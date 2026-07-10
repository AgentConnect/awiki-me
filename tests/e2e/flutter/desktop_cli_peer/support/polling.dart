part of '../desktop_cli_peer_e2e.dart';

Future<void> _waitForGroupMessages({
  required GroupApplicationService groups,
  required String groupDid,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _poll(
    description: 'App group messages contain exact message "$expectedText"',
    action: () async {
      final messages = await groups.listMessages(groupDid, limit: 20);
      return messages
              .where(
                (message) => message._matchesText(
                  expectedText,
                  expectedMessageId: expectedMessageId,
                ),
              )
              .length ==
          1;
    },
  );
}

Future<void> _waitForAppHistory({
  required MessagingService messaging,
  required AppThreadRef thread,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _poll(
    description: 'App history contains exact message "$expectedText"',
    action: () async {
      final messages = await messaging.loadHistory(thread, limit: 20);
      return messages
              .where(
                (message) => message._matchesText(
                  expectedText,
                  expectedMessageId: expectedMessageId,
                ),
              )
              .length ==
          1;
    },
  );
}

Future<void> _expectAppHistoryContainsExactlyOnce({
  required MessagingService messaging,
  required AppThreadRef thread,
  required List<String> expectedTexts,
}) async {
  final first = await messaging.loadHistory(thread, limit: 50);
  await Future<void>.delayed(const Duration(seconds: 2));
  final second = await messaging.loadHistory(thread, limit: 50);
  for (final text in expectedTexts) {
    final firstMatches = first.where((message) => message._matchesText(text));
    final secondMatches = second.where((message) => message._matchesText(text));
    expect(
      firstMatches,
      hasLength(1),
      reason: 'App history should contain exactly one "$text" message.',
    );
    expect(
      secondMatches,
      hasLength(1),
      reason: 'A second App history refresh should not duplicate "$text".',
    );
  }
}

Future<ConversationSummary> _waitForAppConversationRefresh({
  required ConversationService conversations,
  required String ownerDid,
  required String expectedText,
  required String expectedConversationId,
}) async {
  ConversationSummary? matched;
  await _poll(
    description: 'App conversation refresh contains "$expectedText"',
    action: () async {
      final items = await conversations.listConversations(
        ownerDid: ownerDid,
        limit: 20,
      );
      final exact = items
          .where(
            (conversation) =>
                conversation.effectiveConversationId == expectedConversationId,
          )
          .toList(growable: false);
      if (exact.length != 1 ||
          exact.single.lastMessagePreview != expectedText) {
        return false;
      }
      matched = exact.single;
      return true;
    },
  );
  return matched!;
}

Future<void> _waitForAppConversationLatestInTimeline({
  required MessagingService messaging,
  required ConversationSummary conversation,
  required String expectedText,
  String? expectedMessageId,
}) async {
  expect(
    messaging,
    isA<ConversationTimelineMessagingService>(),
    reason:
        'Desktop CLI peer E2E must verify list/detail consistency through '
        'the canonical conversation timeline.',
  );
  final timelineMessaging = messaging as ConversationTimelineMessagingService;
  final conversationId = conversation.effectiveConversationId;
  final latestSnapshot = conversation.lastMessageSnapshot;
  final latestSnapshotId = latestSnapshot == null
      ? null
      : latestSnapshot.remoteId ?? latestSnapshot.localId;

  await _poll(
    description:
        'App conversation "$conversationId" latest message exists in canonical timeline',
    action: () async {
      final messages = await timelineMessaging.loadConversationTimeline(
        AppConversationReadRef.fromConversationId(conversationId),
        limit: 50,
      );
      final textMatches = messages.where(
        (message) => message._matchesText(
          expectedText,
          expectedMessageId: expectedMessageId,
        ),
      );
      if (textMatches.length != 1) {
        return false;
      }
      if (latestSnapshotId == null || latestSnapshotId.isEmpty) {
        return false;
      }
      if (expectedMessageId != null && latestSnapshotId != expectedMessageId) {
        return false;
      }
      return textMatches.single.remoteId == latestSnapshotId &&
          latestSnapshot?.content == expectedText;
    },
  );
}

Future<void> _poll({
  required String description,
  required Future<bool> Function() action,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await action()) {
        return;
      }
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(interval);
  }
  final suffix = lastError == null
      ? ''
      : ' Last error: ${_sanitizeDiagnostic(lastError.toString())}';
  fail('Timed out waiting for $description.$suffix');
}

extension on ChatMessage {
  bool _matchesText(String expectedText, {String? expectedMessageId}) {
    if (content != expectedText) {
      return false;
    }
    final id = remoteId ?? localId;
    return expectedMessageId == null || id == expectedMessageId;
  }
}
