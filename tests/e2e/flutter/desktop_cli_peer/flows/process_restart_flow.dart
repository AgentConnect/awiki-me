part of '../desktop_cli_peer_e2e.dart';

const String _processRestartCaseId = 'PROCESS-RESTART-E2E-001';

void runDesktopCliPeerProcessRestartPhaseA() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Process restart phase A persists real App state', (
    tester,
  ) async {
    final config = _DesktopCliPeerSmokeConfig.load();
    expect(config.e2eCase, DesktopCliPeerIntegrationCase.processRestart);
    final handoffPath = config.processRestartHandoffPath?.trim() ?? '';
    if (handoffPath.isEmpty) {
      fail('Process-restart E2E requires processRestart.handoffPath.');
    }

    final bootstrap = await AppBootstrap.create(
      environment: config.environment,
      appStateRoot: config.appStateRoot,
    );
    var disposed = false;
    addTearDown(() async {
      if (!disposed) {
        await bootstrap.dispose();
      }
    });
    final session = await _prepareAppIdentity(
      bootstrap.onboardingService!,
      config,
    );
    await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    final robot = _DesktopAppRobot(tester);
    await robot.activate(session);

    final canonicalCliDid = await _currentCliDid(config);
    final nonce = _messageNonce();
    final directAppText = 'restart app direct ${config.runId} $nonce';
    final directCliText = 'restart cli direct ${config.runId} $nonce';
    final groupAppText = 'restart app group ${config.runId} $nonce';
    final groupCliText = 'restart cli group ${config.runId} $nonce';

    final direct = await robot.startDirectConversation(config.cliHandle);
    final directDisplayName = robot.expectedDirectDisplayName(direct);
    expect(directDisplayName, _nicknameFixtureDisplayName);
    final peerDid = requireMatchingCliPeerDid(
      canonicalCliDid: canonicalCliDid,
      observedPeerDid: direct.targetDid ?? '',
    );
    await robot.sendText(directAppText);
    final directAppMessage = await _waitForUiMessage(
      robot: robot,
      conversationId: direct.conversationId,
      content: directAppText,
      senderDid: session.did,
      sendState: MessageSendState.sent,
    );

    final groupName = 'AWiki restart ${config.runId} $nonce';
    final group = await robot.createGroup(groupName);
    final groupDid = group.groupId!.trim();
    final cliHandle = config.cliHandle.trim().toLowerCase();
    final cliFullHandle = cliHandle.contains('.')
        ? cliHandle
        : '$cliHandle.${config.environment.didDomain}';
    await robot.addGroupMember(
      cliFullHandle,
      expectedDisplayName: _nicknameFixtureDisplayName,
    );
    final cliMember = await _findGroupMember(
      groups: bootstrap.groupApplicationService!,
      groupDid: groupDid,
      memberRef: cliFullHandle,
    );
    final cliMemberDid = requireMatchingCliPeerDid(
      canonicalCliDid: canonicalCliDid,
      observedPeerDid: cliMember.did,
    );
    final memberProfile = robot.container
        .read(peerDisplayProfileProvider)
        .forDid(cliMemberDid);
    final cliMemberDisplayName = const PeerDisplayNameResolver().resolve(
      nickname: memberProfile?.displayName,
      fullHandle: memberProfile?.handle ?? cliMember.handle,
      did: cliMemberDid,
    );
    expect(cliMemberDisplayName, _nicknameFixtureDisplayName);
    await robot.expectGroupMemberDisplayName(
      member: cliMember,
      expectedName: cliMemberDisplayName,
    );
    await robot.sendText(groupAppText);
    final groupAppMessage = await _waitForUiMessage(
      robot: robot,
      conversationId: group.conversationId,
      content: groupAppText,
      senderDid: session.did,
      sendState: MessageSendState.sent,
    );

    await robot.navigateToContacts();
    final totalUnreadBaseline = robot.container.read(
      conversationListProvider.select((state) => state.unreadCount),
    );
    final directCliMessageId = await _cliSendDirectText(
      config: config,
      text: directCliText,
    );
    await _waitForUiUnreadClosedLoop(
      robot: robot,
      conversationId: direct.conversationId,
      expectedText: directCliText,
      expectedConversationUnread: 1,
      expectedTotalUnread: totalUnreadBaseline + 1,
    );
    final groupSend = await _runCli(config, <String>[
      '--format',
      'json',
      'msg',
      'send',
      '--group',
      groupDid,
      '--text',
      groupCliText,
    ]);
    if (groupSend.exitCode != 0) {
      fail(
        'Process-restart group send failed: '
        '${_summarizeCliResult(groupSend)}',
      );
    }
    final groupCliMessageId = _jsonStringAt(groupSend.stdout, const <Object>[
      'data',
      'message',
      'id',
    ]);
    if (groupCliMessageId == null) {
      fail('Process-restart group send returned no canonical message ID.');
    }
    await _waitForUiUnreadClosedLoop(
      robot: robot,
      conversationId: group.conversationId,
      expectedText: groupCliText,
      expectedConversationUnread: 1,
      expectedTotalUnread: totalUnreadBaseline + 2,
    );
    await _waitForUiConversationUnread(
      robot: robot,
      conversationId: direct.conversationId,
      expectedUnread: 1,
      expectedTotalUnread: totalUnreadBaseline + 2,
      expectedLastMessage: directCliText,
    );
    final handoff = _ProcessRestartHandoff(
      runId: config.runId,
      phaseAProcessId: pid,
      appStateRootDigest: _processRestartStateRootDigest(config.appStateRoot),
      ownerDid: session.did,
      directConversationId: direct.conversationId,
      directPeerPersonaId: direct.peerPersonaId!,
      directPeerDid: peerDid,
      directDisplayName: directDisplayName,
      directAppMessageId: directAppMessage.remoteId!,
      directAppText: directAppText,
      directCliMessageId: directCliMessageId,
      directCliText: directCliText,
      groupConversationId: group.conversationId,
      groupDid: groupDid,
      groupName: groupName,
      groupAppMessageId: groupAppMessage.remoteId!,
      groupAppText: groupAppText,
      groupCliMessageId: groupCliMessageId,
      groupCliText: groupCliText,
      groupMemberDid: cliMemberDid,
      groupMemberDisplayName: cliMemberDisplayName,
      totalUnreadBaseline: totalUnreadBaseline,
    );
    final handoffFile = File(handoffPath);
    await handoffFile.parent.create(recursive: true);
    await handoffFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(handoff.toJson()),
      flush: true,
    );
    await E2eScenarioProgressWriter.record('process_restart_phase_a_persisted');

    // Do not call logout: a real process exit preserves the active identity.
    // Explicitly dispose native/runtime resources so phase B can open the same
    // scope from a different Flutter process without sharing memory.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap.dispose();
    disposed = true;
  });
}

