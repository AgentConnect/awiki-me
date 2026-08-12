import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_bootstrap_epoch_barrier.dart';
import 'package:awiki_me/src/application/handle_recovery_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('Handle Recovery V4 application boundary', () {
    test(
      'Core creates operation and App never supplies an operation id',
      () async {
        final core = _FakeHandleRecoveryCore();
        final service = HandleRecoveryService(
          core: core,
          userPresence: _FakeUserPresence(),
        );

        final result = await service.requestOtp(
          localIdentityId: 'identity-alice',
          handle: ' Alice.AWIKI.info ',
          phone: ' +8613800138000 ',
        );

        expect(result.operationId, 'operation-core-1');
        expect(core.lastOwner?.localIdentityId, 'identity-alice');
        expect(core.lastOwner?.handle, 'alice.awiki.info');
        expect(core.lastPhone, '+8613800138000');
      },
    );

    test(
      'new machine requests recovery without a local identity selector',
      () async {
        final core = _FakeHandleRecoveryCore();
        final service = HandleRecoveryService(
          core: core,
          userPresence: _FakeUserPresence(),
        );

        final result = await service.requestOtp(
          handle: ' Alice.AWIKI.info ',
          phone: ' +8613800138000 ',
        );

        expect(result.operationId, 'operation-core-1');
        expect(core.lastLocalIdentityId, isNull);
        expect(core.lastOwner?.handle, 'alice.awiki.info');
        expect(core.lastPhone, '+8613800138000');
      },
    );

    test(
      'post-attempt factor retry preserves operation id and can prepare',
      () async {
        final retryOperation = _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
          commitAttempted: true,
          resultAbsent: true,
        );
        final core = _FakeHandleRecoveryCore(
          operation: retryOperation,
          otpResponseOperation: retryOperation,
        );
        final service = HandleRecoveryService(
          core: core,
          userPresence: _FakeUserPresence(),
        );

        final result = await service.requestOtp(
          localIdentityId: 'identity-alice',
          handle: 'alice.awiki.info',
          phone: '+8613800138000',
          expectedOperationId: retryOperation.operationId,
        );
        final prepared = await service.prepare(
          operationId: result.operationId,
          phone: '+8613800138000',
          otp: '123456',
        );

        expect(result.operationId, retryOperation.operationId);
        expect(result.operation.commitAttempted, isTrue);
        expect(result.operation.canDiscard, isFalse);
        expect(prepared.operationId, retryOperation.operationId);
      },
    );

    test('post-attempt factor retry rejects a replacement operation', () async {
      final current = _operation(
        operationId: 'operation-core-1',
        lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
        commitAttempted: true,
      );
      final replacement = _operation(
        operationId: 'operation-core-2',
        lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
        commitAttempted: true,
      );
      final service = HandleRecoveryService(
        core: _FakeHandleRecoveryCore(
          operation: current,
          otpResponseOperation: replacement,
        ),
        userPresence: _FakeUserPresence(),
      );

      await expectLater(
        service.requestOtp(
          localIdentityId: 'identity-alice',
          handle: 'alice.awiki.info',
          phone: '+8613800138000',
          expectedOperationId: current.operationId,
        ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (failure) => failure.code,
            'code',
            HandleRecoveryFailureCode.transitionMismatch,
          ),
        ),
      );
    });

    test('restored post-attempt operation requests OTP before prepare', () {
      final operation = _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
        commitAttempted: true,
      );
      final restored = HandleRecoveryState(
        owner: const HandleRecoveryOwner(
          localIdentityId: 'identity-alice',
          handle: 'alice.awiki.info',
        ),
        progress: operation,
      );

      expect(restored.canRequestOtp, isTrue);
      expect(restored.otpRequested, isFalse);

      final afterSend = restored.copyWith(otpPhone: '+8613800138000');
      expect(afterSend.otpOperationId, operation.operationId);
      expect(afterSend.otpRequested, isTrue);
      expect(afterSend.progress?.canDiscard, isFalse);
    });

    test(
      'restart enumerates by stable owner and queries exact operation',
      () async {
        final core = _FakeHandleRecoveryCore(
          operation: _operation(
            lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
            commitAttempted: true,
            resultAbsent: true,
          ),
        );
        final service = HandleRecoveryService(
          core: core,
          userPresence: _FakeUserPresence(),
        );

        final restored = await service.restoreForOwner(
          scope: const HandleRecoveryIdentityScope(
            localIdentityId: 'identity-alice',
          ),
          handle: 'alice.awiki.info',
        );

        expect(core.listCalls, 1);
        expect(core.statusCalls, 1);
        expect(restored?.operationId, 'operation-core-1');
        expect(restored?.isStillConfirming, isTrue);
        expect(restored?.canResume, isTrue);
        expect(restored?.canDiscard, isFalse);
      },
    );

    test(
      'restart reopens latest applied operation for central activation',
      () async {
        final core = _FakeHandleRecoveryCore(
          operation: _operation(
            lifecycleClass: HandleRecoveryLifecycleClass.applied,
            commitAttempted: true,
          ),
        );
        final service = HandleRecoveryService(
          core: core,
          userPresence: _FakeUserPresence(),
        );

        final restored = await service.restoreForOwner(
          scope: const HandleRecoveryIdentityScope(
            localIdentityId: 'identity-alice',
          ),
          handle: 'alice.awiki.info',
        );

        expect(restored?.isCompleted, isTrue);
        expect(core.statusCalls, 1);
      },
    );

    test(
      'only Core-authorized pre-attempt operation can be discarded',
      () async {
        final core = _FakeHandleRecoveryCore();
        final service = HandleRecoveryService(
          core: core,
          userPresence: _FakeUserPresence(),
        );

        await service.discardPreAttempt('operation-core-1');
        expect(core.discardCalls, 1);

        core.operation = _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
          commitAttempted: true,
          resultAbsent: true,
        );
        await expectLater(
          service.discardPreAttempt('operation-core-1'),
          throwsA(
            isA<HandleRecoveryFailure>().having(
              (error) => error.code,
              'code',
              HandleRecoveryFailureCode.outcomeUnknown,
            ),
          ),
        );
        expect(core.discardCalls, 1);
      },
    );

    test(
      'key-unavailable quarantine does not require a successful Vault status',
      () async {
        final core = _FakeHandleRecoveryCore(
          operation: _operation(
            lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
            commitAttempted: true,
          ),
          statusError: const HandleRecoveryFailure(
            HandleRecoveryFailureCode.localKeyUnavailable,
          ),
        );
        final presence = _FakeUserPresence();
        final service = HandleRecoveryService(
          core: core,
          userPresence: presence,
        );

        final result = await service.quarantineKeyUnavailable(
          operationId: 'operation-core-1',
          presenceReason: 'confirm destructive quarantine',
        );

        expect(presence.calls, 1);
        expect(core.quarantineCalls, 1);
        expect(core.statusCalls, 0);
        expect(
          result.lifecycleClass,
          HandleRecoveryLifecycleClass.quarantinedKeyUnavailable,
        );
      },
    );

    test('pre-commit unsupported migration prevents activation', () async {
      final core = _FakeHandleRecoveryCore(
        operation: _operation(
          readyToCommit: true,
          localMigration: HandleRecoveryLocalMigration.preCommitUnsupported,
        ),
      );
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
      );

      await expectLater(
        service.activate(
          operationId: 'operation-core-1',
          presenceReason: 'confirm',
        ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.localMigrationUnsupported,
          ),
        ),
      );
      expect(core.activateCalls, 0);
    });

    test('activation resumes the same operation after remote commit', () async {
      final applied = _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.applied,
        commitAttempted: true,
      );
      final core = _FakeHandleRecoveryCore(
        operation: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
          commitAttempted: true,
        ),
        reconcileResult: applied,
      );
      final presence = _FakeUserPresence();
      final service = HandleRecoveryService(core: core, userPresence: presence);

      final result = await service.activate(
        operationId: 'operation-core-1',
        presenceReason: 'confirm',
      );

      expect(result.isCompleted, isTrue);
      expect(core.activateCalls, 0);
      expect(core.reconcileCalls, 1);
      expect(presence.calls, 0);
    });

    test('Group repair impact never changes an applied Recovery result', () {
      final applied = _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.applied,
        commitAttempted: true,
        unsupportedE2eeGroupCount: 3,
        unsupportedDidOnlyGroupCount: 2,
      );

      expect(applied.isCompleted, isTrue);
      expect(applied.canResume, isFalse);
      expect(applied.impact.hasUnsupportedE2eeGroups, isTrue);
      expect(applied.impact.hasUnsupportedDidOnlyGroups, isTrue);
    });

    test('remote committed may precede the local state-root receipt', () async {
      final core = _FakeHandleRecoveryCore(
        operation: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.remoteCommitted,
          commitAttempted: true,
          stateRootFingerprint: null,
        ),
      );
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
      );

      final operations = await service.listOperations(
        scope: const HandleRecoveryIdentityScope(
          localIdentityId: 'identity-alice',
        ),
        handle: 'alice.awiki.info',
      );

      expect(operations.single.stateRootFingerprint, isNull);
    });

    test('local transition pending requires its state-root receipt', () async {
      final core = _FakeHandleRecoveryCore(
        operation: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
          commitAttempted: true,
          stateRootFingerprint: null,
        ),
      );
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
      );

      await expectLater(
        service.listOperations(
          scope: const HandleRecoveryIdentityScope(
            localIdentityId: 'identity-alice',
          ),
          handle: 'alice.awiki.info',
        ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.transitionMismatch,
          ),
        ),
      );
    });

    test('discarded before factor exchange may keep account id null', () async {
      final core = _FakeHandleRecoveryCore(
        operation: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.discardedPreAttempt,
          keyState: HandleRecoveryKeyState.destroyedPreAttempt,
          accountUserId: null,
          stateRootFingerprint: null,
        ),
      );
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
      );

      final operations = await service.listOperations(
        scope: const HandleRecoveryIdentityScope(
          localIdentityId: 'identity-alice',
        ),
        handle: 'alice.awiki.info',
      );

      expect(operations.single.accountUserId, isNull);
      expect(operations.single.isActionable, isFalse);
    });
  });

  testWidgets(
    'settings recovery targets the exact current identity and accepts a phone',
    (tester) async {
      final core = _FakeHandleRecoveryCore();
      const session = SessionIdentity(
        did: 'did:wba:awiki.info:users:alice-old',
        credentialName: 'alice',
        displayName: 'Alice',
        localIdentityId: 'identity-alice',
        handle: 'alice.awiki.info',
      );

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const SettingsPage(),
          session: session,
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final recoveryRow = find.byKey(
        const Key('settings-recover-handle-did-row'),
      );
      await tester.ensureVisible(recoveryRow);
      await tester.tap(recoveryRow);
      await tester.pumpAndSettle();

      expect(find.byType(HandleRecoveryPage), findsOneWidget);
      expect(
        find.byKey(const Key('handle-recovery-phone-input')),
        findsOneWidget,
      );
      expect(core.lastLocalIdentityId, isNull);

      await tester.enterText(
        find.byKey(const Key('handle-recovery-phone-input')),
        '+8613800138000',
      );
      await tester.tap(find.byKey(const Key('handle-recovery-send-otp')));
      await tester.pumpAndSettle();

      expect(core.lastHandle, 'alice.awiki.info');
      expect(core.lastPhone, '+8613800138000');
      expect(core.lastLocalIdentityId, 'identity-alice');
    },
  );

  testWidgets(
    'result_absent is shown as still confirming and cannot be discarded',
    (tester) async {
      final operation = _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
        commitAttempted: true,
        resultAbsent: true,
      );
      final core = _FakeHandleRecoveryCore(
        operation: operation,
        otpResponseOperation: operation,
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: const Locale('en'),
          home: const HandleRecoveryPage(
            initialHandle: 'alice.awiki.info',
            initialPhone: '+8613800138000',
          ),
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('handle-recovery-handle')), findsOneWidget);
      expect(find.byKey(const Key('handle-recovery-phone')), findsOneWidget);
      expect(find.byKey(const Key('handle-recovery-otp')), findsOneWidget);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('handle-recovery-still-confirming')),
        findsOneWidget,
      );
      expect(find.textContaining('still being confirmed'), findsOneWidget);
      expect(find.byKey(const Key('handle-recovery-cancel-otp')), findsNothing);
      expect(find.byKey(const Key('handle-recovery-resume')), findsOneWidget);
    },
  );

  testWidgets('local key failure exposes explicit quarantine confirmation', (
    tester,
  ) async {
    final operation = _operation(
      lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
      commitAttempted: true,
    );
    final core = _FakeHandleRecoveryCore(
      operation: operation,
      otpResponseOperation: operation,
      reconcileError: const HandleRecoveryFailure(
        HandleRecoveryFailureCode.localKeyUnavailable,
      ),
    );
    final presence = _FakeUserPresence();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: const HandleRecoveryPage(
          initialHandle: 'alice.awiki.info',
          initialPhone: '+8613800138000',
        ),
        providerOverrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(presence),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('handle-recovery-resume')));
    await tester.pumpAndSettle();

    final quarantine = find.byKey(
      const Key('handle-recovery-quarantine-key-unavailable'),
    );
    expect(quarantine, findsOneWidget);

    await tester.ensureVisible(quarantine);
    await tester.pumpAndSettle();
    await tester.tap(quarantine);
    await tester.pumpAndSettle();

    expect(presence.calls, 1);
    expect(core.quarantineCalls, 1);
    expect(
      find.byKey(const Key('handle-recovery-start-after-quarantine')),
      findsOneWidget,
    );
  });

  testWidgets('completed Recovery opens the authenticated message workspace', (
    tester,
  ) async {
    const previousSession = SessionIdentity(
      did: 'did:wba:awiki.info:users:alice-old',
      localIdentityId: 'identity-alice',
      credentialName: 'identity-alice',
      displayName: 'Alice',
      handle: 'alice.awiki.info',
    );
    const recoveredDid = 'did:wba:awiki.info:users:alice-new';
    late ProviderContainer container;
    var oldSessionWasQuiesced = false;
    final core = _FakeHandleRecoveryCore(
      activateResult: _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.applied,
        commitAttempted: true,
      ),
      beforeActivate: () {
        oldSessionWasQuiesced = container.read(sessionProvider).session == null;
      },
    );
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: recoveredDid,
          localIdentityId: 'identity-alice',
          credentialName: 'identity-alice',
          displayName: 'Alice',
          handle: 'alice.awiki.info',
        ),
      ]
      ..loginResult = const SessionIdentity(
        did: recoveredDid,
        localIdentityId: 'identity-alice',
        credentialName: 'identity-alice',
        displayName: 'Alice',
        handle: 'alice.awiki.info',
      );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: previousSession,
        providerOverrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.settings);
    unawaited(
      Navigator.of(tester.element(find.byType(AppShell))).push<void>(
        CupertinoPageRoute<void>(
          builder: (_) => const HandleRecoveryPage(
            initialHandle: 'alice.awiki.info',
            initialPhone: '+8613800138000',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('handle-recovery-otp')),
        matching: find.byType(CupertinoTextField),
      ),
      '123456',
    );
    await tester.tap(find.byKey(const Key('handle-recovery-verify')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    await tester.drag(
      find.descendant(
        of: find.byType(HandleRecoveryPage),
        matching: find.byType(ListView),
      ),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('handle-recovery-activate')),
    );
    await tester.tap(find.byKey(const Key('handle-recovery-activate')));
    await tester.pumpAndSettle();

    expect(find.byType(HandleRecoveryPage), findsNothing);
    expect(find.byType(ConversationWorkspacePage), findsOneWidget);
    expect(container.read(shellDestinationProvider), ShellDestination.messages);
    expect(container.read(sessionProvider).session?.did, recoveredDid);
    expect(gateway.loginCalls, 1);
    expect(oldSessionWasQuiesced, isTrue);
  });

  testWidgets(
    'completed Recovery stays visible until local session activation succeeds',
    (tester) async {
      const recoveredDid = 'did:wba:awiki.info:users:alice-new';
      final core = _FakeHandleRecoveryCore(
        activateResult: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.applied,
          commitAttempted: true,
        ),
      );
      final gateway = _FailOnceLoginGateway()
        ..localCredentials = const <SessionIdentity>[
          SessionIdentity(
            did: recoveredDid,
            localIdentityId: 'identity-alice',
            credentialName: 'identity-alice',
            displayName: 'Alice',
            handle: 'alice.awiki.info',
          ),
        ]
        ..loginResult = const SessionIdentity(
          did: recoveredDid,
          localIdentityId: 'identity-alice',
          credentialName: 'identity-alice',
          displayName: 'Alice',
          handle: 'alice.awiki.info',
        );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: const Locale('zh'),
          home: const AppShell(),
          gateway: gateway,
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      container
          .read(shellDestinationProvider.notifier)
          .select(ShellDestination.settings);
      unawaited(
        Navigator.of(tester.element(find.byType(AppShell))).push<void>(
          CupertinoPageRoute<void>(
            builder: (_) => const HandleRecoveryPage(
              initialHandle: 'alice.awiki.info',
              initialPhone: '+8613800138000',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('handle-recovery-otp')),
          matching: find.byType(CupertinoTextField),
        ),
        '123456',
      );
      await tester.tap(find.byKey(const Key('handle-recovery-verify')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('handle-recovery-risk-confirmation')),
      );
      await tester.drag(
        find.descendant(
          of: find.byType(HandleRecoveryPage),
          matching: find.byType(ListView),
        ),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('handle-recovery-risk-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('handle-recovery-activate')),
      );
      await tester.tap(find.byKey(const Key('handle-recovery-activate')));
      await tester.pumpAndSettle();

      expect(find.byType(HandleRecoveryPage), findsOneWidget);
      expect(container.read(sessionProvider).session, isNull);
      expect(
        container.read(shellDestinationProvider),
        ShellDestination.settings,
      );
      expect(
        find.byKey(const Key('handle-recovery-session-activation-failed')),
        findsOneWidget,
      );
      final retry = find.byKey(const Key('handle-recovery-enter-messages'));
      expect(retry, findsOneWidget);

      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(find.byType(ConversationWorkspacePage), findsOneWidget);
      expect(container.read(sessionProvider).session?.did, recoveredDid);
      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
      expect(gateway.loginAttempts, 2);
      await tester.pump(const Duration(seconds: 9));
    },
  );

  testWidgets('completed activation does not read providers after disposal', (
    tester,
  ) async {
    final activation = Completer<HandleRecoveryProgress>();
    final core = _FakeHandleRecoveryCore(activateCompleter: activation);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const HandleRecoveryPage(
          initialHandle: 'alice.awiki.info',
          initialPhone: '+8613800138000',
        ),
        providerOverrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('handle-recovery-otp')),
        matching: find.byType(CupertinoTextField),
      ),
      '123456',
    );
    await tester.tap(find.byKey(const Key('handle-recovery-verify')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    await tester.drag(
      find.descendant(
        of: find.byType(HandleRecoveryPage),
        matching: find.byType(ListView),
      ),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('handle-recovery-activate')),
    );
    await tester.tap(find.byKey(const Key('handle-recovery-activate')));
    await tester.pump();
    expect(core.activateCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    activation.complete(
      _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.applied,
        commitAttempted: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'post-commit activation failure resumes and opens the message workspace',
    (tester) async {
      const recoveredDid = 'did:wba:awiki.info:users:alice-new';
      final core = _FakeHandleRecoveryCore(
        activateProgressOnError: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
          commitAttempted: true,
        ),
        activateError: StateError('post-commit transport interrupted'),
        reconcileResult: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.applied,
          commitAttempted: true,
        ),
      );
      final gateway = FakeAwikiGateway()
        ..localCredentials = const <SessionIdentity>[
          SessionIdentity(
            did: recoveredDid,
            localIdentityId: 'identity-alice',
            credentialName: 'identity-alice',
            displayName: 'Alice',
            handle: 'alice.awiki.info',
          ),
        ]
        ..loginResult = const SessionIdentity(
          did: recoveredDid,
          localIdentityId: 'identity-alice',
          credentialName: 'identity-alice',
          displayName: 'Alice',
          handle: 'alice.awiki.info',
        );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: const Locale('zh'),
          home: const AppShell(),
          gateway: gateway,
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      unawaited(
        Navigator.of(tester.element(find.byType(AppShell))).push<void>(
          CupertinoPageRoute<void>(
            builder: (_) => const HandleRecoveryPage(
              initialHandle: 'alice.awiki.info',
              initialPhone: '+8613800138000',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('handle-recovery-otp')),
          matching: find.byType(CupertinoTextField),
        ),
        '123456',
      );
      await tester.tap(find.byKey(const Key('handle-recovery-verify')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('handle-recovery-risk-confirmation')),
      );
      await tester.drag(
        find.descendant(
          of: find.byType(HandleRecoveryPage),
          matching: find.byType(ListView),
        ),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('handle-recovery-risk-confirmation')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('handle-recovery-activate')),
      );
      await tester.tap(find.byKey(const Key('handle-recovery-activate')));
      await tester.pumpAndSettle();

      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(find.byType(ConversationWorkspacePage), findsOneWidget);
      expect(container.read(sessionProvider).session?.did, recoveredDid);
      expect(core.activateCalls, 1);
      expect(core.reconcileCalls, 1);
      expect(find.textContaining('恢复尚未准备完成'), findsNothing);
    },
  );

  group('AppBootstrapEpochBarrier', () {
    test('records bounded app_epoch_barrier_total results', () async {
      final observed = <String>[];
      final metrics = AppBootstrapEpochBarrierMetrics(
        sink: (metric, result, total) {
          observed.add('$metric:$result:$total');
        },
      );
      final local = InMemoryAwikiProductLocalStore();
      await local.replaceDeviceRegistrySnapshot(
        _registrySnapshot(
          did: 'did:wba:awiki.info:users:alice-new',
          generation: '8',
        ),
      );
      final barrier = AppBootstrapEpochBarrier(
        recovery: _FakeHandleRecoveryCore(),
        local: local,
        metrics: metrics,
      );

      await barrier.ensureReady(identity: _identity, binding: _binding);
      await barrier.ensureReady(identity: _identity, binding: _binding);
      metrics.record('unbounded-input');

      expect(metrics.snapshot(), <String, int>{
        'ready': 1,
        'cached_ready': 1,
        'other': 1,
      });
      expect(observed, <String>[
        'app_epoch_barrier_total:ready:1',
        'app_epoch_barrier_total:cached_ready:1',
        'app_epoch_barrier_total:other:1',
      ]);
    });

    test(
      'matching Product epoch is ready without a Recovery receipt',
      () async {
        final local = InMemoryAwikiProductLocalStore();
        final core = _FakeHandleRecoveryCore();
        await local.replaceDeviceRegistrySnapshot(
          _registrySnapshot(
            did: 'did:wba:awiki.info:users:alice-new',
            generation: '8',
          ),
        );
        final barrier = AppBootstrapEpochBarrier(recovery: core, local: local);

        await barrier.ensureReady(identity: _identity, binding: _binding);

        expect(core.receiptCalls, 0);
      },
    );

    test(
      'mismatch requires exact receipt and atomically advances Product epoch',
      () async {
        final local = InMemoryAwikiProductLocalStore();
        final core = _FakeHandleRecoveryCore(receipt: _receipt);
        await local.replaceDeviceRegistrySnapshot(
          _registrySnapshot(
            did: 'did:wba:awiki.info:users:alice-old',
            generation: '7',
          ),
        );
        final barrier = AppBootstrapEpochBarrier(recovery: core, local: local);

        await barrier.ensureReady(identity: _identity, binding: _binding);

        final epoch = await local.loadDeviceRegistryEpoch(
          binding: _productBinding,
        );
        expect(epoch?.currentDid, _binding.currentDid);
        expect(epoch?.bindingGeneration, _binding.identityGeneration);
        expect(
          await local.loadDeviceRegistrySnapshot(binding: _productBinding),
          isNull,
        );
        expect(core.receiptCalls, 1);
      },
    );

    test(
      'unknown mismatch fails closed and does not advance Product epoch',
      () async {
        final local = InMemoryAwikiProductLocalStore();
        final core = _FakeHandleRecoveryCore();
        await local.replaceDeviceRegistrySnapshot(
          _registrySnapshot(
            did: 'did:wba:awiki.info:users:alice-old',
            generation: '7',
          ),
        );
        final barrier = AppBootstrapEpochBarrier(recovery: core, local: local);

        await expectLater(
          barrier.ensureReady(identity: _identity, binding: _binding),
          throwsA(
            isA<AppBootstrapEpochBarrierFailure>().having(
              (error) => error.code,
              'code',
              AppBootstrapEpochBarrierFailureCode.unknownEpoch,
            ),
          ),
        );
        final epoch = await local.loadDeviceRegistryEpoch(
          binding: _productBinding,
        );
        expect(epoch?.currentDid, 'did:wba:awiki.info:users:alice-old');
      },
    );

    test('receipt for a different device is rejected before reset', () async {
      final local = InMemoryAwikiProductLocalStore();
      final wrongDeviceReceipt = HandleRecoveryRegistryEpochReset(
        receiptSchemaVersion: _receipt.receiptSchemaVersion,
        accountUserId: _receipt.accountUserId,
        ownerIdentityId: _receipt.ownerIdentityId,
        handle: _receipt.handle,
        previousDid: _receipt.previousDid,
        currentDid: _receipt.currentDid,
        bindingGeneration: _receipt.bindingGeneration,
        currentDeviceId: 'another-device',
        deviceAuthGeneration: _receipt.deviceAuthGeneration,
        registryVersion: _receipt.registryVersion,
        stateRootFingerprint: _receipt.stateRootFingerprint,
        appliedAt: _receipt.appliedAt,
        metadataJson: _receipt.metadataJson,
        sourceKind: _receipt.sourceKind,
        sourceId: _receipt.sourceId,
      );
      final core = _FakeHandleRecoveryCore(receipt: wrongDeviceReceipt);
      await local.replaceDeviceRegistrySnapshot(
        _registrySnapshot(
          did: 'did:wba:awiki.info:users:alice-old',
          generation: '7',
        ),
      );
      final barrier = AppBootstrapEpochBarrier(recovery: core, local: local);

      await expectLater(
        barrier.ensureReady(identity: _identity, binding: _binding),
        throwsA(
          isA<AppBootstrapEpochBarrierFailure>().having(
            (error) => error.code,
            'code',
            AppBootstrapEpochBarrierFailureCode.receiptMismatch,
          ),
        ),
      );
      final epoch = await local.loadDeviceRegistryEpoch(
        binding: _productBinding,
      );
      expect(epoch?.currentDid, 'did:wba:awiki.info:users:alice-old');
    });

    test(
      'receipt generation beyond the frozen 255-digit profile is rejected',
      () async {
        final local = InMemoryAwikiProductLocalStore();
        final invalidReceipt = HandleRecoveryRegistryEpochReset(
          receiptSchemaVersion: _receipt.receiptSchemaVersion,
          accountUserId: _receipt.accountUserId,
          ownerIdentityId: _receipt.ownerIdentityId,
          handle: _receipt.handle,
          previousDid: _receipt.previousDid,
          currentDid: _receipt.currentDid,
          bindingGeneration: '1' * 256,
          currentDeviceId: _receipt.currentDeviceId,
          deviceAuthGeneration: _receipt.deviceAuthGeneration,
          registryVersion: _receipt.registryVersion,
          stateRootFingerprint: _receipt.stateRootFingerprint,
          appliedAt: _receipt.appliedAt,
          metadataJson: _receipt.metadataJson,
          sourceKind: _receipt.sourceKind,
          sourceId: _receipt.sourceId,
        );
        final core = _FakeHandleRecoveryCore(receipt: invalidReceipt);
        await local.replaceDeviceRegistrySnapshot(
          _registrySnapshot(
            did: 'did:wba:awiki.info:users:alice-old',
            generation: '7',
          ),
        );
        final barrier = AppBootstrapEpochBarrier(recovery: core, local: local);

        await expectLater(
          barrier.ensureReady(identity: _identity, binding: _binding),
          throwsA(
            isA<AppBootstrapEpochBarrierFailure>().having(
              (error) => error.code,
              'code',
              AppBootstrapEpochBarrierFailureCode.receiptMismatch,
            ),
          ),
        );
        final epoch = await local.loadDeviceRegistryEpoch(
          binding: _productBinding,
        );
        expect(epoch?.currentDid, 'did:wba:awiki.info:users:alice-old');
      },
    );

    test('concurrent entry points coalesce the exact same barrier', () async {
      final local = InMemoryAwikiProductLocalStore();
      final core = _FakeHandleRecoveryCore(receipt: _receipt);
      await local.replaceDeviceRegistrySnapshot(
        _registrySnapshot(
          did: 'did:wba:awiki.info:users:alice-old',
          generation: '7',
        ),
      );
      final barrier = AppBootstrapEpochBarrier(recovery: core, local: local);

      await Future.wait(<Future<void>>[
        barrier.ensureReady(identity: _identity, binding: _binding),
        barrier.ensureReady(identity: _identity, binding: _binding),
      ]);

      expect(core.receiptCalls, 1);
    });
  });
}

