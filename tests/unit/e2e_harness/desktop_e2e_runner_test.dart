import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/case_attestation.dart';
import '../../e2e/runner.dart';

void main() {
  group('DesktopE2eOptions', () {
    test('parses run-control options only', () {
      final options = DesktopE2eOptions.parse(const <String>[
        '--dry-run',
        '--prepare-only',
        '--case',
        'full',
        '--config',
        'tests/e2e/configs/custom.local.yaml',
        '--run-id',
        'run123',
      ]);

      expect(options.dryRun, isTrue);
      expect(options.prepareOnly, isTrue);
      expect(options.configPath, 'tests/e2e/configs/custom.local.yaml');
      expect(options.runId, 'run123');
      expect(options.e2eCase, DesktopE2eCase.full);
    });

    test('parses group-only case', () {
      final options = DesktopE2eOptions.parse(const <String>[
        '--case',
        'group',
        '--dry-run',
      ]);

      expect(options.e2eCase, DesktopE2eCase.group);
    });

    test('parses direct attachment and contacts cases', () {
      final direct = DesktopE2eOptions.parse(const <String>[
        '--case',
        'direct',
        '--dry-run',
      ]);
      final attachment = DesktopE2eOptions.parse(const <String>[
        '--case',
        'attachment',
        '--dry-run',
      ]);
      final contacts = DesktopE2eOptions.parse(const <String>[
        '--case',
        'contacts',
        '--dry-run',
      ]);

      expect(direct.e2eCase, DesktopE2eCase.direct);
      expect(attachment.e2eCase, DesktopE2eCase.attachment);
      expect(contacts.e2eCase, DesktopE2eCase.contacts);
    });

    test('parses performance case aliases', () {
      final performance = DesktopE2eOptions.parse(const <String>[
        '--case',
        'performance',
        '--dry-run',
      ]);
      final perf = DesktopE2eOptions.parse(const <String>[
        '--case',
        'perf',
        '--dry-run',
      ]);

      expect(performance.e2eCase, DesktopE2eCase.performance);
      expect(perf.e2eCase, DesktopE2eCase.performance);
      expect(performance.e2eCase.caseName, 'performance');
      expect(performance.e2eCase.scenario, 'desktop-app-cli-peer-performance');
      expect(performance.e2eCase.runConfigPath, contains('desktop-cli-peer'));
    });

    test('parses message-agent case aliases', () {
      final hyphen = DesktopE2eOptions.parse(const <String>[
        '--case',
        'message-agent',
        '--dry-run',
      ]);
      final underscore = DesktopE2eOptions.parse(const <String>[
        '--case',
        'message_agent',
        '--dry-run',
      ]);

      expect(hyphen.e2eCase, DesktopE2eCase.messageAgent);
      expect(underscore.e2eCase, DesktopE2eCase.messageAgent);
      expect(hyphen.e2eCase.caseName, 'message-agent');
      expect(hyphen.e2eCase.reportScope, 'message-agent');
      expect(hyphen.e2eCase.runConfigPath, contains('message-agent'));
    });

    test('parses codex-agent case aliases', () {
      final hyphen = DesktopE2eOptions.parse(const <String>[
        '--case',
        'codex-agent',
        '--dry-run',
      ]);
      final underscore = DesktopE2eOptions.parse(const <String>[
        '--case',
        'codex_agent',
        '--dry-run',
      ]);

      expect(hyphen.e2eCase, DesktopE2eCase.codexAgent);
      expect(underscore.e2eCase, DesktopE2eCase.codexAgent);
      expect(hyphen.e2eCase.caseName, 'codex-agent');
      expect(hyphen.e2eCase.reportScope, 'codex-agent');
      expect(hyphen.e2eCase.runConfigPath, contains('codex-agent'));
    });

    test('parses claude-code-agent case aliases', () {
      final hyphen = DesktopE2eOptions.parse(const <String>[
        '--case',
        'claude-code-agent',
        '--dry-run',
      ]);
      final underscore = DesktopE2eOptions.parse(const <String>[
        '--case',
        'claude_code_agent',
        '--dry-run',
      ]);

      expect(hyphen.e2eCase, DesktopE2eCase.claudeCodeAgent);
      expect(underscore.e2eCase, DesktopE2eCase.claudeCodeAgent);
      expect(hyphen.e2eCase.caseName, 'claude-code-agent');
      expect(hyphen.e2eCase.reportScope, 'claude-code-agent');
      expect(hyphen.e2eCase.runConfigPath, contains('claude-code-agent'));
    });

    test('rejects unsupported case', () {
      expect(
        () => DesktopE2eOptions.parse(const <String>['--case', 'unknown']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'Unsupported E2E case "unknown". '
                'Use smoke, full, performance, direct, group, attachment, contacts, '
                'message-agent, codex-agent, or claude-code-agent.',
          ),
        ),
      );
    });

    test('rejects configuration values on the command line', () {
      expect(
        () => DesktopE2eOptions.parse(const <String>['--platform', 'linux']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'Unknown argument: --platform',
          ),
        ),
      );
    });

    test('reports missing values and unknown arguments', () {
      expect(
        () => DesktopE2eOptions.parse(const <String>['--config']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            '--config requires a value.',
          ),
        ),
      );
      expect(
        () => DesktopE2eOptions.parse(const <String>['--unknown']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'Unknown argument: --unknown',
          ),
        ),
      );
    });
  });

  group('CLI build provenance', () {
    const commit = 'abcdefabcdefabcdefabcdefabcdefabcdefabcd';

    test('reads the embedded commit from version JSON', () {
      expect(
        cliBuildCommitFromVersionJson(
          jsonEncode(<String, Object?>{
            'ok': true,
            'data': <String, Object?>{'commit': commit},
          }),
        ),
        commit,
      );
    });

    test('rejects unknown or malformed embedded commits', () {
      expect(
        () => cliBuildCommitFromVersionJson(
          jsonEncode(<String, Object?>{
            'ok': true,
            'data': <String, Object?>{'commit': 'unknown'},
          }),
        ),
        throwsA(isA<E2eFailure>()),
      );
      expect(
        () => cliBuildCommitFromVersionJson('not-json'),
        throwsA(isA<E2eFailure>()),
      );
    });
  });

  group('DesktopE2eFileConfig', () {
    test('loads minimal local YAML config', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_config_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final configFile = File('${root.path}/tests/e2e/configs/e2e.local.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
platform: macos
service:
  baseUrl: https://service.example.test
  didDomain: example.test
  userServiceUrl: https://users.example.test
  messageServiceUrl: https://messages.example.test
  messageServiceWsUrl: wss://messages.example.test/im/ws
  mailServiceUrl: https://mail.example.test
  anpServiceUrl: https://service.example.test/anp-im/rpc
  anpServiceDid: did:wba:example.test
daemon:
  rustRepo: ../awiki-cli-rs2-message-agent
  binary: ../awiki-cli-rs2-message-agent/target/release/awiki-deamon
  stateRoot: .e2e/daemon-state
  readyFile: .e2e/daemon-ready.json
  envFile: .e2e/agent-cli.env
  handle: daemon-from-file
  fakeHermesGatewayCommand: python3 fake_hermes_gateway.py
messageAgent:
  enabled: true
  runtimeProvider: hermes
  processingScope: all_conversations
  realBackend: true
otp:
  phone: test-phone-secret
  code: test-otp-secret
accounts:
  appUser:
    handle: app-from-file
  cliPeer:
    handle: cli-from-file
cliPeer:
  binary: ../awiki-cli-rs2/target/release/awiki-cli
''');

      final config = DesktopE2eFileConfig.load(
        root: root,
        path: 'tests/e2e/configs/e2e.local.yaml',
      );

      expect(config.path, configFile.path);
      expect(config.platform, DesktopE2ePlatform.macos);
      expect(config.serviceBaseUrl, 'https://service.example.test');
      expect(config.userServiceUrl, 'https://users.example.test');
      expect(config.messageServiceUrl, 'https://messages.example.test');
      expect(config.messageServiceWsUrl, 'wss://messages.example.test/im/ws');
      expect(config.mailServiceUrl, 'https://mail.example.test');
      expect(config.didDomain, 'example.test');
      expect(config.anpServiceUrl, 'https://service.example.test/anp-im/rpc');
      expect(config.anpServiceDid, 'did:wba:example.test');
      expect(config.daemonRustRepo, '../awiki-cli-rs2-message-agent');
      expect(
        config.daemonBinary,
        '${root.path}/../awiki-cli-rs2-message-agent/target/release/awiki-deamon',
      );
      expect(config.daemonStateRoot, '${root.path}/.e2e/daemon-state');
      expect(config.daemonReadyFile, '${root.path}/.e2e/daemon-ready.json');
      expect(config.daemonEnvFile, '${root.path}/.e2e/agent-cli.env');
      expect(config.daemonHandle, 'daemon-from-file');
      expect(
        config.daemonFakeHermesGatewayCommand,
        'python3 fake_hermes_gateway.py',
      );
      expect(config.messageAgentEnabled, isTrue);
      expect(config.messageAgentRuntimeProvider, 'hermes');
      expect(config.messageAgentProcessingScope, 'all_conversations');
      expect(config.messageAgentRealBackend, isTrue);
      expect(config.otpPhone, 'test-phone-secret');
      expect(config.otpCode, 'test-otp-secret');
      expect(config.appHandle, 'app-from-file');
      expect(config.cliHandle, 'cli-from-file');
      expect(
        config.cliBin,
        '${root.path}/../awiki-cli-rs2/target/release/awiki-cli',
      );
    });

    test('ignores removed legacy YAML keys', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_legacy_config_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final configFile = File('${root.path}/legacy.yaml')
        ..writeAsStringSync('''
serviceBaseUrl: https://legacy-service.example.test
didDomain: legacy.example.test
accounts:
  appUser:
    phone: test-phone-secret
    otp: test-otp-secret
    handle: app-from-file
  peerUser:
    handle: cli-from-peer-user
cliPeer:
  repo: ../awiki-cli-rs2
  binary: target/debug/awiki-cli
otpPhone: legacy-phone
otpCode: legacy-code
appHandle: legacy-app
cliHandle: legacy-cli
''');

      final config = DesktopE2eFileConfig.load(
        root: root,
        path: configFile.path,
      );

      expect(config.serviceBaseUrl, isNull);
      expect(config.didDomain, isNull);
      expect(config.otpPhone, isNull);
      expect(config.otpCode, isNull);
      expect(config.appHandle, 'app-from-file');
      expect(config.cliHandle, isNull);
      expect(config.cliBin, '${root.path}/target/debug/awiki-cli');
    });
  });

  group('DesktopCliPeerConfig', () {
    test('loads all E2E values from file config only', () {
      final config = DesktopCliPeerConfig.from(
        DesktopE2eOptions.parse(const <String>['--case', 'full']),
        const DesktopE2eFileConfig(
          path: '/tmp/e2e.local.yaml',
          platform: DesktopE2ePlatform.linux,
          serviceBaseUrl: 'https://service.example.test',
          userServiceUrl: 'https://users.example.test',
          messageServiceUrl: 'https://messages.example.test',
          messageServiceWsUrl: 'wss://messages.example.test/im/ws',
          mailServiceUrl: 'https://mail.example.test',
          didDomain: 'example.test',
          anpServiceUrl: 'https://service.example.test/anp-im/rpc',
          anpServiceDid: 'did:wba:example.test',
          daemonRustRepo: '../awiki-cli-rs2-message-agent',
          daemonBinary: '/tmp/awiki-deamon',
          daemonStateRoot: '/tmp/daemon-state',
          daemonReadyFile: '/tmp/daemon-ready.json',
          daemonEnvFile: '/tmp/agent-cli.env',
          daemonHandle: 'daemon-from-file',
          daemonFakeHermesGatewayCommand: 'python3 fake_hermes_gateway.py',
          messageAgentEnabled: true,
          messageAgentRuntimeProvider: 'hermes',
          messageAgentProcessingScope: 'all_conversations',
          messageAgentRealBackend: true,
          otpPhone: 'test-phone-secret',
          otpCode: 'test-otp-secret',
          appHandle: 'app-from-file',
          cliHandle: 'cli-from-file',
          cliBin: '/tmp/file-awiki-cli',
        ),
      );

      expect(config.platform, DesktopE2ePlatform.linux);
      expect(config.serviceBaseUrl, 'https://service.example.test');
      expect(config.userServiceUrl, 'https://users.example.test');
      expect(config.messageServiceUrl, 'https://messages.example.test');
      expect(config.messageServiceWsUrl, 'wss://messages.example.test/im/ws');
      expect(config.mailServiceUrl, 'https://mail.example.test');
      expect(config.didDomain, 'example.test');
      expect(config.anpServiceUrl, 'https://service.example.test/anp-im/rpc');
      expect(config.anpServiceDid, 'did:wba:example.test');
      expect(config.daemonRustRepo, '../awiki-cli-rs2-message-agent');
      expect(config.daemonBinary, '/tmp/awiki-deamon');
      expect(config.daemonStateRoot, '/tmp/daemon-state');
      expect(config.daemonReadyFile, '/tmp/daemon-ready.json');
      expect(config.daemonEnvFile, '/tmp/agent-cli.env');
      expect(config.daemonHandle, 'daemon-from-file');
      expect(
        config.daemonFakeHermesGatewayCommand,
        'python3 fake_hermes_gateway.py',
      );
      expect(config.messageAgentEnabled, isTrue);
      expect(config.messageAgentRuntimeProvider, 'hermes');
      expect(config.messageAgentProcessingScope, 'all_conversations');
      expect(config.messageAgentRealBackend, isTrue);
      expect(config.otpPhone, 'test-phone-secret');
      expect(config.otpCode, 'test-otp-secret');
      expect(config.appHandle, 'app-from-file');
      expect(config.cliHandle, 'cli-from-file');
      expect(config.cliBin, '/tmp/file-awiki-cli');
    });

    test('requires the local config file for real App + CLI peer cases', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopE2eOptions.parse(const <String>['--case', 'full']),
          const DesktopE2eFileConfig.empty(),
        ),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'E2E config file was not found: tests/e2e/configs/e2e.local.yaml',
          ),
        ),
      );
    });

    test('requires complete file config values', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopE2eOptions.parse(const <String>['--case', 'full']),
          const DesktopE2eFileConfig(
            path: '/tmp/e2e.local.yaml',
            didDomain: 'example.test',
          ),
        ),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'service.baseUrl is required in /tmp/e2e.local.yaml.',
          ),
        ),
      );
    });

    test('requires different App and CLI handles', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopE2eOptions.parse(const <String>['--case', 'full']),
          const DesktopE2eFileConfig(
            path: '/tmp/e2e.local.yaml',
            serviceBaseUrl: 'https://service.example.test',
            didDomain: 'example.test',
            otpPhone: 'test-phone-secret',
            otpCode: 'test-otp-secret',
            appHandle: 'same',
            cliHandle: 'Same',
            cliBin: '/tmp/file-awiki-cli',
          ),
        ),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'App handle and CLI handle must differ.',
          ),
        ),
      );
    });

    test('defaults message-agent case to enabled when YAML omits it', () {
      final config = DesktopCliPeerConfig.from(
        DesktopE2eOptions.parse(const <String>['--case', 'message-agent']),
        const DesktopE2eFileConfig(
          path: '/tmp/e2e.local.yaml',
          platform: DesktopE2ePlatform.linux,
          serviceBaseUrl: 'https://service.example.test',
          didDomain: 'example.test',
          otpPhone: 'test-phone-secret',
          otpCode: 'test-otp-secret',
          appHandle: 'app-from-file',
          cliHandle: 'cli-from-file',
          cliBin: '/tmp/file-awiki-cli',
        ),
      );

      expect(config.messageAgentEnabled, isTrue);
    });

    test('rejects message-agent case when YAML disables it', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopE2eOptions.parse(const <String>['--case', 'message-agent']),
          const DesktopE2eFileConfig(
            path: '/tmp/e2e.local.yaml',
            platform: DesktopE2ePlatform.linux,
            serviceBaseUrl: 'https://service.example.test',
            didDomain: 'example.test',
            messageAgentEnabled: false,
            otpPhone: 'test-phone-secret',
            otpCode: 'test-otp-secret',
            appHandle: 'app-from-file',
            cliHandle: 'cli-from-file',
            cliBin: '/tmp/file-awiki-cli',
          ),
        ),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'messageAgent.enabled must be true for --case message-agent '
                'in /tmp/e2e.local.yaml.',
          ),
        ),
      );
    });

    test('keeps non-message-agent cases disabled by default', () {
      final config = DesktopCliPeerConfig.from(
        DesktopE2eOptions.parse(const <String>['--case', 'full']),
        const DesktopE2eFileConfig(
          path: '/tmp/e2e.local.yaml',
          platform: DesktopE2ePlatform.linux,
          serviceBaseUrl: 'https://service.example.test',
          didDomain: 'example.test',
          otpPhone: 'test-phone-secret',
          otpCode: 'test-otp-secret',
          appHandle: 'app-from-file',
          cliHandle: 'cli-from-file',
          cliBin: '/tmp/file-awiki-cli',
        ),
      );

      expect(config.messageAgentEnabled, isFalse);
    });

    test('defaults codex-agent case to enabled real backend', () {
      final config = DesktopCliPeerConfig.from(
        DesktopE2eOptions.parse(const <String>['--case', 'codex-agent']),
        const DesktopE2eFileConfig(
          path: '/tmp/e2e.local.yaml',
          platform: DesktopE2ePlatform.linux,
          serviceBaseUrl: 'https://service.example.test',
          didDomain: 'example.test',
          otpPhone: 'test-phone-secret',
          otpCode: 'test-otp-secret',
          appHandle: 'app-from-file',
          cliHandle: 'cli-from-file',
          cliBin: '/tmp/file-awiki-cli',
        ),
      );

      expect(config.codexAgentEnabled, isTrue);
      expect(config.codexAgentRealBackend, isTrue);
    });

    test('rejects codex-agent case when YAML disables it', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopE2eOptions.parse(const <String>['--case', 'codex-agent']),
          const DesktopE2eFileConfig(
            path: '/tmp/e2e.local.yaml',
            platform: DesktopE2ePlatform.linux,
            serviceBaseUrl: 'https://service.example.test',
            didDomain: 'example.test',
            codexAgentEnabled: false,
            otpPhone: 'test-phone-secret',
            otpCode: 'test-otp-secret',
            appHandle: 'app-from-file',
            cliHandle: 'cli-from-file',
            cliBin: '/tmp/file-awiki-cli',
          ),
        ),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'codexAgent.enabled must be true for --case codex-agent '
                'in /tmp/e2e.local.yaml.',
          ),
        ),
      );
    });

    test('defaults claude-code-agent case to enabled real backend', () {
      final config = DesktopCliPeerConfig.from(
        DesktopE2eOptions.parse(const <String>['--case', 'claude-code-agent']),
        const DesktopE2eFileConfig(
          path: '/tmp/e2e.local.yaml',
          platform: DesktopE2ePlatform.linux,
          serviceBaseUrl: 'https://service.example.test',
          didDomain: 'example.test',
          otpPhone: 'test-phone-secret',
          otpCode: 'test-otp-secret',
          appHandle: 'app-from-file',
          cliHandle: 'cli-from-file',
          cliBin: '/tmp/file-awiki-cli',
        ),
      );

      expect(config.claudeCodeAgentEnabled, isTrue);
      expect(config.claudeCodeAgentRealBackend, isTrue);
    });

    test('rejects claude-code-agent case when YAML disables it', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopE2eOptions.parse(const <String>[
            '--case',
            'claude-code-agent',
          ]),
          const DesktopE2eFileConfig(
            path: '/tmp/e2e.local.yaml',
            platform: DesktopE2ePlatform.linux,
            serviceBaseUrl: 'https://service.example.test',
            didDomain: 'example.test',
            claudeCodeAgentEnabled: false,
            otpPhone: 'test-phone-secret',
            otpCode: 'test-otp-secret',
            appHandle: 'app-from-file',
            cliHandle: 'cli-from-file',
            cliBin: '/tmp/file-awiki-cli',
          ),
        ),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'claudeCodeAgent.enabled must be true for --case '
                'claude-code-agent in /tmp/e2e.local.yaml.',
          ),
        ),
      );
    });
  });

  group('Desktop E2E gate governance', () {
    test('checked-in manifest matches every runner case contract', () {
      final manifest = DesktopE2eSuiteManifest.load(Directory.current);

      expect(manifest.schemaVersion, 1);
      expect(manifest.sourceRevision, isNotEmpty);
      for (final e2eCase in DesktopE2eCase.values) {
        final definition = manifest.definitionFor(e2eCase);
        expect(
          () => definition.validateCodeCaseIds(e2eCase.caseIds),
          returnsNormally,
        );
        expect(definition.owner, isNotEmpty);
        expect(definition.timeout, isNot(Duration.zero));
      }
    });

    test('remote product suites reject local or non-audited targets', () {
      final definition = DesktopE2eSuiteManifest.load(
        Directory.current,
      ).definitionFor(DesktopE2eCase.full);
      final config = DesktopCliPeerConfig(
        platform: DesktopE2ePlatform.macos,
        serviceBaseUrl: 'http://127.0.0.1:9800',
        didDomain: 'awiki.test',
        otpPhone: 'redacted',
        otpCode: 'redacted',
        appHandle: 'app',
        cliHandle: 'cli',
        cliBin: '/tmp/awiki-cli',
        cliSourceRef: '1111111111111111111111111111111111111111',
        e2eCase: DesktopE2eCase.full,
        performance: DesktopPerformanceConfig.defaults,
      );

      expect(
        () => definition.validateRemoteTarget(config),
        throwsA(isA<E2eFailure>()),
      );
    });

    test('real source ref requires an exact non-zero commit SHA', () {
      expect(
        isAuditableGitSha('1111111111111111111111111111111111111111'),
        isTrue,
      );
      expect(
        isAuditableGitSha('0000000000000000000000000000000000000000'),
        isFalse,
      );
      expect(isAuditableGitSha('release/0710'), isFalse);
    });

    test('redactor removes full DIDs from diagnostics', () {
      final redactor = DesktopSecretRedactor(const <String>[]);

      final output = redactor.redact(
        'sender=did:wba:awiki.info:user:alice:e1_sensitive failed',
      );

      expect(output, contains('<redacted-did>'));
      expect(output, isNot(contains('e1_sensitive')));
    });

    test('detects competing Flutter integration tests from ps output', () {
      final pids = competingFlutterIntegrationTestPidsFromPs('''
  101 dart flutter_tools.snapshot test integration_test/app_smoke_test.dart -d macos
  102 dart flutter_tools.snapshot build macos
  103 dart flutter_tools.snapshot test tests/unit/example_test.dart
''');

      expect(pids, <int>[101]);
    });

    test('scenario progress is colocated with strict attestation', () {
      final progress = e2eScenarioProgressFileForAttestation(
        File('/tmp/e2e/reports/case_attestation.json'),
      );

      expect(progress.path, '/tmp/e2e/reports/scenario_progress.json');
    });

    test('failed command writes redacted durable diagnostics', () async {
      if (Platform.isWindows) {
        return;
      }
      final root = await Directory.systemTemp.createTemp(
        'awiki_e2e_diagnostics_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final reports = Directory('${root.path}/reports');
      final runner = DesktopCommandRunner(
        root: root,
        dryRun: false,
        redactor: DesktopSecretRedactor(const <String>['super-secret']),
      )..diagnosticDirectory = reports;

      await expectLater(
        runner.captureResult('/bin/sh', const <String>[
          '-c',
          'echo super-secret; echo failed >&2; exit 79',
        ]),
        throwsA(isA<E2eFailure>()),
      );

      final metadata =
          jsonDecode(
                File(
                  '${reports.path}/command-failure-001.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(metadata['exitCode'], 79);
      expect(
        File(
          '${reports.path}/command-failure-001.stdout.log',
        ).readAsStringSync(),
        contains('<redacted>'),
      );
      expect(
        File(
          '${reports.path}/command-failure-001.stdout.log',
        ).readAsStringSync(),
        isNot(contains('super-secret')),
      );
    });

    test('command timeout terminates the spawned process tree', () async {
      if (Platform.isWindows) {
        return;
      }
      final root = await Directory.systemTemp.createTemp(
        'awiki_e2e_timeout_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final pidFile = File('${root.path}/pids.txt');
      final runner = DesktopCommandRunner(
        root: root,
        dryRun: false,
        redactor: DesktopSecretRedactor(<String>[root.path]),
      );

      await expectLater(
        runner.captureResult('/bin/sh', <String>[
          '-c',
          'sleep 30 & child=\$!; echo "\$\$ \$child" > "${pidFile.path}"; wait',
        ], timeout: const Duration(milliseconds: 200)),
        throwsA(
          isA<DesktopCommandTimeout>()
              .having((error) => error.terminated, 'terminated', isTrue)
              .having(
                (error) => error.safeSummary,
                'safeSummary',
                isNot(contains(root.path)),
              ),
        ),
      );

      final pids = pidFile
          .readAsStringSync()
          .trim()
          .split(RegExp(r'\s+'))
          .map(int.parse)
          .toList();
      for (final pid in pids) {
        var alive = true;
        for (var attempt = 0; attempt < 20 && alive; attempt += 1) {
          final probe = await Process.run('/bin/kill', <String>['-0', '$pid']);
          alive = probe.exitCode == 0;
          if (alive) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
        expect(alive, isFalse, reason: 'timed-out pid $pid must not survive');
      }
    });
  });

  group('DesktopE2eRunner dry-run', () {
    test('loads full E2E settings from default local config', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_file_runner_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      File('${root.path}/tests/e2e/configs/e2e.local.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
platform: linux
service:
  baseUrl: https://service.example.test
  didDomain: example.test
otp:
  phone: test-phone-secret
  code: test-otp-secret
accounts:
  appUser:
    handle: app-from-file
  cliPeer:
    handle: cli-from-file
cliPeer:
  binary: /tmp/file-awiki-cli
''');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--case',
          'full',
          '--dry-run',
          '--run-id',
          'run-file',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(log, contains('platform: linux'));
      expect(log, contains('app handle: app-from-file'));
      expect(log, contains('cli handle: cli-from-file'));
      expect(log, contains('service base: https://service.example.test'));
      expect(log, contains('check file: <redacted>'));
      expect(
        log,
        contains(
          r'$ <redacted> --format json id recover --handle cli-from-file --phone <redacted> --otp <redacted>',
        ),
      );
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_smoke_test.dart -d linux',
        ),
      );
      expect(log, contains('would write Flutter E2E run config: <redacted>'));
      expect(log, isNot(contains('test-phone-secret')));
      expect(log, isNot(contains('test-otp-secret')));

      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run-file/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['case'], 'full');
      expect(decoded['platform'], 'linux');
      expect(decoded['appHandle'], 'app-from-file');
      expect(decoded['cliHandle'], 'cli-from-file');
      expect(decoded['serviceBaseUrl'], 'https://service.example.test');
      expect(decoded['didDomain'], 'example.test');
      expect(decoded['configPath'], isNotNull);
    });

    test('default smoke runs local App and native checks only', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_smoke_runner_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--dry-run',
          '--run-id',
          'run-smoke',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(log, contains('case: smoke'));
      if (Platform.isLinux) {
        expect(
          log,
          contains(
            r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/app_smoke_test.dart -d linux',
          ),
        );
        expect(
          log,
          contains(
            r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/im_core_open_smoke_test.dart -d linux',
          ),
        );
      } else {
        expect(
          log,
          contains(
            r'$ flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/app_smoke_test.dart -d macos',
          ),
        );
        expect(
          log,
          contains(
            r'$ flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/im_core_open_smoke_test.dart -d macos',
          ),
        );
      }
      expect(log, isNot(contains('fake-awiki-cli')));
      expect(log, isNot(contains('DEV_OTP')));
      final timings = File(
        '${root.path}/.e2e/smoke/run-smoke/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['case'], 'smoke');
      expect(decoded['platform'], Platform.isLinux ? 'linux' : 'macos');
      expect(decoded['caseIds'], <dynamic>['SMOKE-E2E-001', 'NATIVE-E2E-001']);
    });

    test('generates Linux commands and redacts secrets', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(
        root,
        platform: 'linux',
        appHandle: 'e2e-app',
        cliHandle: 'e2e-cli',
        cliBin: '/tmp/fake-awiki-cli',
        messageServiceUrl: 'https://messages.example.test',
      );
      final lines = <String>[];
      final options = DesktopE2eOptions.parse(const <String>[
        '--dry-run',
        '--case',
        'full',
        '--run-id',
        'run123',
      ]);
      final runner = DesktopE2eRunner(
        root: root,
        options: options,
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(
        lines,
        containsAllInOrder(const <String>[
          r'$ which flutter',
          'flutter: dry-run',
          r'$ which xvfb-run',
          'xvfb-run: dry-run',
          'check file: <redacted>',
          r'$ <redacted> --format json init',
          r'$ <redacted> --format json config show',
          r'$ <redacted> --format json id recover --handle e2e-cli --phone <redacted> --otp <redacted>',
          r'$ <redacted> --format json id current',
          r'$ <redacted> --format json id status',
          r'$ <redacted> --format json msg inbox --limit 1',
        ]),
      );
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_smoke_test.dart -d linux',
        ),
      );
      expect(log, contains('would write Flutter E2E run config: <redacted>'));
      expect(log, contains('tenant_backend=https://service.example.test'));
      expect(log, isNot(contains('test-phone-secret')));
      expect(log, isNot(contains('test-otp-secret')));
      expect(log, isNot(contains(root.path)));
      expect(log, isNot(contains('../awiki-cli-rs2/cargo')));
      expect(log, contains('<redacted>'));

      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run123/reports/timings.json',
      );
      expect(timings.existsSync(), isTrue);
      final timingText = await timings.readAsString();
      expect(timingText, isNot(contains('test-phone-secret')));
      expect(timingText, isNot(contains('test-otp-secret')));
      expect(timingText, isNot(contains(root.path)));
      final decoded = jsonDecode(timingText) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 2);
      expect(decoded['status'], 'dry_run');
      expect(decoded['mode'], 'dry_run');
      expect(decoded['scenario'], 'desktop-app-cli-peer');
      expect(decoded['case'], 'full');
      expect(decoded['caseIds'], <dynamic>[
        'AUTH-E2E-001',
        'MSG-E2E-001',
        'MSG-E2E-002',
        'MSG-REG-001',
        'GROUP-E2E-001',
        'GROUP-E2E-002',
        'GROUP-P9-001',
        'GROUP-P9-002',
        'GROUP-REG-001',
        'CONTACT-E2E-001',
        'CONTACT-E2E-002',
        'CONTACT-REG-001',
        'CONTACT-MSG-E2E-001',
        'ATTACH-E2E-001',
        'ATTACH-E2E-002',
        'ATTACH-REG-001',
      ]);
      expect(decoded['runId'], 'run123');
      expect(decoded['platform'], 'linux');
      expect(decoded['dryRun'], isTrue);
      expect(decoded['prepareOnly'], isFalse);
      final caseResults = decoded['caseResults'] as List<dynamic>;
      expect(caseResults, hasLength(16));
      expect(
        caseResults.every(
          (value) =>
              (value as Map<String, dynamic>)['status'] == 'dry_run' &&
              value['mode'] == 'dry_run',
        ),
        isTrue,
      );
      expect(decoded['passedCaseIds'], isEmpty);
      expect(
        (decoded['attestation'] as Map<String, dynamic>)['status'],
        'not_expected_dry_run',
      );
      expect(decoded['appHandle'], 'e2e-app');
      expect(decoded['cliHandle'], 'e2e-cli');
      expect(decoded['serviceBaseUrl'], 'https://service.example.test');
      expect(decoded['userServiceUrl'], 'https://service.example.test');
      expect(decoded['messageServiceUrl'], 'https://messages.example.test');
      expect(decoded['cliWorkspace'], '<redacted-workspace>');
      expect(decoded['cliHome'], '<redacted-home>');
      expect(decoded['appStateRoot'], '<redacted-app-state>');
      expect(decoded['configPath'], '<redacted-config-path>');
    });

    test(
      'writes Flutter run config from YAML before starting full E2E',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki_desktop_cli_peer_run_config_test_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        _writeLocalConfig(
          root,
          platform: 'macos',
          appHandle: 'e2e-app',
          cliHandle: 'e2e-cli',
          cliBin: '/tmp/fake-awiki-cli',
          messageServiceUrl: 'https://messages.example.test',
        );
        final lines = <String>[];
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse(const <String>[
            '--case',
            'full',
            '--dry-run',
            '--run-id',
            'run-config',
          ]),
          commands: DesktopCommandRunner(
            root: root,
            dryRun: true,
            redactor: DesktopSecretRedactor(const <String>[
              'test-phone-secret',
              'test-otp-secret',
            ]),
            logLine: lines.add,
          ),
        );

        await runner.run();

        final runConfig = File(
          '${root.path}/.e2e/desktop-cli-peer/current/run_config.json',
        );
        expect(runConfig.existsSync(), isTrue);
        final decoded =
            jsonDecode(await runConfig.readAsString()) as Map<String, dynamic>;
        expect(decoded['enabled'], isTrue);
        expect(decoded['runId'], 'run-config');
        expect(decoded['case'], 'full');
        expect(decoded['platform'], 'macos');
        expect(decoded['service'], isA<Map<String, dynamic>>());
        expect(decoded['otp'], isA<Map<String, dynamic>>());
        expect(decoded['accounts'], isA<Map<String, dynamic>>());
        expect(decoded['cliPeer'], isA<Map<String, dynamic>>());
        expect(decoded['app'], isA<Map<String, dynamic>>());
        final service = decoded['service'] as Map<String, dynamic>;
        expect(service['baseUrl'], 'https://service.example.test');
        expect(service['messageServiceUrl'], 'https://messages.example.test');
        final otp = decoded['otp'] as Map<String, dynamic>;
        expect(otp['phone'], 'test-phone-secret');
        expect(otp['code'], 'test-otp-secret');
        final accounts = decoded['accounts'] as Map<String, dynamic>;
        expect(
          (accounts['appUser'] as Map<String, dynamic>)['handle'],
          'e2e-app',
        );
        expect(
          (accounts['cliPeer'] as Map<String, dynamic>)['handle'],
          'e2e-cli',
        );
        final log = lines.join('\n');
        expect(log, isNot(contains('test-phone-secret')));
        expect(log, isNot(contains('test-otp-secret')));
      },
    );

    test(
      'fails closed when Flutter exits successfully without case attestation',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki_desktop_missing_attestation_test_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        _writeLocalConfig(root, platform: 'macos');
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse(const <String>[
            '--case',
            'direct',
            '--run-id',
            'run-missing-attestation',
          ]),
          commands: DesktopCommandRunner(
            root: root,
            dryRun: true,
            redactor: DesktopSecretRedactor(const <String>[]),
          ),
        );

        await expectLater(
          runner.run(),
          throwsA(
            isA<E2eFailure>().having(
              (error) => error.message,
              'message',
              contains('case attestation failed closed'),
            ),
          ),
        );

        final report = File(
          '${root.path}/.e2e/desktop-cli-peer/'
          'run-missing-attestation/reports/timings.json',
        );
        final decoded =
            jsonDecode(await report.readAsString()) as Map<String, dynamic>;
        expect(decoded['schemaVersion'], 2);
        expect(decoded['status'], 'failed');
        expect(decoded['mode'], 'real');
        expect(decoded['passedCaseIds'], isEmpty);
        expect(
          (decoded['caseResults'] as List<dynamic>).every(
            (value) => (value as Map<String, dynamic>)['status'] == 'not_run',
          ),
          isTrue,
        );
        expect(
          (decoded['attestation'] as Map<String, dynamic>)['status'],
          'invalid',
        );
      },
    );

    test('generates group-only Flutter command and report case IDs', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_group_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(root, platform: 'macos');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--dry-run',
          '--case',
          'group',
          '--run-id',
          'run-group',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(
        log,
        contains(
          r'$ flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_group_test.dart -d macos',
        ),
      );
      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run-group/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['case'], 'group');
      expect(decoded['caseIds'], <dynamic>[
        'AUTH-E2E-001',
        'GROUP-E2E-001',
        'GROUP-E2E-002',
        'GROUP-P9-001',
        'GROUP-P9-002',
        'GROUP-REG-001',
      ]);
    });

    test('generates direct-only Flutter command and report case IDs', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_direct_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(root, platform: 'linux');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--dry-run',
          '--case',
          'direct',
          '--run-id',
          'run-direct',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_direct_test.dart -d linux',
        ),
      );
      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run-direct/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['case'], 'direct');
      expect(decoded['caseIds'], <dynamic>[
        'AUTH-E2E-001',
        'MSG-E2E-001',
        'MSG-E2E-002',
        'MSG-REG-001',
      ]);
    });

    test(
      'generates performance Flutter command, budgets, and report schema',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki_desktop_cli_peer_runner_performance_test_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        _writeLocalConfig(
          root,
          platform: 'linux',
          performanceBlock: '''
performance:
  dataset:
    conversationCount: 12
    longThreadMessageCount: 8
  budgets:
    maxFullRefreshDuringSendReceive: 0
    hardBudgetMs:
      app.launch_to_shell_visible_ms: 30000
    softBudgetMs:
      conversation_list.first_non_empty_visible_ms: 3000
    requiredMetrics:
      - app.launch_to_shell_visible_ms
      - conversation_list.first_non_empty_visible_ms
''',
        );
        final lines = <String>[];
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse(const <String>[
            '--dry-run',
            '--case',
            'performance',
            '--run-id',
            'run-performance',
          ]),
          commands: DesktopCommandRunner(
            root: root,
            dryRun: true,
            redactor: DesktopSecretRedactor(const <String>[
              'test-phone-secret',
              'test-otp-secret',
            ]),
            logLine: lines.add,
          ),
        );

        await runner.run();

        final log = lines.join('\n');
        expect(
          log,
          contains(
            r'$ <redacted> --format json id recover --handle e2e-app --phone <redacted> --otp <redacted>',
          ),
        );
        expect(log, isNot(contains('Preparing performance dataset')));
        expect(
          log,
          contains(
            r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_performance_test.dart -d linux',
          ),
        );
        final runConfig = File(
          '${root.path}/.e2e/desktop-cli-peer/current/run_config.json',
        );
        final runConfigJson =
            jsonDecode(await runConfig.readAsString()) as Map<String, dynamic>;
        expect(runConfigJson['case'], 'performance');
        final performance =
            runConfigJson['performance'] as Map<String, dynamic>;
        expect(performance['enabled'], isTrue);
        expect(performance['datasetConversationCount'], 12);
        expect(performance['longThreadMessageCount'], 8);
        expect(
          performance['productTimingsPath'],
          contains('product_timings.json'),
        );
        final app = runConfigJson['app'] as Map<String, dynamic>;
        expect(
          app['stateRoot'],
          endsWith('/.e2e/desktop-cli-peer/run-performance/app'),
        );

        final timings = File(
          '${root.path}/.e2e/desktop-cli-peer/run-performance/reports/timings.json',
        );
        final decoded =
            jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
        expect(decoded['scenario'], 'desktop-app-cli-peer-performance');
        expect(decoded['case'], 'performance');
        expect(decoded['caseIds'], <dynamic>[
          'PERF-E2E-001',
          'PERF-E2E-002',
          'PERF-E2E-003',
          'PERF-E2E-004',
          'PERF-E2E-005',
          'PERF-E2E-006',
          'PERF-E2E-007',
          'PERF-E2E-008',
          'PERF-E2E-009',
          'PERF-E2E-010',
          'PERF-E2E-011',
          'PERF-E2E-012',
        ]);
        expect(decoded['dataset'], isA<Map<String, dynamic>>());
        expect(decoded['budgets'], isA<Map<String, dynamic>>());
        expect(decoded['hardFailures'], isEmpty);
        expect(decoded['softWarnings'], isEmpty);
        expect(decoded['toolingTimings'], isA<List<dynamic>>());
        final steps = decoded['steps'] as List<dynamic>;
        expect(
          steps.map((step) => (step as Map<String, dynamic>)['name']),
          containsAll(<String>[
            'Preparing performance App identity',
            'Flutter App + CLI peer flow',
          ]),
        );
      },
    );

    test('generates attachment-only Flutter command and report case IDs', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_attachment_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(root, platform: 'macos');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--dry-run',
          '--case',
          'attachment',
          '--run-id',
          'run-attachment',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(
        log,
        contains(
          r'$ flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_attachment_test.dart -d macos',
        ),
      );
      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run-attachment/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['case'], 'attachment');
      expect(decoded['caseIds'], <dynamic>[
        'AUTH-E2E-001',
        'ATTACH-E2E-001',
        'ATTACH-E2E-002',
        'ATTACH-REG-001',
      ]);
    });

    test('generates contacts-only Flutter command and report case IDs', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_contacts_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(root, platform: 'linux');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--dry-run',
          '--case',
          'contacts',
          '--run-id',
          'run-contacts',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_contacts_test.dart -d linux',
        ),
      );
      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run-contacts/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['case'], 'contacts');
      expect(decoded['caseIds'], <dynamic>[
        'AUTH-E2E-001',
        'CONTACT-E2E-001',
        'CONTACT-E2E-002',
        'CONTACT-REG-001',
        'CONTACT-MSG-E2E-001',
      ]);
    });

    test('generates message-agent Flutter command and report case IDs', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_message_agent_runner_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(
        root,
        platform: 'linux',
        appHandle: 'message-agent-app',
        cliHandle: 'message-agent-cli',
        cliBin: '/tmp/fake-awiki-cli',
        messageServiceUrl: 'https://messages.example.test',
        messageServiceWsUrl: 'wss://messages.example.test/im/ws',
        daemonRustRepo: '../awiki-cli-rs2-message-agent',
        daemonBinary: '/tmp/awiki-deamon',
        daemonStateRoot: '.e2e/daemon-state',
        daemonReadyFile: '.e2e/daemon-ready.json',
        daemonHandle: 'message-agent-daemon',
        fakeHermesGatewayCommand: 'python3 fake_hermes_gateway.py',
        messageAgentEnabled: true,
        messageAgentRealBackend: true,
      );
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--case',
          'message-agent',
          '--dry-run',
          '--run-id',
          'run-message-agent',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(log, contains('case: message-agent'));
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/message_agent_full_ui_test.dart -d linux',
        ),
      );
      expect(log, isNot(contains('test-phone-secret')));
      expect(log, isNot(contains('test-otp-secret')));

      final timings = File(
        '${root.path}/.e2e/message-agent/run-message-agent/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['scenario'], 'message-agent-full-ui');
      expect(decoded['case'], 'message-agent');
      expect(decoded['caseIds'], <dynamic>[
        'MSGAGENT-E2E-001',
        'MSGAGENT-E2E-002',
        'MSGAGENT-E2E-004',
      ]);
      expect(
        decoded['messageServiceWsUrl'],
        'wss://messages.example.test/im/ws',
      );
      expect(decoded['daemonRustRepo'], '<redacted-daemon-repo>');
      final messageAgent = decoded['messageAgent'] as Map<String, dynamic>;
      expect(messageAgent['enabled'], isTrue);
      expect(messageAgent['runtimeProvider'], 'hermes');
      expect(messageAgent['processingScope'], 'all_conversations');
      expect(messageAgent['realBackend'], isTrue);

      final runConfig = File(
        '${root.path}/.e2e/message-agent/current/run_config.json',
      );
      expect(runConfig.existsSync(), isTrue);
      final runConfigJson =
          jsonDecode(await runConfig.readAsString()) as Map<String, dynamic>;
      expect(runConfigJson['case'], 'message-agent');
      expect(runConfigJson['daemon'], isA<Map<String, dynamic>>());
      expect(runConfigJson['messageAgent'], isA<Map<String, dynamic>>());
      final daemon = runConfigJson['daemon'] as Map<String, dynamic>;
      expect(daemon['rustRepo'], '../awiki-cli-rs2-message-agent');
      expect(daemon['binary'], '/tmp/awiki-deamon');
      expect(daemon['stateRoot'], '${root.path}/.e2e/daemon-state');
      expect(daemon['readyFile'], '${root.path}/.e2e/daemon-ready.json');
      expect(daemon['handle'], 'message-agent-daemon');
      expect(
        daemon['fakeHermesGatewayCommand'],
        'python3 fake_hermes_gateway.py',
      );
      final runMessageAgent =
          runConfigJson['messageAgent'] as Map<String, dynamic>;
      expect(runMessageAgent['enabled'], isTrue);
      expect(runMessageAgent['runtimeProvider'], 'hermes');
      expect(runMessageAgent['processingScope'], 'all_conversations');
      expect(runMessageAgent['realBackend'], isTrue);
      expect(runMessageAgent['enabled'], messageAgent['enabled']);
      final service = runConfigJson['service'] as Map<String, dynamic>;
      expect(
        service['messageServiceWsUrl'],
        'wss://messages.example.test/im/ws',
      );
    });

    test(
      'defaults message-agent runner report and run config to enabled',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki_message_agent_runner_default_test_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        _writeLocalConfig(
          root,
          platform: 'linux',
          appHandle: 'message-agent-app',
          cliHandle: 'message-agent-cli',
          cliBin: '/tmp/fake-awiki-cli',
          includeMessageAgent: false,
        );
        final lines = <String>[];
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse(const <String>[
            '--case',
            'message-agent',
            '--dry-run',
            '--run-id',
            'run-message-agent-default',
          ]),
          commands: DesktopCommandRunner(
            root: root,
            dryRun: true,
            redactor: DesktopSecretRedactor(const <String>[
              'test-phone-secret',
              'test-otp-secret',
            ]),
            logLine: lines.add,
          ),
        );

        await runner.run();

        final timings = File(
          '${root.path}/.e2e/message-agent/run-message-agent-default/reports/timings.json',
        );
        final decoded =
            jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
        final messageAgent = decoded['messageAgent'] as Map<String, dynamic>;
        expect(messageAgent['enabled'], isTrue);
        expect(messageAgent['realBackend'], isFalse);

        final runConfig = File(
          '${root.path}/.e2e/message-agent/current/run_config.json',
        );
        final runConfigJson =
            jsonDecode(await runConfig.readAsString()) as Map<String, dynamic>;
        final runMessageAgent =
            runConfigJson['messageAgent'] as Map<String, dynamic>;
        expect(runMessageAgent['enabled'], isTrue);
        expect(runMessageAgent['realBackend'], isFalse);
        expect(runMessageAgent['enabled'], messageAgent['enabled']);
      },
    );

    test(
      'writes Codex Agent runner report and deterministic run config',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki_codex_agent_runner_test_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        _writeLocalConfig(
          root,
          platform: 'linux',
          appHandle: 'codex-agent-app',
          cliHandle: 'codex-agent-cli',
          cliBin: '/tmp/fake-awiki-cli',
          daemonRustRepo: '../awiki-cli-rs2-codex-agent',
          daemonBinary: '/tmp/awiki-deamon',
          daemonStateRoot: '.e2e/codex-daemon-state',
          daemonReadyFile: '.e2e/codex-daemon-ready.json',
          daemonEnvFile: '.e2e/codex-agent-cli.env',
          daemonHandle: 'codex-agent-daemon',
          codexAgentEnabled: true,
          codexAgentRealBackend: true,
          codexAgentPrompt: 'Reply exactly OK-CODEX-UNIT and nothing else',
          codexAgentExpectedReply: 'OK-CODEX-UNIT',
        );
        final lines = <String>[];
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse(const <String>[
            '--case',
            'codex-agent',
            '--dry-run',
            '--run-id',
            'run-codex-agent',
          ]),
          commands: DesktopCommandRunner(
            root: root,
            dryRun: true,
            redactor: DesktopSecretRedactor(const <String>[
              'test-phone-secret',
              'test-otp-secret',
            ]),
            logLine: lines.add,
          ),
        );

        await runner.run();

        final log = lines.join('\n');
        expect(log, contains('case: codex-agent'));
        expect(
          log,
          contains(
            r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/codex_agent_full_ui_test.dart -d linux',
          ),
        );

        final timings = File(
          '${root.path}/.e2e/codex-agent/run-codex-agent/reports/timings.json',
        );
        final decoded =
            jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
        expect(decoded['scenario'], 'codex-agent-full-ui');
        expect(decoded['case'], 'codex-agent');
        expect(decoded['caseIds'], <dynamic>[
          'CODEXAGENT-E2E-001',
          'CODEXAGENT-E2E-002',
          'CODEXAGENT-E2E-003',
          'CODEXAGENT-E2E-004',
        ]);
        final codexAgent = decoded['codexAgent'] as Map<String, dynamic>;
        expect(codexAgent['enabled'], isTrue);
        expect(codexAgent['realBackend'], isTrue);
        expect(codexAgent['expectedReply'], 'OK-CODEX-UNIT');
        expect(codexAgent['prompt'], '<redacted-deterministic-prompt>');

        final runConfig = File(
          '${root.path}/.e2e/codex-agent/current/run_config.json',
        );
        expect(runConfig.existsSync(), isTrue);
        final runConfigJson =
            jsonDecode(await runConfig.readAsString()) as Map<String, dynamic>;
        expect(runConfigJson['case'], 'codex-agent');
        final daemon = runConfigJson['daemon'] as Map<String, dynamic>;
        expect(daemon['binary'], '/tmp/awiki-deamon');
        expect(daemon['stateRoot'], '${root.path}/.e2e/codex-daemon-state');
        expect(
          daemon['readyFile'],
          '${root.path}/.e2e/codex-daemon-ready.json',
        );
        expect(daemon['envFile'], '${root.path}/.e2e/codex-agent-cli.env');
        final runCodexAgent =
            runConfigJson['codexAgent'] as Map<String, dynamic>;
        expect(runCodexAgent['enabled'], isTrue);
        expect(runCodexAgent['realBackend'], isTrue);
        expect(
          runCodexAgent['prompt'],
          'Reply exactly OK-CODEX-UNIT and nothing else',
        );
        expect(runCodexAgent['expectedReply'], 'OK-CODEX-UNIT');
      },
    );

    test(
      'writes Claude Code Agent runner report and deterministic run config',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki_claude_code_agent_runner_test_',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        _writeLocalConfig(
          root,
          platform: 'linux',
          appHandle: 'claude-code-agent-app',
          cliHandle: 'claude-code-agent-cli',
          cliBin: '/tmp/fake-awiki-cli',
          daemonRustRepo: '../awiki-cli-rs2-claude-code-agent',
          daemonBinary: '/tmp/awiki-deamon',
          daemonStateRoot: '.e2e/claude-code-daemon-state',
          daemonReadyFile: '.e2e/claude-code-daemon-ready.json',
          daemonEnvFile: '.e2e/claude-code-agent-cli.env',
          daemonHandle: 'claude-code-agent-daemon',
          claudeCodeAgentEnabled: true,
          claudeCodeAgentRealBackend: true,
          claudeCodeAgentPrompt:
              'Reply exactly OK-CLAUDE-CODE-UNIT and nothing else',
          claudeCodeAgentExpectedReply: 'OK-CLAUDE-CODE-UNIT',
        );
        final lines = <String>[];
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse(const <String>[
            '--case',
            'claude-code-agent',
            '--dry-run',
            '--run-id',
            'run-claude-code-agent',
          ]),
          commands: DesktopCommandRunner(
            root: root,
            dryRun: true,
            redactor: DesktopSecretRedactor(const <String>[
              'test-phone-secret',
              'test-otp-secret',
            ]),
            logLine: lines.add,
          ),
        );

        await runner.run();

        final log = lines.join('\n');
        expect(log, contains('case: claude-code-agent'));
        expect(
          log,
          contains(
            r'$ xvfb-run -a flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/claude_code_agent_full_ui_test.dart -d linux',
          ),
        );

        final timings = File(
          '${root.path}/.e2e/claude-code-agent/run-claude-code-agent/reports/timings.json',
        );
        final decoded =
            jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
        expect(decoded['scenario'], 'claude-code-agent-full-ui');
        expect(decoded['case'], 'claude-code-agent');
        expect(decoded['caseIds'], <dynamic>[
          'CLAUDECODEAGENT-E2E-001',
          'CLAUDECODEAGENT-E2E-002',
          'CLAUDECODEAGENT-E2E-003',
          'CLAUDECODEAGENT-E2E-004',
        ]);
        final claudeCodeAgent =
            decoded['claudeCodeAgent'] as Map<String, dynamic>;
        expect(claudeCodeAgent['enabled'], isTrue);
        expect(claudeCodeAgent['realBackend'], isTrue);
        expect(claudeCodeAgent['expectedReply'], 'OK-CLAUDE-CODE-UNIT');
        expect(claudeCodeAgent['prompt'], '<redacted-deterministic-prompt>');

        final runConfig = File(
          '${root.path}/.e2e/claude-code-agent/current/run_config.json',
        );
        expect(runConfig.existsSync(), isTrue);
        final runConfigJson =
            jsonDecode(await runConfig.readAsString()) as Map<String, dynamic>;
        expect(runConfigJson['case'], 'claude-code-agent');
        final daemon = runConfigJson['daemon'] as Map<String, dynamic>;
        expect(daemon['binary'], '/tmp/awiki-deamon');
        expect(
          daemon['stateRoot'],
          '${root.path}/.e2e/claude-code-daemon-state',
        );
        expect(
          daemon['readyFile'],
          '${root.path}/.e2e/claude-code-daemon-ready.json',
        );
        expect(
          daemon['envFile'],
          '${root.path}/.e2e/claude-code-agent-cli.env',
        );
        final runClaudeCodeAgent =
            runConfigJson['claudeCodeAgent'] as Map<String, dynamic>;
        expect(runClaudeCodeAgent['enabled'], isTrue);
        expect(runClaudeCodeAgent['realBackend'], isTrue);
        expect(
          runClaudeCodeAgent['prompt'],
          'Reply exactly OK-CLAUDE-CODE-UNIT and nothing else',
        );
        expect(runClaudeCodeAgent['expectedReply'], 'OK-CLAUDE-CODE-UNIT');
      },
    );

    test('generates macOS Flutter command without Xvfb', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_macos_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(root, platform: 'macos');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--dry-run',
          '--case',
          'full',
          '--run-id',
          'run-macos',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(
        log,
        contains(
          r'$ flutter test --dart-define=AWIKI_E2E=true --dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted> integration_test/desktop_cli_peer_smoke_test.dart -d macos',
        ),
      );
      expect(log, isNot(contains(r'$ xvfb-run')));
    });

    test('prepare-only stops before Flutter test', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_prepare_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      _writeLocalConfig(root, platform: 'linux', cliBin: '/tmp/fake-awiki-cli');
      final lines = <String>[];
      final runner = DesktopE2eRunner(
        root: root,
        options: DesktopE2eOptions.parse(const <String>[
          '--case',
          'full',
          '--prepare-only',
          '--run-id',
          'run-prepare',
        ]),
        commands: DesktopCommandRunner(
          root: root,
          dryRun: true,
          redactor: DesktopSecretRedactor(const <String>[
            'test-phone-secret',
            'test-otp-secret',
          ]),
          logLine: lines.add,
        ),
      );

      await runner.run();

      final log = lines.join('\n');
      expect(log, isNot(contains(r'$ which cargo')));
      expect(log, contains('Prepare-only completed'));
      expect(log, isNot(contains('desktop_cli_peer_smoke_test.dart')));
      final timings = File(
        '${root.path}/.e2e/desktop-cli-peer/run-prepare/reports/timings.json',
      );
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 2);
      expect(decoded['status'], 'prepared');
      expect(decoded['mode'], 'prepared');
      expect(decoded['passedCaseIds'], isEmpty);
      expect(
        (decoded['caseResults'] as List<dynamic>).every(
          (value) => (value as Map<String, dynamic>)['status'] == 'prepared',
        ),
        isTrue,
      );
    });
  });

  group('DesktopPerformanceBudgetResult', () {
    test(
      'default performance gate requires realtime chat open first-paint metrics',
      () {
        final config = DesktopPerformanceConfig.defaults;

        expect(
          config.requiredMetrics,
          contains('message.cli_send_to_app_open_first_paint_ms'),
        );
        expect(
          config.requiredMetrics,
          contains('thread.realtime_open_first_paint_ms'),
        );
        expect(
          config.requiredMetrics,
          contains('cache.total_retained_messages'),
        );
        expect(
          config.requiredMetrics,
          contains('cache.active_patch_subscription_count'),
        );
        expect(
          config.hardBudgetMs['message.cli_send_to_app_open_first_paint_ms'],
          90000,
        );
        expect(
          config.hardBudgetMs['thread.realtime_open_first_paint_ms'],
          5000,
        );
        expect(
          config.softBudgetMs['message.cli_send_to_app_open_first_paint_ms'],
          5000,
        );
        expect(
          config.softBudgetMs['thread.realtime_open_first_paint_ms'],
          1500,
        );
      },
    );

    test('performance YAML budget overrides keep default required metrics', () {
      final config = DesktopPerformanceConfig.fromYaml(const <String, Object?>{
        'budgets': <String, Object?>{
          'requiredMetrics': <Object?>['custom.metric'],
          'hardBudgetMs': <String, Object?>{
            'app.launch_to_shell_visible_ms': 45000,
          },
          'softBudgetMs': <String, Object?>{
            'conversation_list.first_non_empty_visible_ms': 6000,
          },
        },
      });

      expect(config.requiredMetrics, contains('custom.metric'));
      expect(
        config.requiredMetrics,
        contains('message.cli_send_to_app_open_first_paint_ms'),
      );
      expect(config.requiredMetrics, contains('cache.total_retained_messages'));
      expect(config.hardBudgetMs['app.launch_to_shell_visible_ms'], 45000);
      expect(config.hardBudgetMs['thread.realtime_open_first_paint_ms'], 5000);
      expect(
        config.softBudgetMs['conversation_list.first_non_empty_visible_ms'],
        6000,
      );
      expect(
        config.softBudgetMs['message.cli_send_to_app_open_first_paint_ms'],
        5000,
      );
    });

    test('scales Flutter command timeout for large performance datasets', () {
      final fiveHundred = DesktopPerformanceConfig.defaults;
      final oneThousand = DesktopPerformanceConfig(
        datasetConversationCount: 1000,
        longThreadMessageCount: 100,
        requiredMetrics: const <String>{},
        hardBudgetMs: const <String, int>{},
        softBudgetMs: const <String, int>{},
        maxFullRefreshDuringSendReceive: 0,
      );

      expect(fiveHundred.flutterTimeout, const Duration(minutes: 12));
      expect(oneThousand.flutterTimeout, const Duration(minutes: 24));
    });

    test('fails when required metrics or dataset coverage are missing', () {
      final config = DesktopPerformanceConfig(
        datasetConversationCount: 10,
        longThreadMessageCount: 5,
        requiredMetrics: const <String>{
          'conversation_list.first_non_empty_visible_ms',
        },
        hardBudgetMs: const <String, int>{},
        softBudgetMs: const <String, int>{},
        maxFullRefreshDuringSendReceive: 0,
      );
      final result = DesktopPerformanceBudgetResult.evaluate(
        config: config,
        report: DesktopProductTimingReport.fromJson(<String, Object?>{
          'dataset': <String, Object?>{
            'conversationCountTarget': 10,
            'conversationCountObserved': 2,
            'warmupConversationCountObserved': 2,
            'visibleConversationCountObserved': 2,
            'longThreadMessageCountTarget': 5,
            'longThreadMessageCountObserved': 1,
          },
          'metrics': <String, Object?>{},
          'counters': _completePerformanceCounters(),
          'appProductTimings': <Object?>[],
        }),
      );

      expect(
        result.hardFailures,
        contains(
          'missing required metric conversation_list.first_non_empty_visible_ms',
        ),
      );
      expect(
        result.hardFailures,
        contains('dataset conversation count 2 is below target 10'),
      );
      expect(
        result.hardFailures,
        contains('long thread message count 1 is below target 5'),
      );
    });

    test('uses visible conversation coverage instead of warmup coverage', () {
      final config = DesktopPerformanceConfig(
        datasetConversationCount: 10,
        longThreadMessageCount: 1,
        requiredMetrics: const <String>{},
        hardBudgetMs: const <String, int>{},
        softBudgetMs: const <String, int>{},
        maxFullRefreshDuringSendReceive: 0,
      );
      final result = DesktopPerformanceBudgetResult.evaluate(
        config: config,
        report: DesktopProductTimingReport.fromJson(<String, Object?>{
          'dataset': <String, Object?>{
            'conversationCountTarget': 10,
            'conversationCountObserved': 10,
            'warmupConversationCountObserved': 10,
            'visibleConversationCountObserved': 0,
            'longThreadMessageCountTarget': 1,
            'longThreadMessageCountObserved': 1,
          },
          'metrics': <String, Object?>{},
          'counters': _completePerformanceCounters(),
          'appProductTimings': <Object?>[],
        }),
      );

      expect(
        result.hardFailures,
        contains('dataset conversation count 0 is below target 10'),
      );
    });

    test('separates hard budget failures from soft warnings', () {
      final config = DesktopPerformanceConfig(
        datasetConversationCount: 1,
        longThreadMessageCount: 1,
        requiredMetrics: const <String>{'metric.a', 'metric.b'},
        hardBudgetMs: const <String, int>{'metric.a': 100},
        softBudgetMs: const <String, int>{'metric.b': 50},
        maxFullRefreshDuringSendReceive: 0,
      );
      final result = DesktopPerformanceBudgetResult.evaluate(
        config: config,
        report: _completePerformanceReport(
          dataset: const <String, Object?>{
            'conversationCountTarget': 1,
            'conversationCountObserved': 1,
            'warmupConversationCountObserved': 1,
            'visibleConversationCountObserved': 1,
            'longThreadMessageCountTarget': 1,
            'longThreadMessageCountObserved': 1,
          },
          metrics: const <String, Object?>{'metric.a': 101, 'metric.b': 60},
          counters: const <String, Object?>{
            'conversation.full_refresh_during_send_receive_count': 1,
          },
        ),
      );

      expect(
        result.hardFailures,
        contains('metric.a 101ms exceeds hard budget 100ms'),
      );
      expect(
        result.hardFailures,
        contains(
          'conversation full refresh during send/receive count 1 exceeds 0',
        ),
      );
      expect(
        result.softWarnings,
        contains('metric.b 60ms exceeds soft budget 50ms'),
      );
    });

    test('fails when cache counters exceed bounded memory budgets', () {
      final config = DesktopPerformanceConfig(
        datasetConversationCount: 1,
        longThreadMessageCount: 1,
        requiredMetrics: const <String>{},
        hardBudgetMs: const <String, int>{},
        softBudgetMs: const <String, int>{},
        maxFullRefreshDuringSendReceive: 0,
      );
      final result = DesktopPerformanceBudgetResult.evaluate(
        config: config,
        report: _completePerformanceReport(
          metrics: const <String, Object?>{
            'cache.total_retained_messages': 1202,
            'cache.canonical_thread_count': 101,
            'cache.active_patch_subscription_count': 101,
          },
        ),
      );

      expect(
        result.hardFailures,
        contains('cache total retained messages 1202 exceeds 1200'),
      );
      expect(
        result.hardFailures,
        contains('cache canonical thread count 101 exceeds 100'),
      );
      expect(
        result.hardFailures,
        contains('cache active patch subscription count 101 exceeds 100'),
      );
    });

    test('allows cache protected overflow when reported by counters', () {
      final config = DesktopPerformanceConfig(
        datasetConversationCount: 1,
        longThreadMessageCount: 1,
        requiredMetrics: const <String>{},
        hardBudgetMs: const <String, int>{},
        softBudgetMs: const <String, int>{},
        maxFullRefreshDuringSendReceive: 0,
      );
      final result = DesktopPerformanceBudgetResult.evaluate(
        config: config,
        report: _completePerformanceReport(
          metrics: const <String, Object?>{
            'cache.total_retained_messages': 1202,
            'cache.canonical_thread_count': 102,
            'cache.active_patch_subscription_count': 100,
          },
          counters: const <String, Object?>{
            'cache.protected_overflow_count': 2,
          },
        ),
      );

      expect(
        result.hardFailures.where((failure) => failure.startsWith('cache ')),
        isEmpty,
      );
    });

    test('fails when required dataset fields or counters are missing', () {
      final config = DesktopPerformanceConfig(
        datasetConversationCount: 1,
        longThreadMessageCount: 1,
        requiredMetrics: const <String>{},
        hardBudgetMs: const <String, int>{},
        softBudgetMs: const <String, int>{},
        maxFullRefreshDuringSendReceive: 0,
      );
      final result = DesktopPerformanceBudgetResult.evaluate(
        config: config,
        report: DesktopProductTimingReport.fromJson(<String, Object?>{
          'dataset': <String, Object?>{
            'conversationCountObserved': 1,
            'longThreadMessageCountObserved': 1,
          },
          'metrics': <String, Object?>{},
          'counters': <String, Object?>{},
          'appProductTimings': <Object?>[],
        }),
      );

      expect(
        result.hardFailures,
        contains(
          'missing required dataset field visibleConversationCountObserved',
        ),
      );
      expect(
        result.hardFailures,
        contains(
          'missing required counter '
          'conversation.full_refresh_during_send_receive_count',
        ),
      );
      expect(
        result.hardFailures,
        contains('missing required counter cache.trimmed_message_count'),
      );
      expect(
        result.hardFailures,
        contains('dataset conversation count 0 is below target 1'),
      );
    });
  });
}

