import 'dart:io';

import 'package:path/path.dart' as p;

final p.Context _windowsPathContext = p.Context(style: p.Style.windows);

class AttachmentResourceReference {
  const AttachmentResourceReference._({
    required this.uri,
    required this.localPath,
  });

  final Uri uri;
  final String? localPath;

  bool get isLocalFile => localPath != null;

  static AttachmentResourceReference parse(String raw, {bool? windows}) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw const FormatException('Attachment reference is empty.');
    }
    final useWindowsPaths = windows ?? Platform.isWindows;
    if (useWindowsPaths && _isWindowsFilePath(value)) {
      return _local(value, windows: true);
    }

    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.scheme.toLowerCase() == 'file') {
      return _local(
        parsed.toFilePath(windows: useWindowsPaths),
        windows: useWindowsPaths,
      );
    }
    if (parsed != null && parsed.hasScheme) {
      return AttachmentResourceReference._(uri: parsed, localPath: null);
    }
    return _local(value, windows: useWindowsPaths);
  }

  static AttachmentResourceReference _local(
    String path, {
    required bool windows,
  }) {
    return AttachmentResourceReference._(
      uri: Uri.file(path, windows: windows),
      localPath: path,
    );
  }
}

bool _isWindowsFilePath(String value) {
  return _windowsPathContext.isAbsolute(value) ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
      value.startsWith(r'\\') ||
      value.startsWith('//');
}
