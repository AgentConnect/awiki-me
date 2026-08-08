part of 'multi_device_join_ui_test.dart';

const String _appPairHintLossCaseId = 'DEVICE-MESSAGE-HINT-LOSS-E2E-001';
const String _appPairReconnectCaseId = 'DEVICE-MESSAGE-RECONNECT-E2E-001';
const String _appPairPatchReadyCaseId = 'DEVICE-MESSAGE-PATCH-READY-E2E-001';
const String _appPairDiagnosticsCaseId = 'DEVICE-MESSAGE-DIAGNOSTICS-E2E-001';
const String _appPairGenerationFenceCaseId =
    'DEVICE-MESSAGE-GENERATION-FENCE-E2E-001';

void appPairAdminMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated admin App approves an isolated joining App',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final account = _DedicatedAccount.fromProtectedConfig(
        config.localConfigPath,
      );
      final coordinator = config.coordinator;
      final httpClient = http.Client();
      final presence = E2eUserPresencePort();
      final functionalResources = _AppPairFunctionalAdminResources();
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1320, 820));
      _requireIndependentEmptyPaths(<String>[
        config.adminStateRoot,
        if (config.functional) config.cliWorkspace,
        if (config.functional) config.cliHome,
        if (config.functional) config.daemonStateRoot,
      ]);
      addTearDown(() async {
        await functionalResources.dispose();
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await _deleteDirectory(config.adminStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      _requireAppPairModeMatchesInvocation(config);
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(
          config,
          enableAppPairFunctional: config.functional,
        ),
        appStateRoot: config.adminStateRoot,
      );
      final handle = _uniqueHandle(config.handlePrefix);
      final genesisOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _registrationPurpose,
        handle: handle,
      );
      final IdentityRegistrationResult registration;
      try {
        registration = await bootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: genesisOtp,
              handle: handle,
              nickName: 'AWiki App Pair Admin',
            );
      } on Object {
        fail('The App-pair admin registration failed safely.');
      }
      final adminSession = registration.identity;
      if (registration.status != IdentityRegistrationStatus.registered ||
          adminSession == null ||
          !adminSession.authenticated) {
        fail('The App-pair admin did not obtain an authenticated identity.');
      }
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(adminSession.did);
      final bootstrapAdminDeviceId = _requireAppReadyBootstrapAdmin(
        initialRegistry,
      );

      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
          ],
        ),
      );
      final container = await _waitForAuthenticatedApp(
        tester,
        expectedDid: adminSession.did,
      );
      await _pumpUntil(
        tester,
        () => container
            .read(realtimeConnectionStatusProvider)
            .maybeWhen(
              data: (status) => status == RealtimeConnectionStatus.connected,
              orElse: () => false,
            ),
        timeout: const Duration(seconds: 45),
        failure:
            'The admin App realtime listener was not ready before Join began.',
      );
      if (config.functional) {
        await _prepareAppPairFunctionalHistory(
          config: config,
          account: account,
          httpClient: httpClient,
          bootstrap: bootstrap,
          container: container,
          adminDid: adminSession.did,
          resources: functionalResources,
        );
      }
      await coordinator.publish(
        'admin',
        'ready',
        data: <String, Object?>{
          'did': adminSession.did,
          'handle': handle,
          'adminDeviceId': bootstrapAdminDeviceId,
        },
      );

      final pending = await coordinator.waitFor(
        'joiner',
        'pending',
        timeout: config.functional
            ? const Duration(minutes: 8)
            : const Duration(minutes: 3),
      );
      final joinSessionId = _required(pending, 'joinSessionId');
      final joinedDeviceId = _required(pending, 'joinedDeviceId');
      await _pumpUntil(
        tester,
        () {
          final matches = container
              .read(devicesProvider)
              .visibleJoinRequests
              .where(
                (request) =>
                    request.joinSessionId == joinSessionId &&
                    request.protocolDeviceId == joinedDeviceId,
              )
              .toList(growable: false);
          return matches.length == 1 &&
              matches.single.state == DeviceJoinRemoteState.pending &&
              matches.single.canStartVerification &&
              !matches.single.claimedByCurrentDevice;
        },
        timeout: const Duration(seconds: 60),
        failure:
            'The admin App did not expose the listener-delivered global Join entry.',
      );
      final joinEntry = find.bySemanticsIdentifier('device-join-request-entry');
      await _pumpUntil(
        tester,
        () => joinEntry.hitTestable().evaluate().length == 1,
        timeout: const Duration(seconds: 30),
        failure:
            'The admin App did not render the listener-delivered global Join entry.',
      );
      await _tapOne(
        tester,
        joinEntry,
        failure: 'The admin App global Join review entry was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinApprovalSheet).evaluate().length == 1,
        failure: 'The admin App Join approval sheet did not open.',
      );
      if (container.read(devicesProvider).activeJoin != null) {
        fail('Opening the App-pair request performed an implicit mutation.');
      }
      final startVerification = find.bySemanticsIdentifier(
        'multi-device-start-verification',
      );
      await _pumpUntil(
        tester,
        () =>
            !container.read(devicesProvider).isActionPending &&
            startVerification.hitTestable().evaluate().length == 1,
        failure: 'The App-pair request selection did not settle.',
      );
      final startButton = find.ancestor(
        of: startVerification,
        matching: find.byType(AppPrimaryButton),
      );
      if (startButton.evaluate().length != 1 ||
          tester.widget<AppPrimaryButton>(startButton).onPressed == null) {
        fail('The App-pair verification action was not enabled.');
      }
      await _tapOne(
        tester,
        startButton,
        failure: 'The App-pair verification action was unavailable.',
      );
      final verificationDeadline = DateTime.now().add(
        const Duration(seconds: 90),
      );
      var verificationStarted = false;
      while (!verificationStarted &&
          DateTime.now().isBefore(verificationDeadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        final state = container.read(devicesProvider);
        _failOnDeviceError(
          state,
          'The admin App failed to start Join verification',
        );
        final progress = state.activeJoin;
        final challengeCommitted =
            progress?.phase == DeviceJoinPhase.challengePrepared &&
            progress?.remoteState == DeviceJoinRemoteState.challengeSent &&
            progress?.sas == null;
        final responseAlreadyVerified =
            progress?.phase == DeviceJoinPhase.responseVerified &&
            progress?.remoteState == DeviceJoinRemoteState.responseVerified &&
            _validSas(progress?.sas ?? '');
        verificationStarted =
            progress?.joinSessionId == joinSessionId &&
            progress?.protocolDeviceId == joinedDeviceId &&
            progress?.side == DeviceJoinSide.admin &&
            (challengeCommitted || responseAlreadyVerified);
      }
      if (!verificationStarted) {
        final state = container.read(devicesProvider);
        final progress = state.activeJoin;
        fail(
          'The admin App did not start Join verification exactly once '
          '(actionPending=${state.isActionPending}, '
          'activePhase=${progress?.phase.name ?? 'none'}, '
          'remoteState=${progress?.remoteState.name ?? 'none'}, '
          'error=${state.error?.name ?? 'none'}).',
        );
      }
      await coordinator.publish('admin', 'verification_started');

      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(
            state,
            'The admin App failed to consume the Join response',
          );
          final progress = state.activeJoin;
          return progress?.joinSessionId == joinSessionId &&
              progress?.protocolDeviceId == joinedDeviceId &&
              progress?.phase == DeviceJoinPhase.responseVerified &&
              progress?.remoteState == DeviceJoinRemoteState.responseVerified &&
              _validSas(progress?.sas ?? '');
        },
        timeout: const Duration(seconds: 60),
        failure: 'The admin App did not restore the verified Join response.',
      );
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('device-approval-sas')).evaluate().length == 1,
        failure: 'The admin App did not render its local SAS.',
      );
      final adminSas =
          tester
              .widget<Text>(find.byKey(const Key('device-approval-sas')))
              .data ??
          '';
      if (!_validSas(adminSas) ||
          !await coordinator.submitAndCompareSas(
            'admin',
            adminSas,
            timeout: const Duration(minutes: 2),
          )) {
        fail('The two App processes did not derive the same SAS.');
      }

      final approveAction = find.bySemanticsIdentifier('multi-device-approve');
      if (approveAction.evaluate().isNotEmpty) {
        fail('App-pair approval was enabled before SAS confirmation.');
      }
      final sasSwitch = find.descendant(
        of: find.byKey(const Key('device-sas-confirmation')),
        matching: find.byType(CupertinoSwitch),
      );
      await _tapOne(
        tester,
        sasSwitch,
        failure: 'The App-pair SAS confirmation control was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => approveAction.evaluate().length == 1,
        failure: 'SAS confirmation did not enable App-pair approval.',
      );
      await _tapOne(
        tester,
        approveAction,
        failure: 'The App-pair member approval action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          if (presence.calls > 1) {
            fail('The admin App requested user presence more than once.');
          }
          if (presence.completions == 1 && !presence.lastResult) {
            fail('The App-pair user-presence decision was denied.');
          }
          return presence.completions == 1 && presence.lastResult;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The admin App did not complete E2E-only user presence.',
      );

      final joined = await coordinator.waitFor(
        'joiner',
        'authorized',
        timeout: const Duration(minutes: 2),
      );
      if (_required(joined, 'joinedDeviceId') != joinedDeviceId ||
          _required(joined, 'adminDeviceId') != bootstrapAdminDeviceId) {
        fail('The joining App reported a different Registry identity.');
      }
      final adminRegistry = await _waitForAppRegistry(
        bootstrap.deviceManagementCorePort!,
        did: adminSession.did,
        expectedDeviceCount: 2,
      );
      _requireAppAdminAndMember(
        adminRegistry,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: joinedDeviceId,
      );
      await coordinator.publish('admin', 'complete');
      if (config.functional) {
        await _runAppPairAdminFunctional(
          tester: tester,
          config: config,
          account: account,
          httpClient: httpClient,
          bootstrap: bootstrap,
          container: container,
          adminDid: adminSession.did,
          adminHandle: handle,
          joinedDeviceId: joinedDeviceId,
          resources: functionalResources,
        );
      } else {
        await E2eCaseAttestationWriter.markPassed(
          _appPairCaseId,
          phases: const <String>[
            'two_isolated_app_processes_bootstrapped',
            'joiner_pending_without_sas',
            'admin_global_join_review_entry_received',
            'sas_matched_in_memory_without_evidence',
            'single_e2e_user_presence_confirmed',
            'both_app_registries_converged',
          ],
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

void appPairJoinerMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated joining App completes member Join through visible UI',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final account = _DedicatedAccount.fromProtectedConfig(
        config.localConfigPath,
      );
      final coordinator = config.coordinator;
      final httpClient = http.Client();
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1320, 820));
      _requireIndependentEmptyPaths(<String>[config.joinerStateRoot]);
      _requireAppPairModeMatchesInvocation(config);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await _deleteDirectory(config.joinerStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      final admin = await coordinator.waitFor(
        'admin',
        'ready',
        timeout: config.functional
            ? const Duration(minutes: 8)
            : const Duration(minutes: 3),
      );
      final did = _required(admin, 'did');
      final handle = _required(admin, 'handle');
      final bootstrapAdminDeviceId = _required(admin, 'adminDeviceId');

      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(
          config,
          enableAppPairFunctional: config.functional,
        ),
        appStateRoot: config.joinerStateRoot,
      );
      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await _openNewDeviceJoin(tester);
      final joinOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _joinPurpose,
        handle: handle,
      );
      await _enterText(tester, 'multi-device-join-handle', handle);
      await _enterText(tester, 'multi-device-join-phone', account.phone);
      await _enterText(tester, 'multi-device-join-otp', joinOtp);
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('multi-device-start-join'),
        failure: 'The joining App start action was unavailable.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceJoinPage)),
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The joining App rejected Join');
          final progress = state.activeJoin;
          return progress?.did == did &&
              progress?.side == DeviceJoinSide.newDevice &&
              progress?.phase == DeviceJoinPhase.pending &&
              progress?.remoteState == DeviceJoinRemoteState.pending &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 60),
        failure: 'OTP did not leave the joining App pending without a SAS.',
      );
      final pending = container.read(devicesProvider).activeJoin!;
      await coordinator.publish(
        'joiner',
        'pending',
        data: <String, Object?>{
          'joinSessionId': pending.joinSessionId,
          'joinedDeviceId': pending.protocolDeviceId,
        },
      );
      await coordinator.waitFor(
        'admin',
        'verification_started',
        timeout: const Duration(minutes: 4),
      );
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('device-join-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 60),
        failure: 'The joining App did not derive its local SAS.',
      );
      final joinerSas =
          tester.widget<Text>(find.byKey(const Key('device-join-sas'))).data ??
          '';
      if (!_validSas(joinerSas) ||
          !await coordinator.submitAndCompareSas(
            'joiner',
            joinerSas,
            timeout: const Duration(minutes: 2),
          )) {
        fail('The two App processes did not derive the same SAS.');
      }

      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The joining App failed to activate');
          final progress = state.activeJoin;
          final device = progress?.authorizedDevice;
          return progress?.phase == DeviceJoinPhase.authorized &&
              progress?.remoteState == DeviceJoinRemoteState.consumed &&
              progress?.sas == null &&
              device?.protocolDeviceId == pending.protocolDeviceId &&
              device?.role == DeviceRole.member &&
              device?.managementReady == false &&
              device?.isCurrent == true;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The joining App did not activate as the rootless member.',
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(sessionProvider).session?.did == did &&
            container.read(appRuntimeProvider).activatedDid == did,
        timeout: const Duration(seconds: 60),
        failure: 'The joining App did not activate the exact account DID.',
      );
      final joiningRegistry = await _waitForAppRegistry(
        bootstrap.deviceManagementCorePort!,
        did: did,
        expectedDeviceCount: 2,
      );
      _requireAppCurrentMember(
        joiningRegistry,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: pending.protocolDeviceId,
      );
      await coordinator.publish(
        'joiner',
        'authorized',
        data: <String, Object?>{
          'adminDeviceId': bootstrapAdminDeviceId,
          'joinedDeviceId': pending.protocolDeviceId,
        },
      );
      await coordinator.waitFor(
        'admin',
        'complete',
        timeout: const Duration(minutes: 2),
      );
      if (config.functional) {
        await _runAppPairJoinerFunctional(
          tester: tester,
          config: config,
          bootstrap: bootstrap,
          container: container,
          accountDid: did,
          joinedDeviceId: pending.protocolDeviceId,
        );
      } else {
        await _leaveCompletedAppPairJoin(tester);
        await _deleteJoinedCredentialAndOpenFreshJoin(
          tester: tester,
          bootstrap: bootstrap,
          completedJoinSessionId: pending.joinSessionId,
        );
        await E2eCaseAttestationWriter.markPassed(
          _appPairCredentialResetCaseId,
          phases: const <String>[
            'joined_device_credential_deleted',
            'completed_join_retired_from_local_core',
            'fresh_join_form_visible_without_activation_error',
          ],
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _deleteJoinedCredentialAndOpenFreshJoin({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String completedJoinSessionId,
}) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-settings-tab'),
    failure: 'The joined App settings entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().length == 1,
    failure: 'The joined App settings surface did not open.',
  );
  final deleteCredential = find.byKey(
    const Key('settings-delete-credential-row'),
  );
  await tester.ensureVisible(deleteCredential);
  await _tapOne(
    tester,
    deleteCredential,
    failure: 'The joined App delete-credential action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(AppConfirmationDialog).evaluate().length == 1,
    failure: 'The joined App delete-credential confirmation did not open.',
  );
  final confirmation = find.byType(AppConfirmationDialog);
  final confirmLabel = tester
      .element(confirmation)
      .l10n
      .settingsDeleteCredentialConfirmAction;
  await _tapOne(
    tester,
    find.descendant(of: confirmation, matching: find.text(confirmLabel)),
    failure: 'The joined App delete-credential confirmation was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(OnboardingPage).evaluate().length == 1,
    timeout: const Duration(seconds: 60),
    failure: 'Deleting the joined credential did not return to onboarding.',
  );

  final localSessions = await bootstrap.deviceManagementCorePort!
      .localDeviceJoinSessions();
  if (localSessions.any(
    (session) => session.joinSessionId == completedJoinSessionId,
  )) {
    fail('The completed New Device Join survived local identity retirement.');
  }

  await _openNewDeviceJoin(tester);
  final joinL10n = tester.element(find.byType(DeviceJoinPage)).l10n;
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DeviceJoinPage)),
  );
  await _pumpUntil(
    tester,
    () {
      final state = container.read(devicesProvider);
      return !state.isLoading &&
          !state.isActionPending &&
          state.activeJoin == null &&
          state.error == null &&
          find
                  .bySemanticsIdentifier('multi-device-join-phone')
                  .evaluate()
                  .length ==
              1 &&
          find
                  .bySemanticsIdentifier('multi-device-join-handle')
                  .evaluate()
                  .length ==
              1 &&
          find
                  .bySemanticsIdentifier('multi-device-join-otp')
                  .evaluate()
                  .length ==
              1 &&
          find
                  .bySemanticsIdentifier('multi-device-start-join')
                  .evaluate()
                  .length ==
              1;
    },
    timeout: const Duration(seconds: 60),
    failure: 'The joined App did not return to a fresh, error-free Join form.',
  );
  if (find.byKey(const Key('device-join-error')).evaluate().isNotEmpty ||
      find.text(joinL10n.deviceJoinAuthorized).evaluate().isNotEmpty ||
      find.text(joinL10n.deviceJoinActivationRetry).evaluate().isNotEmpty) {
    fail('The fresh Join page retained a terminal activation failure.');
  }
}

