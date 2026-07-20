import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/handle_recovery_completion.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_port.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('AwikiMeApp installs the bootstrap Recovery port', (
    tester,
  ) async {
    final gateway = FakeAwikiGateway();
    final realtimeGateway = FakeRealtimeGateway();
    final recovery = _RecoveryPort();
    final bootstrap = AppBootstrap(
      environment: AwikiEnvironmentConfig(
        baseUrl: 'https://awiki.info',
        handleRecoveryEnabled: true,
      ),
      accountGateway: gateway,
      gateway: gateway,
      realtimeGateway: realtimeGateway,
      notificationFacade: FakeNotificationFacade(),
      e2eeFacade: FakeE2eeFacade(),
      localePreferenceService: FakeLocalePreferenceService(),
      updateService: FakeUpdateService(),
      appSessionService: FakeAppSessionService(gateway),
      onboardingService: FakeOnboardingService(gateway),
      onboardingSupportService: FakeOnboardingSupportService(gateway),
      messagingService: FakeMessagingService(gateway),
      conversationService: FakeConversationService(gateway),
      groupApplicationService: FakeGroupApplicationService(gateway),
      profileApplicationService: FakeProfileApplicationService(gateway),
      relationshipApplicationService: FakeRelationshipApplicationService(
        gateway,
      ),
      realtimeApplicationService: FakeRealtimeApplicationService(
        gateway: gateway,
        realtimeGateway: realtimeGateway,
      ),
      handleRecoveryPort: recovery,
    );

    await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(container.read(handleRecoveryPortProvider), same(recovery));
  });
}

class _RecoveryPort implements HandleRecoveryPort {
  @override
  Future<HandleRecoveryProgress> beginHandleRecoveryWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async => throw UnimplementedError();

  @override
  Future<HandleRecoveryCancelResult> cancelHandleRecovery({
    required String selector,
    required String recoverySessionId,
  }) async => throw UnimplementedError();

  @override
  Future<HandleRecoveryCompletion> finalizeHandleRecoveryWithSms({
    required String recoverySessionId,
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async => throw UnimplementedError();

  @override
  Future<List<HandleRecoveryProgress>> localHandleRecoverySessions() async =>
      const <HandleRecoveryProgress>[];

  @override
  Future<void> markRecoveryActivationComplete(String recoverySessionId) async {}

  @override
  Future<HandleRecoveryProgress> pollHandleRecovery(
    String recoverySessionId,
  ) async => throw UnimplementedError();

  @override
  Future<AppSession> resumeRecoveryActivation(String recoverySessionId) async =>
      throw UnimplementedError();

  @override
  Future<void> sendRecoveryBeginSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  }) async {}

  @override
  Future<void> sendRecoveryFinalizeSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
    required String recoverySessionId,
  }) async {}
}
