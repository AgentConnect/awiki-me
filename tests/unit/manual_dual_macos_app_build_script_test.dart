import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual dual-App builder keeps standalone isolation contract', () {
    final script = File(
      'scripts/build_manual_dual_macos_apps.sh',
    ).readAsStringSync();

    expect(script, contains('--target=lib/main.dart'));
    expect(script, isNot(contains('integration_test/')));
    expect(script, contains('ai.awiki.awikime.dev'));
    expect(script, contains('ai.awiki.awikime.dev.manual.joiner'));
    expect(script, contains('joiner-flutter-build'));
    expect(script, contains('AWIKI_TENANT_CONFIG_PATH'));
    expect(script, contains('AWIKI_BUILTIN_TENANTS_BASE64'));
    expect(script, contains('AWIKI_BUILTIN_TENANTS_SHA256'));
    expect(
      script,
      isNot(contains('AWIKI_MULTI_DEVICE_HANDLE_RECOVERY_ENABLED')),
    );
    expect(script, contains('AWIKI_IM_CORE_REPO_DIR'));
    expect(script, contains('build-sdk-native.sh'));
    expect(script, contains('verify_im_core_native_artifact.sh'));
    expect(script, contains(r'--macos-only --macos-arch "$host_arch"'));
    expect(script, contains('Rebuilding stale awiki_im_core'));
    expect(script, contains('XCFrameworkIntermediates/awiki_im_core'));
    expect(
      script,
      contains('Intermediates.noindex/Pods.build/Debug/awiki_im_core.build'),
    );
    expect(
      script,
      contains('Keeping verified Flutter native Core intermediate'),
    );
    expect(script, contains('/usr/bin/cmp -s'));
    expect(script, contains('Flutter build used a stale native Core library'));
    expect(script, contains('pod_lock_snapshot'));
    expect(script, contains('AWikiMe-Joiner.app'));
    expect(script, contains('/usr/bin/lipo -archs'));
    expect(script, contains('/usr/bin/codesign --verify --deep --strict'));
  });
  test(
    'manual builder rejects IDs outside native development custody',
    () async {
      final result = await Process.run(
        'bash',
        ['scripts/build_manual_dual_macos_apps.sh'],
        environment: {
          'AWIKI_MANUAL_ADMIN_BUNDLE_ID': 'ai.awiki.awikime.e2ee-test',
        },
      );
      expect(result.exitCode, 2);
      expect(
        result.stderr,
        contains('must use the ai.awiki.awikime.dev namespace'),
      );
    },
    skip: !Platform.isMacOS,
  );

  test(
    'manual builder rejects duplicate tenant endpoints before compiling',
    () async {
      final temporary = Directory.systemTemp.createTempSync(
        'manual-tenant-test-',
      );
      try {
        final config = File('${temporary.path}/tenants.json')
          ..writeAsStringSync(
            '{"tenants":{"primary":{"backend_origin":"https://same.example","did_host":"same.example"},'
            '"secondary":{"backend_origin":"https://same.example","did_host":"same.example"}}}',
          );
        final result = await Process.run(
          'bash',
          ['scripts/build_manual_dual_macos_apps.sh'],
          environment: {
            'AWIKI_TENANT_CONFIG_PATH': config.path,
            'FLUTTER_BIN': '/usr/bin/true',
          },
        );
        expect(result.exitCode, isNot(0));
        expect(
          result.stderr,
          contains('manual tenant endpoints must be present and distinct'),
        );
      } finally {
        temporary.deleteSync(recursive: true);
      }
    },
    skip: !Platform.isMacOS,
  );
}
