import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e_test/harness/desktop_e2e_runner.dart';
import '../../e2e_test/harness/src/agent_im_config.dart';
import '../../e2e_test/harness/src/cli_peer_adapter.dart';
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
      expect(config.cliPeer.binary, 'target/debug/awiki-cli');
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
--otp 987580
--token tok_flag_secret_value
''';

      final output = redactor.redact(input);

      expect(output, isNot(contains('tok_super_secret_value')));
      expect(output, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(output, isNot(contains('super-private')));
      expect(output, isNot(contains('987580')));
      expect(output, isNot(contains('+8610011110001')));
      expect(output, isNot(contains('tok_flag_secret_value')));
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

  group('AgentImCliPeerAdapter', () {
    test('builds a dry-run CLI peer plan without secret values', () {
      final config = AgentImDelegatedConfig.load(
        File('tests/e2e_test/configs/agent_im_delegated.example.yaml'),
      );
      final adapter = AgentImCliPeerAdapter(
        config: config,
        cliRepo: Directory('/tmp/awiki-cli-rs2'),
        binary: File('/tmp/awiki-cli-rs2/target/debug/awiki-cli'),
        workspace: Directory('/tmp/peer-b'),
        reportDir: Directory('/tmp/report'),
        runner: _FakeCliRunner(),
        dryRun: true,
      );

      final plan = adapter.buildPlan(
        runId: 'run_cli_001',
        targetHandle: config.accounts.appUser.handle,
        messageText: AgentImCliPeerAdapterPlan.defaultOrdinaryMessageText(
          'run_cli_001',
        ),
      );
      final json = plan.toJson();

      expect(plan.commands, hasLength(4));
      expect(json.toString(), contains(r'$AWIKI_E2E_PEER_PHONE'));
      expect(json.toString(), contains('msg send'));
      expect(json.toString(), contains('run_cli_001'));
      expect(json.toString(), isNot(contains('+8610011110001')));
      expect(json.toString(), isNot(contains('987580')));
    });

    test(
      'runs CLI peer flow with isolated workspace and redacted result',
      () async {
        final config = AgentImDelegatedConfig.load(
          File('tests/e2e_test/configs/agent_im_delegated.example.yaml'),
        );
        final fakeRunner = _FakeCliRunner();
        final adapter = AgentImCliPeerAdapter(
          config: config,
          cliRepo: Directory('/tmp/awiki-cli-rs2'),
          binary: File('/tmp/awiki-cli-rs2/target/debug/awiki-cli'),
          workspace: Directory('/tmp/peer-b'),
          reportDir: Directory('/tmp/report'),
          runner: fakeRunner,
          dryRun: false,
          envReader: (name) => switch (name) {
            'AWIKI_E2E_PEER_PHONE' => '+8610011110001',
            'AWIKI_E2E_PEER_OTP' => '987580',
            _ => null,
          },
        );
        File('/tmp/peer-b/config.yaml')
          ..createSync(recursive: true)
          ..writeAsStringSync("""
service_base_url: https://old.example
did_domain: old.example
anp_service_endpoint: https://old.example/anp-im/rpc
anp_service_did: did:wba:old.example
mail_service_url: https://old.example
""");
        addTearDown(() {
          final dir = Directory('/tmp/peer-b');
          if (dir.existsSync()) {
            dir.deleteSync(recursive: true);
          }
        });

        final result = await adapter.runOrdinaryMessageFlow(
          runId: 'run_cli_002',
          targetHandle: config.accounts.appUser.handle,
          messageText: 'Agent IM E2E ordinary message runId=run_cli_002',
        );

        expect(fakeRunner.calls, hasLength(5));
        expect(
          fakeRunner.calls.first.environment['AWIKI_CLI_WORKSPACE_HOME_DIR'],
          '/tmp/peer-b',
        );
        expect(
          fakeRunner.calls[1].args,
          containsAll(<String>['id', 'recover']),
        );
        expect(fakeRunner.calls[1].args, contains('+8610011110001'));
        expect(
          fakeRunner.calls.last.args,
          containsAll(<String>['msg', 'send']),
        );
        expect(result.toJson().toString(), contains('msg-run'));
        expect(result.toJson().toString(), isNot(contains('+8610011110001')));
        expect(result.toJson().toString(), isNot(contains('987580')));
      },
    );

    test('requires peer secrets for real CLI flow only', () async {
      final config = AgentImDelegatedConfig.load(
        File('tests/e2e_test/configs/agent_im_delegated.example.yaml'),
      );
      final adapter = AgentImCliPeerAdapter(
        config: config,
        cliRepo: Directory('/tmp/awiki-cli-rs2'),
        binary: File('/tmp/awiki-cli-rs2/target/debug/awiki-cli'),
        workspace: Directory('/tmp/peer-b-missing'),
        reportDir: Directory('/tmp/report'),
        runner: _FakeCliRunner(),
        dryRun: false,
        envReader: (_) => null,
      );

      expect(
        adapter.loginOrRestorePeer,
        throwsA(
          isA<AgentImCliPeerFailure>().having(
            (error) => error.message,
            'message',
            contains('AWIKI_E2E_PEER_PHONE'),
          ),
        ),
      );
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

class _FakeCliRunner implements AgentImCliCommandRunner {
  final calls = <_FakeCliCall>[];

  @override
  Future<AgentImCliCommandResult> run(
    String executable,
    List<String> args, {
    required Directory workingDirectory,
    Map<String, String>? environment,
    File? logFile,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    calls.add(
      _FakeCliCall(
        executable: executable,
        args: List<String>.from(args),
        workingDirectory: workingDirectory.path,
        environment: Map<String, String>.from(environment ?? const {}),
        logFile: logFile?.path,
        timeout: timeout,
      ),
    );
    return const AgentImCliCommandResult(
      exitCode: 0,
      stdoutText:
          '{"ok":true,"data":{"message":{"id":"msg-run","secure":false}}}',
      stderrText: '',
    );
  }
}

class _FakeCliCall {
  const _FakeCliCall({
    required this.executable,
    required this.args,
    required this.workingDirectory,
    required this.environment,
    required this.logFile,
    required this.timeout,
  });

  final String executable;
  final List<String> args;
  final String workingDirectory;
  final Map<String, String> environment;
  final String? logFile;
  final Duration timeout;
}
