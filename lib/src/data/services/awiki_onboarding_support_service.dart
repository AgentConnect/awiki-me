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
  Future<RegistrationOtpSendReceipt> sendRegistrationOtp({
    required String phone,
    required String handle,
    required String domain,
    required String fullHandle,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedDomain = _normalizeDomain(domain);
    final canonicalFullHandle = '$normalizedHandle.$normalizedDomain';
    if (fullHandle != canonicalFullHandle) {
      throw ArgumentError('full_handle_not_canonical');
    }
    try {
      final payload = await _users.sendRegistrationOtp(
        phone: _normalizePhone(phone),
        purpose: AwikiOnboardingUtilityClient.registrationOtpPurpose,
        handle: normalizedHandle,
        domain: normalizedDomain,
        fullHandle: canonicalFullHandle,
      );
      return _registrationOtpReceipt(payload);
    } on AwikiOnboardingUtilityError catch (error) {
      final data = error.data;
      if (error.rpcCode == -32005 && data is Map) {
        final payload = data.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        if (payload['code'] == 'otp_rate_limited') {
          final receipt = _registrationOtpReceipt(payload);
          throw RegistrationOtpRateLimited(
            retryAfterSeconds: receipt.retryAfterSeconds,
            retryAt: receipt.retryAt,
          );
        }
      }
      rethrow;
    }
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

RegistrationOtpSendReceipt _registrationOtpReceipt(
  Map<String, Object?> payload,
) {
  final seconds = int.tryParse(
    payload['retry_after_seconds']?.toString() ?? '',
  );
  final retryAtRaw = payload['retry_at']?.toString();
  final retryAt = retryAtRaw == null ? null : DateTime.tryParse(retryAtRaw);
  if (seconds == null ||
      seconds < 1 ||
      seconds > 3600 ||
      retryAt == null ||
      !retryAt.isUtc ||
      !retryAtRaw!.endsWith('Z')) {
    throw const FormatException('registration_otp_retry_boundary_invalid');
  }
  return RegistrationOtpSendReceipt(
    retryAfterSeconds: seconds,
    retryAt: retryAt,
  );
}

String _normalizeDomain(String domain) {
  final normalized = domain.trim().toLowerCase().replaceFirst(
    RegExp(r'\.$'),
    '',
  );
  if (normalized.isEmpty || !normalized.contains('.')) {
    throw ArgumentError('did_domain_invalid');
  }
  return normalized;
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
