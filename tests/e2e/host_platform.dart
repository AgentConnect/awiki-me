// [INPUT]: Host OS/process facts, macOS sysctl output, and canonical App suite tiers.
// [OUTPUT]: Normalized Linux/macOS/Windows evidence and one tier-to-lane mapping.
// [POS]: Shared host contract for E2E applicability, reports, and native artifact checks.

import 'dart:io';

const Set<String> awikiSupportedTestPlatforms = <String>{
  'linux',
  'macos',
  'windows',
};

const Map<String, String> awikiAppTierExecutionLanes = <String, String>{
  'portable_product_ui': 'portable',
  'remote_product_ui': 'remote-client',
  'remote_product_application': 'remote-client',
  'remote_product_ui_security': 'remote-client-security',
  'native_release_security': 'macos-native-security',
  'optional_provider_product_ui': 'optional-provider',
  'remote_integration_diagnostic': 'remote-client-diagnostic',
  'windows_native_smoke': 'windows-native-smoke',
};

String awikiExecutionLaneForAppTier(String tier) {
  final lane = awikiAppTierExecutionLanes[tier];
  if (lane == null) {
    throw FormatException('Unsupported App E2E tier "$tier".');
  }
  return lane;
}

String normalizeAwikiHostArchitecture(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('-', '_');
  return switch (normalized) {
    'arm64' || 'aarch64' => 'arm64',
    'x86_64' || 'amd64' || 'x64' => 'x86_64',
    '' => throw const FormatException('Host architecture is empty.'),
    _ => normalized,
  };
}

String normalizeAwikiHostOperatingSystem(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('linux')) return 'linux';
  if (normalized == 'darwin' || normalized == 'macos') return 'macos';
  if (normalized.startsWith('win') ||
      normalized.startsWith('cygwin') ||
      normalized.startsWith('msys')) {
    return 'windows';
  }
  throw FormatException('Unsupported host operating system "$value".');
}

typedef E2eCommandOutput = Future<String> Function(List<String> command);

final class E2eHostPlatform {
  const E2eHostPlatform({
    required this.operatingSystem,
    required this.processArchitecture,
    required this.hardwareArchitecture,
    required this.translated,
  });

  final String operatingSystem;
  final String processArchitecture;
  final String hardwareArchitecture;
  final bool translated;

  static Future<E2eHostPlatform> detect({
    String? operatingSystem,
    String? machine,
    E2eCommandOutput? commandOutput,
  }) async {
    final os = normalizeAwikiHostOperatingSystem(
      operatingSystem ?? _currentOperatingSystem(),
    );
    final capture = commandOutput ?? _commandOutput;
    final rawMachine = machine ?? await _currentMachine(os, capture);
    final processArchitecture = normalizeAwikiHostArchitecture(rawMachine);
    var hardwareArchitecture = processArchitecture;
    var translated = false;

    if (os == 'macos') {
      translated =
          (await capture(<String>[
            'sysctl',
            '-in',
            'sysctl.proc_translated',
          ])).trim() ==
          '1';
      final armCapable =
          (await capture(<String>[
            'sysctl',
            '-n',
            'hw.optional.arm64',
          ])).trim() ==
          '1';
      if (armCapable) hardwareArchitecture = 'arm64';
    }

    return E2eHostPlatform(
      operatingSystem: os,
      processArchitecture: processArchitecture,
      hardwareArchitecture: hardwareArchitecture,
      translated: translated,
    );
  }

  void requireOperatingSystem(String expected) {
    if (operatingSystem != expected) {
      throw StateError(
        'Configured platform $expected does not match host $operatingSystem.',
      );
    }
  }

  void requireNativeMacToolchain() {
    if (operatingSystem == 'macos' &&
        (translated || processArchitecture != hardwareArchitecture)) {
      throw StateError(
        'Apple Silicon E2E builds require a native arm64 toolchain; '
        'Rosetta/x86 translation is not accepted.',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'os': operatingSystem,
    'processArchitecture': processArchitecture,
    'hardwareArchitecture': hardwareArchitecture,
    'translated': translated,
  };
}

String _currentOperatingSystem() {
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  return Platform.operatingSystem;
}

Future<String> _currentMachine(
  String operatingSystem,
  E2eCommandOutput capture,
) async {
  if (operatingSystem == 'windows') {
    return Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
  }
  return capture(<String>['uname', '-m']);
}

Future<String> _commandOutput(List<String> command) async {
  try {
    final result = await Process.run(command.first, command.sublist(1));
    return result.exitCode == 0 ? result.stdout.toString() : '';
  } on ProcessException {
    return '';
  }
}
