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

  Future<String?> lookup({
    required String messageId,
    required String attachmentId,
  });
}
