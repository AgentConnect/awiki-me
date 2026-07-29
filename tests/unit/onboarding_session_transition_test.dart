import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/legacy_identity_upgrade_port.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test(
    'timed out onboarding cannot activate after its transition is cancelled',
    () async {
      final gateway = FakeAwikiGateway();
      final sessions = FakeAppSessionService(gateway);
      final onboarding = _BlockingOnboardingService();
      final container = ProviderContainer(
        overrides: <Override>[
          appSessionServiceProvider.overrideWithValue(sessions),
          onboardingServiceProvider.overrideWithValue(onboarding),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          onboardingProvider.overrideWith(
            (ref) => OnboardingController(
              ref,
              requestTimeout: const Duration(milliseconds: 20),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(onboardingProvider.notifier);
      await controller.loadServerInfo();
      await controller.requestOtp(
        phone: '13800138000',
        handle: 'alice',
        handleDomain: 'awiki.ai',
      );

      final request = controller.registerWithPhone(
        phone: '13800138000',
        otp: '123456',
        handle: 'alice',
        handleDomain: 'awiki.ai',
        nickName: 'Alice',
        profileMarkdown: '# Alice',
      );
      final transition = await onboarding.started.future;
      expect(sessions.isSessionTransitionCurrent(transition), isTrue);

      await request;
      expect(container.read(onboardingProvider).isBusy, isFalse);
      expect(sessions.isSessionTransitionCurrent(transition), isFalse);

      onboarding.complete(
        const AppSession(
          did: 'did:wba:awiki.ai:user:alice:e1_late',
          identityId: 'late-id',
          displayName: 'Alice',
          handle: 'alice.awiki.ai',
          localAlias: 'alice',
        ),
      );
      await pumpEventQueue();

      expect(await sessions.currentSession(), isNull);
    },
  );

  test(
    'disposing onboarding cancels its in-flight session transition',
    () async {
      final gateway = FakeAwikiGateway();
      final sessions = FakeAppSessionService(gateway);
      final onboarding = _BlockingOnboardingService();
      final container = ProviderContainer(
        overrides: <Override>[
          appSessionServiceProvider.overrideWithValue(sessions),
          onboardingServiceProvider.overrideWithValue(onboarding),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
        ],
      );
      final controller = container.read(onboardingProvider.notifier);
      await controller.loadServerInfo();
      await controller.requestOtp(
        phone: '13800138000',
        handle: 'alice',
        handleDomain: 'awiki.ai',
      );

      final request = controller.registerWithPhone(
        phone: '13800138000',
        otp: '123456',
        handle: 'alice',
        handleDomain: 'awiki.ai',
        nickName: 'Alice',
        profileMarkdown: '# Alice',
      );
      final transition = await onboarding.started.future;
      container.dispose();
      expect(sessions.isSessionTransitionCurrent(transition), isFalse);

      onboarding.complete(
        const AppSession(
          did: 'did:wba:awiki.ai:user:alice:e1_late',
          identityId: 'late-id',
          displayName: 'Alice',
          handle: 'alice.awiki.ai',
          localAlias: 'alice',
        ),
      );
      await request;

      expect(await sessions.currentSession(), isNull);
    },
  );
}

class _BlockingOnboardingService implements OnboardingService {
  final Completer<AppSessionTransition> started =
      Completer<AppSessionTransition>();
  final Completer<IdentityRegistrationResult> _result =
      Completer<IdentityRegistrationResult>();

  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) async => const LegacyIdentityUpgradeStatus.idle();

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) async => const LegacyIdentityUpgradeStatus.completed();

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) {
    started.complete(transition!);
    return _result.future;
  }

  void complete(AppSession session) {
    _result.complete(
      IdentityRegistrationResult(
        status: IdentityRegistrationStatus.registered,
        identity: session,
      ),
    );
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) => throw UnimplementedError();

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) => throw UnimplementedError();
}
