import 'dart:async';

import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/recovery_read_ack.dart';

const target = AppThreadReadWatermark(
  lastReadMessageId: 'fixture-message',
  lastReadThreadSeq: '7',
);

AppConversationReadCommitResult queued({
  AppThreadReadWatermark? watermark = target,
  List<String> warnings = const [
    'Read watermark is queued behind an in-flight predecessor',
  ],
  bool fallback = false,
}) => AppConversationReadCommitResult(
  updatedCount: 1,
  remoteAcknowledged: false,
  partial: true,
  fallbackUsed: fallback,
  pendingRemoteAck: true,
  effectiveWatermark: watermark,
  warnings: warnings,
);

void main() {
  test('an incomplete target cannot start a read request', () async {
    var calls = 0;
    await expectLater(
      awaitRecoveryFixtureReadAck(
        watermark: const AppThreadReadWatermark(),
        timeout: const Duration(seconds: 1),
        markRead: (_) async {
          calls++;
          return AppConversationReadCommitResult.acknowledged(null);
        },
      ),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test(
    'queued predecessor converges to the exact final ACK with one target',
    () async {
      var calls = 0;
      final result = await awaitRecoveryFixtureReadAck(
        watermark: target,
        timeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 1),
        markRead: (watermark) async {
          expect(identical(watermark, target), isTrue);
          return ++calls < 3
              ? queued()
              : AppConversationReadCommitResult.acknowledged(target);
        },
      );
      expect(calls, 3);
      expect(result.remoteAcknowledged, isTrue);
      expect(result.pendingRemoteAck, isFalse);
    },
  );

  test('an immediate exact ACK is not resubmitted', () async {
    var calls = 0;
    await awaitRecoveryFixtureReadAck(
      watermark: target,
      timeout: const Duration(seconds: 1),
      markRead: (_) async {
        calls++;
        return AppConversationReadCommitResult.acknowledged(target);
      },
    );
    expect(calls, 1);
  });

  test(
    'wrong targets, fallback and other partial errors remain terminal',
    () async {
      for (final result in [
        queued(watermark: null),
        queued(
          watermark: const AppThreadReadWatermark(
            lastReadMessageId: 'other',
            lastReadThreadSeq: '7',
          ),
        ),
        queued(
          watermark: const AppThreadReadWatermark(
            lastReadMessageId: 'fixture-message',
            lastReadThreadSeq: '8',
          ),
        ),
        queued(fallback: true),
        queued(
          warnings: const [
            'Remote read-state mark-read failed: private-server-body',
          ],
        ),
        queued(
          warnings: const [
            'Read watermark is queued behind an in-flight predecessor',
            'private-extra-warning',
          ],
        ),
        AppConversationReadCommitResult.acknowledged(
          const AppThreadReadWatermark(
            lastReadMessageId: 'other',
            lastReadThreadSeq: '7',
          ),
        ),
      ]) {
        var calls = 0;
        await expectLater(
          awaitRecoveryFixtureReadAck(
            watermark: target,
            timeout: const Duration(seconds: 1),
            markRead: (_) async {
              calls++;
              return result;
            },
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'closed diagnostic',
              isNot(contains('private-')),
            ),
          ),
        );
        expect(calls, 1);
      }
    },
  );

  test(
    'a predecessor that never converges fails within the same deadline',
    () async {
      await expectLater(
        awaitRecoveryFixtureReadAck(
          watermark: target,
          timeout: const Duration(milliseconds: 20),
          pollInterval: const Duration(milliseconds: 1),
          markRead: (_) async => queued(),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('a stalled call and a thrown transport error are not retried', () async {
    var calls = 0;
    await expectLater(
      awaitRecoveryFixtureReadAck(
        watermark: target,
        timeout: const Duration(milliseconds: 10),
        markRead: (_) {
          calls++;
          return Completer<AppConversationReadCommitResult>().future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
    calls = 0;
    await expectLater(
      awaitRecoveryFixtureReadAck(
        watermark: target,
        timeout: const Duration(seconds: 1),
        markRead: (_) async {
          calls++;
          throw StateError('transport-failed');
        },
      ),
      throwsA(isA<StateError>()),
    );
    expect(calls, 1);
  });
}
