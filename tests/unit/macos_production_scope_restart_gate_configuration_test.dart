import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production Keychain gate separates prepare from zero-build execute', () {
    final script = File(
      'scripts/run_macos_production_scope_restart_gate.sh',
    ).readAsStringSync();

    expect(script, contains('AWIKI_IM_CORE_REPO_DIR'));
    expect(script, contains('build-sdk-native.sh'));
    expect(script, contains('--macos-only'));
    expect(script, contains(r'"$im_core_build_script" --macos-only'));
    expect(script, contains('native dependency build failed'));
    expect(script, contains('verify_im_core_native_artifact.sh'));
    expect(
      script,
      contains('native awiki_im_core provenance verification failed'),
    );
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
    expect(script, contains('--prepare-only'));
    expect(script, contains('--execute'));
    expect(script, contains('bundleRelativePath'));
    expect(script, contains('nativeDependencyBuildCount'));
    expect(script, contains('appBuildCount'));
    expect(script, contains('case_attestation.json'));
    expect(
      script,
      contains('"runId": run_id, "mode": "real", "cases": [case]'),
    );

    expect(script, contains('resource_ledger.json'));
    expect(script, contains('"executionBuildCommands": 0'));
    expect(script, contains(r'"--awiki-scope-probe-phase=$phase"'));

    final execute = script.split('execute_artifact() {').last;
    expect(execute, isNot(contains('flutter build')));
    expect(execute, isNot(contains('pod install')));
    expect(execute, isNot(contains('codesign --force')));
    expect(execute, isNot(contains('build-sdk-native.sh')));
  });
}
