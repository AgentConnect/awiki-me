import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

    test('rejects unsupported case', () {
      expect(
        () => DesktopE2eOptions.parse(const <String>['--case', 'unknown']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'Unsupported E2E case "unknown". '
                'Use smoke, full, direct, group, attachment, contacts, '
                'or message-agent.',
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
      expect(log, contains('check file: /tmp/file-awiki-cli'));
      expect(
        log,
        contains(
          r'$ /tmp/file-awiki-cli --format json id recover --handle cli-from-file --phone <redacted> --otp <redacted>',
        ),
      );
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux',
        ),
      );
      expect(log, contains('would write Flutter E2E run config: <redacted>'));
      expect(log, isNot(contains('--dart-define=')));
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
            r'$ xvfb-run -a flutter test integration_test/app_smoke_test.dart -d linux',
          ),
        );
        expect(
          log,
          contains(
            r'$ xvfb-run -a flutter test integration_test/im_core_open_smoke_test.dart -d linux',
          ),
        );
      } else {
        expect(
          log,
          contains(
            r'$ flutter test integration_test/app_smoke_test.dart -d macos',
          ),
        );
        expect(
          log,
          contains(
            r'$ flutter test integration_test/im_core_open_smoke_test.dart -d macos',
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
          'check file: /tmp/fake-awiki-cli',
          r'$ /tmp/fake-awiki-cli --format json init',
          r'$ /tmp/fake-awiki-cli --format json config show',
          r'$ /tmp/fake-awiki-cli --format json id recover --handle e2e-cli --phone <redacted> --otp <redacted>',
          r'$ /tmp/fake-awiki-cli --format json id current',
          r'$ /tmp/fake-awiki-cli --format json id status',
          r'$ /tmp/fake-awiki-cli --format json msg inbox --limit 1',
        ]),
      );
      expect(
        log,
        contains(
          r'$ xvfb-run -a flutter test integration_test/desktop_cli_peer_smoke_test.dart -d linux',
        ),
      );
      expect(log, contains('would write Flutter E2E run config: <redacted>'));
      expect(log, isNot(contains('--dart-define=')));
      expect(
        log,
        contains('message_service_endpoint=https://messages.example.test'),
      );
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
      expect(decoded['status'], 'success');
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
        'ATTACH-E2E-001',
        'ATTACH-E2E-002',
        'ATTACH-REG-001',
      ]);
      expect(decoded['runId'], 'run123');
      expect(decoded['platform'], 'linux');
      expect(decoded['dryRun'], isTrue);
      expect(decoded['prepareOnly'], isFalse);
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
        expect(log, isNot(contains('--dart-define=')));
        expect(log, isNot(contains('test-phone-secret')));
        expect(log, isNot(contains('test-otp-secret')));
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
          r'$ flutter test integration_test/desktop_cli_peer_group_test.dart -d macos',
        ),
      );
      expect(log, isNot(contains('--dart-define=')));
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
          r'$ xvfb-run -a flutter test integration_test/desktop_cli_peer_direct_test.dart -d linux',
        ),
      );
      expect(log, isNot(contains('--dart-define=')));
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
          r'$ flutter test integration_test/desktop_cli_peer_attachment_test.dart -d macos',
        ),
      );
      expect(log, isNot(contains('--dart-define=')));
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
          r'$ xvfb-run -a flutter test integration_test/desktop_cli_peer_contacts_test.dart -d linux',
        ),
      );
      expect(log, isNot(contains('--dart-define=')));
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
          r'$ xvfb-run -a flutter test integration_test/message_agent_full_ui_test.dart -d linux',
        ),
      );
      expect(log, isNot(contains('--dart-define=')));
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
        'MSGAGENT-E2E-003',
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
          r'$ flutter test integration_test/desktop_cli_peer_smoke_test.dart -d macos',
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
          '--dry-run',
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
    });
  });
}

void _writeLocalConfig(
  Directory root, {
  required String platform,
  String appHandle = 'e2e-app',
  String cliHandle = 'e2e-cli',
  String cliBin = '/tmp/fake-awiki-cli',
  String? messageServiceUrl,
  String? messageServiceWsUrl,
  String? daemonRustRepo,
  String? daemonBinary,
  String? daemonStateRoot,
  String? daemonReadyFile,
  String? daemonHandle,
  String? fakeHermesGatewayCommand,
  bool messageAgentEnabled = false,
  bool messageAgentRealBackend = false,
  bool includeMessageAgent = true,
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
          daemonHandle == null &&
          fakeHermesGatewayCommand == null
      ? ''
      : '''
daemon:
${daemonRustRepo == null ? '' : '  rustRepo: $daemonRustRepo\n'}${daemonBinary == null ? '' : '  binary: $daemonBinary\n'}${daemonStateRoot == null ? '' : '  stateRoot: $daemonStateRoot\n'}${daemonReadyFile == null ? '' : '  readyFile: $daemonReadyFile\n'}${daemonHandle == null ? '' : '  handle: $daemonHandle\n'}${fakeHermesGatewayCommand == null ? '' : '  fakeHermesGatewayCommand: $fakeHermesGatewayCommand\n'}
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
  File('${root.path}/tests/e2e/configs/e2e.local.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
platform: $platform
service:
  baseUrl: https://service.example.test
  didDomain: example.test
$messageService
$messageServiceWs
$daemon$messageAgent
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
''');
}
