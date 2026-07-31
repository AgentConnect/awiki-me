import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Keychain gate prepares one universal native dependency', () {
    final script = File(
      'scripts/run_macos_production_scope_restart_gate.sh',
    ).readAsStringSync();

    expect(script, contains('AWIKI_IM_CORE_REPO_DIR'));
    expect(script, contains('build-sdk-native.sh'));
    expect(script, contains('--macos-only'));
    expect(script, contains(r'if ! "$im_core_build_script" --macos-only'));
    expect(script, contains('native awiki_im_core build failed'));
    expect(script, contains(r'lipo "$library" -verify_arch arm64 x86_64'));
    expect(
      script,
      contains(
        'build/macos/Build/Products/Release/XCFrameworkIntermediates/awiki_im_core',
      ),
    );
    expect(script, contains('--config-only --release --no-pub'));
    expect(
      script,
      contains('release platform configuration generation failed'),
    );
    expect(script, contains('(cd macos && pod install)'));
    expect(script, contains('CocoaPods installation failed'));
    expect(script, contains('native dependency preparation failed'));
    expect(
      script.indexOf('prepare_native_dependency ||'),
      lessThan(script.indexOf('run_phase provision')),
    );
    expect(script, contains('Podfile.lock changed during release phases'));
  });
}
