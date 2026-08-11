import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _appKeyEnvironment = 'AWIKI_ANDROID_EMAS_APP_KEY';
const _appSecretEnvironment = 'AWIKI_ANDROID_EMAS_APP_SECRET';
const _appKey = '123456789';
const _appSecret = 'abcdef0123456789abcdef0123456789';

void main() {
  if (Platform.isWindows) {
    test(
      'Android EMAS Release config checks require the Linux package worker',
      () {},
      skip: 'POSIX owner-only file modes are verified on the Linux worker.',
    );
    return;
  }

  test('writes and validates a minimal owner-only Release config', () async {
    final root = await Directory.systemTemp.createTemp('awiki_emas_release_');
    try {
      final output = File('${root.path}/android/emas.properties');
      final write = _runConfigTool(
        <String>['write', '--output', output.path],
        environment: const <String, String>{
          _appKeyEnvironment: _appKey,
          _appSecretEnvironment: _appSecret,
        },
      );

      expect(write.exitCode, 0, reason: write.stderr.toString());
      final content = await output.readAsString();
      expect(content, contains('debug.enabled=false'));
      expect(content, contains('profile.enabled=false'));
      expect(content, contains('release.enabled=true'));
      expect(content, contains('release.appKey=$_appKey'));
      expect(content, contains('release.appSecret=$_appSecret'));
      expect(content, isNot(contains('appRsaSecret')));
      expect((await output.stat()).mode & 0x1ff, 0x180);

      final validate = _runConfigTool(<String>[
        'validate',
        '--path',
        output.path,
      ]);
      expect(validate.exitCode, 0, reason: validate.stderr.toString());
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('does not create a config when a GitHub secret is missing', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_emas_release_missing_',
    );
    try {
      final output = File('${root.path}/android/emas.properties');
      final result = _runConfigTool(
        <String>['write', '--output', output.path],
        environment: const <String, String>{
          _appKeyEnvironment: '',
          _appSecretEnvironment: '',
        },
      );

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('AWIKI_ANDROID_EMAS_APP_KEY is required'));
      expect(await output.exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('rejects disabled, placeholder, and broadly readable configs', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_emas_release_invalid_',
    );
    try {
      final output = File('${root.path}/emas.properties');
      await output.writeAsString('''
release.enabled=false
release.appKey=$_appKey
release.appSecret=$_appSecret
''');
      await Process.run('chmod', <String>['600', output.path]);
      var result = _runConfigTool(<String>['validate', '--path', output.path]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('release.enabled must be true'));

      await output.writeAsString('''
release.enabled=true
release.appKey=REPLACE_WITH_ANDROID_RELEASE_EMAS_APP_KEY
release.appSecret=$_appSecret
''');
      result = _runConfigTool(<String>['validate', '--path', output.path]);
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr,
        contains('release.appKey still contains a placeholder'),
      );

      await output.writeAsString('''
release.enabled=true
release.appKey=$_appKey
release.appSecret=$_appSecret
''');
      await Process.run('chmod', <String>['644', output.path]);
      result = _runConfigTool(<String>['validate', '--path', output.path]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('permissions must not allow'));
    } finally {
      await root.delete(recursive: true);
    }
  });
}

ProcessResult _runConfigTool(
  List<String> arguments, {
  Map<String, String> environment = const <String, String>{},
}) {
  return Process.runSync(Platform.isWindows ? 'python' : 'python3', <String>[
    'scripts/android_emas_release_config.py',
    ...arguments,
  ], environment: environment);
}
