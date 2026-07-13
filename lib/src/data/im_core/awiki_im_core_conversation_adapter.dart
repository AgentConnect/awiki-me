import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/foundation.dart';

import '../../application/models/app_conversation_read_ref.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/models/app_thread_read_watermark.dart';
import '../../application/models/conversation_patch.dart';
import '../../application/ports/conversation_core_port.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/conversation_summary.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

const bool _imCoreConversationTraceEnabled = bool.fromEnvironment(
  'AWIKI_IM_CORE_CONVERSATION_TRACE',
  defaultValue: false,
);

class AwikiImCoreConversationAdapter
    implements ConversationCorePort, ConversationReadCorePort {
  AwikiImCoreConversationAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<void> ensureConversation(String conversationId) async {
    await _runtime.withCurrentClient((client) {
      return client.messages.ensureConversation(conversationId);
    });
  }

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
            .where(_mappers.shouldIncludeSnapshotConversation)
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
    return (await listConversationPage(
      limit: limit,
      unreadOnly: unreadOnly,
    )).items;
  }

  @override
  Future<CoreConversationPage> listConversationPage({
    int limit = 100,
    String? cursor,
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
        () => client.messages.conversations(
          limit: limit,
          cursor: cursor,
          unreadOnly: unreadOnly,
        ),
        fields: <String, Object?>{
          'limit': limit,
          'cursor': cursor != null,
          'unread_only': unreadOnly,
        },
      );
      final conversations = AwikiPerformanceLogger.sync(
        'im_core_conversations.map',
        () => page.items
            .where(_mappers.shouldIncludeConversation)
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
      return CoreConversationPage(
        items: conversations,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
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
              .where(_mappers.shouldIncludeSnapshotConversation)
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
        if (item == null || !_mappers.shouldIncludeSnapshotConversation(item)) {
          return CoreConversationPatch(
            kind: CoreConversationPatchKind.remove,
            ownerDid: patch.ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            threadId: item?.threadId ?? patch.threadId,
            conversationId:
                item?.conversationIdentity?.conversationId ??
                patch.conversationIdentity?.conversationId,
          );
        }
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.upsert,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          item: _mappers.conversationFromSnapshot(item, ownerDid: ownerDid),
          conversationId:
              item.conversationIdentity?.conversationId ??
              patch.conversationIdentity?.conversationId,
        );
      case core.ConversationStorePatchKind.remove:
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.remove,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          threadId: patch.threadId,
          conversationId: patch.conversationIdentity?.conversationId,
        );
      case core.ConversationStorePatchKind.reorder:
        return CoreConversationPatch(
          kind: CoreConversationPatchKind.reorder,
          ownerDid: patch.ownerDid,
          version: patch.version,
          unreadTotal: patch.unreadTotal,
          threadId: patch.threadId,
          conversationId: patch.conversationIdentity?.conversationId,
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
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {
    await _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      final ownerDid = (await client.identity.current()).did;
      final coreThread = coreThreadRefForMarkRead(thread, ownerDid);
      _imCoreConversationTrace(
        'mark_read.start',
        fields: <String, Object?>{
          'app_thread_ref': _appThreadRefTrace(thread),
          'core_thread_kind': coreThreadKind(coreThread),
          'core_thread_hash': AwikiPerformanceLogger.safeHash(
            _coreThreadStableId(coreThread),
          ),
          'has_watermark': watermark?.isEmpty == false,
          'watermark_seq': watermark?.lastReadThreadSeq,
          'watermark_message_hash': AwikiPerformanceLogger.safeHash(
            watermark?.lastReadMessageId,
          ),
        },
      );
      try {
        final result = await AwikiPerformanceLogger.async(
          'im_core_conversations.mark_read.native',
          () => client.messages.markThreadRead(
            coreThread,
            watermark: _coreReadWatermark(watermark),
          ),
          fields: <String, Object?>{
            'thread_kind': coreThreadKind(coreThread),
            'has_watermark': watermark?.isEmpty == false,
            'watermark_seq': watermark?.lastReadThreadSeq,
            'watermark_message': watermark?.lastReadMessageId != null,
          },
        );
        totalWatch.stop();
        _imCoreConversationTrace(
          'mark_read.done',
          fields: <String, Object?>{
            'core_thread_kind': coreThreadKind(coreThread),
            'updated': result.updatedCount,
            'legacy_message_ids': result.legacyMessageIds.length,
            'remote_ack': result.remoteAcknowledged,
            'partial': result.partial,
            'fallback_used': result.fallbackUsed,
            'pending_remote_ack': result.pendingRemoteAck,
            'watermark_seq': result.effectiveWatermark?.lastReadThreadSeq,
            'warnings': result.warnings.length,
            'elapsed_ms': totalWatch.elapsedMilliseconds,
          },
        );
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
      } catch (error) {
        totalWatch.stop();
        _imCoreConversationTrace(
          'mark_read.failed',
          fields: <String, Object?>{
            'core_thread_kind': coreThreadKind(coreThread),
            'error_type': error.runtimeType,
            'elapsed_ms': totalWatch.elapsedMilliseconds,
          },
        );
        rethrow;
      }
    });
  }

  @override
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) async {
    await _runtime.withCurrentClient((client) async {
      final totalWatch = Stopwatch()..start();
      _imCoreConversationTrace(
        'mark_conversation_read.start',
        fields: <String, Object?>{
          'conversation_hash': AwikiPerformanceLogger.safeHash(
            conversation.conversationId,
          ),
          'has_watermark': watermark?.isEmpty == false,
          'watermark_seq': watermark?.lastReadThreadSeq,
          'watermark_message_hash': AwikiPerformanceLogger.safeHash(
            watermark?.lastReadMessageId,
          ),
        },
      );
      try {
        final result = await AwikiPerformanceLogger.async(
          'im_core_conversations.mark_conversation_read.native',
          () => client.messages.markConversationRead(
            core.ConversationReadRef(
              conversationId: conversation.conversationId,
            ),
            watermark: _coreReadWatermark(watermark),
          ),
          fields: <String, Object?>{
            'conversation_hash': AwikiPerformanceLogger.safeHash(
              conversation.conversationId,
            ),
            'has_watermark': watermark?.isEmpty == false,
            'watermark_seq': watermark?.lastReadThreadSeq,
            'watermark_message': watermark?.lastReadMessageId != null,
          },
        );
        totalWatch.stop();
        _imCoreConversationTrace(
          'mark_conversation_read.done',
          fields: <String, Object?>{
            'updated': result.updatedCount,
            'legacy_message_ids': result.legacyMessageIds.length,
            'remote_ack': result.remoteAcknowledged,
            'partial': result.partial,
            'fallback_used': result.fallbackUsed,
            'pending_remote_ack': result.pendingRemoteAck,
            'watermark_seq': result.effectiveWatermark?.lastReadThreadSeq,
            'warnings': result.warnings.length,
            'elapsed_ms': totalWatch.elapsedMilliseconds,
          },
        );
      } catch (error) {
        totalWatch.stop();
        _imCoreConversationTrace(
          'mark_conversation_read.failed',
          fields: <String, Object?>{
            'conversation_hash': AwikiPerformanceLogger.safeHash(
              conversation.conversationId,
            ),
            'error_type': error.runtimeType,
            'elapsed_ms': totalWatch.elapsedMilliseconds,
          },
        );
        rethrow;
      }
    });
  }
}

