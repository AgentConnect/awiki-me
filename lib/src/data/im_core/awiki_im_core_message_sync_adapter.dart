import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_conversation_read_ref.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/ports/message_sync_core_port.dart';
import '../../application/remote_push_message_reference.dart';
import 'awiki_im_core_error_mapper.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreMessageSyncAdapter
    implements
        MessageSyncCorePort,
        ConversationMessageSyncCorePort,
        MessageReceiveCorePort {
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
  Future<MessageReceiveOutcome> receiveNow({
    int? limit,
    required String reason,
  }) async {
    try {
      return await _runtime.withCurrentClient((client) async {
        final result = await client.messages.receiveNow(
          core.MessageSyncRequest(reason: reason, limit: limit),
        );
        return MessageReceiveOutcome(
          status: _messageSyncStatusFromCore(result.status),
          complete: result.complete,
          eventsReceived: result.eventsReceived,
          pagesFetched: result.pagesFetched,
          messagesHydrated: result.messagesHydrated,
          duplicatesSkipped: result.duplicatesSkipped,
          olderHistoryExcluded: result.olderHistoryExcluded,
          errorCode: _nonEmpty(result.errorCode),
          warnings: List.unmodifiable(result.warnings),
        );
      });
    } on core.AwikiImCoreException catch (error) {
      throw const AwikiImCoreErrorMapper().messageSyncFailure(error);
    }
  }

  @override
  Future<MessageProcessingSession> openProcessingSession() =>
      _runtime.withCurrentClient((client) async {
        final ownerDid = (await client.identity.current()).did;
        return _AppMessageProcessingSession(
          await client.messages.openProcessingSession(),
          ownerDid,
          _mappers,
        );
      });

  @override
  Future<List<LocalIncomingMessage>> findLocalIncoming(
    Set<String> references,
  ) => _runtime.withCurrentClient((client) async {
    if (references.isEmpty) return const <LocalIncomingMessage>[];
    final ownerDid = (await client.identity.current()).did;
    final matched = <String>{};
    final found = <LocalIncomingMessage>[];
    String? cursor;
    do {
      final page = await client.messages.localIncomingRecovery(
        limit: 1000,
        cursor: cursor,
      );
      for (final value in page.items) {
        final candidates = _pushReferencesFromCore(value);
        if (!candidates.any(references.contains)) continue;
        final message = _mappers.chatMessageFromCore(value, ownerDid: ownerDid);
        if (message.isMine ||
            value.direction != core.MessageDirection.incoming) {
          throw StateError('message_sync_recovery_direction_invalid');
        }
        matched.addAll(candidates.where(references.contains));
        found.add(
          LocalIncomingMessage(
            message: message,
            opaqueMessageReferences: candidates,
          ),
        );
      }
      if (matched.containsAll(references) || !page.hasMore) break;
      if (page.nextCursor == null || page.nextCursor == cursor) {
        throw StateError('message_sync_recovery_cursor_invalid');
      }
      cursor = page.nextCursor;
    } while (true);
    return found;
  });

  @override
  Future<MessageSyncOutcome> syncNow({
    int? limit,
    required String reason,
  }) async {
    try {
      return await _runtime.withCurrentClient((client) async {
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
                opaqueMessageReferences: _pushReferencesFromCore(
                  committed.message,
                ),
              ),
            );
          }
          return MessageSyncOutcome(
            status: _messageSyncStatusFromCore(result.status),
            eventsApplied: result.eventsApplied,
            pagesFetched: result.pagesFetched,
            messagesHydrated: result.messagesHydrated,
            duplicatesSkipped: result.duplicatesSkipped,
            olderHistoryExcluded: result.olderHistoryExcluded,
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
    } on core.AwikiImCoreException catch (error) {
      throw const AwikiImCoreErrorMapper().messageSyncFailure(error);
    }
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
      try {
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
      } on core.AwikiImCoreException catch (error) {
        if (const AwikiImCoreErrorMapper()
            .map(error)
            .isDirectSyncBindingUnavailable) {
          throw const DirectMessageSyncBindingUnavailable();
        }
        rethrow;
      }
    });
  }
}

class _AppMessageProcessingSession implements MessageProcessingSession {
  _AppMessageProcessingSession(this._inner, this._ownerDid, this._mappers);
  final core.MessageProcessingSession _inner;
  final String _ownerDid;
  final AwikiImCoreMappers _mappers;

  List<CommittedIncomingMessage> _committed(
    List<core.CommittedIncomingMessage> values,
  ) => values
      .map((value) {
        final message = _mappers.chatMessageFromCore(
          value.message,
          ownerDid: _ownerDid,
        );
        if (value.source != core.CommittedMessageSource.liveDelta ||
            value.direction != core.MessageDirection.incoming ||
            value.eventId.trim().isEmpty ||
            value.logicalMessageId.trim().isEmpty ||
            message.isMine ||
            message.remoteId?.trim() != value.logicalMessageId) {
          throw StateError('message_sync_committed_event_invalid');
        }
        return CommittedIncomingMessage(
          eventId: value.eventId,
          logicalMessageId: value.logicalMessageId,
          message: message,
          opaqueMessageReferences: _pushReferencesFromCore(value.message),
        );
      })
      .toList(growable: false);

  @override
  Stream<MessageProcessingUpdate> get updates => _inner.updates.map(
    (value) => MessageProcessingUpdate(
      eventId: value.eventId,
      status: switch (value.status) {
        core.MessageProcessingStatus.applied => MessageProcessingStatus.applied,
        core.MessageProcessingStatus.retrying =>
          MessageProcessingStatus.retrying,
        core.MessageProcessingStatus.blocked => MessageProcessingStatus.blocked,
        core.MessageProcessingStatus.discarded =>
          MessageProcessingStatus.discarded,
        core.MessageProcessingStatus.resyncRequired =>
          MessageProcessingStatus.resyncRequired,
      },
      changedConversationIds: List.unmodifiable(value.changedConversationIds),
      committedIncomingMessages: _committed(value.committedIncomingMessages),
      errorCode: _nonEmpty(value.errorCode),
    ),
  );

  @override
  Future<MessageProcessingOutcome> waitUntilSettled() async {
    final value = await _inner.waitUntilSettled();
    return MessageProcessingOutcome(
      complete: value.complete,
      pendingCount: value.pendingCount,
      blockedCount: value.blockedCount,
      discardedCount: value.discardedCount,
      changedConversationIds: List.unmodifiable(value.changedConversationIds),
      committedIncomingMessages: _committed(value.committedIncomingMessages),
      errorCode: _nonEmpty(value.errorCode),
    );
  }

  @override
  Future<void> close() => _inner.close();
}

Set<String> _pushReferencesFromCore(core.Message message) {
  final ids = <String>{
    message.id,
    ...message.metadata.attributes
        .where((attribute) => attribute.key == 'raw_message_id')
        .map((attribute) => attribute.value),
  };
  final references = <String>{};
  for (final id in ids) {
    try {
      references.add(remotePushOpaqueMessageReference(id));
    } on ArgumentError {
      /* Not a Push identifier. */
    }
  }
  return references;
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
    core.MessageSyncStatus.blocked => MessageSyncStatus.blocked,
  };
}
