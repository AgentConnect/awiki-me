import '../domain/entities/chat_attachment.dart';

final class AttachmentImageDimensions {
  factory AttachmentImageDimensions({
    required int pixelWidth,
    required int pixelHeight,
  }) {
    if (pixelWidth <= 0) {
      throw ArgumentError.value(pixelWidth, 'pixelWidth', 'must be positive');
    }
    if (pixelHeight <= 0) {
      throw ArgumentError.value(pixelHeight, 'pixelHeight', 'must be positive');
    }
    return AttachmentImageDimensions._(
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
  }

  const AttachmentImageDimensions._({
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final int pixelWidth;
  final int pixelHeight;

  double get aspectRatio => pixelWidth / pixelHeight;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AttachmentImageDimensions &&
            other.pixelWidth == pixelWidth &&
            other.pixelHeight == pixelHeight;
  }

  @override
  int get hashCode => Object.hash(pixelWidth, pixelHeight);

  @override
  String toString() => 'AttachmentImageDimensions($pixelWidth x $pixelHeight)';
}

abstract interface class AttachmentImageDimensionProbe {
  Future<AttachmentImageDimensions?> probe(String localPath);
}

final class NoopAttachmentImageDimensionProbe
    implements AttachmentImageDimensionProbe {
  const NoopAttachmentImageDimensionProbe();

  @override
  Future<AttachmentImageDimensions?> probe(String localPath) {
    return Future<AttachmentImageDimensions?>.value();
  }
}

bool isSupportedAttachmentPreviewImage(ChatAttachment attachment) {
  final normalizedMimeType = attachment.mimeType.trim().toLowerCase();
  if (<String>{
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif',
    'image/webp',
  }.contains(normalizedMimeType)) {
    return true;
  }
  if (normalizedMimeType.isNotEmpty &&
      normalizedMimeType != 'application/octet-stream') {
    return false;
  }
  final normalizedFilename = attachment.filename.trim().toLowerCase();
  return <String>[
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
  ].any(normalizedFilename.endsWith);
}
