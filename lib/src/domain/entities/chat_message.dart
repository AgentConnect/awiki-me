import 'chat_attachment.dart';

enum MessageSendState { sending, sent, failed }

class ChatMessage {
  const ChatMessage({
    required this.localId,
    required this.threadId,
    required this.senderDid,
    required this.content,
    required this.createdAt,
    required this.isMine,
    required this.sendState,
    this.senderName,
    this.remoteId,
    this.receiverDid,
    this.groupId,
    this.serverSequence,
    this.isEncrypted = false,
    this.originalType = 'text',
    this.attachment,
  });

  final String localId;
  final String? remoteId;
  final String threadId;
  final String senderDid;
  final String? senderName;
  final String? receiverDid;
  final String? groupId;
  final String content;
  final String originalType;
  final DateTime createdAt;
  final bool isMine;
  final int? serverSequence;
  final bool isEncrypted;
  final MessageSendState sendState;
  final ChatAttachment? attachment;

  bool get hasDisplayableText => content.trim().isNotEmpty && isTextMessage;

  bool get hasRenderableContent => hasDisplayableText || attachment != null;

  bool get isTextMessage {
    final type = originalType.trim().toLowerCase();
    return type.isEmpty ||
        type == 'text' ||
        type == 'markdown' ||
        type == 'text/plain' ||
        type == 'text/markdown';
  }

  bool get isAttachmentMessage => attachment != null;

  String get previewText {
    final text = content.trim();
    if (text.isNotEmpty && (isTextMessage || attachment == null)) {
      return text;
    }
    final currentAttachment = attachment;
    if (currentAttachment != null) {
      final caption = currentAttachment.caption?.trim();
      if (caption != null && caption.isNotEmpty) {
        return caption;
      }
      return '[附件] ${currentAttachment.displayName}';
    }
    return text;
  }

  ChatMessage copyWith({
    String? remoteId,
    String? content,
    DateTime? createdAt,
    int? serverSequence,
    MessageSendState? sendState,
    String? senderName,
    ChatAttachment? attachment,
  }) {
    return ChatMessage(
      localId: localId,
      remoteId: remoteId ?? this.remoteId,
      threadId: threadId,
      senderDid: senderDid,
      senderName: senderName ?? this.senderName,
      receiverDid: receiverDid,
      groupId: groupId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      isMine: isMine,
      sendState: sendState ?? this.sendState,
      serverSequence: serverSequence ?? this.serverSequence,
      isEncrypted: isEncrypted,
      originalType: originalType,
      attachment: attachment ?? this.attachment,
    );
  }
}
