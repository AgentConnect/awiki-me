import 'models/onboarding_server_info.dart';
import '../domain/repositories/awiki_account_gateway.dart';

abstract interface class OnboardingSupportService {
  Future<OnboardingServerInfo> loadServerInfo();

  Future<void> sendOtp({required String phone});

  Future<void> sendRegistrationOtp({
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
