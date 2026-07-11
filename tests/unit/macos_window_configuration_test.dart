import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS main window defaults to the larger chat workspace', () {
    final source = File(
      'macos/Runner/Base.lproj/MainMenu.xib',
    ).readAsStringSync();

    expect(
      source,
      contains(
        '<rect key="contentRect" x="335" y="390" width="1180" height="760"/>',
      ),
    );
    expect(
      source,
      contains('<rect key="frame" x="0.0" y="0.0" width="1180" height="760"/>'),
    );
  });

  test('menu bar controller retains the main window for reopen', () {
    final source = File(
      'macos/Runner/MenuBarStatusController.swift',
    ).readAsStringSync();

    expect(source, contains('private var mainWindow: NSWindow?'));
    expect(source, isNot(contains('private weak var mainWindow: NSWindow?')));
    expect(source, contains('window.makeKeyAndOrderFront(nil)'));
  });
}
