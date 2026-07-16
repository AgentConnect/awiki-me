import 'dart:convert';

import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:flutter/widgets.dart' show Key, Text, Widget;
import 'package:flutter_test/flutter_test.dart';

import '../../../case_attestation.dart';

enum DesktopPlatformVariant { macOS, other }

enum E2eObservationStatus { pending, pass, fatal }

class E2eObservation {
  const E2eObservation._(this.status, this.code);

  const E2eObservation.pending([String? code])
    : this._(E2eObservationStatus.pending, code);

  const E2eObservation.pass() : this._(E2eObservationStatus.pass, null);

  const E2eObservation.fatal(String code)
    : this._(E2eObservationStatus.fatal, code);

  final E2eObservationStatus status;
  final String? code;
}

class ExactMessageExpectation {
  const ExactMessageExpectation({
    required this.canonicalId,
    required this.content,
    this.conversationId,
    this.senderDid,
    this.senderPeerPersonaId,
    this.serverSequence,
    this.sendState = MessageSendState.sent,
  });

  final String canonicalId;
  final String content;
  final String? conversationId;
  final String? senderDid;
  final String? senderPeerPersonaId;
  final int? serverSequence;
  final MessageSendState? sendState;
}

E2eObservation observeExactScopedText({
  required Iterable<Widget> widgets,
  required String expectedText,
  required String pendingCode,
  required String exactOneCode,
  required String mismatchCode,
}) {
  final values = widgets.toList(growable: false);
  if (values.isEmpty) {
    return E2eObservation.pending(pendingCode);
  }
  if (values.length != 1 || values.single is! Text) {
    return E2eObservation.fatal(exactOneCode);
  }
  final visible = (values.single as Text).data?.trim() ?? '';
  if (visible != expectedText.trim()) {
    return E2eObservation.fatal(mismatchCode);
  }
  return const E2eObservation.pass();
}

/// Returns the message that owns the visible sender label for [target].
///
/// Group chat intentionally renders one sender label for a contiguous run from
/// the same remote sender. A strict E2E assertion must inspect that visible
/// cluster label rather than require every bubble to repeat the name.
ChatMessage requireGroupSenderLabelAnchor({
  required List<ChatMessage> messages,
  required ChatMessage target,
}) {
  var index = messages.indexWhere(
    (message) =>
        message.localId == target.localId ||
        (target.remoteId?.trim().isNotEmpty == true &&
            message.remoteId == target.remoteId),
  );
  if (index < 0) {
    throw StateError('Sender-label target is missing from the UI timeline.');
  }
  if (target.isMine || target.isGroupSystemEvent) {
    throw StateError('Sender labels only belong to remote group messages.');
  }
  while (index > 0) {
    final current = messages[index];
    final previous = messages[index - 1];
    final startsNewCluster =
        previous.isMine ||
        current.createdAt
                .toLocal()
                .difference(previous.createdAt.toLocal())
                .inMinutes >=
            30 ||
        previous.senderDid.trim() != current.senderDid.trim();
    if (startsNewCluster) {
      break;
    }
    index -= 1;
  }
  return messages[index];
}

/// Observes the first title rendered after the target conversation becomes
/// selected. A missing target selection or blank/skeleton title is a valid
/// loading state, but the first non-empty title must already be the cached
/// nickname. Waiting for a wrong Handle/DID/Unknown title to self-heal would
/// hide the user-visible flash this oracle is intended to catch.
E2eObservation observeFirstVisibleConversationTitle({
  required bool targetSelected,
  required Iterable<String> visibleTitles,
  required String expectedTitle,
}) {
  final expected = expectedTitle.trim();
  if (expected.isEmpty) {
    return const E2eObservation.fatal('expected_title_is_empty');
  }
  if (!targetSelected) {
    return const E2eObservation.pending('target_selection_pending');
  }
  final titles = visibleTitles.map((title) => title.trim()).toList();
  if (titles.length > 1) {
    return const E2eObservation.fatal('conversation_title_not_exact_one');
  }
  if (titles.isEmpty || titles.single.isEmpty) {
    return const E2eObservation.pending('conversation_title_pending');
  }
  if (titles.single != expected) {
    return const E2eObservation.fatal('wrong_first_visible_conversation_title');
  }
  return const E2eObservation.pass();
}

