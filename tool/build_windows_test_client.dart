import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'windows_e2e_workspace.dart';
import 'windows_nuget_cache.dart';
import '../tests/e2e/desktop_tool_executable.dart';

/// Builds the normal lib/main.dart UI against an explicit test tenant, with
/// isolated native Windows identities. Native SDK compilation is a prerequisite
/// owned by scripts/flutter/build-windows.ps1 in the Core repository.
Future<void> main(List<String> arguments) async {
  try {
    if (!Platform.isWindows) {
      throw StateError('A native Windows host is required.');
    }
    final options = <String, String>{};
    for (final argument in arguments) {
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') || separator < 3) {
        throw ArgumentError(
          'Use --tenant-config, --pin-trust and --run-id in --key=value form.',
        );
      }
      options[argument.substring(2, separator)] = argument.substring(
        separator + 1,
      );
    }
    final runId = options['run-id'] ?? '';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$').hasMatch(runId)) {
      throw ArgumentError('The test-client run ID is invalid.');
    }
    final root = Directory.current.absolute;
    final tenantFile = File(options['tenant-config'] ?? '');
    final trustFile = File(options['pin-trust'] ?? '');
    final tenantBytes = tenantFile.readAsBytesSync();
    final trustBytes = trustFile.readAsBytesSync();
    final tenant = jsonDecode(utf8.decode(tenantBytes)) as Map;
    final slots = tenant['tenants'] as Map;
    if (tenant['schema_version'] != 1 ||
        tenant['default_slot'] != 'primary' ||
        slots['primary']['backend_origin'] != 'https://awiki.info' ||
        slots['primary']['did_host'] != 'awiki.info') {
      throw StateError(
        'This candidate must use the reviewed awiki.info testing tenant.',
      );
    }
    final trust = jsonDecode(utf8.decode(trustBytes)) as List;
    if (trust.isEmpty ||
        trust.any(
          (item) =>
              item['control_base_url'] !=
              'https://awiki.info/user-service/v1/key-recovery',
        )) {
      throw StateError(
        'The test-client Realm trust does not match awiki.info.',
      );
    }
    final slot = sha256.convert(utf8.encode(runId)).toString().substring(0, 8);
    final work = Directory('${root.path}/.e2e/wc/$slot');
    final source = await prepareWindowsE2eWorkspace(
      projectRoot: root,
      destination: Directory('${work.path}/s'),
      bundleId: 'ai.awiki.awikime.dev.e2e.client',
      name: 'client',
    );
    final config = Directory('${work.path}/flutter-config')
      ..createSync(recursive: true);
    File('${config.path}/.flutter_settings').writeAsStringSync(
      jsonEncode({'build-dir': 'build', 'enable-windows-desktop': true}),
    );
    final nuget = await prepareWindowsNugetEnvironment(root, source);
    final environment = <String, String>{
      ...Platform.environment,
      'PATH': '${nuget.parent.path};${Platform.environment['PATH'] ?? ''}',
      'APPDATA': config.path,
      'PUB_HOSTED_URL':
          Platform.environment['PUB_HOSTED_URL'] ??
          'https://mirrors.tuna.tsinghua.edu.cn/dart-pub',
    };
    Future<void> run(List<String> args) async {
      final process = await Process.start(
        desktopToolExecutable('flutter'),
        args,
        workingDirectory: source.path,
        environment: environment,
        mode: ProcessStartMode.inheritStdio,
      );
      if (await process.exitCode != 0) {
        throw StateError('Windows test-client Flutter ${args.first} failed.');
      }
    }

    await run(['pub', 'get', '--enforce-lockfile']);
    verifyWindowsSnapshotDependencies(root, source);
    await run([
      'build',
      'windows',
      '--debug',
      '--no-pub',
      '--target=lib/main.dart',
      '--dart-define=AWIKI_BUILTIN_TENANTS_BASE64=${base64Encode(tenantBytes)}',
      '--dart-define=AWIKI_BUILTIN_TENANTS_SHA256=${sha256.convert(tenantBytes)}',
      '--dart-define=AWIKI_PIN_RECOVERY_TENANTS_BASE64=${base64Encode(trustBytes)}',
    ]);
    final bundle = Directory('${source.path}/build/windows/x64/runner/Debug');
    for (final name in [
      'AWikiMe.exe',
      'flutter_windows.dll',
      'awiki_im_core.dll',
    ]) {
      if (!File('${bundle.path}/$name').existsSync()) {
        throw StateError(
          'The Windows test-client runtime bundle is incomplete.',
        );
      }
    }
    final manifest = File('${work.path}/client.json');
    manifest.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'status': 'built', 'platform': 'windows-x64', 'entrypoint': 'lib/main.dart', 'bundle': bundle.path, 'executable': '${bundle.path}/AWikiMe.exe', 'tenantSha256': sha256.convert(tenantBytes).toString(), 'realmTrustSha256': sha256.convert(trustBytes).toString(), 'sdkSha256': sha256.convert(File('${bundle.path}/awiki_im_core.dll').readAsBytesSync()).toString()})}\n',
    );
    stdout.writeln('Windows test client: ${manifest.path}');
  } catch (error) {
    stderr.writeln(
      'Windows test client failed: '
      '${error is StateError ? error.message : error.runtimeType}.',
    );
    exitCode = 1;
  }
}
