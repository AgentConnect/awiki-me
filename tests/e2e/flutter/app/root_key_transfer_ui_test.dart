// [INPUT]: Audited awiki.info endpoints, production App/native Core, an
//          independent CLI device, strict OTP resolution, and real macOS user presence.
// [OUTPUT]: Executable UI evidence for encrypted root import, imported ACK,
//           Registry-backed management readiness, and permanent device revoke.
// [POS]: Remote management lifecycle part of multi_device_join_ui_test.dart;
//        no fake port, secret projection, scripted presence, or test bypass is allowed.

part of 'multi_device_join_ui_test.dart';

const String _rootTransferCaseId = 'ROOT-TRANSFER-E2E-001';
const String _deviceRevokeCaseId = 'DEVICE-REVOKE-E2E-001';

void _registerRootKeyTransferAndRevokeTests() {
  testWidgets(
    'real App imports root into an admin device then permanently revokes it',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      final cli = _JoiningCli(
        config,
        rootTransferEnabled: true,
        deviceRevokeEnabled: true,
        directE2eeEnabled: true,
      );
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await _prepareFreshManagementRoots(config);
      _requireIndependentEmptyRoots(config);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await cli.deleteLocalState();
        final appRoot = Directory(config.appStateRoot);
        if (await appRoot.exists()) {
          await appRoot.delete(recursive: true);
        }
        await tester.binding.setSurfaceSize(null);
      });

      if (!await LocalAuthentication().isDeviceSupported()) {
        fail(
          'The remote management lifecycle gate requires real operating-system user presence.',
        );
      }
      await cli.initialize();

      final environment = AwikiEnvironmentConfig(
        baseUrl: config.baseUrl,
        userServiceUrl: config.userServiceUrl,
        messageServiceUrl: config.messageServiceUrl,
        mailServiceUrl: config.mailServiceUrl,
        didDomain: config.didDomain,
        anpServiceUrl: config.anpServiceUrl,
        anpServiceDid: config.anpServiceDid,
        agentImEnabled: false,
        multiDeviceJoinEnabled: true,
        multiDeviceRootTransferEnabled: true,
        multiDeviceDeviceRevokeEnabled: true,
        multiDeviceDirectE2eeEnabled: true,
        multiDeviceGroupE2eeEnabled: false,
        handleRecoveryEnabled: false,
      );
      bootstrap = await AppBootstrap.create(
        environment: environment,
        appStateRoot: config.appStateRoot,
      );
      final handle = _uniqueHandle(config.handlePrefix);
      final genesisOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _genesisPurpose,
        handle: handle,
      );
      final AppSession adminSession;
      try {
        adminSession = await bootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: genesisOtp,
              handle: handle,
              nickName: 'AWiki management lifecycle E2E',
            );
      } on Object {
        fail('App bootstrap registration failed without exposing remote data.');
      }
      if (!adminSession.authenticated) {
        fail('The App bootstrap identity was not authenticated.');
      }
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(adminSession.did);
      final bootstrapAdminDeviceId = _requireReadyBootstrapAdmin(
        initialRegistry,
      );

      final joinOperation = 'app-admin-join-${_nonce(10)}';
      final joinOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _joinPurpose,
        handle: handle,
      );
      final grant = await _exchangeJoinGrant(
        client: httpClient,
        config: config,
        account: account,
        handle: handle,
        otp: joinOtp,
        operationId: joinOperation,
      );
      final started = await cli.startJoin(
        did: adminSession.did,
        operationId: joinOperation,
        accountVerificationToken: grant,
      );
      if (started.remoteState != 'pending' || started.sas != null) {
        fail('OTP did not leave the management device pending without SAS.');
      }

      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
          ],
        ),
      );
      final container = await _waitForRestoredAuthenticatedApp(
        tester,
        expectedDid: adminSession.did,
      );
      await _openDevicesPage(tester);

      await _pumpUntil(
        tester,
        () => find.text(started.protocolDeviceId).evaluate().length == 1,
        timeout: const Duration(seconds: 30),
        failure: 'The pending management device did not appear in the App.',
      );
      await _tapOne(
        tester,
        find.text(started.protocolDeviceId),
        failure: 'The pending management device could not be opened.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinApprovalSheet).evaluate().length == 1,
        failure: 'The App Join approval surface did not open.',
      );
      await _waitForAppAdminChallenge(
        tester,
        container: container,
        expectedDid: adminSession.did,
        expectedJoinSessionId: started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );

      final joiningProgress = await cli.pollUntilSas(
        started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      await _waitForAppAdminResponseVerified(
        tester,
        container: container,
        expectedDid: adminSession.did,
        expectedJoinSessionId: started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('device-approval-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The App did not derive the management-device Join SAS.',
      );
      final appSas =
          tester
              .widget<Text>(find.byKey(const Key('device-approval-sas')))
              .data ??
          '';
      if (!_validSas(appSas) ||
          !_constantTimeAsciiEquals(appSas, joiningProgress.sas!)) {
        fail('The independently derived management-device SAS values differ.');
      }

      final sasSwitch = find.descendant(
        of: find.byKey(const Key('device-sas-confirmation')),
        matching: find.byType(CupertinoSwitch),
      );
      final adminSwitch = find.descendant(
        of: find.byKey(const Key('device-admin-toggle')),
        matching: find.byType(CupertinoSwitch),
      );
      if (tester.widget<CupertinoSwitch>(adminSwitch).value) {
        fail('The App selected management permission without user intent.');
      }
      await _tapOne(
        tester,
        sasSwitch,
        failure: 'The SAS confirmation control was not available.',
      );
      await _tapOne(
        tester,
        adminSwitch,
        failure: 'The management permission control was not available.',
      );
      final approveAction = find.bySemanticsIdentifier('multi-device-approve');
      await _pumpUntil(
        tester,
        () => approveAction.evaluate().length == 1,
        failure: 'The App did not enable explicit admin approval.',
      );
      await _tapOne(
        tester,
        approveAction,
        failure: 'The explicit admin approval action was not available.',
      );
      await _waitForPresenceCompletion(
        tester,
        presence,
        expectedCompletions: 1,
        failure: 'The admin Join user-presence check did not complete.',
      );

      final authorized = await cli.pollUntilAuthorized(
        started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      if (authorized.protocolDeviceId != started.protocolDeviceId ||
          authorized.role != 'admin' ||
          authorized.managementReady ||
          !authorized.isCurrent) {
        fail(
          'The joining device was not an active admin awaiting root import.',
        );
      }
      _requireCliAdminRegistry(
        await cli.loadRegistry(),
        protocolDeviceId: started.protocolDeviceId,
        managementReady: false,
      );
      _requireAppAdminRegistry(
        await bootstrap.deviceManagementCorePort!.identityDeviceRegistry(
          adminSession.did,
        ),
        protocolDeviceId: started.protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        managementReady: false,
      );

      final doneLabel = tester
          .element(find.byType(DeviceJoinApprovalSheet))
          .l10n
          .commonDone;
      await _tapOne(
        tester,
        find.text(doneLabel),
        failure: 'The completed admin Join could not return to Devices.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DevicesPage).evaluate().length == 1,
        failure: 'The Devices page did not resume after admin Join.',
      );

      final rootAction = find.byKey(
        Key('root-transfer-${started.protocolDeviceId}'),
      );
      await _pumpUntil(
        tester,
        () => rootAction.evaluate().length == 1,
        failure: 'The admin-awaiting-root action was not visible.',
      );
      await _tapOne(
        tester,
        rootAction,
        failure: 'The initial secure root-import action was unavailable.',
      );
      await _waitForPresenceCompletion(
        tester,
        presence,
        expectedCompletions: 2,
        failure:
            'The initial root-import user-presence check did not complete.',
      );
      await _pumpUntil(
        tester,
        () =>
            find
                .byKey(const Key('devices-root-session-pending'))
                .evaluate()
                .length ==
            1,
        timeout: const Duration(seconds: 30),
        failure: 'The App did not distinguish session Init from root delivery.',
      );
      if ((await cli.loadRootTransfers()).isNotEmpty) {
        fail('Session Init incorrectly created a root-transfer projection.');
      }

      await cli.syncInbox();
      await bootstrap.messageSyncService!.syncNow(
        reason: 'e2e_root_session_reply',
      );
      await _tapOne(
        tester,
        rootAction,
        failure: 'The root-import continuation was unavailable.',
      );
      await _waitForPresenceCompletion(
        tester,
        presence,
        expectedCompletions: 3,
        failure:
            'The continued root-import user-presence check did not complete.',
      );
      await _pumpUntil(
        tester,
        () {
          final l10n = tester.element(find.byType(DevicesPage)).l10n;
          return find
                  .textContaining(l10n.deviceManagementImporting)
                  .evaluate()
                  .isNotEmpty &&
              find
                  .byKey(const Key('devices-root-session-pending'))
                  .evaluate()
                  .isEmpty;
        },
        timeout: const Duration(seconds: 30),
        failure: 'The App did not project encrypted root import in progress.',
      );

      await _waitForRootImportConvergence(
        tester: tester,
        bootstrap: bootstrap,
        cli: cli,
        did: adminSession.did,
        recipientDeviceId: started.protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
      );
      if (presence.calls != 3 ||
          presence.completions != 3 ||
          !presence.lastResult) {
        fail('Root import did not use exactly three approved presence checks.');
      }
      _expectNoRootControlContent(tester);

      await E2eCaseAttestationWriter.markPassed(
        _rootTransferCaseId,
        startedAt: startedAt,
        phases: const <String>[
          'admin_joined_awaiting_root',
          'init_only_pending_visible',
          'fresh_presence_continued_import',
          'signed_imported_ack_completed',
          'registry_management_ready_visible',
        ],
      );

      final revokeAction = find.byKey(
        Key('device-revoke-${started.protocolDeviceId}'),
      );
      await _tapOne(
        tester,
        revokeAction,
        failure: 'The permanent revoke action was not available.',
      );
      await _pumpUntil(
        tester,
        () =>
            find
                .byKey(const Key('device-revoke-confirm-dialog'))
                .evaluate()
                .length ==
            1,
        failure: 'The destructive revoke confirmation did not appear.',
      );
      await _tapOne(
        tester,
        find.byKey(const Key('device-revoke-confirm-action')),
        failure: 'The destructive revoke confirmation was unavailable.',
      );
      await _waitForPresenceCompletion(
        tester,
        presence,
        expectedCompletions: 4,
        failure: 'The permanent revoke user-presence check did not complete.',
      );
      await _waitForRevokedProjection(
        tester: tester,
        bootstrap: bootstrap,
        did: adminSession.did,
        targetDeviceId: started.protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
      );
      if (presence.calls != 4 ||
          presence.completions != 4 ||
          !presence.lastResult) {
        fail('Permanent revoke did not use exactly one fresh presence check.');
      }
      _expectNoRootControlContent(tester);

      await E2eCaseAttestationWriter.markPassed(
        _deviceRevokeCaseId,
        startedAt: startedAt,
        phases: const <String>[
          'destructive_confirmation_visible',
          'single_fresh_user_presence_confirmed',
          'registry_projected_target_revoked',
          'current_ready_admin_retained',
        ],
      );
    },
    skip:
        !Platform.isMacOS ||
        !_RemoteJoinRunConfig.exists() ||
        !_invocationExpects(_rootTransferCaseId),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _prepareFreshManagementRoots(_RemoteJoinRunConfig config) async {
  for (final path in <String>[
    config.appStateRoot,
    config.cliWorkspace,
    config.cliHome,
  ]) {
    final directory = Directory(path);
    if (await directory.exists()) {
      if ((await directory.list(followLinks: false).toList()).isNotEmpty) {
        fail('A management E2E local root was not fresh.');
      }
    } else {
      await directory.create(recursive: true);
    }
  }
}

Future<void> _openDevicesPage(WidgetTester tester) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-settings-tab'),
    failure: 'The App settings entry was not visible.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().length == 1,
    failure: 'The App settings surface did not open.',
  );
  final l10n = tester.element(find.byType(SettingsPage)).l10n;
  await _tapOne(
    tester,
    find.text(l10n.settingsDevices),
    failure: 'The App Devices entry was not visible.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DevicesPage).evaluate().length == 1,
    failure: 'The App Devices surface did not open.',
  );
}

