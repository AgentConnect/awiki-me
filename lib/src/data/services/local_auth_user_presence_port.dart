import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../application/ports/user_presence_port.dart';

typedef UserPresenceSupportCheck = Future<bool> Function();

typedef UserPresenceAuthenticator =
    Future<bool> Function({
      required String localizedReason,
      required bool biometricOnly,
      required bool sensitiveTransaction,
      required bool persistAcrossBackgrounding,
    });

class LocalAuthUserPresencePort implements UserPresencePort {
  LocalAuthUserPresencePort({
    LocalAuthentication? authentication,
    UserPresenceSupportCheck? supportCheck,
    UserPresenceAuthenticator? authenticator,
  }) : _authentication = authentication ?? LocalAuthentication(),
       _supportCheck = supportCheck,
       _authenticator = authenticator;

  final LocalAuthentication _authentication;
  final UserPresenceSupportCheck? _supportCheck;
  final UserPresenceAuthenticator? _authenticator;

  @override
  Future<bool> confirm({required String reason}) async {
    final localizedReason = reason.trim();
    if (localizedReason.isEmpty) {
      return false;
    }

    try {
      final supported =
          await (_supportCheck ?? _authentication.isDeviceSupported)();
      if (!supported) {
        return false;
      }
      final authenticate = _authenticator ?? _authenticate;
      return await authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: false,
      );
    } on LocalAuthException {
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _authenticate({
    required String localizedReason,
    required bool biometricOnly,
    required bool sensitiveTransaction,
    required bool persistAcrossBackgrounding,
  }) {
    return _authentication.authenticate(
      localizedReason: localizedReason,
      biometricOnly: biometricOnly,
      sensitiveTransaction: sensitiveTransaction,
      persistAcrossBackgrounding: persistAcrossBackgrounding,
    );
  }
}