DesktopPlatformVariant requireDesktopPlatformVariant({
  required int macOSCount,
  required int otherCount,
  required String element,
}) {
  if (macOSCount == 1 && otherCount == 0) {
    return DesktopPlatformVariant.macOS;
  }
  if (macOSCount == 0 && otherCount == 1) {
    return DesktopPlatformVariant.other;
  }
  throw StateError(
    'Expected exactly one $element platform variant; '
    'macos=$macOSCount other=$otherCount.',
  );
}

void requireNoDirectConversationForPeer({
  required Iterable<ConversationSummary> conversations,
  required String peerDid,
  required Iterable<String> peerHandles,
}) {
  final did = peerDid.trim();
  final handles = peerHandles
      .map(_normalizePeerReference)
      .where((value) => value.isNotEmpty)
      .toSet();
  if (did.isEmpty || handles.isEmpty) {
    throw StateError('Peer DID and Handle fixtures must be non-empty.');
  }
  final matches = conversations
      .where((conversation) {
        if (conversation.isGroup) {
          return false;
        }
        if ((conversation.targetDid?.trim() ?? '') == did) {
          return true;
        }
        return handles.contains(
          _normalizePeerReference(conversation.targetPeer),
        );
      })
      .toList(growable: false);
  if (matches.isNotEmpty) {
    throw StateError(
      'Contact-first fixture already has a Direct conversation for the peer.',
    );
  }
}

String _normalizePeerReference(String? value) {
  var normalized = value?.trim().toLowerCase() ?? '';
  while (normalized.startsWith('@')) {
    normalized = normalized.substring(1).trimLeft();
  }
  return normalized;
}

/// Strict, reusable product oracles for the UI-driven App + CLI E2E flows.
///
/// These helpers deliberately reject zero and duplicate matches. A visible
/// string, a non-empty history, or an outer process exit code is not enough to
/// prove that the intended message reached the intended conversation.
ChatMessage requireExactlyOneMessage({
  required Iterable<ChatMessage> messages,
  required String content,
  String? messageId,
  String? senderDid,
  String? receiverDid,
  String? groupDid,
  MessageSendState? sendState,
  bool requireCanonicalRemoteId = true,
}) {
  final matches = messages
      .where((message) {
        return message.content == content;
      })
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one message with content "$content" in the target '
      'view before canonical-id validation, found ${matches.length}.',
    );
  }
  final message = matches.single;
  final canonicalId = message.remoteId ?? message.localId;
  if (messageId != null && canonicalId != messageId) {
    throw StateError(
      'Message "$content" canonical id "$canonicalId" != "$messageId".',
    );
  }
  final remoteId = message.remoteId?.trim() ?? '';
  if (requireCanonicalRemoteId && remoteId.isEmpty) {
    throw StateError('Message "$content" has no canonical remote id.');
  }
  if (senderDid != null && message.senderDid.trim() != senderDid.trim()) {
    throw StateError(
      'Message "$content" sender ${message.senderDid} != $senderDid.',
    );
  }
  if (receiverDid != null &&
      (message.receiverDid?.trim() ?? '') != receiverDid.trim()) {
    throw StateError(
      'Message "$content" receiver ${message.receiverDid} != $receiverDid.',
    );
  }
  if (groupDid != null && (message.groupId?.trim() ?? '') != groupDid.trim()) {
    throw StateError(
      'Message "$content" group ${message.groupId} != $groupDid.',
    );
  }
  if (sendState != null && message.sendState != sendState) {
    throw StateError(
      'Message "$content" send state ${message.sendState} != $sendState.',
    );
  }
  return message;
}

