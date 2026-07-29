import 'package:awiki_me/src/data/services/local_auth_user_presence_port.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  test(
    'returns true only after supported system authentication succeeds',
    () async {
      final service = LocalAuthUserPresencePort(
        supportCheck: () async => true,
        authenticator:
            ({
              required localizedReason,
              required biometricOnly,
              required sensitiveTransaction,
              required persistAcrossBackgrounding,
            }) async {
              expect(localizedReason, 'Confirm device approval');
              expect(biometricOnly, isFalse);
              expect(sensitiveTransaction, isTrue);
              expect(persistAcrossBackgrounding, isFalse);
              return true;
            },
      );

      expect(
        await service.confirm(reason: '  Confirm device approval  '),
        isTrue,
      );
    },
  );

  test(
    'returns false without prompting when the device is unsupported',
    () async {
      var promptCount = 0;
      final service = LocalAuthUserPresencePort(
        supportCheck: () async => false,
        authenticator:
            ({
              required localizedReason,
              required biometricOnly,
              required sensitiveTransaction,
              required persistAcrossBackgrounding,
            }) async {
              promptCount += 1;
              return true;
            },
      );

      expect(await service.confirm(reason: 'Confirm action'), isFalse);
      expect(promptCount, 0);
    },
  );

  test('returns false when the user rejects the system prompt', () async {
    final service = LocalAuthUserPresencePort(
      supportCheck: () async => true,
      authenticator:
          ({
            required localizedReason,
            required biometricOnly,
            required sensitiveTransaction,
            required persistAcrossBackgrounding,
          }) async => false,
    );

    expect(await service.confirm(reason: 'Confirm action'), isFalse);
  });

  test('fails closed for local-auth exceptions', () async {
    final service = LocalAuthUserPresencePort(
      supportCheck: () async => true,
      authenticator:
          ({
            required localizedReason,
            required biometricOnly,
            required sensitiveTransaction,
            required persistAcrossBackgrounding,
          }) async => throw const LocalAuthException(
            code: LocalAuthExceptionCode.userCanceled,
          ),
    );

    expect(await service.confirm(reason: 'Confirm action'), isFalse);
  });

  test('fails closed for platform exceptions', () async {
    final service = LocalAuthUserPresencePort(
      supportCheck: () async => throw PlatformException(code: 'failed'),
    );

    expect(await service.confirm(reason: 'Confirm action'), isFalse);
  });

  test('fails closed when the platform plugin is unavailable', () async {
    final service = LocalAuthUserPresencePort(
      supportCheck: () async => throw MissingPluginException(),
    );

    expect(await service.confirm(reason: 'Confirm action'), isFalse);
  });

  test('rejects a blank reason without checking platform support', () async {
    var supportCheckCount = 0;
    final service = LocalAuthUserPresencePort(
      supportCheck: () async {
        supportCheckCount += 1;
        return true;
      },
    );

    expect(await service.confirm(reason: '   '), isFalse);
    expect(supportCheckCount, 0);
  });
}
