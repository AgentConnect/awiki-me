part of 'multi_device_join_ui_test.dart';

const String _didWebAppCaseId = 'DID-WEB-APP-E2E-001';

String _webProtectedServices(List<IdentityDocumentService> services) =>
    jsonEncode([
      for (final s in services.where((s) => s.isProtected))
        [
          s.id,
          s.type,
          s.endpoint,
          s.serviceDid,
          s.profiles,
          s.securityProfiles,
        ],
    ]);

Future<IdentityRegistrationResult> _registerWebThroughUi(
  WidgetTester tester,
  AppBootstrap bootstrap,
  _DedicatedAccount account,
  String handle,
  E2eUserPresencePort presence, {
  required String diagnosticPath,
}) async {
  // Observe the same production capability reads independently so a failing
  // Core/Server Info prerequisite retains its closed error code in the driver.
  await bootstrap.identityCorePort!.identityCreationMethods().timeout(
    const Duration(seconds: 45),
  );
  await bootstrap.identityCorePort!.pendingIdentityRegistrations().timeout(
    const Duration(seconds: 45),
  );
  await bootstrap.onboardingSupportService!.loadServerInfo().timeout(
    const Duration(seconds: 45),
  );
  await tester.pumpWidget(
    AwikiMeApp(
      bootstrap: bootstrap,
      providerOverrides: [userPresencePortProvider.overrideWithValue(presence)],
    ),
  );
  await _pumpUntil(
    tester,
    () =>
        find.byKey(const Key('identity-method-picker')).evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'Configured service did not advertise both creation methods.',
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(OnboardingPage)),
  );
  if (container.read(onboardingProvider).didMethod != IdentityDidMethod.wba) {
    fail('New identity creation no longer defaults to WBA.');
  }
  await _tapOne(
    tester,
    find.byKey(const Key('identity-method-web')),
    failure: 'Web creation option was not visible.',
  );
  if (container.read(onboardingProvider).didMethod != IdentityDidMethod.web ||
      find
              .byKey(const Key('identity-web-admin-limitation'))
              .evaluate()
              .length !=
          1) {
    fail('Web selection omitted the first-admin loss limitation.');
  }
  await _enterText(tester, 'e2e-phone-input', account.phone);
  await _enterText(tester, 'e2e-handle-input', handle);
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-send-otp-button'),
    failure: 'Web registration OTP action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.bySemanticsIdentifier('e2e-otp-sent').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 45),
    failure: 'Web registration OTP did not complete.',
  );
  await _enterText(tester, 'e2e-otp-input', account.fixedOtp);
  final mac = find.byKey(const Key('onboarding-mac-phone-submit-action'));
  await _tapOne(
    tester,
    mac.evaluate().isNotEmpty
        ? mac
        : find.byKey(const Key('onboarding-phone-submit-action')),
    failure: 'Web registration submit was unavailable.',
  );
  try {
    await _pumpUntil(
      tester,
      () {
        final session = container.read(sessionProvider).session;
        return session?.did.startsWith('did:web:') == true &&
            find.bySemanticsIdentifier('e2e-authenticated').evaluate().length ==
                1;
      },
      timeout: const Duration(seconds: 90),
      failure: 'Visible Web registration did not activate a Web identity.',
    );
  } on Object {
    final state = container.read(onboardingProvider);
    final session = container.read(sessionProvider).session;
    final observation = <String, Object?>{
      'stage': 'activation',
      'outcome': state.phoneRegistrationOutcome.name,
      'failureCode': _appPairSafeToken(
        state.phoneRegistrationFailureCode ?? 'none',
      ),
      'selectedMethod': state.didMethod.name,
      'sessionPresent': session != null,
      'sessionWeb': session?.did.startsWith('did:web:') ?? false,
      'sessionHasBearer': session?.jwtToken?.isNotEmpty ?? false,
      'authenticatedMarkerCount': find
          .bySemanticsIdentifier('e2e-authenticated')
          .evaluate()
          .length,
    };
    try {
      final identity = await bootstrap.identityCorePort!.defaultIdentity();
      observation['coreIdentityPresent'] = identity != null;
      observation['coreIdentityWeb'] =
          identity?.did.startsWith('did:web:') ?? false;
      observation['coreIdentityAuthenticated'] =
          identity?.authenticated ?? false;
      observation['pendingPhases'] =
          (await bootstrap.identityCorePort!.pendingIdentityRegistrations())
              .map((item) => item.phase)
              .toList();
    } on Object catch (error) {
      observation['coreReadError'] = _appPairClosedRegistrationError(error);
    }
    await File(diagnosticPath).writeAsString(jsonEncode(observation));
    rethrow;
  }
  return IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: await container.read(identityCorePortProvider).defaultIdentity(),
  );
}

