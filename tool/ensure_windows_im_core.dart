import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

class WindowsImCoreArtifactGuard {
  WindowsImCoreArtifactGuard({required this.projectRoot});
  final Directory projectRoot;

  Future<WindowsImCoreArtifact> ensure({bool rebuildIfStale = true}) async {
    if (!Platform.isWindows) {
      throw StateError('Windows SDK verification requires Windows.');
    }
    final layout = await WindowsImCoreLayout.resolve(projectRoot);
    final before = await windowsNativeSourceDigest(layout.sourceRepository);
    if (layout.artifact.existsSync() && layout.manifest.existsSync()) {
      final saved = jsonDecode(layout.manifest.readAsStringSync());
      final sha = await windowsFileSha256(layout.artifact);
      if (saved is Map &&
          saved['schemaVersion'] == 1 &&
          saved['sourceDigest'] == before &&
          saved['artifactSha256'] == sha &&
          windowsPeMachine(layout.artifact.readAsBytesSync()) == 0x8664) {
        return WindowsImCoreArtifact(layout, sha, before, false);
      }
    }
    if (!rebuildIfStale) {
      throw StateError('Windows IM Core artifact provenance is stale.');
    }
    final environment = <String, String>{
      ...Platform.environment,
      'CARGO_NET_GIT_FETCH_WITH_CLI': 'true',
      'AWIKI_IM_CORE_WINDOWS_TARGET': 'x86_64-pc-windows-msvc',
      'AWIKI_IM_CORE_RUST_TOOLCHAIN': '1.88.0',
    };
    final vswhere = File(
      p.join(
        Platform.environment['PROGRAMFILES(X86)'] ?? r'C:\Program Files (x86)',
        'Microsoft Visual Studio',
        'Installer',
        'vswhere.exe',
      ),
    );
    if (vswhere.existsSync()) {
      final found = await Process.run(vswhere.path, [
        '-latest',
        '-products',
        '*',
        '-property',
        'installationPath',
      ]);
      final versions = Directory(
        '${found.stdout.toString().trim()}/VC/Tools/MSVC',
      );
      if (found.exitCode == 0 && versions.existsSync()) {
        final directories = versions.listSync().whereType<Directory>().toList()
          ..sort((a, b) => b.path.compareTo(a.path));
        for (final directory in directories) {
          final bin = Directory('${directory.path}/bin/Hostx64/x64');
          if (File('${bin.path}/dumpbin.exe').existsSync()) {
            environment['PATH'] =
                '${bin.path};${Platform.environment['PATH'] ?? ''}';
            break;
          }
        }
      }
    }
    if (!environment.containsKey('GIT_SSH_COMMAND')) {
      final key = File(
        '${Platform.environment['USERPROFILE']}/.ssh/id_ed25519_github',
      );
      if (key.existsSync()) {
        environment['GIT_SSH_COMMAND'] =
            'ssh -i "${key.path.replaceAll('\\', '/')}" '
            '-o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15';
      }
    }
    final build = await Process.start(
      'pwsh.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-File',
        '${layout.sourceRepository.path}/scripts/flutter/build-windows.ps1',
      ],
      workingDirectory: layout.sourceRepository.path,
      environment: environment,
    );
    await Future.wait([
      stdout.addStream(build.stdout),
      stderr.addStream(build.stderr),
    ]);
    if (await build.exitCode != 0) {
      throw StateError('The official Windows native SDK build failed.');
    }
    final after = await windowsNativeSourceDigest(layout.sourceRepository);
    if (before != after) {
      throw StateError('Windows SDK sources changed during compilation.');
    }
    if (windowsPeMachine(layout.artifact.readAsBytesSync()) != 0x8664) {
      throw StateError('The Windows SDK artifact is not PE x64.');
    }
    final sha = await windowsFileSha256(layout.artifact);
    layout.manifest.parent.createSync(recursive: true);
    layout.manifest.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1, 'target': 'x86_64-pc-windows-msvc', 'mode': 'workspace-source-testing', 'sourceDigest': after, 'artifactSha256': sha, 'builtAt': DateTime.now().toUtc().toIso8601String()})}\n',
      flush: true,
    );
    return WindowsImCoreArtifact(layout, sha, after, true);
  }
}