class _FailOnceLoginGateway extends FakeAwikiGateway {
  int loginAttempts = 0;

  @override
  Future<SessionIdentity> loginWithLocalCredential(
    String credentialName,
  ) async {
    loginAttempts += 1;
    if (loginAttempts == 1) {
      throw StateError('recovered_local_session_activation_failed');
    }
    return super.loginWithLocalCredential(credentialName);
  }
}

const _productBinding = ProductAccountBinding(
  ownerIdentityId: 'identity-alice',
  accountId: 'account-1',
);

const _binding = SessionAccountBinding(
  ownerIdentityId: 'identity-alice',
  accountId: 'account-1',
  currentDid: 'did:wba:awiki.info:users:alice-new',
  protocolDeviceId: 'device-new',
  identityGeneration: '8',
  deviceAuthGeneration: '3',
);

const _identity = AppSession(
  did: 'did:wba:awiki.info:users:alice-new',
  identityId: 'identity-alice',
  displayName: 'Alice',
  handle: 'alice.awiki.info',
);

final _receipt = HandleRecoveryRegistryEpochReset(
  receiptSchemaVersion: '1',
  accountUserId: 'account-1',
  ownerIdentityId: 'identity-alice',
  handle: 'alice.awiki.info',
  previousDid: 'did:wba:awiki.info:users:alice-old',
  currentDid: 'did:wba:awiki.info:users:alice-new',
  bindingGeneration: '8',
  currentDeviceId: 'device-new',
  deviceAuthGeneration: 3,
  registryVersion: 12,
  stateRootFingerprint:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  appliedAt: DateTime.utc(2026, 8, 7),
  metadataJson: '{}',
  sourceKind: HandleRecoveryTransitionSourceKind.initiator,
  sourceId: 'operation-core-1',
);

