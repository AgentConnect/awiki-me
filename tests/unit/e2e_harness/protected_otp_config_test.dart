import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/protected_otp_config.dart';

void main() {
  test('loads protected OTP without exposing it through object rendering', () {
    final root = Directory.systemTemp.createTempSync('awiki-protected-otp-');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/e2e.local.yaml')
      ..writeAsStringSync('otp:\n  phone: "+15550000006"\n  code: "294681"\n');

    final config = ProtectedOtpConfig.load(file.path);

    expect(config.phone, '+15550000006');
    expect(config.code, '294681');
    expect(config.toString(), 'ProtectedOtpConfig(<redacted>)');
    expect(config.toString(), isNot(contains('294681')));
  });

  test('rejects missing and malformed protected OTP config', () {
    final root = Directory.systemTemp.createTempSync('awiki-protected-otp-');
    addTearDown(() => root.deleteSync(recursive: true));
    final malformed = File('${root.path}/malformed.yaml')
      ..writeAsStringSync('otp:\n  phone: "+15550000006"\n  code: "12345"\n');

    expect(
      () => ProtectedOtpConfig.load('${root.path}/missing.yaml'),
      throwsStateError,
    );
    expect(() => ProtectedOtpConfig.load(malformed.path), throwsStateError);
  });

  test('uses only a complete protected environment override', () {
    final root = Directory.systemTemp.createTempSync('awiki-protected-otp-');
    addTearDown(() => root.deleteSync(recursive: true));
    final file = File('${root.path}/e2e.local.yaml')
      ..writeAsStringSync('otp:\n  phone: "+15550000006"\n  code: "294681"\n');

    final config = ProtectedOtpConfig.load(
      file.path,
      environment: const <String, String>{
        'AWIKI_E2E_OTP_PHONE': '+15550000007',
        'AWIKI_E2E_OTP_CODE': '836492',
      },
    );

    expect(config.phone, '+15550000007');
    expect(config.code, '836492');
    expect(config.toString(), isNot(contains('836492')));
    expect(
      () => ProtectedOtpConfig.load(
        file.path,
        environment: const <String, String>{
          'AWIKI_E2E_OTP_PHONE': '+15550000007',
        },
      ),
      throwsStateError,
    );
  });
}