core.ReadWatermark? _coreReadWatermark(AppThreadReadWatermark? watermark) {
  if (watermark == null || watermark.isEmpty) {
    return null;
  }
  return core.ReadWatermark(
    lastReadMessageId: _nonEmptyText(watermark.lastReadMessageId),
    lastReadThreadSeq: _nonEmptyText(watermark.lastReadThreadSeq),
    readAt: watermark.readAt,
  );
}

String? _nonEmptyText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

void _imCoreConversationTrace(
  String event, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (!_imCoreConversationTraceEnabled) {
    return;
  }
  final details = <String>[];
  for (final entry in fields.entries) {
    final value = entry.value;
    if (value != null) {
      details.add('${entry.key}=${_collapseImCoreConversationTrace(value)}');
    }
  }
  debugPrint(
    details.isEmpty
        ? '[awiki_me][im_core_conversation_trace] event=$event'
        : '[awiki_me][im_core_conversation_trace] event=$event ${details.join(' ')}',
  );
}

String _appThreadRefTrace(AppThreadRef ref) {
  final kind = switch (ref) {
    AppDirectThreadRef() => 'direct',
    AppGroupThreadRef() => 'group',
    AppMessageThreadRef() => 'thread',
  };
  return '$kind:${AwikiPerformanceLogger.safeHash(ref.stableId)}';
}

String _coreThreadStableId(core.ThreadRef ref) {
  return switch (ref) {
    core.DirectThreadRef(:final peer) => 'direct:$peer',
    core.GroupThreadRef(:final group) => 'group:$group',
    core.MessageThreadRef(:final threadId) => 'thread:$threadId',
  };
}

String _collapseImCoreConversationTrace(Object value) {
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  final raw = value.toString();
  final buffer = StringBuffer();
  var lastWasWhitespace = false;
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      if (!lastWasWhitespace) {
        buffer.write('_');
      }
      lastWasWhitespace = true;
    } else {
      buffer.write(char);
      lastWasWhitespace = false;
    }
  }
  return buffer.toString();
}
