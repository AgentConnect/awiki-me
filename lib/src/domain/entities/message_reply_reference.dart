import 'dart:convert';

class MessageReplyReference {
  const MessageReplyReference({required this.sourceMessageId});

  final String sourceMessageId;

  static MessageReplyReference? tryParse(String? payloadJson) {
    final raw = payloadJson?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final annotations = decoded['annotations'];
    if (annotations is! Map) {
      return null;
    }
    final sourceMessageId = annotations['awiki_reply_to_message_id']
        ?.toString()
        .trim();
    if (sourceMessageId == null || sourceMessageId.isEmpty) {
      return null;
    }
    return MessageReplyReference(sourceMessageId: sourceMessageId);
  }
}
