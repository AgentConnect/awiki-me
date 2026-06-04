import '../../application/config/awiki_environment_config.dart';
import '../../application/onboarding_support_service.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import 'awiki_onboarding_utility_client.dart';

class AwikiOnboardingSupportService implements OnboardingSupportService {
  AwikiOnboardingSupportService({
    required this.userServiceUrl,
    AwikiOnboardingUtilityClient? userClient,
  }) : _userClient = userClient;

  factory AwikiOnboardingSupportService.fromEnvironment() {
    final userServiceUrl =
        AwikiEnvironmentConfig.fromEnvironment().userServiceUrl;
    return AwikiOnboardingSupportService(userServiceUrl: userServiceUrl);
  }

  final String userServiceUrl;
  final AwikiOnboardingUtilityClient? _userClient;
  AwikiOnboardingUtilityClient? _cachedUserClient;

  AwikiOnboardingUtilityClient get _users {
    return _userClient ??
        (_cachedUserClient ??= AwikiOnboardingUtilityClient(
          serviceClient: AwikiOnboardingUtilityHttpClient(
            baseUrl: userServiceUrl,
          ),
        ));
  }

  @override
  Future<void> sendOtp({required String phone}) {
    return _users.sendOtp(phone: _normalizePhone(phone));
  }

  @override
  Future<void> sendEmailVerification({required String email}) {
    return _users.sendEmailVerification(
      baseUrl: userServiceUrl,
      email: email.trim().toLowerCase(),
    );
  }

  @override
  Future<bool> checkEmailVerified({required String email}) {
    return _users.checkEmailVerified(
      baseUrl: userServiceUrl,
      email: email.trim().toLowerCase(),
    );
  }

  @override
  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    try {
      final result = await _users.getPublicProfile(
        didOrHandle: normalizedHandle,
      );
      final did = result['did']?.toString() ?? '';
      if (did.isEmpty) {
        throw StateError('Handle lookup response did not include a DID.');
      }
      _ensureE1Did(did);
      return HandleRegistrationStatus.registered;
    } on AwikiOnboardingUtilityError catch (error) {
      if (_isHandleNotFoundError(error)) {
        return HandleRegistrationStatus.notRegistered;
      }
      rethrow;
    }
  }
}

String _normalizePhone(String phone) {
  final raw = phone.trim();
  final intlPattern = RegExp(r'^\+\d{1,3}\d{6,14}$');
  final cnLocalPattern = RegExp(r'^1[3-9]\d{9}$');
  if (raw.startsWith('+')) {
    if (!intlPattern.hasMatch(raw)) {
      throw ArgumentError('手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000');
    }
    return raw;
  }
  if (cnLocalPattern.hasMatch(raw)) {
    return '+86$raw';
  }
  throw ArgumentError('手机号格式不正确，请输入国际格式或中国大陆 11 位手机号');
}

String _normalizeHandle(String handle) {
  final normalized = handle.trim().toLowerCase();
  final pattern = RegExp(r'^[a-z0-9-]{2,32}$');
  if (!pattern.hasMatch(normalized)) {
    throw ArgumentError('handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线');
  }
  return normalized;
}

bool _isHandleNotFoundError(AwikiOnboardingUtilityError error) {
  final normalized = error.message.toLowerCase();
  return normalized.contains('handle not found') ||
      normalized.contains('handle') &&
          (normalized.contains('not found') ||
              normalized.contains('does not exist'));
}

bool _isE1Did(String did) => did.trim().split(':').last.startsWith('e1_');

void _ensureE1Did(String did) {
  if (!_isE1Did(did)) {
    throw StateError('Only e1 DID identities are supported.');
  }
}