ProductDeviceRegistrySnapshot _registrySnapshot({
  required String did,
  required String generation,
}) => ProductDeviceRegistrySnapshot(
  binding: _productBinding,
  epoch: ProductDeviceRegistryEpoch(
    currentDid: did,
    bindingGeneration: generation,
  ),
  domainVersion: generation,
  refreshedAt: DateTime.utc(2026, 8, 7),
  devices: const <ProductDeviceRegistryItem>[],
);

HandleRecoveryProgress _operation({
  String operationId = 'operation-core-1',
  HandleRecoveryLifecycleClass lifecycleClass =
      HandleRecoveryLifecycleClass.preCommit,
  bool commitAttempted = false,
  HandleRecoveryKeyState keyState = HandleRecoveryKeyState.available,
  bool resultAbsent = false,
  bool readyToCommit = false,
  String? accountUserId = 'account-1',
  String? stateRootFingerprint =
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  HandleRecoveryLocalMigration localMigration =
      HandleRecoveryLocalMigration.supported,
  int unsupportedE2eeGroupCount = 0,
  int unsupportedDidOnlyGroupCount = 0,
}) => HandleRecoveryProgress(
  operationId: operationId,
  ownerIdentityId: 'identity-alice',
  accountUserId: accountUserId,
  handle: 'alice.awiki.info',
  lifecycleClass: lifecycleClass,
  impact: HandleRecoveryImpact(
    localOrdinaryDataWillMigrate: true,
    otherDevicesMustRejoin: true,
    unsupportedE2eeGroupCount: unsupportedE2eeGroupCount,
    unsupportedDidOnlyGroupCount: unsupportedDidOnlyGroupCount,
  ),
  commitAttempted: commitAttempted,
  keyState: keyState,
  resultAbsent: resultAbsent,
  readyToCommit: readyToCommit,
  localMigration: localMigration,
  discardAllowed:
      lifecycleClass == HandleRecoveryLifecycleClass.preCommit &&
      !commitAttempted,
  stateRootFingerprint: stateRootFingerprint,
  createdAt: DateTime.utc(2026, 8, 7),
  updatedAt: DateTime.utc(2026, 8, 7),
);

