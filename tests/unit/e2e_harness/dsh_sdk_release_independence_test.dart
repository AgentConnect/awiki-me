import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = Directory.current.absolute;
  for (final version in ['0.2.5', '9.8.7']) {
    test('remote Join preflight accepts SDK release $version', () async {
      final workspace = Directory.systemTemp.createTempSync('dsh_sdk_release_');
      addTearDown(() => workspace.deleteSync(recursive: true));
      final app = Directory('${workspace.path}/awiki-me')..createSync();
      void write(String path, String content) {
        File('${workspace.path}/$path')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
      }

      write(
        'dsh-awiki/package.json',
        jsonEncode({
          'dependencies': {'@awiki/im-core-node': version},
        }),
      );
      write('dsh-awiki/scripts/device-join-e2e.mjs', '');
      write('dsh-awiki/lib/index.js', '');
      write(
        'awiki-me/tests/e2e/suite_manifest.json',
        File('${repo.path}/tests/e2e/suite_manifest.json').readAsStringSync(),
      );
      write('awiki-me/tests/e2e/configs/e2e.local.yaml', '''
platform: linux
service:
  baseUrl: https://awiki.info
  didDomain: awiki.info
otp:
  phone: test-phone-secret
  code: "123456"
cliPeer:
  binary: /tmp/fake-awiki-cli
  sourceRef: "1111111111111111111111111111111111111111"
''');
      write('probe.dart', '''
import 'dart:io';
import '${File('${repo.path}/tests/e2e/runner.dart').uri}';
Future<void> main() async {
  final root = Directory.current;
  await DesktopE2eRunner(
    root: root,
    options: DesktopE2eOptions.parse([
      '--dry-run', '--case', 'multi-device-remote-join',
      '--run-id', 'sdk-release-probe',
    ]),
    commands: DesktopCommandRunner(
      root: root, dryRun: true,
      redactor: DesktopSecretRedactor([]), logLine: print,
    ),
  ).run();
}
''');
      final environment = Map<String, String>.from(Platform.environment)
        ..removeWhere(
          (key, _) =>
              key.startsWith('AWIKI_E2E_') ||
              key.startsWith('DEV_OTP_') ||
              key == 'HANDLE_REGISTRATION_PHONE_WHITELIST',
        )
        ..['AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED'] = '1';
      final result = await Process.run(
        'dart',
        [
          '--packages=${repo.path}/.dart_tool/package_config.json',
          '${workspace.path}/probe.dart',
        ],
        workingDirectory: app.path,
        environment: environment,
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('would write remote multi-device Join run config'),
      );
    });
  }
}
