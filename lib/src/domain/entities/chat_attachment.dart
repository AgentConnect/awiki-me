class ChatAttachment {
  const ChatAttachment({
    required this.attachmentId,
    required this.filename,
    required this.mimeType,
    this.sizeBytes,
    this.caption,
    this.objectUri,
    this.localPath,
    this.hasLocalSource = false,
  });

  final String attachmentId;
  final String filename;
  final String mimeType;
  final int? sizeBytes;
  final String? caption;
  final String? objectUri;
  final String? localPath;
  final bool hasLocalSource;

  String get displayName {
    final value = filename.trim();
    return value;
  }

  ChatAttachment copyWith({
    String? attachmentId,
    String? filename,
    String? mimeType,
    int? sizeBytes,
    String? caption,
    String? objectUri,
    String? localPath,
    bool? hasLocalSource,
  }) {
    return ChatAttachment(
      attachmentId: attachmentId ?? this.attachmentId,
      filename: filename ?? this.filename,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      caption: caption ?? this.caption,
      objectUri: objectUri ?? this.objectUri,
      localPath: localPath ?? this.localPath,
      hasLocalSource: hasLocalSource ?? this.hasLocalSource,
    );
  }
}
