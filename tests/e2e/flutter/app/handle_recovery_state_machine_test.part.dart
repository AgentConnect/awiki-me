part of 'handle_recovery_ui_test.dart';

const String _stateMachineTargetCaseId =
    'HANDLE-RECOVERY-STATE-MACHINE-TARGET-E2E-001';
const String _stateMachineResumeCaseId =
    'HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001';
const String _stateMachineRepeatCaseId =
    'HANDLE-RECOVERY-STATE-MACHINE-REPEAT-E2E-001';

void _registerStateMachineRecoveryE2e() {
  testWidgets(
    'real Recovery isolates targets, reenters pending work and recovers after deletion',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final config = _RemoteRecoveryRunConfig.load();
      final account = _DedicatedAccount.fromConfig(config);
      final presence = E2eUserPresencePort();
      _requireFreshRoot(config.appStateRoot);
      AppBootstrap? bootstrap;
      HandleRecoveryCommitCutProxy? proxy;
      _HeldRecoveryPort? held;
      var completedAll = false;
      addTearDown(() async {
        held?.releaseAll();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await proxy?.close();
        // A failed chain may have an unresolved Commit. Keep its isolated root;
        // do not delete evidence or keys merely because the UI test has ended.
        if (completedAll) {
          await _deleteDirectory(config.appStateRoot);
          await _deleteDirectory(config.peerAppStateRoot);
        }
        await tester.binding.setSurfaceSize(null);
      });
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      final environment = _environment(
        config,
        directE2eeEnabled: false,
        groupE2eeEnabled: false,
        agentImEnabled: false,
      );
      bootstrap = await AppBootstrap.create(
        environment: environment,
        appStateRoot: config.appStateRoot,
      );
      final handleA = _uniqueHandle('${config.handlePrefix}a');
      final handleB = _uniqueHandle('${config.handlePrefix}b');
      Future<AppSession> register(String handle) async {
        final factor = await _requestAndResolveRegistrationOtp(
          onboardingSupport: bootstrap!.onboardingSupportService!,
          config: config,
          account: account,
          handle: handle,
        );
        final registered = await bootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: factor.otp,
              handle: handle,
              nickName: 'Recovery isolated fixture',
            );
        if (registered.identity == null ||
            registered.status != IdentityRegistrationStatus.registered) {
          fail('State-machine fixture registration failed.');
        }
        return registered.identity!;
      }

      final identityA = await register(handleA);
      final identityB = await register(handleB);
      await bootstrap.appSessionService!.loginWithIdentity(
        identityA.identityId,
      );
      held = _HeldRecoveryPort(bootstrap.handleRecoveryCorePort!);
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
            handleRecoveryCorePortProvider.overrideWithValue(held),
          ],
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(AppShell).evaluate().length == 1,
        failure: 'Fixture App shell is missing.',
      );
      var appContainer = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      await _pumpUntil(
        tester,
        () => appContainer.read(sessionProvider).session?.did == identityA.did,
        failure: 'Fixture A session did not activate.',
      );
      await _smOpenSettingsRecovery(tester, appContainer, account);
      final operationA = await _smVerifyFactor(
        tester,
        account,
        handleA,
        config.didDomain,
      );
      await _smWaitPrepared(tester);
      proxy = await HandleRecoveryCommitCutProxy.start(
        upstream: Uri.parse(config.userServiceUrl),
        operationId: operationA,
        handle: handleA,
      );
      held.cutOperationId = operationA;
      final originalBootstrap = bootstrap;
      held.activateWithCut = (operation, confirmed) => _smActivateWithNativeCut(
        originalBootstrap,
        config,
        proxy!.endpoint,
        operation,
        confirmed,
      );
      await _smConfirmAndActivate(tester);
      await _pumpUntil(
        tester,
        () =>
            held!.activationReached.isCompleted ||
            held.activationReturned.isCompleted,
        timeout: const Duration(minutes: 2),
        failure: 'The real Commit did not reach its local cut.',
        safeDiagnostic: () {
          final state = _recoveryUiContainer(
            tester,
          ).read(handleRecoveryProvider);
          return '${proxy!.safeDiagnostic},presence=${presence.calls},phase=${state.progress?.phase.name},error=${state.error?.safeCode},code=${state.progress?.lastErrorCode},native=${held!.lastSafeFailure}';
        },
      );
      if (!proxy.committed || !proxy.localCutObserved || presence.calls != 1) {
        fail(
          'The native local cut did not follow one confirmed real Commit (${proxy.safeDiagnostic},native=${held.lastSafeFailure}).',
        );
      }
      await tester.pageBack();
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().isNotEmpty,
        failure: 'Leaving pending Recovery did not return to onboarding.',
      );
      final bCredentials = appContainer
          .read(sessionProvider)
          .localCredentials
          .where((item) => item.handle == identityB.handle)
          .toList();
      if (bCredentials.length != 1) {
        fail('The independent B login credential is missing.');
      }
      await _smTap(
        tester,
        find.byKey(
          Key(
            'onboarding-local-credential-select:${bCredentials.single.credentialName}',
          ),
        ),
      );
      await _pumpUntil(
        tester,
        () => appContainer.read(sessionProvider).session?.did == identityB.did,
        timeout: const Duration(minutes: 1),
        failure: 'Visible B login did not activate B.',
      );
      await _smOpenSettingsRecovery(tester, appContainer, account);
      held.holdNextPrepare = true;
      final operationB = await _smVerifyFactor(
        tester,
        account,
        handleB,
        config.didDomain,
      );
      await _pumpUntil(
        tester,
        () => held!.prepareReached.isCompleted,
        failure:
            'B factor verification did not reach its deterministic return hold.',
      );
      final feedbackBefore = appContainer.read(uiFeedbackProvider)?.id;
      held.activationRelease.complete();
      await _pumpUntil(
        tester,
        () => held!.activationReturned.isCompleted,
        failure: 'The old activation response did not return.',
      );
      await tester.pump();
      final bState = _recoveryUiContainer(tester).read(handleRecoveryProvider);
      if (!bState.isBusy ||
          bState.progress?.operationId != operationB ||
          bState.progress?.handle != identityB.handle ||
          bState.error != null ||
          bState.riskConfirmed ||
          appContainer.read(sessionProvider).session?.did != identityB.did ||
          appContainer.read(uiFeedbackProvider)?.id != feedbackBefore ||
          find.byType(HandleRecoveryPage).evaluate().length != 1) {
        fail('The late A error/finally changed B UI, session or navigation.');
      }
      held.prepareRelease.complete();
      await _smWaitPrepared(tester);
      await E2eCaseAttestationWriter.markPassed(
        _stateMachineTargetCaseId,
        startedAt: startedAt,
        phases: const [
          'real_a_commit_held_after_local_cut',
          'visible_b_login_and_recovery',
          'late_a_error_finally_preserved_b_busy_target',
          'b_session_feedback_navigation_unchanged',
        ],
      );
      await _smTap(tester, find.byKey(const Key('handle-recovery-cancel-otp')));
      await _pumpUntil(
        tester,
        () =>
            !_recoveryUiContainer(tester).read(handleRecoveryProvider).isBusy &&
            _recoveryUiContainer(
                  tester,
                ).read(handleRecoveryProvider).progress ==
                null,
        failure: 'B pre-attempt operation was not explicitly discarded.',
      );
      await tester.pageBack();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      bootstrap = await AppBootstrap.create(
        environment: environment,
        appStateRoot: config.appStateRoot,
      );
      final recording = _RecordingHandleRecoveryCorePort(
        bootstrap.handleRecoveryCorePort!,
      );
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
            handleRecoveryCorePortProvider.overrideWithValue(recording),
          ],
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(AppShell).evaluate().length == 1,
        failure: 'The same native scope did not reopen.',
      );
      appContainer = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      await _pumpUntil(
        tester,
        () => appContainer.read(sessionProvider).session?.did == identityB.did,
        failure: 'B was not preserved across native runtime reopen.',
      );
      await _smLogout(tester, appContainer, delete: false);
      await _smSubmitHandle(
        tester,
        appContainer,
        account,
        handleA,
        config.didDomain,
      );
      await _pumpUntil(
        tester,
        () => find.byType(HandleRecoveryPage).evaluate().length == 1,
        timeout: const Duration(minutes: 1),
        failure: 'Registration did not redirect into the pending Recovery.',
      );
      final pending = _recoveryUiContainer(tester).read(handleRecoveryProvider);
      if (pending.progress?.operationId != operationA ||
          pending.progress?.lifecycleClass !=
              HandleRecoveryLifecycleClass.localTransitionPending ||
          !pending.allows(HandleRecoveryAction.resume) ||
          recording.requestOtpCalls != 0 ||
          pending.riskConfirmed) {
        fail(
          'Cold reentry did not select the exact committed operation before factor actions.',
        );
      }
      await _smTap(tester, find.byKey(const Key('handle-recovery-resume')));
      await _waitForCompletedRecovery(
        tester,
        observedProgress: () => recording.lastProgress,
        coreDiagnostic: () => recording.lastSafeFailure,
      );
      await _smWaitMessages(tester, appContainer, identityA.handle!);
      final recoveredA = appContainer.read(sessionProvider).session!;
      if (recoveredA.did == identityA.did ||
          presence.calls != 1 ||
          recording.requestOtpCalls != 0) {
        fail('Resume performed another first Commit or reused the old DID.');
      }
      await E2eCaseAttestationWriter.markPassed(
        _stateMachineResumeCaseId,
        startedAt: startedAt,
        phases: const [
          'core_reopened_same_scope_with_committed_result',
          'registration_redirected_to_exact_recovery',
          'resume_without_new_factor_or_presence',
          'recovered_session_entered_messages',
        ],
      );
      await _smLogout(tester, appContainer, delete: true);
      final afterDeletion = await bootstrap.appSessionService!
          .listLocalIdentities();
      if (afterDeletion.any((item) => item.handle == identityA.handle) ||
          !afterDeletion.any((item) => item.did == identityB.did)) {
        fail(
          'Visible credential deletion did not preserve the independent Handle.',
        );
      }
      final historical = await recording.inspectContext(
        handle: identityA.handle!,
      );
      if (historical.allowedActions.contains(
            HandleRecoveryAction.activateIdentity,
          ) ||
          !historical.allowedActions.contains(HandleRecoveryAction.startNew)) {
        fail('Deleted history was offered as an active credential.');
      }
      await _smSubmitHandle(
        tester,
        appContainer,
        account,
        handleA,
        config.didDomain,
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('existing-handle-recovery-action'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(minutes: 1),
        failure: 'The deleted Handle did not expose explicit new Recovery.',
      );
      await _smTap(
        tester,
        find.byKey(const Key('existing-handle-recovery-action')),
      );
      await _pumpUntil(
        tester,
        () => find.byType(HandleRecoveryPage).evaluate().length == 1,
        failure: 'Explicit second Recovery did not open.',
      );
      await _smEnsureOtp(tester, appContainer);
      final secondOperation = await _smVerifyFactor(
        tester,
        account,
        handleA,
        config.didDomain,
      );
      await _smWaitPrepared(tester);
      if (secondOperation == operationA ||
          _recoveryUiContainer(
            tester,
          ).read(handleRecoveryProvider).riskConfirmed) {
        fail('Second Recovery reused the old operation or risk confirmation.');
      }
      await _smConfirmAndActivate(tester);
      await _waitForCompletedRecovery(
        tester,
        observedProgress: () => recording.lastProgress,
        coreDiagnostic: () => recording.lastSafeFailure,
      );
      await _smWaitMessages(tester, appContainer, identityA.handle!);
      final secondSession = appContainer.read(sessionProvider).session!;
      final finalIdentities = await bootstrap.appSessionService!
          .listLocalIdentities();
      if (secondSession.did == recoveredA.did ||
          secondSession.did == identityA.did ||
          presence.calls != 2 ||
          !finalIdentities.any((item) => item.did == identityB.did) ||
          finalIdentities
                  .where((item) => item.handle == identityA.handle)
                  .length !=
              1) {
        fail(
          'Second Recovery did not create one new active identity while preserving B.',
        );
      }
      await E2eCaseAttestationWriter.markPassed(
        _stateMachineRepeatCaseId,
        startedAt: startedAt,
        phases: const [
          'visible_current_data_deletion',
          'same_process_provider_tree_reentered',
          'historical_applied_not_login',
          'second_operation_and_confirmation_distinct',
          'second_recovery_entered_messages',
          'independent_handle_preserved',
        ],
      );
      completedAll = true;
    },
  );
}

