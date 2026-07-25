import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/auth/auth_session_coordinator.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/data/services/authenticated_user_service_rpc_client.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retries once with refreshed token after 401', () async {
    final sessions = _FakeSessions(
      current: _session(jwtToken: 'expired-token'),
      refreshed: _session(jwtToken: 'fresh-token'),
    );
    final httpClient = _QueueHttpClient([
      http.Response(
        '{"jsonrpc":"2.0","result":null,"error":{"code":-32000,"message":"Missing or invalid Authorization header","data":null},"id":"req-1"}',
        401,
      ),
      http.Response(
        '{"jsonrpc":"2.0","result":{"agents":[]},"id":"req-1"}',
        200,
      ),
    ]);
    var publishedRefreshes = 0;
    final client = AuthenticatedUserServiceRpcClient(
      client: AwikiOnboardingUtilityHttpClient(
        baseUrl: 'https://example.test',
        httpClient: httpClient,
      ),
      sessions: AuthSessionCoordinator(
        sessions: sessions,
        onSessionUpdated: (_) => publishedRefreshes += 1,
      ),
    );

    final result = await client.rpcCall(
      path: '/user-service/agent-inventory/rpc',
      method: 'list_agents',
      params: const <String, Object?>{'include_inactive': false},
    );

    expect(result['agents'], isEmpty);
    expect(sessions.refreshCount, 1);
    expect(httpClient.requests, hasLength(2));
    expect(
      httpClient.requests[0].headers['Authorization'],
      'Bearer expired-token',
    );
    expect(
      httpClient.requests[1].headers['Authorization'],
      'Bearer fresh-token',
    );
    expect(publishedRefreshes, 1);
  });

  test(
    'refreshes before request when local token is already expired',
    () async {
      final expiredJwt = _unsignedJwt(exp: 946684800);
      final sessions = _FakeSessions(
        current: _session(jwtToken: expiredJwt),
        refreshed: _session(jwtToken: 'fresh-token'),
      );
      final httpClient = _QueueHttpClient([
        http.Response(
          '{"jsonrpc":"2.0","result":{"token":"install-token"},"id":"req-1"}',
          200,
        ),
      ]);
      final client = AuthenticatedUserServiceRpcClient(
        client: AwikiOnboardingUtilityHttpClient(
          baseUrl: 'https://example.test',
          httpClient: httpClient,
        ),
        sessions: AuthSessionCoordinator(
          sessions: sessions,
          now: () => DateTime.utc(2026, 6, 8),
        ),
      );

      final result = await client.rpcCall(
        path: '/user-service/agent-registration/rpc',
        method: 'issue_token',
        params: const <String, Object?>{'agent_kind': 'daemon'},
      );

      expect(result['token'], 'install-token');
      expect(sessions.refreshCount, 1);
      expect(httpClient.requests, hasLength(1));
      expect(
        httpClient.requests.single.headers['Authorization'],
        'Bearer fresh-token',
      );
    },
  );

  test('propagates non-auth RPC errors without refreshing token', () async {
    final sessions = _FakeSessions(
      current: _session(jwtToken: 'valid-token'),
      refreshed: _session(jwtToken: 'fresh-token'),
    );
    final httpClient = _QueueHttpClient([
      http.Response(
        '{"jsonrpc":"2.0","error":{"code":-32602,"message":"invalid params"},"id":"req-1"}',
        200,
      ),
    ]);
    final client = AuthenticatedUserServiceRpcClient(
      client: AwikiOnboardingUtilityHttpClient(
        baseUrl: 'https://example.test',
        httpClient: httpClient,
      ),
      sessions: AuthSessionCoordinator(sessions: sessions),
    );

    await expectLater(
      client.rpcCall(
        path: '/user-service/agent-inventory/rpc',
        method: 'list_agents',
        params: const <String, Object?>{'include_inactive': false},
      ),
      throwsA(
        isA<AwikiOnboardingUtilityError>().having(
          (error) => error.message,
          'message',
          'invalid params',
        ),
      ),
    );

    expect(sessions.refreshCount, 0);
    expect(httpClient.requests, hasLength(1));
    expect(
      httpClient.requests.single.headers['Authorization'],
      'Bearer valid-token',
    );
  });

  test('does not retry an old RPC with a replacement session token', () async {
    final refreshResult = Completer<AppSession?>();
    final sessions = _FakeSessions(
      current: _session(jwtToken: 'identity-a-token'),
      refreshed: _session(jwtToken: 'identity-a-refreshed-token'),
      refreshCompleter: refreshResult,
    );
    final httpClient = _QueueHttpClient([
      http.Response(
        '{"jsonrpc":"2.0","result":null,"error":{"code":-32000,"message":"Missing or invalid Authorization header","data":null},"id":"req-1"}',
        401,
      ),
    ]);
    var publishedRefreshes = 0;
    final client = AuthenticatedUserServiceRpcClient(
      client: AwikiOnboardingUtilityHttpClient(
        baseUrl: 'https://example.test',
        httpClient: httpClient,
      ),
      sessions: AuthSessionCoordinator(
        sessions: sessions,
        onSessionUpdated: (_) => publishedRefreshes += 1,
      ),
    );

    final request = client.rpcCall(
      path: '/user-service/agent-inventory/rpc',
      method: 'list_agents',
      params: const <String, Object?>{'include_inactive': false},
    );
    await pumpEventQueue();
    expect(sessions.refreshCount, 1);

    sessions.replaceCommittedSession(
      _session(jwtToken: 'same-identity-new-login-token'),
    );
    refreshResult.complete(_session(jwtToken: 'identity-a-refreshed-token'));

    await expectLater(
      request,
      throwsA(
        isA<AuthSessionUnavailable>().having(
          (error) => error.message,
          'message',
          'auth_session_changed',
        ),
      ),
    );
    expect(httpClient.requests, hasLength(1));
    expect(publishedRefreshes, 0);
  });
}

