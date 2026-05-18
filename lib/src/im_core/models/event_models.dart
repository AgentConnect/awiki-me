import 'client_models.dart';
import 'error_models.dart';
import 'group_models.dart';
import 'message_models.dart';
import '../apis/outbox_api.dart';

enum ImEventKind {
  messageReceived,
  messageUpdated,
  conversationUpdated,
  groupUpdated,
  outboxUpdated,
  connectionChanged,
  syncCompleted,
  warning,
  error,
}

class ImEventDto {
  const ImEventDto({
    required this.eventId,
    required this.kind,
    required this.occurredAt,
    this.message,
    this.conversation,
    this.group,
    this.outboxItem,
    this.connectionState,
    this.warning,
    this.error,
    this.metadata = const <String, Object?>{},
  });

  final String eventId;
  final ImEventKind kind;
  final DateTime occurredAt;
  final ImMessageDto? message;
  final ImConversationDto? conversation;
  final ImGroupDto? group;
  final ImOutboxItemDto? outboxItem;
  final ImConnectionStateDto? connectionState;
  final ImWarningDto? warning;
  final ImErrorDto? error;
  final Map<String, Object?> metadata;
}
