// [INPUT]: Host operating system or a checked-in desktop platform value.
// [OUTPUT]: The normalized macOS/Linux desktop E2E platform.
// [POS]: Platform selection contract shared by runner orchestration modules.

import 'dart:io';

import 'failure.dart';

enum DesktopE2ePlatform {
  macos,
  linux;

  static DesktopE2ePlatform fromHost() {
    if (Platform.isMacOS) {
      return DesktopE2ePlatform.macos;
    }
    if (Platform.isLinux) {
      return DesktopE2ePlatform.linux;
    }
    throw E2eFailure('Only macOS and Linux desktop E2E are supported.');
  }

  static DesktopE2ePlatform parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'macos' => DesktopE2ePlatform.macos,
      'linux' => DesktopE2ePlatform.linux,
      _ => throw E2eFailure(
        'Unsupported desktop platform "$value". Use macos or linux.',
      ),
    };
  }
}
