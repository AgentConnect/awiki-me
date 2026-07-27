part of 'multi_device_join_ui_test.dart';

void appPairAdminMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated admin App approves an isolated joining App',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final coordinator = config.coordinator;
      final httpClient = http.Client();
      final presence = _AppPairUserPresencePort(
        automated: config.automatedUserPresence,
      );
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
      if (!config.automatedUserPresence &&
          !await LocalAuthentication().isDeviceSupported()) {
        fail(
          'The App-pair admin requires real operating-system user presence.',
        );
      }
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
        timeout: const Duration(minutes: 3),
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
        failure: config.automatedUserPresence
            ? 'The admin App did not complete E2E-only user presence.'
            : 'The admin App did not complete real user presence.',
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
            'single_real_user_presence_confirmed',
            'both_app_registries_converged',
          ],
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

void appPairJoinerMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated joining App completes member Join through visible UI',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
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
        timeout: const Duration(minutes: 3),
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
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

void _requireAppPairModeMatchesInvocation(_AppPairRunConfig config) {
  final expectsFunctional =
      _invocationExpects(_appPairAgentSyncCaseId) ||
      _invocationExpects(_appPairOutboundSyncCaseId) ||
      _invocationExpects(_appPairInboundSyncCaseId);
  final expectsSecurity = _invocationExpects(_appPairCaseId);
  if (config.functional != expectsFunctional ||
      config.functional == expectsSecurity ||
      config.automatedUserPresence != config.functional) {
    fail(
      'The App-pair run config mixed the real-presence security suite with '
      'the E2E-only unattended functional suite.',
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
  required _AppPairFunctionalAdminResources resources,
}) async {
  await _leaveCompletedAppPairApproval(tester);
  await config.coordinator.waitFor(
    'joiner',
    'functional_ready',
    timeout: const Duration(minutes: 2),
  );

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
  await config.coordinator.publish(
    'admin',
    'functional_peer_ready',
    data: <String, Object?>{'peerDid': peerDid, 'peerHandle': peerHandle},
  );

  final peerResolution = await bootstrap.directoryApplicationService!
      .resolvePeer(peerDid);
  final canonicalConversationId = peerResolution.conversationId?.trim() ?? '';
  if (peerResolution.did != peerDid ||
      !canonicalConversationId.startsWith('dm:peer-scope:v1:')) {
    fail('The admin App did not resolve the peer to a canonical conversation.');
  }
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
      outbound.senderDid != adminDid ||
      outbound.receiverDid != peerDid) {
    fail('The admin App did not commit the canonical outbound Direct message.');
  }
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
    daemonDid: install.daemonDid,
    handle: claudeHandle,
    runtime: RuntimeAgentKind.claudeCode.runtime,
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
    },
  );
  await config.coordinator.waitFor(
    'joiner',
    'functional_agents_converged',
    timeout: const Duration(minutes: 2),
  );
}

Future<void> _runAppPairJoinerFunctional({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String accountDid,
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
      joinedOutbound.senderDid != accountDid ||
      joinedOutbound.receiverDid != peerDid) {
    fail('The joining App did not commit its outbound Direct message.');
  }
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

  await _openAppPairAgentsPage(tester);
  await config.coordinator.publish('joiner', 'functional_agent_observer_ready');
  final created = await config.coordinator.waitFor(
    'admin',
    'functional_agents_created',
    timeout: const Duration(minutes: 3),
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

class _AppPairUserPresencePort implements UserPresencePort {
  _AppPairUserPresencePort({required this.automated});

  final bool automated;
  final LocalAuthUserPresencePort _real = LocalAuthUserPresencePort();
  int calls = 0;
  int completions = 0;
  bool lastResult = false;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    lastResult = automated ? true : await _real.confirm(reason: reason);
    completions += 1;
    return lastResult;
  }
}

class _AppPairFunctionalAdminResources {
  _AppPairDaemonProcess? daemon;
  _JoinCli? peer;

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
    fail('The App-pair daemon install failed safely.');
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

Future<AgentSummary> _waitForAppPairRuntime({
  required WidgetTester tester,
  required ProviderContainer container,
  required String daemonDid,
  required String handle,
  required String runtime,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
    final state = container.read(agentsProvider);
    if (state.error != null) {
      fail('The App-pair runtime Agent creation failed: ${state.error}.');
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
    if (matches.length == 1 && !state.isActing) return matches.single;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The App-pair runtime Agent did not converge: $handle.');
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
    return '${error.runtimeType}:${error.code}:${error.serviceCode ?? 'none'}';
  }
  return error.runtimeType.toString();
}

Future<ChatMessage> _waitForAppPairMessage({
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
  while (DateTime.now().isBefore(deadline)) {
    final messages = await timeline.loadConversationTimeline(
      conversation,
      limit: 20,
    );
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
  fail('The App-pair history did not converge the exact Direct message.');
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
