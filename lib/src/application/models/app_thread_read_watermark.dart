class AppThreadReadWatermark {
  const AppThreadReadWatermark({
    this.lastReadMessageId,
    this.lastReadThreadSeq,
    this.readAt,
  });

  final String? lastReadMessageId;
  final String? lastReadThreadSeq;
  final DateTime? readAt;

  bool get isEmpty =>
      (lastReadMessageId == null || lastReadMessageId!.trim().isEmpty) &&
      (lastReadThreadSeq == null || lastReadThreadSeq!.trim().isEmpty) &&
      readAt == null;
}

class AppConversationReadCommitResult {
  const AppConversationReadCommitResult({
    required this.updatedCount,
    required this.remoteAcknowledged,
    required this.partial,
    required this.fallbackUsed,
    required this.pendingRemoteAck,
    required this.effectiveWatermark,
    this.warnings = const <String>[],
  });

  final int updatedCount;
  final bool remoteAcknowledged;
  final bool partial;
  final bool fallbackUsed;
  final bool pendingRemoteAck;
  final AppThreadReadWatermark? effectiveWatermark;
  final List<String> warnings;

  factory AppConversationReadCommitResult.acknowledged(
    AppThreadReadWatermark? watermark,
  ) {
    return AppConversationReadCommitResult(
      updatedCount: 1,
      remoteAcknowledged: true,
      partial: false,
      fallbackUsed: false,
      pendingRemoteAck: false,
      effectiveWatermark: watermark,
    );
  }
}
