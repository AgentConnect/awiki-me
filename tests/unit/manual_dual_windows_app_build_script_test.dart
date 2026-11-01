import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Windows preparation isolates identities without changing checkout',
    () async {
      final files = <String>[
        'windows/runner/app_constants.h',
        'windows/runner/Runner.rc',
        'windows/runner/desktop_shell.cpp',
        'windows/runner/scope_secret_store.cpp',
        'lib/src/data/storage/platform_scope_secret_repository.dart',
        'lib/src/data/services/app_notification_facade.dart',
      ];
      final before = {
        for (final file in files) file: File(file).readAsStringSync(),
      };
      final temp = Directory.systemTemp.createTempSync('awiki-cu-tenant-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final tenant = File('${temp.path}/tenant.json');
      tenant.writeAsStringSync(
        jsonEncode({
          'schema_version': 1,
          'default_slot': 'primary',
          'tenants': {
            'primary': {
              'backend_origin': 'https://awiki.info',
              'did_host': 'awiki.info',
            },
            'secondary': {
              'backend_origin': 'https://awiki.ai',
              'did_host': 'awiki.ai',
            },
          },
        }),
      );
      final result = await Process.run('pwsh', [
        '-NoProfile',
        '-File',
        'scripts/build_manual_dual_windows_apps.ps1',
        '-TenantConfigPath',
        tenant.path,
        '-PrepareOnly',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final manifestFile = File(
        (result.stdout as String).trim().split('\n').last.trim(),
      );
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      expect(manifest['status'], 'prepared');
      expect(manifest['entrypoint'], 'lib/main.dart');
      final apps = manifest['apps'] as List<dynamic>;
      expect(apps, hasLength(2));
      expect(
        apps.map((dynamic a) => a['secret_service']).toSet(),
        hasLength(2),
      );
      for (final dynamic app in apps) {
        final source = app['source'] as String;
        final role = app['role'] as String;
        final native = File(
          '$source/windows/runner/app_constants.h',
        ).readAsStringSync();
        expect(native, contains('cu.$role.single-instance'));
        expect(native, contains(app['title']));
        expect(native, isNot(contains('L"AWiki.AWikiMe"')));
        final roots = File(
          '$source/windows/runner/desktop_shell.cpp',
        ).readAsStringSync();
        expect(roots, contains('L"${app['product']}"'));
        expect(roots, isNot(contains('/ L"AWikiMe"')));
        final rc = File('$source/windows/runner/Runner.rc').readAsStringSync();
        expect(rc, contains('"ProductName", "${app['product']}"'));
        for (final path in [
          'windows/runner/scope_secret_store.cpp',
          'lib/src/data/storage/platform_scope_secret_repository.dart',
        ]) {
          final code = File('$source/$path').readAsStringSync();
          expect(code, contains(app['secret_service']));
          expect(code, isNot(contains('ai.awiki.awikime.dev.scope-secrets')));
          expect(code, contains('ai.awiki.awikime.scope-secrets'));
        }
        expect(
          File('$source/lib/main.dart').readAsStringSync(),
          File('lib/main.dart').readAsStringSync(),
        );
        expect(
          File(
            '$source/lib/src/data/services/local_auth_user_presence_port.dart',
          ).readAsStringSync(),
          File(
            'lib/src/data/services/local_auth_user_presence_port.dart',
          ).readAsStringSync(),
        );
      }
      for (final file in files) {
        expect(File(file).readAsStringSync(), before[file], reason: file);
      }
      tenant.writeAsStringSync('{"schema_version":0}');
      final rejected = await Process.run('pwsh', [
        '-NoProfile',
        '-File',
        'scripts/build_manual_dual_windows_apps.ps1',
        '-TenantConfigPath',
        tenant.path,
        '-PrepareOnly',
      ]);
      expect(rejected.exitCode, isNot(0));
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
