import 'dart:convert';

class MessageReplyReference {
  const MessageReplyReference({
    required this.sourceMessageId,
    this.runId,
    this.senderName,
    this.excerpt,
  });

  final String sourceMessageId;
  final String? runId;
  final String? senderName;
  final String? excerpt;

  Map<String, Object?> get annotations => {
    'awiki_reply_to_message_id': sourceMessageId,
    if (senderName != null) 'awiki_reply_sender_name': senderName,
    if (excerpt != null) 'awiki_reply_excerpt': excerpt,
  };

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
    final runId = annotations['awiki_run_id'];
    if (annotations.containsKey('awiki_run_id') &&
        (runId is! String || runId.trim().isEmpty)) {
      return null;
    }
    return MessageReplyReference(
      sourceMessageId: sourceMessageId,
      senderName: annotations['awiki_reply_sender_name'] is String
          ? annotations['awiki_reply_sender_name'] as String
          : null,
      excerpt: annotations['awiki_reply_excerpt'] is String
          ? annotations['awiki_reply_excerpt'] as String
          : null,
      runId: runId is String && runId.trim().isNotEmpty ? runId.trim() : null,
    );
  }
}
