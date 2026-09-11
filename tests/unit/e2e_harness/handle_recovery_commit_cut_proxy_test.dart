import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../e2e/handle_recovery_commit_cut_proxy.dart';

void main() {
  test(
    'Commit cut forwards only the exact operation then rejects local WNS',
    () async {
      var calls = 0;
      final proxy = await HandleRecoveryCommitCutProxy.start(
        upstream: Uri.parse('https://awiki.info'),
        operationId: 'test-op',
        handle: 'test-handle',
        client: MockClient((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://awiki.info/user-service/v1/did-auth/rpc',
          );
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': '1',
              'result': {'operation_id': 'test-op'},
              'error': null,
            }),
            200,
          );
        }),
      );
      addTearDown(proxy.close);
      final legacy = await http.post(
        Uri.parse('${proxy.endpoint}/user-service/did-auth/rpc'),
        body: '{}',
      );
      expect(legacy.statusCode, 502);
      expect(calls, 0);
      final response = await http.post(
        Uri.parse('${proxy.endpoint}/user-service/v1/did-auth/rpc'),
        body: jsonEncode({
          'method': 'handle_recovery_commit_v4',
          'params': {
            'intent': {'operation_id': 'test-op'},
          },
        }),
      );
      expect(response.statusCode, 200);
      expect(proxy.committed, isTrue);
      final cut = await http.get(
        Uri.parse('${proxy.endpoint}/.well-known/handle/test-handle'),
      );
      expect(cut.statusCode, 502);
      expect(proxy.localCutObserved, isTrue);
      expect(calls, 1);
      await http.post(
        Uri.parse('${proxy.endpoint}/user-service/v1/did-auth/rpc'),
        body: '{}',
      );
      expect(calls, 1);
    },
  );

  test('Commit cut rejects an unaudited upstream', () async {
    await expectLater(
      HandleRecoveryCommitCutProxy.start(
        upstream: Uri.parse('https://example.invalid'),
        operationId: 'test-op',
        handle: 'test-handle',
      ),
      throwsStateError,
    );
  });
}
