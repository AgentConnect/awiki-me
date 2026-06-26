import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_thread_ref.dart';
import '../../application/ports/conversation_core_port.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/conversation_summary.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreConversationAdapter implements ConversationCorePort {
  AwikiImCoreConversationAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final ownerDid = (await AwikiPerformanceLogger.async(
        'im_core_conversations.identity_current',
        client.identity.current,
      )).did;
      final page = await AwikiPerformanceLogger.async(
        'im_core_conversations.native_list',
        () =>
            client.messages.conversations(limit: limit, unreadOnly: unreadOnly),
        fields: <String, Object?>{'limit': limit, 'unread_only': unreadOnly},
      );
      final conversations = AwikiPerformanceLogger.sync(
        'im_core_conversations.map',
        () => page.items
            .where((conversation) => !_hasControlLastMessage(conversation))
            .map(
              (conversation) => _mappers.conversationFromCore(
                conversation,
                ownerDid: ownerDid,
              ),
            )
            .toList(),
        fields: <String, Object?>{'items': page.items.length},
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'im_core_conversations.list',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'items': page.items.length,
          'mapped': conversations.length,
          'has_more': page.hasMore,
        },
      );
      return conversations;
    });
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {
    await _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final ownerDid = (await client.identity.current()).did;
      final coreThread = coreThreadRefForMarkRead(thread, ownerDid);
      final result = await AwikiPerformanceLogger.async(
        'im_core_conversations.mark_read.native',
        () => client.messages.markThreadRead(coreThread),
        fields: <String, Object?>{'thread_kind': coreThreadKind(coreThread)},
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'im_core_conversations.mark_read',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'message_ids': result.messageIds.length,
          'updated': result.updatedCount,
          'local_candidates': result.localCandidateCount,
          'local_updated': result.localUpdatedCount,
          'remote_updated': result.remoteUpdatedCount,
          'remote_ack': result.remoteAcknowledged,
          'partial': result.partial,
          'warnings': result.warnings.length,
        },
      );
    });
  }
}

bool _hasControlLastMessage(core.Conversation conversation) {
  return AgentControlPayloads.isControl(
    conversation.lastMessage?.body.payloadJson,
  );
}

core.ThreadRef coreThreadRefForMarkRead(AppThreadRef thread, String ownerDid) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => core.ThreadRef.direct(
      peerDidOrHandle,
    ),
    AppGroupThreadRef(:final groupDid) => core.ThreadRef.group(
      _stripGroupPrefix(groupDid),
    ),
    AppMessageThreadRef(:final threadId) => _coreThreadRefFromThreadId(
      threadId,
      ownerDid,
    ),
  };
}

String coreThreadKind(core.ThreadRef thread) {
  return switch (thread) {
    core.DirectThreadRef() => 'direct',
    core.GroupThreadRef() => 'group',
    core.MessageThreadRef() => 'thread',
  };
}

core.ThreadRef _coreThreadRefFromThreadId(String threadId, String ownerDid) {
  final raw = threadId.trim();
  if (raw.startsWith('group:')) {
    return core.ThreadRef.group(_stripGroupPrefix(raw));
  }
  if (raw.startsWith('dm:peer-scope:')) {
    return core.ThreadRef.thread(raw);
  }
  final peer = _directPeerFromThreadId(ownerDid, raw);
  if (peer != null) {
    return core.ThreadRef.direct(peer);
  }
  return core.ThreadRef.thread(raw);
}

String _stripGroupPrefix(String groupDid) {
  final raw = groupDid.trim();
  return raw.startsWith('group:') ? raw.substring('group:'.length) : raw;
}

String? _directPeerFromThreadId(String ownerDid, String threadId) {
  final raw = threadId.trim();
  if (!raw.startsWith('dm:')) {
    return null;
  }
  final body = raw.substring('dm:'.length);
  final owner = ownerDid.trim();
  if (owner.isEmpty) {
    return null;
  }
  if (body.startsWith('$owner:')) {
    return _nonEmpty(body.substring(owner.length + 1));
  }
  if (body.endsWith(':$owner')) {
    return _nonEmpty(body.substring(0, body.length - owner.length - 1));
  }
  return null;
}

String? _nonEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