DesktopProductTimingReport _completePerformanceReport({
  Map<String, Object?> dataset = const <String, Object?>{},
  Map<String, Object?> metrics = const <String, Object?>{},
  Map<String, Object?> counters = const <String, Object?>{},
}) {
  return DesktopProductTimingReport.fromJson(<String, Object?>{
    'dataset': <String, Object?>{
      'conversationCountTarget': 1,
      'conversationCountObserved': 1,
      'warmupConversationCountObserved': 1,
      'visibleConversationCountObserved': 1,
      'longThreadMessageCountTarget': 1,
      'longThreadMessageCountObserved': 1,
      ...dataset,
    },
    'metrics': <String, Object?>{...metrics},
    'counters': <String, Object?>{
      ..._completePerformanceCounters(),
      ...counters,
    },
    'appProductTimings': <Object?>[],
  });
}

Map<String, Object?> _completePerformanceCounters() {
  return <String, Object?>{
    'performance_dataset.existing_count': 0,
    'performance_dataset.created_count': 1,
    'performance_dataset.long_thread_initial_count': 0,
    'performance_dataset.long_thread_created_count': 1,
    'performance_dataset.long_thread_observed_count': 1,
    'message_sync.warmup_events_applied': 1,
    'message_sync.warmup_pages_fetched': 1,
    'message_sync.warmup_snapshot_required_count': 0,
    'message_sync.warmup_has_more_count': 0,
    'conversation_list.fast_local_pages_fetched': 1,
    'conversation_list.full_pages_fetched': 1,
    'conversation.full_refresh_during_send_receive_count': 0,
    'conversation.list_conversations_calls_total': 0,
    'conversation.patch_apply_count': 1,
    'conversation.patch_repair_count': 0,
    'cache.trimmed_message_count': 0,
    'cache.evicted_thread_count': 0,
    'cache.protected_overflow_count': 0,
  };
}

