import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../e2e/handle_recovery_commit_cut_proxy.dart';

void main() {
  for (final domain in ['awiki.info', 'anpclaw.com', 'test-fix.anpclaw.com']) {
    test(
      'Commit cut on $domain forwards the exact operation then rejects local WNS',
      () async {
        var calls = 0;
        final proxy = await HandleRecoveryCommitCutProxy.start(
          upstream: Uri.parse('https://$domain'),
          operationId: 'test-op',
          handle: 'test-handle',
          client: MockClient((request) async {
            calls++;
            expect(
              request.url.toString(),
              'https://$domain/user-service/v1/did-auth/rpc',
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
        final wrongOperation = await http.post(
          Uri.parse('${proxy.endpoint}/user-service/v1/did-auth/rpc'),
          body: jsonEncode({
            'method': 'handle_recovery_commit_v4',
            'params': {
              'intent': {'operation_id': 'another-operation'},
            },
          }),
        );
        expect(wrongOperation.statusCode, 502);
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
  }

  test('Commit cut rejects an unaudited upstream', () async {
    for (final url in [
      'https://example.invalid',
      'https://test-fix-b.anpclaw.com',
      'http://test-fix.anpclaw.com',
      'https://test-fix.anpclaw.com:8443',
      'https://anpclaw.com:8443',
      'https://test-fix.anpclaw.com/unreviewed-path',
      'https://user:password@test-fix.anpclaw.com',
      'https://test-fix.anpclaw.com?redirect=elsewhere',
      'https://test-fix.anpclaw.com#fragment',
    ]) {
      await expectLater(
        HandleRecoveryCommitCutProxy.start(
          upstream: Uri.parse(url),
          operationId: 'test-op',
          handle: 'test-handle',
        ),
        throwsStateError,
      );
    }
  });
}
