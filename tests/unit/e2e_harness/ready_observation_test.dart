import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/ready_observation.dart';

void main() {
  test(
    'returns the observed completion when a new sync begins before await resumes',
    () async {
      var current = 'ready';
      final observed = waitForE2eObservation(
        read: () {
          final value = current;
          scheduleMicrotask(() => current = 'syncing');
          return value;
        },
        ready: (value) => value == 'ready',
        pump: () async {},
        timeout: const Duration(seconds: 1),
      );
      expect(await observed, 'ready');
      expect(current, 'syncing');
    },
  );
  test('pumps until the same observation satisfies readiness', () async {
    var current = 0;
    expect(
      await waitForE2eObservation(
        read: () => current,
        ready: (value) => value == 2,
        pump: () async {
          current++;
        },
        timeout: const Duration(seconds: 1),
      ),
      2,
    );
  });
  test('does not accept an incomplete observation at timeout', () async {
    await expectLater(
      waitForE2eObservation(
        read: () => false,
        ready: (value) => value,
        pump: () async {},
        timeout: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}
