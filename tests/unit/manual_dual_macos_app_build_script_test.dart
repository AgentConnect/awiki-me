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
    expect(script, contains('AWIKI_PRIMARY_TENANT_DOMAIN'));
    expect(script, contains('AWIKI_MULTI_DEVICE_HANDLE_RECOVERY_ENABLED'));
    expect(script, contains('HANDLE_RECOVERY_ENABLED:-true'));
    expect(script, contains('AWIKI_IM_CORE_REPO_DIR'));
    expect(script, contains('build-sdk-native.sh'));
    expect(script, contains('verify_im_core_native_artifact.sh'));
    expect(script, contains('--macos-only --macos-arch x86_64'));
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
}
