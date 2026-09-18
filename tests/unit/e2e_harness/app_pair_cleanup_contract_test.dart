import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/app_pair_cleanup_contract.dart';
import '../../e2e/app_pair_protocol.dart';

void main() {
  test('cleanup requires the approved App-pair handle namespace', () {
    expect(() => validateAppPairCleanupHandlePrefix('appmd'), returnsNormally);
    for (final prefix in <String>[
      'app0123456789ab',
      'appmd0123',
      'systestmd',
      'custom',
    ]) {
      expect(
        () => validateAppPairCleanupHandlePrefix(prefix),
        throwsFormatException,
      );
    }
  });

  test('cleanup readiness requires the exact read-only operator receipt', () {
    final receipt = {
      'schemaVersion': 1,
      'service': 'message-service',
      'action': 'system_test_app_scope_cleanup_preflight',
      'ready': true,
      'code': 'ready',
    };
    validateAppPairCleanupPreflight(jsonEncode(receipt));
    expect(
      () => validateAppPairCleanupPreflight(
        jsonEncode({...receipt, 'ready': false}),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          validateAppPairCleanupPreflight(jsonEncode({...receipt, 'extra': 1})),
      throwsFormatException,
    );
  });
  test(
    'cleanup command retains reviewed host and sends selectors only on stdin',
    () {
      final command = appPairMessageCleanupCommand('ali');
      expect(command.take(3), ['ssh', 'ali', '--']);
      expect(
        command,
        contains(
          '/opt/awiki/services/message-service/current/scripts/cleanup_system_test_scope.py',
        ),
      );
      expect(command, isNot(contains('account-1')));
      expect(jsonDecode(appPairCleanupRequest(['account-1'])), {
        'action': 'cleanup_test_app_scope',
        'account_ids': ['account-1'],
      });
      expect(() => appPairMessageCleanupCommand('other'), throwsArgumentError);
      for (final value in ['', 'account\nother', '*', 'a;command']) {
        expect(() => appPairCleanupRequest([value]), throwsFormatException);
      }
    },
  );

  Map<String, Object?> receipt() => {
    'schemaVersion': 1,
    'service': 'message-service',
    'action': 'system_test_app_scope_cleanup',
    'scopeFingerprint': appPairCleanupFingerprint(['account-1']),
    'authorizedAccountCount': 1,
    'deletedCounts': {
      'account': 1,
      'attachment': 0,
      'direct': 2,
      'group': 0,
      'outbox': 0,
      'sync': 2,
    },
    'residualCount': 0,
    'cleaned': true,
  };

  test(
    'only exact-scope zero-residual receipt is recorded as message cleaned',
    () {
      final result = validateAppPairCleanupReceipt(
        jsonEncode(receipt()),
        accountIds: ['account-1'],
      );
      expect(result['status'], 'cleaned');
      expect(jsonEncode(result), isNot(contains('account-1')));
      for (final change in <Map<String, Object?>>[
        {
          'scopeFingerprint': appPairCleanupFingerprint(['other']),
        },
        {'residualCount': 1},
        {'cleaned': false},
        {'authorizedAccountCount': 2},
        {'service': 'user-service'},
        {'extra': true},
        {
          'deletedCounts': {'direct': -1},
        },
      ]) {
        expect(
          () => validateAppPairCleanupReceipt(
            jsonEncode({...receipt(), ...change}),
            accountIds: ['account-1'],
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'coordinator retains one immutable admin scope only in memory',
    () async {
      final server = await AppPairCoordinatorServer.start(token: 't' * 48);
      addTearDown(server.close);
      final client = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );
      expect(server.cleanupAccountIds, isEmpty);
      await client.publish(
        'admin',
        'cleanup_scope',
        data: {'accountId': 'account-1'},
      );
      expect(server.cleanupAccountIds, ['account-1']);
      await expectLater(
        client.publish(
          'admin',
          'cleanup_scope',
          data: {'accountId': 'account-2'},
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
      await expectLater(
        client.publish(
          'joiner',
          'cleanup_scope',
          data: {'accountId': 'account-2'},
        ),
        throwsA(isA<AppPairProtocolException>()),
      );
      expect(server.cleanupAccountIds, ['account-1']);
      await client.publish(
        'admin',
        'cleanup_peer',
        data: {'accountId': 'peer-1'},
      );
      expect(server.cleanupAccountIds, ['account-1', 'peer-1']);
      expect(
        appPairCleanupFingerprint(['peer-1', 'account-1']),
        appPairCleanupFingerprint(['account-1', 'peer-1']),
      );
      expect(
        () => appPairCleanupRequest(['account-1', 'account-1']),
        throwsFormatException,
      );
      expect(
        () => appPairCleanupRequest(['a', 'b', 'c']),
        throwsFormatException,
      );
    },
  );
}