void runDesktopCliPeerProcessRestartPhaseB() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Process restart phase B restores only persisted App state', (
    tester,
  ) async {
    final startedAt = DateTime.now().toUtc();
    final config = _DesktopCliPeerSmokeConfig.load();
    expect(config.e2eCase, DesktopCliPeerIntegrationCase.processRestart);
    final handoffPath = config.processRestartHandoffPath?.trim() ?? '';
    if (handoffPath.isEmpty) {
      fail('Process-restart E2E requires processRestart.handoffPath.');
    }
    final handoff = _ProcessRestartHandoff.read(File(handoffPath));
    expect(handoff.runId, config.runId);
    expect(handoff.phaseAProcessId, isNot(pid));
    expect(
      handoff.appStateRootDigest,
      _processRestartStateRootDigest(config.appStateRoot),
    );

    final bootstrap = await AppBootstrap.create(
      environment: config.environment,
      appStateRoot: config.appStateRoot,
    );
    var disposed = false;
    addTearDown(() async {
      if (!disposed) {
        await bootstrap.dispose();
      }
    });
    final restored = await bootstrap.appSessionService!.restoreSession();
    if (restored == null) {
      fail('The second Flutter process could not restore the active identity.');
    }
    expect(restored.did, handoff.ownerDid);

    await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    final robot = _DesktopAppRobot(tester);
    await robot.activate(restored);

    await _waitForUiConversationUnread(
      robot: robot,
      conversationId: handoff.directConversationId,
      expectedUnread: 1,
      expectedTotalUnread: handoff.totalUnreadBaseline + 2,
      expectedLastMessage: handoff.directCliText,
    );
    await _waitForUiConversationUnread(
      robot: robot,
      conversationId: handoff.groupConversationId,
      expectedUnread: 1,
      expectedTotalUnread: handoff.totalUnreadBaseline + 2,
      expectedLastMessage: handoff.groupCliText,
    );
    final conversations = robot.container
        .read(conversationListProvider)
        .conversations;
    requireExactlyOneDirectConversationForPersona(
      conversations: conversations,
      conversationId: handoff.directConversationId,
      peerPersonaId: handoff.directPeerPersonaId,
      unreadCount: 1,
      lastMessage: handoff.directCliText,
    );
    requireExactlyOneGroupConversation(
      conversations: conversations,
      conversationId: handoff.groupConversationId,
      canonicalGroupDid: handoff.groupDid,
      unreadCount: 1,
      lastMessage: handoff.groupCliText,
    );
    await robot.expectConversationRowPresentation(
      conversationId: handoff.directConversationId,
      expectedTitle: handoff.directDisplayName,
      expectedPreview: handoff.directCliText,
      unreadCount: 1,
    );
    await robot.expectConversationRowPresentation(
      conversationId: handoff.groupConversationId,
      expectedTitle: handoff.groupName,
      expectedPreview: handoff.groupCliText,
      unreadCount: 1,
    );
    await robot.openConversationRowWithFirstVisibleTitle(
      conversationId: handoff.directConversationId,
      expectedTitle: handoff.directDisplayName,
    );
    await _assertUiMessagesExactlyOnce(
      robot: robot,
      conversationId: handoff.directConversationId,
      expected: <ExactMessageExpectation>[
        ExactMessageExpectation(
          canonicalId: handoff.directAppMessageId,
          content: handoff.directAppText,
          conversationId: handoff.directConversationId,
          senderDid: handoff.ownerDid,
        ),
        ExactMessageExpectation(
          canonicalId: handoff.directCliMessageId,
          content: handoff.directCliText,
          conversationId: handoff.directConversationId,
          senderDid: handoff.directPeerDid,
        ),
      ],
    );
    await _waitForUiConversationUnread(
      robot: robot,
      conversationId: handoff.directConversationId,
      expectedUnread: 0,
      expectedTotalUnread: handoff.totalUnreadBaseline + 1,
      expectedLastMessage: handoff.directCliText,
    );

    await robot.openConversationRowWithFirstVisibleTitle(
      conversationId: handoff.groupConversationId,
      expectedTitle: handoff.groupName,
    );
    await _assertUiMessagesExactlyOnce(
      robot: robot,
      conversationId: handoff.groupConversationId,
      expected: <ExactMessageExpectation>[
        ExactMessageExpectation(
          canonicalId: handoff.groupAppMessageId,
          content: handoff.groupAppText,
          conversationId: handoff.groupConversationId,
          senderDid: handoff.ownerDid,
        ),
        ExactMessageExpectation(
          canonicalId: handoff.groupCliMessageId,
          content: handoff.groupCliText,
          conversationId: handoff.groupConversationId,
          senderDid: handoff.groupMemberDid,
        ),
      ],
    );
    final groupMessage = await _waitForUiMessage(
      robot: robot,
      conversationId: handoff.groupConversationId,
      content: handoff.groupCliText,
      messageId: handoff.groupCliMessageId,
      senderDid: handoff.groupMemberDid,
      sendState: MessageSendState.sent,
    );
    await robot.expectMessageSenderIdentityProjection(
      conversationId: handoff.groupConversationId,
      message: groupMessage,
      expectedName: handoff.groupMemberDisplayName,
    );
    final member = await _findGroupMember(
      groups: bootstrap.groupApplicationService!,
      groupDid: handoff.groupDid,
      memberRef: handoff.groupMemberDid,
    );
    await robot.expectGroupMemberDisplayName(
      member: member,
      expectedName: handoff.groupMemberDisplayName,
    );
    await _waitForUiConversationUnread(
      robot: robot,
      conversationId: handoff.groupConversationId,
      expectedUnread: 0,
      expectedTotalUnread: handoff.totalUnreadBaseline,
      expectedLastMessage: handoff.groupCliText,
    );
    await E2eCaseAttestationWriter.markPassed(
      _processRestartCaseId,
      startedAt: startedAt,
      phases: const <String>[
        'distinct_flutter_process_same_state_root',
        'active_identity_restored_without_login',
        'direct_persona_exact_one_after_cold_start',
        'group_exact_one_after_cold_start',
        'exact_messages_and_unread_restored',
        'cached_names_visible_without_fallback',
      ],
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap.dispose();
    disposed = true;
  });
}

