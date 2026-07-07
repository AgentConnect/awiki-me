import 'chat_attachment.dart';
import 'chat_mention.dart';
import 'agent/agent_control_payloads.dart';
import 'group_system_event.dart';

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
    this.conversationId,
    this.senderName,
    this.remoteId,
    this.receiverDid,
    this.groupId,
    this.serverSequence,
    this.isEncrypted = false,
    this.originalType = 'text',
    this.attachment,
    this.payloadJson,
    this.mentions = const <ChatMessageMention>[],
  });

  final String localId;
  final String? remoteId;
  final String? conversationId;
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
  final String? payloadJson;
  final List<ChatMessageMention> mentions;

  bool get hasValidMentions =>
      mentions.any((mention) => mention.rangeMatches(content));

  bool get isMentionPayload =>
      payloadJson != null && originalType.trim().toLowerCase().contains('json');

  bool get hasDisplayableText =>
      content.trim().isNotEmpty && (isTextMessage || isMentionPayload);

  GroupSystemEvent? get groupSystemEvent =>
      GroupSystemEvent.tryParse(payloadJson);

  bool get isGroupSystemEvent => groupSystemEvent != null;

  bool get isAgentControlPayload =>
      !isGroupSystemEvent && AgentControlPayloads.isControl(payloadJson);

  bool get hasRenderableContent =>
      !isAgentControlPayload &&
      (isGroupSystemEvent || hasDisplayableText || attachment != null);

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
    if (isGroupSystemEvent) {
      return groupSystemEvent?.type ?? '';
    }
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
      return currentAttachment.displayName;
    }
    return text;
  }

  ChatMessage copyWith({
    String? remoteId,
    Object? conversationId = _chatMessageUnset,
    String? content,
    String? originalType,
    DateTime? createdAt,
    int? serverSequence,
    MessageSendState? sendState,
    String? senderName,
    ChatAttachment? attachment,
    String? payloadJson,
    List<ChatMessageMention>? mentions,
  }) {
    return ChatMessage(
      localId: localId,
      remoteId: remoteId ?? this.remoteId,
      conversationId: _resolveNullableString(
        conversationId,
        this.conversationId,
      ),
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
      originalType: originalType ?? this.originalType,
      attachment: attachment ?? this.attachment,
      payloadJson: payloadJson ?? this.payloadJson,
      mentions: mentions ?? this.mentions,
    );
  }
}

const Object _chatMessageUnset = Object();

String? _resolveNullableString(Object? value, String? current) {
  if (identical(value, _chatMessageUnset)) {
    return current;
  }
  return value as String?;
}