class _QueueHttpClient extends http.BaseClient {
  _QueueHttpClient(this._responses);

  final List<http.Response> _responses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (_responses.isEmpty) {
      throw StateError(
        'No queued response for ${request.method} ${request.url}',
      );
    }
    final response = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

class _FakeSessions
    with AppSessionTransitionGuard
    implements AppSessionService {
  _FakeSessions({
    required AppSession current,
    required AppSession refreshed,
    this.refreshCompleter,
  }) : _current = current,
       _refreshed = refreshed;

  AppSession? _current;
  final AppSession _refreshed;
  final Completer<AppSession?>? refreshCompleter;
  int refreshCount = 0;

  @override
  Future<AppSession> activateIdentity(
    AppSession identity, {
    AppSessionTransition? transition,
    Future<void> Function(AppSession session)? initializeIdentitySession,
  }) async {
    final requestedTransition = transition ?? beginSessionTransition();
    if (!isSessionTransitionCurrent(requestedTransition)) {
      throw const AppSessionTransitionSuperseded();
    }
    await initializeIdentitySession?.call(identity);
    _current = identity;
    markSessionTransitionCommitted(requestedTransition);
    return identity;
  }

  @override
  Future<AppSession?> currentSession() async => _current;

  @override
  Future<AppSessionLease?> currentSessionLease() async =>
      sessionLeaseFor(_current);

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async =>
      _current ?? _session(jwtToken: null);

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    if (_current != null) _current!,
  ];

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) async => _current ?? _session(jwtToken: null);

  @override
  Future<void> logout() async {
    _current = null;
  }

  @override
  Future<AppSession?> refreshSession() async {
    refreshCount += 1;
    final completer = refreshCompleter;
    if (completer != null) {
      return completer.future;
    }
    _current = _refreshed;
    return _current;
  }

  void replaceCommittedSession(AppSession session) {
    final transition = beginSessionTransition();
    _current = session;
    markSessionTransitionCommitted(transition);
  }

  @override
  Future<AppSession?> restoreSession() async => _current;
}

AppSession _session({required String? jwtToken}) {
  return AppSession(
    did: 'did:wba:example.test:user:alice:e1_123',
    identityId: 'alice-id',
    displayName: 'Alice',
    handle: 'alice.example.test',
    localAlias: 'alice',
    authenticated: jwtToken != null,
    jwtToken: jwtToken,
  );
}

String _unsignedJwt({required int exp}) {
  final header = base64Url.encode(
    utf8.encode(jsonEncode(<String, Object?>{'alg': 'none', 'typ': 'JWT'})),
  );
  final payload = base64Url.encode(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'sub': 'did:wba:example.test:user:alice:e1_123',
        'exp': exp,
      }),
    ),
  );
  return '$header.$payload.signature';
}
