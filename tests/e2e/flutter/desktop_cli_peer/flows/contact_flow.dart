part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyContactRegression({
  required _DesktopAppRobot robot,
  required RelationshipApplicationService relationships,
  required MessagingService messaging,
  required ConversationService conversations,
  required String ownerDid,
  required AppSession session,
  required AppBootstrap bootstrap,
  required List<Override> providerOverrides,
  required String canonicalCliDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final cliDid = requireMatchingCliPeerDid(
    canonicalCliDid: canonicalCliDid,
    observedPeerDid: canonicalCliDid,
  );

  // Reused remote identities require an explicit baseline. Cleanup is setup,
  // while every relationship transition under test is driven by App UI or CLI.
  await _tryIgnore(() => relationships.unfollow(cliDid));
  await _tryIgnore(
    () => _runCli(config, <String>[
      '--format',
      'json',
      'people',
      'unfollow',
      config.appHandle,
    ]),
  );
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'none',
  );
  await _waitForCliRelationshipStatus(
    config: config,
    peer: config.appHandle,
    expectedRelationship: 'none',
  );
  await robot.refreshRelationshipProjection(
    peerDid: cliDid,
    expectedFollowing: false,
  );

  final conversation = await robot.startDirectConversation(config.cliHandle);
  requireMatchingCliPeerDid(
    canonicalCliDid: cliDid,
    observedPeerDid: conversation.targetDid ?? '',
  );
  await robot.followSelectedPeer();
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'following',
  );
  await _waitForAppRelationshipList(
    description: 'App following contains exact CLI DID',
    load: () => relationships.listFollowing(limit: 50),
    expectedDid: cliDid,
  );
  await _waitForCliRelationshipList(
    config: config,
    command: 'followers',
    expectedDidOrHandle: config.appHandle,
  );
  await _waitForCliRelationshipStatus(
    config: config,
    peer: config.appHandle,
    expectedRelationship: 'follower',
  );

  await _verifyContactDirectCanonicalRegression(
    robot: robot,
    messaging: messaging,
    conversations: conversations,
    ownerDid: ownerDid,
    session: session,
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    cliDid: cliDid,
    expectedConversationId: conversation.effectiveConversationId,
    config: config,
    nonce: nonce,
  );

  final cliFollow = await _runCli(config, <String>[
    '--format',
    'json',
    'people',
    'follow',
    config.appHandle,
  ]);
  if (cliFollow.exitCode != 0) {
    fail('CLI people follow failed: ${_summarizeCliResult(cliFollow)}');
  }
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'friend',
  );
  await _waitForAppRelationshipList(
    description: 'App followers contain exact CLI DID',
    load: () => relationships.listFollowers(limit: 50),
    expectedDid: cliDid,
  );
  await _waitForCliRelationshipList(
    config: config,
    command: 'following',
    expectedDidOrHandle: config.appHandle,
  );

  await robot.openSelectedPeerInfo();
  await robot.unfollowSelectedPeer();
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'follower',
  );
  await _waitForAppRelationshipListAbsent(
    description: 'App following excludes exact CLI DID',
    load: () => relationships.listFollowing(limit: 50),
    unexpectedDid: cliDid,
  );

  final cliUnfollow = await _runCli(config, <String>[
    '--format',
    'json',
    'people',
    'unfollow',
    config.appHandle,
  ]);
  if (cliUnfollow.exitCode != 0) {
    fail('CLI people unfollow failed: ${_summarizeCliResult(cliUnfollow)}');
  }
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'none',
  );
  await _waitForCliRelationshipStatus(
    config: config,
    peer: config.appHandle,
    expectedRelationship: 'none',
  );
  await robot.closePeerInfo();
}

