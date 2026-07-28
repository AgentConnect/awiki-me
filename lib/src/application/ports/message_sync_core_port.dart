import '../../domain/entities/chat_message.dart';
import '../models/app_conversation_read_ref.dart';
import '../models/app_thread_ref.dart';

abstract interface class MessageSyncCorePort {
  Future<MessageSyncOutcome> syncNow({int? limit, required String reason});

  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  });
}

abstract interface class ConversationMessageSyncCorePort {
  Future<MessageSyncThreadAfterResult> syncConversationAfter({
    required AppConversationReadRef conversation,
    String? afterServerSeq,
    int? limit,
  });
}

enum MessageSyncStatus {
  idle,
  changed,
  recoveryRequired,
  retryableFailure,
  authRevoked,
}

class CommittedIncomingMessage {
  const CommittedIncomingMessage({
    required this.eventId,
    required this.logicalMessageId,
    required this.message,
  });

  final String eventId;
  final String logicalMessageId;
  final ChatMessage message;
}

class MessageSyncOutcome {
  const MessageSyncOutcome({
    required this.status,
    required this.eventsApplied,
    required this.pagesFetched,
    this.messagesHydrated = 0,
    this.duplicatesSkipped = 0,
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
