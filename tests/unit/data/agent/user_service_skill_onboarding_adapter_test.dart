import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/data/agent/user_service_skill_onboarding_adapter.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'issueSkillToken sends the v1 allowlisted request and parses scope',
    () async {
      final httpClient = _CapturingHttpClient();
      final adapter = UserServiceSkillOnboardingAdapter(
        userServiceUrl: 'https://awiki.info',
        client: AwikiOnboardingUtilityHttpClient(
          baseUrl: 'https://awiki.info',
          httpClient: httpClient,
        ),
        bearerTokenProvider: () => 'user-session-token',
      );

      final grant = await adapter.issueSkillToken(
        controllerDid: 'did:wba:awiki.info:user:alice',
        controllerHandle: '@Alice.AWIKI.INFO',
        clientPlatform: 'android',
      );

      expect(grant.token, 'awsk1_adapter_secret_value');
      expect(grant.agentHandle, 'skill-test.awiki.info');
      expect(grant.serviceOrigin, 'https://awiki.info');
      expect(grant.toString(), isNot(contains('awsk1_adapter_secret_value')));
      expect(httpClient.requests, hasLength(1));
      expect(
        httpClient.requests.single.url.path,
        '/user-service/agent-registration/rpc',
      );
      expect(
        httpClient.requests.single.headers['authorization'],
        'Bearer user-session-token',
      );
      final body = jsonDecode(httpClient.requests.single.body) as Map;
      expect(body['method'], 'issue_token');
      final params = body['params'] as Map;
      expect(params['agent_kind'], 'skill');
      expect(params['controller_did'], 'did:wba:awiki.info:user:alice');
      expect(params['controller_handle'], 'alice.awiki.info');
      expect(params['one_time'], true);
      expect(params.containsKey('controller_user_id'), isFalse);
      expect(params.containsKey('handle'), isFalse);
      expect(params.containsKey('expires_in_seconds'), isFalse);
      expect(params['metadata'], <String, Object?>{
        'client': 'awiki-me',
        'client_platform': 'android',
        'onboarding_version': 1,
      });
    },
  );
}

class _CapturingHttpClient extends http.BaseClient {
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final captured = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      captured.body = request.body;
    }
    requests.add(captured);
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable(<List<int>>[
        utf8.encode(
          '{"jsonrpc":"2.0","result":{'
          '"token":"awsk1_adapter_secret_value",'
          '"token_id":"agtok_skill_1",'
          '"controller_full_handle":"alice.awiki.info",'
          '"handle":"skill-test.awiki.info",'
          '"expires_at":"2026-07-21T12:30:00Z",'
          '"scope":{"service_origin":"https://awiki.info"}'
          '},"id":"req-1"}',
        ),
      ]),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