Future<void> _verifyContactDirectCanonicalRegression({
  required _DesktopAppRobot robot,
  required MessagingService messaging,
  required ConversationService conversations,
  required String ownerDid,
  required AppSession session,
  required AppBootstrap bootstrap,
  required List<Override> providerOverrides,
  required String cliDid,
  required String expectedConversationId,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final outboundText = 'e2e contact to cli ${config.runId} $nonce';
  final inboundText = 'e2e cli to contact ${config.runId} $nonce';

  await robot.closePeerInfo();
  await robot.refreshRelationshipProjection(
    peerDid: cliDid,
    expectedFollowing: true,
  );
  final conversation = await robot.openContactConversation(cliDid);
  final conversationId = conversation.effectiveConversationId;
  expect(conversationId.startsWith('dm:peer-scope:v1:'), isTrue);
  expect(conversationId, expectedConversationId);
  expect(find.byKey(Key('conversation-row:$conversationId')), findsOneWidget);
  await E2eScenarioProgressWriter.record('contact_canonical_row_opened');

  await robot.sendText(outboundText);
  final outbound = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: outboundText,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  final outboundId = outbound.remoteId!;
  await robot.expectMessageContentVisible(outbound);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedLastMessage: outboundText,
  );
  await _waitForCliInbox(
    config: config,
    expectedText: outboundText,
    expectedMessageId: outboundId,
    expectedSenderDid: ownerDid,
    expectedReceiverDid: cliDid,
    expectedContentType: 'text/plain',
  );
  await _waitForCliHistory(
    config: config,
    peerHandle: config.appHandle,
    expectedText: outboundText,
    expectedMessageId: outboundId,
    expectedSenderDid: ownerDid,
    expectedReceiverDid: cliDid,
    expectedContentType: 'text/plain',
  );
  final coreSummary = await _waitForAppConversationRefresh(
    conversations: conversations,
    ownerDid: ownerDid,
    expectedText: outboundText,
    expectedConversationId: conversationId,
  );
  await _expectCanonicalContactRowsExact(
    robot: robot,
    conversations: conversations,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );
  await _waitForAppConversationLatestInTimeline(
    messaging: messaging,
    conversation: coreSummary,
    expectedText: outboundText,
    expectedMessageId: outboundId,
  );
  await _expectSingleCanonicalContactOverlay(
    bootstrap: bootstrap,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <String, String>{outboundText: outboundId},
  );

  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await robot.openConversationRow(conversationId);
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <String, String>{outboundText: outboundId},
  );
  requireExactlyOneConversation(
    conversations: robot.container.read(conversationListProvider).conversations,
    conversationId: conversationId,
    unreadCount: 0,
    lastMessage: outboundText,
  );
  await _expectCanonicalContactRowsExact(
    robot: robot,
    conversations: conversations,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );

  await robot.navigateToContacts();
  final unreadBaseline = robot.container.read(
    conversationListProvider.select((state) => state.unreadCount),
  );
  final inboundId = await _cliSendDirectText(config: config, text: inboundText);
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: conversationId,
    expectedText: inboundText,
    expectedConversationUnread: 1,
    expectedTotalUnread: unreadBaseline + 1,
  );
  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await robot.expectConversationUnreadBadge(
    conversationId: conversationId,
    unreadCount: 1,
  );
  await robot.openConversationRow(conversationId);
  final inbound = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: inboundText,
    messageId: inboundId,
    senderDid: cliDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(inbound);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
    expectedLastMessage: inboundText,
  );
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <String, String>{
      outboundText: outboundId,
      inboundText: inboundId,
    },
  );
  await _expectSingleCanonicalContactOverlay(
    bootstrap: bootstrap,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );
  await E2eScenarioProgressWriter.record(
    'contact_restart_unread_read_closed_loop_completed',
  );
}

Future<void> _expectCanonicalContactRowsExact({
  required _DesktopAppRobot robot,
  required ConversationService conversations,
  required String ownerDid,
  required String conversationId,
  required String peerDid,
}) async {
  final legacyConversationId = 'dm:${peerDid.trim()}';
  final coreRows = await conversations.listConversations(
    ownerDid: ownerDid,
    limit: 50,
  );
  expect(
    coreRows.where((item) => item.effectiveConversationId == conversationId),
    hasLength(1),
  );
  expect(
    coreRows.where(
      (item) => item.effectiveConversationId == legacyConversationId,
    ),
    isEmpty,
  );
  final uiRows = robot.container.read(conversationListProvider).conversations;
  expect(
    uiRows.where((item) => item.effectiveConversationId == conversationId),
    hasLength(1),
  );
  expect(
    uiRows.where(
      (item) => item.effectiveConversationId == legacyConversationId,
    ),
    isEmpty,
  );
  expect(find.byKey(Key('conversation-row:$conversationId')), findsOneWidget);
}