String _processRestartStateRootDigest(String stateRoot) =>
    sha256.convert(utf8.encode(File(stateRoot).absolute.path)).toString();

class _ProcessRestartHandoff {
  const _ProcessRestartHandoff({
    required this.runId,
    required this.phaseAProcessId,
    required this.appStateRootDigest,
    required this.ownerDid,
    required this.directConversationId,
    required this.directPeerPersonaId,
    required this.directPeerDid,
    required this.directDisplayName,
    required this.directAppMessageId,
    required this.directAppText,
    required this.directCliMessageId,
    required this.directCliText,
    required this.groupConversationId,
    required this.groupDid,
    required this.groupName,
    required this.groupAppMessageId,
    required this.groupAppText,
    required this.groupCliMessageId,
    required this.groupCliText,
    required this.groupMemberDid,
    required this.groupMemberDisplayName,
    required this.totalUnreadBaseline,
  });

  factory _ProcessRestartHandoff.read(File file) {
    if (!file.existsSync()) {
      throw StateError('Process-restart phase A handoff is missing.');
    }
    final decoded = jsonDecode(file.readAsStringSync());
    final map = _stringKeyMap(decoded, path: 'processRestart.handoff');
    if (map['schemaVersion'] != 1) {
      throw StateError('Unsupported process-restart handoff schema.');
    }
    String requiredString(String key) =>
        _requiredConfig(map, key, 'processRestart.handoff.$key');
    int requiredInt(String key) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      throw StateError('processRestart.handoff.$key must be an integer.');
    }

