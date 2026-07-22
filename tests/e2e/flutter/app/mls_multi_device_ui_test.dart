// [INPUT]: Audited awiki.info P6 v2 endpoints, a production AWiki Me owner,
//          an independently joined CLI device, dynamic OTP, and real macOS user presence.
// [OUTPUT]: Executable App evidence for same-DID Add/Welcome, future group
//           text/attachment delivery, exact-device Remove, and stable business membership.
// [POS]: Remote MLS lifecycle part of multi_device_join_ui_test.dart; all
//        cryptographic state stays inside each independent native Core root.

part of 'multi_device_join_ui_test.dart';

const String _mlsReadinessCaseId = 'MLS-MULTI-DEVICE-E2E-001';
const String _mlsRevokeCaseId = 'MLS-MULTI-DEVICE-E2E-002';
const Set<String> _revokedMlsErrorCodes = <String>{
  'auth_required',
  'permission_denied',
};
const Set<String> _forbiddenMlsProjectionKeys = <String>{
  'auth_generation',
  'ciphertext',
  'commit',
  'commit_b64u',
  'confirmation_tag_b64u',
  'crypto_group_id_b64u',
  'download_ticket',
  'download_ticket_b64u',
  'epoch',
  'epoch_authenticator',
  'epoch_secret',
  'group_key_package',
  'key_package',
  'leaf_index',
  'leaf_private_key',
  'mls_epoch',
  'mls_key_package_b64u',
  'nonce_b64u',
  'object_key_b64u',
  'private_key',
  'private_message_b64u',
  'ratchet_tree_b64u',
  'welcome',
  'welcome_b64u',
};