/// Requires the complete run-owned message sequence, not merely the presence
/// of each expected body. The caller owns the run filter so unrelated remote
/// history cannot make a reused test account fail.
List<ChatMessage> requireExactMessageSequence({
  required Iterable<ChatMessage> messages,
  required List<ExactMessageExpectation> expected,
  required bool Function(ChatMessage message) isRunOwned,
}) {
  final expectedIds = expected
      .map((item) => item.canonicalId.trim())
      .toList(growable: false);
  if (expectedIds.any((id) => id.isEmpty) ||
      expectedIds.toSet().length != expectedIds.length) {
    throw StateError('Expected message ids must be non-empty and unique.');
  }

  final actual = messages.where(isRunOwned).toList(growable: false);
  final actualIds = actual
      .map((message) => (message.remoteId ?? message.localId).trim())
      .toList(growable: false);
  if (actualIds.any((id) => id.isEmpty) ||
      actualIds.toSet().length != actualIds.length) {
    throw StateError('Run-owned canonical message ids are not unique.');
  }
  if (actual.length != expected.length) {
    throw StateError(
      'Run-owned message count ${actual.length} != ${expected.length}.',
    );
  }
  if (!_sameStringSequence(actualIds, expectedIds)) {
    throw StateError('Run-owned canonical message order does not match.');
  }

  for (var index = 0; index < expected.length; index += 1) {
    final message = actual[index];
    final item = expected[index];
    if (message.content != item.content) {
      throw StateError('Run-owned message content does not match at $index.');
    }
    if (item.conversationId != null &&
        (message.conversationId?.trim() ?? '') != item.conversationId!.trim()) {
      throw StateError(
        'Run-owned message conversation does not match at $index.',
      );
    }
    if (item.senderDid != null &&
        message.senderDid.trim() != item.senderDid!.trim()) {
      throw StateError('Run-owned message sender does not match at $index.');
    }
    if (item.senderPeerPersonaId != null &&
        (message.senderPeerPersonaId?.trim() ?? '') !=
            item.senderPeerPersonaId!.trim()) {
      throw StateError(
        'Run-owned message sender Persona does not match at $index.',
      );
    }
    if (item.serverSequence != null &&
        message.serverSequence != item.serverSequence) {
      throw StateError(
        'Run-owned message server sequence does not match at $index.',
      );
    }
    if (item.sendState != null && message.sendState != item.sendState) {
      throw StateError(
        'Run-owned message terminal state does not match at $index.',
      );
    }
  }
  return actual;
}

/// Observes an incrementally arriving run-owned sequence without weakening
/// the final exact comparison. A strict expected prefix may still be pending;
/// an unexpected id, out-of-order item, duplicate id, or wrong terminal field
/// is fatal immediately.
E2eObservation observeExactMessageSequence({
  required Iterable<ChatMessage> messages,
  required List<ExactMessageExpectation> expected,
  required bool Function(ChatMessage message) isRunOwned,
}) {
  final expectedIds = expected
      .map((item) => item.canonicalId.trim())
      .toList(growable: false);
  if (expectedIds.any((id) => id.isEmpty) ||
      expectedIds.toSet().length != expectedIds.length) {
    return const E2eObservation.fatal('invalid_expected_message_ids');
  }

  final actual = messages.where(isRunOwned).toList(growable: false);
  if (actual.length > expected.length) {
    return const E2eObservation.fatal('unexpected_run_owned_message');
  }
  final actualIds = actual
      .map((message) => (message.remoteId ?? message.localId).trim())
      .toList(growable: false);
  if (actualIds.where((id) => id.isNotEmpty).toSet().length !=
      actualIds.where((id) => id.isNotEmpty).length) {
    return const E2eObservation.fatal('duplicate_canonical_message_id');
  }

  for (var index = 0; index < actual.length; index += 1) {
    final message = actual[index];
    final item = expected[index];
    final remoteId = message.remoteId?.trim() ?? '';
    final canonicalId = actualIds[index];
    if (remoteId.isEmpty) {
      return const E2eObservation.pending('canonical_message_id_pending');
    }
    if (canonicalId != item.canonicalId.trim()) {
      return const E2eObservation.fatal('wrong_message_id_or_order');
    }
    if (message.content != item.content) {
      return const E2eObservation.fatal('wrong_message_content');
    }
    if (item.conversationId != null &&
        (message.conversationId?.trim() ?? '') != item.conversationId!.trim()) {
      return const E2eObservation.fatal('wrong_message_conversation');
    }
    if (item.senderDid != null &&
        message.senderDid.trim() != item.senderDid!.trim()) {
      return const E2eObservation.fatal('wrong_message_sender');
    }
    if (item.senderPeerPersonaId != null &&
        (message.senderPeerPersonaId?.trim() ?? '') !=
            item.senderPeerPersonaId!.trim()) {
      return const E2eObservation.fatal('wrong_message_sender_persona');
    }
    if (item.serverSequence != null &&
        message.serverSequence != item.serverSequence) {
      return const E2eObservation.fatal('wrong_message_server_sequence');
    }
    if (item.sendState != null && message.sendState != item.sendState) {
      if (item.sendState == MessageSendState.sent &&
          message.sendState == MessageSendState.sending) {
        return const E2eObservation.pending('terminal_send_state_pending');
      }
      return const E2eObservation.fatal('wrong_message_send_state');
    }
  }

  if (actual.length < expected.length) {
    return const E2eObservation.pending('message_sequence_incomplete');
  }
  return const E2eObservation.pass();
}

