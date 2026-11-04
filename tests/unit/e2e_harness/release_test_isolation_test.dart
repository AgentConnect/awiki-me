import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/verify_release_test_isolation.dart';

void main() {
  test(
    'release rejects enabled and disabled test flags and encoded injection',
    () {
      for (final key in [
        'AWIKI_E2E',
        'AWIKI_E2E_IDENTITY_DELETION_CRASH_AFTER_PRODUCT_DELETE',
        'AWIKI_HANDLE_RECOVERY_E2E_PHASE',
        'AWIKI_MULTI_DEVICE_APP_PAIR_ROLE',
      ]) {
        for (final value in ['true', 'false', '1']) {
          expect(
            () => verifyReleaseTestIsolation({key: value}),
            throwsFormatException,
          );
          expect(
            () => verifyReleaseTestIsolation({
              'DART_DEFINES': base64Encode(utf8.encode('$key=$value')),
            }),
            throwsFormatException,
          );
        }
      }
      expect(
        () => verifyReleaseTestIsolation({'DART_DEFINES': 'broken@@'}),
        throwsFormatException,
      );
      expect(
        () => verifyReleaseTestIsolation({
          'FLUTTER_TARGET': 'integration_test/test.dart',
        }),
        throwsFormatException,
      );
      expect(
        () => verifyReleaseTestIsolation(
          {},
          arguments: ['--dart-define=AWIKI_E2E=true'],
        ),
        throwsFormatException,
      );
      verifyReleaseTestIsolation({
        'FLUTTER_TARGET': 'lib/main.dart',
        'DART_DEFINES': base64Encode(utf8.encode('AWIKI_APP_SOURCE_REF=abcd')),
      });
    },
  );
}
