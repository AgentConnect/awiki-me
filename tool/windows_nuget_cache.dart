import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

// Baselines of the Microsoft-signed archives already installed by this locked
// plugin. Keeping an offline feed avoids service-index queries for each role.
const windowsNativeNugetPackages = [
  (
    id: 'Microsoft.Windows.ImplementationLibrary',
    version: '1.0.220201.1',
    hash: '924f1553bf191578261312bedfa9e9a441ad9fca59aaeae4f0038aa3533ccd34',
  ),
  (
    id: 'Microsoft.Windows.CppWinRT',
    version: '2.0.220418.1',
    hash: '35f4b33a2625da94c0f79db51985148b255b5121445fc257e36597e6f54277c4',
  ),
];

Future<File> prepareWindowsNugetEnvironment(
  Directory project,
  Directory generatedProject,
) async {
  final executable = await ensureWindowsNuget(project);
  final feed = Directory('${project.parent.path}/.tools/nuget/native-packages');
  final snapshots = Directory('${project.path}/.e2e/wb');
  final dirs = snapshots.existsSync()
      ? snapshots.listSync(followLinks: false).whereType<Directory>().toList()
      : <Directory>[];
  for (final package in windowsNativeNugetPackages) {
    final name = '${package.id}.${package.version}.nupkg';
    await cacheVerifiedWindowsTool(
      target: File('${feed.path}/$name'),
      candidates: [
        for (final dir in dirs)
          File(
            '${dir.path}/s/build/windows/x64/packages/${package.id}.${package.version}/$name',
          ),
      ],
      expectedSha256: package.hash,
      download: () async {
        final id = package.id.toLowerCase(), version = package.version;
        final url = Uri.parse(
          'https://api.nuget.org/v3-flatcontainer/$id/$version/$id.$version.nupkg',
        );
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 30);
        client.findProxy = (url) => HttpClient.findProxyFromEnvironment(url);
        try {
          final response = await (await client.getUrl(
            url,
          )).close().timeout(const Duration(seconds: 45));
          if (response.statusCode != 200) {
            throw StateError('Pinned native NuGet package download failed.');
          }
          final bytes = <int>[];
          await for (final part in response.timeout(
            const Duration(seconds: 45),
          )) {
            bytes.addAll(part);
            if (bytes.length > 32 * 1024 * 1024) {
              throw StateError('Pinned NuGet package is too large.');
            }
          }
          return bytes;
        } finally {
          client.close(force: true);
        }
      },
    );
  }
  String xml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');
  // NuGet starts config discovery at CMAKE_BINARY_DIR, underneath this root.
  // No machine/user NuGet configuration is changed.
  await File('${generatedProject.path}/NuGet.Config').writeAsString(
    '<?xml version="1.0" encoding="utf-8"?>\n<configuration><packageSources><clear />'
    '<add key="AWikiVerifiedNativeCache" value="${xml(feed.path)}" />'
    '</packageSources></configuration>\n',
    flush: true,
  );
  return executable;
}

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
