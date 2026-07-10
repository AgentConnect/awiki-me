import '../domain/repositories/awiki_account_gateway.dart';
import 'models/onboarding_server_info.dart';

abstract interface class OnboardingSupportService {
  Future<OnboardingServerInfo> loadServerInfo();

  Future<void> sendOtp({required String phone});

  Future<void> sendEmailVerification({required String email});

  Future<bool> checkEmailVerified({required String email});

  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  });

  Future<HandleAvailability> validateHandle({
    required String handle,
    String? domain,
  });
}
