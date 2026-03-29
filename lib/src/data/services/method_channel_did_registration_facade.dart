import 'package:flutter/services.dart';

import '../../domain/services/did_registration_facade.dart';

class MethodChannelDidRegistrationFacade implements DidRegistrationFacade {
  MethodChannelDidRegistrationFacade({
    MethodChannel? channel,
  }) : _channel =
            channel ?? const MethodChannel('ai.awiki.awikime/did_registration');

  final MethodChannel _channel;

  @override
  Future<Map<String, Object?>> buildRegisterHandleParams({
    String? phone,
    String? otp,
    String? email,
    required String handle,
    String? inviteCode,
    String? nickName,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'buildRegisterHandleParams',
      <String, Object?>{
        'phone': phone,
        'otp': otp,
        'email': email,
        'handle': handle,
        'inviteCode': inviteCode,
        'nickName': nickName,
      },
    );
    if (result == null || result['did_document'] == null) {
      throw PlatformException(
        code: 'invalid_payload',
        message: 'DID registration plugin returned empty did_document payload.',
      );
    }
    return result;
  }

  @override
  Future<String> generateDidAuthHeader({
    required Map<String, Object?> didDocument,
    required String privateKeyPem,
    required String domain,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'generateDidAuthHeader',
      <String, Object?>{
        'did_document': didDocument,
        'private_key_pem': privateKeyPem,
        'domain': domain,
      },
    );
    if (result == null || result.isEmpty) {
      throw PlatformException(
        code: 'empty_auth_header',
        message: 'DID registration plugin returned empty authorization header.',
      );
    }
    return result;
  }

  @override
  Future<bool> isSupported() async {
    final result = await _channel.invokeMethod<bool>('isSupported');
    return result ?? false;
  }
}
