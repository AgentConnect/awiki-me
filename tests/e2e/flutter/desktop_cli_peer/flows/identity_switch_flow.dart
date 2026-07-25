part of '../desktop_cli_peer_e2e.dart';

class _IdentitySwitchSessions {
  const _IdentitySwitchSessions({
    required this.primary,
    required this.secondary,
  });

  final AppSession primary;
  final AppSession secondary;
}

Future<_IdentitySwitchSessions> _prepareIdentitySwitchSessions(
  AppBootstrap bootstrap,
  _DesktopCliPeerSmokeConfig config,
) async {
  final secondaryHandle = config.secondaryAppHandle;
  if (secondaryHandle == null || secondaryHandle.trim().isEmpty) {
    throw StateError(
      'accounts.appSecondaryUser.handle is required for identity-switch E2E.',
    );
  }
  final onboarding = bootstrap.onboardingService!;
  final primary = await _prepareAppIdentity(onboarding, config);
  final secondary = await _prepareAppIdentityForHandle(
    onboarding,
    config,
    handle: secondaryHandle,
    displayLabel: 'Secondary',
  );
  if (primary.identityId == secondary.identityId ||
      primary.did == secondary.did) {
    throw StateError('Identity-switch E2E requires two distinct identities.');
  }
  final reactivatedPrimary = await bootstrap.appSessionService!
      .activateIdentity(primary);
  return _IdentitySwitchSessions(
    primary: reactivatedPrimary,
    secondary: secondary,
  );
}