/// Observes whether a conversation summary and its canonical local timeline
/// agree on the latest message. Equal message bodies remain legal when their
/// canonical ids differ; once an expected id is known, identity rather than
/// body text owns the exact-one check.
E2eObservation observeConversationLatestInTimeline({
  required Iterable<ChatMessage> messages,
  required ChatMessage? latestSnapshot,
  required String conversationId,
  required String expectedText,
  String? expectedMessageId,
}) {
  final canonicalConversationId = conversationId.trim();
  final canonicalExpectedId = expectedMessageId?.trim() ?? '';
  final items = messages.toList(growable: false);

  ChatMessage? matched;
  if (canonicalExpectedId.isNotEmpty) {
    final idMatches = items
        .where(
          (message) =>
              (message.remoteId ?? message.localId).trim() ==
              canonicalExpectedId,
        )
        .toList(growable: false);
    if (idMatches.isEmpty) {
      return const E2eObservation.pending('canonical_timeline_message_pending');
    }
    if (idMatches.length != 1) {
      return const E2eObservation.fatal(
        'duplicate_canonical_timeline_message_id',
      );
    }
    matched = idMatches.single;
    if (matched.content != expectedText) {
      return const E2eObservation.fatal(
        'canonical_timeline_message_content_mismatch',
      );
    }
  } else {
    final bodyMatches = items
        .where((message) => message.content == expectedText)
        .toList(growable: false);
    if (bodyMatches.isEmpty) {
      return const E2eObservation.pending('canonical_timeline_message_pending');
    }
    if (bodyMatches.length != 1) {
      return const E2eObservation.fatal('duplicate_canonical_timeline_message');
    }
    matched = bodyMatches.single;
  }

  if ((matched.conversationId?.trim() ?? '') != canonicalConversationId) {
    return const E2eObservation.fatal(
      'canonical_timeline_message_conversation_mismatch',
    );
  }
  if (latestSnapshot == null) {
    return const E2eObservation.pending('conversation_latest_snapshot_pending');
  }
  final latestSnapshotId = (latestSnapshot.remoteId ?? latestSnapshot.localId)
      .trim();
  if (latestSnapshotId.isEmpty) {
    return const E2eObservation.pending('conversation_latest_snapshot_pending');
  }
  final matchedId = (matched.remoteId ?? matched.localId).trim();
  if (latestSnapshotId != matchedId || latestSnapshot.content != expectedText) {
    return const E2eObservation.pending(
      'conversation_latest_snapshot_content_pending',
    );
  }
  if ((latestSnapshot.conversationId?.trim() ?? '') !=
      canonicalConversationId) {
    return const E2eObservation.fatal(
      'conversation_latest_snapshot_conversation_mismatch',
    );
  }
  return const E2eObservation.pass();
}

void requireNoRunOwnedMessageLeakage({
  required Iterable<ChatMessage> messages,
  required String targetConversationId,
  required bool Function(ChatMessage message) isRunOwned,
}) {
  final target = targetConversationId.trim();
  if (target.isEmpty) {
    throw StateError('Target conversation id must be non-empty.');
  }
  for (final message in messages.where(isRunOwned)) {
    if ((message.conversationId?.trim() ?? '') != target) {
      throw StateError('Run-owned message leaked outside target conversation.');
    }
  }
}

/// Confirms that a UI/directory/group resolution points to the exact active
/// CLI identity. Diagnostics intentionally never include either DID.
String requireMatchingCliPeerDid({
  required String canonicalCliDid,
  required String observedPeerDid,
}) {
  final canonical = canonicalCliDid.trim();
  final observed = observedPeerDid.trim();
  if (canonical.isEmpty || observed.isEmpty || canonical != observed) {
    throw StateError('CLI peer identity mismatch.');
  }
  return canonical;
}

