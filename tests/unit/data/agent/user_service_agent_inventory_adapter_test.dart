import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/data/agent/user_service_agent_inventory_adapter.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'issueDaemonToken sends controller_handle without daemon handle',
    () async {
      final httpClient = _CapturingHttpClient();
      final adapter = UserServiceAgentInventoryAdapter(
        userServiceUrl: 'https://example.test',
        client: AwikiOnboardingUtilityHttpClient(
          baseUrl: 'https://example.test',
          httpClient: httpClient,
        ),
        bearerTokenProvider: () => 'user-token',
      );

      final token = await adapter.issueDaemonToken(
        controllerDid: 'did:human:alice',
        controllerHandle: '@Alice.Anpclaw.com',
        clientPlatform: 'macos',
      );

      expect(token.token, 'daemon-token');
      expect(httpClient.requests, hasLength(1));
      final body = jsonDecode(httpClient.requests.single.body) as Map;
      expect(body['method'], 'issue_token');
      final params = body['params'] as Map;
      expect(params['agent_kind'], 'daemon');
      expect(params['controller_did'], 'did:human:alice');
      expect(params['controller_handle'], 'alice.anpclaw.com');
      expect(params.containsKey('handle'), isFalse);
    },
  );

  test('issueDaemonToken rejects empty controller handle locally', () async {
    final httpClient = _CapturingHttpClient();
    final adapter = UserServiceAgentInventoryAdapter(
      userServiceUrl: 'https://example.test',
      client: AwikiOnboardingUtilityHttpClient(
        baseUrl: 'https://example.test',
        httpClient: httpClient,
      ),
      bearerTokenProvider: () => 'user-token',
    );

    expect(
      () => adapter.issueDaemonToken(
        controllerDid: 'did:human:alice',
        controllerHandle: ' @ ',
        clientPlatform: 'macos',
      ),
      throwsArgumentError,
    );
    expect(httpClient.requests, isEmpty);
  });
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
          '{"jsonrpc":"2.0","result":{"token":"daemon-token","token_id":"agtok_1"},"id":"req-1"}',
        ),
      ]),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}
