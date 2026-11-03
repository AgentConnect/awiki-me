import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../e2e/runner.dart';

void main() {
  test('focused attachment has a Windows runnable entrypoint', () {
    final suite = DesktopE2eSuiteManifest.load(
      Directory.current,
    ).definitionFor(DesktopE2eCase.attachment);
    expect(suite.supportedPlatforms, contains('windows'));
    expect(
      DesktopE2eCase.attachment.testFile,
      'integration_test/desktop_cli_peer_attachment_test.dart',
    );
  });

  for (final (aggregateSupportsWindows, allowOneSuite) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    test(
      'full rejects an incomplete Windows matrix aggregate=$aggregateSupportsWindows oneSuite=$allowOneSuite',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'awiki-full-platform-',
        );
        addTearDown(() => root.delete(recursive: true));
        final e2e = await Directory(
          '${root.path}/tests/e2e',
        ).create(recursive: true);
        final manifest =
            jsonDecode(File('tests/e2e/suite_manifest.json').readAsStringSync())
                as Map;
        final suites = manifest['suites'] as Map;
        for (final value in suites.values) {
          (value['supportedPlatforms'] as List).remove('windows');
        }
        if (aggregateSupportsWindows) {
          (suites['full']['supportedPlatforms'] as List).add('windows');
        }
        if (allowOneSuite) {
          (suites['smoke']['supportedPlatforms'] as List).add('windows');
        }
        await File(
          '${e2e.path}/suite_manifest.json',
        ).writeAsString(jsonEncode(manifest));
        await File(
          'tests/e2e/user_test_exclusions.json',
        ).copy('${e2e.path}/user_test_exclusions.json');
        final config = await File(
          '${root.path}/config.yaml',
        ).writeAsString('platform: windows\n');
        await expectLater(
          runDesktopFull(
            root: root,
            options: DesktopE2eOptions(
              dryRun: true,
              prepareOnly: false,
              help: false,
              configPath: config.path,
              runId: 'unsupported',
              e2eCase: DesktopE2eCase.full,
            ),
            commands: DesktopCommandRunner(
              root: root,
              dryRun: true,
              redactor: DesktopSecretRedactor([]),
              logLine: (_) {},
            ),
            environment: {},
          ),
          throwsA(
            isA<E2eFailure>().having(
              (error) => error.toString(),
              'reason',
              contains(
                allowOneSuite
                    ? 'missing portable suites'
                    : aggregateSupportsWindows
                    ? 'no executable suites'
                    : 'does not support windows',
              ),
            ),
          ),
        );
        expect(
          Directory('${root.path}/.e2e/full/unsupported').existsSync(),
          isFalse,
        );
      },
    );
  }
}