void _requireAppPairModeMatchesInvocation(_AppPairRunConfig config) {
  final expectsFunctional =
      _invocationExpects(_appPairAgentSyncCaseId) ||
      _invocationExpects(_appPairOutboundSyncCaseId) ||
      _invocationExpects(_appPairInboundSyncCaseId) ||
      _invocationExpects(_appPairOnlineSyncV2CaseId) ||
      _invocationExpects(_appPairTailOnlySyncV2CaseId) ||
      _invocationExpects(_appPairReadSyncV2CaseId) ||
      _invocationExpects(_appPairOfflineRecoveryV2CaseId) ||
      _invocationExpects(_appPairHintLossCaseId) ||
      _invocationExpects(_appPairReconnectCaseId) ||
      _invocationExpects(_appPairPatchReadyCaseId) ||
      _invocationExpects(_appPairDiagnosticsCaseId) ||
      _invocationExpects(_appPairGenerationFenceCaseId) ||
      _invocationExpects(_appPairAgentAddSyncCaseId) ||
      _invocationExpects(_appPairAgentRenameSyncCaseId) ||
      _invocationExpects(_appPairAgentDeleteSyncCaseId) ||
      _invocationExpects(_appPairAgentUnbindSyncCaseId) ||
      _invocationExpects(_appPairAgentArchiveSyncCaseId) ||
      _invocationExpects(_appPairProfileSyncCaseId) ||
      _invocationExpects(_appPairRegistrySyncCaseId) ||
      _invocationExpects(_appPairDomainIsolationCaseId);
  final expectsSecurity =
      _invocationExpects(_appPairCaseId) ||
      _invocationExpects(_appPairCredentialResetCaseId);
  if (config.functional != expectsFunctional ||
      config.functional == expectsSecurity ||
      !config.automatedUserPresence) {
    fail(
      'The App-pair run config mixed suite roles or omitted the E2E-only '
      'unattended user-presence control.',
    );
  }
}

Future<void> _runAppPairAdminFunctional({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required _DedicatedAccount account,
  required http.Client httpClient,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String adminDid,
  required String adminHandle,
  required String joinedDeviceId,
  required _AppPairFunctionalAdminResources resources,
}) async {
  await _leaveCompletedAppPairApproval(tester);
  await config.coordinator.waitFor(
    'joiner',
    'functional_ready',
    timeout: const Duration(minutes: 2),
  );

  final peer = resources.peer;
  final peerDid = resources.peerDid;
  final peerHandle = resources.peerHandle;
  final canonicalConversationId = resources.conversationId;
  final historicalMessageId = resources.historicalMessageId;
  final historicalText = resources.historicalText;
  if (peer == null ||
      peerDid == null ||
      peerHandle == null ||
      canonicalConversationId == null ||
      historicalMessageId == null ||
      historicalText == null) {
    fail('The functional pre-Join message fixture was not prepared.');
  }
  await config.coordinator.publish(
    'admin',
    'functional_peer_ready',
    data: <String, Object?>{
      'peerDid': peerDid,
      'peerHandle': peerHandle,
      'conversationId': canonicalConversationId,
      'historicalMessageId': historicalMessageId,
      'historicalText': historicalText,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_tail_only_verified',
    timeout: const Duration(minutes: 2),
  );
  final outboundText = _appPairMessage(config.runId, 'outbound');
  final outbound = await bootstrap.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(
      canonicalConversationId,
    ),
    content: outboundText,
  );
  final outboundId = outbound.remoteId?.trim() ?? '';
  final conversationId = outbound.conversationId?.trim() ?? '';
  if (outboundId.isEmpty ||
      conversationId != canonicalConversationId ||
      outbound.sendState != MessageSendState.sent ||
      !outbound.isMine ||
      outbound.senderDid != adminDid) {
    fail(
      'The admin App did not commit the canonical outbound Direct message '
      '(remote_id=${outboundId.isNotEmpty}, '
      'conversation=${conversationId == canonicalConversationId}, '
      'state=${outbound.sendState.name}, mine=${outbound.isMine}, '
      'sender=${outbound.senderDid == adminDid}).',
    );
  }
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: canonicalConversationId,
    content: outboundText,
    messageId: outboundId,
    senderDid: adminDid,
    receiverDid: peerDid,
    isMine: true,
  );
  await config.coordinator.publish(
    'admin',
    'functional_outbound_sent',
    data: <String, Object?>{
      'conversationId': conversationId,
      'messageId': outboundId,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_own_sync_visible',
    timeout: const Duration(minutes: 2),
  );

  final joinedOutbound = await config.coordinator.waitFor(
    'joiner',
    'functional_joiner_outbound_sent',
    timeout: const Duration(minutes: 2),
  );
  final joinedOutboundId = _required(joinedOutbound, 'messageId');
  final joinedOutboundText = _appPairMessage(config.runId, 'joiner-outbound');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: canonicalConversationId,
    content: joinedOutboundText,
    messageId: joinedOutboundId,
    senderDid: adminDid,
    receiverDid: peerDid,
    isMine: true,
  );
  await _openAppPairConversation(
    tester: tester,
    conversationId: canonicalConversationId,
    content: joinedOutboundText,
  );
  await config.coordinator.publish(
    'admin',
    'functional_joiner_outbound_visible',
  );

  final replyText = _appPairMessage(config.runId, 'reply');
  final replyId = await peer.sendDirectText(to: adminDid, text: replyText);
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: canonicalConversationId,
    content: replyText,
    messageId: replyId,
    senderDid: peerDid,
    receiverDid: adminDid,
    isMine: false,
  );
  await config.coordinator.publish(
    'admin',
    'functional_reply_sent',
    data: <String, Object?>{'messageId': replyId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_reply_visible',
    timeout: const Duration(minutes: 2),
  );
  await _runAppPairAdminReadAndRecovery(
    tester: tester,
    config: config,
    bootstrap: bootstrap,
    container: container,
    peer: peer,
    accountDid: adminDid,
    peerDid: peerDid,
    conversationId: canonicalConversationId,
    joinedDeviceId: joinedDeviceId,
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_agent_observer_ready',
    timeout: const Duration(minutes: 2),
  );

  final install = await _installAppPairDaemon(
    config: config,
    inventory: container.read(agentInventoryPortProvider),
    controllerDid: adminDid,
    controllerHandle: adminHandle,
  );
  resources.daemon = await _startAppPairDaemon(config);
  await _waitForAppPairDaemonReady(config.daemonReadyFile, resources.daemon!);

  await _openAppPairAgentsPage(tester);
  final agents = container.read(agentsProvider.notifier);
  await _waitForAppPairAgent(
    tester: tester,
    container: container,
    agentDid: install.daemonDid,
    handle: install.handle,
    activelyLoad: true,
  );
  await _waitForAppPairDaemonDrivers(
    tester: tester,
    container: container,
    controller: agents,
    daemonDid: install.daemonDid,
  );

  final codexHandle = _appPairRuntimeHandle(config.runId, 'codex');
  const codexDisplayName = 'Pair Codex';
  await agents.createRuntimeAgent(
    install.daemonDid,
    options: RuntimeAgentCreateOptions(
      kind: RuntimeAgentKind.codex,
      handle: codexHandle,
      displayName: codexDisplayName,
    ),
  );
  final codex = await _waitForAppPairRuntime(
    tester: tester,
    container: container,
    daemon: resources.daemon!,
    daemonDid: install.daemonDid,
    handle: codexHandle,
    runtime: RuntimeAgentKind.codex.runtime,
  );

  final claudeHandle = _appPairRuntimeHandle(config.runId, 'claude');
  const claudeDisplayName = 'Pair Claude';
  await agents.createRuntimeAgent(
    install.daemonDid,
    options: RuntimeAgentCreateOptions(
      kind: RuntimeAgentKind.claudeCode,
      handle: claudeHandle,
      displayName: claudeDisplayName,
    ),
  );
  final claude = await _waitForAppPairRuntime(
    tester: tester,
    container: container,
    daemon: resources.daemon!,
    daemonDid: install.daemonDid,
    handle: claudeHandle,
    runtime: RuntimeAgentKind.claudeCode.runtime,
  );
  final archiveHandle = _appPairRuntimeHandle(config.runId, 'archive');
  const archiveDisplayName = 'Pair Archive Fixture';
  await agents.createRuntimeAgent(
    install.daemonDid,
    options: RuntimeAgentCreateOptions(
      kind: RuntimeAgentKind.codex,
      handle: archiveHandle,
      displayName: archiveDisplayName,
    ),
  );
  final archiveFixture = await _waitForAppPairRuntime(
    tester: tester,
    container: container,
    daemon: resources.daemon!,
    daemonDid: install.daemonDid,
    handle: archiveHandle,
    runtime: RuntimeAgentKind.codex.runtime,
  );
  await config.coordinator.publish(
    'admin',
    'functional_agents_created',
    data: <String, Object?>{
      'daemonDid': install.daemonDid,
      'daemonHandle': install.handle,
      'codexDid': codex.agentDid,
      'codexHandle': codexHandle,
      'claudeDid': claude.agentDid,
      'claudeHandle': claudeHandle,
      'archiveDid': archiveFixture.agentDid,
      'archiveHandle': archiveHandle,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_agents_converged',
    timeout: const Duration(minutes: 2),
  );
  final agentPrompt = await config.coordinator.waitFor(
    'joiner',
    'functional_agent_prompt_sent',
    timeout: const Duration(minutes: 2),
  );
  final agentPromptConversationId = _required(agentPrompt, 'conversationId');
  final agentPromptMessageId = _required(agentPrompt, 'messageId');
  final agentPromptText = _appPairMessage(config.runId, 'agent-prompt');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: agentPromptConversationId,
    content: agentPromptText,
    messageId: agentPromptMessageId,
    senderDid: adminDid,
    receiverDid: codex.agentDid,
    isMine: true,
  );
  await _openAppPairConversation(
    tester: tester,
    conversationId: agentPromptConversationId,
    content: agentPromptText,
  );
  await config.coordinator.publish('admin', 'functional_agent_prompt_visible');
  await _runAppPairAdminAccountStateDomains(
    tester: tester,
    config: config,
    bootstrap: bootstrap,
    container: container,
    accountDid: adminDid,
    joinedDeviceId: joinedDeviceId,
    peer: peer,
    peerDid: peerDid,
    conversationId: canonicalConversationId,
    agents: agents,
    codex: codex,
    claude: claude,
    archiveFixture: archiveFixture,
  );
}

