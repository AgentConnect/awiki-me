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

  test('Debug App uses a stable Apple Development signing identity', () {
    final source = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final start = source.indexOf('33CC10FC2044A3C60003C045 /* Debug */ = {');
    final end = source.indexOf('\n\t\t};', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final debugTarget = source.substring(start, end);
    expect(debugTarget, contains('CODE_SIGN_IDENTITY = "Apple Development";'));
    expect(debugTarget, contains('DEVELOPMENT_TEAM = DT9HA3J8KE;'));
    expect(
      debugTarget,
      contains('PRODUCT_BUNDLE_IDENTIFIER = ai.awiki.awikime.dev;'),
    );
    expect(
      debugTarget,
      contains('AWIKI_APP_DISPLAY_NAME = "AWiki Me (Development)";'),
    );
    expect(debugTarget, isNot(contains('CODE_SIGN_IDENTITY = "-";')));

    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(infoPlist, contains('<key>CFBundleDisplayName</key>'));
    expect(
      '<string>\$(AWIKI_APP_DISPLAY_NAME)</string>'.allMatches(infoPlist),
      hasLength(2),
    );
    for (final locale in <String>['en', 'zh-Hans']) {
      final localizedInfo = File(
        'macos/Runner/$locale.lproj/InfoPlist.strings',
      ).readAsStringSync();
      expect(localizedInfo, isNot(contains('"CFBundleName"')));
    }
  });
}