/// Requires one target message-content container and one exact text rendering
/// inside it. Identical text in recents previews or other bubbles is ignored,
/// while a missing/duplicated container or duplicated in-container text fails.
void expectExactlyOneVisibleMessageContent({
  required String localId,
  required String expectedText,
}) {
  final content = find.byKey(Key('chat-message-content:$localId'));
  expect(
    content,
    findsOneWidget,
    reason: 'Expected exactly one content container for message $localId.',
  );
  expect(
    find.descendant(
      of: content,
      matching: find.text(expectedText, findRichText: true),
    ),
    findsOneWidget,
    reason:
        'Expected exactly one "$expectedText" rendering inside message '
        '$localId.',
  );
}

void expectVisibleMessageOrder({
  required WidgetTester tester,
  required List<String> localIds,
}) {
  double? previousTop;
  for (final localId in localIds) {
    final content = find.byKey(Key('chat-message-content:$localId'));
    expect(content, findsOneWidget);
    final top = tester.getTopLeft(content).dy;
    if (previousTop != null && top <= previousTop) {
      throw StateError('Visible message order does not match canonical order.');
    }
    previousTop = top;
  }
}

/// Parses CLI message output without allowing an expected id to hide a second
/// delivery of the same body under another canonical id.
///
/// Callers must require the returned list to contain exactly one item. The id
/// is checked only after the body-level result is already unique.
List<Map<String, Object?>> cliMessagesWithExactText(
  String output, {
  required String expectedText,
  String? expectedMessageId,
}) {
  final messages = _jsonValueAt(output, const <Object>['data', 'messages']);
  if (messages is! List) {
    return const <Map<String, Object?>>[];
  }
  final bodyMatches = messages
      .whereType<Map>()
      .map(_stringKeyMap)
      .where((message) => _cliMessageContentMatches(message, expectedText))
      .toList(growable: false);
  if (expectedMessageId == null || bodyMatches.length != 1) {
    return bodyMatches;
  }
  final canonicalId = _firstNonEmptyString(<Object?>[
    bodyMatches.single['message_id'],
    bodyMatches.single['msg_id'],
    bodyMatches.single['id'],
  ]);
  return canonicalId == expectedMessageId
      ? bodyMatches
      : const <Map<String, Object?>>[];
}

/// Classifies one CLI message collection without collapsing duplicate,
/// canonical-id, routing, or content-type failures into a boolean mismatch.
E2eObservation observeCliExactMessage({
  required String output,
  required String expectedText,
  String? expectedMessageId,
  String? expectedSenderDid,
  String? expectedReceiverDid,
  String? expectedGroupDid,
  String? expectedContentType,
}) {
  final matches = cliMessagesWithExactText(output, expectedText: expectedText);
  if (matches.isEmpty) {
    return const E2eObservation.pending('cli_exact_message_pending');
  }
  if (matches.length != 1) {
    return const E2eObservation.fatal('cli_duplicate_exact_message');
  }
  final message = matches.single;
  final canonicalId = _firstNonEmptyString(<Object?>[
    message['message_id'],
    message['msg_id'],
    message['id'],
  ]);
  if (expectedMessageId != null && canonicalId != expectedMessageId) {
    return const E2eObservation.fatal('cli_message_id_mismatch');
  }
  bool mismatch(String key, String? expected) =>
      expected != null &&
      _firstNonEmptyString(<Object?>[message[key]])?.trim() != expected.trim();
  if (mismatch('sender_did', expectedSenderDid)) {
    return const E2eObservation.fatal('cli_message_sender_mismatch');
  }
  if (mismatch('receiver_did', expectedReceiverDid)) {
    return const E2eObservation.fatal('cli_message_receiver_mismatch');
  }
  if (mismatch('group_did', expectedGroupDid)) {
    return const E2eObservation.fatal('cli_message_group_mismatch');
  }
  if (mismatch('content_type', expectedContentType)) {
    return const E2eObservation.fatal('cli_message_content_type_mismatch');
  }
  return const E2eObservation.pass();
}