Future<void> _waitForPresenceCompletion(
  WidgetTester tester,
  _CountingRealUserPresencePort presence, {
  required int expectedCompletions,
  required String failure,
}) async {
  await _pumpUntil(
    tester,
    () {
      if (presence.calls > expectedCompletions) {
        fail('The App requested operating-system user presence too often.');
      }
      if (presence.completions == expectedCompletions && !presence.lastResult) {
        fail('The operating-system user-presence check was denied.');
      }
      return presence.completions == expectedCompletions && presence.lastResult;
    },
    timeout: const Duration(minutes: 2),
    failure: failure,
  );
}

Future<void> _waitForRootImportConvergence({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required _JoiningCli cli,
  required String did,
  required String recipientDeviceId,
  required String bootstrapAdminDeviceId,
}) async {
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    await cli.syncInbox();
    await bootstrap.messageSyncService!.syncNow(
      reason: 'e2e_root_imported_ack',
    );
    await _tapOne(
      tester,
      find.byKey(const Key('devices-refresh')),
      failure: 'The Devices refresh action was unavailable during root import.',
    );
    await tester.pump(const Duration(milliseconds: 300));
    final cliRegistry = await cli.loadRegistry();
    final appRegistry = await bootstrap.deviceManagementCorePort!
        .identityDeviceRegistry(did);
    final transfers = await cli.loadRootTransfers();
    final importedAckCompleted =
        transfers.length == 1 &&
        transfers.single['recipient_device_id'] == recipientDeviceId &&
        transfers.single['status'] == 'completed' &&
        transfers.single['retryable'] == false;
    if (importedAckCompleted &&
        _cliAdminReady(cliRegistry, protocolDeviceId: recipientDeviceId) &&
        _appAdminReady(
          appRegistry,
          protocolDeviceId: recipientDeviceId,
          bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        )) {
      final readyLabel = tester.element(find.byType(DevicesPage)).l10n;
      if (find
                  .textContaining(readyLabel.deviceManagementReady)
                  .evaluate()
                  .length >=
              2 &&
          find
              .byKey(Key('root-transfer-$recipientDeviceId'))
              .evaluate()
              .isEmpty) {
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 700));
  }
  fail('Root import did not converge through imported ACK and Registry ready.');
}

