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
      return messages.any(
        (message) => message._matchesText(
          expectedText,
          expectedMessageId: expectedMessageId,
        ),
      );
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
      return messages.any(
        (message) => message._matchesText(
          expectedText,
          expectedMessageId: expectedMessageId,
        ),
      );
    },
  );
}

Future<ChatMessage> _waitForAppAttachment({
  required MessagingService messaging,
  required AppThreadRef thread,
  required String expectedCaption,
  required String expectedFilename,
  String? expectedMessageId,
  String? expectedAttachmentId,
}) async {
  ChatMessage? matched;
  await _poll(
    description:
        'App history contains attachment "$expectedFilename" with caption "$expectedCaption"',
    action: () async {
      final messages = await messaging.loadHistory(thread, limit: 50);
      for (final message in messages) {
        final attachment = message.attachment;
        if (attachment == null) {
          continue;
        }
        final messageId = message.remoteId ?? message.localId;
        if (message.content == expectedCaption &&
            attachment.filename == expectedFilename &&
            (expectedMessageId == null || messageId == expectedMessageId) &&
            (expectedAttachmentId == null ||
                attachment.attachmentId == expectedAttachmentId)) {
          matched = message;
          return true;
        }
      }
      return false;
    },
  );
  return matched!;
}

Future<void> _expectAppHistoryContainsExactlyOnce({
  required MessagingService messaging,
  required AppThreadRef thread,
  required List<String> expectedTexts,
}) async {
  final first = await messaging.loadHistory(thread, limit: 50);
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

Future<void> _waitForAppConversationRefresh({
  required ConversationService conversations,
  required String ownerDid,
  required String expectedText,
}) async {
  await _poll(
    description: 'App conversation refresh contains "$expectedText"',
    action: () async {
      final items = await conversations.listConversations(
        ownerDid: ownerDid,
        limit: 20,
      );
      return items.any(
        (conversation) =>
            conversation.lastMessagePreview.contains(expectedText),
      );
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
