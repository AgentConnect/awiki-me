import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../../application/attachment_picker_service.dart';
import '../../application/models/attachment_models.dart';

typedef AttachmentProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef AttachmentTemporaryDirectoryProvider = Future<Directory> Function();
typedef AttachmentClipboardImageReader = Future<Uint8List?> Function();
typedef AttachmentClipboardFilesReader = Future<List<String>> Function();
typedef AttachmentPlatformFileSelector =
    Future<AttachmentPlatformFile?> Function();
typedef AttachmentPlatformFileSaver =
    Future<String?> Function({
      required String filename,
      required String mimeType,
      required Uint8List bytes,
    });
typedef AttachmentScreenCaptureRunner = Future<bool> Function(String imagePath);
typedef AttachmentScreenCaptureCanceler = Future<bool> Function();

const int defaultMaxAttachmentSizeBytes = 100 * 1024 * 1024;

class AttachmentPlatformFile {
  const AttachmentPlatformFile({
    required this.path,
    this.filename,
    this.mimeType,
    this.sizeBytes,
  });

  final String path;
  final String? filename;
  final String? mimeType;
  final int? sizeBytes;
}

class MethodChannelAttachmentPickerService implements AttachmentPickerService {
  MethodChannelAttachmentPickerService({
    MethodChannel? channel,
    bool? screenshotSupported,
    AttachmentProcessRunner? processRunner,
    AttachmentTemporaryDirectoryProvider? temporaryDirectoryProvider,
    AttachmentClipboardImageReader? clipboardImageReader,
    AttachmentClipboardFilesReader? clipboardFilesReader,
    bool? preferClipboardFiles,
    bool? windowsPlatform,
    AttachmentPlatformFileSelector? windowsFileSelector,
    AttachmentPlatformFileSaver? windowsFileSaver,
    AttachmentScreenCaptureRunner? windowsScreenCaptureRunner,
    AttachmentScreenCaptureCanceler? windowsScreenCaptureCanceler,
    AttachmentTemporaryDirectoryProvider? attachmentTemporaryDirectoryProvider,
    // Native Windows capture cancels at 120 seconds. Keep this watchdog later
    // so an ordinary native timeout cannot race the MethodChannel future.
    this.screenCaptureTimeout = const Duration(seconds: 125),
    this.maxAttachmentSizeBytes = defaultMaxAttachmentSizeBytes,
  }) : _channel =
           channel ?? const MethodChannel('ai.awiki.awikime/attachment_picker'),
       _windowsPlatform = windowsPlatform ?? Platform.isWindows,
       _screenshotSupported =
           screenshotSupported ?? (Platform.isMacOS || Platform.isWindows),
       _processRunner =
           processRunner ??
           ((executable, arguments) => Process.run(executable, arguments)),
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ??
           (() async => Directory(
             Platform.isWindows
                 ? p.join(Directory.systemTemp.path, 'AWikiMe', 'screenshots')
                 : p.join(Directory.systemTemp.path, 'awiki-screenshots'),
           )),
       _attachmentTemporaryDirectoryProvider =
           attachmentTemporaryDirectoryProvider ??
           (() async => Directory(
             Platform.isWindows
                 ? p.join(Directory.systemTemp.path, 'AWikiMe', 'attachments')
                 : p.join(Directory.systemTemp.path, 'awiki-attachments'),
           )),
       _clipboardImageReader = clipboardImageReader ?? (() => Pasteboard.image),
       _clipboardFilesReader = clipboardFilesReader ?? Pasteboard.files,
       _preferClipboardFiles = preferClipboardFiles ?? Platform.isMacOS,
       _windowsFileSelector = windowsFileSelector ?? _selectWindowsFile,
       _windowsFileSaver = windowsFileSaver ?? _saveWindowsFile,
       _windowsScreenCaptureRunner = windowsScreenCaptureRunner,
       _windowsScreenCaptureCanceler = windowsScreenCaptureCanceler {
    if (maxAttachmentSizeBytes <= 0) {
      throw ArgumentError.value(
        maxAttachmentSizeBytes,
        'maxAttachmentSizeBytes',
        'must be positive',
      );
    }
    if (screenCaptureTimeout <= Duration.zero) {
      throw ArgumentError.value(
        screenCaptureTimeout,
        'screenCaptureTimeout',
        'must be positive',
      );
    }
  }