Future<void> _runAppPairJoinerFunctional({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
  required String joinedDeviceId,
}) async {
  await _leaveCompletedAppPairJoin(tester);
  await _pumpUntil(
    tester,
    () => container
        .read(realtimeConnectionStatusProvider)
        .maybeWhen(
          data: (status) => status == RealtimeConnectionStatus.connected,
          orElse: () => false,
        ),
    timeout: const Duration(seconds: 45),
    failure:
        'The joining App realtime listener was not ready for functional sync.',
  );
  await config.coordinator.publish('joiner', 'functional_ready');

  final peer = await config.coordinator.waitFor(
    'admin',
    'functional_peer_ready',
    timeout: const Duration(minutes: 2),
  );
  final peerDid = _required(peer, 'peerDid');
  final historicalConversationId = _required(peer, 'conversationId');
  final historicalMessageId = _required(peer, 'historicalMessageId');
  final historicalText = _required(peer, 'historicalText');
  await _pumpUntil(
    tester,
    () {
      final sync = container.read(messageSyncCoordinatorProvider);
      return !sync.isSyncing &&
          sync.lastReason != null &&
          sync.lastStatus != null &&
          !sync.recoveryRequired;
    },
    timeout: const Duration(seconds: 60),
    failure: 'The joining App did not complete its tail-only bootstrap.',
  );
  final historicalConversationVisible = container
      .read(conversationListProvider)
      .conversations
      .any(
        (conversation) =>
            conversation.conversationId == historicalConversationId ||
            conversation.lastMessagePreview == historicalText,
      );
  final historicalMessageVisible = container
      .read(chatThreadProvider(historicalConversationId))
      .messages
      .any(
        (message) =>
            message.localId == historicalMessageId ||
            message.remoteId == historicalMessageId ||
            message.content == historicalText,
      );
  if (historicalConversationVisible || historicalMessageVisible) {
    fail('The joining App received a message committed before device Join.');
  }
  final activeSession = container.read(sessionProvider).session;
  final activeBinding = activeSession?.accountBinding;
  if (activeSession?.did != accountDid ||
      activeBinding == null ||
      activeBinding.currentDid != accountDid ||
      activeBinding.ownerIdentityId.trim().isEmpty ||
      activeBinding.accountId.trim().isEmpty ||
      activeBinding.deviceAuthGeneration.trim().isEmpty) {
    fail('The joining App startup did not establish a bound sync session.');
  }
  final startupPatchObservation = container
      .read(conversationListProvider.notifier)
      .patchStartupObservation;
  if (startupPatchObservation == null ||
      !startupPatchObservation.provesSubscribeBeforeFirstReliableSync) {
    fail(
      'The normal startup path did not prove Patch subscription and committed '
      'reset before its first reliable sync.',
    );
  }
  await config.coordinator.publish('joiner', 'functional_tail_only_verified');
  final outbound = await config.coordinator.waitFor(
    'admin',
    'functional_outbound_sent',
    timeout: const Duration(minutes: 2),
  );
  final conversationId = _required(outbound, 'conversationId');
  final outboundId = _required(outbound, 'messageId');
  final outboundText = _appPairMessage(config.runId, 'outbound');
  await _waitForAppPairConversation(
    tester: tester,
    container: container,
    peerDid: peerDid,
    conversationId: conversationId,
    preview: outboundText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: outboundText,
    messageId: outboundId,
    senderDid: accountDid,
    receiverDid: peerDid,
    isMine: true,
  );
  await _openAppPairConversation(
    tester: tester,
    conversationId: conversationId,
    content: outboundText,
  );
  await container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('e2e_patch_ready_exact_once', immediate: true);
  await _assertAppPairMessageCount(
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: outboundText,
    messageId: outboundId,
    expectedCount: 1,
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairPatchReadyCaseId,
    phases: const <String>[
      'startup_patch_subscription_started',
      'startup_committed_reset_ready_before_first_pull',
      'first_reliable_sync_started_after_patch_ready',
      'post_startup_message_projected_once',
      'repeat_reliable_pull_kept_exact_one',
    ],
  );
  await config.coordinator.publish('joiner', 'functional_own_sync_visible');

  final joinedOutboundText = _appPairMessage(config.runId, 'joiner-outbound');
  final joinedOutbound = await bootstrap.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(conversationId),
    content: joinedOutboundText,
  );
  final joinedOutboundId = joinedOutbound.remoteId?.trim() ?? '';
  if (joinedOutboundId.isEmpty ||
      joinedOutbound.conversationId != conversationId ||
      joinedOutbound.sendState != MessageSendState.sent ||
      !joinedOutbound.isMine ||
      joinedOutbound.senderDid != accountDid) {
    fail('The joining App did not commit its outbound Direct message.');
  }
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: joinedOutboundText,
    messageId: joinedOutboundId,
    senderDid: accountDid,
    receiverDid: peerDid,
    isMine: true,
  );
  await config.coordinator.publish(
    'joiner',
    'functional_joiner_outbound_sent',
    data: <String, Object?>{'messageId': joinedOutboundId},
  );
  await config.coordinator.waitFor(
    'admin',
    'functional_joiner_outbound_visible',
    timeout: const Duration(minutes: 2),
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairOutboundSyncCaseId,
    phases: const <String>[
      'admin_app_outbound_committed',
      'joining_app_conversation_projected',
      'joining_app_own_sync_history_projected',
      'joining_app_message_visible',
      'joining_app_outbound_committed',
      'admin_app_reverse_own_sync_projected',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairTailOnlySyncV2CaseId,
    phases: const <String>[
      'prejoin_message_committed_on_existing_device',
      'new_replica_bootstrap_completed',
      'prejoin_message_absent_on_joining_device',
      'postjoin_message_visible_once',
    ],
  );

  final reply = await config.coordinator.waitFor(
    'admin',
    'functional_reply_sent',
    timeout: const Duration(minutes: 2),
  );
  final replyId = _required(reply, 'messageId');
  final replyText = _appPairMessage(config.runId, 'reply');
  await _waitForAppPairConversation(
    tester: tester,
    container: container,
    peerDid: peerDid,
    conversationId: conversationId,
    preview: replyText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: replyText,
    messageId: replyId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await _pumpUntil(
    tester,
    () => find
        .bySemanticsIdentifier(e2eMessageIdentifier(replyText))
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 60),
    failure: 'The joining App did not render the exact peer reply.',
  );
  await config.coordinator.publish('joiner', 'functional_reply_visible');
  await E2eCaseAttestationWriter.markPassed(
    _appPairInboundSyncCaseId,
    phases: const <String>[
      'cli_peer_reply_committed',
      'admin_app_received_exact_reply',
      'joining_app_conversation_updated',
      'joining_app_incoming_history_projected',
      'joining_app_reply_visible',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairOnlineSyncV2CaseId,
    phases: const <String>[
      'existing_device_outgoing_committed',
      'joining_sibling_outgoing_projected_once',
      'joining_device_outgoing_committed',
      'existing_sibling_reverse_outgoing_projected_once',
      'both_online_devices_received_incoming_once',
    ],
  );

  await _runAppPairJoinerReadAndRecovery(
    tester: tester,
    config: config,
    bootstrap: bootstrap,
    container: container,
    accountDid: accountDid,
    peerDid: peerDid,
    conversationId: conversationId,
    joinedDeviceId: joinedDeviceId,
    preservedMessageId: outboundId,
    preservedMessageText: outboundText,
  );
  await _openAppPairAgentsPage(tester);
  final agentAddBefore = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_agent_add_before',
  );
  await config.coordinator.publish('joiner', 'functional_agent_observer_ready');
  final created = await config.coordinator.waitFor(
    'admin',
    'functional_agents_created',
    timeout: const Duration(minutes: 3),
  );
  final agentAddAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_agent_add_after',
  );
  _requireDomainAdvanced(
    agentAddBefore.domainVersions,
    agentAddAfter.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  final daemon = await _waitForAppPairAgent(
    tester: tester,
    container: container,
    agentDid: _required(created, 'daemonDid'),
    handle: _required(created, 'daemonHandle'),
    activelyLoad: false,
  );
  final codex = await _waitForAppPairAgent(
    tester: tester,
    container: container,
    agentDid: _required(created, 'codexDid'),
    handle: _required(created, 'codexHandle'),
    activelyLoad: false,
  );
  final claude = await _waitForAppPairAgent(
    tester: tester,
    container: container,
    agentDid: _required(created, 'claudeDid'),
    handle: _required(created, 'claudeHandle'),
    activelyLoad: false,
  );
  if (!daemon.isDaemon ||
      !codex.isRuntime ||
      codex.daemonAgentDid != daemon.agentDid ||
      (codex.runtime != RuntimeAgentKind.codex.runtime &&
          codex.runtime != 'generic-cli') ||
      !claude.isRuntime ||
      claude.daemonAgentDid != daemon.agentDid ||
      (claude.runtime != RuntimeAgentKind.claudeCode.runtime &&
          claude.runtime != 'generic-cli')) {
    fail('The joining App did not converge the exact remote Agent topology.');
  }
  await _pumpUntil(
    tester,
    () =>
        find.text(codex.displayName).evaluate().isNotEmpty &&
        find.text(claude.displayName).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
    failure: 'The joining App Agent page did not render both runtime Agents.',
  );
  await config.coordinator.publish('joiner', 'functional_agents_converged');
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentSyncCaseId,
    phases: const <String>[
      'joiner_inventory_observation_started',
      'same_daemon_projected',
      'same_codex_runtime_projected',
      'same_claude_runtime_projected',
      'both_runtime_agents_visible',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentAddSyncCaseId,
    phases: const <String>[
      'admin_app_created_runtime_agents',
      'joining_app_pulled_new_inventory_version',
      'joining_app_projected_exact_added_agents_once',
    ],
  );
  final agentPrompt = await _sendAppPairAgentPromptThroughUi(
    tester: tester,
    container: container,
    messaging: bootstrap.messagingService!,
    agent: codex,
    accountDid: accountDid,
    content: _appPairMessage(config.runId, 'agent-prompt'),
  );
  await config.coordinator.publish(
    'joiner',
    'functional_agent_prompt_sent',
    data: <String, Object?>{
      'conversationId': agentPrompt.conversationId!,
      'messageId': agentPrompt.remoteId!,
    },
  );
  await config.coordinator.waitFor(
    'admin',
    'functional_agent_prompt_visible',
    timeout: const Duration(minutes: 2),
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentMessageSyncCaseId,
    phases: const <String>[
      'joining_app_opened_existing_runtime_agent_chat',
      'joining_app_agent_prompt_committed_default_plain',
      'admin_app_agent_conversation_projected',
      'admin_app_agent_own_sync_visible',
    ],
  );
  await _runAppPairJoinerAccountStateDomains(
    tester: tester,
    config: config,
    bootstrap: bootstrap,
    container: container,
    accountDid: accountDid,
    joinedDeviceId: joinedDeviceId,
    peerDid: peerDid,
    conversationId: conversationId,
  );
}

