import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_runner.dart';

void main() {
  group('RunnerOptions', () {
    test('uses the local config by default', () {
      final options = RunnerOptions.parse(const <String>[]);

      expect(options.configPath, 'awiki_e2e.local.yaml');
      expect(options.skipBuild, isFalse);
      expect(options.dryRun, isFalse);
      expect(options.help, isFalse);
    });

    test('parses explicit config and dry-run flags', () {
      final options = RunnerOptions.parse(const <String>[
        '--config',
        'awiki_e2e.example.yaml',
        '--skip-build',
        '--dry-run',
      ]);

      expect(options.configPath, 'awiki_e2e.example.yaml');
      expect(options.skipBuild, isTrue);
      expect(options.dryRun, isTrue);
      expect(options.help, isFalse);
    });

    test('reports missing config path', () {
      expect(
        () => RunnerOptions.parse(const <String>['--config']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            '--config requires a path.',
          ),
        ),
      );
    });

    test('reports unknown arguments', () {
      expect(
        () => RunnerOptions.parse(const <String>['--device']),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'Unknown argument: --device',
          ),
        ),
      );
    });
  });

  group('E2eConfig', () {
    test('loads the example config with platform specific defaults', () {
      final config = E2eConfig.load(File('awiki_e2e.example.yaml'));

      expect(config.platform, E2ePlatform.ios);
      expect(config.appId, 'ai.awiki.awikime123');
      expect(config.app.androidId, 'ai.awiki.awikime');
      expect(config.service.baseUrl, 'https://awiki.ai');
      expect(config.device.resetBeforeRun, isTrue);
      expect(config.device.ios.names.a, 'awiki-e2e-ios-a');
      expect(config.device.ios.names.b, 'awiki-e2e-ios-b');
      expect(config.device.android.avdNames.a, 'awiki_e2e_android_a');
      expect(config.device.android.avdNames.b, 'awiki_e2e_android_b');
      expect(config.otp.timeout, const Duration(seconds: 180));
      expect(config.message.waitTimeout, const Duration(seconds: 90));
      expect(config.accounts.a.handle, 'awiki-e2e-a');
      expect(config.accounts.b.handle, 'awiki-e2e-b');
    });

    test('loads android app id when platform is android', () async {
      final file = await _writeConfig('''
platform: android
app:
  androidId: ai.awiki.android
  iosId: ai.awiki.ios
service:
  baseUrl: https://example.test
  userServiceUrl: https://user.example.test
  messageServiceUrl: https://message.example.test
  didDomain: example.test
device:
  resetBeforeRun: false
  android:
    ids:
      a: emulator-5554
      b: emulator-5556
otp:
  digits: 6
  timeoutSeconds: 30
accounts:
  a:
    phone: "+8610011110001"
    handle: alice
  b:
    phone: "+8610011110002"
    handle: bob
message:
  waitTimeoutSeconds: 45
''');

      final config = E2eConfig.load(file);

      expect(config.platform, E2ePlatform.android);
      expect(config.appId, 'ai.awiki.android');
      expect(config.device.resetBeforeRun, isFalse);
      expect(config.device.android.ids.a, 'emulator-5554');
      expect(config.device.android.ids.b, 'emulator-5556');
      expect(config.otp.timeout, const Duration(seconds: 30));
      expect(config.message.waitTimeout, const Duration(seconds: 45));
    });

    test('rejects duplicate account handles case-insensitively', () async {
      final file = await _writeConfig('''
platform: ios
app: {}
service: {}
device: {}
otp: {}
accounts:
  a:
    phone: "+8610011110001"
    handle: SameHandle
  b:
    phone: "+8610011110002"
    handle: samehandle
message: {}
''');

      expect(
        () => E2eConfig.load(file),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'accounts.a.handle and accounts.b.handle must differ.',
          ),
        ),
      );
    });

    test('rejects unsupported platform with a focused message', () async {
      final file = await _writeConfig('''
platform: macos
app: {}
service: {}
device: {}
otp: {}
accounts:
  a:
    phone: "+8610011110001"
    handle: alice
  b:
    phone: "+8610011110002"
    handle: bob
message: {}
''');

      expect(
        () => E2eConfig.load(file),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'macOS is not supported in the first E2E version.',
          ),
        ),
      );
    });

    test('rejects invalid OTP and message timeout values', () async {
      final invalidOtp = await _writeConfig('''
platform: ios
app: {}
service: {}
device: {}
otp:
  timeoutSeconds: 0
accounts:
  a:
    phone: "+8610011110001"
    handle: alice
  b:
    phone: "+8610011110002"
    handle: bob
message: {}
''');

      expect(
        () => E2eConfig.load(invalidOtp),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'otp.timeoutSeconds must be greater than 0.',
          ),
        ),
      );

      final invalidMessageTimeout = await _writeConfig('''
platform: ios
app: {}
service: {}
device: {}
otp: {}
accounts:
  a:
    phone: "+8610011110001"
    handle: alice
  b:
    phone: "+8610011110002"
    handle: bob
message:
  waitTimeoutSeconds: 0
''');

      expect(
        () => E2eConfig.load(invalidMessageTimeout),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'message.waitTimeoutSeconds must be greater than 0.',
          ),
        ),
      );
    });
  });

  group('CommandRunner dry-run', () {
    test('records commands without invoking external tools', () async {
      final lines = <String>[];
      final runner = CommandRunner(
        root: Directory.current,
        dryRun: true,
        logLine: lines.add,
      );

      await runner.requireExecutable('maestro');
      await runner.run('flutter', const <String>['build', 'apk']);
      final process = await runner.start('maestro', const <String>[
        'test',
        '.maestro/login.yaml',
      ], label: 'login-a');
      final exitCode = await process.wait();

      expect(exitCode, 0);
      expect(
        lines,
        containsAllInOrder(const <String>[
          r'$ which maestro',
          'maestro: dry-run',
          r'$ flutter build apk',
          r'$ maestro test .maestro/login.yaml',
        ]),
      );
    });

    test('writes timing reports in dry-run mode', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_me_e2e_runner_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final configFile = File('${root.path}/e2e.yaml');
      await configFile.writeAsString('''
platform: android
app: {}
service: {}
device: {}
otp: {}
accounts:
  a:
    phone: "+8610011110001"
    handle: alice
  b:
    phone: "+8610011110002"
    handle: bob
message: {}
''');
      final options = RunnerOptions(
        configPath: configFile.path,
        skipBuild: false,
        dryRun: true,
        help: false,
      );
      final runner = E2eRunner(
        root: root,
        config: E2eConfig.load(configFile),
        options: options,
      );

      await runner.run();

      final reports = Directory(
        '${root.path}/.e2e/reports',
      ).listSync().whereType<Directory>().toList();
      expect(reports, hasLength(1));
      final timings = File('${reports.single.path}/timings.json');
      expect(timings.existsSync(), isTrue);
      final decoded =
          jsonDecode(await timings.readAsString()) as Map<String, dynamic>;
      expect(decoded['status'], 'success');
      expect(
        decoded['steps'],
        contains(
          isA<Map<String, dynamic>>()
              .having((step) => step['name'], 'name', 'Checking tooling')
              .having((step) => step['status'], 'status', 'success'),
        ),
      );
      expect(
        decoded['steps'],
        contains(
          isA<Map<String, dynamic>>()
              .having((step) => step['name'], 'name', 'Building app')
              .having((step) => step['status'], 'status', 'success'),
        ),
      );
    });
  });
}

Future<File> _writeConfig(String contents) async {
  final directory = await Directory.systemTemp.createTemp(
    'awiki_me_e2e_config_test_',
  );
  final file = File('${directory.path}/awiki_e2e.yaml');
  await file.writeAsString(contents);
  addTearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
  return file;
}