class _HeldRecoveryPort extends _RecordingHandleRecoveryCorePort {
  _HeldRecoveryPort(super.delegate);
  String? cutOperationId;
  Future<HandleRecoveryProgress> Function(String, bool)? activateWithCut;
  bool holdNextPrepare = false;
  final activationReached = Completer<void>();
  final activationRelease = Completer<void>();
  final activationReturned = Completer<void>();
  final prepareReached = Completer<void>();
  final prepareRelease = Completer<void>();

  @override
  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required bool userPresenceConfirmed,
  }) async {
    if (operationId != cutOperationId) {
      return super.activate(
        operationId: operationId,
        userPresenceConfirmed: userPresenceConfirmed,
      );
    }
    try {
      return await activateWithCut!(operationId, userPresenceConfirmed);
    } catch (error) {
      if (error is! HandleRecoveryFailure ||
          error.code != HandleRecoveryFailureCode.localTransitionPending) {
        lastSafeFailure = error is _RecoveryCutFailure
            ? error.code
            : _safeDiagnosticToken(error.runtimeType.toString());
        rethrow;
      }
      activationReached.complete();
      await activationRelease.future;
      rethrow;
    } finally {
      activationReturned.complete();
    }
  }

  @override
  Future<HandleRecoveryProgress> prepare({
    required String operationId,
    required String phone,
    required String otp,
  }) async {
    final result = await super.prepare(
      operationId: operationId,
      phone: phone,
      otp: otp,
    );
    if (holdNextPrepare) {
      holdNextPrepare = false;
      prepareReached.complete();
      await prepareRelease.future;
    }
    return result;
  }

  void releaseAll() {
    if (!activationRelease.isCompleted) activationRelease.complete();
    if (!prepareRelease.isCompleted) prepareRelease.complete();
  }
}