Future<void> _waitForRevokedProjection({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String did,
  required String targetDeviceId,
  required String bootstrapAdminDeviceId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    final registry = await bootstrap.deviceManagementCorePort!
        .identityDeviceRegistry(did);
    final target = registry.devices
        .where((device) => device.protocolDeviceId == targetDeviceId)
        .toList(growable: false);
    final current = registry.devices
        .where((device) => device.protocolDeviceId == bootstrapAdminDeviceId)
        .toList(growable: false);
    if (target.length == 1 &&
        target.single.status == DeviceStatus.revoked &&
        current.length == 1 &&
        current.single.isCurrent &&
        current.single.canManageDevices) {
      final l10n = tester.element(find.byType(DevicesPage)).l10n;
      if (find.textContaining(l10n.deviceStatusRevoked).evaluate().isNotEmpty &&
          find.byKey(Key('device-revoke-$targetDeviceId')).evaluate().isEmpty) {
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 500));
  }
  fail('The App did not project the authoritative permanent revoke.');
}

void _requireCliAdminRegistry(
  List<Map<String, Object?>> devices, {
  required String protocolDeviceId,
  required bool managementReady,
}) {
  if (devices.length != 2) {
    fail('The joining CLI Registry did not contain exactly two devices.');
  }
  final current = devices
      .where((device) => device['is_current'] == true)
      .toList(growable: false);
  if (current.length != 1 ||
      current.single['protocol_device_id'] != protocolDeviceId ||
      current.single['role'] != 'admin' ||
      current.single['management_ready'] != managementReady ||
      current.single['status'] != 'active') {
    fail('The joining CLI did not project the expected current admin state.');
  }
}

