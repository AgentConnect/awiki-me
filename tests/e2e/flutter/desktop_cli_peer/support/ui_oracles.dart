import 'dart:convert';

import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';

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

/// Returns a normalized, explicitly reported CLI relationship state.
///
/// Missing, empty, conflicting, or unknown fields are malformed and return
/// null. In particular, an absent field is never inferred to mean `none`.
String? cliRelationshipState(String output) {
  final data = _jsonValueAt(output, const <Object>['data']);
  if (data is! Map) {
    return null;
  }
  final map = _stringKeyMap(data);
  final states = <String>[];
  for (final key in const <String>['relationship', 'status']) {
    if (!map.containsKey(key)) {
      continue;
    }
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (!const <String>{
      'none',
      'following',
      'follower',
      'friend',
      'blocked',
      'blocked_by',
    }.contains(normalized)) {
      return null;
    }
    states.add(normalized);
  }
  if (states.isEmpty || states.any((state) => state != states.first)) {
    return null;
  }
  return states.first;
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
        (conversation) =>
            conversation.effectiveConversationId.trim() == normalizedId,
      )
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one conversation "$normalizedId", '
      'found ${matches.length}.',
    );
  }
  final conversation = matches.single;
  if (conversation.unreadCount != unreadCount) {
    throw StateError(
      'Conversation "$normalizedId" unread ${conversation.unreadCount} '
      '!= $unreadCount.',
    );
  }
  if (lastMessage != null &&
      conversation.lastMessagePreview.trim() != lastMessage.trim()) {
    throw StateError(
      'Conversation "$normalizedId" preview '
      '"${conversation.lastMessagePreview}" != "$lastMessage".',
    );
  }
  return conversation;
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
