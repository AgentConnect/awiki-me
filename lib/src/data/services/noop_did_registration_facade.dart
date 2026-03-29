import '../../domain/services/did_registration_facade.dart';

class NoopDidRegistrationFacade implements DidRegistrationFacade {
  @override
  Future<Map<String, Object?>> buildRegisterHandleParams({
    String? phone,
    String? otp,
    String? email,
    required String handle,
    String? inviteCode,
    String? nickName,
  }) async {
    final authHint = email?.isNotEmpty == true ? '邮箱' : '手机号+验证码';
    throw UnsupportedError(
      'AWiki Me 当前未接入 DID 注册插件（$authHint 注册）。请先使用 Python 脚本注册并导入会话，'
      '或接入原生插件后再在 App 内完成注册。',
    );
  }

  @override
  Future<String> generateDidAuthHeader({
    required Map<String, Object?> didDocument,
    required String privateKeyPem,
    required String domain,
  }) async {
    throw UnsupportedError(
      'AWiki Me 当前未接入 DID 注册插件，无法自动刷新 token。',
    );
  }

  @override
  Future<bool> isSupported() async {
    return false;
  }
}
