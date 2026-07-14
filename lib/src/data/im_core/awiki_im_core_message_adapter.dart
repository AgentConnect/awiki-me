import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/attachment_models.dart';
import '../../application/models/app_conversation_read_ref.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/thread_message_patch.dart';
import '../../application/ports/message_core_port.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreMessageAdapter
    implements
        MessageCorePort,
        LocalHistoryMessageCorePort,
        ThreadPatchMessageCorePort,
        ConversationTimelineMessageCorePort {
  AwikiImCoreMessageAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;
  core.AwikiImClient? _ownerDidClient;
  String? _ownerDid;

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
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
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
      final mentionPayloadJson = mentions.isEmpty || caption == null
          ? null
          : jsonEncode(
              ChatMentionPayload.toP9Json(
                text: caption,
                draftMentions: mentions,
              ),
            );
      final result = await client.attachments.send(
        core.AttachmentSendRequest(
          target: _mappers.messageTargetToCore(thread),
          input: _attachmentInputToCore(attachment),
          caption: caption,
          mentionPayloadJson: mentionPayloadJson,
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
  Future<ChatMessage> sendConversationAttachment({
    required AppConversationReadRef conversation,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
      final mentionPayloadJson = mentions.isEmpty || caption == null
          ? null
          : jsonEncode(
              ChatMentionPayload.toP9Json(
                text: caption,
                draftMentions: mentions,
              ),
            );
      final result = await client.attachments.sendConversation(
        core.SendConversationAttachmentRequest(
          conversation: core.ConversationReadRef(
            conversationId: conversation.conversationId,
          ),
          input: _attachmentInputToCore(attachment),
          caption: caption,
          mentionPayloadJson: mentionPayloadJson,
          filename: attachment.filename,
          mimeType: attachment.mimeType,
          clientMessageId: clientMessageId,
          idempotencyKey: idempotencyKey,
        ),
      );
      return _conversationMessageFromCore(
        result.message.message,
        ownerDid: ownerDid,
        expectedConversationId: conversation.conversationId,
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
      final ownerDid = await _currentOwnerDid(client);
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
  Future<ChatMessage> sendConversationText({
    required AppConversationReadRef conversation,
    required String content,
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
      final result = await client.messages.sendConversationText(
        core.SendConversationTextRequest(
          conversation: core.ConversationReadRef(
            conversationId: conversation.conversationId,
          ),
          text: content,
          clientMessageId: clientMessageId,
          idempotencyKey: idempotencyKey,
        ),
      );
      return _conversationMessageFromCore(
        result.message,
        ownerDid: ownerDid,
        expectedConversationId: conversation.conversationId,
      );
    });
  }

  @override
  Future<ChatMessage> sendConversationPayload({
    required AppConversationReadRef conversation,
    required Map<String, Object?> payload,
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
      final result = await client.messages.sendConversationPayload(
        core.SendConversationPayloadRequest(
          conversation: core.ConversationReadRef(
            conversationId: conversation.conversationId,
          ),
          payloadJson: jsonEncode(payload),
          clientMessageId: clientMessageId,
          idempotencyKey: idempotencyKey,
        ),
      );
      return _conversationMessageFromCore(
        result.message,
        ownerDid: ownerDid,
        expectedConversationId: conversation.conversationId,
      );
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
    bool includeControlPayloads = false,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final ownerDid = await _currentOwnerDid(client);
      final coreThread = _mappers.threadRefToCore(thread);
      final page = await AwikiPerformanceLogger.async(
        'im_core_messages.remote_history_native',
        () => AwikiPerformanceLogger.async(
          'im_core_messages.history_native',
          () =>
              client.messages.history(coreThread, limit: limit, cursor: cursor),
          fields: <String, Object?>{
            'limit': limit,
            'cursor': cursor != null,
            'thread_kind': thread.runtimeType.toString(),
          },
        ),
        fields: <String, Object?>{
          'limit': limit,
          'cursor': cursor != null,
          'thread_kind': thread.runtimeType.toString(),
        },
      );
      final messages = AwikiPerformanceLogger.sync(
        'im_core_messages.history_map',
        () => page.items
            .map(
              (message) =>
                  _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
            )
            .where(
              (message) =>
                  includeControlPayloads || message.hasRenderableContent,
            )
            .toList(),
        fields: <String, Object?>{
          'items': page.items.length,
          'include_control_payloads': includeControlPayloads,
        },
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'im_core_messages.history',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'items': page.items.length,
          'returned': messages.length,
          'has_more': page.hasMore,
          'include_control_payloads': includeControlPayloads,
        },
      );
      return messages;
    });
  }

  @override
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final ownerDid = await _currentOwnerDid(client);
      final coreThread = _mappers.threadRefToCore(thread);
      final page = await AwikiPerformanceLogger.async(
        'im_core_messages.local_history_native',
        () => client.messages.localHistory(
          coreThread,
          limit: limit,
          cursor: cursor,
        ),
        fields: <String, Object?>{
          'limit': limit,
          'cursor': cursor != null,
          'thread_kind': thread.runtimeType.toString(),
        },
      );
      final messages = AwikiPerformanceLogger.sync(
        'im_core_messages.local_history_map',
        () => page.items
            .map(
              (message) =>
                  _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
            )
            .where(
              (message) =>
                  includeControlPayloads || message.hasRenderableContent,
            )
            .toList(),
        fields: <String, Object?>{
          'items': page.items.length,
          'include_control_payloads': includeControlPayloads,
        },
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'im_core_messages.local_history',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'items': page.items.length,
          'returned': messages.length,
          'has_more': page.hasMore,
          'include_control_payloads': includeControlPayloads,
        },
      );
      return messages;
    });
  }

  @override
  Future<List<ChatMessage>> loadConversationTimeline(
    AppConversationReadRef conversation, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final ownerDid = await _currentOwnerDid(client);
      final page = await AwikiPerformanceLogger.async(
        'im_core_messages.conversation_timeline_native',
        () => client.messages.localConversationTimeline(
          core.ConversationReadRef(conversationId: conversation.conversationId),
          limit: limit,
          cursor: cursor,
        ),
        fields: <String, Object?>{
          'limit': limit,
          'cursor': cursor != null,
          'conversation_hash': AwikiPerformanceLogger.safeHash(
            conversation.conversationId,
          ),
        },
      );
      final messages = AwikiPerformanceLogger.sync(
        'im_core_messages.conversation_timeline_map',
        () => page.items
            .map(
              (message) => _conversationMessageFromCore(
                message,
                ownerDid: ownerDid,
                expectedConversationId: conversation.conversationId,
              ),
            )
            .where(
              (message) =>
                  includeControlPayloads || message.hasRenderableContent,
            )
            .toList(),
        fields: <String, Object?>{
          'items': page.items.length,
          'include_control_payloads': includeControlPayloads,
        },
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'im_core_messages.conversation_timeline',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'items': page.items.length,
          'returned': messages.length,
          'has_more': page.hasMore,
          'include_control_payloads': includeControlPayloads,
        },
      );
      return messages;
    });
  }

  @override
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  }) async* {
    final client = await _runtime.currentClient();
    final ownerDid = await _currentOwnerDid(client);
    yield* client.messages
        .watchThreadPatches(_mappers.threadRefToCore(thread), limit: limit)
        .map((patch) => _threadPatchFromCore(patch, ownerDid: ownerDid));
  }

  @override
  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
      final patch = await client.messages.repairThreadStore(
        _mappers.threadRefToCore(thread),
        limit: limit,
      );
      return _threadPatchFromCore(patch, ownerDid: ownerDid);
    });
  }

  @override
  Stream<ThreadMessagePatch> watchConversationTimelinePatches(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) async* {
    final client = await _runtime.currentClient();
    final ownerDid = await _currentOwnerDid(client);
    yield* client.messages
        .watchConversationTimelinePatches(
          core.ConversationReadRef(conversationId: conversation.conversationId),
          limit: limit,
        )
        .map(
          (patch) => _conversationPatchFromCore(
            patch,
            ownerDid: ownerDid,
            expectedConversationId: conversation.conversationId,
          ),
        );
  }

  @override
  Future<ThreadMessagePatch> repairConversationTimelineStore(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = await _currentOwnerDid(client);
      final patch = await client.messages.repairConversationTimelineStore(
        core.ConversationReadRef(conversationId: conversation.conversationId),
        limit: limit,
      );
      return _conversationPatchFromCore(
        patch,
        ownerDid: ownerDid,
        expectedConversationId: conversation.conversationId,
      );
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

  Future<String> _currentOwnerDid(core.AwikiImClient client) async {
    final cachedOwnerDid = _ownerDid;
    if (identical(_ownerDidClient, client) &&
        cachedOwnerDid != null &&
        cachedOwnerDid.isNotEmpty) {
      return cachedOwnerDid;
    }
    final identity = await AwikiPerformanceLogger.async(
      'im_core_messages.identity_current',
      client.identity.current,
    );
    final ownerDid = identity.did;
    _ownerDidClient = client;
    _ownerDid = ownerDid;
    return ownerDid;
  }

  ThreadMessagePatch _threadPatchFromCore(
    core.ThreadMessageStorePatch patch, {
    required String ownerDid,
  }) {
    final messages = patch.items
        .map(
          (message) =>
              _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
        )
        .where((message) => message.hasRenderableContent)
        .toList();
    final message = patch.message == null
        ? null
        : _mappers.chatMessageFromCore(patch.message!, ownerDid: ownerDid);
    return ThreadMessagePatch(
      kind: switch (patch.kind) {
        core.ThreadMessageStorePatchKind.reset => ThreadMessagePatchKind.reset,
        core.ThreadMessageStorePatchKind.upsert =>
          ThreadMessagePatchKind.upsert,
        core.ThreadMessageStorePatchKind.remove =>
          ThreadMessagePatchKind.remove,
        core.ThreadMessageStorePatchKind.repairRequired =>
          ThreadMessagePatchKind.repairRequired,
      },
      ownerDid: patch.ownerDid,
      version: patch.version,
      threadKind: patch.threadKind,
      threadId: patch.threadId,
      conversationId:
          patch.conversationIdentity?.conversationId ??
          message?.conversationId ??
          _firstConversationId(messages),
      messages: messages,
      message: message == null || message.hasRenderableContent ? message : null,
      index: patch.index,
      messageId: patch.messageId,
      reason: patch.reason,
    );
  }

  ChatMessage _conversationMessageFromCore(
    core.Message message, {
    required String ownerDid,
    required String expectedConversationId,
  }) {
    final mapped = _mappers.chatMessageFromCore(message, ownerDid: ownerDid);
    _requireExpectedConversationId(
      mapped.conversationId,
      expectedConversationId,
    );
    return mapped;
  }

  ThreadMessagePatch _conversationPatchFromCore(
    core.ThreadMessageStorePatch patch, {
    required String ownerDid,
    required String expectedConversationId,
  }) {
    _requireExpectedConversationId(
      patch.conversationIdentity?.conversationId,
      expectedConversationId,
    );
    for (final message in patch.items) {
      _requireExpectedConversationId(
        message.conversationId,
        expectedConversationId,
      );
    }
    final message = patch.message;
    if (message != null) {
      _requireExpectedConversationId(
        message.conversationId,
        expectedConversationId,
      );
    }
    return _threadPatchFromCore(patch, ownerDid: ownerDid);
  }
}

void _requireExpectedConversationId(
  String? actualConversationId,
  String expectedConversationId,
) {
  final actual = actualConversationId?.trim();
  if (actual == null || actual.isEmpty) {
    throw StateError('canonical_conversation_identity_missing');
  }
  if (actual != expectedConversationId) {
    throw StateError('canonical_conversation_identity_mismatch');
  }
}

String? _firstConversationId(Iterable<ChatMessage> messages) {
  for (final message in messages) {
    final conversationId = message.conversationId?.trim();
    if (conversationId != null && conversationId.isNotEmpty) {
      return conversationId;
    }
  }
  return null;
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