void _registerMlsMultiDeviceTests() {
  testWidgets(
    'real App owner adds and removes one same-DID CLI MLS endpoint',
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
        deviceRevokeEnabled: true,
        groupE2eeEnabled: true,
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
          'The remote MLS revoke gate requires real operating-system user presence.',
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
        multiDeviceRootTransferEnabled: false,
        multiDeviceDeviceRevokeEnabled: true,
        multiDeviceDirectE2eeEnabled: false,
        multiDeviceGroupE2eeEnabled: true,
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
              nickName: 'AWiki MLS lifecycle E2E',
            );
      } on Object {
        fail(
          'App MLS bootstrap registration failed without exposing remote data.',
        );
      }
      if (!adminSession.authenticated) {
        fail('The App MLS bootstrap identity was not authenticated.');
      }
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(adminSession.did);
      final bootstrapAdminDeviceId = _requireReadyBootstrapAdmin(
        initialRegistry,
      );

      final group = await bootstrap.groupApplicationService!.createGroup(
        name: 'AWiki MLS ${_nonce(8)}',
        slug: 'app_mls_${_nonce(10)}',
        description: '',
        goal: '',
        rules: '',
        messagePrompt: '',
        identity: const GroupIdentitySelection.didOnly(),
      );
      await _waitForAppCoreGroupReady(
        bootstrap: bootstrap,
        groupDid: group.groupId,
      );
      await _assertOneAppBusinessMember(
        bootstrap: bootstrap,
        groupDid: group.groupId,
        expectedDid: adminSession.did,
      );

      final historicalText = 'app-mls-before-welcome-${_nonce(18)}';
      final historical = await bootstrap.messagingService!.sendText(
        thread: AppThreadRef.group(group.groupId),
        content: historicalText,
      );
      if (!historical.isEncrypted ||
          historical.remoteId?.trim().isEmpty != false) {
        fail(
          'The pre-Welcome App group application was not securely accepted.',
        );
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

      final joinedDeviceId = await _joinCliMemberThroughApp(
        tester: tester,
        container: container,
        bootstrap: bootstrap,
        cli: cli,
        client: httpClient,
        config: config,
        account: account,
        presence: presence,
        handle: handle,
        did: adminSession.did,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
      );
      await _assertCliBusinessMembership(
        cli: cli,
        groupDid: group.groupId,
        expectedDid: adminSession.did,
      );
      await _assertCliMissingLocalMlsState(cli: cli, groupDid: group.groupId);
      await _assertCliGroupTextAbsent(
        cli: cli,
        groupDid: group.groupId,
        text: historicalText,
      );

      await _openGroupDetailFromDevices(tester, group);
      await _repairGroupThroughAppProjection(
        tester: tester,
        container: container,
        groupDid: group.groupId,
      );
      await _waitForCliGroupReady(cli: cli, groupDid: group.groupId);
      await container
          .read(groupEncryptionProvider(group.groupId).notifier)
          .load();
      await tester.pumpAndSettle();
      _requireVisibleGroupReady(tester);
      await _assertCliGroupTextAbsent(
        cli: cli,
        groupDid: group.groupId,
        text: historicalText,
      );

      final appToCliText = 'app-mls-future-${_nonce(18)}';
      final appToCli = await bootstrap.messagingService!.sendText(
        thread: AppThreadRef.group(group.groupId),
        content: appToCliText,
      );
      if (!appToCli.isEncrypted || appToCli.remoteId?.trim().isEmpty != false) {
        fail('The App did not send a canonical secure future group message.');
      }
      await _waitForCliGroupText(
        cli: cli,
        groupDid: group.groupId,
        text: appToCliText,
      );

      final cliToAppText = 'cli-mls-future-${_nonce(18)}';
      await _sendCliSecureGroupText(
        cli: cli,
        groupDid: group.groupId,
        text: cliToAppText,
      );
      await _waitForOneAppGroupMessage(
        bootstrap: bootstrap,
        groupDid: group.groupId,
        matches: (message) =>
            message.content == cliToAppText && message.isEncrypted,
      );

      final attachmentText = 'cli-mls-attachment-${_nonce(24)}';
      final attachmentCaption = 'cli-mls-caption-${_nonce(14)}';
      final sentAttachment = await _sendCliSecureGroupAttachment(
        cli: cli,
        groupDid: group.groupId,
        plaintext: attachmentText,
        caption: attachmentCaption,
      );
      final receivedAttachment = await _waitForOneAppGroupMessage(
        bootstrap: bootstrap,
        groupDid: group.groupId,
        matches: (message) =>
            message.isEncrypted &&
            message.attachment?.attachmentId == sentAttachment.attachmentId &&
            message.attachment?.filename == sentAttachment.filename &&
            (message.content == attachmentCaption ||
                message.attachment?.caption == attachmentCaption),
      );
      final messageId = receivedAttachment.remoteId?.trim() ?? '';
      if (messageId.isEmpty || receivedAttachment.attachment == null) {
        fail('The App group attachment projection was incomplete.');
      }
      final downloaded = await bootstrap.messagingService!.downloadAttachment(
        thread: AppThreadRef.group(group.groupId),
        messageId: messageId,
        attachmentId: sentAttachment.attachmentId,
      );
      if (downloaded.bytes == null ||
          utf8.decode(downloaded.bytes!) != attachmentText) {
        fail(
          'The App did not decrypt the one projected MLS attachment object.',
        );
      }
      await _assertOneAppBusinessMember(
        bootstrap: bootstrap,
        groupDid: group.groupId,
        expectedDid: adminSession.did,
      );
      _expectNoMlsPrivateContent(tester);

      await E2eCaseAttestationWriter.markPassed(
        _mlsReadinessCaseId,
        startedAt: startedAt,
        phases: const <String>[
          'independent_roots_and_pre_welcome_isolation',
          'app_reconciliation_add_welcome_ready',
          'bidirectional_future_group_message_once',
          'group_attachment_decrypted_once',
          'single_business_member_retained',
        ],
      );

      Navigator.of(tester.element(find.byType(GroupDetailPage))).pop();
      await _pumpUntil(
        tester,
        () => find.byType(DevicesPage).evaluate().length == 1,
        failure: 'The Devices page did not resume before MLS revoke.',
      );
      final revokeAction = find.byKey(Key('device-revoke-$joinedDeviceId'));
      await _tapOne(
        tester,
        revokeAction,
        failure: 'The MLS target device revoke action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () =>
            find
                .byKey(const Key('device-revoke-confirm-dialog'))
                .evaluate()
                .length ==
            1,
        failure: 'The MLS device revoke confirmation did not appear.',
      );
      await _tapOne(
        tester,
        find.byKey(const Key('device-revoke-confirm-action')),
        failure: 'The MLS device revoke confirmation was unavailable.',
      );
      await _waitForPresenceCompletion(
        tester,
        presence,
        expectedCompletions: 2,
        failure: 'The MLS revoke user-presence check did not complete.',
      );
      await _waitForRevokedProjection(
        tester: tester,
        bootstrap: bootstrap,
        did: adminSession.did,
        targetDeviceId: joinedDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
      );

      await _openGroupDetailFromDevices(tester, group);
      await _waitForVisibleGroupReadyAfterRevoke(
        tester: tester,
        container: container,
        bootstrap: bootstrap,
        groupDid: group.groupId,
      );
      final afterRevokeText = 'app-mls-after-revoke-${_nonce(18)}';
      final afterRevoke = await bootstrap.messagingService!.sendText(
        thread: AppThreadRef.group(group.groupId),
        content: afterRevokeText,
      );
      if (!afterRevoke.isEncrypted ||
          afterRevoke.remoteId?.trim().isEmpty != false) {
        fail(
          'The surviving App device could not send after exact MLS removal.',
        );
      }
      await _waitForOneAppGroupMessage(
        bootstrap: bootstrap,
        groupDid: group.groupId,
        matches: (message) =>
            message.content == afterRevokeText && message.isEncrypted,
      );
      final revokedCode = await cli._runForErrorCode(<String>[
        '--format',
        'json',
        'group',
        'messages',
        '--group',
        group.groupId,
        '--limit',
        '100',
      ]);
      if (!_revokedMlsErrorCodes.contains(revokedCode)) {
        fail('The revoked MLS endpoint did not fail at authorization.');
      }
      await _assertOneAppBusinessMember(
        bootstrap: bootstrap,
        groupDid: group.groupId,
        expectedDid: adminSession.did,
      );
      if (presence.calls != 2 ||
          presence.completions != 2 ||
          !presence.lastResult) {
        fail(
          'The MLS lifecycle did not use exactly two approved presence checks.',
        );
      }
      _expectNoMlsPrivateContent(tester);

      await E2eCaseAttestationWriter.markPassed(
        _mlsRevokeCaseId,
        startedAt: startedAt,
        phases: const <String>[
          'exact_device_revoked_with_remove_commit',
          'app_ready_only_after_remove_convergence',
          'revoked_endpoint_rejected_future_group_data',
          'surviving_app_leaf_and_business_member_retained',
        ],
      );
    },
    skip:
        !Platform.isMacOS ||
        !_RemoteJoinRunConfig.exists() ||
        !_invocationExpects(_mlsReadinessCaseId) ||
        !_invocationExpects(_mlsRevokeCaseId),
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<String> _joinCliMemberThroughApp({
  required WidgetTester tester,
  required ProviderContainer container,
  required AppBootstrap bootstrap,
  required _JoiningCli cli,
  required http.Client client,
  required _RemoteJoinRunConfig config,
  required _DedicatedAccount account,
  required _CountingRealUserPresencePort presence,
  required String handle,
  required String did,
  required String bootstrapAdminDeviceId,
}) async {
  final operationId = 'app-mls-join-${_nonce(10)}';
  final otp = await _requestAndResolveOtp(
    client: client,
    config: config,
    account: account,
    purpose: _joinPurpose,
    handle: handle,
  );
  final grant = await _exchangeJoinGrant(
    client: client,
    config: config,
    account: account,
    handle: handle,
    otp: otp,
    operationId: operationId,
  );
  final started = await cli.startJoin(
    did: did,
    operationId: operationId,
    accountVerificationToken: grant,
  );
  if (started.remoteState != 'pending' || started.sas != null) {
    fail('The MLS joining endpoint did not remain pending before approval.');
  }

  await _openDevicesPage(tester);
  await _pumpUntil(
    tester,
    () => find.text(started.protocolDeviceId).evaluate().length == 1,
    timeout: const Duration(seconds: 30),
    failure: 'The pending MLS device did not appear in the App.',
  );
  await _tapOne(
    tester,
    find.text(started.protocolDeviceId),
    failure: 'The pending MLS device could not be opened.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DeviceJoinApprovalSheet).evaluate().length == 1,
    failure: 'The MLS device approval surface did not open.',
  );
  await _waitForAppAdminChallenge(
    tester,
    container: container,
    expectedDid: did,
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
    expectedDid: did,
    expectedJoinSessionId: started.joinSessionId,
    expectedDeviceId: started.protocolDeviceId,
  );
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('device-approval-sas')).evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'The App did not derive the MLS device Join SAS.',
  );
  final appSas =
      tester.widget<Text>(find.byKey(const Key('device-approval-sas'))).data ??
      '';
  if (!_validSas(appSas) ||
      !_constantTimeAsciiEquals(appSas, joiningProgress.sas!)) {
    fail('The independently derived MLS Join SAS values differ.');
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
    fail('The App selected MLS endpoint management permission implicitly.');
  }
  await _tapOne(
    tester,
    sasSwitch,
    failure: 'The MLS SAS confirmation control was unavailable.',
  );
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('multi-device-approve'),
    failure: 'The explicit MLS device approval action was unavailable.',
  );
  await _waitForPresenceCompletion(
    tester,
    presence,
    expectedCompletions: 1,
    failure: 'The MLS Join user-presence check did not complete.',
  );

  final authorized = await cli.pollUntilAuthorized(
    started.joinSessionId,
    expectedDeviceId: started.protocolDeviceId,
  );
  if (authorized.protocolDeviceId != started.protocolDeviceId ||
      authorized.role != 'member' ||
      authorized.managementReady ||
      !authorized.isCurrent) {
    fail('The MLS endpoint was not activated as an independent member device.');
  }
  _requireJoinedMemberRegistry(
    await cli.loadRegistry(),
    protocolDeviceId: started.protocolDeviceId,
  );
  _requireAppRegistryMember(
    await bootstrap.deviceManagementCorePort!.identityDeviceRegistry(did),
    protocolDeviceId: started.protocolDeviceId,
    bootstrapAdminDeviceId: bootstrapAdminDeviceId,
  );

  final doneLabel = tester
      .element(find.byType(DeviceJoinApprovalSheet))
      .l10n
      .commonDone;
  await _tapOne(
    tester,
    find.text(doneLabel),
    failure: 'The completed MLS Join could not return to Devices.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DevicesPage).evaluate().length == 1,
    failure: 'The Devices page did not resume after MLS Join.',
  );
  return started.protocolDeviceId;
}

