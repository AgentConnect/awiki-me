import '../../application/config/awiki_environment_config.dart';
import '../../application/models/onboarding_server_info.dart';
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
  Future<OnboardingServerInfo> loadServerInfo() async {
    final payload = await _users.loadServerInfo();
    return OnboardingServerInfo.fromJson(payload);
  }

  @override
  Future<void> sendOtp({required String phone}) {
    return _users.sendOtp(phone: _normalizePhone(phone));
  }

  @override
  Future<void> sendEmailVerification({
    required String email,
    required String handle,
  }) {
    return _users.sendEmailVerification(
      baseUrl: userServiceUrl,
      email: email.trim().toLowerCase(),
      handle: _normalizeHandle(handle),
    );
  }

  @override
  Future<bool> checkEmailVerified({
    required String email,
    required String handle,
  }) {
    return _users.checkEmailVerified(
      baseUrl: userServiceUrl,
      email: email.trim().toLowerCase(),
      handle: _normalizeHandle(handle),
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

  @override
  Future<HandleAvailability> validateHandle({
    required String handle,
    String? domain,
  }) async {
    final normalizedHandle = _normalizeHandle(
      handle,
      minLength: 1,
      maxLength: 63,
    );
    final normalizedDomain = domain?.trim().toLowerCase();
    final result = await _users.validateHandle(
      handle: normalizedHandle,
      domain: normalizedDomain,
    );
    return HandleAvailability(
      handle: result['handle']?.toString() ?? normalizedHandle,
      domain: result['domain']?.toString(),
      fullHandle: result['full_handle']?.toString(),
      available: result['available'] == true,
      reason: result['reason']?.toString(),
      message: result['message']?.toString(),
    );
  }
}

String _normalizePhone(String phone) {
  final raw = phone.trim();
  final intlPattern = RegExp(r'^\+\d{1,3}\d{6,14}$');
  final cnLocalPattern = RegExp(r'^1[3-9]\d{9}$');
  if (raw.startsWith('+')) {
    if (!intlPattern.hasMatch(raw)) {
      throw ArgumentError('phone_invalid_intl_example');
    }
    return raw;
  }
  if (cnLocalPattern.hasMatch(raw)) {
    return '+86$raw';
  }
  throw ArgumentError('phone_invalid_intl_or_cn');
}

String _normalizeHandle(
  String handle, {
  int minLength = 2,
  int maxLength = 32,
}) {
  final normalized = handle.trim().toLowerCase();
  final pattern = RegExp('^[a-z0-9-]{$minLength,$maxLength}\$');
  if (!pattern.hasMatch(normalized)) {
    throw ArgumentError('handle_invalid_pattern');
  }
  return normalized;
}

bool _isHandleNotFoundError(AwikiOnboardingUtilityError error) {
  if (_machineCode(error.data) == 'handle_not_found') {
    return true;
  }
  return _machineCode(error.message) == 'handle_not_found';
}

String _machineCode(Object? value) {
  if (value is Map) {
    return _machineCode(value['code']);
  }
  return value?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
}

bool _isE1Did(String did) => did.trim().split(':').last.startsWith('e1_');

void _ensureE1Did(String did) {
  if (!_isE1Did(did)) {
    throw StateError('Only e1 DID identities are supported.');
  }
}
