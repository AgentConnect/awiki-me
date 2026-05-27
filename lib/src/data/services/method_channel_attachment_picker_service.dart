import 'dart:io';

import 'package:flutter/services.dart';

import '../../application/attachment_picker_service.dart';
import '../../application/models/attachment_models.dart';

class MethodChannelAttachmentPickerService implements AttachmentPickerService {
  MethodChannelAttachmentPickerService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('ai.awiki.awikime/attachment_picker');

  final MethodChannel _channel;

  @override
  Future<AttachmentDraft?> pickAttachment() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickAttachment',
      );
      if (result == null) {
        return null;
      }
      final filename = _readString(result, 'filename') ?? '附件';
      final mimeType =
          _readString(result, 'mime_type') ?? 'application/octet-stream';
      final path = _readString(result, 'path');
      final bytes = _readBytes(result['bytes']);
      final sizeBytes =
          _readInt(result, 'size_bytes') ??
          bytes?.length ??
          _fileSizeIfAvailable(path);
      if ((path == null || path.isEmpty) && bytes == null) {
        throw StateError('未能读取所选文件。');
      }
      return AttachmentDraft(
        filename: filename,
        mimeType: mimeType,
        localPath: path,
        bytes: bytes,
        sizeBytes: sizeBytes,
      );
    } on PlatformException catch (error) {
      throw StateError(_friendlyMessage(error, fallback: '文件选择失败，请稍后重试。'));
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
      throw StateError(_friendlyMessage(error, fallback: '文件保存失败，请稍后重试。'));
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

  String _friendlyMessage(PlatformException error, {required String fallback}) {
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return fallback;
  }
}