Future<void> _runAppPairAdminAccountStateDomains({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
  required String joinedDeviceId,
  required _JoinCli peer,
  required String peerDid,
  required String conversationId,
  required AgentsController agents,
  required AgentSummary codex,
  required AgentSummary claude,
  required AgentSummary archiveFixture,
}) async {
  final accountId = _requireAppPairAccountId(container);

  await config.coordinator.waitFor(
    'joiner',
    'account_state_stage4_baseline_ready',
    timeout: const Duration(minutes: 2),
  );
  final renamedCodex = 'Pair Codex ${_safeId(config.runId, 8)}';
  await agents.renameAgent(agentDid: codex.agentDid, displayName: renamedCodex);
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: codex.agentDid,
    displayName: renamedCodex,
  );
  await config.coordinator.publish(
    'admin',
    'account_state_agent_renamed',
    data: <String, Object?>{
      'agentDid': codex.agentDid,
      'displayName': renamedCodex,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_agent_rename_converged',
    timeout: const Duration(minutes: 2),
  );

  agents.select(claude.agentDid);
  await agents.unbindSelected();
  await _waitForAppPairAgentAbsent(
    tester: tester,
    container: container,
    agentDid: claude.agentDid,
  );
  await config.coordinator.publish(
    'admin',
    'account_state_agent_unbound',
    data: <String, Object?>{'agentDid': claude.agentDid},
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_agent_unbind_converged',
    timeout: const Duration(minutes: 2),
  );

  await config.coordinator.publish(
    'admin',
    'account_state_archive_fixture_ready',
    data: <String, Object?>{
      'agentDid': archiveFixture.agentDid,
      'displayName': archiveFixture.displayName,
      'handle': archiveFixture.handle,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_archive_fixture_converged_active',
    timeout: const Duration(minutes: 2),
  );
  agents.select(archiveFixture.agentDid);
  await agents.deleteSelected();
  await _waitForAppPairAgentAbsent(
    tester: tester,
    container: container,
    agentDid: archiveFixture.agentDid,
    timeout: const Duration(minutes: 2),
  );
  await config.coordinator.publish(
    'admin',
    'account_state_archive_product_delete_completed',
    data: <String, Object?>{'agentDid': archiveFixture.agentDid},
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_archive_converged',
    timeout: const Duration(minutes: 2),
  );

  agents.select(codex.agentDid);
  await agents.deleteSelected();
  await _waitForAppPairAgentAbsent(
    tester: tester,
    container: container,
    agentDid: codex.agentDid,
    timeout: const Duration(minutes: 2),
  );
  await config.coordinator.publish(
    'admin',
    'account_state_agent_deleted',
    data: <String, Object?>{'agentDid': codex.agentDid},
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_agent_delete_converged',
    timeout: const Duration(minutes: 2),
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentDeleteSyncCaseId,
    phases: const <String>[
      'admin_app_submitted_real_runtime_delete',
      'admin_app_removed_deleted_runtime_after_authoritative_reconcile',
      'joining_app_confirmed_terminal_inventory_convergence',
    ],
  );

  final beforeProfile = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_profile_before',
  );
  final nickname = 'Pair Profile ${_safeId(config.runId, 10)}';
  final bio = 'account-state-${_safeId(config.runId, 12)}';
  await container
      .read(profileProvider.notifier)
      .updateProfile(ProfilePatch(displayName: nickname, bio: bio));
  await _waitForAppPairProfile(
    tester: tester,
    container: container,
    displayName: nickname,
    bio: bio,
  );
  final afterProfile = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_profile_after',
  );
  _requireOnlyAccountStateDomainAdvanced(
    beforeProfile.domainVersions,
    afterProfile.domainVersions,
    advanced: ProductAccountDomain.profile,
    ignored: const <ProductAccountDomain>{ProductAccountDomain.agentStatus},
  );
  await config.coordinator.publish(
    'admin',
    'account_state_profile_updated',
    data: <String, Object?>{'displayName': nickname, 'bio': bio},
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_profile_converged',
    timeout: const Duration(minutes: 2),
  );

  final isolationAgent = await _runAppPairAccountStateOperator(
    config,
    action: 'agent_add',
    accountId: accountId,
    params: <String, Object?>{'controller_did': accountDid},
    expectedResultKeys: const <String>{
      'agent_did',
      'display_name',
      'active_state',
    },
  );
  final isolationAgentDid = _required(isolationAgent, 'agent_did');
  final isolationOldName = _required(isolationAgent, 'display_name');
  if (isolationAgent['active_state'] != 'active') {
    fail('The Account State isolation Agent did not start active.');
  }
  await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_isolation_fixture',
  );
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: isolationAgentDid,
    displayName: isolationOldName,
  );
  await config.coordinator.publish(
    'admin',
    'account_state_isolation_fixture_ready',
    data: <String, Object?>{
      'agentDid': isolationAgentDid,
      'displayName': isolationOldName,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_isolation_fixture_converged',
    timeout: const Duration(minutes: 2),
  );

  final receiptId = 'receipt-${_nonce(14)}';
  await _runAppPairAccountStateOperator(
    config,
    action: 'account_state_fail_once',
    accountId: accountId,
    params: <String, Object?>{
      'protocol_device_id': joinedDeviceId,
      'domain': 'agent_inventory',
      'ttl_seconds': 60,
      'receipt_id': receiptId,
    },
    expectedResultKeys: const <String>{
      'domain',
      'armed',
      'ttl_seconds',
      'receipt_id',
    },
  );
  final renamedIsolationAgent = await _runAppPairAccountStateOperator(
    config,
    action: 'agent_rename',
    accountId: accountId,
    params: <String, Object?>{'agent_did': isolationAgentDid},
    expectedResultKeys: const <String>{
      'agent_did',
      'display_name',
      'active_state',
    },
  );
  final isolationNewName = _required(renamedIsolationAgent, 'display_name');
  if (_required(renamedIsolationAgent, 'agent_did') != isolationAgentDid ||
      isolationNewName == isolationOldName ||
      renamedIsolationAgent['active_state'] != 'active') {
    fail('The isolation Agent rename receipt was not closed.');
  }
  final isolationNickname = 'Isolation ${_safeId(config.runId, 10)}';
  final isolationProfile = await _runAppPairAccountStateOperator(
    config,
    action: 'profile_update',
    accountId: accountId,
    params: <String, Object?>{'nick_name': isolationNickname},
    expectedResultKeys: const <String>{'nick_name'},
  );
  if (isolationProfile['nick_name'] != isolationNickname) {
    fail('The isolation Profile mutation receipt was not closed.');
  }
  final isolationMessage = _appPairMessage(config.runId, 'domain-isolation');
  final isolationMessageId = await peer.sendDirectText(
    to: accountDid,
    text: isolationMessage,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: isolationMessage,
    messageId: isolationMessageId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await config.coordinator.publish(
    'admin',
    'account_state_isolation_mutated',
    data: <String, Object?>{
      'agentDid': isolationAgentDid,
      'oldDisplayName': isolationOldName,
      'newDisplayName': isolationNewName,
      'profileDisplayName': isolationNickname,
      'messageId': isolationMessageId,
      'receiptId': receiptId,
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_isolation_recovered',
    timeout: const Duration(minutes: 3),
  );

  await container.read(devicesProvider.notifier).loadManagement();
  final registryBefore = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_registry_before',
  );
  final target = container
      .read(devicesProvider)
      .registry
      ?.devices
      .where(
        (device) =>
            device.protocolDeviceId == joinedDeviceId &&
            device.status == DeviceStatus.active &&
            !device.isCurrent,
      )
      .toList(growable: false);
  if (target == null || target.length != 1) {
    fail('The admin App did not resolve the exact active revoke target.');
  }
  await config.coordinator.publish('admin', 'account_state_registry_ready');
  await config.coordinator.waitFor(
    'joiner',
    'account_state_registry_observer_ready',
    timeout: const Duration(minutes: 2),
  );
  final revoked = await container
      .read(devicesProvider.notifier)
      .revokeDevice(
        target: target.single,
        presenceReason: 'AWiki E2E exact sibling revoke',
      );
  if (!revoked) {
    fail('The admin App did not complete the exact sibling revoke.');
  }
  await _pumpUntil(
    tester,
    () {
      final registry = container.read(devicesProvider).registry;
      return registry?.devices
              .where(
                (device) =>
                    device.protocolDeviceId == joinedDeviceId &&
                    device.status == DeviceStatus.revoked,
              )
              .length ==
          1;
    },
    timeout: const Duration(minutes: 2),
    failure: 'The admin App fresh Registry did not confirm sibling revoke.',
  );
  final registryAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_registry_after',
  );
  _requireDomainAdvanced(
    registryBefore.domainVersions,
    registryAfter.domainVersions,
    ProductAccountDomain.deviceRegistry,
  );
  final cachedRegistry = container.read(devicesProvider).cachedRegistry;
  if (cachedRegistry == null ||
      cachedRegistry.devices
              .where(
                (device) =>
                    device.protocolDeviceId == joinedDeviceId &&
                    device.status == DeviceStatus.revoked,
              )
              .length !=
          1) {
    fail('The admin App display cache did not converge the revoked sibling.');
  }
  await config.coordinator.publish('admin', 'account_state_registry_revoked');
  await config.coordinator.waitFor(
    'joiner',
    'account_state_registry_fence_observed',
    timeout: const Duration(minutes: 2),
  );
  final postRevokeText = _appPairMessage(config.runId, 'post-revoke-fence');
  final postRevokeMessageId = await peer.sendDirectText(
    to: accountDid,
    text: postRevokeText,
  );
  await config.coordinator.publish(
    'admin',
    'account_state_post_revoke_message_committed',
    data: <String, Object?>{'messageId': postRevokeMessageId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'account_state_revoked_device_auth_fenced',
    timeout: const Duration(minutes: 2),
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairRegistrySyncCaseId,
    phases: const <String>[
      'admin_security_path_loaded_fresh_registry',
      'admin_revoked_exact_active_sibling_with_user_presence',
      'active_admin_registry_cache_converged_higher_version',
      'revoked_sibling_product_request_was_fenced',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairGenerationFenceCaseId,
    phases: const <String>[
      'revoked_device_binding_captured_before_revoke',
      'same_did_exact_device_revoked',
      'post_revoke_message_committed_for_account',
      'revoked_device_message_not_projected',
      'revoked_device_reliable_pull_auth_fenced',
    ],
  );
}

Future<void> _runAppPairJoinerAccountStateDomains({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
  required String joinedDeviceId,
  required String peerDid,
  required String conversationId,
}) async {
  final preRevokeSessionState = container.read(sessionProvider);
  final preRevokeBinding = preRevokeSessionState.session?.accountBinding;
  if (preRevokeSessionState.session?.did != accountDid ||
      preRevokeBinding == null ||
      preRevokeBinding.currentDid != accountDid ||
      preRevokeBinding.protocolDeviceId != joinedDeviceId ||
      preRevokeBinding.accountId.trim().isEmpty ||
      preRevokeBinding.deviceAuthGeneration.trim().isEmpty) {
    fail('The joining App lacked the exact bound device before revoke.');
  }
  var versions = (await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_stage4_baseline',
  )).domainVersions;
  await config.coordinator.publish(
    'joiner',
    'account_state_stage4_baseline_ready',
  );

  final renamed = await config.coordinator.waitFor(
    'admin',
    'account_state_agent_renamed',
    timeout: const Duration(minutes: 2),
  );
  final renameBefore = versions;
  final renameAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_agent_rename',
  );
  _requireDomainAdvanced(
    renameBefore,
    renameAfter.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  final renamedDid = _required(renamed, 'agentDid');
  final renamedDisplayName = _required(renamed, 'displayName');
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: renamedDid,
    displayName: renamedDisplayName,
  );
  versions = renameAfter.domainVersions;
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentRenameSyncCaseId,
    phases: const <String>[
      'admin_app_renamed_exact_runtime_agent',
      'joining_app_pulled_higher_inventory_version',
      'joining_app_rendered_exact_new_name_without_duplicate',
    ],
  );
  await config.coordinator.publish(
    'joiner',
    'account_state_agent_rename_converged',
  );

  final unbound = await config.coordinator.waitFor(
    'admin',
    'account_state_agent_unbound',
    timeout: const Duration(minutes: 2),
  );
  final unbindAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_agent_unbind',
  );
  _requireDomainAdvanced(
    versions,
    unbindAfter.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  final unboundDid = _required(unbound, 'agentDid');
  await _waitForAppPairAgentAbsent(
    tester: tester,
    container: container,
    agentDid: unboundDid,
  );
  await _waitForCachedAgentState(
    tester: tester,
    container: container,
    agentDid: unboundDid,
    activeState: 'inactive',
  );
  versions = unbindAfter.domainVersions;
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentUnbindSyncCaseId,
    phases: const <String>[
      'admin_app_unbound_exact_runtime_agent',
      'joining_app_cached_authoritative_inactive_row',
      'joining_app_removed_inactive_agent_from_visible_projection',
    ],
  );
  await config.coordinator.publish(
    'joiner',
    'account_state_agent_unbind_converged',
  );

  final archiveFixture = await config.coordinator.waitFor(
    'admin',
    'account_state_archive_fixture_ready',
    timeout: const Duration(minutes: 2),
  );
  final archiveAgentDid = _required(archiveFixture, 'agentDid');
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: archiveAgentDid,
    displayName: _required(archiveFixture, 'displayName'),
  );
  await _waitForCachedAgentState(
    tester: tester,
    container: container,
    agentDid: archiveAgentDid,
    activeState: 'active',
  );
  await config.coordinator.publish(
    'joiner',
    'account_state_archive_fixture_converged_active',
  );
  final archived = await config.coordinator.waitFor(
    'admin',
    'account_state_archive_product_delete_completed',
    timeout: const Duration(minutes: 2),
  );
  if (_required(archived, 'agentDid') != archiveAgentDid) {
    fail('The product runtime delete targeted a different archive fixture.');
  }
  final archiveAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_agent_archive_product_delete',
  );
  _requireDomainAdvanced(
    versions,
    archiveAfter.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  await _waitForAppPairAgentAbsent(
    tester: tester,
    container: container,
    agentDid: archiveAgentDid,
  );
  await _waitForCachedAgentState(
    tester: tester,
    container: container,
    agentDid: archiveAgentDid,
    activeState: 'archived',
  );
  versions = archiveAfter.domainVersions;
  await E2eCaseAttestationWriter.markPassed(
    _appPairAgentArchiveSyncCaseId,
    phases: const <String>[
      'independent_runtime_created_through_product',
      'joining_app_converged_runtime_active',
      'admin_app_submitted_daemon_backed_runtime_delete',
      'joining_app_cached_archived_row_at_higher_inventory_version',
      'joining_app_filtered_archived_runtime_from_visible_projection',
    ],
  );
  await config.coordinator.publish('joiner', 'account_state_archive_converged');

  final deleted = await config.coordinator.waitFor(
    'admin',
    'account_state_agent_deleted',
    timeout: const Duration(minutes: 2),
  );
  final deleteAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_agent_delete',
  );
  _requireDomainAdvanced(
    versions,
    deleteAfter.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  final deletedDid = _required(deleted, 'agentDid');
  await _waitForAppPairAgentAbsent(
    tester: tester,
    container: container,
    agentDid: deletedDid,
  );
  await _waitForCachedAgentState(
    tester: tester,
    container: container,
    agentDid: deletedDid,
    activeState: 'archived',
  );
  versions = deleteAfter.domainVersions;
  await config.coordinator.publish(
    'joiner',
    'account_state_agent_delete_converged',
  );

  final profile = await config.coordinator.waitFor(
    'admin',
    'account_state_profile_updated',
    timeout: const Duration(minutes: 2),
  );
  final profileBefore = versions;
  final profileAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_profile_remote',
  );
  _requireOnlyAccountStateDomainAdvanced(
    profileBefore,
    profileAfter.domainVersions,
    advanced: ProductAccountDomain.profile,
    ignored: const <ProductAccountDomain>{ProductAccountDomain.agentStatus},
  );
  await _waitForAppPairProfile(
    tester: tester,
    container: container,
    displayName: _required(profile, 'displayName'),
    bio: _required(profile, 'bio'),
  );
  versions = profileAfter.domainVersions;
  await E2eCaseAttestationWriter.markPassed(
    _appPairProfileSyncCaseId,
    phases: const <String>[
      'admin_app_committed_profile_mutation',
      'joining_app_profile_version_advanced',
      'joining_app_rendered_exact_profile_snapshot',
      'inventory_and_registry_versions_did_not_advance',
    ],
  );
  final accountStateRequests = container.read(
    accountStateSyncRequestBusProvider,
  );
  final accountStateCoordinator = container.read(
    accountStateSyncCoordinatorProvider.notifier,
  );
  accountStateRequests.detach();
  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.paused);
  await _pumpUntil(
    tester,
    () {
      final state = container.read(accountStateSyncCoordinatorProvider);
      return !state.isSyncing && state.pendingReason == null;
    },
    timeout: const Duration(seconds: 30),
    failure: 'The Account State coordinator did not quiesce before failpoint.',
  );
  await config.coordinator.publish('joiner', 'account_state_profile_converged');

  final fixture = await config.coordinator.waitFor(
    'admin',
    'account_state_isolation_fixture_ready',
    timeout: const Duration(minutes: 2),
  );
  final fixtureAfter = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_isolation_fixture',
  );
  final isolationAgentDid = _required(fixture, 'agentDid');
  final isolationOldName = _required(fixture, 'displayName');
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: isolationAgentDid,
    displayName: isolationOldName,
  );
  versions = fixtureAfter.domainVersions;
  await config.coordinator.publish(
    'joiner',
    'account_state_isolation_fixture_converged',
  );

  final isolation = await config.coordinator.waitFor(
    'admin',
    'account_state_isolation_mutated',
    timeout: const Duration(minutes: 2),
  );
  final isolationBefore = versions;
  final failed = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_domain_isolation_failure',
    allowPartialFailure: true,
  );
  if (failed.domainErrors.keys.toSet().difference(const <ProductAccountDomain>{
        ProductAccountDomain.agentInventory,
      }).isNotEmpty ||
      !failed.domainErrors.containsKey(ProductAccountDomain.agentInventory)) {
    fail('The Account State one-shot failure was not isolated to Inventory.');
  }
  _requireDomainUnchanged(
    isolationBefore,
    failed.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  _requireDomainAdvanced(
    isolationBefore,
    failed.domainVersions,
    ProductAccountDomain.profile,
  );
  await _waitForAppPairProfile(
    tester: tester,
    container: container,
    displayName: _required(isolation, 'profileDisplayName'),
  );
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: isolationAgentDid,
    displayName: _required(isolation, 'oldDisplayName'),
  );
  final isolationText = _appPairMessage(config.runId, 'domain-isolation');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: isolationText,
    messageId: _required(isolation, 'messageId'),
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  final recovered = await _requestAppPairAccountState(
    tester: tester,
    container: container,
    reason: 'e2e_domain_isolation_retry',
  );
  if (recovered.domainErrors.isNotEmpty) {
    fail('The Account State one-shot failure did not recover on retry.');
  }
  _requireDomainAdvanced(
    isolationBefore,
    recovered.domainVersions,
    ProductAccountDomain.agentInventory,
  );
  await _waitForAppPairAgentDisplayName(
    tester: tester,
    container: container,
    agentDid: isolationAgentDid,
    displayName: _required(isolation, 'newDisplayName'),
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairDomainIsolationCaseId,
    phases: const <String>[
      'exact_joining_device_inventory_failpoint_consumed_once',
      'profile_domain_converged_while_inventory_failed',
      'ordinary_message_sync_converged_while_inventory_failed',
      'previous_inventory_snapshot_was_preserved',
      'inventory_retry_converged_and_cleared_domain_error',
    ],
  );
  await config.coordinator.publish(
    'joiner',
    'account_state_isolation_recovered',
  );
  accountStateRequests.attach(
    (reason, {force = false, minimumVersion}) => accountStateCoordinator
        .request(reason, force: force, minimumVersion: minimumVersion),
  );
  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.resumed);

  await config.coordinator.waitFor(
    'admin',
    'account_state_registry_ready',
    timeout: const Duration(minutes: 2),
  );
  final currentRegistry = container.read(devicesProvider).displayRegistry;
  if (currentRegistry == null ||
      currentRegistry.currentDevice?.protocolDeviceId != joinedDeviceId ||
      currentRegistry.currentDevice?.status != DeviceStatus.active) {
    fail('The joining App did not start Registry observation as active.');
  }
  await config.coordinator.publish(
    'joiner',
    'account_state_registry_observer_ready',
  );
  await config.coordinator.waitFor(
    'admin',
    'account_state_registry_revoked',
    timeout: const Duration(minutes: 2),
  );
  var fenced = false;
  try {
    await bootstrap.deviceManagementCorePort!.identityDeviceRegistry(
      accountDid,
    );
  } on Object {
    fenced = true;
  }
  if (!fenced) {
    fail('The revoked joining App retained a successful Registry request.');
  }
  await config.coordinator.publish(
    'joiner',
    'account_state_registry_fence_observed',
  );
  final postRevoke = await config.coordinator.waitFor(
    'admin',
    'account_state_post_revoke_message_committed',
    timeout: const Duration(minutes: 2),
  );
  final postRevokeText = _appPairMessage(config.runId, 'post-revoke-fence');
  final postRevokeMessageId = _required(postRevoke, 'messageId');
  final stillRevokedBinding = container.read(sessionProvider);
  final currentBinding = stillRevokedBinding.session?.accountBinding;
  if (stillRevokedBinding.generation != preRevokeSessionState.generation ||
      currentBinding == null ||
      currentBinding.ownerIdentityId != preRevokeBinding.ownerIdentityId ||
      currentBinding.accountId != preRevokeBinding.accountId ||
      currentBinding.currentDid != preRevokeBinding.currentDid ||
      currentBinding.protocolDeviceId != preRevokeBinding.protocolDeviceId ||
      currentBinding.identityGeneration !=
          preRevokeBinding.identityGeneration ||
      currentBinding.deviceAuthGeneration !=
          preRevokeBinding.deviceAuthGeneration) {
    fail(
      'The revoked-device pull oracle lost the original bound session before '
      'the reliable pull was attempted.',
    );
  }
  await tester.pump(const Duration(seconds: 1));
  await _assertAppPairMessageAbsent(
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: postRevokeText,
    messageId: postRevokeMessageId,
  );
  await container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('e2e_revoked_generation_fence', immediate: true);
  await _pumpUntil(
    tester,
    () {
      final sync = container.read(messageSyncCoordinatorProvider);
      final runtime = container.read(appRuntimeProvider);
      return sync.isAuthRevoked ||
          runtime.authRevoked ||
          container.read(sessionProvider).session == null;
    },
    timeout: const Duration(seconds: 45),
    failure: 'The old auth generation was not fenced from reliable pull.',
  );
  await _assertAppPairMessageAbsent(
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: postRevokeText,
    messageId: postRevokeMessageId,
  );
  await _assertRevokedJoinDoesNotRestoreCompletedSession(tester);
  await config.coordinator.publish(
    'joiner',
    'account_state_revoked_device_auth_fenced',
  );
}

