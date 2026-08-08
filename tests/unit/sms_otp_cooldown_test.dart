import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/sms_otp_cooldown_service.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/key_value_sms_otp_cooldown_service.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeyValueSmsOtpCooldownService', () {
    test('persists only a UTC boundary and isolates tenant scopes', () async {
      final storage = _MemoryStore();
      final first = KeyValueSmsOtpCooldownService(
        storage: storage,
        scopeId: 'tenant-awiki-ai',
      );
      final second = KeyValueSmsOtpCooldownService(
        storage: storage,
        scopeId: 'tenant-anpclaw-com',
      );
      final firstBoundary = DateTime(2026, 8, 6, 12, 1, 2);
      final secondBoundary = DateTime.utc(2026, 8, 6, 13, 2, 3);

      await first.saveRetryAt(firstBoundary);
      expect(await second.loadRetryAt(), isNull);
      await second.saveRetryAt(secondBoundary);

      expect(storage.values, hasLength(2));
      expect(
        storage.values.values,
        containsAll(<String>[
          firstBoundary.toUtc().toIso8601String(),
          secondBoundary.toIso8601String(),
        ]),
      );
      expect(
        storage.values.values.every((value) => value.endsWith('Z')),
        isTrue,
      );
      expect(
        storage.values.entries.every(
          (entry) =>
              !entry.key.contains('phone') &&
              !entry.value.contains('phone') &&
              !entry.value.contains('handle'),
        ),
        isTrue,
      );
      expect(await first.loadRetryAt(), firstBoundary.toUtc());
      expect(await second.loadRetryAt(), secondBoundary);
    });

    test(
      'isolates Handle Recovery from registration and Join cooldown',
      () async {
        final storage = _MemoryStore();
        final service = KeyValueSmsOtpCooldownService(
          storage: storage,
          scopeId: 'tenant-awiki-ai',
        );
        final registrationBoundary = DateTime.utc(2026, 8, 8, 9, 1);
        final recoveryBoundary = DateTime.utc(2026, 8, 8, 9, 2);

        await service.saveRetryAt(registrationBoundary);
        await service.saveRetryAt(
          recoveryBoundary,
          purpose: SmsOtpCooldownPurpose.handleRecovery,
        );

        expect(await service.loadRetryAt(), registrationBoundary);
        expect(
          await service.loadRetryAt(
            purpose: SmsOtpCooldownPurpose.handleRecovery,
          ),
          recoveryBoundary,
        );
      },
    );

    test('deletes malformed and non-UTC persisted values', () async {
      final storage = _MemoryStore();
      final service = KeyValueSmsOtpCooldownService(
        storage: storage,
        scopeId: 'tenant-awiki-ai',
      );
      await service.saveRetryAt(DateTime.utc(2026, 8, 6, 12, 1));
      final key = storage.values.keys.single;

      for (final invalid in <String>[
        'not-a-timestamp',
        '2026-08-06T12:01:00',
        '2026-08-06T12:01:00+00:00',
      ]) {
        storage.values[key] = invalid;
        expect(await service.loadRetryAt(), isNull);
        expect(storage.values, isEmpty);
      }
    });
  });

  group('SmsOtpCooldownController', () {
    test(
      'restores one persisted boundary after controller recreation',
      () async {
        final now = DateTime.utc(2026, 8, 6, 12);
        final service = _MemoryCooldownService(
          retryAt: now.add(const Duration(seconds: 45)),
        );

        final firstContainer = _cooldownContainer(service: service, now: now);
        final first = firstContainer.read(smsOtpCooldownProvider.notifier);
        expect(await first.beginSend(), isFalse);
        expect(firstContainer.read(smsOtpCooldownProvider).isReady, isTrue);
        expect(
          firstContainer.read(smsOtpCooldownProvider).remainingSeconds,
          45,
        );
        firstContainer.dispose();

        final restartedContainer = _cooldownContainer(
          service: service,
          now: now,
        );
        final restarted = restartedContainer.read(
          smsOtpCooldownProvider.notifier,
        );
        expect(await restarted.beginSend(), isFalse);
        expect(
          restartedContainer.read(smsOtpCooldownProvider).remainingSeconds,
          45,
        );
        restartedContainer.dispose();
      },
    );

    test(
      'blocks sends until restoration finishes and serializes callers',
      () async {
        final now = DateTime.utc(2026, 8, 6, 12);
        final pendingLoad = Completer<DateTime?>();
        final service = _MemoryCooldownService(loadResult: pendingLoad.future);
        final container = _cooldownContainer(service: service, now: now);
        final controller = container.read(smsOtpCooldownProvider.notifier);

        final first = controller.beginSend();
        final second = controller.beginSend();
        expect(container.read(smsOtpCooldownProvider).canSend, isFalse);
        pendingLoad.complete(null);

        expect(await Future.wait(<Future<bool>>[first, second]), <bool>[
          true,
          false,
        ]);
        expect(container.read(smsOtpCooldownProvider).isSending, isTrue);
        controller.completeFailed();
        container.dispose();
      },
    );

    test(
      'expired and implausibly distant values cannot block sending',
      () async {
        final now = DateTime.utc(2026, 8, 6, 12);
        for (final invalidBoundary in <DateTime>[
          now.subtract(const Duration(seconds: 1)),
          now.add(const Duration(seconds: 3601)),
        ]) {
          final service = _MemoryCooldownService(retryAt: invalidBoundary);
          final container = _cooldownContainer(service: service, now: now);
          final controller = container.read(smsOtpCooldownProvider.notifier);

          expect(await controller.beginSend(), isTrue);
          await Future<void>.delayed(Duration.zero);
          expect(service.clearCalls, 1);
          controller.completeFailed();
          container.dispose();
        }
      },
    );

    test(
      'a shorter late boundary never shortens the active cooldown',
      () async {
        final now = DateTime.utc(2026, 8, 6, 12);
        final service = _MemoryCooldownService();
        final container = _cooldownContainer(service: service, now: now);
        final controller = container.read(smsOtpCooldownProvider.notifier);

        expect(await controller.beginSend(), isTrue);
        await controller.completeAcceptedAfter(90);
        await controller.completeRateLimitedAfter(20);

        expect(container.read(smsOtpCooldownProvider).remainingSeconds, 90);
        expect(service.retryAt, now.add(const Duration(seconds: 90)));
        container.dispose();
      },
    );

    test(
      'persistence failure keeps the process-local cooldown active',
      () async {
        final now = DateTime.utc(2026, 8, 6, 12);
        final service = _MemoryCooldownService(failSave: true);
        final container = _cooldownContainer(service: service, now: now);
        final controller = container.read(smsOtpCooldownProvider.notifier);

        expect(await controller.beginSend(), isTrue);
        await controller.completeAcceptedAfter(60);

        expect(container.read(smsOtpCooldownProvider).remainingSeconds, 60);
        expect(container.read(smsOtpCooldownProvider).canSend, isFalse);
        expect(await controller.beginSend(), isFalse);
        container.dispose();
      },
    );
  });
}

ProviderContainer _cooldownContainer({
  required SmsOtpCooldownService service,
  required DateTime now,
}) {
  return ProviderContainer(
    overrides: <Override>[
      smsOtpCooldownServiceProvider.overrideWithValue(service),
      smsOtpCooldownClockProvider.overrideWithValue(() => now),
    ],
  );
}

final class _MemoryStore implements AppKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

final class _MemoryCooldownService implements SmsOtpCooldownService {
  _MemoryCooldownService({
    this.retryAt,
    Future<DateTime?>? loadResult,
    this.failSave = false,
  }) : _loadResult = loadResult;

  DateTime? retryAt;
  final Future<DateTime?>? _loadResult;
  final bool failSave;
  int clearCalls = 0;

  @override
  Future<void> clearRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {
    clearCalls += 1;
    retryAt = null;
  }

  @override
  Future<DateTime?> loadRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async => _loadResult == null ? retryAt : await _loadResult;

  @override
  Future<void> saveRetryAt(
    DateTime value, {
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {
    if (failSave) throw StateError('storage unavailable');
    retryAt = value;
  }
}
