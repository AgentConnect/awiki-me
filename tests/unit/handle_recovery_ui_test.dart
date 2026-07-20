import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/handle_recovery_completion.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/repositories/awiki_account_gateway.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';
import 'devices/device_test_support.dart';

void main() {
  testWidgets(
    'registered Handle enters cooling, requires a second OTP, then activates a new DID',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      final gateway = FakeAwikiGateway()
        ..handleRegistrationStatus = HandleRegistrationStatus.registered;
      final recovery = _FakeHandleRecoveryPort()..failFinalizeOnce = true;
      final e2ee = _FailOnceRecoveryE2ee();

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const OnboardingPage(),
          gateway: gateway,
          providerOverrides: _recoveryOverrides(recovery),
          e2eeFacade: e2ee,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
      await tester.enterText(
        find.byType(CupertinoTextField).at(1),
        '13800138000',
      );
      await tester.tap(find.text('发送验证码'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).at(2), '123456');
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('handle-recovery-panel')), findsOneWidget);
      expect(find.text('恢复 AWiki Handle'), findsOneWidget);
      expect(find.textContaining('全新的根密钥和密码学 DID'), findsOneWidget);
      expect(find.textContaining('群组成员关系不会自动继承'), findsOneWidget);
      expect(recovery.beginCalls, 1);
      expect(recovery.sendBeginOtpCalls, 1);
      expect(recovery.lastBeginOtpHandle, 'alice');
      expect(recovery.lastBeginOtpDomain, 'awiki.ai');
      expect(recovery.lastBeginOtp, '123456');
      expect(gateway.sendOtpCalls, 0);
      expect(gateway.recoverHandleCalls, 0);
      expect(gateway.resumeGroupRecoveryCalls, 0);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      expect(container.read(sessionProvider).session, isNull);

      final refresh = find.text('刷新恢复状态');
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(find.text('可以进行独立的再次确认'), findsOneWidget);

      final finalButton = find.text('确认恢复 Handle 并创建新 DID');
      expect(
        tester
            .widget<AppDangerButton>(
              find.ancestor(
                of: finalButton,
                matching: find.byType(AppDangerButton),
              ),
            )
            .onPressed,
        isNull,
      );

      final sendFinalOtp = find.text('发送新的验证码');
      await tester.ensureVisible(sendFinalOtp);
      await tester.tap(sendFinalOtp);
      await tester.pumpAndSettle();
      expect(recovery.sendFinalizeOtpCalls, 1);

      final panel = find.byKey(const Key('handle-recovery-panel'));
      final fields = find.descendant(
        of: panel,
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(fields.at(1), '654321');
      final confirmation = find.byKey(
        const Key('handle-recovery-risk-confirmation'),
      );
      await tester.ensureVisible(confirmation);
      await tester.tap(confirmation);
      await tester.pump();
      await tester.ensureVisible(finalButton);
      await tester.tap(finalButton);
      await tester.pumpAndSettle();

      expect(recovery.finalizeCalls, 1);
      expect(container.read(sessionProvider).session, isNull);
      expect(find.byKey(const Key('handle-recovery-error')), findsOneWidget);

      await tester.enterText(fields.at(1), '654321');
      await tester.ensureVisible(finalButton);
      await tester.tap(finalButton);
      await tester.pumpAndSettle();

      expect(recovery.finalizeCalls, 2);
      expect(recovery.lastFinalizeOtp, '654321');
      expect(find.text('新 DID 已创建，等待本地激活'), findsOneWidget);
      expect(container.read(sessionProvider).session, isNull);
      expect(container.read(appRuntimeProvider).activatedDid, isNull);
      expect(recovery.markActivationCompleteCalls, 0);

      final retryActivation = find.text('重试本地激活');
      await tester.ensureVisible(retryActivation);
      await tester.tap(retryActivation);
      await tester.pumpAndSettle();

      expect(recovery.finalizeCalls, 2);
      expect(recovery.markActivationCompleteCalls, 1);
      expect(recovery.resumeActivationCalls, 1);
      expect(e2ee.initializeCalls, 2);
      expect(
        container.read(sessionProvider).session?.did,
        'did:wba:awiki.info:user:alice:e1_new',
      );
      expect(
        container.read(appRuntimeProvider).activatedDid,
        'did:wba:awiki.info:user:alice:e1_new',
      );
      expect(gateway.resumeGroupRecoveryCalls, 0);
    },
  );

  testWidgets('old admin device receives an explicit cancel entry', (
    tester,
  ) async {
    final recovery = _FakeHandleRecoveryPort(
      oldAdminNotices: <OldAdminRecoveryNotice>[_oldAdminNotice()],
    );
    final devices = FakeDeviceManagementCore()
      ..registry = const DeviceRegistrySnapshot(
        did: 'did:wba:awiki.info:user:alice:e1_old',
        devices: <DeviceSummary>[
          DeviceSummary(
            protocolDeviceId: 'old-admin-current',
            signingKeyId: 'did:wba:awiki.info:user:alice:e1_old#old-admin-sign',
            e2eeKeyId: 'did:wba:awiki.info:user:alice:e1_old#old-admin-e2ee',
            status: DeviceStatus.active,
            role: DeviceRole.admin,
            managementReady: true,
            isCurrent: true,
          ),
        ],
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const DevicesPage(),
        session: const SessionIdentity(
          did: 'did:wba:awiki.info:user:alice:e1_old',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        providerOverrides: <Override>[
          ..._recoveryOverrides(recovery),
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(devices),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsOneWidget,
    );
    expect(find.text('身份恢复警报'), findsOneWidget);
    expect(find.textContaining('若不是你本人操作'), findsOneWidget);
    expect(find.textContaining('申请时间：'), findsOneWidget);
    expect(find.textContaining('可取消截止时间：'), findsOneWidget);
    expect(find.textContaining('隐藏此警报不会取消'), findsOneWidget);
    expect(
      find.textContaining('awiki.identity.recovery-started.v1'),
      findsNothing,
    );
    expect(find.textContaining('sync_checkpoint'), findsNothing);

    await tester.tap(find.text('取消恢复'));
    await tester.pumpAndSettle();
    expect(find.text('确认取消 Handle 恢复？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('handle-recovery-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(recovery.cancelCalls, 1);
    expect(recovery.getNoticeCalls, 1);
    expect(recovery.dismissNoticeCalls, 1);
    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsNothing,
    );
  });

  testWidgets('local hide never calls server recovery cancel', (tester) async {
    final recovery = _FakeHandleRecoveryPort(
      oldAdminNotices: <OldAdminRecoveryNotice>[_oldAdminNotice()],
    );
    final devices = FakeDeviceManagementCore()
      ..registry = _adminRegistry(managementReady: true);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const DevicesPage(),
        session: const SessionIdentity(
          did: 'did:wba:awiki.info:user:alice:e1_old',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        providerOverrides: <Override>[
          ..._recoveryOverrides(recovery),
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(devices),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('仅在本设备隐藏'));
    await tester.pumpAndSettle();
    expect(find.text('此操作只隐藏本设备上的警报，不会取消服务器上的恢复请求。'), findsOneWidget);
    await tester.tap(find.byKey(const Key('handle-recovery-dismiss-confirm')));
    await tester.pumpAndSettle();

    expect(recovery.dismissNoticeCalls, 1);
    expect(recovery.cancelCalls, 0);
    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsNothing,
    );
  });

  testWidgets('refresh discovers a notice persisted by realtime Core', (
    tester,
  ) async {
    final recovery = _FakeHandleRecoveryPort();
    final devices = FakeDeviceManagementCore()
      ..registry = _adminRegistry(managementReady: true);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const DevicesPage(),
        session: const SessionIdentity(
          did: 'did:wba:awiki.info:user:alice:e1_old',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        providerOverrides: <Override>[
          ..._recoveryOverrides(recovery),
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(devices),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsNothing,
    );

    // Simulates the already-implemented Core realtime path persisting the
    // control event. AWiki Me discovers only the safe DTO on refresh.
    recovery.oldAdminNotices = <OldAdminRecoveryNotice>[_oldAdminNotice()];
    await tester.tap(find.byKey(const Key('devices-refresh')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsOneWidget,
    );
    expect(find.text('alice.awiki.info'), findsOneWidget);
    expect(find.textContaining('proof'), findsNothing);
    expect(find.textContaining('token'), findsNothing);

    // Core omits expired, cancelled, and locally dismissed records. The App
    // must converge to that safe list instead of retaining a stale card.
    recovery.oldAdminNotices = const <OldAdminRecoveryNotice>[];
    await tester.tap(find.byKey(const Key('devices-refresh')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsNothing,
    );
  });

  testWidgets('non-ready admin cannot see a recovery cancel action', (
    tester,
  ) async {
    final recovery = _FakeHandleRecoveryPort(
      oldAdminNotices: <OldAdminRecoveryNotice>[_oldAdminNotice()],
    );
    final devices = FakeDeviceManagementCore()
      ..registry = _adminRegistry(managementReady: false);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const DevicesPage(),
        session: const SessionIdentity(
          did: 'did:wba:awiki.info:user:alice:e1_old',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        providerOverrides: <Override>[
          ..._recoveryOverrides(recovery),
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(devices),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('handle-recovery-admin-section')),
      findsNothing,
    );
    expect(find.text('取消恢复'), findsNothing);
    expect(recovery.cancelCalls, 0);
  });

  testWidgets('consumed recovery resumes only local activation after restart', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    final recovery = _FakeHandleRecoveryPort(
      localSessions: <HandleRecoveryProgress>[
        _progress(
          phase: HandleRecoveryPhase.consumed,
          newDid: 'did:wba:awiki.info:user:alice:e1_new',
          localActivationPending: true,
        ),
      ],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: _recoveryOverrides(recovery),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('新 DID 已创建，等待本地激活'), findsOneWidget);
    expect(recovery.finalizeCalls, 0);

    final retry = find.text('重试本地激活');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(recovery.resumeActivationCalls, 1);
    expect(recovery.finalizeCalls, 0);
    expect(
      container.read(sessionProvider).session?.did,
      'did:wba:awiki.info:user:alice:e1_new',
    );
  });

  testWidgets(
    'marker ACK failure stays globally retryable without repeating E2EE or finalize',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      final recovery = _FakeHandleRecoveryPort(
        localSessions: <HandleRecoveryProgress>[
          _progress(
            phase: HandleRecoveryPhase.consumed,
            newDid: 'did:wba:awiki.info:user:alice:e1_new',
            localActivationPending: true,
          ),
        ],
      )..failMarkOnce = true;
      final sessions = _RecoveryAppSessionService();
      final e2ee = _CountingRecoveryE2ee();

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          providerOverrides: _recoveryOverrides(recovery, sessions: sessions),
          e2eeFacade: e2ee,
        ),
      );
      await tester.pumpAndSettle();

      final initialRetry = find.text('重试本地激活');
      await tester.ensureVisible(initialRetry);
      await tester.tap(initialRetry);
      await tester.pumpAndSettle();

      expect(recovery.markActivationCompleteCalls, 1);
      expect(recovery.resumeActivationCalls, 1);
      expect(sessions.activateCalls, 1);
      expect(e2ee.initializeCalls, 1);
      expect(
        find.byKey(const Key('handle-recovery-global-activation')),
        findsOneWidget,
      );

      await tester.tap(find.text('重试保存完成状态'));
      await tester.pumpAndSettle();

      expect(recovery.markActivationCompleteCalls, 2);
      expect(recovery.resumeActivationCalls, 1);
      expect(recovery.finalizeCalls, 0);
      expect(sessions.activateCalls, 1);
      expect(e2ee.initializeCalls, 1);
      expect(
        find.byKey(const Key('handle-recovery-global-activation')),
        findsNothing,
      );
    },
  );

  testWidgets('identity transition stops old realtime before Core activation', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    const oldSession = AppSession(
      did: 'did:wba:awiki.info:user:alice:e1_old',
      identityId: 'did:wba:awiki.info:user:alice:e1_old',
      displayName: 'alice-old',
      handle: 'alice.awiki.info',
      authenticated: true,
      jwtToken: 'old-device-token',
    );
    final recovery = _FakeHandleRecoveryPort(
      localSessions: <HandleRecoveryProgress>[
        _progress(
          phase: HandleRecoveryPhase.consumed,
          newDid: 'did:wba:awiki.info:user:alice:e1_new',
          localActivationPending: true,
        ),
      ],
    );
    final stopGate = Completer<void>();
    final sessions = _RecoveryAppSessionService(restoreResult: oldSession);
    final realtime = _ControlledRecoveryRealtime(
      running: true,
      nextStopGate: stopGate,
    )..currentDid = () async => (await sessions.currentSession())?.did;
    final e2ee = _CountingRecoveryE2ee();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: _recoveryOverrides(
          recovery,
          sessions: sessions,
          realtime: realtime,
        ),
        e2eeFacade: e2ee,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(container.read(sessionProvider).session?.did, oldSession.did);

    await tester.tap(find.text('重试本地激活'));
    await realtime.stopStarted.future;
    await tester.pump();

    expect(container.read(sessionProvider).session, isNull);
    expect(container.read(appRuntimeProvider).activatedDid, isNull);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(
      find.byKey(const Key('handle-recovery-global-activation')),
      findsNothing,
    );
    expect(recovery.resumeActivationCalls, 0);
    expect(sessions.logoutCalls, 0);
    expect(sessions.activateCalls, 0);
    expect(recovery.markActivationCompleteCalls, 0);
    expect(realtime.startCalls, 0);

    stopGate.complete();
    await tester.pumpAndSettle();

    expect(
      container.read(sessionProvider).session?.did,
      'did:wba:awiki.info:user:alice:e1_new',
    );
    expect(
      container.read(appRuntimeProvider).activatedDid,
      'did:wba:awiki.info:user:alice:e1_new',
    );
    expect(sessions.activateCalls, 1);
    expect(e2ee.initializeCalls, 2);
    expect(recovery.markActivationCompleteCalls, 1);
    expect(realtime.stopCalls, 1);
    expect(realtime.startCalls, 1);
    expect(realtime.startedDids, <String?>[
      'did:wba:awiki.info:user:alice:e1_new',
    ]);
  });

  testWidgets('realtime stop failure leaves recovery logged out and pending', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    const oldSession = AppSession(
      did: 'did:wba:awiki.info:user:alice:e1_old',
      identityId: 'did:wba:awiki.info:user:alice:e1_old',
      displayName: 'alice-old',
      handle: 'alice.awiki.info',
      authenticated: true,
      jwtToken: 'old-device-token',
    );
    final pending = _progress(
      phase: HandleRecoveryPhase.consumed,
      newDid: 'did:wba:awiki.info:user:alice:e1_new',
      localActivationPending: true,
    );
    final recovery = _FakeHandleRecoveryPort(
      localSessions: <HandleRecoveryProgress>[pending],
    );
    final sessions = _RecoveryAppSessionService(restoreResult: oldSession);
    final realtime = _ControlledRecoveryRealtime(
      running: true,
      stopError: StateError('realtime_stop_failed'),
    );
    final e2ee = _CountingRecoveryE2ee();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: _recoveryOverrides(
          recovery,
          sessions: sessions,
          realtime: realtime,
        ),
        e2eeFacade: e2ee,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(container.read(sessionProvider).session?.did, oldSession.did);

    await tester.tap(find.text('重试本地激活'));
    await tester.pumpAndSettle();

    final state = container.read(handleRecoveryProvider);
    expect(container.read(sessionProvider).session, isNull);
    expect(container.read(appRuntimeProvider).activatedDid, isNull);
    expect(await sessions.currentSession(), isNull);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(state.activationPending?.newDid, pending.newDid);
    expect(state.error, HandleRecoveryErrorKind.activation);
    expect(recovery.resumeActivationCalls, 0);
    expect(sessions.activateCalls, 0);
    expect(recovery.markActivationCompleteCalls, 0);
    expect(e2ee.initializeCalls, 1);
    expect(realtime.stopCalls, 1);
    expect(realtime.startCalls, 0);
  });

  testWidgets('slow restore cannot overwrite a newer marker-only ACK', (
    tester,
  ) async {
    const restored = AppSession(
      did: 'did:wba:awiki.info:user:alice:e1_new',
      identityId: 'did:wba:awiki.info:user:alice:e1_new',
      displayName: 'alice',
      handle: 'alice.awiki.info',
      authenticated: true,
    );
    final stalePending = _progress(
      phase: HandleRecoveryPhase.consumed,
      newDid: restored.did,
      localActivationPending: true,
    );
    final recovery = _FakeHandleRecoveryPort(
      localSessions: <HandleRecoveryProgress>[stalePending],
    )..failMarkOnce = true;
    final sessions = _RecoveryAppSessionService(restoreResult: restored);
    final e2ee = _CountingRecoveryE2ee();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: _recoveryOverrides(recovery, sessions: sessions),
        e2eeFacade: e2ee,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final controller = container.read(handleRecoveryProvider.notifier);
    final restoreGate = Completer<List<HandleRecoveryProgress>>();
    final markGate = Completer<void>();
    recovery.nextRestore = restoreGate;
    recovery.nextMarkGate = markGate;

    final slowRestore = controller.restore();
    await tester.pump();
    expect(container.read(handleRecoveryProvider).isLoading, isTrue);
    expect(
      tester
          .widget<AppPrimaryButton>(
            find.descendant(
              of: find.byKey(const Key('handle-recovery-global-activation')),
              matching: find.byType(AppPrimaryButton),
            ),
          )
          .onPressed,
      isNull,
    );

    final retry = controller.retryActivation();
    await recovery.markStarted.future;
    restoreGate.complete(<HandleRecoveryProgress>[stalePending]);
    await slowRestore;
    expect(container.read(handleRecoveryProvider).isActionPending, isTrue);
    markGate.complete();
    expect(await retry, isTrue);
    await tester.pumpAndSettle();

    final state = container.read(handleRecoveryProvider);
    expect(state.activationPending, isNull);
    expect(state.sessions, isEmpty);
    expect(state.isBusy, isFalse);
    expect(recovery.markActivationCompleteCalls, 2);
    expect(recovery.resumeActivationCalls, 0);
    expect(sessions.activateCalls, 0);
    expect(e2ee.initializeCalls, 1);
  });

  testWidgets('slow restore cannot overwrite a newer full local activation', (
    tester,
  ) async {
    final stalePending = _progress(
      phase: HandleRecoveryPhase.consumed,
      newDid: 'did:wba:awiki.info:user:alice:e1_new',
      localActivationPending: true,
    );
    final recovery = _FakeHandleRecoveryPort(
      localSessions: <HandleRecoveryProgress>[stalePending],
    );
    final activationGate = Completer<void>();
    final sessions = _RecoveryAppSessionService(
      nextActivationGate: activationGate,
    );
    final e2ee = _CountingRecoveryE2ee();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: _recoveryOverrides(recovery, sessions: sessions),
        e2eeFacade: e2ee,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final controller = container.read(handleRecoveryProvider.notifier);
    final restoreGate = Completer<List<HandleRecoveryProgress>>();
    recovery.nextRestore = restoreGate;

    final slowRestore = controller.restore();
    await tester.pump();
    expect(container.read(handleRecoveryProvider).isLoading, isTrue);

    final retry = controller.retryActivation();
    await sessions.activationStarted.future;
    restoreGate.complete(<HandleRecoveryProgress>[stalePending]);
    await slowRestore;
    expect(container.read(handleRecoveryProvider).isActionPending, isTrue);
    activationGate.complete();
    expect(await retry, isTrue);
    await tester.pumpAndSettle();

    final state = container.read(handleRecoveryProvider);
    expect(state.activationPending, isNull);
    expect(state.sessions, isEmpty);
    expect(state.isBusy, isFalse);
    expect(recovery.resumeActivationCalls, 1);
    expect(recovery.markActivationCompleteCalls, 1);
    expect(sessions.activateCalls, 1);
    expect(e2ee.initializeCalls, 1);
    expect(
      container.read(sessionProvider).session?.did,
      'did:wba:awiki.info:user:alice:e1_new',
    );
  });

  testWidgets('slow restore cannot overwrite a newer admin cancellation', (
    tester,
  ) async {
    final staleAdmin = _progress(
      side: HandleRecoverySide.oldAdmin,
      canCancel: true,
    );
    final recovery = _FakeHandleRecoveryPort(
      localSessions: <HandleRecoveryProgress>[staleAdmin],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const DevicesPage(),
        providerOverrides: _recoveryOverrides(recovery),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DevicesPage)),
    );
    final controller = container.read(handleRecoveryProvider.notifier);
    final restoreGate = Completer<List<HandleRecoveryProgress>>();
    final cancelGate = Completer<void>();
    recovery.nextRestore = restoreGate;
    recovery.nextCancelGate = cancelGate;

    final slowRestore = controller.restore();
    await tester.pump();
    expect(container.read(handleRecoveryProvider).isLoading, isTrue);

    final cancel = controller.cancel(
      staleAdmin,
      intentConfirmed: true,
      presenceReason: 'Confirm cancellation',
    );
    await recovery.cancelStarted.future;
    restoreGate.complete(<HandleRecoveryProgress>[staleAdmin]);
    await slowRestore;
    expect(container.read(handleRecoveryProvider).isActionPending, isTrue);
    cancelGate.complete();
    expect(await cancel, isTrue);
    await tester.pumpAndSettle();

    final state = container.read(handleRecoveryProvider);
    expect(state.cancellableAdminSessions, isEmpty);
    expect(state.sessions.single.phase, HandleRecoveryPhase.cancelled);
    expect(state.isBusy, isFalse);
    expect(recovery.cancelCalls, 1);
  });

  testWidgets(
    'active-session persistence failure stays pending and retries without refinalize',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      final recovery = _FakeHandleRecoveryPort(
        localSessions: <HandleRecoveryProgress>[
          _progress(
            phase: HandleRecoveryPhase.consumed,
            newDid: 'did:wba:awiki.info:user:alice:e1_new',
            localActivationPending: true,
          ),
        ],
      );
      final sessions = _RecoveryAppSessionService(failActivateOnce: true);
      final e2ee = _CountingRecoveryE2ee();

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          providerOverrides: _recoveryOverrides(recovery, sessions: sessions),
          e2eeFacade: e2ee,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('重试本地激活'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      expect(container.read(sessionProvider).session, isNull);
      expect(container.read(appRuntimeProvider).activatedDid, isNull);
      expect(recovery.finalizeCalls, 0);
      expect(recovery.resumeActivationCalls, 1);
      expect(recovery.markActivationCompleteCalls, 0);
      expect(sessions.activateCalls, 1);
      expect(e2ee.initializeCalls, 0);
      expect(find.text('新 DID 已创建，等待本地激活'), findsOneWidget);

      await tester.tap(find.text('重试本地激活'));
      await tester.pumpAndSettle();

      expect(recovery.finalizeCalls, 0);
      expect(recovery.resumeActivationCalls, 2);
      expect(recovery.markActivationCompleteCalls, 1);
      expect(sessions.activateCalls, 2);
      expect(e2ee.initializeCalls, 1);
      expect(
        container.read(sessionProvider).session?.did,
        'did:wba:awiki.info:user:alice:e1_new',
      );
    },
  );

  testWidgets(
    'restart restores the new identity and runs E2EE once before marker-only retry',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      const restored = AppSession(
        did: 'did:wba:awiki.info:user:alice:e1_new',
        identityId: 'did:wba:awiki.info:user:alice:e1_new',
        displayName: 'alice',
        handle: 'alice.awiki.info',
        authenticated: true,
        jwtToken: 'new-device-token',
      );
      final recovery = _FakeHandleRecoveryPort(
        localSessions: <HandleRecoveryProgress>[
          _progress(
            phase: HandleRecoveryPhase.consumed,
            newDid: restored.did,
            localActivationPending: true,
          ),
        ],
      );
      final sessions = _RecoveryAppSessionService(restoreResult: restored);
      final e2ee = _CountingRecoveryE2ee();

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          providerOverrides: _recoveryOverrides(recovery, sessions: sessions),
          e2eeFacade: e2ee,
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      expect(sessions.restoreCalls, 1);
      expect(sessions.activateCalls, 0);
      expect(recovery.resumeActivationCalls, 0);
      expect(recovery.finalizeCalls, 0);
      expect(recovery.markActivationCompleteCalls, 1);
      expect(e2ee.initializeCalls, 1);
      expect(container.read(appRuntimeProvider).activatedDid, restored.did);
      expect(container.read(sessionProvider).session?.did, restored.did);
      expect(
        find.byKey(const Key('handle-recovery-global-activation')),
        findsNothing,
      );
    },
  );
}

