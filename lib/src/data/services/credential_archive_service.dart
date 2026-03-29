import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/session_identity.dart';

class CredentialArchiveService {
  static const String bundleVersion = '1';

  List<int> buildZip({
    required Map<String, Object?> manifest,
    required Directory credentialDirectory,
  }) {
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode(manifest),
      ),
    );
    for (final entity in credentialDirectory.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relativePath = entity.path.substring(
        credentialDirectory.path.length + 1,
      );
      archive.addFile(
        ArchiveFile(
          'credential/${_normalizeArchivePath(relativePath)}',
          entity.lengthSync(),
          entity.readAsBytesSync(),
        ),
      );
    }
    return ZipEncoder().encode(archive) ?? <int>[];
  }

  Map<String, Object?> buildManifest({
    required Map<String, Object?> indexEntry,
    required String credentialName,
    required SessionIdentity session,
    DateTime? exportedAt,
  }) {
    final exportTime = exportedAt ?? DateTime.now();
    return <String, Object?>{
      'bundle_version': bundleVersion,
      'credential_name': credentialName,
      'dir_name': indexEntry['dir_name']?.toString() ?? '',
      'did': indexEntry['did']?.toString() ?? session.did,
      'unique_id': indexEntry['unique_id']?.toString() ?? '',
      'display_name': indexEntry['name']?.toString() ?? session.displayName,
      'handle': indexEntry['handle']?.toString() ?? session.handle,
      'created_at': indexEntry['created_at']?.toString() ?? '',
      'exported_at': exportTime.toIso8601String(),
    };
  }

  String buildExportFileName({
    required SessionIdentity session,
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    final formatter = DateFormat('yyyyMMddHHmmss');
    final usernameShort = _sanitizeFileNameComponent(
      session.handle?.trim().isNotEmpty == true
          ? session.handle!
          : session.displayName.trim().isNotEmpty
              ? session.displayName
              : session.credentialName,
      maxLength: 12,
    );
    final credentialName = _sanitizeFileNameComponent(
      session.credentialName,
      maxLength: 32,
    );
    return 'awiki-credential-'
        '$usernameShort-$credentialName-${formatter.format(time)}.zip';
  }

  ImportedCredentialBundle unpackZip({
    required List<int> bytes,
    required Directory destinationRoot,
  }) {
    final decoded = ZipDecoder().decodeBytes(bytes, verify: true);
    Map<String, Object?>? manifest;
    Directory? credentialDirectory;
    for (final entry in decoded) {
      final normalizedPath = _normalizeArchivePath(entry.name);
      if (normalizedPath.isEmpty) {
        continue;
      }
      if (entry.isSymbolicLink) {
        throw const FormatException('ZIP 包不支持符号链接。');
      }
      if (normalizedPath == 'manifest.json') {
        final manifestRaw = utf8.decode(entry.content as List<int>);
        final parsed = jsonDecode(manifestRaw);
        if (parsed is! Map) {
          throw const FormatException('manifest.json 格式不正确。');
        }
        manifest = parsed.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        continue;
      }
      if (!normalizedPath.startsWith('credential/')) {
        continue;
      }
      if (!entry.isFile) {
        continue;
      }
      credentialDirectory ??= Directory(
          '${destinationRoot.path}${Platform.pathSeparator}credential');
      final targetFile = File(
        '${credentialDirectory.path}${Platform.pathSeparator}'
        '${normalizedPath.substring('credential/'.length)}',
      );
      targetFile.parent.createSync(recursive: true);
      final content = entry.content;
      if (content is! List<int>) {
        throw const FormatException('ZIP 包内容损坏。');
      }
      targetFile.writeAsBytesSync(content);
    }
    if (manifest == null) {
      throw const FormatException('ZIP 包缺少 manifest.json。');
    }
    if (credentialDirectory == null || !credentialDirectory.existsSync()) {
      throw const FormatException('ZIP 包缺少 credential 目录。');
    }
    _validateRequiredFiles(credentialDirectory);
    return ImportedCredentialBundle(
      manifest: manifest,
      credentialDirectory: credentialDirectory,
    );
  }

  static void _validateRequiredFiles(Directory credentialDirectory) {
    const requiredFiles = <String>[
      'identity.json',
      'auth.json',
      'key-1-private.pem',
    ];
    for (final name in requiredFiles) {
      final file = File(
        '${credentialDirectory.path}${Platform.pathSeparator}$name',
      );
      if (!file.existsSync()) {
        throw FormatException('ZIP 包缺少必需文件：$name');
      }
    }
  }

  static String _sanitizeFileNameComponent(
    String rawValue, {
    required int maxLength,
  }) {
    final sanitized = rawValue
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (sanitized.isEmpty) {
      return 'credential';
    }
    if (sanitized.length <= maxLength) {
      return sanitized;
    }
    return sanitized.substring(0, maxLength);
  }

  static String _normalizeArchivePath(String rawPath) {
    final replaced = rawPath.replaceAll('\\', '/').trim();
    if (replaced.isEmpty) {
      return '';
    }
    final segments = <String>[];
    for (final segment in replaced.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        throw const FormatException('ZIP 包包含非法路径。');
      }
      segments.add(segment);
    }
    if (segments.isEmpty) {
      return '';
    }
    if (rawPath.startsWith('/') || rawPath.startsWith('\\')) {
      throw const FormatException('ZIP 包包含绝对路径。');
    }
    return segments.join('/');
  }
}

class ImportedCredentialBundle {
  const ImportedCredentialBundle({
    required this.manifest,
    required this.credentialDirectory,
  });

  final Map<String, Object?> manifest;
  final Directory credentialDirectory;
}