Future<void> _assertRevokedJoinDoesNotRestoreCompletedSession(
  WidgetTester tester,
) async {
  await _openNewDeviceJoin(tester);
  final joinPage = find.byType(DeviceJoinPage);
  final joinL10n = tester.element(joinPage).l10n;
  final container = ProviderScope.containerOf(tester.element(joinPage));
  await _pumpUntil(
    tester,
    () {
      final state = container.read(devicesProvider);
      return !state.isLoading &&
          !state.isActionPending &&
          state.activeJoin == null &&
          state.error == null &&
          find
                  .bySemanticsIdentifier('multi-device-join-phone')
                  .evaluate()
                  .length ==
              1 &&
          find
                  .bySemanticsIdentifier('multi-device-join-handle')
                  .evaluate()
                  .length ==
              1 &&
          find
                  .bySemanticsIdentifier('multi-device-join-otp')
                  .evaluate()
                  .length ==
              1;
    },
    timeout: const Duration(seconds: 60),
    failure:
        'The revoked joining App restored a completed Join instead of a fresh form.',
  );
  if (find.byKey(const Key('device-join-error')).evaluate().isNotEmpty ||
      find.text(joinL10n.deviceJoinAuthorized).evaluate().isNotEmpty ||
      find.text(joinL10n.deviceJoinActivationRetry).evaluate().isNotEmpty) {
    fail('The revoked joining App exposed stale authorized Join state.');
  }
}

Future<AccountStateSyncCoordinatorState> _requestAppPairAccountState({
  required WidgetTester tester,
  required ProviderContainer container,
  required String reason,
  bool allowPartialFailure = false,
}) async {
  final previousCompletedAt = container
      .read(accountStateSyncCoordinatorProvider)
      .lastCompletedAt;
  await container
      .read(accountStateSyncCoordinatorProvider.notifier)
      .request(reason, force: true);
  await _pumpUntil(
    tester,
    () {
      final current = container.read(accountStateSyncCoordinatorProvider);
      return !current.isSyncing &&
          current.pendingReason == null &&
          current.lastCompletedAt != null &&
          current.lastCompletedAt != previousCompletedAt;
    },
    timeout: const Duration(seconds: 30),
    failure: 'The Account State coordinator did not quiesce for $reason.',
  );
  final state = container.read(accountStateSyncCoordinatorProvider);
  if (!allowPartialFailure &&
      (state.status != AccountStateSyncCoordinatorStatus.ready ||
          state.domainErrors.isNotEmpty)) {
    fail('The Account State coordinator failed safely for $reason.');
  }
  if (allowPartialFailure && state.domainErrors.isEmpty) {
    fail('The Account State failure injection was not observed for $reason.');
  }
  for (final domain in ProductAccountDomain.values) {
    final version = state.domainVersions[domain];
    if (version == null || !_isWireDecimal(version)) {
      fail('The Account State coordinator omitted a decimal domain version.');
    }
  }
  return state;
}

bool _isWireDecimal(String value) =>
    RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value);

void _requireDomainAdvanced(
  Map<ProductAccountDomain, String> before,
  Map<ProductAccountDomain, String> after,
  ProductAccountDomain domain,
) {
  final previous = BigInt.tryParse(before[domain] ?? '');
  final current = BigInt.tryParse(after[domain] ?? '');
  if (previous == null || current == null || current <= previous) {
    fail(
      'The expected Account State domain version did not advance '
      '(${domain.name}).',
    );
  }
}

void _requireDomainUnchanged(
  Map<ProductAccountDomain, String> before,
  Map<ProductAccountDomain, String> after,
  ProductAccountDomain domain,
) {
  if (before[domain] == null || before[domain] != after[domain]) {
    fail('An Account State domain version changed unexpectedly.');
  }
}

void _requireOnlyAccountStateDomainAdvanced(
  Map<ProductAccountDomain, String> before,
  Map<ProductAccountDomain, String> after, {
  required ProductAccountDomain advanced,
  Set<ProductAccountDomain> ignored = const <ProductAccountDomain>{},
}) {
  _requireDomainAdvanced(before, after, advanced);
  for (final domain in ProductAccountDomain.values) {
    if (domain == advanced || ignored.contains(domain)) {
      continue;
    }
    _requireDomainUnchanged(before, after, domain);
  }
}

Future<void> _waitForAppPairProfile({
  required WidgetTester tester,
  required ProviderContainer container,
  required String displayName,
  String? bio,
}) async {
  await _pumpUntil(
    tester,
    () {
      final profile = container.read(profileProvider).profile;
      return profile?.displayName == displayName &&
          (bio == null || profile?.bio == bio);
    },
    timeout: const Duration(seconds: 60),
    failure: 'The App-pair Profile projection did not converge exactly.',
  );
}

Future<void> _waitForAppPairAgentDisplayName({
  required WidgetTester tester,
  required ProviderContainer container,
  required String agentDid,
  required String displayName,
}) async {
  try {
    await _pumpUntil(
      tester,
      () {
        final matches = container
            .read(agentsProvider)
            .agents
            .where(
              (agent) =>
                  agent.agentDid == agentDid &&
                  agent.displayName == displayName &&
                  agent.activeState == 'active',
            )
            .toList(growable: false);
        if (matches.length > 1) {
          fail('The App-pair Agent projection contained a duplicate.');
        }
        return matches.length == 1;
      },
      timeout: const Duration(seconds: 90),
      failure: 'The App-pair Agent display name did not converge.',
    );
  } on TestFailure {
    final state = container.read(agentsProvider);
    fail(
      'The App-pair Agent display name did not converge '
      '(error=${_sanitizeAppPairDaemonLine(state.error ?? '<none>')}, '
      'pending=${state.pendingActionKeys.length}).',
    );
  }
}

Future<void> _waitForAppPairAgentAbsent({
  required WidgetTester tester,
  required ProviderContainer container,
  required String agentDid,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await container
        .read(accountStateSyncCoordinatorProvider.notifier)
        .request('e2e_agent_terminal_reconcile', force: true);
    await tester.pump(const Duration(milliseconds: 200));
    final matches = container
        .read(agentsProvider)
        .agents
        .where((agent) => agent.agentDid == agentDid)
        .length;
    if (matches == 0) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The App-pair visible Agent projection retained a terminal Agent.');
}

Future<void> _waitForCachedAgentState({
  required WidgetTester tester,
  required ProviderContainer container,
  required String agentDid,
  required String activeState,
}) async {
  final session = container.read(sessionProvider).session;
  final binding = session?.accountBinding;
  if (binding == null) {
    fail('The App-pair session has no stable Account State binding.');
  }
  final stableBinding = ProductAccountBinding.fromSession(binding);
  final store = container.read(productLocalStoreProvider);
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await store.loadAgentInventorySnapshot(
      binding: stableBinding,
    );
    final matches =
        snapshot?.agents
            .where(
              (item) =>
                  item.agentDid == agentDid && item.activeState == activeState,
            )
            .length ??
        0;
    if (matches > 1) {
      fail('The App-pair cache retained duplicate Agent topology rows.');
    }
    if (matches == 1) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('The App-pair cache did not retain the terminal Agent state.');
}

String _requireAppPairAccountId(ProviderContainer container) {
  final accountId = container
      .read(sessionProvider)
      .session
      ?.accountBinding
      ?.accountId
      .trim();
  if (accountId == null || accountId.isEmpty) {
    fail('The App-pair session has no stable account_id.');
  }
  return accountId;
}

Future<Map<String, Object?>> _runAppPairAccountStateOperator(
  _AppPairRunConfig config, {
  required String action,
  required String accountId,
  required Map<String, Object?> params,
  required Set<String> expectedResultKeys,
}) async {
  _requireAccountStateOperatorEnvironment(config.accountStateOperatorCommand);
  final process = await Process.start(
    config.accountStateOperatorCommand.first,
    config.accountStateOperatorCommand.skip(1).toList(growable: false),
    includeParentEnvironment: true,
    runInShell: false,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(
    jsonEncode(<String, Object?>{
      'schema_version': 1,
      'action': action,
      'account_id': accountId,
      'params': params,
    }),
  );
  await process.stdin.close();
  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(seconds: 60));
  } on TimeoutException {
    process.kill();
    fail('The fixed Account State operator timed out.');
  }
  final stdout = await stdoutFuture;
  final stderr = await stderrFuture;
  if (exitCode != 0 || utf8.encode(stdout).length > 32 * 1024) {
    final safeStderr = utf8.encode(stderr).length <= 4 * 1024
        ? _sanitizeAppPairDaemonLine(stderr.replaceAll(RegExp(r'\s+'), ' '))
        : '<oversized>';
    fail(
      'The fixed Account State operator returned no bounded receipt '
      '(exit=$exitCode, stderr=$safeStderr).',
    );
  }
  Object? decoded;
  try {
    decoded = jsonDecode(stdout);
  } on FormatException {
    fail('The fixed Account State operator returned no closed receipt.');
  }
  if (decoded is! Map) {
    fail('The fixed Account State operator receipt was not an object.');
  }
  final receipt = _stringMap(decoded);
  final resultRaw = receipt['result'];
  if (receipt.length != 4 ||
      receipt['schema_version'] != 1 ||
      receipt['action'] != action ||
      receipt['changed'] != true ||
      resultRaw is! Map) {
    fail('The fixed Account State operator receipt was invalid.');
  }
  final result = _stringMap(resultRaw);
  if (result.keys.toSet().difference(expectedResultKeys).isNotEmpty ||
      expectedResultKeys.difference(result.keys.toSet()).isNotEmpty) {
    fail('The fixed Account State operator result schema was invalid.');
  }
  return result;
}