List<Override> _recoveryOverrides(
  _FakeHandleRecoveryPort recovery, {
  AppSessionService? sessions,
  RealtimeApplicationService? realtime,
}) {
  return <Override>[
    awikiEnvironmentConfigProvider.overrideWithValue(
      AwikiEnvironmentConfig(
        baseUrl: 'https://awiki.info',
        handleRecoveryEnabled: true,
      ),
    ),
    handleRecoveryPortProvider.overrideWithValue(recovery),
    userPresencePortProvider.overrideWithValue(_AllowUserPresence()),
    if (sessions != null) appSessionServiceProvider.overrideWithValue(sessions),
    if (realtime != null)
      realtimeApplicationServiceProvider.overrideWithValue(realtime),
  ];
}

HandleRecoveryProgress _progress({
  HandleRecoverySide side = HandleRecoverySide.requester,
  HandleRecoveryPhase phase = HandleRecoveryPhase.cooling,
  bool canCancel = false,
  String? newDid,
  bool localActivationPending = false,
}) {
  return HandleRecoveryProgress(
    recoverySessionId: 'recovery-1',
    handle: 'alice',
    handleDomain: 'awiki.ai',
    oldDid: 'did:wba:awiki.info:user:alice:e1_old',
    side: side,
    phase: phase,
    coolingUntil: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    canCancelFromThisDevice: canCancel,
    newDid: newDid,
    localActivationPending: localActivationPending,
  );
}