Future<void> _verifyIdentitySwitchRegression({
  required AppBootstrap bootstrap,
  required AppSession primary,
  required AppSession secondary,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final sessions = bootstrap.appSessionService!;
  final realtime = bootstrap.realtimeApplicationService!;
  final messaging = bootstrap.messagingService!;
  final sync = bootstrap.messageSyncService!;
  final conversations = bootstrap.conversationService!;
  final directory = bootstrap.directoryApplicationService!;

  final primaryToSecondaryText =
      'identity switch primary to secondary ${config.runId} $nonce';
  final secondaryToPrimaryText =
      'identity switch secondary to primary ${config.runId} $nonce';

  await sessions.activateIdentity(primary);
  await realtime.start();
  final primaryConversation = await _identitySwitchConversation(
    directory: directory,
    conversations: conversations,
    ownerDid: primary.did,
    peerHandle: config.secondaryAppHandle!,
  );
  final primarySent = await messaging.sendConversationText(
    conversation: primaryConversation,
    content: primaryToSecondaryText,
    idempotencyKey: 'identity-switch-a-b-${config.runId}-$nonce',
  );
  final primarySentId = _requireIdentitySwitchMessageId(primarySent);

  await sessions.logout();
  final activeSecondary = await sessions.loginWithIdentity(
    secondary.identityId,
  );
  expect(activeSecondary.did, secondary.did);
  final secondaryConversation = await _identitySwitchConversation(
    directory: directory,
    conversations: conversations,
    ownerDid: secondary.did,
    peerHandle: config.appHandle,
  );
  await _waitForIdentitySwitchUnread(
    sync: sync,
    conversations: conversations,
    ownerDid: secondary.did,
    conversation: secondaryConversation,
    expectedUnread: 1,
    reason: 'identity_switch_primary_to_secondary',
  );
  await realtime.start();
  final secondaryReceived = await _waitForIdentitySwitchHydration(
    sync: sync,
    messaging: messaging,
    conversation: secondaryConversation,
    messageId: primarySentId,
    expectedText: primaryToSecondaryText,
  );
  expect(secondaryReceived.isMine, isFalse);
  expect(secondaryReceived.senderDid, primary.did);
  await _markIdentitySwitchRead(
    conversations: conversations,
    ownerDid: secondary.did,
    conversation: secondaryConversation,
    message: secondaryReceived,
  );

  final secondarySent = await messaging.sendConversationText(
    conversation: secondaryConversation,
    content: secondaryToPrimaryText,
    idempotencyKey: 'identity-switch-b-a-${config.runId}-$nonce',
  );
  final secondarySentId = _requireIdentitySwitchMessageId(secondarySent);

  await sessions.logout();
  final activePrimary = await sessions.loginWithIdentity(primary.identityId);
  expect(activePrimary.did, primary.did);
  await _waitForIdentitySwitchUnread(
    sync: sync,
    conversations: conversations,
    ownerDid: primary.did,
    conversation: primaryConversation,
    expectedUnread: 1,
    reason: 'identity_switch_secondary_to_primary',
  );
  await realtime.start();
  final primaryReceived = await _waitForIdentitySwitchHydration(
    sync: sync,
    messaging: messaging,
    conversation: primaryConversation,
    messageId: secondarySentId,
    expectedText: secondaryToPrimaryText,
  );
  expect(primaryReceived.isMine, isFalse);
  expect(primaryReceived.senderDid, secondary.did);
  await _markIdentitySwitchRead(
    conversations: conversations,
    ownerDid: primary.did,
    conversation: primaryConversation,
    message: primaryReceived,
  );

  await sessions.logout();
  await sessions.loginWithIdentity(secondary.identityId);
  await realtime.start();
  final secondaryTimeline = await _identitySwitchTimeline(
    messaging,
    secondaryConversation,
  );
  _expectIdentitySwitchDirection(
    secondaryTimeline,
    primarySentId,
    isMine: false,
  );
  _expectIdentitySwitchDirection(
    secondaryTimeline,
    secondarySentId,
    isMine: true,
  );

  await sessions.logout();
  await sessions.loginWithIdentity(primary.identityId);
  await realtime.start();
  final primaryTimeline = await _identitySwitchTimeline(
    messaging,
    primaryConversation,
  );
  _expectIdentitySwitchDirection(primaryTimeline, primarySentId, isMine: true);
  _expectIdentitySwitchDirection(
    primaryTimeline,
    secondarySentId,
    isMine: false,
  );
  expect(realtime.isRunning, isTrue);
}

Future<AppConversationReadRef> _identitySwitchConversation({
  required DirectoryApplicationService directory,
  required ConversationService conversations,
  required String ownerDid,
  required String peerHandle,
}) async {
  final resolution = await directory.resolvePeer(peerHandle);
  final conversationId = resolution.conversationId?.trim();
  if (conversationId == null ||
      !conversationId.startsWith('dm:peer-scope:v1:')) {
    throw StateError(
      'Identity-switch E2E requires a resolved canonical Direct conversation.',
    );
  }
  await conversations.ensureConversationInRecents(
    ownerDid: ownerDid,
    conversationId: conversationId,
  );
  return AppConversationReadRef.fromConversationId(conversationId);
}

Future<ConversationSummary> _waitForIdentitySwitchUnread({
  required MessageSyncService sync,
  required ConversationService conversations,
  required String ownerDid,
  required AppConversationReadRef conversation,
  required int expectedUnread,
  required String reason,
}) {
  return _pollIdentitySwitch<ConversationSummary>(
    label: 'owner-scoped unread projection',
    action: () async {
      final result = await sync.syncNow(reason: reason, limit: 100);
      if (result.snapshotRequired) {
        throw StateError(
          'Reliable sync requested an unavailable snapshot repair.',
        );
      }
      final items = await conversations.listConversationSummariesFast(
        ownerDid: ownerDid,
      );
      final matches = items
          .where((item) => item.conversationId == conversation.conversationId)
          .toList(growable: false);
      if (matches.length != 1 || matches.single.unreadCount != expectedUnread) {
        return null;
      }
      return matches.single;
    },
  );
}

Future<ChatMessage> _waitForIdentitySwitchHydration({
  required MessageSyncService sync,
  required MessagingService messaging,
  required AppConversationReadRef conversation,
  required String messageId,
  required String expectedText,
}) {
  final conversationSync = sync as ConversationMessageSyncService;
  return _pollIdentitySwitch<ChatMessage>(
    label: 'hydrated canonical timeline message',
    action: () async {
      await conversationSync.syncConversationAfter(
        conversation: conversation,
        limit: 100,
      );
      final timeline = await _identitySwitchTimeline(messaging, conversation);
      final idMatches = timeline
          .where((message) => message.remoteId == messageId)
          .toList(growable: false);
      if (idMatches.length > 1) {
        fail(
          'Identity-switch timeline contains a duplicate canonical message.',
        );
      }
      if (idMatches.length != 1 ||
          idMatches.single.content != expectedText ||
          !idMatches.single.hasRenderableContent) {
        return null;
      }
      return idMatches.single;
    },
  );
}

Future<List<ChatMessage>> _identitySwitchTimeline(
  MessagingService messaging,
  AppConversationReadRef conversation,
) {
  final timeline = messaging as ConversationTimelineMessagingService;
  return timeline.loadConversationTimeline(conversation, limit: 100);
}

Future<void> _markIdentitySwitchRead({
  required ConversationService conversations,
  required String ownerDid,
  required AppConversationReadRef conversation,
  required ChatMessage message,
}) async {
  await conversations.markConversationRead(
    conversation,
    watermark: AppThreadReadWatermark(
      lastReadMessageId: message.remoteId,
      lastReadThreadSeq: message.serverSequence?.toString(),
      readAt: DateTime.now().toUtc(),
    ),
  );
  await _pollIdentitySwitch<ConversationSummary>(
    label: 'owner-scoped unread clear',
    action: () async {
      final items = await conversations.listConversationSummariesFast(
        ownerDid: ownerDid,
      );
      final matches = items
          .where((item) => item.conversationId == conversation.conversationId)
          .toList(growable: false);
      if (matches.length != 1 || matches.single.unreadCount != 0) {
        return null;
      }
      return matches.single;
    },
  );
}

String _requireIdentitySwitchMessageId(ChatMessage message) {
  final messageId = message.remoteId?.trim();
  if (message.sendState != MessageSendState.sent ||
      messageId == null ||
      messageId.isEmpty) {
    throw StateError(
      'Identity-switch send did not reach a canonical sent message.',
    );
  }
  return messageId;
}

void _expectIdentitySwitchDirection(
  List<ChatMessage> timeline,
  String messageId, {
  required bool isMine,
}) {
  final matches = timeline
      .where((message) => message.remoteId == messageId)
      .toList(growable: false);
  expect(matches, hasLength(1));
  expect(matches.single.isMine, isMine);
}

Future<T> _pollIdentitySwitch<T>({
  required String label,
  required Future<T?> Function() action,
  Duration timeout = const Duration(seconds: 90),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      final result = await action();
      if (result != null) {
        return result;
      }
    } on TestFailure {
      rethrow;
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError(
    'Timed out waiting for $label.'
    '${lastError == null ? '' : ' Last error type: ${lastError.runtimeType}.'}',
  );
}
