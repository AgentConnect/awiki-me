import '../models/common.dart';
import '../models/message_models.dart';
import 'message_api.dart';

abstract class ImOutboxApi {
  Future<ImPage<ImOutboxItemDto>> list(ImListOutboxRequest request);
  Future<ImSendResultDto> retry(String outboxId);
  Future<void> drop(String outboxId);
}

class ImListOutboxRequest {
  const ImListOutboxRequest({
    this.limit = 50,
    this.cursor,
    this.failedOnly = false,
  });

  final int limit;
  final String? cursor;
  final bool failedOnly;
}

class ImOutboxItemDto {
  const ImOutboxItemDto({
    required this.outboxId,
    required this.target,
    this.visibleMessage,
    required this.state,
    required this.attemptCount,
    this.lastErrorCode,
    this.retryHint,
    required this.createdAt,
    this.lastAttemptAt,
  });

  final String outboxId;
  final ImSendTarget target;
  final ImMessageDto? visibleMessage;
  final ImSendState state;
  final int attemptCount;
  final String? lastErrorCode;
  final String? retryHint;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;

  ImOutboxItemDto copyWith({
    ImSendState? state,
    int? attemptCount,
    String? lastErrorCode,
    String? retryHint,
    DateTime? lastAttemptAt,
  }) {
    return ImOutboxItemDto(
      outboxId: outboxId,
      target: target,
      visibleMessage: visibleMessage,
      state: state ?? this.state,
      attemptCount: attemptCount ?? this.attemptCount,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      retryHint: retryHint ?? this.retryHint,
      createdAt: createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }
}