Future<void> _leaveCompletedAppPairJoin(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(DeviceJoinPage).evaluate().length == 1,
    failure: 'The completed joining-device page was unavailable.',
  );
  final done = find.text(
    tester.element(find.byType(DeviceJoinPage)).l10n.commonDone,
  );
  await _tapOne(
    tester,
    done,
    failure: 'The completed joining-device Done action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DeviceJoinPage).evaluate().isEmpty,
    timeout: const Duration(seconds: 30),
    failure: 'The joining App did not return to the authenticated shell.',
  );
}

Future<void> _leaveCompletedAppPairApproval(WidgetTester tester) async {
  final approval = find.byType(DeviceJoinApprovalSheet);
  await _pumpUntil(
    tester,
    () => approval.evaluate().length == 1,
    failure: 'The completed admin approval page was unavailable.',
  );
  final back = find.descendant(
    of: approval,
    matching: find.byType(TopBarActionButton),
  );
  await _tapOne(
    tester,
    back,
    failure: 'The completed admin approval Back action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => approval.evaluate().isEmpty,
    timeout: const Duration(seconds: 30),
    failure: 'The admin App did not return to the authenticated shell.',
  );
}

class _AppPairFunctionalAdminResources {
  _AppPairDaemonProcess? daemon;
  _JoinCli? peer;
  String? peerDid;
  String? peerHandle;
  String? conversationId;
  String? historicalMessageId;
  String? historicalText;

  Future<void> dispose() async {
    final currentDaemon = daemon;
    daemon = null;
    if (currentDaemon != null && !await _processExited(currentDaemon.process)) {
      currentDaemon.process.kill(ProcessSignal.sigterm);
      try {
        await currentDaemon.process.exitCode.timeout(
          const Duration(seconds: 5),
        );
      } on TimeoutException {
        currentDaemon.process.kill(ProcessSignal.sigkill);
        await currentDaemon.process.exitCode;
      }
    }
    final currentPeer = peer;
    peer = null;
    await currentPeer?.deleteLocalState();
  }
}

Future<void> _prepareAppPairFunctionalHistory({
  required _AppPairRunConfig config,
  required _DedicatedAccount account,
  required http.Client httpClient,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String adminDid,
  required _AppPairFunctionalAdminResources resources,
}) async {
  final peer = _JoinCli.peer(config);
  resources.peer = peer;
  await peer.initialize();
  final peerHandle = _uniqueHandle(config.handlePrefix);
  final peerOtp = await _requestAndResolveOtp(
    client: httpClient,
    config: config,
    account: account,
    purpose: _registrationPurpose,
    handle: peerHandle,
  );
  final peerDid = await peer.registerReadyAdmin(
    handle: peerHandle,
    phone: account.phone,
    otp: peerOtp,
  );
  final peerResolution = await bootstrap.directoryApplicationService!
      .resolvePeer(peerDid);
  final conversationId = peerResolution.conversationId?.trim() ?? '';
  if (peerResolution.did != peerDid ||
      !conversationId.startsWith('dm:peer-scope:v1:')) {
    fail('The admin App did not resolve the functional peer canonically.');
  }
  final historicalText = _appPairMessage(config.runId, 'before-join');
  final historical = await bootstrap.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(conversationId),
    content: historicalText,
  );
  final historicalMessageId = historical.remoteId?.trim() ?? '';
  if (historicalMessageId.isEmpty ||
      historical.conversationId != conversationId ||
      historical.sendState != MessageSendState.sent ||
      !historical.isMine ||
      historical.senderDid != adminDid) {
    fail('The existing App did not commit the pre-Join ordinary message.');
  }
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: historicalText,
    messageId: historicalMessageId,
    senderDid: adminDid,
    receiverDid: peerDid,
    isMine: true,
  );
  resources
    ..peerDid = peerDid
    ..peerHandle = peerHandle
    ..conversationId = conversationId
    ..historicalMessageId = historicalMessageId
    ..historicalText = historicalText;
}

class _AppPairDaemonInstall {
  const _AppPairDaemonInstall({required this.daemonDid, required this.handle});

  final String daemonDid;
  final String handle;
}

Future<_AppPairDaemonInstall> _installAppPairDaemon({
  required _AppPairRunConfig config,
  required AgentInventoryPort inventory,
  required String controllerDid,
  required String controllerHandle,
}) async {
  final token = await inventory.issueDaemonToken(
    controllerDid: controllerDid,
    controllerHandle: controllerHandle,
    clientPlatform: 'darwin-amd64',
  );
  final result = await Process.run(
    config.daemonBinary,
    <String>[
      'install',
      '--token',
      token.token,
      '--base-url',
      config.baseUrl,
      '--no-service',
      '--print-json',
      '--state-root',
      config.daemonStateRoot,
    ],
    environment: _appPairDaemonEnvironment(config),
    includeParentEnvironment: true,
    runInShell: false,
  ).timeout(const Duration(minutes: 2));
  if (result.exitCode != 0) {
    fail(
      'The App-pair daemon install failed safely '
      '(${safeCliFailureDiagnostic(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)}).',
    );
  }
  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is! Map) {
    fail('The App-pair daemon install returned no JSON object.');
  }
  final payload = _stringMap(decoded);
  final daemonDid = payload['daemon_agent_did']?.toString().trim() ?? '';
  final handle =
      payload['handle']?.toString().trim() ?? config.daemonHandle.trim();
  if (daemonDid.isEmpty || handle.isEmpty) {
    fail('The App-pair daemon install returned no safe identity projection.');
  }
  final agentList = await Process.run(
    config.daemonBinary,
    <String>['agent-list', '--state-root', config.daemonStateRoot],
    environment: _appPairDaemonEnvironment(config),
    includeParentEnvironment: true,
    runInShell: false,
  ).timeout(const Duration(seconds: 30));
  if (agentList.exitCode != 0) {
    fail('The App-pair daemon local Agent registry was unreadable.');
  }
  final agentListJson = jsonDecode(agentList.stdout.toString());
  final configuredAgents = agentListJson is Map
      ? agentListJson['agents']
      : null;
  final exactConfigured =
      configuredAgents is List &&
      configuredAgents
              .whereType<Map>()
              .where(
                (agent) =>
                    agent['agent_did']?.toString() == daemonDid &&
                    agent['handle']?.toString() == handle,
              )
              .length ==
          1;
  if (!exactConfigured) {
    fail('The App-pair daemon install did not persist its exact local Agent.');
  }
  return _AppPairDaemonInstall(daemonDid: daemonDid, handle: handle);
}

class _AppPairDaemonProcess {
  _AppPairDaemonProcess(this.process);

  final Process process;
  final List<String> _diagnostics = <String>[];
  late final Future<void> diagnosticsDone;

  void capture(String source, String line) {
    if (_diagnostics.length == 20) _diagnostics.removeAt(0);
    _diagnostics.add('$source:${_sanitizeAppPairDaemonLine(line)}');
  }

  String get safeDiagnostics =>
      _diagnostics.isEmpty ? '<none>' : _diagnostics.join(' | ');

  void attachDiagnostics() {
    diagnosticsDone = Future.wait<void>(<Future<void>>[
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => capture('stdout', line),
            onError: (_) => capture('stdout', '<decode-error>'),
          )
          .asFuture<void>(),
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => capture('stderr', line),
            onError: (_) => capture('stderr', '<decode-error>'),
          )
          .asFuture<void>(),
    ]);
  }
}

Future<_AppPairDaemonProcess> _startAppPairDaemon(
  _AppPairRunConfig config,
) async {
  final ready = File(config.daemonReadyFile);
  if (ready.existsSync()) ready.deleteSync();
  final process = await Process.start(
    config.daemonBinary,
    <String>[
      'foreground',
      '--state-root',
      config.daemonStateRoot,
      '--ready-file',
      config.daemonReadyFile,
      '--max-runtime-ms',
      '1200000',
      '--poll-interval-ms',
      '100',
    ],
    environment: _appPairDaemonEnvironment(config),
    includeParentEnvironment: true,
    runInShell: false,
  );
  final running = _AppPairDaemonProcess(process);
  running.attachDiagnostics();
  return running;
}

Map<String, String> _appPairDaemonEnvironment(_AppPairRunConfig config) {
  final environment = <String, String>{};
  final envPath = config.daemonEnvFile?.trim();
  if (envPath != null && envPath.isNotEmpty) {
    for (final line in File(envPath).readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final equals = trimmed.indexOf('=');
      if (equals <= 0) {
        fail('The App-pair daemon env file is invalid.');
      }
      final key = trimmed.substring(0, equals).trim();
      var value = trimmed.substring(equals + 1).trim();
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
        fail('The App-pair daemon env file contains an invalid key.');
      }
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      environment[key] = value;
    }
  }
  environment.addAll(<String, String>{
    'AWIKI_DAEMON_SERVICE_BASE_URL': config.baseUrl,
    'AWIKI_DAEMON_USER_SERVICE_BASE_URL': config.userServiceUrl,
    'AWIKI_DAEMON_MESSAGE_SERVICE_BASE_URL': config.messageServiceUrl,
    'AWIKI_DAEMON_DID_DOMAIN': config.didDomain,
    'AWIKI_DAEMON_ALLOW_PLAIN_CONTROL': '1',
  });
  return environment;
}

Future<void> _waitForAppPairDaemonReady(
  String path,
  _AppPairDaemonProcess daemon,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    if (await _processExited(daemon.process)) {
      final exitCode = await daemon.process.exitCode;
      try {
        await daemon.diagnosticsDone.timeout(const Duration(seconds: 1));
      } on Object {
        // The bounded diagnostic collected so far is still safe to report.
      }
      fail(
        'The App-pair daemon exited before ready (exit=$exitCode): '
        '${daemon.safeDiagnostics}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('The App-pair daemon did not become ready: ${daemon.safeDiagnostics}');
}

String _sanitizeAppPairDaemonLine(String input) => input
    .replaceAll(RegExp(r'did:[^\s,;]+'), '<did>')
    .replaceAll(RegExp(r'\b[0-9]{6}\b'), '<redacted>')
    .replaceAll(
      RegExp(r'(token|secret|password)=\S+', caseSensitive: false),
      r'$1=<redacted>',
    );

Future<void> _openAppPairAgentsPage(WidgetTester tester) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-agents-tab'),
    failure: 'The App-pair Agents tab was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(AgentsWorkspacePage).evaluate().length == 1,
    timeout: const Duration(seconds: 30),
    failure: 'The App-pair Agents workspace did not open.',
  );
}