Future<void> _requireWebDeviceUi(
  WidgetTester tester,
  ProviderContainer container, {
  required bool admin,
}) async {
  await _openDevicesPage(tester, expectNoRecovery: true);
  await container.read(devicesProvider.notifier).refreshRegistryOnly();
  await tester.pump();
  final state = container.read(devicesProvider);
  final caps = state.registry?.methodCapabilities;
  if (caps?.method != IdentityDidMethod.web ||
      caps?.rootTransfer != false ||
      caps?.handleRecovery != false ||
      caps?.rootImport != false ||
      state.currentDeviceCanManage != admin) {
    fail('Web device method or management capabilities were incorrect.');
  }
  if (find
          .byKey(const Key('root-transfer-grant-management'))
          .evaluate()
          .isNotEmpty ||
      find.byKey(const Key('identity-services-open')).evaluate().isNotEmpty !=
          admin) {
    fail('Web device UI exposed an unavailable management action.');
  }
  for (final device in state.registry!.devices) {
    if (find
            .byKey(Key('device-grant-management-${device.protocolDeviceId}'))
            .evaluate()
            .isNotEmpty ||
        (!admin &&
            find
                .byKey(Key('device-revoke-${device.protocolDeviceId}'))
                .evaluate()
                .isNotEmpty)) {
      fail('Web device UI exposed a transfer or member revoke action.');
    }
  }
}