/// Returns the combined relationship state from the CLI's directional flags.
///
/// `relationship` is the CLI identity's outbound local projection
/// (`following` or `none`), not the combined state: an inbound-only relation
/// therefore legitimately reports `relationship=none` and
/// `is_follower=true`. Missing or contradictory flags fail closed.
String? cliRelationshipState(String output) {
  final data = _jsonValueAt(output, const <Object>['data']);
  if (data is! Map) {
    return null;
  }
  final map = _stringKeyMap(data);
  bool? flag(String key) {
    final value = map[key];
    return value is bool ? value : null;
  }

  final isFollowing = flag('is_following');
  final isFollower = flag('is_follower');
  final isFriend = flag('is_friend');
  final isBlocked = flag('is_blocked');
  final isBlockedBy = flag('is_blocked_by');
  if (<bool?>[
    isFollowing,
    isFollower,
    isFriend,
    isBlocked,
    isBlockedBy,
  ].any((value) => value == null)) {
    return null;
  }
  final following = isFollowing!;
  final follower = isFollower!;
  final friend = isFriend!;
  final blocked = isBlocked!;
  final blockedBy = isBlockedBy!;
  if (friend != (following && follower)) {
    return null;
  }
  final combined = blocked
      ? 'blocked'
      : blockedBy
      ? 'blocked_by'
      : friend
      ? 'friend'
      : following
      ? 'following'
      : follower
      ? 'follower'
      : 'none';

  final relationship = map['relationship'];
  if (relationship is! String || relationship.trim().isEmpty) {
    return null;
  }
  final outbound = relationship.trim().toLowerCase();
  if (!const <String>{'none', 'following'}.contains(outbound)) {
    return null;
  }
  if (!blocked && !blockedBy) {
    final expectedOutbound = following ? 'following' : 'none';
    if (outbound != expectedOutbound) {
      return null;
    }
  }
  final reportedCombined = map['status'];
  if (reportedCombined != null &&
      (reportedCombined is! String ||
          reportedCombined.trim().toLowerCase() != combined)) {
    return null;
  }
  return combined;
}

/// Verifies the complete P9 contract for one CLI-observed mention.
bool cliMessageHasExactSingleMention({
  required Map<String, Object?> message,
  required String expectedText,
  required String expectedMentionSurface,
  required String expectedTargetDid,
  required String expectedTargetKind,
  required String expectedMentionRole,
  String expectedRangeUnit = 'unicode_code_point',
}) {
  final payload = _cliMessagePayload(message);
  if (payload == null || payload['text'] != expectedText) {
    return false;
  }
  final mentions = payload['mentions'];
  if (mentions is! List || mentions.length != 1) {
    return false;
  }
  final rawMention = mentions.single;
  if (rawMention is! Map) {
    return false;
  }
  final mention = _stringKeyMap(rawMention);
  final mentionId = mention['id'];
  final rawRange = mention['range'];
  final rawTarget = mention['target'];
  if (mentionId is! String ||
      mentionId.trim().isEmpty ||
      rawRange is! Map ||
      rawTarget is! Map) {
    return false;
  }
  final range = _stringKeyMap(rawRange);
  final target = _stringKeyMap(rawTarget);
  final expectedEnd = expectedMentionSurface.runes.length;
  return expectedText.startsWith(expectedMentionSurface) &&
      range['start'] == 0 &&
      range['end'] == expectedEnd &&
      range['unit'] == expectedRangeUnit &&
      target['did'] == expectedTargetDid &&
      target['kind'] == expectedTargetKind &&
      mention['mention_role'] == expectedMentionRole;
}

ConversationSummary requireExactlyOneConversation({
  required Iterable<ConversationSummary> conversations,
  required String conversationId,
  required int unreadCount,
  String? lastMessage,
}) {
  final normalizedId = conversationId.trim();
  final matches = conversations
      .where(
        (conversation) => conversation.conversationId.trim() == normalizedId,
      )
      .toList(growable: false);
  if (matches.length != 1) {
    final semanticMatches = conversations.where((conversation) {
      final previewMatches =
          lastMessage == null ||
          conversation.lastMessagePreview.trim() == lastMessage.trim();
      return conversation.unreadCount == unreadCount && previewMatches;
    }).length;
    throw StateError(
      'Conversation oracle canonical_matches=${matches.length}, '
      'semantic_matches=$semanticMatches, '
      'candidate_rows=${conversations.length}.',
    );
  }
  final conversation = matches.single;
  if (conversation.unreadCount != unreadCount) {
    throw StateError(
      'Conversation unread ${conversation.unreadCount} != $unreadCount.',
    );
  }
  if (lastMessage != null &&
      conversation.lastMessagePreview.trim() != lastMessage.trim()) {
    throw StateError(
      'Conversation preview does not match the exact expected message.',
    );
  }
  return conversation;
}