class _FakeHandleRecoveryCore implements HandleRecoveryCorePort {
  _FakeHandleRecoveryCore({
    HandleRecoveryProgress? operation,
    this.otpResponseOperation,
    this.activateResult,
    this.activateProgressOnError,
    this.activateError,
    this.activateCompleter,
    this.reconcileResult,
    this.receipt,
    this.statusError,
    this.reconcileError,
    this.beforeActivate,
  }) : operation = operation ?? _operation();

  HandleRecoveryProgress operation;
  final HandleRecoveryProgress? otpResponseOperation;
  final HandleRecoveryProgress? activateResult;
  final HandleRecoveryProgress? activateProgressOnError;
  final Object? activateError;
  final Completer<HandleRecoveryProgress>? activateCompleter;
  final HandleRecoveryProgress? reconcileResult;
  final HandleRecoveryRegistryEpochReset? receipt;
  final Object? statusError;
  final Object? reconcileError;
  final FutureOr<void> Function()? beforeActivate;
  HandleRecoveryOwner? lastOwner;
  String? lastHandle;
  String? lastLocalIdentityId;
  String? lastPhone;
  int listCalls = 0;
  int statusCalls = 0;
  int discardCalls = 0;
  int quarantineCalls = 0;
  int activateCalls = 0;
  int reconcileCalls = 0;
  int receiptCalls = 0;