class _RecoveryCutFailure implements Exception {
  const _RecoveryCutFailure(this.code);
  final String code;
}

Future<HandleRecoveryProgress> _smActivateWithNativeCut(
  AppBootstrap bootstrap,
  _RemoteRecoveryRunConfig config,
  String endpoint,
  String operationId,
  bool confirmed,
) async {
  final paths = AwikiImCorePathLayout.fromStorageScope(
    bootstrap.storageScopeLayout!,
  );
  final secrets = await ScopeAwikiImCoreVaultSecretProvider(
    repository: buildScopeSecretRepository(appStateRoot: config.appStateRoot),
  ).openExisting(paths.scopeId);
  final version = RegExp(
    r'^([^/]+)/([^/]+)/([^+]+)\+(\d+)$',
  ).firstMatch(bootstrap.userServiceHttpClient!.clientVersionHeader!);
  if (version == null) fail('The real App client version is unavailable.');
  final native = await core.AwikiImCore.open(
    config: core.AwikiImCoreConfig(
      serviceBaseUrl: config.baseUrl,
      didDomain: config.didDomain,
      userServiceEndpoint: endpoint,
      messageServiceEndpoint: config.messageServiceUrl,
      mailServiceEndpoint: config.mailServiceUrl,
      clientVersionInfo: core.AwikiClientVersionInfo(
        product: version.group(1)!,
        release: version.group(2)!,
        version: version.group(3)!,
        build: int.parse(version.group(4)!),
      ),
    ),
    paths: paths.toCorePaths(),
    openOptions: core.AwikiImCoreOpenOptions.vaultRequired(
      multiDeviceHandleRecoveryEnabled: true,
      multiDeviceAudience: 'awiki-user-service',
      identitySecretVault: core.ImCoreSecretVaultOptions(
        rootKey: secrets.rootKey,
        vaultDir: paths.vaultDir,
        workspaceId: paths.vaultWorkspaceId,
        deviceId: paths.vaultContextDeviceId,
      ),
    ),
  );
  try {
    final progress = await native.activateHandleRecovery(
      operationId: operationId,
      userPresenceConfirmed: confirmed,
    );
    throw _RecoveryCutFailure(
      'native_returned_${progress.phase.name}_${progress.failureCode?.name ?? 'none'}',
    );
  } on core.AwikiImCoreException catch (error) {
    if (error.handleRecoveryFailureCode !=
        core.HandleRecoveryFailureCode.localTransitionPending) {
      throw _RecoveryCutFailure(
        'native_${_safeDiagnosticToken(error.code)}_${_safeDiagnosticToken(error.serviceCode)}',
      );
    }
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.localTransitionPending,
      retryable: true,
    );
  } finally {
    await native.dispose();
  }
}

