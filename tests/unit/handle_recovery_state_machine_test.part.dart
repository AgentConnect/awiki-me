part of 'handle_recovery_flow_test.dart';

void _registerHandleRecoveryStateMachineTests() {
  group('Recovery state machine hardening', () {
    testWidgets('late activation cannot replace the next Handle', (
      tester,
    ) async {
      final pendingActivation = Completer<HandleRecoveryProgress>();
      final core = _FakeHandleRecoveryCore(
        operation: _operation(readyToCommit: true),
        activateCompleter: pendingActivation,
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const SizedBox(key: Key('recovery-state-machine-root')),
          gateway: FakeAwikiGateway(),
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('recovery-state-machine-root'))),
      );
      final controller = container.read(handleRecoveryProvider.notifier);
      await controller.restoreForOwner(
        scope: const HandleRecoveryIdentityScope(
          localIdentityId: 'identity-alice',
        ),
        handle: 'alice.awiki.info',
      );
      controller.setRiskConfirmed(true);
      final activation = controller.activate(presenceReason: 'Test recovery');
      await tester.pumpAndSettle();
      expect(core.activateCalls, 1);

      controller.reset();
      core.operation = _stateMachineBobOperation();
      await controller.restoreForOwner(
        scope: const HandleRecoveryIdentityScope(
          localIdentityId: 'identity-bob',
        ),
        handle: 'bob.awiki.info',
      );
      expect(
        container.read(handleRecoveryProvider).progress?.handle,
        'bob.awiki.info',
      );
      pendingActivation.complete(
        _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.applied,
          commitAttempted: true,
        ),
      );
      await activation;

      final state = container.read(handleRecoveryProvider);
      expect(state.owner?.handle, 'bob.awiki.info');
      expect(state.progress?.handle, 'bob.awiki.info');
    });

    testWidgets('reentry restores local transition before requesting OTP', (
      tester,
    ) async {
      final core = _FakeHandleRecoveryCore(
        operation: _operation(
          lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
          commitAttempted: true,
        ),
        otpError: const HandleRecoveryFailure(
          HandleRecoveryFailureCode.unknownEpoch,
        ),
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const HandleRecoveryPage(
            initialHandle: 'alice.awiki.info',
            initialPhone: '+8613800138000',
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
      expect(
        container.read(handleRecoveryProvider).progress?.canResume,
        isTrue,
      );
      expect(core.lastPhone, isNull);
    });

    for (final fails in [false, true]) {
      testWidgets(
        'late activation ${fails ? 'error' : 'success'} and finally cannot clear the next request busy state',
        (tester) async {
          final old = Completer<HandleRecoveryProgress>();
          final next = Completer<HandleRecoveryProgress>();
          final core = _FakeHandleRecoveryCore(
            operation: _operation(readyToCommit: true),
            activateCompleter: old,
            prepareCompleter: next,
          );
          final container = await _stateMachineContainer(tester, core);
          final controller = container.read(handleRecoveryProvider.notifier);
          await controller.initialize(handle: 'alice.awiki.info');
          controller.setRiskConfirmed(true);
          final oldRequest = controller.activate(presenceReason: 'Test');
          await tester.pumpAndSettle();
          expect(core.activateCalls, 1);
          core.operation = _stateMachineBobOperation(prepared: false);
          await controller.initialize(handle: 'bob.awiki.info');
          final nextRequest = controller.prepare(
            phone: '+8613800138000',
            otp: '123456',
          );
          await tester.pump();
          expect(container.read(handleRecoveryProvider).isBusy, isTrue);
          if (fails) {
            old.completeError(StateError('old_failure'));
          } else {
            old.complete(
              _operation(
                lifecycleClass: HandleRecoveryLifecycleClass.applied,
                commitAttempted: true,
              ),
            );
          }
          await oldRequest;
          final current = container.read(handleRecoveryProvider);
          expect(current.isBusy, isTrue);
          expect(current.error, isNull);
          expect(current.riskConfirmed, isFalse);
          expect(current.progress?.handle, 'bob.awiki.info');
          next.complete(_stateMachineBobOperation());
          await nextRequest;
          expect(container.read(handleRecoveryProvider).isBusy, isFalse);
          expect(
            container.read(handleRecoveryProvider).progress?.handle,
            'bob.awiki.info',
          );
        },
      );
    }

    testWidgets(
      'confirmation arriving after target change cannot authorize first commit',
      (tester) async {
        final presenceResult = Completer<bool>();
        final presence = _FakeUserPresence(completer: presenceResult);
        final core = _FakeHandleRecoveryCore(
          operation: _operation(readyToCommit: true),
        );
        final container = await _stateMachineContainer(
          tester,
          core,
          presence: presence,
        );
        final controller = container.read(handleRecoveryProvider.notifier);
        await controller.initialize(handle: 'alice.awiki.info');
        controller.setRiskConfirmed(true);
        final request = controller.activate(presenceReason: 'Test');
        await tester.pumpAndSettle();
        expect(presence.calls, 1);
        core.operation = _stateMachineBobOperation();
        await controller.initialize(handle: 'bob.awiki.info');
        presenceResult.complete(true);
        await request;
        expect(core.activateCalls, 0);
        expect(
          container.read(handleRecoveryProvider).progress?.handle,
          'bob.awiki.info',
        );
      },
    );

    testWidgets(
      'failed authoritative refresh keeps evidence but disables every action',
      (tester) async {
        final core = _FakeHandleRecoveryCore(
          operation: _operation(
            lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
            commitAttempted: true,
          ),
        );
        final container = await _stateMachineContainer(tester, core);
        final controller = container.read(handleRecoveryProvider.notifier);
        await controller.initialize(handle: 'alice.awiki.info');
        expect(
          container
              .read(handleRecoveryProvider)
              .allows(HandleRecoveryAction.resume),
          isTrue,
        );
        core.statusError = const HandleRecoveryFailure(
          HandleRecoveryFailureCode.localStateUnavailable,
        );
        await controller.resume();
        final current = container.read(handleRecoveryProvider);
        expect(
          current.progress?.lifecycleClass,
          HandleRecoveryLifecycleClass.localTransitionPending,
        );
        expect(current.authoritative, isFalse);
        for (final action in HandleRecoveryAction.values) {
          expect(current.allows(action), isFalse);
        }
      },
    );

    test('post-commit failure and expired factor retain distinct UI codes', () {
      expect(
        handleRecoveryUiErrorFrom(
          const HandleRecoveryFailure(
            HandleRecoveryFailureCode.localTransitionPending,
          ),
        ),
        HandleRecoveryUiError.localTransitionPending,
      );
      expect(
        handleRecoveryUiErrorFrom(
          const HandleRecoveryFailure(
            HandleRecoveryFailureCode.factorRetryRequired,
          ),
        ),
        HandleRecoveryUiError.factorRetryRequired,
      );
      const unknown = HandleRecoveryState();
      for (final action in HandleRecoveryAction.values) {
        expect(unknown.allows(action), isFalse);
      }
    });

    for (final sameHandle in [false, true]) {
      testWidgets(
        'covered Recovery route cannot navigate or activate over ${sameHandle ? 'another scope with the same Handle' : 'another Handle'}',
        (tester) async {
          final old = Completer<HandleRecoveryProgress>();
          final coreA = _FakeHandleRecoveryCore(
            operation: _operation(readyToCommit: true),
            activateCompleter: old,
          );
          final coreB = _FakeHandleRecoveryCore(
            operation: sameHandle
                ? _operation(readyToCommit: true)
                : _stateMachineBobOperation(),
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              home: const HandleRecoveryPage(
                initialHandle: 'alice.awiki.info',
                initialPhone: '+8613800138000',
                autoRequestOtp: false,
              ),
              gateway: FakeAwikiGateway(),
              providerOverrides: <Override>[
                handleRecoveryCorePortProvider.overrideWithValue(coreA),
                userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
              ],
            ),
          );
          await tester.pumpAndSettle();
          final contextA = tester.element(
            find.byKey(const Key('handle-recovery-page')),
          );
          final containerA = ProviderScope.containerOf(contextA);
          containerA
              .read(handleRecoveryProvider.notifier)
              .setRiskConfirmed(true);
          await tester.pump();
          expect(
            containerA.read(handleRecoveryProvider).progress?.canActivate,
            isTrue,
          );
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -700),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const Key('handle-recovery-activate')),
          );
          await tester.tap(find.byKey(const Key('handle-recovery-activate')));
          // A live activity indicator must not be settled while Core is held.
          await tester.pump();
          expect(containerA.read(handleRecoveryProvider).isBusy, isTrue);
          expect(coreA.activateCalls, 1);
          unawaited(
            Navigator.of(contextA).push<void>(
              CupertinoPageRoute(
                builder: (_) => ProviderScope(
                  overrides: [
                    handleRecoveryCorePortProvider.overrideWithValue(coreB),
                  ],
                  child: HandleRecoveryPage(
                    initialHandle: sameHandle
                        ? 'alice.awiki.info'
                        : 'bob.awiki.info',
                    initialPhone: '+8613800138000',
                    autoRequestOtp: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final contextB = tester.element(
            find.byKey(const Key('handle-recovery-page')),
          );
          final containerB = ProviderScope.containerOf(contextB);
          expect(coreB.listCalls, greaterThan(0));
          expect(
            identical(
              containerA.read(handleRecoveryProvider.notifier),
              containerB.read(handleRecoveryProvider.notifier),
            ),
            isFalse,
          );
          old.complete(
            _operation(
              lifecycleClass: HandleRecoveryLifecycleClass.applied,
              commitAttempted: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(Navigator.of(contextB).canPop(), isTrue);
          expect(
            containerB.read(handleRecoveryProvider).progress?.handle,
            sameHandle ? 'alice.awiki.info' : 'bob.awiki.info',
          );
          expect(containerB.read(sessionProvider).session, isNull);
          expect(
            containerB.read(handleRecoveryProvider).riskConfirmed,
            isFalse,
          );
          Navigator.of(contextB).pop();
          await tester.pumpAndSettle();
          expect(containerA.read(handleRecoveryProvider).isBusy, isFalse);
          expect(
            containerA
                .read(handleRecoveryProvider)
                .allows(HandleRecoveryAction.activateIdentity),
            isTrue,
          );
          expect(coreA.activateCalls, 1);
          expect(coreA.lastPhone, isNull);
          expect(containerA.read(sessionProvider).session, isNull);
        },
      );
    }

    test('every typed Recovery failure retains its stable diagnostic code', () {
      for (final code in HandleRecoveryFailureCode.values) {
        expect(
          handleRecoveryUiErrorFrom(HandleRecoveryFailure(code)).code,
          code,
        );
      }
    });

    test('resume does not advance an unattempted operation', () async {
      final core = _FakeHandleRecoveryCore(
        operation: _operation(readyToCommit: true),
      );
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
      );
      await expectLater(
        service.resume('operation-core-1'),
        throwsA(isA<HandleRecoveryFailure>()),
      );
      expect(core.reconcileCalls, 0);
    });
  });
}

HandleRecoveryProgress _stateMachineBobOperation({
  bool prepared = true,
}) => HandleRecoveryProgress(
  allowedActions: [
    if (prepared)
      HandleRecoveryAction.activate
    else ...[
      HandleRecoveryAction.prepare,
      HandleRecoveryAction.requestOtp,
    ],
    HandleRecoveryAction.discardPreAttempt,
  ],
  operationId: 'operation-core-bob',
  ownerIdentityId: 'identity-bob',
  accountUserId: 'account-bob',
  handle: 'bob.awiki.info',
  lifecycleClass: HandleRecoveryLifecycleClass.preCommit,
  impact: const HandleRecoveryImpact(
    localOrdinaryDataWillMigrate: true,
    otherDevicesMustRejoin: true,
  ),
  commitAttempted: false,
  keyState: HandleRecoveryKeyState.available,
  resultAbsent: false,
  readyToCommit: prepared,
  localMigration: HandleRecoveryLocalMigration.supported,
  discardAllowed: true,
  stateRootFingerprint:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  createdAt: DateTime.utc(2026, 8, 7),
  updatedAt: DateTime.utc(2026, 8, 7),
);

Future<ProviderContainer> _stateMachineContainer(
  WidgetTester tester,
  _FakeHandleRecoveryCore core, {
  _FakeUserPresence? presence,
}) async {
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: const SizedBox(key: Key('state-machine-controller')),
      gateway: FakeAwikiGateway(),
      providerOverrides: <Override>[
        handleRecoveryCorePortProvider.overrideWithValue(core),
        userPresencePortProvider.overrideWithValue(
          presence ?? _FakeUserPresence(),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byKey(const Key('state-machine-controller'))),
  );
}
