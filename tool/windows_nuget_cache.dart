import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Reuse the exact NuGet executable pinned by local_auth_windows. Each isolated
/// CMake project otherwise downloads the same file again through FetchContent.
Future<File> ensureWindowsNuget(Directory project) async {
  final config = File('${project.path}/.dart_tool/package_config.json');
  final packages = jsonDecode(await config.readAsString()) as Map;
  final package = (packages['packages'] as List).cast<Map>().singleWhere(
    (entry) => entry['name'] == 'local_auth_windows',
  );
  final packageRoot = Directory.fromUri(
    config.uri.resolve(package['rootUri'] as String),
  ).uri;
  final cmake = await File.fromUri(
    packageRoot.resolve('windows/CMakeLists.txt'),
  ).readAsString();
  final pin = RegExp(
    r'FetchContent_Declare\(nuget\s+URL\s+"([^"]+)"\s+URL_HASH\s+SHA256=([a-fA-F0-9]{64})',
  ).firstMatch(cmake);
  if (pin == null) {
    throw StateError('The Windows NuGet dependency is not pinned.');
  }
  final uri = Uri.parse(pin.group(1)!);
  if (uri.scheme != 'https' ||
      uri.host != 'dist.nuget.org' ||
      uri.userInfo.isNotEmpty ||
      !RegExp(
        r'^/win-x86-commandline/v[0-9.]+/nuget\.exe$',
      ).hasMatch(uri.path)) {
    throw StateError('The pinned Windows NuGet source is unsupported.');
  }
  final expected = pin.group(2)!.toLowerCase();
  final cache = File('${project.parent.path}/.tools/nuget/$expected/nuget.exe');
  final candidates = <File>[];
  final snapshots = Directory('${project.path}/.e2e/wb');
  if (snapshots.existsSync()) {
    for (final directory
        in snapshots.listSync(followLinks: false).whereType<Directory>()) {
      candidates.add(
        File('${directory.path}/s/build/windows/x64/_deps/nuget-src/nuget.exe'),
      );
    }
  }
  return cacheVerifiedWindowsTool(
    target: cache,
    candidates: candidates,
    expectedSha256: expected,
    download: () async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      client.findProxy = (url) => HttpClient.findProxyFromEnvironment(url);
      try {
        final request = await client.getUrl(uri);
        final response = await request.close().timeout(
          const Duration(seconds: 45),
        );
        if (response.statusCode != 200) {
          throw StateError('Pinned NuGet download failed.');
        }
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 45),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 32 * 1024 * 1024) {
            throw StateError('Pinned NuGet download exceeded its limit.');
          }
        }
        return bytes;
      } finally {
        client.close(force: true);
      }
    },
  );
}

Future<File> cacheVerifiedWindowsTool({
  required File target,
  required Iterable<File> candidates,
  required String expectedSha256,
  required Future<List<int>> Function() download,
}) async {
  bool matches(List<int> bytes) =>
      sha256.convert(bytes).toString() == expectedSha256;
  if (target.existsSync()) {
    if (!matches(await target.readAsBytes())) {
      throw StateError('Pinned Windows tool cache integrity mismatch.');
    }
    return target;
  }
  List<int>? verified;
  for (final candidate in candidates) {
    if (!candidate.existsSync()) continue;
    final bytes = await candidate.readAsBytes();
    if (matches(bytes)) {
      verified = bytes;
      break;
    }
  }
  verified ??= await download();
  if (!matches(verified)) {
    throw StateError('Pinned Windows tool download integrity mismatch.');
  }
  await target.parent.create(recursive: true);
  final pending = File(
    '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.pending',
  );
  await pending.writeAsBytes(verified, flush: true);
  if (target.existsSync()) {
    if (!matches(await target.readAsBytes())) {
      throw StateError('Pinned Windows tool cache changed.');
    }
    await pending.delete();
  } else {
    await pending.rename(target.path);
  }
  return target;
}