OldAdminRecoveryNotice _oldAdminNotice() => OldAdminRecoveryNotice(
  eventId: 'recovery-event-1',
  recoverySessionId: 'recovery-1',
  canonicalHandle: 'alice.awiki.info',
  oldDid: 'did:wba:awiki.info:user:alice:e1_old',
  requestedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
  cancellableUntil: DateTime.now().toUtc().add(const Duration(days: 1)),
);

DeviceRegistrySnapshot _adminRegistry({required bool managementReady}) =>
    DeviceRegistrySnapshot(
      did: 'did:wba:awiki.info:user:alice:e1_old',
      devices: <DeviceSummary>[
        DeviceSummary(
          protocolDeviceId: 'old-admin-current',
          signingKeyId: 'did:wba:awiki.info:user:alice:e1_old#old-admin-sign',
          e2eeKeyId: 'did:wba:awiki.info:user:alice:e1_old#old-admin-e2ee',
          status: DeviceStatus.active,
          role: DeviceRole.admin,
          managementReady: managementReady,
          isCurrent: true,
        ),
      ],
    );

class _FakeHandleRecoveryPort implements HandleRecoveryPort {
  _FakeHandleRecoveryPort({
    this.localSessions = const <HandleRecoveryProgress>[],
    this.oldAdminNotices = const <OldAdminRecoveryNotice>[],
  });

