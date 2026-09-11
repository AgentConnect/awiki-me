import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/sms_otp_cooldown_service.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _BlockingOtp extends FakeOnboardingSupportService {
  _BlockingOtp(super.gateway);
  final started = Completer<void>();
  final result = Completer<RegistrationOtpSendReceipt>();
  @override
  Future<RegistrationOtpSendReceipt> sendRegistrationOtp({
    required String phone,
    required String handle,
    required String domain,
    required String fullHandle,
  }) {
    started.complete();
    return result.future;
  }
}

void main() {
  for (final blockRestore in [true, false]) {
    test(
      'controller disposal during cooldown ${blockRestore ? "restore" : "persistence"} is safe',
      () async {
        final gateway = FakeAwikiGateway();
        final support = _BlockingOtp(gateway);
        final storage = _BlockingCooldown(blockRestore: blockRestore);
        final container = ProviderContainer(
          overrides: [
            onboardingSupportServiceProvider.overrideWithValue(support),
            smsOtpCooldownServiceProvider.overrideWithValue(storage),
            appSessionServiceProvider.overrideWithValue(
              FakeAppSessionService(gateway),
            ),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(onboardingProvider.notifier);
        await controller.loadServerInfo();
        final request = controller.requestOtp(
          phone: '13800138000',
          handle: 'alice',
          handleDomain: 'awiki.ai',
        );
        final retryAt = DateTime.now().toUtc().add(const Duration(seconds: 60));
        if (blockRestore) {
          await storage.started.future;
        } else {
          await support.started.future;
          support.result.complete(
            RegistrationOtpSendReceipt(retryAfterSeconds: 60, retryAt: retryAt),
          );
          await storage.started.future;
        }
        container.invalidate(onboardingProvider);
        storage.release.complete();
        await request;
        expect(container.read(onboardingProvider).otpTargetFullHandle, isNull);
        expect(container.read(uiFeedbackProvider), isNull);
        expect(container.read(smsOtpCooldownProvider).isSending, isFalse);
        if (blockRestore) {
          expect(support.started.isCompleted, isFalse);
          expect(container.read(smsOtpCooldownProvider).canSend, isTrue);
        } else {
          expect(container.read(smsOtpCooldownProvider).retryAt, retryAt);
        }
      },
    );
  }
  for (final rateLimited in [false, true]) {
    for (final disposeContainer in [false, true]) {
      test(
        'OTP ${rateLimited ? "rate limit" : "success"} after ${disposeContainer ? "container disposal" : "controller replacement"} finishes safely',
        () async {
          final gateway = FakeAwikiGateway();
          final support = _BlockingOtp(gateway);
          final container = ProviderContainer(
            overrides: [
              onboardingSupportServiceProvider.overrideWithValue(support),
              appSessionServiceProvider.overrideWithValue(
                FakeAppSessionService(gateway),
              ),
            ],
          );
          if (!disposeContainer) addTearDown(container.dispose);
          final controller = container.read(onboardingProvider.notifier);
          await controller.loadServerInfo();
          final request = controller.requestOtp(
            phone: '13800138000',
            handle: 'alice',
            handleDomain: 'awiki.ai',
          );
          await support.started.future;
          if (disposeContainer) {
            container.dispose();
          } else {
            container.invalidate(onboardingProvider);
          }
          final retryAt = DateTime.now().toUtc().add(
            const Duration(seconds: 60),
          );
          if (rateLimited) {
            support.result.completeError(
              RegistrationOtpRateLimited(
                retryAfterSeconds: 60,
                retryAt: retryAt,
              ),
            );
          } else {
            support.result.complete(
              RegistrationOtpSendReceipt(
                retryAfterSeconds: 60,
                retryAt: retryAt,
              ),
            );
          }
          await request;
          if (!disposeContainer) {
            expect(
              container.read(onboardingProvider).otpTargetFullHandle,
              isNull,
            );
            expect(container.read(uiFeedbackProvider), isNull);
            final cooldown = container.read(smsOtpCooldownProvider);
            expect(cooldown.retryAt, retryAt);
            expect(cooldown.isSending, isFalse);
            expect(cooldown.canSend, isFalse);
          }
        },
      );
    }
  }
}

class _BlockingCooldown extends NoopSmsOtpCooldownService {
  _BlockingCooldown({required this.blockRestore});
  final bool blockRestore;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<DateTime?> loadRetryAt({
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {
    if (blockRestore) {
      started.complete();
      await release.future;
    }
    return null;
  }

  @override
  Future<void> saveRetryAt(
    DateTime retryAt, {
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {
    if (!blockRestore) {
      started.complete();
      await release.future;
    }
  }
}