Future<ChatMessage> _sendAppPairAgentPromptThroughUi({
  required WidgetTester tester,
  required ProviderContainer container,
  required MessagingService messaging,
  required AgentSummary agent,
  required String accountDid,
  required String content,
}) async {
  container.read(agentsProvider.notifier).select(agent.agentDid);
  await tester.pump(const Duration(milliseconds: 200));
  final workspace = find.byType(AgentsWorkspacePage);
  final openChat = find.text(tester.element(workspace).l10n.agentOpenChat);
  await _tapOne(
    tester,
    openChat,
    failure: 'The joining App runtime Agent chat action was unavailable.',
  );
  final input = find.bySemanticsIdentifier('e2e-chat-input');
  await _pumpUntil(
    tester,
    () => input.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 30),
    failure: 'The joining App runtime Agent chat input was unavailable.',
  );
  await tester.enterText(input, content);
  await tester.pump(const Duration(milliseconds: 100));
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-chat-send-button'),
    failure: 'The joining App runtime Agent send action was unavailable.',
  );
  late final String conversationId;
  final conversationDeadline = DateTime.now().add(const Duration(seconds: 30));
  while (true) {
    final matches = container
        .read(conversationListProvider)
        .conversations
        .where(
          (item) =>
              item.targetDid == agent.agentDid &&
              item.conversationId.startsWith('dm:peer-scope:v1:'),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The joining App projected duplicate runtime Agent conversations.');
    }
    if (matches.length == 1) {
      conversationId = matches.single.conversationId;
      break;
    }
    if (!DateTime.now().isBefore(conversationDeadline)) {
      fail(
        'The joining App did not retain the canonical runtime Agent conversation.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The App-pair messaging service lacks conversation timeline reads.');
  }
  final timeline = messaging as ConversationTimelineMessagingService;
  final conversationRef = AppConversationReadRef.fromConversationId(
    conversationId,
  );
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final messages = await timeline.loadConversationTimeline(
      conversationRef,
      limit: 20,
    );
    final matches = messages
        .where((message) => message.content == content)
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The joining App projected a duplicate runtime Agent prompt.');
    }
    if (matches.length == 1) {
      final message = matches.single;
      final messageId = message.remoteId?.trim() ?? '';
      final conversationId = message.conversationId?.trim() ?? '';
      if (messageId.isNotEmpty &&
          conversationId.startsWith('dm:peer-scope:v1:') &&
          message.senderDid == accountDid &&
          message.receiverDid == agent.agentDid &&
          message.isMine &&
          message.sendState == MessageSendState.sent) {
        await _pumpUntil(
          tester,
          () => find
              .bySemanticsIdentifier(e2eMessageIdentifier(content))
              .evaluate()
              .isNotEmpty,
          timeout: const Duration(seconds: 30),
          failure:
              'The joining App did not render its committed runtime Agent prompt.',
        );
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(
    'The joining App canonical timeline did not commit its default-plain '
    'runtime Agent prompt.',
  );
}

Future<AgentSummary> _waitForAppPairAgent({
  required WidgetTester tester,
  required ProviderContainer container,
  required String agentDid,
  required String handle,
  required bool activelyLoad,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (activelyLoad) {
      await container.read(agentsProvider.notifier).load();
    }
    await tester.pump(const Duration(milliseconds: 200));
    final matches = container
        .read(agentsProvider)
        .agents
        .where((agent) => agent.agentDid == agentDid && agent.handle == handle)
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The App-pair Agent inventory projected a duplicate exact Agent.');
    }
    if (matches.length == 1) return matches.single;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The App-pair Agent inventory did not converge $agentDid/$handle.');
}

Future<void> _waitForAppPairDaemonDrivers({
  required WidgetTester tester,
  required ProviderContainer container,
  required AgentsController controller,
  required String daemonDid,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await controller.load();
    controller.select(daemonDid);
    await controller.refreshDaemonStatus(daemonDid);
    await tester.pump(const Duration(milliseconds: 200));
    final daemonMatches = container
        .read(agentsProvider)
        .agents
        .where((agent) => agent.agentDid == daemonDid)
        .toList(growable: false);
    final daemon = daemonMatches.isEmpty ? null : daemonMatches.single;
    final configSummary = daemon?.latest.diagnosticsSummary['config_summary'];
    final genericCli = configSummary is Map
        ? configSummary['generic_cli']
        : null;
    if (daemon != null &&
        container.read(agentsProvider).canCreateRuntimeAgent(daemon) &&
        genericCli is Map &&
        genericCli['capability_schema_version']?.toString() == '1') {
      final drivers = genericCli['supported_drivers'];
      if (drivers is List &&
          drivers.map((value) => value.toString()).contains('codex') &&
          drivers.map((value) => value.toString()).contains('claude-code')) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
  }
  fail('The App-pair daemon did not report Codex and Claude Code drivers.');
}

Future<void> _runAppPairAdminReadAndRecovery({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required _JoinCli peer,
  required String accountDid,
  required String peerDid,
  required String conversationId,
  required String joinedDeviceId,
}) async {
  await _openAppPairAgentsPage(tester);
  await config.coordinator.publish('admin', 'functional_read_observer_ready');
  await config.coordinator.waitFor(
    'joiner',
    'functional_read_observer_ready',
    timeout: const Duration(minutes: 2),
  );

  final readText = _appPairMessage(config.runId, 'read-sync');
  final readMessageId = await peer.sendDirectText(
    to: accountDid,
    text: readText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: readText,
    messageId: readMessageId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count > 0,
    failure: 'The admin App did not project the read-sync message as unread.',
  );
  await config.coordinator.publish(
    'admin',
    'functional_read_message_sent',
    data: <String, Object?>{'messageId': readMessageId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_read_unread_visible',
    timeout: const Duration(minutes: 2),
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_read_committed',
    timeout: const Duration(minutes: 2),
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count == 0,
    failure: 'The admin App did not converge the sibling read watermark.',
  );

  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.paused);
  await container.read(realtimeApplicationServiceProvider).stop();
  await _resumeAppPairAndWaitForSync(
    tester: tester,
    container: container,
    failure: 'The admin App did not finish its duplicate/reconnect sync.',
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count == 0,
    failure: 'Duplicate sync regressed the admin App read watermark.',
  );
  await config.coordinator.publish('admin', 'functional_read_converged');

  await _runAppPairAdminHintLossAndReconnect(
    tester: tester,
    bootstrap: bootstrap,
    container: container,
    peer: peer,
    accountDid: accountDid,
    peerDid: peerDid,
    conversationId: conversationId,
    runId: config.runId,
  );

  await config.coordinator.waitFor(
    'joiner',
    'functional_offline_ready',
    timeout: const Duration(minutes: 2),
  );
  final recoveryText = _appPairMessage(config.runId, 'offline-recovery');
  final recoveryMessageId = await peer.sendDirectText(
    to: accountDid,
    text: recoveryText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: recoveryText,
    messageId: recoveryMessageId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count > 0,
    failure: 'The admin App did not project the offline message as unread.',
  );
  await _openAppPairConversation(
    tester: tester,
    conversationId: conversationId,
    content: recoveryText,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count == 0,
    failure: 'The admin App did not commit the offline-message read state.',
  );
  await _forceAppPairRetentionGap(joinedDeviceId);
  await config.coordinator.publish(
    'admin',
    'functional_recovery_gap_prepared',
    data: <String, Object?>{'messageId': recoveryMessageId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_recovery_completed',
    timeout: const Duration(minutes: 3),
  );

  final postAnchorText = _appPairMessage(config.runId, 'post-anchor');
  final postAnchorId = await peer.sendDirectText(
    to: accountDid,
    text: postAnchorText,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: postAnchorText,
    messageId: postAnchorId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await config.coordinator.publish(
    'admin',
    'functional_post_anchor_sent',
    data: <String, Object?>{'messageId': postAnchorId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_post_anchor_visible',
    timeout: const Duration(minutes: 2),
  );
  await _openAppPairAgentsPage(tester);
}

Future<void> _runAppPairAdminHintLossAndReconnect({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required _JoinCli peer,
  required String accountDid,
  required String peerDid,
  required String conversationId,
  required String runId,
}) async {
  await _pumpUntil(
    tester,
    () {
      final sync = container.read(messageSyncCoordinatorProvider);
      return !sync.isSyncing && sync.pendingReason == null;
    },
    timeout: const Duration(seconds: 30),
    failure: 'The admin App sync queue did not quiesce before hint loss.',
  );
  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.paused);
  await container.read(realtimeApplicationServiceProvider).stop();
  if (container.read(realtimeApplicationServiceProvider).isRunning) {
    fail('The normal WebSocket did not stop before the reconnect gap.');
  }

  final gapText = _appPairMessage(runId, 'hint-loss-reconnect-gap');
  final gapMessageId = await peer.sendDirectText(to: accountDid, text: gapText);
  await tester.pump(const Duration(milliseconds: 750));
  await _assertAppPairMessageAbsent(
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: gapText,
    messageId: gapMessageId,
  );

  await _resumeAppPairAndWaitForSync(
    tester: tester,
    container: container,
    failure: 'The active admin App did not run reconnect HTTP reconciliation.',
  );
  await _pumpUntil(
    tester,
    () => container
        .read(realtimeConnectionStatusProvider)
        .maybeWhen(
          data: (status) => status == RealtimeConnectionStatus.connected,
          orElse: () => false,
        ),
    timeout: const Duration(seconds: 45),
    failure: 'The active admin App did not reconnect its normal WebSocket.',
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: gapText,
    messageId: gapMessageId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await _assertAppPairMessageCount(
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: gapText,
    messageId: gapMessageId,
    expectedCount: 1,
  );

  await E2eCaseAttestationWriter.markPassed(
    _appPairHintLossCaseId,
    phases: const <String>[
      'realtime_hint_channel_stopped_before_commit',
      'ordinary_message_committed_while_hint_unobservable',
      'foreground_http_reconcile_started',
      'reliable_message_projected_once',
      'repeat_local_read_kept_single_projection',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairReconnectCaseId,
    phases: const <String>[
      'normal_websocket_disconnect_completed',
      'active_device_reconnect_completed',
      'disconnect_gap_pulled_from_reliable_http',
      'post_reconnect_projection_exact_once',
    ],
  );
}

Future<void> _runAppPairJoinerReadAndRecovery({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
  required String peerDid,
  required String conversationId,
  required String joinedDeviceId,
  required String preservedMessageId,
  required String preservedMessageText,
}) async {
  await _openAppPairAgentsPage(tester);
  await config.coordinator.publish('joiner', 'functional_read_observer_ready');
  await config.coordinator.waitFor(
    'admin',
    'functional_read_observer_ready',
    timeout: const Duration(minutes: 2),
  );
  final read = await config.coordinator.waitFor(
    'admin',
    'functional_read_message_sent',
    timeout: const Duration(minutes: 2),
  );
  final readMessageId = _required(read, 'messageId');
  final readText = _appPairMessage(config.runId, 'read-sync');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: readText,
    messageId: readMessageId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count > 0,
    failure: 'The joining App did not project the read-sync message as unread.',
  );
  await config.coordinator.publish('joiner', 'functional_read_unread_visible');
  await _openAppPairConversation(
    tester: tester,
    conversationId: conversationId,
    content: readText,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count == 0,
    failure: 'The joining App did not commit its visible read watermark.',
  );
  await config.coordinator.publish('joiner', 'functional_read_committed');
  await config.coordinator.waitFor(
    'admin',
    'functional_read_converged',
    timeout: const Duration(minutes: 2),
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairReadSyncV2CaseId,
    phases: const <String>[
      'ordinary_message_unread_on_both_apps',
      'joining_app_visible_read_committed_by_core',
      'admin_app_read_watermark_converged',
      'duplicate_sync_did_not_regress_read',
    ],
  );

  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: preservedMessageText,
    messageId: preservedMessageId,
    senderDid: accountDid,
    receiverDid: peerDid,
    isMine: true,
  );
  await _pumpUntil(
    tester,
    () {
      final sync = container.read(messageSyncCoordinatorProvider);
      return !sync.isSyncing && sync.pendingReason == null;
    },
    timeout: const Duration(seconds: 30),
    failure: 'The joining App sync queue did not quiesce before going offline.',
  );
  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.paused);
  await container.read(realtimeApplicationServiceProvider).stop();
  final stoppedSync = container.read(messageSyncCoordinatorProvider);
  if (container.read(realtimeApplicationServiceProvider).isRunning ||
      stoppedSync.isSyncing ||
      stoppedSync.pendingReason != null) {
    fail('The joining App realtime transport remained online.');
  }
  await config.coordinator.publish('joiner', 'functional_offline_ready');
  final recovery = await config.coordinator.waitFor(
    'admin',
    'functional_recovery_gap_prepared',
    timeout: const Duration(minutes: 2),
  );
  final recoveryMessageId = _required(recovery, 'messageId');
  final recoveryText = _appPairMessage(config.runId, 'offline-recovery');
  final diagnosticsSuccessSequenceBeforeRecovery = container
      .read(messageSyncCoordinatorProvider)
      .safeDiagnostics
      .refreshSuccessSequence;
  await _resumeAppPairAndWaitForSync(
    tester: tester,
    container: container,
    timeout: const Duration(minutes: 2),
    failure: 'The joining App did not finish its Core-owned recovery chain.',
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: recoveryText,
    messageId: recoveryMessageId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: preservedMessageText,
    messageId: preservedMessageId,
    senderDid: accountDid,
    receiverDid: peerDid,
    isMine: true,
  );
  await _waitForAppPairUnreadCount(
    tester: tester,
    container: container,
    conversationId: conversationId,
    matches: (count) => count == 0,
    failure: 'The joining App did not converge the current read state.',
  );
  await _waitForSafeAppPairSyncDiagnostics(
    tester: tester,
    container: container,
    priorSuccessSequence: diagnosticsSuccessSequenceBeforeRecovery,
  );
  await config.coordinator.publish('joiner', 'functional_recovery_completed');
  final postAnchor = await config.coordinator.waitFor(
    'admin',
    'functional_post_anchor_sent',
    timeout: const Duration(minutes: 2),
  );
  final postAnchorId = _required(postAnchor, 'messageId');
  final postAnchorText = _appPairMessage(config.runId, 'post-anchor');
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: postAnchorText,
    messageId: postAnchorId,
    senderDid: peerDid,
    receiverDid: accountDid,
    isMine: false,
  );
  await config.coordinator.publish('joiner', 'functional_post_anchor_visible');
  await E2eCaseAttestationWriter.markPassed(
    _appPairOfflineRecoveryV2CaseId,
    phases: const <String>[
      'existing_replica_offline_gap_created',
      'core_owned_recovery_completed',
      'recent_plain_messages_converged_once',
      'older_local_messages_preserved',
      'current_state_and_post_anchor_delta_converged',
    ],
  );
  await E2eCaseAttestationWriter.markPassed(
    _appPairDiagnosticsCaseId,
    phases: const <String>[
      'typed_diagnostics_refreshed_after_real_sync',
      'pending_mutation_count_reported_as_non_negative_count',
      'compact_recovery_closed_by_core_sync_now',
      'diagnostics_refresh_sequence_advanced_after_recovery',
      'diagnostics_projection_excluded_sensitive_fields',
    ],
  );
}

Future<void> _waitForSafeAppPairSyncDiagnostics({
  required WidgetTester tester,
  required ProviderContainer container,
  required int priorSuccessSequence,
}) async {
  await _pumpUntil(
    tester,
    () {
      final state = container.read(messageSyncCoordinatorProvider);
      final diagnostics = state.safeDiagnostics;
      return diagnostics.isCurrent &&
          diagnostics.refreshSuccessSequence > priorSuccessSequence &&
          diagnostics.lastSuccessAt != null &&
          state.status == MessageSyncCoordinatorStatus.idle &&
          diagnostics.mode == AppMessageSyncMode.idle &&
          diagnostics.retryState == AppMessageSyncRetryState.none &&
          diagnostics.nextRetryAt == null;
    },
    timeout: const Duration(seconds: 30),
    failure:
        'The product coordinator did not close the Core-directed retry chain.',
  );
  _requireSafeAppPairSyncDiagnostics(
    container.read(messageSyncCoordinatorProvider),
    priorSuccessSequence: priorSuccessSequence,
  );
}

void _requireSafeAppPairSyncDiagnostics(
  MessageSyncCoordinatorState state, {
  required int priorSuccessSequence,
}) {
  final diagnostics = state.safeDiagnostics;
  final failedChecks = <String>[
    if (!diagnostics.isCurrent) 'diagnostics_not_current',
    if (diagnostics.refreshSuccessSequence <= priorSuccessSequence)
      'refresh_sequence_not_advanced',
    if (diagnostics.lastSuccessAt == null) 'last_success_missing',
    if (diagnostics.pendingMutationCount < 0) 'negative_pending_count',
    if (diagnostics.dirtyDomains.toSet().length !=
        diagnostics.dirtyDomains.length)
      'duplicate_dirty_domain',
    if (state.status != MessageSyncCoordinatorStatus.idle)
      'coordinator_not_idle',
    if (diagnostics.mode != AppMessageSyncMode.idle) 'core_mode_not_idle',
    if (diagnostics.retryState != AppMessageSyncRetryState.none)
      'retry_not_closed',
    if (diagnostics.nextRetryAt != null) 'retry_deadline_present',
  ];
  if (failedChecks.isNotEmpty) {
    fail(
      'The product-safe sync diagnostics did not reach a closed state '
      '(${failedChecks.join(',')}).',
    );
  }
  final encoded = jsonEncode(diagnostics.toJson()).toLowerCase();
  const forbidden = <String>[
    'cursor',
    'scan_seq',
    'stream_epoch',
    'account_id',
    'device_id',
    'recovery_token',
    'message_content',
    'payload',
  ];
  if (forbidden.any(encoded.contains)) {
    fail('The product-safe sync diagnostics exposed a forbidden field.');
  }
}

Future<void> _waitForAppPairUnreadCount({
  required WidgetTester tester,
  required ProviderContainer container,
  required String conversationId,
  required bool Function(int count) matches,
  required String failure,
}) async {
  await _pumpUntil(
    tester,
    () {
      final conversations = container
          .read(conversationListProvider)
          .conversations
          .where((item) => item.conversationId == conversationId)
          .toList(growable: false);
      if (conversations.length > 1) {
        fail('The App-pair projected a duplicate Direct conversation.');
      }
      return conversations.length == 1 &&
          matches(conversations.single.unreadCount);
    },
    timeout: const Duration(seconds: 90),
    failure: failure,
  );
}

Future<void> _resumeAppPairAndWaitForSync({
  required WidgetTester tester,
  required ProviderContainer container,
  required String failure,
  Duration timeout = const Duration(seconds: 60),
}) async {
  var syncStarted = false;
  final subscription = container.listen<MessageSyncCoordinatorState>(
    messageSyncCoordinatorProvider,
    (previous, next) {
      if (next.isSyncing ||
          next.recoveryRequired ||
          next.status == MessageSyncCoordinatorStatus.recovering ||
          next.pendingReason == 'app_resumed') {
        syncStarted = true;
      }
    },
  );
  container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.resumed);
  try {
    await _pumpUntil(
      tester,
      () => syncStarted,
      timeout: timeout,
      failure: '$failure No app-resumed sync was observed.',
    );
    await _pumpUntil(
      tester,
      () {
        final sync = container.read(messageSyncCoordinatorProvider);
        return !sync.isSyncing &&
            !sync.recoveryRequired &&
            !sync.isAuthRevoked &&
            sync.lastError == null &&
            sync.lastStatus != null;
      },
      timeout: timeout,
      failure: failure,
    );
  } finally {
    subscription.close();
  }
}

Future<void> _forceAppPairRetentionGap(String protocolDeviceId) async {
  final environment = Platform.environment;
  final mode = environment[_syncRecoveryOperatorModeEnv]?.trim();
  if (environment[_syncRecoveryEnableEnv] != '1' ||
      environment[_syncRecoveryTargetEnv] != _syncRecoveryTarget ||
      mode != 'ali') {
    fail('The fixed recovery operator gate is incomplete.');
  }
  const command = reviewedSyncRecoveryOperatorCommand;
  final process = await Process.start(
    command.first,
    command.skip(1).toList(growable: false),
    includeParentEnvironment: true,
    runInShell: false,
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.drain<void>();
  process.stdin.write(
    jsonEncode(<String, String>{
      'action': 'force_retention_gap',
      'protocol_device_id': protocolDeviceId,
    }),
  );
  await process.stdin.close();
  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(seconds: 30));
  } on TimeoutException {
    process.kill();
    fail('The fixed recovery retention-gap preparation timed out.');
  }
  final stdoutText = await stdoutFuture;
  await stderrFuture;
  Object? receipt;
  try {
    receipt = jsonDecode(stdoutText);
  } on FormatException {
    fail('The fixed recovery operator returned no closed receipt.');
  }
  if (exitCode != 0 ||
      receipt is! Map ||
      receipt.length != 3 ||
      receipt['affected_streams'] != 1 ||
      receipt['mode'] != 'retention_gap' ||
      receipt['prepared'] != true) {
    fail('The fixed recovery retention-gap preparation failed.');
  }
}

