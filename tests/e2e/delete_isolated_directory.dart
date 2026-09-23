import 'dart:io';

/// Wait only for transient SQLite/WAL teardown in an already disposed test root.
Future<void> deleteIsolatedDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (!await directory.exists()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      if (!const <int>{39, 66}.contains(error.osError?.errorCode) ||
          attempt == 9) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}
