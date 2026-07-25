import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
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

      final request = controller.registerWithPhone(
        phone: '13800138000',
        otp: '123456',
        handle: 'alice',
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

      final request = controller.registerWithPhone(
        phone: '13800138000',
        otp: '123456',
        handle: 'alice',
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
  final Completer<AppSession> _result = Completer<AppSession>();

  @override
  Future<AppSession> registerHandleWithPhone({
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
    _result.complete(session);
  }

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
    AppSessionTransition? transition,
  }) => throw UnimplementedError();

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) => throw UnimplementedError();

  @override
  Future<AppSession> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) => throw UnimplementedError();
}