Future<AgentSummary> _waitForAppPairRuntime({
  required WidgetTester tester,
  required ProviderContainer container,
  required _AppPairDaemonProcess daemon,
  required String daemonDid,
  required String handle,
  required String runtime,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    final state = container.read(agentsProvider);
    if (state.error != null) {
      fail(
        'The App-pair runtime Agent creation failed: ${state.error}. '
        'daemon=${daemon.safeDiagnostics}',
      );
    }
    final matches = state.agents
        .where(
          (agent) =>
              agent.isRuntime &&
              agent.daemonAgentDid == daemonDid &&
              agent.handle == handle &&
              (agent.runtime == runtime || agent.runtime == 'generic-cli'),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The App-pair runtime inventory projected a duplicate Agent.');
    }
    final hasMatchingPending = state.pendingRuntimeCreations.any(
      (pending) =>
          pending.daemonAgentDid == daemonDid && pending.handle == handle,
    );
    if (matches.length == 1 && !state.isActing && !hasMatchingPending) {
      return matches.single;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail(
    'The App-pair runtime Agent or its local creation state did not converge: '
    '$handle. '
    'daemon=${daemon.safeDiagnostics}',
  );
}

Future<void> _waitForAppPairConversation({
  required WidgetTester tester,
  required ProviderContainer container,
  required String peerDid,
  required String conversationId,
  required String preview,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    final matches = container
        .read(conversationListProvider)
        .conversations
        .where(
          (conversation) =>
              conversation.conversationId == conversationId &&
              conversation.targetDid == peerDid,
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The joining App projected a duplicate Direct conversation.');
    }
    if (matches.length == 1 && matches.single.lastMessagePreview == preview) {
      return;
    }
  }
  final sync = container.read(messageSyncCoordinatorProvider);
  final realtime = container.read(realtimeConnectionStatusProvider).valueOrNull;
  final conversations = container.read(conversationListProvider).conversations;
  final idMatches = conversations
      .where((item) => item.conversationId == conversationId)
      .length;
  final targetMatches = conversations
      .where((item) => item.targetDid == peerDid)
      .length;
  final previewMatches = conversations
      .where((item) => item.lastMessagePreview == preview)
      .length;
  final routeMatches = conversations
      .where(
        (item) =>
            item.conversationId == conversationId && item.targetDid == peerDid,
      )
      .toList(growable: false);
  final historyDiagnostic = await _appPairHistoryDiagnostic(
    container: container,
    conversationId: conversationId,
    preview: preview,
  );
  fail(
    'The joining App conversation list did not converge '
    '(realtime=${realtime?.name ?? 'unknown'}, '
    'lastSync=${sync.lastReason ?? 'none'}, '
    'syncError=${_appPairErrorDiagnostic(sync.lastError)}, '
    'syncing=${sync.isSyncing}, conversations=${conversations.length}, '
    'idMatches=$idMatches, targetMatches=$targetMatches, '
    'previewMatches=$previewMatches, routeMatches=${routeMatches.length}, '
    'routePreviewLengths=${routeMatches.map((item) => item.lastMessagePreview.length).toList()}, '
    '$historyDiagnostic).',
  );
}

Future<String> _appPairHistoryDiagnostic({
  required ProviderContainer container,
  required String conversationId,
  required String preview,
}) async {
  try {
    final messaging = container.read(messagingServiceProvider);
    if (messaging is! ConversationTimelineMessagingService) {
      return 'historyError=conversation_timeline_unavailable';
    }
    final messages = await (messaging as ConversationTimelineMessagingService)
        .loadConversationTimeline(
          AppConversationReadRef.fromConversationId(conversationId),
          limit: 20,
        );
    return 'history=${messages.length}, '
        'historyContentMatches=${messages.where((item) => item.content == preview).length}';
  } on Object catch (error) {
    return 'historyError=${_appPairErrorDiagnostic(error)}';
  }
}

String _appPairErrorDiagnostic(Object? error) {
  if (error == null) return 'none';
  if (error is core.AwikiImCoreException) {
    return '${error.runtimeType}:${error.code}:${error.serviceCode ?? 'none'}:'
        '${error.message}';
  }
  return error.runtimeType.toString();
}

Future<ChatMessage> _waitForAppPairMessage({
  required ProviderContainer container,
  required MessagingService messaging,
  required String conversationId,
  required String content,
  required String messageId,
  required String senderDid,
  required String receiverDid,
  required bool isMine,
}) async {
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The App-pair messaging service lacks conversation timeline reads.');
  }
  final timeline = messaging as ConversationTimelineMessagingService;
  final conversation = AppConversationReadRef.fromConversationId(
    conversationId,
  );
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  var lastMessages = const <ChatMessage>[];
  while (DateTime.now().isBefore(deadline)) {
    final messages = await timeline.loadConversationTimeline(
      conversation,
      limit: 20,
    );
    lastMessages = messages;
    final matches = messages
        .where((message) => message.content == content)
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The App-pair history projected a duplicate exact message.');
    }
    if (matches.length == 1) {
      final message = matches.single;
      if (message.remoteId == messageId &&
          message.senderDid == senderDid &&
          message.receiverDid == receiverDid &&
          message.isMine == isMine &&
          message.sendState == MessageSendState.sent) {
        return message;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
  }
  final contentMatches = lastMessages
      .where((message) => message.content == content)
      .toList(growable: false);
  final exact = contentMatches.length == 1 ? contentMatches.single : null;
  final sync = container.read(messageSyncCoordinatorProvider);
  fail(
    'The App-pair history did not converge the exact Direct message '
    '(messages=${lastMessages.length}, contentMatches=${contentMatches.length}, '
    'id=${exact?.remoteId == messageId}, '
    'conversation=${exact?.conversationId == conversationId}, '
    'sender=${exact?.senderDid == senderDid}, '
    'receiver=${exact?.receiverDid == receiverDid}, '
    'mine=${exact?.isMine == isMine}, state=${exact?.sendState.name ?? 'none'}, '
    'lastSync=${sync.lastReason ?? 'none'}, '
    'syncError=${_appPairErrorDiagnostic(sync.lastError)}, '
    'syncing=${sync.isSyncing}).',
  );
}

Future<void> _assertAppPairMessageAbsent({
  required MessagingService messaging,
  required String conversationId,
  required String content,
  required String messageId,
}) async {
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The App-pair messaging service lacks conversation timeline reads.');
  }
  final messages = await (messaging as ConversationTimelineMessagingService)
      .loadConversationTimeline(
        AppConversationReadRef.fromConversationId(conversationId),
        limit: 20,
      );
  if (messages.any(
    (message) => message.content == content || message.remoteId == messageId,
  )) {
    fail('A message crossed the stopped realtime channel before HTTP pull.');
  }
}

Future<void> _assertAppPairMessageCount({
  required MessagingService messaging,
  required String conversationId,
  required String content,
  required String messageId,
  required int expectedCount,
}) async {
  if (messaging is! ConversationTimelineMessagingService) {
    fail('The App-pair messaging service lacks conversation timeline reads.');
  }
  final messages = await (messaging as ConversationTimelineMessagingService)
      .loadConversationTimeline(
        AppConversationReadRef.fromConversationId(conversationId),
        limit: 20,
      );
  final matches = messages
      .where(
        (message) =>
            message.content == content && message.remoteId == messageId,
      )
      .length;
  if (matches != expectedCount) {
    fail('Reliable HTTP reconciliation did not preserve exact message count.');
  }
}

Future<void> _openAppPairConversation({
  required WidgetTester tester,
  required String conversationId,
  required String content,
}) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-messages-tab'),
    failure: 'The joining App Messages tab was unavailable.',
  );
  await _pumpUntil(
    tester,
    () =>
        find.byKey(Key('conversation-row:$conversationId')).evaluate().length ==
        1,
    timeout: const Duration(seconds: 30),
    failure: 'The joining App exact conversation row was unavailable.',
  );
  await _tapOne(
    tester,
    find.byKey(Key('conversation-row:$conversationId')),
    failure: 'The joining App exact conversation row was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find
        .bySemanticsIdentifier(e2eMessageIdentifier(content))
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 60),
    failure: 'The joining App did not render the exact own-sync message.',
  );
}

String _appPairRuntimeHandle(String runId, String kind) =>
    'pair-${_safeId(kind, 8)}-${_safeId(runId, 14)}'.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9-]'),
      '-',
    );

String _appPairMessage(String runId, String phase) =>
    'app-pair-${_safeId(runId, 20)}-$phase';
