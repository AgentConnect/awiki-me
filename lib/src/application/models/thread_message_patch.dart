import '../../domain/entities/chat_message.dart';

enum ThreadMessagePatchKind { reset, upsert, remove, repairRequired }

class ThreadMessagePatch {
  const ThreadMessagePatch({
    required this.kind,
    required this.ownerDid,
    required this.version,
    required this.threadKind,
    required this.threadId,
    this.conversationId,
    this.messages = const <ChatMessage>[],
    this.message,
    this.index,
    this.messageId,
    this.reason,
  });

  final ThreadMessagePatchKind kind;
  final String ownerDid;
  final int version;
  final String threadKind;
  final String threadId;
  final String? conversationId;
  final List<ChatMessage> messages;
  final ChatMessage? message;
  final int? index;
  final String? messageId;
  final String? reason;
}