class WindowsImCoreLayout {
  WindowsImCoreLayout(this.sourceRepository, this.artifact, this.manifest);
  final Directory sourceRepository;
  final File artifact, manifest;
  static Future<WindowsImCoreLayout> resolve(Directory projectRoot) async {
    final config = File('${projectRoot.path}/.dart_tool/package_config.json');
    final packages =
        (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
    final package =
        packages.singleWhere((row) => row['name'] == 'awiki_im_core') as Map;
    final root = Directory.fromUri(
      config.uri.resolve(package['rootUri'] as String),
    );
    final repository = root.parent.parent;
    return WindowsImCoreLayout(
      repository,
      File('${root.path}/windows/bin/awiki_im_core.dll'),
      File('${projectRoot.path}/.e2e/native-core/windows/provenance.json'),
    );
  }
}

class WindowsImCoreArtifact {
  WindowsImCoreArtifact(
    this.layout,
    this.sha256,
    this.sourceDigest,
    this.rebuilt,
  );
  final WindowsImCoreLayout layout;
  final String sha256, sourceDigest;
  final bool rebuilt;
}

Future<String> windowsFileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

int windowsPeMachine(List<int> image) {
  if (image.length < 64 || image[0] != 0x4d || image[1] != 0x5a) {
    throw const FormatException('Windows native artifact has no DOS header.');
  }
  final bytes = ByteData.sublistView(Uint8List.fromList(image));
  final offset = bytes.getUint32(0x3c, Endian.little);
  if (offset > image.length - 6 ||
      bytes.getUint32(offset, Endian.little) != 0x4550) {
    throw const FormatException('Windows native artifact has no PE header.');
  }
  return bytes.getUint16(offset + 4, Endian.little);
}

Future<String> windowsNativeSourceDigest(Directory core) async {
  final roots = [
    core,
    Directory('${core.parent.path}/anp/anp'),
    Directory('${core.parent.path}/anp/anp-identity'),
  ];
  final evidence = <String>[];
  for (final root in roots) {
    final files = await Process.run('git', [
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '-z',
      '--',
      'Cargo.toml',
      'Cargo.lock',
      'rust-toolchain.toml',
      'crates',
      'src',
      'rust',
      'packages/awiki_im_core',
      'scripts/flutter/build-windows.ps1',
      '.cargo/config.toml',
    ], workingDirectory: root.path);
    if (files.exitCode != 0) {
      throw StateError('Windows native source inventory is unavailable.');
    }
    final names =
        files.stdout
            .toString()
            .split('\u0000')
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    for (final name in names) {
      // Generated DLLs, archives and machine-local state never enter the source digest.
      if (name.endsWith('.dll') ||
          name.contains('/target/') ||
          name.contains('/bin/')) {
        continue;
      }
      final file = File(p.join(root.path, name));
      if (file.existsSync()) {
        evidence.add('${root.path}|$name|${await windowsFileSha256(file)}');
      }
    }
  }
  return sha256.convert(utf8.encode(evidence.join('\n'))).toString();
}

Future<void> main(List<String> args) async {
  try {
    final result = await WindowsImCoreArtifactGuard(
      projectRoot: Directory.current,
    ).ensure(rebuildIfStale: !args.contains('--check-only'));
    stdout.writeln(
      jsonEncode({
        'status': 'current',
        'rebuilt': result.rebuilt,
        'artifactSha256': result.sha256,
        'sourceDigest': result.sourceDigest,
      }),
    );
  } catch (error) {
    stderr.writeln('Windows native SDK check failed (${error.runtimeType}).');
    exitCode = 2;
  }
}
