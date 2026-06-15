import 'dart:io';

import '../domain/entities/chat_message.dart';
import 'attachment_cache_service.dart';
import 'models/attachment_models.dart';

class AttachmentPreviewService {
  const AttachmentPreviewService({required this.cache});

  Future<String> previewPathFor({
    required ChatMessage message,
    required Future<AttachmentDownloadResult> Function() download,
  }) async {
    final attachment = message.attachment;
    if (attachment == null) {
      throw const AttachmentUnavailableException();
    }

    final localPath = await availableAttachmentPath(attachment.localPath);
    if (localPath != null) {
      return localPath;
    }

    final messageId = _stableMessageId(message);
    final cachedPath = await cache.lookup(
      messageId: messageId,
      attachmentId: attachment.attachmentId,
    );
    final availableCachedPath = await availableAttachmentPath(cachedPath);
    if (availableCachedPath != null) {
      return availableCachedPath;
    }

    final result = await download();
    final downloadedPath = await availableAttachmentPath(result.localPath);
    if (downloadedPath != null) {
      return downloadedPath;
    }

    final bytes = result.bytes;
    if (bytes == null) {
      throw const AttachmentUnavailableException();
    }
    return cache.cacheDownloadedBytes(
      messageId: messageId,
      attachmentId: attachment.attachmentId,
      filename: result.filename ?? attachment.filename,
      mimeType: result.mimeType ?? attachment.mimeType,
      bytes: bytes,
    );
  }

  final AttachmentCacheService cache;

  static Future<String?> availableAttachmentPath(String? pathOrUri) async {
    final value = pathOrUri?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme && parsed.scheme != 'file') {
      return value;
    }
    final file = parsed != null && parsed.scheme == 'file'
        ? File.fromUri(parsed)
        : File(value);
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  String _stableMessageId(ChatMessage message) {
    final remoteId = message.remoteId?.trim();
    if (remoteId != null && remoteId.isNotEmpty) {
      return remoteId;
    }
    return message.localId.trim();
  }
}

class AttachmentUnavailableException implements Exception {
  const AttachmentUnavailableException();

  @override
  String toString() => 'AttachmentUnavailableException';
}