    return _ProcessRestartHandoff(
      runId: requiredString('runId'),
      phaseAProcessId: requiredInt('phaseAProcessId'),
      appStateRootDigest: requiredString('appStateRootDigest'),
      ownerDid: requiredString('ownerDid'),
      directConversationId: requiredString('directConversationId'),
      directPeerPersonaId: requiredString('directPeerPersonaId'),
      directPeerDid: requiredString('directPeerDid'),
      directDisplayName: requiredString('directDisplayName'),
      directAppMessageId: requiredString('directAppMessageId'),
      directAppText: requiredString('directAppText'),
      directCliMessageId: requiredString('directCliMessageId'),
      directCliText: requiredString('directCliText'),
      groupConversationId: requiredString('groupConversationId'),
      groupDid: requiredString('groupDid'),
      groupName: requiredString('groupName'),
      groupAppMessageId: requiredString('groupAppMessageId'),
      groupAppText: requiredString('groupAppText'),
      groupCliMessageId: requiredString('groupCliMessageId'),
      groupCliText: requiredString('groupCliText'),
      groupMemberDid: requiredString('groupMemberDid'),
      groupMemberDisplayName: requiredString('groupMemberDisplayName'),
      totalUnreadBaseline: requiredInt('totalUnreadBaseline'),
    );
  }

  final String runId;
  final int phaseAProcessId;
  final String appStateRootDigest;
  final String ownerDid;
  final String directConversationId;
  final String directPeerPersonaId;
  final String directPeerDid;
  final String directDisplayName;
  final String directAppMessageId;
  final String directAppText;
  final String directCliMessageId;
  final String directCliText;
  final String groupConversationId;
  final String groupDid;
  final String groupName;
  final String groupAppMessageId;
  final String groupAppText;
  final String groupCliMessageId;
  final String groupCliText;
  final String groupMemberDid;
  final String groupMemberDisplayName;
  final int totalUnreadBaseline;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'runId': runId,
    'phaseAProcessId': phaseAProcessId,
    'appStateRootDigest': appStateRootDigest,
    'ownerDid': ownerDid,
    'directConversationId': directConversationId,
    'directPeerPersonaId': directPeerPersonaId,
    'directPeerDid': directPeerDid,
    'directDisplayName': directDisplayName,
    'directAppMessageId': directAppMessageId,
    'directAppText': directAppText,
    'directCliMessageId': directCliMessageId,
    'directCliText': directCliText,
    'groupConversationId': groupConversationId,
    'groupDid': groupDid,
    'groupName': groupName,
    'groupAppMessageId': groupAppMessageId,
    'groupAppText': groupAppText,
    'groupCliMessageId': groupCliMessageId,
    'groupCliText': groupCliText,
    'groupMemberDid': groupMemberDid,
    'groupMemberDisplayName': groupMemberDisplayName,
    'totalUnreadBaseline': totalUnreadBaseline,
  };
}
