import 'common.dart';

class ImConversationDto {
  const ImConversationDto({
    required this.thread,
    required this.displayName,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.securityMode,
    this.avatarSeed,
    this.metadata = const <String, Object?>{},
  });

  final ImThreadRef thread;
  final String displayName;
  final String lastMessagePreview;
  final DateTime lastMessageAt;
  final int unreadCount;
  final ImSecurityMode securityMode;
  final String? avatarSeed;
  final Map<String, Object?> metadata;
}

class ImMessageDto {
  const ImMessageDto({
    required this.localId,
    this.remoteId,
    required this.thread,
    required this.direction,
    required this.kind,
    required this.securityMode,
    required this.sendState,
    required this.readState,
    required this.senderDid,
    this.senderHandle,
    this.senderDisplayName,
    this.receiverDid,
    this.groupId,
    this.plaintextText,
    this.content = const <String, Object?>{},
    this.attachments = const <ImAttachmentDto>[],
    required this.createdAt,
    this.acceptedAt,
    this.serverSequence,
    this.operationId,
    this.errorCode,
    this.retryHint,
    this.metadata = const <String, Object?>{},
  });

  final String localId;
  final String? remoteId;
  final ImThreadRef thread;
  final ImMessageDirection direction;
  final ImMessageKind kind;
  final ImSecurityMode securityMode;
  final ImSendState sendState;
  final ImReadState readState;
  final String senderDid;
  final String? senderHandle;
  final String? senderDisplayName;
  final String? receiverDid;
  final String? groupId;
  final String? plaintextText;
  final Map<String, Object?> content;
  final List<ImAttachmentDto> attachments;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final int? serverSequence;
  final String? operationId;
  final String? errorCode;
  final String? retryHint;
  final Map<String, Object?> metadata;

  ImMessageDto copyWith({
    ImSendState? sendState,
    ImReadState? readState,
    String? errorCode,
    String? retryHint,
  }) {
    return ImMessageDto(
      localId: localId,
      remoteId: remoteId,
      thread: thread,
      direction: direction,
      kind: kind,
      securityMode: securityMode,
      sendState: sendState ?? this.sendState,
      readState: readState ?? this.readState,
      senderDid: senderDid,
      senderHandle: senderHandle,
      senderDisplayName: senderDisplayName,
      receiverDid: receiverDid,
      groupId: groupId,
      plaintextText: plaintextText,
      content: content,
      attachments: attachments,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      serverSequence: serverSequence,
      operationId: operationId,
      errorCode: errorCode ?? this.errorCode,
      retryHint: retryHint ?? this.retryHint,
      metadata: metadata,
    );
  }
}

class ImAttachmentDto {
  const ImAttachmentDto({
    required this.attachmentId,
    required this.fileName,
    required this.mimeType,
    this.sizeBytes,
    this.localPath,
    this.downloadUrl,
    this.objectId,
    this.sha256,
    this.metadata = const <String, Object?>{},
  });

  final String attachmentId;
  final String fileName;
  final String mimeType;
  final int? sizeBytes;
  final String? localPath;
  final Uri? downloadUrl;
  final String? objectId;
  final String? sha256;
  final Map<String, Object?> metadata;
}
