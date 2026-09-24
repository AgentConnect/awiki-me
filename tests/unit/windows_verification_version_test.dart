import 'package:flutter_test/flutter_test.dart';

import '../../tool/validate_windows_verification_version.dart';

void main() {
  test('numeric verification metadata fits both Core and Windows', () {
    validateWindowsVerificationVersion('0.1.34', '45');
    validateWindowsVerificationVersion('65535.0.65535', '65535');
  });

  test('rejects the installer version that failed native startup', () {
    expect(
      () => validateWindowsVerificationVersion('0.1.34-test.1', '44'),
      throwsFormatException,
    );
  });

  test('rejects ambiguous versions and invalid Windows version components', () {
    for (final version in [
      '',
      '0.1',
      '0.1.34.45',
      '01.1.34',
      '0.1.34+45',
      '0.1.65536',
      '-1.0.0',
      '0.1.34\n',
      '0.1.34 ',
    ]) {
      expect(
        () => validateWindowsVerificationVersion(version, '45'),
        throwsFormatException,
        reason: version,
      );
    }
    for (final build in ['', '0', '045', '-1', '1.5', '65536', '45\n']) {
      expect(
        () => validateWindowsVerificationVersion('0.1.34', build),
        throwsFormatException,
        reason: build,
      );
    }
  });
}