  final MethodChannel _channel;
  final bool _windowsPlatform;
  final bool _screenshotSupported;
  final AttachmentProcessRunner _processRunner;
  final AttachmentTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final AttachmentTemporaryDirectoryProvider
  _attachmentTemporaryDirectoryProvider;
  final AttachmentClipboardImageReader _clipboardImageReader;
  final AttachmentClipboardFilesReader _clipboardFilesReader;
  final bool _preferClipboardFiles;
  final AttachmentPlatformFileSelector _windowsFileSelector;
  final AttachmentPlatformFileSaver _windowsFileSaver;
  final AttachmentScreenCaptureRunner? _windowsScreenCaptureRunner;
  final AttachmentScreenCaptureCanceler? _windowsScreenCaptureCanceler;
  final Duration screenCaptureTimeout;
  final int maxAttachmentSizeBytes;
  bool _screenCapturePermissionRequested = false;
  static const String _fallbackMimeType = 'application/octet-stream';

  @override
  Future<AttachmentDraft?> pickAttachment() async {
    if (_windowsPlatform) {
      try {
        final selected = await _windowsFileSelector();
        if (selected == null) {
          return null;
        }
        return draftFromExternalSource(
          path: selected.path,
          filename: selected.filename,
          mimeType: selected.mimeType,
          sizeBytes: selected.sizeBytes,
        );
      } on PlatformException catch (error) {
        throw StateError(
          _friendlyMessage(error, fallback: 'attachment_picker_failed'),
        );
      }
    }
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
      return draftFromExternalSource(
        filename: filename,
        mimeType: mimeType,
        path: path,
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
  Future<AttachmentDraft?> captureScreenshot({bool hideApp = false}) async {
    if (!_screenshotSupported) {
      return null;
    }
    if (_windowsPlatform) {
      return _captureWindowsScreenshot();
    }
    if (!await _ensureScreenCapturePermission()) {
      throw StateError('screenshot_screen_recording_permission_required');
    }
    final directory = await _temporaryDirectoryProvider();
    await directory.create(recursive: true);
    await _cleanupOldAttachmentTempFiles(directory);
    final filename = 'screenshot-${DateTime.now().microsecondsSinceEpoch}.png';
    final source = File(p.join(directory.path, filename));
    try {
      final result = await _processRunner('/usr/sbin/screencapture', <String>[
        '-i',
        '-x',
        source.path,
      ]);
      if (result.exitCode != 0 || !await source.exists()) {
        return null;
      }
      final sizeBytes = await source.length();
      if (sizeBytes <= 0) {
        return null;
      }
      return await draftFromExternalSource(
        path: source.path,
        filename: filename,
        mimeType: 'image/png',
        sizeBytes: sizeBytes,
      );
    } on ProcessException catch (error) {
      throw StateError('screenshot_capture_failed: ${error.errorCode}');
    } finally {
      try {
        if (await source.exists()) {
          await source.delete();
        }
      } catch (_) {
        // Best-effort source cleanup. The attachment copy has its own TTL.
      }
    }
  }

  Future<AttachmentDraft?> _captureWindowsScreenshot() async {
    final directory = await _temporaryDirectoryProvider();
    await directory.create(recursive: true);
    await _cleanupOldAttachmentTempFiles(directory);
    final filename = 'screenshot-${DateTime.now().microsecondsSinceEpoch}.png';
    final source = File(p.join(directory.path, filename));
    try {
      final captured = await _captureWindowsRegion(
        source.path,
      ).timeout(screenCaptureTimeout);
      if (!captured || !await source.exists()) {
        return null;
      }
      final sizeBytes = await source.length();
      if (sizeBytes <= 0) {
        return null;
      }
      return await draftFromExternalSource(
        path: source.path,
        filename: filename,
        mimeType: 'image/png',
        sizeBytes: sizeBytes,
      );
    } on TimeoutException {
      await _cancelWindowsRegionCapture();
      throw StateError('screenshot_capture_timeout');
    } on PlatformException catch (error) {
      throw StateError(switch (error.code) {
        'capture_invalid_path' ||
        'capture_busy' ||
        'capture_failed' => error.code,
        _ => 'screenshot_capture_failed',
      });
    } finally {
      try {
        if (await source.exists()) {
          await source.delete();
        }
      } catch (_) {
        // The staged attachment is independent from the capture source.
      }
    }
  }

  Future<bool> _captureWindowsRegion(String imagePath) {
    final runner = _windowsScreenCaptureRunner;
    if (runner != null) {
      return runner(imagePath);
    }
    return _channel
        .invokeMethod<bool>('captureRegion', <String, Object?>{
          'outputPath': imagePath,
        })
        .then((captured) => captured ?? false);
  }

  Future<void> _cancelWindowsRegionCapture() async {
    try {
      final canceler = _windowsScreenCaptureCanceler;
      if (canceler != null) {
        await canceler();
      } else {
        await _channel.invokeMethod<bool>('cancelCapture');
      }
    } on MissingPluginException {
      // Unit and non-Windows hosts may not install the native capture bridge.
    } on PlatformException {
      // The original timeout remains the user-visible failure.
    }
  }

  Future<bool> _ensureScreenCapturePermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>(
            'preflightScreenCapturePermission',
          ) ??
          false;
      if (granted) {
        return true;
      }
      if (_screenCapturePermissionRequested) {
        return false;
      }
      _screenCapturePermissionRequested = true;
      return await _channel.invokeMethod<bool>(
            'requestScreenCapturePermission',
          ) ??
          false;
    } on MissingPluginException {
      // Non-macOS/unit environments do not install the native permission
      // bridge. Screenshot support is injected explicitly in those tests.
      return true;
    } on PlatformException {
      return false;
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
      _validateAttachmentSize(bytes.length);
      return AttachmentDraft(
        filename: resolvedFilename,
        mimeType: resolvedMimeType,
        bytes: bytes,
        sizeBytes: bytes.length,
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
    _validateAttachmentSize(stat.size);
    final cachedPath = await _copyExternalFileToTemporaryDirectory(
      sourceFile: sourceFile,
      filename: resolvedFilename,
    );
    return AttachmentDraft(
      filename: resolvedFilename,
      mimeType: resolvedMimeType,
      localPath: cachedPath,
      sizeBytes: stat.size,
    );
  }

  @override
  Future<AttachmentDraft?> readClipboardAttachment() async {
    try {
      if (_preferClipboardFiles) {
        final fileDraft = await _firstClipboardFileDraft();
        if (fileDraft != null) {
          return fileDraft;
        }
      }
      final imageBytes = await _clipboardImageReader();
      if (imageBytes != null && imageBytes.isNotEmpty) {
        return draftFromExternalSource(
          filename: _pastedImageFilename(),
          mimeType: 'image/png',
          bytes: imageBytes,
          sizeBytes: imageBytes.length,
        );
      }
      if (!_preferClipboardFiles) {
        return _firstClipboardFileDraft();
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

  Future<AttachmentDraft?> _firstClipboardFileDraft() async {
    final files = await _clipboardFilesReader();
    for (final filePath in files) {
      final draft = await draftFromExternalSource(path: filePath);
      if (draft != null) {
        return draft;
      }
    }
    return null;
  }

  @override
  Future<String?> saveAttachment({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    _validateAttachmentSize(bytes.length);
    if (_windowsPlatform) {
      try {
        return _windowsFileSaver(
          filename: _sanitizedFileName(filename),
          mimeType: _resolvedMimeType(mimeType, filename),
          bytes: bytes,
        );
      } on PlatformException catch (error) {
        throw StateError(
          _friendlyMessage(error, fallback: 'attachment_save_failed'),
        );
      }
    }
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
    final directory = await _attachmentTemporaryDirectoryProvider();
    await directory.create(recursive: true);
    await _cleanupOldAttachmentTempFiles(directory);
    final safeName = _sanitizedFileName(filename);
    final destination = File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}-$safeName',
      ),
    );
    await destination.parent.create(recursive: true);
    return sourceFile.copy(destination.path).then((file) => file.path);
  }

  void _validateAttachmentSize(int sizeBytes) {
    if (sizeBytes <= 0) {
      throw StateError('attachment_size_invalid');
    }
    if (sizeBytes > maxAttachmentSizeBytes) {
      throw StateError('attachment_too_large');
    }
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

Future<AttachmentPlatformFile?> _selectWindowsFile() async {
  final selected = await openFile();
  if (selected == null) {
    return null;
  }
  return AttachmentPlatformFile(
    path: selected.path,
    filename: selected.name,
    mimeType: selected.mimeType,
    sizeBytes: await selected.length(),
  );
}

Future<String?> _saveWindowsFile({
  required String filename,
  required String mimeType,
  required Uint8List bytes,
}) async {
  final location = await getSaveLocation(suggestedName: filename);
  if (location == null) {
    return null;
  }
  final file = XFile.fromData(bytes, mimeType: mimeType, name: filename);
  await file.saveTo(location.path);
  return location.path;
}