  List<HandleRecoveryProgress> localSessions;
  List<OldAdminRecoveryNotice> oldAdminNotices;
  int beginCalls = 0;
  int sendBeginOtpCalls = 0;
  int sendFinalizeOtpCalls = 0;
  int finalizeCalls = 0;
  int cancelCalls = 0;
  int getNoticeCalls = 0;
  int dismissNoticeCalls = 0;
  int markActivationCompleteCalls = 0;
  int resumeActivationCalls = 0;
  bool failFinalizeOnce = false;
  bool failMarkOnce = false;
  Completer<List<HandleRecoveryProgress>>? nextRestore;
  Completer<void>? nextMarkGate;
  Completer<void>? nextCancelGate;
  final Completer<void> markStarted = Completer<void>();
  final Completer<void> cancelStarted = Completer<void>();
  String? lastBeginOtpHandle;
  String? lastBeginOtpDomain;
  String? lastBeginOtp;
  String? lastFinalizeOtp;

  @override
  Future<void> sendRecoveryBeginSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  }) async {
    sendBeginOtpCalls += 1;
    lastBeginOtpHandle = handle;
    lastBeginOtpDomain = handleDomain;
  }

  @override
  Future<HandleRecoveryProgress> beginHandleRecoveryWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    beginCalls += 1;
    lastBeginOtp = otp;
    final progress = _progress();
    localSessions = <HandleRecoveryProgress>[progress];
    return progress;
  }

  @override
  Future<HandleRecoveryCancelResult> cancelHandleRecovery({
    required String selector,
    required String recoverySessionId,
  }) async {
    cancelCalls += 1;
    final gate = nextCancelGate;
    if (gate != null) {
      nextCancelGate = null;
      if (!cancelStarted.isCompleted) cancelStarted.complete();
      await gate.future;
    }
    final cancelled = _progress(
      side: HandleRecoverySide.oldAdmin,
      phase: HandleRecoveryPhase.cancelled,
    );
    localSessions = <HandleRecoveryProgress>[cancelled];
    return HandleRecoveryCancelResult(
      recoverySessionId: cancelled.recoverySessionId,
      phase: cancelled.phase,
    );
  }

  @override
  Future<HandleRecoveryCompletion> finalizeHandleRecoveryWithSms({
    required String recoverySessionId,
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    finalizeCalls += 1;
    lastFinalizeOtp = otp;
    if (failFinalizeOnce) {
      failFinalizeOnce = false;
      throw StateError('network_unavailable');
    }
    const newDid = 'did:wba:awiki.info:user:alice:e1_new';
    final consumed = _progress(
      phase: HandleRecoveryPhase.consumed,
      newDid: newDid,
      localActivationPending: true,
    );
    localSessions = <HandleRecoveryProgress>[consumed];
    return HandleRecoveryCompletion(
      progress: consumed,
      session: const AppSession(
        did: newDid,
        identityId: newDid,
        displayName: 'alice',
        handle: 'alice.awiki.info',
        authenticated: true,
        jwtToken: 'new-device-token',
      ),
    );
  }

  @override
  Future<List<HandleRecoveryProgress>> localHandleRecoverySessions() {
    final pending = nextRestore;
    if (pending != null) {
      nextRestore = null;
      return pending.future;
    }
    return Future<List<HandleRecoveryProgress>>.value(localSessions);
  }

  @override
  Future<List<OldAdminRecoveryNotice>> listOldAdminRecoveryNotices(
    String oldIdentity,
  ) async => oldAdminNotices;

  @override
  Future<OldAdminRecoveryNotice?> getOldAdminRecoveryNotice({
    required String oldIdentity,
    required String eventId,
  }) async {
    getNoticeCalls += 1;
    for (final notice in oldAdminNotices) {
      if (notice.eventId == eventId) return notice;
    }
    return null;
  }

  @override
  Future<OldAdminRecoveryNoticeDismissResult> dismissOldAdminRecoveryNotice({
    required String oldIdentity,
    required String eventId,
  }) async {
    dismissNoticeCalls += 1;
    oldAdminNotices = oldAdminNotices
        .where((notice) => notice.eventId != eventId)
        .toList(growable: false);
    return OldAdminRecoveryNoticeDismissResult(
      eventId: eventId,
      dismissed: true,
    );
  }

  @override
  Future<HandleRecoveryProgress> pollHandleRecovery(
    String recoverySessionId,
  ) async {
    final current = localSessions.single;
    final ready = _progress(
      side: current.side,
      phase: HandleRecoveryPhase.ready,
      canCancel: current.canCancelFromThisDevice,
    );
    localSessions = <HandleRecoveryProgress>[ready];
    return ready;
  }

  @override
  Future<void> sendRecoveryFinalizeSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
    required String recoverySessionId,
  }) async {
    sendFinalizeOtpCalls += 1;
  }

  @override
  Future<AppSession> resumeRecoveryActivation(String recoverySessionId) async {
    resumeActivationCalls += 1;
    return const AppSession(
      did: 'did:wba:awiki.info:user:alice:e1_new',
      identityId: 'did:wba:awiki.info:user:alice:e1_new',
      displayName: 'alice',
      handle: 'alice.awiki.info',
      authenticated: true,
      jwtToken: 'new-device-token',
    );
  }

  @override
  Future<void> markRecoveryActivationComplete(String recoverySessionId) async {
    markActivationCompleteCalls += 1;
    final gate = nextMarkGate;
    if (gate != null) {
      nextMarkGate = null;
      if (!markStarted.isCompleted) markStarted.complete();
      await gate.future;
    }
    if (failMarkOnce) {
      failMarkOnce = false;
      throw StateError('marker_ack_failed');
    }
    localSessions = <HandleRecoveryProgress>[];
  }
}

