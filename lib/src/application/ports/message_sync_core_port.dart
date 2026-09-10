import '../../domain/entities/chat_message.dart';
import '../models/app_conversation_read_ref.dart';
import '../models/app_thread_ref.dart';
import '../models/message_sync_diagnostics.dart';

abstract interface class MessageSyncCorePort {
  Future<MessageSyncOutcome> syncNow({int? limit, required String reason});

  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  });
}

abstract interface class MessageReceiveCorePort {
  Future<MessageReceiveOutcome> receiveNow({
    int? limit,
    required String reason,
  });
  Future<MessageProcessingSession> openProcessingSession();
  Future<List<LocalIncomingMessage>> findLocalIncoming(Set<String> references);
}

class MessageReceiveOutcome {
  const MessageReceiveOutcome({
    required this.status,
    required this.complete,
    required this.eventsReceived,
    required this.pagesFetched,
    this.messagesHydrated = 0,
    this.duplicatesSkipped = 0,
    this.olderHistoryExcluded = false,
    this.errorCode,
    this.warnings = const [],
  });
  final MessageSyncStatus status;
  final bool complete;
  final int eventsReceived;
  final int pagesFetched;
  final int messagesHydrated;
  final int duplicatesSkipped;
  final bool olderHistoryExcluded;
  final String? errorCode;
  final List<String> warnings;
}

enum MessageProcessingStatus {
  applied,
  retrying,
  blocked,
  discarded,
  resyncRequired,
}

class MessageProcessingUpdate {
  const MessageProcessingUpdate({
    required this.eventId,
    required this.status,
    this.changedConversationIds = const [],
    this.committedIncomingMessages = const [],
    this.errorCode,
  });
  final String eventId;
  final MessageProcessingStatus status;
  final List<String> changedConversationIds;
  final List<CommittedIncomingMessage> committedIncomingMessages;
  final String? errorCode;
}

class MessageProcessingOutcome {
  const MessageProcessingOutcome({
    required this.complete,
    required this.pendingCount,
    required this.blockedCount,
    required this.discardedCount,
    this.changedConversationIds = const [],
    this.committedIncomingMessages = const [],
    this.recoveredIncomingMessages = const [],
    this.errorCode,
  });
  final bool complete;
  final int pendingCount;
  final int blockedCount;
  final int discardedCount;
  final List<String> changedConversationIds;
  final List<CommittedIncomingMessage> committedIncomingMessages;
  final List<LocalIncomingMessage> recoveredIncomingMessages;
  final String? errorCode;
}

abstract interface class MessageProcessingSession {
  Stream<MessageProcessingUpdate> get updates;
  Future<MessageProcessingOutcome> waitUntilSettled();
  Future<void> close();
}

abstract interface class ConversationMessageSyncCorePort {
  Future<MessageSyncThreadAfterResult> syncConversationAfter({
    required AppConversationReadRef conversation,
    String? afterServerSeq,
    int? limit,
  });
}

/// Core has not yet observed an authoritative service event that binds this
/// Direct conversation to a durable remote thread.
///
/// This is an expected state for an empty conversation on a newly joined
/// tail-only device. Callers must not derive or persist a binding from a DID,
/// Handle, or presentation route.
class DirectMessageSyncBindingUnavailable implements Exception {
  const DirectMessageSyncBindingUnavailable();

  @override
  String toString() => 'DirectMessageSyncBindingUnavailable';
}

/// Payload-free failure projected by the Core adapter for App orchestration.
class MessageSyncCoreFailure implements Exception {
  const MessageSyncCoreFailure({
    required this.category,
    required this.code,
    this.httpStatus,
  });

  final AppMessageSyncFailureCategory category;
  final String code;
  final int? httpStatus;

  @override
  String toString() => code;
}

enum MessageSyncStatus {
  idle,
  changed,
  recoveryRequired,
  retryableFailure,
  authRevoked,
  blocked,
}

class CommittedIncomingMessage {
  const CommittedIncomingMessage({
    required this.eventId,
    required this.logicalMessageId,
    required this.message,
    this.opaqueMessageReferences = const {},
  });

  final String eventId;
  final String logicalMessageId;
  final ChatMessage message;
  final Set<String> opaqueMessageReferences;
}

/// Already committed Core facts used to correlate a Push after restart/replay.
class LocalIncomingMessage {
  const LocalIncomingMessage({
    required this.message,
    required this.opaqueMessageReferences,
  });
  final ChatMessage message;
  final Set<String> opaqueMessageReferences;
}

class MessageSyncOutcome {
  const MessageSyncOutcome({
    required this.status,
    required this.eventsApplied,
    required this.pagesFetched,
    this.messagesHydrated = 0,
    this.duplicatesSkipped = 0,
    this.olderHistoryExcluded = false,
    this.changedConversationIds = const <String>[],
    this.committedIncomingMessages = const <CommittedIncomingMessage>[],
    this.errorCode,
    this.warnings = const <String>[],
  });

  final MessageSyncStatus status;
  final int eventsApplied;
  final int pagesFetched;
  final int messagesHydrated;
  final int duplicatesSkipped;
  final bool olderHistoryExcluded;
  final List<String> changedConversationIds;
  final List<CommittedIncomingMessage> committedIncomingMessages;
  final String? errorCode;
  final List<String> warnings;

  bool get recoveryRequired => status == MessageSyncStatus.recoveryRequired;
  bool get changed => status == MessageSyncStatus.changed;
}

class MessageSyncThreadAfterResult {
  const MessageSyncThreadAfterResult({
    required this.messages,
    this.nextAfterServerSeq,
    required this.hasMore,
    this.warnings = const <String>[],
  });

  final List<ChatMessage> messages;
  final String? nextAfterServerSeq;
  final bool hasMore;
  final List<String> warnings;
}
