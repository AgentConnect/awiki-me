import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/attachment_models.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/ports/message_core_port.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreMessageAdapter implements MessageCorePort {
  AwikiImCoreMessageAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.messages.sendText(
        core.SendTextRequest(
          target: _mappers.messageTargetToCore(thread),
          text: content,
        ),
      );
      return _mappers.chatMessageFromCore(result.message, ownerDid: ownerDid);
    });
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.attachments.send(
        core.AttachmentSendRequest(
          target: _mappers.messageTargetToCore(thread),
          input: _attachmentInputToCore(attachment),
          caption: caption,
          filename: attachment.filename,
          mimeType: attachment.mimeType,
          idempotencyKey: idempotencyKey,
        ),
      );
      return _mappers.chatMessageFromCore(
        result.message.message,
        ownerDid: ownerDid,
      );
    });
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.messages.sendPayload(
        core.SendPayloadRequest(
          target: _mappers.messageTargetToCore(thread),
          payloadJson: jsonEncode(payload),
          security: secure
              ? core.MessageSecurityMode.secureDirect
              : core.MessageSecurityMode.defaultPlain,
          idempotencyKey: idempotencyKey,
        ),
      );
      return _mappers.chatMessageFromCore(result.message, ownerDid: ownerDid);
    });
  }

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final result = await client.attachments.download(
        core.DownloadAttachmentRequest(
          thread: _mappers.threadRefToCore(thread),
          messageId: messageId,
          attachmentId: attachmentId,
          destination: localPath == null
              ? const core.AttachmentDestination.memory()
              : core.AttachmentDestination.localFile(localPath),
          overwrite: true,
        ),
      );
      return AttachmentDownloadResult(
        attachmentId: result.attachmentId,
        filename: result.filename,
        mimeType: result.mimeType,
        sizeBytes: result.sizeBytes,
        localPath: switch (result.destination) {
          core.DownloadedAttachmentLocalFile(:final path) => path,
          core.DownloadedAttachmentMemory() => null,
        },
        bytes: switch (result.destination) {
          core.DownloadedAttachmentLocalFile() => null,
          core.DownloadedAttachmentMemory(:final bytes) => Uint8List.fromList(
            bytes,
          ),
        },
        warnings: result.warnings,
      );
    });
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final page = await client.messages.history(
        _mappers.threadRefToCore(thread),
        limit: limit,
        cursor: cursor,
      );
      return page.items
          .map(
            (message) =>
                _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
          )
          .where((message) => message.hasRenderableContent)
          .toList();
    });
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    final mentionPayload = ChatMentionPayload.tryParsePayloadJson(
      failed.payloadJson,
    );
    if (mentionPayload != null && mentionPayload.hasValidMentions) {
      final decoded = jsonDecode(failed.payloadJson!) as Map;
      return sendPayload(
        thread: _threadFromFailedMessage(failed),
        payload: decoded.cast<String, Object?>(),
        secure: false,
        idempotencyKey: failed.localId,
      );
    }
    return sendText(
      thread: _threadFromFailedMessage(failed),
      content: failed.content,
    );
  }
}

core.AttachmentInput _attachmentInputToCore(AttachmentDraft attachment) {
  final localPath = attachment.localPath?.trim();
  if (localPath != null && localPath.isNotEmpty) {
    return core.AttachmentInput.localFile(localPath);
  }
  final bytes = attachment.bytes;
  if (bytes == null) {
    throw StateError('Attachment draft requires a local path or bytes.');
  }
  return core.AttachmentInput.bytes(
    filename: attachment.filename,
    mimeType: attachment.mimeType,
    bytes: bytes,
  );
}

AppThreadRef _threadFromFailedMessage(ChatMessage failed) {
  final groupId = failed.groupId;
  if (groupId != null && groupId.trim().isNotEmpty) {
    return AppThreadRef.group(groupId);
  }
  final peer = failed.isMine ? failed.receiverDid : failed.senderDid;
  if (peer == null || peer.trim().isEmpty) {
    throw StateError('Cannot retry message without a direct peer or group id.');
  }
  return AppThreadRef.direct(peer);
}