Future<void> _smTap(WidgetTester tester, Finder finder) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().length == 1,
    failure: 'The required visible state-machine action is missing.',
  );
  await tester.ensureVisible(finder);
  await tester.pump();
  await _tapOne(
    tester,
    finder,
    failure: 'The state-machine UI action is not hit-testable.',
  );
}

Future<void> _smOpenSettingsRecovery(
  WidgetTester tester,
  ProviderContainer app,
  _DedicatedAccount account,
) async {
  app.read(shellDestinationProvider.notifier).select(ShellDestination.settings);
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().isNotEmpty,
    failure: 'Settings did not open.',
  );
  await _smTap(
    tester,
    find.byKey(const Key('settings-recover-handle-did-row')),
  );
  await _pumpUntil(
    tester,
    () => find.byType(HandleRecoveryPage).evaluate().length == 1,
    failure: 'Settings Recovery did not open.',
  );
  await _enterTextByKey(
    tester,
    const Key('handle-recovery-phone-input'),
    account.phone,
  );
  await _smEnsureOtp(tester, app);
}

Future<void> _smEnsureOtp(WidgetTester tester, ProviderContainer app) async {
  await _pumpUntil(
    tester,
    () => !_recoveryUiContainer(tester).read(handleRecoveryProvider).isBusy,
    timeout: const Duration(minutes: 1),
    failure: 'Recovery context inspection did not finish.',
  );
  if (_recoveryUiContainer(tester).read(handleRecoveryProvider).progress ==
          null ||
      _recoveryUiContainer(tester).read(handleRecoveryProvider).otpPhone ==
          null) {
    await _pumpUntil(
      tester,
      () => app.read(handleRecoverySmsOtpCooldownProvider).canSend,
      timeout: const Duration(minutes: 2),
      failure: 'Recovery SMS retry boundary did not open.',
    );
    await _smTap(tester, find.byKey(const Key('handle-recovery-send-otp')));
  }
  await _pumpUntil(
    tester,
    () => !_recoveryUiContainer(tester).read(handleRecoveryProvider).isBusy,
    timeout: const Duration(minutes: 1),
    failure: 'Recovery OTP did not return.',
  );
  final state = _recoveryUiContainer(tester).read(handleRecoveryProvider);
  if (state.error == HandleRecoveryUiError.rateLimited) {
    await _retryRecoveryOtpAfterRateLimit(tester, app);
  }
  if (!_recoveryUiContainer(tester).read(handleRecoveryProvider).otpRequested) {
    fail('Recovery OTP was not accepted.');
  }
}

