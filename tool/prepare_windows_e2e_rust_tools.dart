import 'dart:convert';
import 'dart:io';

import '../tests/e2e/runner.dart';
import 'ensure_windows_im_core.dart' show windowsFileSha256, windowsPeMachine;

/// Builds test tools before any backend fixture window or UI invocation opens.
Future<void> main() async {
  try {
    if (!Platform.isWindows) throw StateError('Native Windows is required.');
    final root = Directory.current.absolute;
    final repo = Directory('${root.parent.path}/awiki-cli-rs2');
    final source = await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: repo.path);
    final sourceRef = source.stdout.toString().trim();
    if (source.exitCode != 0 ||
        !RegExp(r'^[0-9a-f]{40}$').hasMatch(sourceRef)) {
      throw StateError('Current Core source could not be identified.');
    }
    final commands = DesktopCommandRunner(
      root: root,
      dryRun: false,
      redactor: DesktopSecretRedactor([]),
      logLine: stderr.writeln,
    );
    final cli = await prepareVersionedCliArtifact(
      root: root,
      rustRepoPath: repo.path,
      expectedSourceRef: sourceRef,
      commands: commands,
      includeAvatarProbe: true,
    );
    final target = cli.binary.parent.parent;
    await commands.run(
      'cargo',
      const [
        'rustc',
        '--locked',
        '-p',
        'awiki-deamon',
        '--features',
        'system-test-probe',
        '--bin',
        'awiki-deamon',
        '--',
        '-C',
        'link-arg=/STACK:8388608',
      ],
      workingDirectory: repo,
      environment: {'CARGO_TARGET_DIR': target.path},
      timeout: const Duration(minutes: 20),
    );
    final daemon = File('${target.path}/debug/awiki-deamon.exe');
    final probe = File('${target.path}/debug/awiki-system-test-probe.exe');
    final daemonVersion = RegExp(r'^version\s*=\s*"([0-9.]+)"', multiLine: true)
        .firstMatch(
          File(
            '${repo.path}/crates/awiki-deamon/Cargo.toml',
          ).readAsStringSync(),
        )
        ?.group(1);
    if (daemonVersion == null) {
      throw StateError('Daemon version is unavailable.');
    }
    final checked = await commands.captureResult(daemon.path, [
      '__self-check',
      '--expected-version',
      daemonVersion,
    ]);
    final check = jsonDecode(checked.output) as Map;
    if (check['ok'] != true) {
      throw StateError('Native Daemon self-check failed.');
    }
    final cliCheck = await commands.captureResult(cli.binary.path, [
      '--format',
      'json',
      'version',
    ]);
    final version = (jsonDecode(cliCheck.output) as Map)['data'] as Map;
    if (version['commit'] != sourceRef ||
        version['goos'] != 'windows' ||
        version['goarch'] != 'amd64') {
      throw StateError(
        'CLI did not attest the selected native Windows source.',
      );
    }
    final files = {'cli': cli.binary, 'probe': probe, 'daemon': daemon};
    final artifacts = <String, Object>{};
    for (final entry in files.entries) {
      if (!entry.value.existsSync() ||
          windowsPeMachine(entry.value.readAsBytesSync()) != 0x8664) {
        throw StateError(
          'A test tool is missing or is not a native Windows x64 PE.',
        );
      }
      artifacts[entry.key] = {
        'path': entry.value.path,
        'sha256': await windowsFileSha256(entry.value),
      };
    }
    final after = await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: repo.path);
    if (after.exitCode != 0 || after.stdout.toString().trim() != sourceRef) {
      throw StateError('Core source changed during Windows tool preparation.');
    }
    final result = {
      'schemaVersion': 1,
      'platform': 'windows',
      'architecture': 'x86_64',
      'sourceRef': sourceRef,
      'cliVersion': cli.version,
      'daemonVersion': daemonVersion,
      'artifacts': artifacts,
    };
    final output = File(
      '${root.path}/.e2e/windows-tools/$sourceRef/tools.json',
    );
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      flush: true,
    );
    stdout.writeln(jsonEncode(result));
  } on E2eFailure catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  } catch (error) {
    stderr.writeln(
      'Windows Rust test tool preparation failed (${error.runtimeType}).',
    );
    exitCode = 2;
  }
}