Future<void> _expectSingleCanonicalContactOverlay({
  required AppBootstrap bootstrap,
  required String ownerDid,
  required String conversationId,
  required String peerDid,
}) async {
  final store = bootstrap.productLocalStore;
  if (store == null) {
    fail('Product local store is required for the contact overlay oracle.');
  }
  await _poll(
    description: 'exactly one canonical contact overlay',
    action: () async {
      final canonical = await store.loadConversationOverlaysByConversationId(
        ownerDid: ownerDid,
        conversationIds: <String>[conversationId],
      );
      if (canonical.length != 1 ||
          canonical.values.single.effectiveConversationId != conversationId) {
        return false;
      }
      final legacy = await store.loadConversationOverlays(
        ownerDid: ownerDid,
        threadIds: <String>['dm:${peerDid.trim()}'],
      );
      return legacy.isEmpty;
    },
  );
}

Future<String> _currentCliDid(_DesktopCliPeerSmokeConfig config) async {
  final current = await _runCli(config, const <String>[
    '--format',
    'json',
    'id',
    'current',
  ]);
  if (current.exitCode != 0) {
    fail('CLI peer identity mismatch.');
  }
  final did = _jsonStringAt(current.stdout, const <Object>[
    'data',
    'identity',
    'did',
  ]);
  if (did == null || did.trim().isEmpty) {
    fail('CLI peer identity mismatch.');
  }
  return requireMatchingCliPeerDid(canonicalCliDid: did, observedPeerDid: did);
}

Future<void> _waitForAppRelationshipStatus({
  required RelationshipApplicationService relationships,
  required String peer,
  required String expected,
}) async {
  await _poll(
    description: 'App relationship status for "$peer" equals $expected',
    action: () async {
      final status = await relationships.status(peer);
      return status.relationship.trim().toLowerCase() == expected;
    },
  );
}

Future<void> _waitForAppRelationshipList({
  required String description,
  required Future<CoreRelationshipPage> Function() load,
  required String expectedDid,
}) async {
  await _poll(
    description: description,
    action: () async {
      final page = await load();
      return page.items
              .where((item) => item.did.trim() == expectedDid)
              .length ==
          1;
    },
  );
}

Future<void> _waitForAppRelationshipListAbsent({
  required String description,
  required Future<CoreRelationshipPage> Function() load,
  required String unexpectedDid,
}) async {
  await _poll(
    description: description,
    action: () async {
      final page = await load();
      return page.items.every((item) => item.did.trim() != unexpectedDid);
    },
  );
}

Future<void> _waitForCliRelationshipList({
  required _DesktopCliPeerSmokeConfig config,
  required String command,
  required String expectedDidOrHandle,
}) async {
  await _poll(
    description: 'CLI people $command contains exact "$expectedDidOrHandle"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'people',
        command,
        '--limit',
        '50',
        '--profile',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _cliRelationshipListExactCount(
            result.stdout,
            expectedDidOrHandle,
          ) ==
          1;
    },
  );
}

Future<void> _waitForCliRelationshipStatus({
  required _DesktopCliPeerSmokeConfig config,
  required String peer,
  required String expectedRelationship,
}) async {
  await _poll(
    description: 'CLI people status for "$peer" equals $expectedRelationship',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'people',
        'status',
        peer,
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return cliRelationshipState(result.stdout) ==
          expectedRelationship.trim().toLowerCase();
    },
  );
}

int _cliRelationshipListExactCount(String output, String expectedRef) {
  final expected = _normalizeIdentityRef(expectedRef);
  if (expected.isEmpty) {
    return 0;
  }
  final items = _jsonValueAt(output, const <Object>['data', 'items']);
  if (items is! List) {
    return 0;
  }
  return items.whereType<Map>().where((item) {
    final map = _cliStringKeyMap(item);
    final did = _normalizeIdentityRef(map['did']?.toString() ?? '');
    final handle = _normalizeIdentityRef(map['handle']?.toString() ?? '');
    return did == expected || handle == expected;
  }).length;
}

Future<void> _tryIgnore(Future<Object?> Function() action) async {
  try {
    await action();
  } on Object {
    // Best-effort cleanup for reused non-production E2E identities.
  }
}