void _writeLocalConfig(
  Directory root, {
  required String platform,
  String appHandle = 'e2e-app',
  String cliHandle = 'e2e-cli',
  String cliBin = '/tmp/fake-awiki-cli',
  String cliSourceRef = '1111111111111111111111111111111111111111',
  String? messageServiceUrl,
  String? messageServiceWsUrl,
  String? daemonRustRepo,
  String? daemonBinary,
  String? daemonStateRoot,
  String? daemonReadyFile,
  String? daemonEnvFile,
  String? daemonHandle,
  String? fakeHermesGatewayCommand,
  bool messageAgentEnabled = false,
  bool messageAgentRealBackend = false,
  bool includeMessageAgent = true,
  bool codexAgentEnabled = false,
  bool codexAgentRealBackend = false,
  String? codexAgentPrompt,
  String? codexAgentExpectedReply,
  bool includeCodexAgent = true,
  bool claudeCodeAgentEnabled = false,
  bool claudeCodeAgentRealBackend = false,
  String? claudeCodeAgentPrompt,
  String? claudeCodeAgentExpectedReply,
  bool includeClaudeCodeAgent = true,
  String performanceBlock = '',
}) {
  final messageService = messageServiceUrl == null
      ? ''
      : '  messageServiceUrl: $messageServiceUrl\n';
  final messageServiceWs = messageServiceWsUrl == null
      ? ''
      : '  messageServiceWsUrl: $messageServiceWsUrl\n';
  final daemon =
      daemonRustRepo == null &&
          daemonBinary == null &&
          daemonStateRoot == null &&
          daemonReadyFile == null &&
          daemonEnvFile == null &&
          daemonHandle == null &&
          fakeHermesGatewayCommand == null
      ? ''
      : '''
daemon:
${daemonRustRepo == null ? '' : '  rustRepo: $daemonRustRepo\n'}${daemonBinary == null ? '' : '  binary: $daemonBinary\n'}${daemonStateRoot == null ? '' : '  stateRoot: $daemonStateRoot\n'}${daemonReadyFile == null ? '' : '  readyFile: $daemonReadyFile\n'}${daemonEnvFile == null ? '' : '  envFile: $daemonEnvFile\n'}${daemonHandle == null ? '' : '  handle: $daemonHandle\n'}${fakeHermesGatewayCommand == null ? '' : '  fakeHermesGatewayCommand: $fakeHermesGatewayCommand\n'}
''';
  final messageAgent = includeMessageAgent
      ? '''
messageAgent:
  enabled: $messageAgentEnabled
  runtimeProvider: hermes
  processingScope: all_conversations
  realBackend: $messageAgentRealBackend
'''
      : '';
  final codexPromptLine = codexAgentPrompt == null
      ? ''
      : '  prompt: "$codexAgentPrompt"\n';
  final codexExpectedReplyLine = codexAgentExpectedReply == null
      ? ''
      : '  expectedReply: "$codexAgentExpectedReply"\n';
  final codexAgent = includeCodexAgent
      ? '''
codexAgent:
  enabled: $codexAgentEnabled
  realBackend: $codexAgentRealBackend
$codexPromptLine$codexExpectedReplyLine
'''
      : '';
  final claudeCodePromptLine = claudeCodeAgentPrompt == null
      ? ''
      : '  prompt: "$claudeCodeAgentPrompt"\n';
  final claudeCodeExpectedReplyLine = claudeCodeAgentExpectedReply == null
      ? ''
      : '  expectedReply: "$claudeCodeAgentExpectedReply"\n';
  final claudeCodeAgent = includeClaudeCodeAgent
      ? '''
claudeCodeAgent:
  enabled: $claudeCodeAgentEnabled
  realBackend: $claudeCodeAgentRealBackend
$claudeCodePromptLine$claudeCodeExpectedReplyLine
'''
      : '';
  File('${root.path}/tests/e2e/configs/e2e.local.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
platform: $platform
service:
  baseUrl: https://service.example.test
  didDomain: example.test
$messageService
$messageServiceWs
$daemon$messageAgent$codexAgent$claudeCodeAgent$performanceBlock
otp:
  phone: test-phone-secret
  code: test-otp-secret
accounts:
  appUser:
    handle: $appHandle
  cliPeer:
    handle: $cliHandle
cliPeer:
  binary: $cliBin
  sourceRef: $cliSourceRef
''');
}
