import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../application/attachment_cache_service.dart';

class FileAttachmentCacheService implements AttachmentCacheService {
  FileAttachmentCacheService({
    required Future<Directory> Function() rootDirectory,
  }) : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  static const String _transientPrefix = '._awiki_cache_';
  static int _nextTransactionId = 0;

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
    final directory = await _attachmentDirectory(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    await directory.create(recursive: true);
    final staging = _newTransientFile(directory, kind: 'staging');
    try {
      await source.copy(staging.path);
      return _commitStagedFile(
        directory: directory,
        staging: staging,
        filename: filename,
        isCurrent: () => true,
      );
    } catch (_) {
      _deleteFileBestEffort(staging);
      rethrow;
    }
  }

  @override
  Future<String> cacheDownloadedBytes({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final path = await cacheDownloadedBytesIfCurrent(
      messageId: messageId,
      attachmentId: attachmentId,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
      isCurrent: () => true,
    );
    if (path == null) {
      throw StateError('Unconditional attachment cache commit was rejected.');
    }
    return path;
  }

  @override
  Future<String?> cacheDownloadedBytesIfCurrent({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    required bool Function() isCurrent,
  }) async {
    final directory = await _attachmentDirectory(
      messageId: messageId,
      attachmentId: attachmentId,
    );
    await directory.create(recursive: true);
    final staging = _newTransientFile(directory, kind: 'staging');
    try {
      await staging.writeAsBytes(bytes, flush: true);
      return _commitStagedFile(
        directory: directory,
        staging: staging,
        filename: filename,
        isCurrent: isCurrent,
      );
    } catch (_) {
      _deleteFileBestEffort(staging);
      rethrow;
    }
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
      if (entity is File &&
          !_isTransientFile(entity) &&
          await entity.exists()) {
        return entity.path;
      }
    }
    return null;
  }

  String? _commitStagedFile({
    required Directory directory,
    required File staging,
    required String filename,
    required bool Function() isCurrent,
  }) {
    if (!isCurrent()) {
      _deleteFileBestEffort(staging);
      return null;
    }

    final destination = File(p.join(directory.path, _safeFilename(filename)));
    final committedFiles = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) => !_isTransientFile(file))
        .toList(growable: false);
    final backups = <_CacheBackup>[];
    try {
      for (var index = 0; index < committedFiles.length; index += 1) {
        final committed = committedFiles[index];
        final backup = _newTransientFile(directory, kind: 'backup-$index');
        committed.renameSync(backup.path);
        backups.add(_CacheBackup(originalPath: committed.path, backup: backup));
      }
      staging.renameSync(destination.path);
    } catch (_) {
      _restoreBackups(backups);
      _deleteFileBestEffort(staging);
      rethrow;
    }

    for (final backup in backups) {
      _deleteFileBestEffort(backup.backup);
    }
    return destination.path;
  }

  static File _newTransientFile(Directory directory, {required String kind}) {
    final transactionId = _nextTransactionId++;
    final token =
        '${DateTime.now().microsecondsSinceEpoch}-$pid-$transactionId';
    return File(p.join(directory.path, '$_transientPrefix$kind-$token'));
  }

  static bool _isTransientFile(File file) {
    return p.basename(file.path).startsWith(_transientPrefix);
  }

  static void _restoreBackups(List<_CacheBackup> backups) {
    for (final backup in backups.reversed) {
      try {
        if (!backup.backup.existsSync()) {
          continue;
        }
        final original = File(backup.originalPath);
        if (original.existsSync()) {
          backup.backup.deleteSync();
        } else {
          backup.backup.renameSync(original.path);
        }
      } catch (_) {
        // Preserve the original commit error. A leftover backup remains hidden
        // from lookup and cannot displace a later committed file.
      }
    }
  }

  static void _deleteFileBestEffort(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {
      // Transient files are ignored by lookup, so cleanup failure is harmless.
    }
  }

  Future<Directory> _attachmentDirectory({
    required String messageId,
    required String attachmentId,
  }) async {
    final root = await _rootDirectory();
    return Directory(
      p.join(
        root.path,
        _safePathSegment(messageId),
        _safePathSegment(attachmentId),
      ),
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

class _CacheBackup {
  const _CacheBackup({required this.originalPath, required this.backup});

  final String originalPath;
  final File backup;
}
