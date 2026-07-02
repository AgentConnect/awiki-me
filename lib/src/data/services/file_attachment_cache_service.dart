import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../application/attachment_cache_service.dart';
import '../im_core/awiki_im_core_paths.dart';

class FileAttachmentCacheService implements AttachmentCacheService {
  FileAttachmentCacheService({
    Future<Directory> Function()? rootDirectory,
    String? stateNamespace,
  }) : _rootDirectory =
           rootDirectory ??
           (() => _defaultRootDirectory(
             stateNamespace: normalizeAwikiStateNamespace(stateNamespace),
           ));

  final Future<Directory> Function() _rootDirectory;

  @override
  Future<String?> cacheLocalSource({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return null;
    }
    final destination = await _attachmentFile(
      messageId: messageId,
      attachmentId: attachmentId,
      filename: filename,
    );
    await destination.parent.create(recursive: true);
    await source.copy(destination.path);
    return destination.path;
  }

  @override
  Future<String> cacheDownloadedBytes({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final destination = await _attachmentFile(
      messageId: messageId,
      attachmentId: attachmentId,
      filename: filename,
    );
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes, flush: true);
    return destination.path;
  }

  @override
  Future<String?> lookup({
    required String messageId,
    required String attachmentId,
  }) async {
    final directory = await _attachmentDirectory(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    if (!await directory.exists()) {
      return null;
    }
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && await entity.exists()) {
        return entity.path;
      }
    }
    return null;
  }

  Future<File> _attachmentFile({
    required String messageId,
    required String attachmentId,
    required String filename,
  }) async {
    final directory = await _attachmentDirectory(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    return File('${directory.path}/${_safeFilename(filename)}');
  }

  Future<Directory> _attachmentDirectory({
    required String messageId,
    required String attachmentId,
  }) async {
    final root = await _rootDirectory();
    return Directory(
      '${root.path}/${_safePathSegment(messageId)}/${_safePathSegment(attachmentId)}',
    );
  }

  static Future<Directory> _defaultRootDirectory({
    required String stateNamespace,
  }) async {
    final e2eRoot = awikiE2eAppStateRoot();
    if (e2eRoot != null) {
      return Directory(
        '$e2eRoot/support/awiki-me/environments/$stateNamespace/attachments',
      );
    }
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}/awiki-me/environments/$stateNamespace/attachments',
    );
  }

  static String _safePathSegment(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'unknown' : safe;
  }

  static String _safeFilename(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[\/\\:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized == '..' ||
        normalized.startsWith('.')) {
      return 'attachment';
    }
    return normalized;
  }
}