ConversationSummary requireExactlyOneDirectConversationForPersona({
  required Iterable<ConversationSummary> conversations,
  required String conversationId,
  required String peerPersonaId,
  required int unreadCount,
  String? lastMessage,
}) {
  final rows = conversations.toList(growable: false);
  final normalizedPersonaId = peerPersonaId.trim();
  if (normalizedPersonaId.isEmpty) {
    throw StateError('Expected peer Persona id must be non-empty.');
  }
  final semanticMatches = rows
      .where(
        (conversation) =>
            !conversation.isGroup &&
            conversation.resolutionState ==
                ConversationIdentityResolutionState.resolved &&
            conversation.peerPersonaId?.trim() == normalizedPersonaId,
      )
      .toList(growable: false);
  if (semanticMatches.length != 1) {
    throw StateError(
      'Direct conversation semantic_matches=${semanticMatches.length}, '
      'candidate_rows=${rows.length}.',
    );
  }
  final canonical = requireExactlyOneConversation(
    conversations: rows,
    conversationId: conversationId,
    unreadCount: unreadCount,
    lastMessage: lastMessage,
  );
  if (!identical(canonical, semanticMatches.single)) {
    throw StateError('Direct canonical row does not match the Persona row.');
  }
  return canonical;
}

ConversationSummary requireExactlyOneGroupConversation({
  required Iterable<ConversationSummary> conversations,
  required String conversationId,
  required String canonicalGroupDid,
  required int unreadCount,
  String? lastMessage,
}) {
  final rows = conversations.toList(growable: false);
  final normalizedGroupDid = canonicalGroupDid.trim();
  if (normalizedGroupDid.isEmpty) {
    throw StateError('Expected canonical Group DID must be non-empty.');
  }
  final semanticMatches = rows
      .where(
        (conversation) =>
            conversation.isGroup &&
            (conversation.canonicalGroupDid?.trim().isNotEmpty ?? false) &&
            conversation.canonicalGroupDid?.trim() == normalizedGroupDid,
      )
      .toList(growable: false);
  if (semanticMatches.length != 1) {
    throw StateError(
      'Group conversation semantic_matches=${semanticMatches.length}, '
      'candidate_rows=${rows.length}.',
    );
  }
  final canonical = requireExactlyOneConversation(
    conversations: rows,
    conversationId: conversationId,
    unreadCount: unreadCount,
    lastMessage: lastMessage,
  );
  if (!identical(canonical, semanticMatches.single)) {
    throw StateError('Group canonical row does not match the Group DID row.');
  }
  return canonical;
}

void requireRelativeConversationOrder({
  required Iterable<ConversationSummary> conversations,
  required List<String> expectedConversationIds,
}) {
  final expected = expectedConversationIds
      .map((id) => id.trim())
      .toList(growable: false);
  if (expected.isEmpty ||
      expected.any((id) => id.isEmpty) ||
      expected.toSet().length != expected.length) {
    throw StateError('Expected conversation ids must be non-empty and unique.');
  }
  final rows = conversations.toList(growable: false);
  for (final id in expected) {
    final count = rows
        .where((conversation) => conversation.conversationId.trim() == id)
        .length;
    if (count != 1) {
      throw StateError('Conversation $id appears $count times in the list.');
    }
  }
  final actual = rows
      .map((conversation) => conversation.conversationId.trim())
      .where(expected.toSet().contains)
      .toList(growable: false);
  if (!_sameStringSequence(actual, expected)) {
    throw StateError('Conversation relative order does not match.');
  }
}

Future<void> requireAppProjectionRelativeConversationOrder({
  required Iterable<ConversationSummary> conversations,
  required List<String> expectedConversationIds,
  String? caseId,
}) async {
  try {
    requireRelativeConversationOrder(
      conversations: conversations,
      expectedConversationIds: expectedConversationIds,
    );
  } on StateError {
    await E2eFailureObservationWriter.recordFirst(
      layer: 'app_projection',
      status: 'fatal',
      code: 'conversation_relative_order_mismatch',
      caseId: caseId,
    );
    rethrow;
  }
}

void expectVisibleConversationOrder({
  required WidgetTester tester,
  required List<String> conversationIds,
}) {
  double? previousTop;
  for (final conversationId in conversationIds) {
    final row = find.byKey(Key('conversation-row:$conversationId'));
    expect(row, findsOneWidget);
    final top = tester.getTopLeft(row).dy;
    if (previousTop != null && top <= previousTop) {
      throw StateError('Visible conversation order does not match.');
    }
    previousTop = top;
  }
}

