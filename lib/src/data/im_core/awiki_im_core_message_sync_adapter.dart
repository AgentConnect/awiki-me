import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_conversation_read_ref.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/ports/message_sync_core_port.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreMessageSyncAdapter
    implements MessageSyncCorePort, ConversationMessageSyncCorePort {
  AwikiImCoreMessageSyncAdapter({
    required AwikiImCoreRuntime runtime,
    required bool syncV2ReadEnabled,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _syncV2ReadEnabled = syncV2ReadEnabled,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final bool _syncV2ReadEnabled;
  final AwikiImCoreMappers _mappers;

  @override
  Future<MessageSyncOutcome> syncNow({int? limit, required String reason}) {
    return _runtime.withCurrentClient((client) async {
      if (_syncV2ReadEnabled) {
        final ownerDid = (await client.identity.current()).did;
        final result = await client.messages.syncNow(
          core.MessageSyncRequest(reason: reason, limit: limit),
        );
        final committedIncoming = <CommittedIncomingMessage>[];
        for (final committed in result.committedIncomingMessages) {
          if (committed.source != core.CommittedMessageSource.liveDelta ||
              committed.direction != core.MessageDirection.incoming) {
            throw StateError('message_sync_committed_event_invalid');
          }
          final eventId = committed.eventId.trim();
          final logicalMessageId = committed.logicalMessageId.trim();
          final message = _mappers.chatMessageFromCore(
            committed.message,
            ownerDid: ownerDid,
          );
          if (eventId.isEmpty ||
              logicalMessageId.isEmpty ||
              message.isMine ||
              message.remoteId?.trim() != logicalMessageId) {
            throw StateError('message_sync_committed_event_invalid');
          }
          committedIncoming.add(
            CommittedIncomingMessage(
              eventId: eventId,
              logicalMessageId: logicalMessageId,
              message: message,
            ),
          );
        }
        return MessageSyncOutcome(
          status: _messageSyncStatusFromCore(result.status),
          eventsApplied: result.eventsApplied,
          pagesFetched: result.pagesFetched,
          messagesHydrated: result.messagesHydrated,
          duplicatesSkipped: result.duplicatesSkipped,
          changedConversationIds: List<String>.unmodifiable(
            result.changedConversationIds,
          ),
          committedIncomingMessages:
              List<CommittedIncomingMessage>.unmodifiable(committedIncoming),
          errorCode: _nonEmpty(result.errorCode),
          warnings: List<String>.unmodifiable(result.warnings),
        );
      }
      final result = await client.messages.syncDelta(
        core.SyncDeltaRequest(limit: limit, reason: reason),
      );
      return MessageSyncOutcome(
        status: result.snapshotRequired
            ? MessageSyncStatus.recoveryRequired
            : result.eventsApplied > 0
            ? MessageSyncStatus.changed
            : MessageSyncStatus.idle,
        eventsApplied: result.eventsApplied,
        pagesFetched: result.pagesFetched,
        warnings: result.warnings,
      );
    });
  }

  @override
  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  }) {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.messages.syncThreadAfter(
        core.SyncThreadAfterRequest(
          thread: _mappers.threadRefToCore(thread),
          afterServerSeq: afterServerSeq,
          limit: limit,
        ),
      );
      return MessageSyncThreadAfterResult(
        messages: result.messages
            .map(
              (message) =>
                  _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
            )
            .toList(),
        nextAfterServerSeq: result.nextAfterServerSeq,
        hasMore: result.hasMore,
        warnings: result.warnings,
      );
    });
  }

  @override
  Future<MessageSyncThreadAfterResult> syncConversationAfter({
    required AppConversationReadRef conversation,
    String? afterServerSeq,
    int? limit,
  }) {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.messages.syncConversationAfter(
        core.SyncConversationAfterRequest(
          conversation: core.ConversationReadRef(
            conversationId: conversation.conversationId,
          ),
          afterServerSeq: afterServerSeq,
          limit: limit,
        ),
      );
      return MessageSyncThreadAfterResult(
        messages: result.messages
            .map(
              (message) =>
                  _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
            )
            .toList(),
        nextAfterServerSeq: result.nextAfterServerSeq,
        hasMore: result.hasMore,
        warnings: result.warnings,
      );
    });
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

MessageSyncStatus _messageSyncStatusFromCore(core.MessageSyncStatus value) {
  return switch (value) {
    core.MessageSyncStatus.idle => MessageSyncStatus.idle,
    core.MessageSyncStatus.changed => MessageSyncStatus.changed,
    core.MessageSyncStatus.recoveryRequired =>
      MessageSyncStatus.recoveryRequired,
    core.MessageSyncStatus.retryableFailure =>
      MessageSyncStatus.retryableFailure,
    core.MessageSyncStatus.authRevoked => MessageSyncStatus.authRevoked,
  };
}
