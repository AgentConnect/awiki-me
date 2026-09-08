part of 'handle_recovery_flow_test.dart';

void _registerHandleRecoverySessionTests() {
  for (final failure in ['status', 'presence', 'precommit', 'committed']) {
    testWidgets(
      'session boundary handles $failure failure without guessing commit state',
      (tester) async {
        final session = _ControlledRecoverySession();
        final denied = Completer<bool>()..complete(false);
        final core = _FakeHandleRecoveryCore(
          operation: _operation(readyToCommit: true),
          activateError: failure == 'precommit' || failure == 'committed'
              ? StateError('fixture-activate-failure')
              : null,
          activateProgressOnError: failure == 'committed'
              ? _operation(
                  lifecycleClass:
                      HandleRecoveryLifecycleClass.localTransitionPending,
                  commitAttempted: true,
                )
              : null,
          reconcileError: StateError('fixture-resume-failure'),
        );
        final scope = await _sessionBoundaryScope(
          tester,
          core,
          session,
          presence: _FakeUserPresence(
            completer: failure == 'presence' ? denied : null,
          ),
        );
        if (failure == 'status')
          core.statusError = StateError('fixture-status-failure');
        scope.controller.setRiskConfirmed(true);
        await scope.controller.activate(presenceReason: 'Test');
        expect(scope.container.read(handleRecoveryProvider).isBusy, isFalse);
        if (failure == 'status' || failure == 'presence') {
          expect(session.events, isEmpty);
          expect(core.activateCalls, 0);
          expect(session.currentIdentityId, 'identity-alice');
        } else if (failure == 'precommit') {
          expect(session.events, ['pause', 'restore']);
          expect(session.currentIdentityId, 'identity-alice');
          expect(core.activateCalls, 1);
        } else {
          expect(session.events, ['pause']);
          expect(session.currentIdentityId, isNull);
          expect(core.reconcileCalls, 1);
          expect(
            scope.container
                .read(handleRecoveryProvider)
                .progress!
                .commitAttempted,
            isTrue,
          );
        }
      },
    );
  }

  testWidgets(
    'session restoration keeps busy and blocks duplicate activation',
    (tester) async {
      final restored = Completer<bool>();
      final session = _ControlledRecoverySession()..restoreResult = restored;
      final core = _FakeHandleRecoveryCore(
        operation: _operation(readyToCommit: true),
        activateError: StateError('fixture-not-committed'),
      );
      final scope = await _sessionBoundaryScope(tester, core, session);
      scope.controller.setRiskConfirmed(true);
      final task = scope.controller.activate(presenceReason: 'Test');
      await tester.pump();
      expect(scope.container.read(handleRecoveryProvider).isBusy, isTrue);
      expect(session.events, ['pause', 'restore']);
      await scope.controller.activate(presenceReason: 'Duplicate');
      expect(core.activateCalls, 1);
      restored.complete(true);
      await task;
      expect(scope.container.read(handleRecoveryProvider).isBusy, isFalse);
      expect(session.currentIdentityId, 'identity-alice');
    },
  );

  testWidgets(
    'failed previous-session restoration is visible and releases busy',
    (tester) async {
      final session = _ControlledRecoverySession()
        ..restoreResult = (Completer<bool>()..complete(false));
      final core = _FakeHandleRecoveryCore(
        operation: _operation(readyToCommit: true),
        activateError: StateError('fixture-not-committed'),
      );
      final scope = await _sessionBoundaryScope(tester, core, session);
      scope.controller.setRiskConfirmed(true);
      await scope.controller.activate(presenceReason: 'Test');
      final state = scope.container.read(handleRecoveryProvider);
      expect(state.isBusy, isFalse);
      expect(state.error, HandleRecoveryUiError.failed);
      expect(state.progress!.isCompleted, isFalse);
    },
  );

  testWidgets('a covered page cannot commit after delayed session pause', (
    tester,
  ) async {
    final paused = Completer<void>();
    final session = _ControlledRecoverySession()..pauseResult = paused;
    final core = _FakeHandleRecoveryCore(
      operation: _operation(readyToCommit: true),
    );
    final scope = await _sessionBoundaryScope(tester, core, session);
    scope.controller.setRiskConfirmed(true);
    final task = scope.controller.activate(presenceReason: 'Test');
    await tester.pump();
    expect(session.events, ['pause']);
    scope.controller.invalidate();
    paused.complete();
    await task;
    expect(core.activateCalls, 0);
    expect(session.events, ['pause']);
  });

  testWidgets('manual resume status failure keeps the old session paused', (
    tester,
  ) async {
    final session = _ControlledRecoverySession();
    final core = _FakeHandleRecoveryCore(
      operation: _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
        commitAttempted: true,
      ),
    );
    final scope = await _sessionBoundaryScope(tester, core, session);
    core.statusError = StateError('fixture-status-unavailable');
    await scope.controller.resume();
    expect(session.events, ['pause']);
    expect(session.currentIdentityId, isNull);
    expect(core.reconcileCalls, 0);
    expect(scope.container.read(handleRecoveryProvider).authoritative, isFalse);
  });

  testWidgets('unreadable outcome must not restore old session', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const previousSession = SessionIdentity(
      did: 'did:wba:awiki.info:users:alice-old',
      localIdentityId: 'identity-alice',
      credentialName: 'identity-alice',
      displayName: 'Alice',
      handle: 'alice.awiki.info',
    );
    late _FakeHandleRecoveryCore core;
    core = _FakeHandleRecoveryCore(
      operation: _operation(readyToCommit: true),
      activateError: StateError('fixture-response-lost'),
      beforeActivate: () {
        core.statusError = StateError('fixture-status-unavailable');
      },
    );
    final gateway = _SessionBoundaryLoginGateway()
      ..localCredentials = const [previousSession]
      ..loginResult = previousSession;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
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
    final shell = tester.element(find.byType(AppShell));
    unawaited(
      Navigator.of(shell).push<void>(
        CupertinoPageRoute<void>(
          builder: (_) => const HandleRecoveryPage(
            initialHandle: 'alice.awiki.info',
            initialPhone: '+15555550100',
            autoRequestOtp: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('handle-recovery-activate')));
    await tester.pumpAndSettle();
    expect(core.activateCalls, 1);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('handle-recovery-page'))),
    );
    expect(container.read(handleRecoveryProvider).authoritative, isFalse);
    expect(gateway.restoredIdentities, isEmpty);
  });

  testWidgets('committed waiting hides obsolete factor and submit controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final core = _FakeHandleRecoveryCore(
      operation: _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
        commitAttempted: true,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
        home: const HandleRecoveryPage(
          initialHandle: 'alice.awiki.info',
          initialPhone: '+15555550100',
          autoRequestOtp: false,
        ),
        gateway: FakeAwikiGateway(),
        providerOverrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('handle-recovery-page'))),
    );
    expect(container.read(handleRecoveryProvider).isBusy, isFalse);
    expect(find.byKey(const Key('handle-recovery-otp')), findsNothing);
    expect(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
      findsNothing,
    );
    expect(find.byKey(const Key('handle-recovery-activate')), findsNothing);
    expect(find.text('正在迁移本机身份数据。'), findsNothing);
  });

  testWidgets('manual resume quiesces previous session before Core', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const previousSession = SessionIdentity(
      did: 'did:wba:awiki.info:users:alice-old',
      localIdentityId: 'identity-alice',
      credentialName: 'identity-alice',
      displayName: 'Alice',
      handle: 'alice.awiki.info',
    );
    final core = _FakeHandleRecoveryCore(
      operation: _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
        commitAttempted: true,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('zh'),
        home: const AppShell(),
        gateway: FakeAwikiGateway(),
        session: previousSession,
        providerOverrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final shell = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(shell);
    expect(container.read(sessionProvider).session, isNotNull);
    var quiesced = false;
    core.beforeReconcile = () {
      quiesced = container.read(sessionProvider).session == null;
    };
    unawaited(
      Navigator.of(shell).push<void>(
        CupertinoPageRoute<void>(
          builder: (_) => const HandleRecoveryPage(
            initialHandle: 'alice.awiki.info',
            initialPhone: '+15555550100',
            autoRequestOtp: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final resume = find.byKey(const Key('handle-recovery-resume'));
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();
    expect(core.reconcileCalls, 1);
    expect(quiesced, isTrue);
  });
}

class _SessionBoundaryLoginGateway extends FakeAwikiGateway {
  final restoredIdentities = <String>[];
  @override
  Future<SessionIdentity> loginWithLocalCredential(
    String credentialName,
  ) async {
    restoredIdentities.add(credentialName);
    return super.loginWithLocalCredential(credentialName);
  }
}

Future<({HandleRecoveryController controller, ProviderContainer container})>
_sessionBoundaryScope(
  WidgetTester tester,
  _FakeHandleRecoveryCore core,
  _ControlledRecoverySession session, {
  _FakeUserPresence? presence,
}) async {
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: const HandleRecoveryPage(
        initialHandle: 'alice.awiki.info',
        initialPhone: '+15555550100',
        autoRequestOtp: false,
      ),
      gateway: FakeAwikiGateway(),
      providerOverrides: <Override>[
        handleRecoveryCorePortProvider.overrideWithValue(core),
        handleRecoverySessionProvider.overrideWithValue(session),
        userPresencePortProvider.overrideWithValue(
          presence ?? _FakeUserPresence(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byKey(const Key('handle-recovery-page'))),
  );
  return (
    controller: container.read(handleRecoveryProvider.notifier),
    container: container,
  );
}

class _ControlledRecoverySession implements HandleRecoverySession {
  @override
  String? currentIdentityId = 'identity-alice';
  final events = <String>[];
  Completer<void>? pauseResult;
  Completer<bool>? restoreResult;

  @override
  Future<void> pauseCurrent({required bool Function() isCurrent}) async {
    if (!isCurrent()) return;
    events.add('pause');
    currentIdentityId = null;
    await pauseResult?.future;
  }

  @override
  Future<bool> restorePrevious(
    String identityId, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    events.add('restore');
    final result = await (restoreResult?.future ?? Future.value(true));
    if (!isCurrent() || !result) return false;
    currentIdentityId = identityId;
    return true;
  }
}
