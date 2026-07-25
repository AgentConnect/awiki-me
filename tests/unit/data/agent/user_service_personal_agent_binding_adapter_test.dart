import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/data/agent/user_service_personal_agent_binding_adapter.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('writes the canonical Personal Agent endpoint and fields', () async {
    final httpClient = _QueueHttpClient(<http.Response>[
      http.Response(_bindingResponse('personal_agent_did'), 200),
    ]);
    final adapter = _adapter(httpClient);

    final binding = await adapter.ensureBinding(
      userDid: 'did:human:alice',
      daemonAgentDid: 'did:agent:daemon',
      personalAgentDid: 'did:agent:personal',
      runtimeProvider: 'hermes',
      runtimeProfile: const <String, Object?>{'profile': 'personal_agent'},
      delegatedKeyVerificationMethod: 'did:human:alice#daemon-key-1',
    );

    expect(binding.personalAgentDid, 'did:agent:personal');
    expect(httpClient.requests, hasLength(1));
    expect(
      httpClient.requests.single.url.path,
      UserServicePersonalAgentBindingAdapter.endpoint,
    );
    final params = _requestParams(httpClient.requests.single);
    expect(params['personal_agent_did'], 'did:agent:personal');
    expect(params.containsKey('message_agent_did'), isFalse);
    expect((params['runtime_profile'] as Map)['profile'], 'personal_agent');
  });

  test('falls back to the legacy endpoint only when canonical is missing', () async {
    final httpClient = _QueueHttpClient(<http.Response>[
      http.Response('not found', 404),
      http.Response(_bindingResponse('message_agent_did'), 200),
    ]);
    final adapter = _adapter(httpClient);

    final binding = await adapter.ensureBinding(
      userDid: 'did:human:alice',
      daemonAgentDid: 'did:agent:daemon',
      personalAgentDid: 'did:agent:personal',
      runtimeProvider: 'hermes',
      runtimeProfile: const <String, Object?>{'profile': 'personal_agent'},
      delegatedKeyVerificationMethod: 'did:human:alice#daemon-key-1',
    );

    expect(binding.personalAgentDid, 'did:agent:personal');
    expect(
      httpClient.requests.map((request) => request.url.path),
      <String>[
        UserServicePersonalAgentBindingAdapter.endpoint,
        UserServicePersonalAgentBindingAdapter.legacyEndpoint,
      ],
    );
    final legacyParams = _requestParams(httpClient.requests.last);
    expect(legacyParams['message_agent_did'], 'did:agent:personal');
    expect(legacyParams.containsKey('personal_agent_did'), isFalse);
    expect((legacyParams['runtime_profile'] as Map)['profile'], 'message_agent');
  });

  test('does not replay canonical validation errors through legacy API', () async {
    final httpClient = _QueueHttpClient(<http.Response>[
      http.Response(
        '{"jsonrpc":"2.0","error":{"code":-32602,"message":"invalid params"},"id":"req-1"}',
        200,
      ),
    ]);
    final adapter = _adapter(httpClient);

    await expectLater(
      adapter.getActiveBinding(),
      throwsA(
        isA<AwikiOnboardingUtilityError>().having(
          (error) => error.rpcCode,
          'rpcCode',
          -32602,
        ),
      ),
    );
    expect(httpClient.requests, hasLength(1));
  });
}

UserServicePersonalAgentBindingAdapter _adapter(http.Client httpClient) {
  return UserServicePersonalAgentBindingAdapter(
    userServiceUrl: 'https://example.test',
    client: AwikiOnboardingUtilityHttpClient(
      baseUrl: 'https://example.test',
      httpClient: httpClient,
    ),
    bearerTokenProvider: () => 'user-token',
  );
}

String _bindingResponse(String didField) {
  return jsonEncode(<String, Object?>{
    'jsonrpc': '2.0',
    'result': <String, Object?>{
      'binding': <String, Object?>{
        'id': 'binding-1',
        'user_did': 'did:human:alice',
        'daemon_agent_did': 'did:agent:daemon',
        didField: 'did:agent:personal',
        'runtime_provider': 'hermes',
        'runtime_profile': <String, Object?>{'profile': 'personal_agent'},
        'delegated_key_verification_method':
            'did:human:alice#daemon-key-1',
        'status': 'active',
      },
    },
    'id': 'req-1',
  });
}

Map<String, Object?> _requestParams(http.Request request) {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  return (body['params'] as Map).map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

class _QueueHttpClient extends http.BaseClient {
  _QueueHttpClient(this._responses);

  final List<http.Response> _responses;
  final List<http.Request> requests = <http.Request>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final captured = http.Request(request.method, request.url)
      ..headers.addAll(request.headers);
    if (request is http.Request) {
      captured.body = request.body;
    }
    requests.add(captured);
    final response = _responses.removeAt(0);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}
