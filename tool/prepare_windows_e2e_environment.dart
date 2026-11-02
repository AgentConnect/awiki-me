import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import '../tests/e2e/protected_files.dart';
import '../tests/e2e/desktop_tool_executable.dart';
import '../tests/e2e/account_state_operator_contract.dart';

/// Relocates an existing reviewed fixture; never invents phone/OTP/PIN values
/// and never writes those values to stdout or command-line arguments.
Future<void> main(List<String> arguments) async {
  try {
    if (!Platform.isWindows) {
      throw StateError('Windows E2E environment requires Windows.');
    }
    final args = <String, String>{};
    for (final argument in arguments) {
      final i = argument.indexOf('=');
      if (!argument.startsWith('--') || i < 3) {
        throw ArgumentError('Use --key=value options.');
      }
      args[argument.substring(2, i)] = argument.substring(i + 1);
    }
    final source = File(args['config'] ?? '');
    final pin = File(args['pin-fixture'] ?? '');
    if (!isPrivateE2eFile(source) || !isPrivateE2eFile(pin)) {
      throw StateError('Reviewed input fixtures must be private.');
    }
    final runId = args['run-id'] ?? '';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$').hasMatch(runId)) {
      throw ArgumentError('Invalid run ID.');
    }
    final root = Directory.current.absolute;
    final output = Directory('${root.path}/.e2e/windows-runtime/$runId')
      ..createSync(recursive: true);
    protectE2ePathSync(output.path, directory: true);
    final data =
        jsonDecode(jsonEncode(loadYaml(source.readAsStringSync())))
            as Map<String, dynamic>;
    final service = data['service'] as Map;
    if (service['baseUrl'] != 'https://awiki.info' ||
        service['didDomain'] != 'awiki.info') {
      throw StateError('Only reviewed awiki.info is permitted.');
    }
    data['platform'] = 'windows';
    if (args['otp-preset'] != null) {
      final presetFile = File(args['otp-preset']!);
      if (!isPrivateE2eFile(presetFile)) {
        throw StateError('OTP preset must be private.');
      }
      final preset = jsonDecode(presetFile.readAsStringSync()) as Map;
      if (!RegExp(
            r'^\+[1-9][0-9]{6,14}$',
          ).hasMatch(preset['phone'] as String) ||
          !RegExp(r'^[0-9]{6}$').hasMatch(preset['code'] as String)) {
        throw StateError('OTP preset is invalid.');
      }
      data['otp'] = {'phone': preset['phone'], 'code': preset['code']};
    }
    final core = Directory('${root.parent.path}/awiki-cli-rs2');
    final ref = (await Process.run('git', [
      'rev-parse',
      'HEAD',
    ], workingDirectory: core.path)).stdout.toString().trim();
    final release =
        jsonDecode(
              File(
                '${core.path}/scripts/release/cli/release-config.json',
              ).readAsStringSync(),
            )
            as Map;
    final version = release['channels']['stable']['version'] as String;
    final toolsFile = File('${root.path}/.e2e/windows-tools/$ref/tools.json');
    final tools = jsonDecode(toolsFile.readAsStringSync()) as Map;
    if (tools['sourceRef'] != ref ||
        tools['platform'] != 'windows' ||
        tools['architecture'] != 'x86_64') {
      throw StateError(
        'Prepared Windows test tools do not match the selected Core source.',
      );
    }
    final artifacts = tools['artifacts'] as Map;
    final cli = data['cliPeer'] as Map;
    cli['rustRepo'] = core.path;
    cli['sourceRef'] = ref;
    cli['binary'] = artifacts['cli']['path'];
    final daemon = Map<String, dynamic>.from(
      data['daemon'] as Map? ?? const {},
    );
    daemon['rustRepo'] = core.path;
    daemon['binary'] = artifacts['daemon']['path'];
    daemon['stateRoot'] = '${output.path}/daemon-state';
    daemon['readyFile'] = '${output.path}/daemon-state/ready.json';
    final fakeClients = Directory('${output.path}/acp-clients');
    final fixtureEnvironment = <String, String>{};
    if (Platform.environment['AWIKI_E2E_PYTHON_BIN']?.isNotEmpty == true) {
      final fixtureResult =
          await Process.run(desktopToolExecutable('python3'), [
            '${core.path}/scripts/testing/prepare_acp_fixture.py',
            '--root',
            fakeClients.path,
          ]);
      if (fixtureResult.exitCode != 0) {
        throw StateError('Native offline ACP fixture preparation failed.');
      }
      fixtureEnvironment.addAll(
        Map<String, String>.from(
          jsonDecode(fixtureResult.stdout.toString()) as Map,
        ),
      );
    } else {
      fakeClients.createSync(recursive: true);
    }
    protectE2ePathSync(fakeClients.path, directory: true);
    final daemonEnvironment = File('${output.path}/daemon-test.env');
    daemonEnvironment.writeAsStringSync(
      [
        '# Native Windows test clients; service endpoints come from the reviewed run config.',
        for (final entry in fixtureEnvironment.entries)
          '${entry.key}=${entry.value}',
        '',
      ].join('\n'),
      flush: true,
    );
    protectE2ePathSync(daemonEnvironment.path, directory: false);
    daemon['envFile'] = daemonEnvironment.path;
    daemon['fakeHermesHome'] = fakeClients.path;
    data['daemon'] = daemon;
    final config = File('${output.path}/config.local.yaml');
    await config.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(data)}\n',
    );
    protectE2ePathSync(config.path);
    final fixture = File('${output.path}/pin-fixture.json');
    await pin.copy(fixture.path);
    protectE2ePathSync(fixture.path);
    final result = {
      'platform': 'windows',
      'configPath': config.path,
      'pinFixturePath': fixture.path,
      'cliSourceRef': ref,
      'cliVersion': version,
      'cliBinary': cli['binary'],
      'daemonBinary': daemon['binary'],
      'nativeAcpFixturePrepared': fixtureEnvironment.isNotEmpty,
      'serviceOrigin': 'https://awiki.info',
      'operatorEnvironment': {
        'AWIKI_MESSAGE_SYNC_V2_RECOVERY_E2E': '1',
        'AWIKI_MULTI_DEVICE_E2E_OPERATOR_MODE': 'ali',
        'AWIKI_ACCOUNT_STATE_V1_E2E': '1',
        'AWIKI_ACCOUNT_STATE_E2E_OPERATOR_COMMAND_JSON': jsonEncode(
          reviewedAccountStateOperatorCommandForMode('ali'),
        ),
        'AWIKI_ACCOUNT_STATE_TEST_FAILPOINTS_ENABLED': '1',
        if (File(
          '${root.parent.path}/awiki-system-test/.venv/Scripts/python.exe',
        ).existsSync()) ...{
          'PYTHONPATH':
              '${root.parent.path}/awiki-system-test;${root.parent.path}/awiki-system-test/src',
          'AWIKI_E2E_AGENT_AVATAR_FIXTURE_COMMAND': jsonEncode([
            '${root.parent.path}/awiki-system-test/.venv/Scripts/python.exe',
            '-m',
            'helpers.agent_avatar_fixture',
            '--target',
            'awiki-info-testing',
            '--state-dir',
            '${output.path}/agent-avatar-fixtures',
          ]),
        },
      },
    };
    File(
      '${output.path}/environment.json',
    ).writeAsStringSync(jsonEncode(result));
    stdout.writeln(jsonEncode(result));
  } catch (error) {
    stderr.writeln(
      'Windows E2E environment preparation failed (${error.runtimeType}).',
    );
    exitCode = 2;
  }
}
