// [INPUT]: Two loopback App-pair clients, checkpoints, and transient SAS values.
// [OUTPUT]: Authenticated phase exchange and secret-free SAS match results.
// [POS]: Contract test for the dual-App E2E coordinator.

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/app_pair_protocol.dart';

void main() {
  test(
    'two isolated roles exchange checkpoints and compare SAS in memory',
    () async {
      final server = await AppPairCoordinatorServer.start(
        token: List<String>.filled(48, 't').join(),
      );
      addTearDown(server.close);
      final admin = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );
      final joiner = AppPairCoordinatorClient(
        endpoint: server.endpoint,
        token: server.token,
      );

      await admin.publish(
        'admin',
        'ready',
        data: const <String, Object?>{
          'did': 'did:wba:awiki.info:alice',
          'handle': 'alice.awiki.info',
          'adminDeviceId': 'admin-device',
        },
      );
      expect(await joiner.waitFor('admin', 'ready'), const <String, Object?>{
        'did': 'did:wba:awiki.info:alice',
        'handle': 'alice.awiki.info',
        'adminDeviceId': 'admin-device',
      });
      await joiner.publish(
        'joiner',
        'pending',
        data: const <String, Object?>{
          'joinSessionId': 'join-session',
          'joinedDeviceId': 'member-device',
        },
      );
      await admin.publish('admin', 'verification_started');
      await joiner.publish(
        'joiner',
        'authorized',
        data: const <String, Object?>{
          'adminDeviceId': 'admin-device',
          'joinedDeviceId': 'member-device',
        },
      );
      await admin.publish('admin', 'complete');

      final results = await Future.wait<bool>(<Future<bool>>[
        admin.submitAndCompareSas('admin', '123456'),
        joiner.submitAndCompareSas('joiner', '123456'),
      ]);
      expect(results, everyElement(isTrue));
    },
  );

  test('checkpoint payload rejects secret-bearing fields', () async {
    final server = await AppPairCoordinatorServer.start(
      token: List<String>.filled(48, 't').join(),
    );
    addTearDown(server.close);
    final client = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );

    await expectLater(
      client.publish(
        'admin',
        'ready',
        data: const <String, Object?>{
          'did': 'did:wba:awiki.info:alice',
          'handle': 'alice.awiki.info',
          'adminDeviceId': 'admin-device',
          'details': <String, Object?>{'sasValue': '123456'},
        },
      ),
      throwsA(isA<AppPairProtocolException>()),
    );
    await expectLater(
      client.publish(
        'admin',
        'verification_started',
        data: const <String, Object?>{'code': '123456'},
      ),
      throwsA(isA<AppPairProtocolException>()),
    );
    await expectLater(
      client.publish('joiner', 'unapproved'),
      throwsA(isA<AppPairProtocolException>()),
    );
  });

  test('mismatched SAS returns only a negative comparison', () async {
    final server = await AppPairCoordinatorServer.start(
      token: List<String>.filled(48, 't').join(),
    );
    addTearDown(server.close);
    final admin = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );
    final joiner = AppPairCoordinatorClient(
      endpoint: server.endpoint,
      token: server.token,
    );

    final results = await Future.wait<bool>(<Future<bool>>[
      admin.submitAndCompareSas('admin', '123456'),
      joiner.submitAndCompareSas('joiner', '654321'),
    ]);
    expect(results, everyElement(isFalse));
  });
}