class _AllowUserPresence implements UserPresencePort {
  @override
  Future<bool> confirm({required String reason}) async => true;
}

class _FailOnceRecoveryE2ee extends FakeE2eeFacade {
  bool _fail = true;
  int initializeCalls = 0;

  @override
  Future<void> initialize(SessionIdentity identity) async {
    initializeCalls += 1;
    if (_fail) {
      _fail = false;
      throw StateError('e2ee_initialization_failed');
    }
  }
}

class _CountingRecoveryE2ee extends FakeE2eeFacade {
  int initializeCalls = 0;

  @override
  Future<void> initialize(SessionIdentity identity) async {
    initializeCalls += 1;
  }
}

class _ControlledRecoveryRealtime implements RealtimeApplicationService {
  _ControlledRecoveryRealtime({
    required this.running,
    this.nextStopGate,
    this.stopError,
  });

  bool running;
  Completer<void>? nextStopGate;
  Object? stopError;
  Future<String?> Function()? currentDid;
  final Completer<void> stopStarted = Completer<void>();
  final List<String?> startedDids = <String?>[];
  int stopCalls = 0;
  int startCalls = 0;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates =>
      const Stream<RealtimeConnectionStatus>.empty();

  @override
  bool get isRunning => running;

  @override
  Stream<RealtimeUpdate> get updates => const Stream<RealtimeUpdate>.empty();

