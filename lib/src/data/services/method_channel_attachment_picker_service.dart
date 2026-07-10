import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../../application/attachment_picker_service.dart';
import '../../application/models/attachment_models.dart';

class MethodChannelAttachmentPickerService implements AttachmentPickerService {
  MethodChannelAttachmentPickerService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('ai.awiki.awikime/attachment_picker');

  final MethodChannel _channel;
  static const String _fallbackMimeType = 'application/octet-stream';

  @override
  Future<AttachmentDraft?> pickAttachment() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickAttachment',
      );
      if (result == null) {
        return null;
      }
      final filename = _readString(result, 'filename') ?? '';
      final mimeType =
          _readString(result, 'mime_type') ?? 'application/octet-stream';
      final path = _readString(result, 'path');
      final bytes = _readBytes(result['bytes']);
      final sizeBytes =
          _readInt(result, 'size_bytes') ??
          bytes?.length ??
          _fileSizeIfAvailable(path);
      if ((path == null || path.isEmpty) && bytes == null) {
        throw StateError('attachment_picker_empty_result');
      }
      return AttachmentDraft(
        filename: filename,
        mimeType: mimeType,
        localPath: path,
        bytes: bytes,
        sizeBytes: sizeBytes,
      );
    } on PlatformException catch (error) {
      throw StateError(
        _friendlyMessage(error, fallback: 'attachment_picker_failed'),
      );
    }
  }

  @override
  Future<AttachmentDraft?> draftFromExternalSource({
    String? path,
    String? filename,
    String? mimeType,
    int? sizeBytes,
    Uint8List? bytes,
  }) async {
    final trimmedPath = _trimToNull(path);
    final resolvedFilename = _resolvedFilename(
      explicitFilename: filename,
      path: trimmedPath,
      mimeType: mimeType,
    );
    final resolvedMimeType = _resolvedMimeType(mimeType, resolvedFilename);
    if (bytes != null) {
      return AttachmentDraft(
        filename: resolvedFilename,
        mimeType: resolvedMimeType,
        bytes: bytes,
        sizeBytes: sizeBytes ?? bytes.length,
      );
    }
    if (trimmedPath == null) {
      return null;
    }
    final sourceFile = File(trimmedPath);
    final stat = await sourceFile.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }
    final cachedPath = await _copyExternalFileToTemporaryDirectory(
      sourceFile: sourceFile,
      filename: resolvedFilename,
    );
    return AttachmentDraft(
      filename: resolvedFilename,
      mimeType: resolvedMimeType,
      localPath: cachedPath,
      sizeBytes: sizeBytes ?? await File(cachedPath).length(),
    );
  }

  @override
  Future<AttachmentDraft?> readClipboardAttachment() async {
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        return draftFromExternalSource(
          filename: _pastedImageFilename(),
          mimeType: 'image/png',
          bytes: imageBytes,
          sizeBytes: imageBytes.length,
        );
      }
      final files = await Pasteboard.files();
      for (final filePath in files) {
        final draft = await draftFromExternalSource(path: filePath);
        if (draft != null) {
          return draft;
        }
      }
      return null;
    } on PlatformException catch (error) {
      throw StateError(
        _friendlyMessage(error, fallback: 'attachment_picker_failed'),
      );
    } on UnimplementedError {
      return null;
    } on UnsupportedError {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> saveAttachment({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    try {
      return _channel.invokeMethod<String>('saveAttachment', <String, Object?>{
        'filename': filename,
        'mime_type': mimeType,
        'bytes': bytes,
      });
    } on PlatformException catch (error) {
      throw StateError(
        _friendlyMessage(error, fallback: 'attachment_save_failed'),
      );
    }
  }

  String? _readString(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _readInt(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return null;
  }

  Uint8List? _readBytes(Object? raw) {
    if (raw is Uint8List) {
      return raw;
    }
    if (raw is List) {
      return Uint8List.fromList(raw.whereType<int>().toList());
    }
    return null;
  }

  int? _fileSizeIfAvailable(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    try {
      return File(path).lengthSync();
    } catch (_) {
      return null;
    }
  }

  Future<String> _copyExternalFileToTemporaryDirectory({
    required File sourceFile,
    required String filename,
  }) async {
    final directory = Directory(
      p.join(Directory.systemTemp.path, 'awiki-attachments'),
    );
    await directory.create(recursive: true);
    await _cleanupOldAttachmentTempFiles(directory);
    final safeName = _sanitizedFileName(filename);
    final destination = File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}-$safeName',
      ),
    );
    return sourceFile.copy(destination.path).then((file) => file.path);
  }

  Future<void> _cleanupOldAttachmentTempFiles(Directory directory) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    await for (final entity in directory.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } catch (_) {
        // Best-effort cleanup must not block attachment staging.
      }
    }
  }

  String _resolvedFilename({
    required String? explicitFilename,
    required String? path,
    required String? mimeType,
  }) {
    final explicit = _trimToNull(explicitFilename);
    if (explicit != null) {
      return _sanitizedFileName(explicit);
    }
    if (path != null) {
      final basename = _trimToNull(p.basename(path));
      if (basename != null) {
        return _sanitizedFileName(basename);
      }
    }
    if (mimeType?.trim().toLowerCase().startsWith('image/') == true) {
      return _pastedImageFilename();
    }
    return 'attachment';
  }

  String _resolvedMimeType(String? mimeType, String filename) {
    final explicit = _trimToNull(mimeType);
    if (explicit != null) {
      return explicit;
    }
    return _mimeTypeForFilename(filename);
  }

  String _mimeTypeForFilename(String filename) {
    switch (p.extension(filename).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
        return 'text/plain';
      case '.md':
      case '.markdown':
        return 'text/markdown';
      case '.json':
        return 'application/json';
      case '.csv':
        return 'text/csv';
      case '.zip':
        return 'application/zip';
      default:
        return _fallbackMimeType;
    }
  }

  String _pastedImageFilename() {
    return 'pasted-image-${DateTime.now().microsecondsSinceEpoch}.png';
  }

  String _sanitizedFileName(String value) {
    final replaced = value
        .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), '_')
        .trim();
    if (replaced.isEmpty) {
      return 'attachment';
    }
    if (replaced.length <= 160) {
      return replaced;
    }
    final extension = p.extension(replaced);
    final keep = 160 - extension.length;
    if (keep <= 0) {
      return replaced.substring(0, 160);
    }
    return '${replaced.substring(0, keep)}$extension';
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _friendlyMessage(PlatformException error, {required String fallback}) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return fallback;
  }
}