void _requireAppAdminRegistry(
  DeviceRegistrySnapshot registry, {
  required String protocolDeviceId,
  required String bootstrapAdminDeviceId,
  required bool managementReady,
}) {
  if (!_appAdminReady(
        registry,
        protocolDeviceId: protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        expectedManagementReady: managementReady,
      ) ||
      registry.devices.length != 2) {
    fail('The App did not project the expected two-admin Registry state.');
  }
}

bool _cliAdminReady(
  List<Map<String, Object?>> devices, {
  required String protocolDeviceId,
}) {
  final current = devices
      .where((device) => device['is_current'] == true)
      .toList(growable: false);
  return devices.length == 2 &&
      current.length == 1 &&
      current.single['protocol_device_id'] == protocolDeviceId &&
      current.single['role'] == 'admin' &&
      current.single['management_ready'] == true &&
      current.single['status'] == 'active';
}

bool _appAdminReady(
  DeviceRegistrySnapshot registry, {
  required String protocolDeviceId,
  required String bootstrapAdminDeviceId,
  bool expectedManagementReady = true,
}) {
  final recipient = registry.devices
      .where((device) => device.protocolDeviceId == protocolDeviceId)
      .toList(growable: false);
  final current = registry.devices
      .where((device) => device.protocolDeviceId == bootstrapAdminDeviceId)
      .toList(growable: false);
  return recipient.length == 1 &&
      recipient.single.role == DeviceRole.admin &&
      recipient.single.managementReady == expectedManagementReady &&
      recipient.single.status == DeviceStatus.active &&
      !recipient.single.isCurrent &&
      current.length == 1 &&
      current.single.isCurrent &&
      current.single.canManageDevices;
}

void _expectNoRootControlContent(WidgetTester tester) {
  for (final marker in const <String>[
    'root_private_key',
    'RootKeyEnvelope',
    'awiki.device.root-key-transfer',
    'root_key_imported_ack',
    'system_type',
    'auth_generation',
    'ciphertext',
  ]) {
    if (find.textContaining(marker, findRichText: true).evaluate().isNotEmpty) {
      fail('A private control marker reached the visible product UI.');
    }
  }
}
