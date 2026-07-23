import 'dart:typed_data';

abstract interface class AttachmentCacheService {
  Future<String?> cacheLocalSource({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required String sourcePath,
  });

  Future<String> cacheDownloadedBytes({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  });

  /// Stages [bytes] and commits them only when [isCurrent] still returns true.
  ///
  /// The callback is invoked synchronously immediately before the cache makes
  /// the staged file authoritative. A null result means the staged write was
  /// discarded because the caller's generation is no longer current.
  Future<String?> cacheDownloadedBytesIfCurrent({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    required bool Function() isCurrent,
  });

  Future<String?> lookup({
    required String messageId,
    required String attachmentId,
  });
}
