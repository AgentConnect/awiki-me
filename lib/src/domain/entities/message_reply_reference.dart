import 'dart:convert';

class MessageReplyReference {
  const MessageReplyReference({required this.sourceMessageId, this.runId});

  final String sourceMessageId;
  final String? runId;

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
      runId: runId is String && runId.trim().isNotEmpty ? runId.trim() : null,
    );
  }
}
