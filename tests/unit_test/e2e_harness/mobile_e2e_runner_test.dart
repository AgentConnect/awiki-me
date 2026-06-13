import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e_test/harness/mobile_e2e_runner.dart';

void main() {
  group('RunnerOptions', () {
    test('uses the local config by default', () {
      final options = RunnerOptions.parse(const <String>[]);

      expect(options.configPath, 'tests/e2e_test/configs/mobile.local.yaml');
      expect(options.skipBuild, isFalse);
      expect(options.dryRun, isFalse);
      expect(options.help, isFalse);
    });

    test('parses explicit config and dry-run flags', () {
      final options = RunnerOptions.parse(const <String>[
        '--config',
        'tests/e2e_test/configs/mobile.example.yaml',
        '--skip-build',
        '--dry-run',
      ]);

      expect(options.configPath, 'tests/e2e_test/configs/mobile.example.yaml');
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
      final config = E2eConfig.load(
        File('tests/e2e_test/configs/mobile.example.yaml'),
      );

      expect(config.platform, E2ePlatform.ios);
      expect(config.appId, 'ai.awiki.awikime123');
      expect(config.app.androidId, 'ai.awiki.awikime');
      expect(config.service.baseUrl, 'https://awiki.info');
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

    test('rejects partial and duplicate mobile device configuration', () async {
      final partialAndroidIds = await _writeConfig('''
platform: android
app: {}
service: {}
device:
  android:
    ids:
      a: emulator-5554
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
      final partialAndroidConfig = E2eConfig.load(partialAndroidIds);
      expect(
        () => AndroidDeviceManager(
          CommandRunner(root: Directory.current, dryRun: true),
          partialAndroidConfig,
          Directory.systemTemp,
        ).prepare(),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'Configure both android.ids.a and android.ids.b, or omit both.',
          ),
        ),
      );

      final duplicateIosIds = await _writeConfig('''
platform: ios
app: {}
service: {}
device:
  ios:
    ids:
      a: IOS-DEVICE
      b: IOS-DEVICE
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
      final duplicateIosConfig = E2eConfig.load(duplicateIosIds);
      expect(
        () => IosDeviceManager(
          CommandRunner(root: Directory.current, dryRun: true),
          duplicateIosConfig,
        ).prepare(),
        throwsA(
          isA<E2eFailure>().having(
            (error) => error.message,
            'message',
            'iOS E2E requires two different simulator UDIDs.',
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
        'tests/e2e_test/mobile/maestro/login.yaml',
      ], label: 'login-a');
      final exitCode = await process.wait();

      expect(exitCode, 0);
      expect(
        lines,
        containsAllInOrder(const <String>[
          r'$ which maestro',
          'maestro: dry-run',
          r'$ flutter build apk',
          r'$ maestro test tests/e2e_test/mobile/maestro/login.yaml',
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

    test('reports process log file on non-zero exit', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_me_e2e_process_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final logFile = File('${root.path}/failed.log');
      final process = await CommandRunner(root: root, dryRun: false).start(
        'false',
        const <String>[],
        label: 'maestro-login-a',
        logFile: logFile,
      );

      expect(
        () => process.wait(),
        throwsA(
          isA<E2eFailure>()
              .having(
                (error) => error.message,
                'message',
                contains('maestro-login-a exited with code 1.'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('See log: ${logFile.path}'),
              ),
        ),
      );
    });
  });

  group('Maestro selectors', () {
    test('flows use E2E identifiers present in app source', () {
      final sourceIds = _sourceE2eIds();
      final referencedIds = _maestroReferencedIds();

      expect(
        referencedIds,
        containsAll(<String>{
          'e2e-phone-input',
          'e2e-send-otp-button',
          'e2e-otp-sent',
          'e2e-otp-input',
          'e2e-otp-complete',
          'e2e-login-next-button',
          'e2e-handle-input',
          'e2e-complete-login-button',
          'e2e-quick-actions-button',
          'e2e-start-conversation-menu-item',
          'e2e-identity-lookup-input',
          'e2e-identity-lookup-search-button',
          'e2e-identity-start-chat-button',
          'e2e-chat-back-button',
          'e2e-chat-input',
          'e2e-chat-send-button',
        }),
      );
      final staticIds = referencedIds
          .where((id) => !id.startsWith(r'${'))
          .toSet();
      expect(sourceIds, containsAll(staticIds));
      expect(
        File('lib/src/app/e2e_semantics.dart').readAsStringSync(),
        contains('e2e-message-'),
      );
      expect(
        File('lib/src/presentation/chat/chat_page.dart').readAsStringSync(),
        contains('e2eMessageIdentifier(message.content)'),
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

Set<String> _maestroReferencedIds() {
  final ids = <String>{};
  for (final file in Directory(
    'tests/e2e_test/mobile/maestro',
  ).listSync().whereType<File>().where((file) => file.path.endsWith('.yaml'))) {
    final contents = file.readAsStringSync();
    for (final match in RegExp(r'id:\s*([^\s]+)').allMatches(contents)) {
      ids.add(match.group(1)!.trim().replaceAll('"', ''));
    }
  }
  return ids;
}

Set<String> _sourceE2eIds() {
  final ids = <String>{};
  for (final directory in <String>['lib/src', 'lib/l10n']) {
    for (final entity in Directory(directory).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final contents = entity.readAsStringSync();
      for (final match in RegExp(r'''e2e-[a-z0-9-]+''').allMatches(contents)) {
        ids.add(match.group(0)!);
      }
    }
  }
  return ids;
}
