import '../models/common.dart';
import '../models/message_models.dart';

abstract class ImMessageApi {
  Future<ImPage<ImMessageDto>> list(ImListMessagesRequest request);
  Future<ImSendResultDto> send(ImSendMessageRequest request);
  Future<void> markRead(ImMarkReadRequest request);
  Future<void> sync(ImSyncRequest request);
}

class ImListMessagesRequest {
  const ImListMessagesRequest({
    required this.thread,
    this.limit = 50,
    this.cursor,
    this.sinceSequence,
    this.includeLocalPending = true,
  });

  final ImThreadRef thread;
  final int limit;
  final String? cursor;
  final int? sinceSequence;
  final bool includeLocalPending;
}

class ImSendMessageRequest {
  const ImSendMessageRequest({
    required this.target,
    this.text,
    this.messageType = 'text',
    this.securityMode = ImSecurityMode.transportProtected,
    this.attachments = const <ImAttachmentInput>[],
    this.clientOperationId,
    this.metadata = const <String, Object?>{},
  });

  final ImSendTarget target;
  final String? text;
  final String messageType;
  final ImSecurityMode securityMode;
  final List<ImAttachmentInput> attachments;
  final String? clientOperationId;
  final Map<String, Object?> metadata;
}

class ImSendTarget {
  const ImSendTarget({this.peerDidOrHandle, this.groupId});

  final String? peerDidOrHandle;
  final String? groupId;
}

class ImSendResultDto {
  const ImSendResultDto({
    required this.message,
    required this.accepted,
    required this.finalAcceptance,
    this.remoteMessageId,
    this.operationId,
    this.deliveryState,
  });

  final ImMessageDto message;
  final bool accepted;
  final bool finalAcceptance;
  final String? remoteMessageId;
  final String? operationId;
  final String? deliveryState;
}

class ImMarkReadRequest {
  const ImMarkReadRequest({this.messageIds = const <String>[], this.threadId});

  final List<String> messageIds;
  final String? threadId;
}

class ImSyncRequest {
  const ImSyncRequest({
    this.scope,
    this.threadId,
    this.limit = 100,
    this.pullRemote = false,
    this.processRealtimeBacklog = true,
  });

  final ImThreadKind? scope;
  final String? threadId;
  final int limit;
  final bool pullRemote;
  final bool processRealtimeBacklog;
}

class ImAttachmentInput {
  const ImAttachmentInput({
    this.localPath,
    this.bytes,
    required this.fileName,
    this.mimeType,
    this.caption,
  });

  final String? localPath;
  final List<int>? bytes;
  final String fileName;
  final String? mimeType;
  final String? caption;
}
