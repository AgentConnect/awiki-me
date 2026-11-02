// [INPUT]: Host operating system or a checked-in desktop platform value.
// [OUTPUT]: The normalized macOS/Linux/Windows desktop E2E platform.
// [POS]: Platform selection contract shared by runner orchestration modules.

import 'dart:io';

import 'failure.dart';

enum DesktopE2ePlatform {
  macos,
  linux,
  windows;

  static DesktopE2ePlatform fromHost() {
    if (Platform.isMacOS) {
      return DesktopE2ePlatform.macos;
    }
    if (Platform.isLinux) {
      return DesktopE2ePlatform.linux;
    }
    if (Platform.isWindows) {
      return DesktopE2ePlatform.windows;
    }
    throw E2eFailure(
      'Only macOS, Linux, and Windows desktop E2E are supported.',
    );
  }

  static DesktopE2ePlatform parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'macos' => DesktopE2ePlatform.macos,
      'linux' => DesktopE2ePlatform.linux,
      'windows' => DesktopE2ePlatform.windows,
      _ => throw E2eFailure(
        'Unsupported desktop platform "$value". Use macos, linux, or windows.',
      ),
    };
  }
}
