import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Cache the exact source URL selected by the locked sqlite3_flutter_libs.
/// The plugin has no archive hash; record the downloaded archive and extracted
/// file hashes, then verify those same bytes on every subsequent build.
Future<Directory> ensureWindowsSqliteSource(Directory project) async {
  final config = File('${project.path}/.dart_tool/package_config.json');
  final packages = jsonDecode(await config.readAsString()) as Map;
  final package = (packages['packages'] as List).cast<Map>().singleWhere(
    (p) => p['name'] == 'sqlite3_flutter_libs',
  );
  final root = Directory.fromUri(
    config.uri.resolve(package['rootUri'] as String),
  );
  final cmake = await File(
    '${root.path}/windows/CMakeLists.txt',
  ).readAsString();
  final matches = RegExp(
    r'URL\s+(https://sqlite\.org/[0-9]{4}/sqlite-autoconf-[0-9]{7}\.tar\.gz)',
  ).allMatches(cmake).map((m) => m.group(1)!).toSet();
  if (matches.length != 1) {
    throw StateError('Windows SQLite source URL is not unambiguous.');
  }
  final url = matches.single;
  final uri = Uri.parse(url);
  final filename = uri.pathSegments.last;
  final archiveRoot = filename.substring(0, filename.length - 7);
  final key = sha256.convert(utf8.encode(url)).toString();
  final cache = Directory('${project.parent.path}/.tools/sqlite-source/$key');
  final manifest = File('${cache.path}/source.json');
  if (manifest.existsSync()) return verifyWindowsSqliteCache(cache, url);
  List<int>? bytes;
  final snapshots = Directory('${project.path}/.e2e/wb');
  if (snapshots.existsSync()) {
    for (final dir
        in snapshots.listSync(followLinks: false).whereType<Directory>()) {
      final base =
          '${dir.path}/s/build/windows/x64/_deps/sqlite3-subbuild/sqlite3-populate-prefix/src';
      final candidate = File('$base/$filename');
      final stamp = File(
        '$base/sqlite3-populate-stamp/sqlite3-populate-urlinfo.txt',
      );
      if (candidate.existsSync() &&
          stamp.existsSync() &&
          const LineSplitter()
              .convert(stamp.readAsStringSync())
              .contains('url(s)=$url')) {
        if (await candidate.length() == 0) continue;
        // Failed CMake downloads leave both urlinfo and an empty/partial file.
        // A complete archive must contain the three exact compilation inputs.
        final listing = await Process.run('tar.exe', [
          '-tzf',
          candidate.path,
          for (final name in ['sqlite3.c', 'sqlite3.h', 'sqlite3ext.h'])
            '$archiveRoot/$name',
        ]);
        if (listing.exitCode == 0) {
          bytes = await candidate.readAsBytes();
          break;
        }
      }
    }
  }
  if (bytes == null) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    client.findProxy = (url) => HttpClient.findProxyFromEnvironment(url);
    try {
      final response = await (await client.getUrl(
        uri,
      )).close().timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw StateError('Windows SQLite source download failed.');
      }
      bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 45))) {
        bytes.addAll(part);
        if (bytes.length > 32 * 1024 * 1024) {
          throw StateError('Windows SQLite source archive is too large.');
        }
      }
    } finally {
      client.close(force: true);
    }
  }
  if (bytes.isEmpty) {
    throw StateError('Windows SQLite source archive is empty.');
  }
  await cache.create(recursive: true);
  final archive = File('${cache.path}/source.tar.gz');
  await archive.writeAsBytes(bytes, flush: true);
  final temporary = Directory(
    '${cache.path}/extract-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  await temporary.create();
  const names = ['sqlite3.c', 'sqlite3.h', 'sqlite3ext.h'];
  final extract = await Process.run('tar.exe', [
    '-xzf',
    archive.path,
    '-C',
    temporary.path,
    '--strip-components=1',
    for (final name in names) '$archiveRoot/$name',
  ]);
  if (extract.exitCode != 0) {
    throw StateError('Windows SQLite source extraction failed.');
  }
  final files = <String, String>{};
  for (final name in names) {
    final file = File('${temporary.path}/$name');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError(
        'SQLite source cache contains a missing or linked file.',
      );
    }
    files[name] = sha256.convert(await file.readAsBytes()).toString();
  }
  await temporary.rename('${cache.path}/src');
  await manifest.writeAsString(
    jsonEncode({
      'url': url,
      'archiveSha256': sha256.convert(bytes).toString(),
      'files': files,
    }),
    flush: true,
  );
  return verifyWindowsSqliteCache(cache, url);
}

Future<Directory> verifyWindowsSqliteCache(
  Directory cache,
  String expectedUrl,
) async {
  final value =
      jsonDecode(await File('${cache.path}/source.json').readAsString()) as Map;
  if (value['url'] != expectedUrl ||
      sha256
              .convert(await File('${cache.path}/source.tar.gz').readAsBytes())
              .toString() !=
          value['archiveSha256']) {
    throw StateError('Windows SQLite archive cache integrity mismatch.');
  }
  final files = value['files'] as Map;
  if (files.keys.toSet().difference({
        'sqlite3.c',
        'sqlite3.h',
        'sqlite3ext.h',
      }).isNotEmpty ||
      files.length != 3) {
    throw StateError('Windows SQLite source cache manifest mismatch.');
  }
  for (final entry in files.entries) {
    final file = File('${cache.path}/src/${entry.key}');
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        sha256.convert(await file.readAsBytes()).toString() != entry.value) {
      throw StateError('Windows SQLite source cache integrity mismatch.');
    }
  }
  return Directory('${cache.path}/src');
}