void expectExactConversationRowUi({
  required String conversationId,
  required String expectedTitle,
  required String expectedPreview,
  String? expectedUnreadLabel,
}) {
  final row = find.byKey(Key('conversation-row:$conversationId'));
  expect(row, findsOneWidget);
  expect(
    find.descendant(
      of: row,
      matching: find.byKey(Key('conversation-row-title:$conversationId')),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(Key('conversation-row-title:$conversationId')),
      matching: find.text(expectedTitle, findRichText: true),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byKey(Key('conversation-row-preview:$conversationId')),
      matching: find.text(expectedPreview, findRichText: true),
    ),
    findsOneWidget,
  );

  final unread = find.descendant(
    of: row,
    matching: find.byKey(const Key('conversation-preview-tag-unread')),
  );
  if (expectedUnreadLabel == null) {
    expect(unread, findsNothing);
    return;
  }
  expect(unread, findsOneWidget);
  expect(
    find.descendant(
      of: unread,
      matching: find.text(expectedUnreadLabel, findRichText: true),
    ),
    findsOneWidget,
  );
}

void expectExactlyOneScopedText({
  required Key scopeKey,
  required String expectedText,
  Iterable<String> forbiddenTexts = const <String>[],
}) {
  final scope = find.byKey(scopeKey);
  expect(scope, findsOneWidget);
  expect(
    find.descendant(
      of: scope,
      matching: find.text(expectedText, findRichText: true),
    ),
    findsOneWidget,
  );
  for (final text in forbiddenTexts) {
    if (text == expectedText || text.trim().isEmpty) {
      continue;
    }
    expect(
      find.descendant(of: scope, matching: find.text(text, findRichText: true)),
      findsNothing,
    );
  }
}

void requireUnreadTotal({required int actual, required int expected}) {
  if (actual != expected) {
    throw StateError('Unread total $actual != $expected.');
  }
}

void requireSingleMentionTarget({
  required ChatMessage message,
  required String targetDid,
}) {
  if (message.mentions.length != 1) {
    throw StateError(
      'Message "${message.content}" has ${message.mentions.length} mentions, '
      'expected exactly one.',
    );
  }
  final mention = message.mentions.single;
  if (!mention.rangeMatches(message.content)) {
    throw StateError(
      'Message "${message.content}" has an invalid mention range.',
    );
  }
  final mentionDid = mention.target.did?.trim() ?? '';
  if (mentionDid != targetDid.trim()) {
    throw StateError('Mention target ${mention.target.did} != $targetDid.');
  }
}

Object? _jsonValueAt(String output, List<Object> path) {
  Object? value;
  try {
    value = jsonDecode(output);
  } on Object {
    return null;
  }
  for (final segment in path) {
    if (value is Map) {
      value = value[segment];
      continue;
    }
    if (value is List && segment is int) {
      if (segment < 0 || segment >= value.length) {
        return null;
      }
      value = value[segment];
      continue;
    }
    return null;
  }
  return value;
}

Map<String, Object?> _stringKeyMap(Map<dynamic, dynamic> value) {
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _firstNonEmptyString(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) {
      return value.toString();
    }
  }
  return null;
}

bool _cliMessageContentMatches(
  Map<String, Object?> message,
  String expectedText,
) {
  for (final content in <Object?>[
    message['content'],
    message['payload'],
    message['body'],
  ]) {
    if (content is String) {
      if (content == expectedText) {
        return true;
      }
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          final map = _stringKeyMap(decoded);
          if (map['text'] == expectedText || map['caption'] == expectedText) {
            return true;
          }
        }
      } on FormatException {
        // Plain text is already compared above.
      }
    }
    if (content is Map) {
      final map = _stringKeyMap(content);
      if (map['text'] == expectedText || map['caption'] == expectedText) {
        return true;
      }
    }
  }
  return false;
}

bool _sameStringSequence(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

Map<String, Object?>? _cliMessagePayload(Map<String, Object?> message) {
  for (final value in <Object?>[
    message['payload'],
    message['content'],
    message['body'],
  ]) {
    if (value is Map) {
      final map = _stringKeyMap(value);
      if (map['text'] is String && map['mentions'] is List) {
        return map;
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          final map = _stringKeyMap(decoded);
          if (map['text'] is String && map['mentions'] is List) {
            return map;
          }
        }
      } on FormatException {
        // Continue through alternate wire fields.
      }
    }
  }
  return null;
}
