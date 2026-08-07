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
    expect(script, contains('AWikiMe-Joiner.app'));
    expect(script, contains('/usr/bin/lipo -archs'));
    expect(script, contains('/usr/bin/codesign --verify --deep --strict'));
  });
}
