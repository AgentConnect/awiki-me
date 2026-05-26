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

  bool get hasDisplayableText => content.trim().isNotEmpty && isTextMessage;

  bool get isTextMessage {
    final type = originalType.trim().toLowerCase();
    return type.isEmpty ||
        type == 'text' ||
        type == 'markdown' ||
        type == 'text/plain' ||
        type == 'text/markdown';
  }

  ChatMessage copyWith({
    String? remoteId,
    String? content,
    DateTime? createdAt,
    int? serverSequence,
    MessageSendState? sendState,
    String? senderName,
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
    );
  }
}