  @override
  Future<HandleRecoveryOtpResult> requestOtp({
    required String handle,
    required String phone,
    String? localIdentityId,
  }) async {
    lastHandle = handle;
    lastLocalIdentityId = localIdentityId;
    lastOwner = HandleRecoveryOwner(
      localIdentityId: localIdentityId ?? operation.ownerIdentityId,
      handle: handle,
    );
    lastPhone = phone;
    operation =
        otpResponseOperation ??
        _operation(accountUserId: null, stateRootFingerprint: null);
    return HandleRecoveryOtpResult(
      operation: operation,
      accepted: true,
      retryAfterSeconds: 60,
      retryAt: DateTime.utc(2026, 8, 7, 0, 1),
    );
  }

  @override
  Future<HandleRecoveryProgress> prepare({
    required String operationId,
    required String phone,
    required String otp,
  }) async {
    operation = _operation(readyToCommit: true);
    return operation;
  }

  @override
  Future<List<HandleRecoveryProgress>> listOperations(
    HandleRecoveryOwner owner,
  ) async {
    listCalls += 1;
    lastOwner = owner;
    return <HandleRecoveryProgress>[operation];
  }

  @override
  Future<HandleRecoveryProgress> getStatus(String operationId) async {
    statusCalls += 1;
    final error = statusError;
    if (error != null) throw error;
    return operation;
  }

