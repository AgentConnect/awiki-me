import 'models/onboarding_server_info.dart';
import '../domain/repositories/awiki_account_gateway.dart';

class RegistrationOtpSendReceipt {
  const RegistrationOtpSendReceipt({
    required this.retryAfterSeconds,
    required this.retryAt,
  });

  final int retryAfterSeconds;
  final DateTime retryAt;
}

class RegistrationOtpRateLimited implements Exception {
  const RegistrationOtpRateLimited({
    required this.retryAfterSeconds,
    required this.retryAt,
  });

  final int retryAfterSeconds;
  final DateTime retryAt;
}

abstract interface class OnboardingSupportService {
  Future<OnboardingServerInfo> loadServerInfo();

  Future<void> sendOtp({required String phone});

  Future<RegistrationOtpSendReceipt> sendRegistrationOtp({
    required String phone,
    required String handle,
    required String domain,
    required String fullHandle,
  });

  Future<void> sendEmailVerification({
    required String email,
    required String handle,
  });

  Future<bool> checkEmailVerified({
    required String email,
    required String handle,
  });

  Future<HandleAvailability> validateHandle({
    required String handle,
    String? domain,
  });
}
