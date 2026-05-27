import 'dart:typed_data';

class AttachmentDraft {
  const AttachmentDraft({
    required this.filename,
    required this.mimeType,
    this.localPath,
    this.bytes,
    this.sizeBytes,
  }) : assert(
         localPath != null || bytes != null,
         'AttachmentDraft requires either localPath or bytes.',
       );

  final String filename;
  final String mimeType;
  final String? localPath;
  final Uint8List? bytes;
  final int? sizeBytes;

  String get displayName {
    final value = filename.trim();
    return value.isEmpty ? '附件' : value;
  }
}

class AttachmentDownloadResult {
  const AttachmentDownloadResult({
    required this.attachmentId,
    this.filename,
    this.mimeType,
    this.sizeBytes,
    this.localPath,
    this.bytes,
    this.warnings = const <String>[],
  });

  final String attachmentId;
  final String? filename;
  final String? mimeType;
  final int? sizeBytes;
  final String? localPath;
  final Uint8List? bytes;
  final List<String> warnings;
}
