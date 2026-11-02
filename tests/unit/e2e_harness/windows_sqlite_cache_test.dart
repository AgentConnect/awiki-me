import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/windows_sqlite_cache.dart';

void main() {
  test(
    'SQLite cache binds archive, source URL and exact source file bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-sqlite-cache-');
      addTearDown(() => root.delete(recursive: true));
      const url = 'https://sqlite.org/2026/sqlite-autoconf-3520000.tar.gz';
      await File('${root.path}/source.tar.gz').writeAsBytes([1, 2, 3]);
      await Directory('${root.path}/src').create();
      final files = <String, String>{};
      for (final name in ['sqlite3.c', 'sqlite3.h', 'sqlite3ext.h']) {
        await File('${root.path}/src/$name').writeAsString('synthetic $name');
        files[name] = sha256.convert(utf8.encode('synthetic $name')).toString();
      }
      await File('${root.path}/source.json').writeAsString(
        jsonEncode({
          'url': url,
          'archiveSha256': sha256.convert([1, 2, 3]).toString(),
          'files': files,
        }),
      );
      expect((await verifyWindowsSqliteCache(root, url)).existsSync(), isTrue);
      await expectLater(
        verifyWindowsSqliteCache(root, 'https://foreign.example/source'),
        throwsStateError,
      );
      await File('${root.path}/src/sqlite3.c').writeAsString('changed');
      await expectLater(verifyWindowsSqliteCache(root, url), throwsStateError);
    },
  );
}
