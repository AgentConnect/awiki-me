import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/desktop_cli_peer_e2e_runner.dart';

void main() {
  group('DesktopCliPeerOptions', () {
    test('parses Linux dry-run options', () {
      final options = DesktopCliPeerOptions.parse(const <String>[
        '--platform',
        'linux',
        '--dry-run',
        '--prepare-only',
        '--service-base-url',
        'https://service.example.test',
        '--did-domain',
        'example.test',
        '--app-handle',
        'app-smoke',
        '--cli-handle',
        'cli-smoke',
        '--cli-bin',
        '../awiki-cli-rs2/target/release/awiki-cli',
        '--run-id',
        'run123',
      ]);

      expect(options.platform, DesktopE2ePlatform.linux);
      expect(options.dryRun, isTrue);
      expect(options.prepareOnly, isTrue);
      expect(options.serviceBaseUrl, 'https://service.example.test');
      expect(options.didDomain, 'example.test');
      expect(options.appHandle, 'app-smoke');
      expect(options.cliHandle, 'cli-smoke');
      expect(options.cliBin, '../awiki-cli-rs2/target/release/awiki-cli');
      expect(options.runId, 'run123');
    });

    test('supports macOS platform', () {
      final options = DesktopCliPeerOptions.parse(const <String>[
        '--platform',
        'macos',
        '--dry-run',
      ]);

      expect(options.platform, DesktopE2ePlatform.macos);
    });

    test('rejects unsupported platform', () {
      expect(
        () => DesktopCliPeerOptions.parse(const <String>[
          '--platform',
          'windows',
        ]),
        throwsA(
          isA<DesktopCliPeerFailure>().having(
            (error) => error.message,
            'message',
            'Unsupported desktop platform "windows". Use macos or linux.',
          ),
        ),
      );
    });

    test('reports missing values and unknown arguments', () {
      expect(
        () => DesktopCliPeerOptions.parse(const <String>['--platform']),
        throwsA(
          isA<DesktopCliPeerFailure>().having(
            (error) => error.message,
            'message',
            '--platform requires a value.',
          ),
        ),
      );
      expect(
        () => DesktopCliPeerOptions.parse(const <String>['--config']),
        throwsA(
          isA<DesktopCliPeerFailure>().having(
            (error) => error.message,
            'message',
            'Unknown argument: --config',
          ),
        ),
      );
    });
  });

  group('DesktopCliPeerConfig', () {
    test('loads service and account values from environment', () {
      final config = DesktopCliPeerConfig.from(
        DesktopCliPeerOptions.parse(const <String>[
          '--platform',
          'linux',
          '--dry-run',
        ]),
        const <String, String>{
          'AWIKI_SERVICE_BASE_URL': 'https://service.example.test',
          'AWIKI_DID_DOMAIN': 'example.test',
          'AWIKI_ANP_SERVICE_URL': 'https://service.example.test/anp-im/rpc',
          'AWIKI_ANP_SERVICE_DID': 'did:wba:example.test',
          'AWIKI_USER_SERVICE_URL': 'https://users.example.test',
          'AWIKI_MESSAGE_SERVICE_URL': 'https://messages.example.test',
          'AWIKI_MAIL_SERVICE_URL': 'https://mail.example.test',
          'DEV_OTP_PHONE': 'test-phone-secret',
          'DEV_OTP_CODE': 'test-otp-secret',
          'AWIKI_E2E_APP_HANDLE': 'app-peer',
          'AWIKI_E2E_CLI_HANDLE': 'cli-peer',
          'AWIKI_CLI_BIN': '/tmp/awiki-cli',
        },
      );

      expect(config.platform, DesktopE2ePlatform.linux);
      expect(config.serviceBaseUrl, 'https://service.example.test');
      expect(config.userServiceUrl, 'https://users.example.test');
      expect(config.messageServiceUrl, 'https://messages.example.test');
      expect(config.mailServiceUrl, 'https://mail.example.test');
      expect(config.didDomain, 'example.test');
      expect(config.anpServiceUrl, 'https://service.example.test/anp-im/rpc');
      expect(config.anpServiceDid, 'did:wba:example.test');
      expect(config.otpPhone, 'test-phone-secret');
      expect(config.otpCode, 'test-otp-secret');
      expect(config.appHandle, 'app-peer');
      expect(config.cliHandle, 'cli-peer');
      expect(config.cliBin, '/tmp/awiki-cli');
    });

    test('allows placeholder OTP values only in dry-run', () {
      final config = DesktopCliPeerConfig.from(
        DesktopCliPeerOptions.parse(const <String>[
          '--platform',
          'linux',
          '--dry-run',
        ]),
        const <String, String>{},
      );

      expect(config.otpPhone, '<DEV_OTP_PHONE>');
      expect(config.otpCode, '<DEV_OTP_CODE>');
    });

    test('requires OTP values outside dry-run', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopCliPeerOptions.parse(const <String>['--platform', 'linux']),
          const <String, String>{},
        ),
        throwsA(
          isA<DesktopCliPeerFailure>().having(
            (error) => error.message,
            'message',
            'DEV_OTP_PHONE is required.',
          ),
        ),
      );
    });

    test('requires different App and CLI handles', () {
      expect(
        () => DesktopCliPeerConfig.from(
          DesktopCliPeerOptions.parse(const <String>[
            '--platform',
            'linux',
            '--dry-run',
            '--app-handle',
            'Same',
            '--cli-handle',
            'same',
          ]),
          const <String, String>{},
        ),
        throwsA(
          isA<DesktopCliPeerFailure>().having(
            (error) => error.message,
            'message',
            'App handle and CLI handle must differ.',
          ),
        ),
      );
    });
  });

  group('DesktopCliPeerRunner dry-run', () {
    test('generates Linux commands and redacts secrets', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final lines = <String>[];
      final options = DesktopCliPeerOptions.parse(const <String>[
        '--platform',
        'linux',
        '--dry-run',
        '--run-id',
        'run123',
        '--service-base-url',
        'https://service.example.test',
        '--did-domain',
        'example.test',
        '--app-handle',
        'e2e-app',
        '--cli-handle',
        'e2e-cli',
        '--cli-bin',
        '/tmp/fake-awiki-cli',
      ]);
      final runner = DesktopCliPeerRunner(
        root: root,
        options: options,
        environment: const <String, String>{
          'DEV_OTP_PHONE': 'test-phone-secret',
          'DEV_OTP_CODE': 'test-otp-secret',
          'AWIKI_MESSAGE_SERVICE_URL': 'https://messages.example.test',
        },
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
      expect(log, contains('--dart-define=AWIKI_E2E_RUN_ID=run123'));
      expect(log, contains('--dart-define=AWIKI_E2E_PLATFORM=linux'));
      expect(
        log,
        contains('--dart-define=AWIKI_BASE_URL=https://service.example.test'),
      );
      expect(
        log,
        contains(
          '--dart-define=AWIKI_SERVICE_BASE_URL=https://service.example.test',
        ),
      );
      expect(log, contains('--dart-define=AWIKI_E2E_APP_HANDLE=e2e-app'));
      expect(log, contains('--dart-define=AWIKI_E2E_CLI_HANDLE=e2e-cli'));
      expect(log, contains('--dart-define=DEV_OTP_PHONE=<redacted>'));
      expect(log, contains('--dart-define=DEV_OTP_CODE=<redacted>'));
      expect(
        log,
        contains('--dart-define=AWIKI_E2E_APP_STATE_ROOT=<redacted>'),
      );
      expect(log, contains('--dart-define=AWIKI_CLI_HOME_DIR=<redacted>'));
      expect(
        log,
        contains(
          '--dart-define=AWIKI_MESSAGE_SERVICE_URL=https://messages.example.test',
        ),
      );
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
      expect(decoded['runId'], 'run123');
      expect(decoded['platform'], 'linux');
      expect(decoded['cliWorkspace'], '<redacted-workspace>');
    });

    test('generates macOS Flutter command without Xvfb', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_macos_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final lines = <String>[];
      final runner = DesktopCliPeerRunner(
        root: root,
        options: DesktopCliPeerOptions.parse(const <String>[
          '--platform',
          'macos',
          '--dry-run',
          '--run-id',
          'run-macos',
          '--cli-bin',
          '/tmp/fake-awiki-cli',
        ]),
        environment: const <String, String>{
          'DEV_OTP_PHONE': 'test-phone-secret',
          'DEV_OTP_CODE': 'test-otp-secret',
        },
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

    test('plans CLI release build when no binary is provided', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_desktop_cli_peer_runner_build_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final lines = <String>[];
      final runner = DesktopCliPeerRunner(
        root: root,
        options: DesktopCliPeerOptions.parse(const <String>[
          '--platform',
          'linux',
          '--dry-run',
          '--prepare-only',
          '--run-id',
          'run-build',
        ]),
        environment: const <String, String>{
          'DEV_OTP_PHONE': 'test-phone-secret',
          'DEV_OTP_CODE': 'test-otp-secret',
        },
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
      expect(log, contains(r'$ which cargo'));
      expect(
        log,
        contains(
          r'$ cargo build -p awiki-cli --bin awiki-cli --release --locked',
        ),
      );
      expect(log, isNot(contains('../awiki-cli-rs2/cargo')));
      expect(log, contains('Prepare-only completed'));
      expect(log, isNot(contains('desktop_cli_peer_smoke_test.dart')));
    });
  });
}
