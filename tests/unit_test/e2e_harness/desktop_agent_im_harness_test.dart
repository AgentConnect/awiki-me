import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e_test/harness/desktop_e2e_runner.dart';
import '../../e2e_test/harness/src/agent_im_config.dart';
import '../../e2e_test/harness/src/e2e_report.dart';
import '../../e2e_test/harness/src/scenario_registry.dart';
import '../../e2e_test/harness/src/secret_redactor.dart';

void main() {
  group('DesktopE2eOptions Agent IM parsing', () {
    test('parses scenario and config flags', () {
      final options = DesktopE2eOptions.parse(const <String>[
        '--platform=macos',
        '--scenario=agent-im-delegated-message',
        '--config',
        'tests/e2e_test/configs/agent_im_delegated.example.yaml',
        '--dry-run',
      ]);

      expect(options.platform, DesktopE2ePlatform.macos);
      expect(options.scenario, agentImDelegatedMessageScenario);
      expect(
        options.configPath,
        'tests/e2e_test/configs/agent_im_delegated.example.yaml',
      );
      expect(options.dryRun, isTrue);
    });

    test('reports missing scenario and config values', () {
      expect(
        () => DesktopE2eOptions.parse(const <String>['--scenario']),
        throwsA(
          isA<DesktopE2eFailure>().having(
            (error) => error.message,
            'message',
            '--scenario requires a value.',
          ),
        ),
      );
      expect(
        () => DesktopE2eOptions.parse(const <String>['--config']),
        throwsA(
          isA<DesktopE2eFailure>().having(
            (error) => error.message,
            'message',
            '--config requires a path.',
          ),
        ),
      );
    });
  });

  group('AgentImDelegatedConfig', () {
    test('loads the checked-in example config', () {
      final config = AgentImDelegatedConfig.load(
        File('tests/e2e_test/configs/agent_im_delegated.example.yaml'),
      );

      expect(config.service.baseUrl, 'https://awiki.info');
      expect(config.service.messageServiceWsUrl, 'wss://awiki.info/im/ws');
      expect(config.remote.sshAlias, 'ali');
      expect(config.cliPeer.repo, '../awiki-cli-rs2');
      expect(config.app.platform, 'macos');
      expect(config.agent.expectedRuntime, 'hermes');
      expect(config.agent.delegatedKeyFragment, 'daemon-key-1');
      expect(config.accounts.appUser.phoneEnv, 'DEV_OTP_PHONE');
      expect(config.accounts.appUser.otpEnv, 'DEV_OTP_CODE');
      expect(config.accounts.peerUser.otpEnv, 'AWIKI_E2E_PEER_OTP');
      expect(config.timeouts.messageProcess, const Duration(seconds: 120));
    });

    test('rejects inline phone values in env-name fields', () async {
      final file = await _writeConfig('''
service: {}
remote: {}
cliPeer: {}
app: {}
agent: {}
accounts:
  appUser:
    phoneEnv: "+8610011110001"
    otpEnv: DEV_OTP_CODE
    handle: app
  peerUser:
    phoneEnv: AWIKI_E2E_PEER_PHONE
    otpEnv: AWIKI_E2E_PEER_OTP
    handle: peer
timeouts: {}
''');

      expect(
        () => AgentImDelegatedConfig.load(file),
        throwsA(
          isA<AgentImConfigFailure>().having(
            (error) => error.message,
            'message',
            'accounts.appUser.phoneEnv must be an environment variable name.',
          ),
        ),
      );
    });
  });

  group('SecretRedactor', () {
    test('redacts tokens, private packages, OTP values and phones', () {
      const redactor = SecretRedactor();
      const input = '''
Authorization style bearer tok_super_secret_value
jwt=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhd2lraSJ9.abcDEFghiJKL123456789
private_key_pem: super-private
otp=987580
phone +8610011110001
''';

      final output = redactor.redact(input);

      expect(output, isNot(contains('tok_super_secret_value')));
      expect(output, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(output, isNot(contains('super-private')));
      expect(output, isNot(contains('987580')));
      expect(output, isNot(contains('+8610011110001')));
      expect(output, contains('<REDACTED_TOKEN>'));
      expect(output, contains('<REDACTED_JWT>'));
      expect(output, contains('<REDACTED_PRIVATE_KEY>'));
      expect(output, contains('<REDACTED_OTP>'));
      expect(output, contains('<REDACTED_PHONE>'));
    });

    test('keeps environment variable names in redacted JSON', () {
      const redactor = SecretRedactor();
      final output =
          redactor.redactJson(<String, Object?>{
                'phoneEnv': 'DEV_OTP_PHONE',
                'otpEnv': 'DEV_OTP_CODE',
                'runtime_token': 'runtime-secret',
              })
              as Map<Object?, Object?>;

      expect(output['phoneEnv'], 'DEV_OTP_PHONE');
      expect(output['otpEnv'], 'DEV_OTP_CODE');
      expect(output['runtime_token'], '<REDACTED_TOKEN>');
    });
  });

  group('Agent IM scenario plan and report', () {
    test('builds a dry-run plan with remote evidence commands', () async {
      final config = AgentImDelegatedConfig.load(
        File('tests/e2e_test/configs/agent_im_delegated.example.yaml'),
      );
      const registry = E2eScenarioRegistry();
      final plan = registry.buildAgentImPlan(
        runId: 'run_test_001',
        platform: 'macos',
        config: config,
      );

      expect(registry.supports(agentImDelegatedMessageScenario), isTrue);
      expect(plan.scenario, agentImDelegatedMessageScenario);
      expect(plan.steps, hasLength(5));
      expect(plan.remoteCommands, hasLength(3));
      expect(plan.toJson().toString(), contains('run_test_001'));
      expect(plan.toJson().toString(), isNot(contains('987580')));
    });

    test('writes redacted JSON reports', () async {
      final dir = await Directory.systemTemp.createTemp('awiki-report-test-');
      addTearDown(() => dir.deleteSync(recursive: true));

      final writer = E2eReportWriter(directory: Directory('unused'));
      final realWriter = E2eReportWriter(directory: dir);
      // Keep const construction covered while writing with a temp directory.
      expect(writer.redactor, isA<SecretRedactor>());

      realWriter.writeJson('report.json', <String, Object?>{
        'phoneEnv': 'DEV_OTP_PHONE',
        'token': 'tok_should_not_appear',
        'nested': <String, Object?>{'private_key': 'private-material'},
      });

      final json =
          jsonDecode(File('${dir.path}/report.json').readAsStringSync())
              as Map<String, Object?>;
      expect(json['phoneEnv'], 'DEV_OTP_PHONE');
      expect(json['token'], '<REDACTED_TOKEN>');
      expect(json['nested'].toString(), isNot(contains('private-material')));
    });
  });
}

Future<File> _writeConfig(String content) async {
  final dir = await Directory.systemTemp.createTemp('agent-im-config-test-');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  final file = File('${dir.path}/config.yaml');
  await file.writeAsString(content);
  return file;
}