  @override
  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required bool userPresenceConfirmed,
  }) async {
    activateCalls += 1;
    await beforeActivate?.call();
    final completer = activateCompleter;
    if (completer != null) {
      operation = await completer.future;
      return operation;
    }
    final progressOnError = activateProgressOnError;
    if (progressOnError != null) operation = progressOnError;
    final error = activateError;
    if (error != null) throw error;
    operation = activateResult ?? operation;
    return operation;
  }

  @override
  Future<HandleRecoveryProgress> reconcile(String operationId) async {
    reconcileCalls += 1;
    final error = reconcileError;
    if (error != null) throw error;
    operation = reconcileResult ?? operation;
    return operation;
  }

  @override
  Future<void> discardPreAttempt(String operationId) async {
    discardCalls += 1;
  }

  @override
  Future<HandleRecoveryProgress> quarantineKeyUnavailable({
    required String operationId,
    required bool confirmed,
  }) async {
    quarantineCalls += 1;
    operation = _operation(
      lifecycleClass: HandleRecoveryLifecycleClass.quarantinedKeyUnavailable,
      commitAttempted: true,
      keyState: HandleRecoveryKeyState.permanentlyUnavailable,
    );
    return operation;
  }

  @override
  Future<HandleRecoveryRegistryEpochReset?> authorizedEpochReceipt(
    HandleRecoveryOwner owner,
  ) async {
    receiptCalls += 1;
    lastOwner = owner;
    return receipt;
  }

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> activateAuthorizedJoin({
    required HandleRecoveryIdentityScope scope,
    required String phone,
    required String otp,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required bool userPresenceConfirmed,
  }) => throw UnimplementedError();

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> resumeAuthorizedJoinActivation({
    required String joinSessionId,
  }) => throw UnimplementedError();
}

class _FakeUserPresence implements UserPresencePort {
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    return true;
  }
}
