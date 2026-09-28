import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Only native image-picker copies inside this App's temporary directory.
/// Desktop originals and paths outside the sandbox are never removed.
Future<void> discardAvatarPickerFile(String path) async {
  try {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final root = await (await getTemporaryDirectory()).resolveSymbolicLinks();
    final file = File(path);
    final resolved = await file.resolveSymbolicLinks();
    if (resolved.startsWith('$root${Platform.pathSeparator}')) {
      await file.delete();
    }
  } catch (_) {
    // The OS may already have removed its temporary result.
  }
}
