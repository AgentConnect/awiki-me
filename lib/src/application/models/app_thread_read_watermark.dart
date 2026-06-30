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
