part of 'handle_recovery_flow_test.dart';

void _registerHandleRecoveryPresentationTests() {
  test(
    'post-commit confirmation only asks for OTP when Core needs a factor',
    () {
      final operation = _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
        commitAttempted: true,
      );
      final state = HandleRecoveryState(
        authoritative: true,
        progress: operation,
        allowedActions: operation.allowedActions,
      );
      expect(HandleRecoveryPresentation(state).showFactorInput, isFalse);
      expect(
        HandleRecoveryPresentation(state).stage,
        HandleRecoveryViewStage.continuation,
      );
      expect(
        HandleRecoveryPresentation(
          state.copyWith(error: HandleRecoveryUiError.factorRetryRequired),
        ).showFactorInput,
        isTrue,
      );
      expect(
        HandleRecoveryPresentation(
          state.copyWith(authoritative: false),
        ).canRestartPreparation,
        isFalse,
      );
      final factor = _operation(
        lifecycleClass: HandleRecoveryLifecycleClass.remoteUnresolved,
        commitAttempted: true,
        failureCode: HandleRecoveryFailureCode.factorRetryRequired,
      );
      expect(
        HandleRecoveryPresentation(
          HandleRecoveryState(
            authoritative: true,
            progress: factor,
            allowedActions: factor.allowedActions,
            error: HandleRecoveryUiError.failed,
          ),
        ).showFactorInput,
        isTrue,
      );
    },
  );

  testWidgets('blocked OTP phase shows the reason and safely prepares again', (
    tester,
  ) async {
    final operation = _operation(
      failureCode: HandleRecoveryFailureCode.localMigrationUnsupported,
      allowedActionsOverride: const [HandleRecoveryAction.discardPreAttempt],
    );
    final core = _FakeHandleRecoveryCore(
      operation: operation,
      discardCompletes: true,
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: const HandleRecoveryPage(
          initialHandle: 'alice.awiki.info',
          initialPhone: '+8613800138000',
          autoRequestOtp: false,
        ),
        providerOverrides: [
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('handle-recovery-error')), findsOneWidget);
    expect(
      find.textContaining('No recovery commit was attempted'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('handle-recovery-otp')), findsNothing);
    String? diagnostic;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          diagnostic = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.tap(find.byKey(const Key('handle-recovery-copy-diagnostic')));
    expect(diagnostic, contains('stage=blocked; time='));
    expect(diagnostic, isNot(contains('alice')));
    expect(diagnostic, isNot(contains('+8613800138000')));
    final restart = find.byKey(
      const Key('handle-recovery-restart-preparation'),
    );
    await tester.ensureVisible(restart);
    await tester.tap(restart);
    await tester.pumpAndSettle();
    expect(core.discardCalls, 1);
    expect(core.lastPhone, isNull);
    expect(find.byKey(const Key('handle-recovery-error')), findsNothing);
    expect(find.byKey(const Key('handle-recovery-otp')), findsOneWidget);
    expect(find.byKey(const Key('handle-recovery-send-otp')), findsOneWidget);
    expect(core.activateCalls, 0);
  });

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    for (final width in [390.0, 1100.0]) {
      for (final scale in [1.0, 1.6]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          testWidgets(
            'blocked recovery stays readable at $width ${locale.languageCode} $scale $brightness',
            (tester) async {
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              tester.platformDispatcher.platformBrightnessTestValue =
                  brightness;
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              addTearDown(
                tester.platformDispatcher.clearPlatformBrightnessTestValue,
              );
              tester.view.devicePixelRatio = 1;
              tester.view.physicalSize = Size(width, 900);
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final core = _FakeHandleRecoveryCore(
                operation: _operation(
                  failureCode:
                      HandleRecoveryFailureCode.localMigrationUnsupported,
                  allowedActionsOverride: const [
                    HandleRecoveryAction.discardPreAttempt,
                  ],
                ),
              );
              await tester.pumpWidget(
                buildLocalizedTestApp(
                  locale: locale,
                  home: const HandleRecoveryPage(
                    initialHandle: 'alice.awiki.info',
                    initialPhone: '',
                    autoRequestOtp: false,
                  ),
                  providerOverrides: [
                    handleRecoveryCorePortProvider.overrideWithValue(core),
                    userPresencePortProvider.overrideWithValue(
                      _FakeUserPresence(),
                    ),
                  ],
                ),
              );
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('handle-recovery-error')),
                findsOneWidget,
              );
              await tester.scrollUntilVisible(
                find.byKey(const Key('handle-recovery-restart-preparation')),
                200,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expect(
                find.byKey(const Key('handle-recovery-restart-preparation')),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              expect(core.discardCalls, 0);
              expect(core.lastPhone, isNull);
            },
          );
        }
      }
    }
  }

  testWidgets('fresh recovery discloses separate history before confirmation', (
    tester,
  ) async {
    final core = _FakeHandleRecoveryCore(
      operation: _operation(
        readyToCommit: true,
        localOrdinaryDataWillMigrate: false,
      ),
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: const HandleRecoveryPage(
          initialHandle: 'alice.awiki.info',
          initialPhone: '',
          autoRequestOtp: false,
        ),
        providerOverrides: [
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('not automatically carry over'), findsOneWidget);
    expect(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
      findsOneWidget,
    );
    expect(core.activateCalls, 0);
    final details = find.byKey(const Key('handle-recovery-impact-details'));
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(find.text('Hide details'), findsOneWidget);
    expect(core.activateCalls, 0);
  });
}