Future<String> _smVerifyFactor(
  WidgetTester tester,
  _DedicatedAccount account,
  String handle,
  String domain,
) async {
  final operation = _recoveryUiContainer(
    tester,
  ).read(handleRecoveryProvider).progress?.operationId;
  if (operation == null) fail('Recovery has no exact operation to verify.');
  final otp = await _resolveOtp(
    account: account,
    purpose: _recoveryPurpose,
    handle: handle,
    didDomain: domain,
    operationId: operation,
  );
  await _enterTextByKey(tester, const Key('handle-recovery-otp'), otp);
  await _smTap(tester, find.byKey(const Key('handle-recovery-verify')));
  return operation;
}

Future<void> _smWaitPrepared(WidgetTester tester) => _pumpUntil(
  tester,
  () {
    final state = _recoveryUiContainer(tester).read(handleRecoveryProvider);
    _failOnRecoveryError(state, 'State-machine prepare');
    return !state.isBusy && state.allows(HandleRecoveryAction.activate);
  },
  timeout: const Duration(minutes: 2),
  failure: 'Recovery was not prepared.',
);

Future<void> _smConfirmAndActivate(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byType(HandleRecoveryPage),
        matching: find.byType(Scrollable),
      )
      .first;
  final risk = find.byKey(const Key('handle-recovery-risk-confirmation'));
  await tester.scrollUntilVisible(risk, 250, scrollable: scrollable);
  await _smTap(tester, risk);
  final activate = find.byKey(const Key('handle-recovery-activate'));
  await tester.scrollUntilVisible(activate, 200, scrollable: scrollable);
  await _smTap(tester, activate);
}

