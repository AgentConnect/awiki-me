import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Wait only for transient SQLite/WAL teardown in an already disposed test root.
Future<void> deleteIsolatedDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 10; attempt += 1) {
    if (!await directory.exists()) return;
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      final transient =
          const <int>{39, 66}.contains(error.osError?.errorCode) ||
          (Platform.isWindows &&
              const <int>{32, 145}.contains(error.osError?.errorCode));
      if (!transient || attempt == 9) {
        if (Platform.isWindows && transient) {
          await _recordWindowsSharingDiagnostic(directory);
        }
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }
}

/// Diagnostics never change the original deletion result or print child output.
Future<void> _recordWindowsSharingDiagnostic(Directory directory) async {
  Process? child;
  StreamSubscription<String>? outputSubscription;
  var exited = false;
  void unavailable() => print('windows_fixture_sharing unavailable');
  try {
    final python = Platform.environment['AWIKI_E2E_PYTHON_BIN'];
    final script = Platform.environment['AWIKI_E2E_WINDOWS_FILE_LOCK_PROBE'];
    if (python == null ||
        script == null ||
        !File(python).existsSync() ||
        !File(script).existsSync()) {
      unavailable();
      return;
    }
    child = await Process.start(
      python,
      ['-I', '-S', script, '--root', directory.path],
      environment: {
        for (final key in [
          'SystemRoot',
          'WINDIR',
          'ComSpec',
          'PATH',
          'TEMP',
          'TMP',
        ])
          if (Platform.environment[key] != null)
            key: Platform.environment[key]!,
      },
      includeParentEnvironment: false,
      runInShell: false,
    );
    final output = StringBuffer();
    var length = 0;
    var invalid = false;
    outputSubscription = child.stdout.transform(utf8.decoder).listen((text) {
      if (invalid) return;
      length += text.length;
      if (length > 8192) {
        invalid = true;
        child?.kill();
        return;
      }
      output.write(text);
    });
    final outputDone = outputSubscription.asFuture<void>().catchError((
      Object _,
    ) {
      invalid = true;
    });
    final errorsDone = child.stderr.drain<void>().catchError((Object _) {
      invalid = true;
    });
    final code = await child.exitCode.timeout(const Duration(seconds: 5));
    exited = true;
    await Future.wait([
      outputDone,
      errorsDone,
    ]).timeout(const Duration(seconds: 1));
    final decoded = code == 0 && !invalid
        ? jsonDecode(output.toString())
        : null;
    if (decoded is! Map ||
        decoded['status'] != 'scanned' ||
        decoded['lockedCategories'] is! Map) {
      unavailable();
      return;
    }
    final locks = decoded['lockedCategories'] as Map;
    int bounded(Object? value) =>
        value is int && value >= 0 && value <= 512 ? value : 0;
    final errors = decoded['systemErrorCounts'];
    final systemErrors = errors is Map
        ? errors.values.fold<int>(0, (sum, value) => sum + bounded(value))
        : 0;
    // Only fixed field names and bounded numbers cross into Flutter logs.
    print(
      'windows_fixture_sharing ${jsonEncode({'scanned': bounded(decoded['scannedCount']), 'coreSqlite': bounded(locks['core_sqlite']), 'coreJournal': bounded(locks['core_sqlite_journal']), 'productSqlite': bounded(locks['product_sqlite']), 'lockFiles': bounded(locks['lock_file']), 'directories': bounded(locks['directory']), 'otherFiles': bounded(locks['other_file']), 'systemErrors': systemErrors > 512 ? 512 : systemErrors, 'truncated': decoded['truncated'] == true})}',
    );
  } on Object {
    unavailable();
  } finally {
    if (child != null && !exited) {
      child.kill();
      try {
        await child.exitCode.timeout(const Duration(seconds: 1));
      } on Object {
        /* Keep the original failure. */
      }
    }
    try {
      await outputSubscription?.cancel();
    } on Object {
      /* Keep the original failure. */
    }
  }
}