Future<void> _runWebAdmin({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String did,
  required String joinedDeviceId,
  required _AppPairContentAdminResources resources,
  required E2eUserPresencePort presence,
  required void Function(AppBootstrap) onReopened,
}) async {
  await _leaveCompletedAppPairApproval(tester);
  await _requireWebDeviceUi(tester, container, admin: true);
  final port = container.read(identityDocumentCorePortProvider);
  final before = await port.identityServices(did);
  final protected = before.services.where((s) => s.isProtected).toList();
  if (before.pending || protected.isEmpty) {
    fail('Web service baseline was invalid.');
  }
  await _tapOne(
    tester,
    find.byKey(const Key('identity-services-open')),
    failure: 'Web admin services entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () =>
        find
            .byKey(const Key('identity-service-add'))
            .hitTestable()
            .evaluate()
            .length ==
        1,
    failure: 'Web services editor did not load.',
  );
  await _tapOne(
    tester,
    find.byKey(const Key('identity-service-add')),
    failure: 'Web service add action was unavailable.',
  );
  final id = '$did#e2e-links';
  final endpoint = Uri.parse(
    config.baseUrl,
  ).resolve('/e2e-public-links').toString();
  await tester.enterText(find.byKey(const Key('identity-service-id')), id);
  await tester.enterText(
    find.byKey(const Key('identity-service-type')),
    'Links',
  );
  await tester.enterText(
    find.byKey(const Key('identity-service-endpoint')),
    endpoint,
  );
  await _tapOne(
    tester,
    find.byKey(const Key('identity-service-save')),
    failure: 'Web service save action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.text(endpoint).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 60),
    failure: 'Web service update did not become visible.',
  );
  final after = await port.identityServices(did);
  if (after.pending ||
      !after.services.any((s) => s.id == id && s.endpoint == endpoint) ||
      _webProtectedServices(protected) !=
          _webProtectedServices(after.services)) {
    fail(
      'Web service update changed protected entries or left an unresolved operation.',
    );
  }
  Navigator.of(tester.element(find.byType(IdentityServicesPage))).pop();
  await tester.pumpAndSettle();

  final peer = resources.peer!;
  final peerDid = resources.peerDid!;
  final conversationId = resources.directConversationId!;
  if (!peerDid.startsWith('did:wba:')) {
    fail('The independent peer was not WBA.');
  }
  await peer.startRealtimeListener();
  await config.coordinator.publish(
    'admin',
    'web_peer_ready',
    data: {'peerDid': peerDid, 'conversationId': conversationId},
  );
  await config.coordinator.waitFor(
    'joiner',
    'web_member_readonly',
    timeout: const Duration(minutes: 2),
  );
  final incoming = _appPairMessage(config.runId, 'web-incoming');
  final incomingId = await peer.sendDirectText(to: did, text: incoming);
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: incoming,
    messageId: incomingId,
    senderDid: peerDid,
    receiverDid: did,
    isMine: false,
  );
  await config.coordinator.publish(
    'admin',
    'web_incoming',
    data: {'messageId': incomingId},
  );
  final reply = await config.coordinator.waitFor(
    'joiner',
    'web_reply',
    timeout: const Duration(minutes: 2),
  );
  await peer.waitForDirectNotification(
    messageId: _required(reply, 'messageId'),
    content: _appPairMessage(config.runId, 'web-reply'),
    senderDid: did,
    recipientDid: peerDid,
  );

  await _tapOne(
    tester,
    find.byKey(Key('device-revoke-$joinedDeviceId')),
    failure: 'Web admin did not expose exact member revoke.',
  );
  await _pumpUntil(
    tester,
    () =>
        find
            .byKey(const Key('device-revoke-confirm-dialog'))
            .evaluate()
            .length ==
        1,
    failure: 'Web revoke confirmation was not visible.',
  );
  final calls = presence.calls;
  await _tapOne(
    tester,
    find.byKey(const Key('device-revoke-confirm-action')),
    failure: 'Web revoke confirmation was unavailable.',
  );
  await _pumpUntil(
    tester,
    () =>
        container
            .read(devicesProvider)
            .registry
            ?.devices
            .any(
              (d) =>
                  d.protocolDeviceId == joinedDeviceId &&
                  d.status == DeviceStatus.revoked,
            ) ==
        true,
    timeout: const Duration(seconds: 90),
    failure: 'Web revoke did not converge to revoked.',
  );
  if (presence.calls != calls + 1) {
    fail('Web revoke did not require one fresh user presence.');
  }
  await config.coordinator.publish('admin', 'web_revoked');
  await config.coordinator.waitFor(
    'joiner',
    'web_auth_fenced',
    timeout: const Duration(minutes: 2),
  );

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await bootstrap.dispose();
  final reopened = await AppBootstrap.create(
    environment: _joinOnlyEnvironment(
      config,
      enableMessageSyncCore: true,
      enableDeviceRevoke: true,
    ),
    appStateRoot: config.adminStateRoot,
  );
  onReopened(reopened);
  await tester.pumpWidget(
    AwikiMeApp(
      bootstrap: reopened,
      providerOverrides: [userPresencePortProvider.overrideWithValue(presence)],
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byType(AppShell).evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'Reopened Web admin did not restore the shell.',
  );
  final restored = await _waitForAuthenticatedApp(tester, expectedDid: did);
  await _requireWebDeviceUi(tester, restored, admin: true);
  final restoredServices = await restored
      .read(identityDocumentCorePortProvider)
      .identityServices(did);
  if (restoredServices.pending ||
      !restoredServices.services.any(
        (s) => s.id == id && s.endpoint == endpoint,
      )) {
    fail(
      'Web service update did not survive closing and reopening the App/Core root.',
    );
  }
  final post = _appPairMessage(config.runId, 'web-reopened');
  final sent = await reopened.messagingService!.sendConversationText(
    conversation: AppConversationReadRef.fromConversationId(conversationId),
    content: post,
  );
  final postId = _requireCommittedContentMessage(
    sent,
    conversationId: conversationId,
    senderDid: did,
    isMine: true,
    failure: 'Reopened Web admin could not send.',
  );
  await peer.waitForDirectNotification(
    messageId: postId,
    content: post,
    senderDid: did,
    recipientDid: peerDid,
  );
  await E2eCaseAttestationWriter.markPassed(
    _didWebAppCaseId,
    phases: const [
      'visible_web_creation_default_wba',
      'same_pending_join_reopened_without_otp',
      'sas_member_join_and_method_gates',
      'protected_services_preserved',
      'wba_cli_web_apps_bidirectional',
      'exact_revoke_and_auth_fence',
      'admin_root_reopened_and_sent',
    ],
  );
}