Future<void> _smLogout(
  WidgetTester tester,
  ProviderContainer app, {
  required bool delete,
}) async {
  app.read(shellDestinationProvider.notifier).select(ShellDestination.settings);
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().isNotEmpty,
    failure: 'Logout Settings did not open.',
  );
  final settingsContext = tester.element(find.byType(SettingsPage));
  final action = find.descendant(
    of: find.byType(SettingsPage),
    matching: find.text(
      delete
          ? settingsContext.l10n.settingsDeleteCredential
          : settingsContext.l10n.settingsLogout,
    ),
  );
  final scrollable = find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(action, 250, scrollable: scrollable);
  await _smTap(tester, action);
  await _pumpUntil(
    tester,
    () => find.byType(AppConfirmationDialog).evaluate().length == 1,
    failure: 'The destructive-action confirmation is missing.',
  );
  final dialog = tester.widget<AppConfirmationDialog>(
    find.byType(AppConfirmationDialog),
  );
  await _smTap(
    tester,
    find
        .descendant(
          of: find.byType(AppConfirmationDialog),
          matching: find.text(dialog.confirmLabel),
        )
        .last,
  );
  await _pumpUntil(
    tester,
    () =>
        app.read(sessionProvider).session == null &&
        find.byType(OnboardingPage).evaluate().isNotEmpty,
    timeout: const Duration(minutes: 1),
    failure: 'The confirmed logout/deletion did not finish.',
  );
}

Future<void> _smSubmitHandle(
  WidgetTester tester,
  ProviderContainer app,
  _DedicatedAccount account,
  String handle,
  String domain,
) async {
  final fields = find.descendant(
    of: find.byType(OnboardingPage),
    matching: find.byType(CupertinoTextField),
  );
  await _pumpUntil(
    tester,
    () => fields.evaluate().length >= 3,
    failure: 'The unified phone form is unavailable.',
  );
  await tester.enterText(fields.at(0), account.phone);
  await tester.enterText(fields.at(1), handle);
  await _pumpUntil(
    tester,
    () =>
        app.read(smsOtpCooldownProvider).canSend &&
        !app.read(onboardingProvider).isBusy,
    timeout: const Duration(minutes: 2),
    failure: 'Registration SMS retry boundary did not open.',
  );
  await _smTap(tester, find.bySemanticsIdentifier('e2e-send-otp-button'));
  await _pumpUntil(
    tester,
    () => !app.read(onboardingProvider).isBusy,
    timeout: const Duration(minutes: 1),
    failure: 'Registration OTP did not return.',
  );
  if (app.read(uiFeedbackProvider)?.message.id == 'otpRateLimited') {
    await _retryRegistrationOtpAfterRateLimit(tester, app);
  }
  if (app.read(onboardingProvider).otpTargetFullHandle != '$handle.$domain') {
    fail('Registration OTP target was not exact.');
  }
  final otp = await _resolveOtp(
    account: account,
    purpose: _registrationPurpose,
    handle: handle,
    didDomain: domain,
  );
  await tester.enterText(fields.at(2), otp);
  await _smTap(
    tester,
    find.byKey(const Key('onboarding-mac-phone-submit-action')),
  );
}

Future<void> _smWaitMessages(
  WidgetTester tester,
  ProviderContainer app,
  String handle,
) => _pumpUntil(
  tester,
  () {
    final session = app.read(sessionProvider).session;
    return session?.handle == handle &&
        app.read(appRuntimeProvider).activatedDid == session?.did &&
        find.byType(ConversationWorkspacePage).evaluate().isNotEmpty &&
        find.byType(HandleRecoveryPage).evaluate().isEmpty;
  },
  timeout: const Duration(minutes: 2),
  failure: 'Recovery did not activate its exact session and message workspace.',
);
