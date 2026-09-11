import 'package:flutter_test/flutter_test.dart';

import '../../e2e/host_platform.dart';

void main() {
  test('normalizes host architectures without fixing macOS to x86', () {
    expect(normalizeAwikiHostArchitecture('arm64'), 'arm64');
    expect(normalizeAwikiHostArchitecture('aarch64'), 'arm64');
    expect(normalizeAwikiHostArchitecture('x86_64'), 'x86_64');
    expect(normalizeAwikiHostArchitecture('AMD64'), 'x86_64');
  });

  test('platform schema explicitly preserves Windows', () {
    expect(
      awikiSupportedTestPlatforms,
      containsAll(<String>['linux', 'macos', 'windows']),
    );
    expect(normalizeAwikiHostOperatingSystem('win32'), 'windows');
    expect(
      awikiExecutionLaneForAppTier('windows_native_smoke'),
      'windows-native-smoke',
    );
  });

  test('detects native Apple Silicon and translated x86 separately', () async {
    Future<String> native(List<String> command) async {
      return command.last == 'hw.optional.arm64' ? '1\n' : '0\n';
    }

    final arm = await E2eHostPlatform.detect(
      operatingSystem: 'darwin',
      machine: 'arm64',
      commandOutput: native,
    );
    expect(arm.processArchitecture, 'arm64');
    expect(arm.hardwareArchitecture, 'arm64');
    expect(arm.translated, isFalse);
    expect(arm.requireNativeMacToolchain, returnsNormally);

    Future<String> translated(List<String> _) async => '1\n';
    final rosetta = await E2eHostPlatform.detect(
      operatingSystem: 'darwin',
      machine: 'x86_64',
      commandOutput: translated,
    );
    expect(rosetta.processArchitecture, 'x86_64');
    expect(rosetta.hardwareArchitecture, 'arm64');
    expect(rosetta.translated, isTrue);
    expect(rosetta.requireNativeMacToolchain, throwsStateError);
  });

  test('canonical App tiers each map to one lane', () {
    expect(awikiExecutionLaneForAppTier('portable_product_ui'), 'portable');
    expect(
      awikiExecutionLaneForAppTier('remote_product_ui_security'),
      'remote-client-security',
    );
    expect(
      () => awikiExecutionLaneForAppTier('product_ui'),
      throwsFormatException,
    );
  });
}