Future<void> _runWebJoiner({
  required WidgetTester tester,
  required _AppPairRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required String did,
}) async {
  await _leaveCompletedAppPairJoin(tester);
  await _requireWebDeviceUi(tester, container, admin: false);
  final peer = await config.coordinator.waitFor(
    'admin',
    'web_peer_ready',
    timeout: const Duration(minutes: 2),
  );
  final peerDid = _required(peer, 'peerDid');
  final conversationId = _required(peer, 'conversationId');
  await config.coordinator.publish('joiner', 'web_member_readonly');
  final incoming = await config.coordinator.waitFor(
    'admin',
    'web_incoming',
    timeout: const Duration(minutes: 2),
  );
  await _waitForAppPairMessage(
    container: container,
    messaging: bootstrap.messagingService!,
    conversationId: conversationId,
    content: _appPairMessage(config.runId, 'web-incoming'),
    messageId: _required(incoming, 'messageId'),
    senderDid: peerDid,
    receiverDid: did,
    isMine: false,
  );
  Navigator.of(tester.element(find.byType(DevicesPage))).pop();
  await tester.pumpAndSettle();
  await _openAppPairConversation(
    tester: tester,
    conversationId: conversationId,
    content: _appPairMessage(config.runId, 'web-incoming'),
  );
  final replyText = _appPairMessage(config.runId, 'web-reply');
  await _enterText(tester, 'e2e-chat-input', replyText);
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-chat-send-button'),
    failure: 'The Web member chat send action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => container
        .read(chatThreadProvider(conversationId))
        .messages
        .any(
          (m) =>
              m.content == replyText &&
              m.remoteId?.isNotEmpty == true &&
              m.sendState == MessageSendState.sent,
        ),
    timeout: const Duration(seconds: 90),
    failure: 'The Web member visible reply did not commit.',
  );
  final reply = container
      .read(chatThreadProvider(conversationId))
      .messages
      .where(
        (m) =>
            m.content == replyText &&
            m.remoteId?.isNotEmpty == true &&
            m.sendState == MessageSendState.sent,
      )
      .single;
  final replyId = _requireCommittedContentMessage(
    reply,
    conversationId: conversationId,
    senderDid: did,
    isMine: true,
    failure: 'Web member reply did not use the exact account DID.',
  );
  await config.coordinator.publish(
    'joiner',
    'web_reply',
    data: {'messageId': replyId},
  );
  await config.coordinator.waitFor(
    'admin',
    'web_revoked',
    timeout: const Duration(minutes: 2),
  );
  var fenced = false;
  try {
    await bootstrap.deviceManagementCorePort!.identityDeviceRegistry(did);
  } on DeviceManagementTransportException catch (error) {
    fenced = error.code == 'device_authorization_inactive';
  } on core.AwikiImCoreException catch (error) {
    fenced = error.statusCode == 401;
  }
  if (!fenced) {
    fail('The revoked Web member did not receive an authentication fence.');
  }
  await config.coordinator.publish('joiner', 'web_auth_fenced');
}