  @override
  Future<void> start() async {
    startCalls += 1;
    startedDids.add(await currentDid?.call());
    running = true;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (!stopStarted.isCompleted) stopStarted.complete();
    final gate = nextStopGate;
    if (gate != null) {
      nextStopGate = null;
      await gate.future;
    }
    final error = stopError;
    if (error != null) throw error;
    running = false;
  }
}

class _RecoveryAppSessionService implements AppSessionService {
  _RecoveryAppSessionService({
    this.restoreResult,
    this.failActivateOnce = false,
    this.nextActivationGate,
  });

  final AppSession? restoreResult;
  bool failActivateOnce;
  Completer<void>? nextActivationGate;
  final Completer<void> activationStarted = Completer<void>();
  AppSession? _current;
  int restoreCalls = 0;
  int activateCalls = 0;
  int logoutCalls = 0;

  @override
  Future<AppSession> activateIdentity(AppSession identity) async {
    activateCalls += 1;
    if (failActivateOnce) {
      failActivateOnce = false;
      throw StateError('active_session_write_failed');
    }
    final gate = nextActivationGate;
    if (gate != null) {
      nextActivationGate = null;
      if (!activationStarted.isCompleted) activationStarted.complete();
      await gate.future;
    }
    _current = identity;
    return identity;
  }

  @override
  Future<AppSession?> currentSession() async => _current;

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) =>
      throw UnsupportedError('unsupported');

  @override
  Future<List<AppSession>> listLocalIdentities() async => restoreResult == null
      ? const <AppSession>[]
      : <AppSession>[restoreResult!];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) =>
      throw UnsupportedError('unsupported');

  @override
  Future<void> logout() async {
    logoutCalls += 1;
    _current = null;
  }

  @override
  Future<AppSession?> refreshSession() async => _current;

  @override
  Future<AppSession?> restoreSession() async {
    restoreCalls += 1;
    _current = restoreResult;
    return restoreResult;
  }
}