Future<void> _waitForAppCoreGroupReady({
  required AppBootstrap bootstrap,
  required String groupDid,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    final status = await bootstrap.groupEncryptionCorePort!.status(groupDid);
    if (status.readiness == GroupEncryptionReadiness.ready &&
        status.canSendSecure) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The App bootstrap device did not obtain a ready local MLS state.');
}

Future<void> _assertOneAppBusinessMember({
  required AppBootstrap bootstrap,
  required String groupDid,
  required String expectedDid,
}) async {
  final members = await bootstrap.groupApplicationService!.listMembers(
    groupDid,
  );
  if (members.length != 1 ||
      members.single.did != expectedDid ||
      members.single.role != 'owner') {
    fail('The same-DID MLS lifecycle changed the one-owner business roster.');
  }
}

Future<Map<String, Object?>> _cliSuccess(
  _JoiningCli cli,
  List<String> args,
) async {
  final data = _data(await cli._run(args), action: null);
  if (_containsMlsPrivateProjection(data)) {
    fail(
      'The public CLI group projection exposed MLS control or secret state.',
    );
  }
  return data;
}

Future<void> _assertCliBusinessMembership({
  required _JoiningCli cli,
  required String groupDid,
  required String expectedDid,
}) async {
  final list = await _cliSuccess(cli, <String>[
    '--format',
    'json',
    'group',
    'list',
    '--limit',
    '50',
  ]);
  final groups = list['groups'];
  if (groups is! List ||
      groups
              .whereType<Map>()
              .where((item) => item['group_did'] == groupDid)
              .length !=
          1 ||
      _stringMap(
            groups.whereType<Map>().singleWhere(
              (item) => item['group_did'] == groupDid,
            ),
          )['my_role'] !=
          'owner') {
    fail('The joined endpoint did not inherit one business group membership.');
  }
  final roster = await _cliSuccess(cli, <String>[
    '--format',
    'json',
    'group',
    'members',
    '--group',
    groupDid,
    '--limit',
    '50',
  ]);
  final members = roster['members'];
  if (members is! List ||
      members.length != 1 ||
      members.single is! Map ||
      (members.single as Map)['did'] != expectedDid ||
      (members.single as Map)['role'] != 'owner') {
    fail(
      'The joined endpoint projected duplicate or incorrect business members.',
    );
  }
}

Future<Map<String, Object?>> _cliGroupStatus({
  required _JoiningCli cli,
  required String groupDid,
}) async {
  final data = await _cliSuccess(cli, <String>[
    '--format',
    'json',
    'group',
    'secure',
    'status',
    '--group',
    groupDid,
  ]);
  final status = data['status'];
  if (status is! Map) {
    fail('The CLI returned no secret-free MLS readiness projection.');
  }
  return _stringMap(status);
}

Future<void> _assertCliMissingLocalMlsState({
  required _JoiningCli cli,
  required String groupDid,
}) async {
  final status = await _cliGroupStatus(cli: cli, groupDid: groupDid);
  final readiness = status['local_readiness'];
  if (status['state'] != 'MissingLocalState' ||
      status['can_send_secure'] != false ||
      readiness is! Map ||
      readiness['has_local_state'] != false ||
      readiness['has_active_membership'] != false) {
    fail('The new device did not remain isolated before its own Welcome.');
  }
}

Future<List<Map<String, Object?>>> _cliGroupMessages({
  required _JoiningCli cli,
  required String groupDid,
}) async {
  final data = await _cliSuccess(cli, <String>[
    '--format',
    'json',
    'group',
    'messages',
    '--group',
    groupDid,
    '--limit',
    '100',
  ]);
  final messages = data['messages'];
  if (messages is! List || messages.any((item) => item is! Map)) {
    fail('The CLI returned no safe group message projection.');
  }
  return messages.cast<Map>().map(_stringMap).toList(growable: false);
}

Future<void> _assertCliGroupTextAbsent({
  required _JoiningCli cli,
  required String groupDid,
  required String text,
}) async {
  final messages = await _cliGroupMessages(cli: cli, groupDid: groupDid);
  if (messages.any((message) => message['content'] == text)) {
    fail('The new MLS endpoint received a pre-Welcome group application.');
  }
}

Future<void> _openGroupDetailFromDevices(
  WidgetTester tester,
  GroupSummary group,
) async {
  final devices = find.byType(DevicesPage);
  if (devices.evaluate().length != 1) {
    fail('The current Devices route was not available for group navigation.');
  }
  unawaited(
    Navigator.of(tester.element(devices)).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => GroupDetailPage(initialGroup: group),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byType(GroupEncryptionStatusCard).evaluate().length == 1,
    failure: 'The App group encryption status surface did not open.',
  );
}

Future<void> _repairGroupThroughAppProjection({
  required WidgetTester tester,
  required ProviderContainer container,
  required String groupDid,
}) async {
  await _pumpUntil(
    tester,
    () =>
        find
            .byKey(const Key('group-encryption-status-title'))
            .evaluate()
            .length ==
        1,
    failure: 'The App did not render group encryption readiness.',
  );
  final repair = container
      .read(groupEncryptionProvider(groupDid).notifier)
      .retry();
  await tester.pump();
  final l10n = tester.element(find.byType(GroupEncryptionStatusCard)).l10n;
  await _pumpUntil(
    tester,
    () => find.text(l10n.groupEncryptionPreparingTitle).evaluate().length == 1,
    failure: 'The App retained a stale ready claim during MLS reconciliation.',
  );
  await repair;
  await tester.pumpAndSettle();
  _requireVisibleGroupReady(tester);
}

void _requireVisibleGroupReady(WidgetTester tester) {
  final card = find.byType(GroupEncryptionStatusCard);
  if (card.evaluate().length != 1) {
    fail('The App group encryption status card was unavailable.');
  }
  final l10n = tester.element(card).l10n;
  if (find.text(l10n.groupEncryptionReadyTitle).evaluate().length != 1) {
    fail('The App did not visibly converge to ready group encryption.');
  }
}

Future<void> _waitForCliGroupReady({
  required _JoiningCli cli,
  required String groupDid,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await _cliGroupMessages(cli: cli, groupDid: groupDid);
    final status = await _cliGroupStatus(cli: cli, groupDid: groupDid);
    final readiness = status['local_readiness'];
    if (status['state'] == 'Ready' &&
        status['can_send_secure'] == true &&
        readiness is Map &&
        readiness['has_local_state'] == true &&
        readiness['has_active_membership'] == true) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The independent device did not consume its Welcome and become ready.');
}

Future<void> _sendCliSecureGroupText({
  required _JoiningCli cli,
  required String groupDid,
  required String text,
}) async {
  final messageId = 'app-mls-msg-${_nonce(20)}';
  final data = await _cliSuccess(cli, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    groupDid,
    '--text',
    text,
    '--secure',
    'required',
    '--client-message-id',
    messageId,
    '--idempotency-key',
    'op-$messageId',
  ]);
  final message = data['message'];
  final delivery = data['delivery'];
  if (message is! Map ||
      message['secure'] != true ||
      delivery is! Map ||
      delivery['accepted'] != true ||
      delivery['final_acceptance'] != true) {
    fail('The CLI did not securely accept the future group message.');
  }
}

Future<void> _waitForCliGroupText({
  required _JoiningCli cli,
  required String groupDid,
  required String text,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final matches = (await _cliGroupMessages(cli: cli, groupDid: groupDid))
        .where(
          (message) => message['content'] == text && message['secure'] == true,
        )
        .toList(growable: false);
    if (matches.length == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final stable = (await _cliGroupMessages(cli: cli, groupDid: groupDid))
          .where(
            (message) =>
                message['content'] == text && message['secure'] == true,
          )
          .length;
      if (stable == 1) {
        return;
      }
      fail('The independent MLS endpoint projected a duplicate group message.');
    }
    if (matches.length > 1) {
      fail('The independent MLS endpoint projected a duplicate group message.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail(
    'The independent MLS endpoint did not receive the future group message.',
  );
}

Future<ChatMessage> _waitForOneAppGroupMessage({
  required AppBootstrap bootstrap,
  required String groupDid,
  required bool Function(ChatMessage message) matches,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final found = (await bootstrap.groupApplicationService!.listMessages(
      groupDid,
      limit: 100,
    )).where(matches).toList(growable: false);
    if (found.length == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final stable = (await bootstrap.groupApplicationService!.listMessages(
        groupDid,
        limit: 100,
      )).where(matches).toList(growable: false);
      if (stable.length == 1) {
        return stable.single;
      }
      fail('The App projected a duplicate MLS group application.');
    }
    if (found.length > 1) {
      fail('The App projected a duplicate MLS group application.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The App did not receive the expected MLS group application.');
}

Future<_CliGroupAttachment> _sendCliSecureGroupAttachment({
  required _JoiningCli cli,
  required String groupDid,
  required String plaintext,
  required String caption,
}) async {
  final fixtureDirectory = Directory('${cli.config.cliWorkspace}/mls-fixtures');
  await fixtureDirectory.create(recursive: true);
  final filename = 'app-mls-${_nonce(10)}.txt';
  final file = File('${fixtureDirectory.path}/$filename');
  await file.writeAsString(plaintext, flush: true);
  final messageId = 'app-mls-attachment-${_nonce(18)}';
  final data = await _cliSuccess(cli, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    groupDid,
    '--file',
    file.path,
    '--mime-type',
    'text/plain',
    '--text',
    caption,
    '--secure',
    'required',
    '--client-message-id',
    messageId,
    '--idempotency-key',
    'op-$messageId',
  ]);
  final message = data['message'];
  final attachment = data['attachment'];
  final delivery = data['delivery'];
  final attachmentMap = attachment is Map ? _stringMap(attachment) : null;
  final attachmentId = attachmentMap?['attachment_id']?.toString().trim() ?? '';
  if (message is! Map ||
      message['secure'] != true ||
      message['type'] != 'attachment_manifest' ||
      attachmentId.isEmpty ||
      attachmentMap?['object_encryption_mode'] != 'object-e2ee' ||
      delivery is! Map ||
      delivery['accepted'] != true ||
      delivery['final_acceptance'] != true) {
    fail('The CLI did not securely accept one MLS attachment object.');
  }
  return _CliGroupAttachment(attachmentId: attachmentId, filename: filename);
}

Future<void> _waitForVisibleGroupReadyAfterRevoke({
  required WidgetTester tester,
  required ProviderContainer container,
  required AppBootstrap bootstrap,
  required String groupDid,
}) async {
  await bootstrap.messageSyncService!.syncNow(reason: 'e2e_mls_remove');
  await _repairGroupThroughAppProjection(
    tester: tester,
    container: container,
    groupDid: groupDid,
  );
}

bool _containsMlsPrivateProjection(Object? value) {
  if (value is Map) {
    final systemType = value['system_type'];
    final schema = value['schema'];
    final noticeType = value['notice_type'];
    final method = value['method'];
    if ((systemType is String && systemType.startsWith('awiki.')) ||
        (schema is String && schema.startsWith('awiki.group.system_event.')) ||
        noticeType == 'welcome-delivery' ||
        noticeType == 'commit-delivery' ||
        method == 'group.e2ee.notice') {
      return true;
    }
    return value.entries.any(
      (entry) =>
          _forbiddenMlsProjectionKeys.contains(
            entry.key.toString().toLowerCase(),
          ) ||
          _containsMlsPrivateProjection(entry.value),
    );
  }
  if (value is Iterable) {
    return value.any(_containsMlsPrivateProjection);
  }
  return false;
}

void _expectNoMlsPrivateContent(WidgetTester tester) {
  for (final marker in const <String>[
    'Leaf',
    'Welcome',
    'Commit',
    'epoch',
    '私钥',
  ]) {
    if (find.textContaining(marker).evaluate().isNotEmpty) {
      fail('The App exposed MLS control or private-state content.');
    }
  }
}

class _CliGroupAttachment {
  const _CliGroupAttachment({
    required this.attachmentId,
    required this.filename,
  });

  final String attachmentId;
  final String filename;
}
