import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_thread_ref.dart';
import '../../application/models/conversation_patch.dart';
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
  Future<List<ConversationSummary>> loadConversationSnapshot() async {
    return _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final snapshot = await AwikiPerformanceLogger.async(
        'im_core_conversations.snapshot.native_load',
        client.messages.loadConversationSnapshot,
        level: AwikiPerformanceLogLevel.verbose,
      );
      if (snapshot == null || snapshot.items.isEmpty) {
        totalWatch.stop();
        AwikiPerformanceLogger.log(
          'im_core_conversations.snapshot',
          elapsed: totalWatch.elapsed,
          fields: const <String, Object?>{'items': 0},
          level: AwikiPerformanceLogLevel.verbose,
        );
        return const <ConversationSummary>[];
      }
      final conversations = AwikiPerformanceLogger.sync(
        'im_core_conversations.snapshot.map',
        () => snapshot.items
            .where(
              (conversation) => !_hasControlSnapshotLastMessage(conversation),
            )
            .map(
              (conversation) => _mappers.conversationFromSnapshot(
                conversation,
                ownerDid: snapshot.ownerDid,
              ),
            )
            .toList(),
        fields: <String, Object?>{'items': snapshot.items.length},
        level: AwikiPerformanceLogLevel.verbose,
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'im_core_conversations.snapshot',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'items': snapshot.items.length,
          'mapped': conversations.length,
        },
        level: AwikiPerformanceLogLevel.verbose,
      );
      return conversations;
    });
  }

  @override
  Future<void> clearConversationSnapshot() async {
    await _runtime.withCurrentClient((client) {
      return client.messages.clearConversationSnapshot();
    });
  }

  @override
  Stream<CoreConversationPatch> watchConversationPatches() async* {
    final client = await _runtime.currentClient();
    final ownerDid = (await client.identity.current()).did;
    await for (final patch in client.messages.watchConversationPatches()) {
      final mapped = _patchFromCore(patch, ownerDid: ownerDid);
      if (mapped != null) {
        yield mapped;
      }
    }
  }

  @override
  Future<CoreConversationPatch> repairConversationStore() async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final patch = await client.messages.repairConversationStore();
      return _patchFromCore(patch, ownerDid: ownerDid) ??
          CoreConversationPatch(
            kind: CoreConversationPatchKind.repairRequired,
            ownerDid: ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            reason: 'owner_mismatch',
          );
    });
  }

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

  CoreConversationPatch? _patchFromCore(
    core.ConversationStorePatch patch, {
    required String ownerDid,
  }) {
    if (patch.ownerDid != ownerDid) {
      return null;
    }
    switch (patch.kind) {
      case core.ConversationStorePatchKind.reset:
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.reset,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          items: patch.items
              .where(
                (conversation) => !_hasControlSnapshotLastMessage(
                  conversation,
                ),
              )
              .map(
                (conversation) => _mappers.conversationFromSnapshot(
                  conversation,
                  ownerDid: ownerDid,
                ),
              )
              .toList(growable: false),
        );
      case core.ConversationStorePatchKind.upsert:
        final item = patch.item;
        if (item == null || _hasControlSnapshotLastMessage(item)) {
          return CoreConversationPatch(
            kind: CoreConversationPatchKind.remove,
            ownerDid: patch.ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            threadId: item?.threadId ?? patch.threadId,
          );
        }
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.upsert,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          item: _mappers.conversationFromSnapshot(item, ownerDid: ownerDid),
        );
      case core.ConversationStorePatchKind.remove:
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.remove,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          threadId: patch.threadId,
        );
      case core.ConversationStorePatchKind.reorder:
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.reorder,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          threadId: patch.threadId,
          index: patch.index,
        );
      case core.ConversationStorePatchKind.repairRequired:
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.repairRequired,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          reason: patch.reason,
        );
    }
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
          'updated': result.updatedCount,
          'legacy_message_ids': result.legacyMessageIds.length,
          'remote_ack': result.remoteAcknowledged,
          'partial': result.partial,
          'fallback_used': result.fallbackUsed,
          'pending_remote_ack': result.pendingRemoteAck,
          'watermark_seq': result.effectiveWatermark?.lastReadThreadSeq,
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

bool _hasControlSnapshotLastMessage(
  core.ConversationSnapshotItem conversation,
) {
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
