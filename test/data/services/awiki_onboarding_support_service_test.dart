import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_support_service.dart';
import 'package:awiki_me/src/domain/repositories/awiki_account_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delegates onboarding utility calls with normalized inputs', () async {
    final userClient = _FakeUserClient();
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: userClient,
    );

    await service.sendOtp(phone: '13800138000');
    await service.sendEmailVerification(email: ' Alice@Example.Test ');
    final verified = await service.checkEmailVerified(
      email: ' Alice@Example.Test ',
    );
    final status = await service.lookupHandleRegistration(handle: ' Alice ');

    expect(userClient.sentOtpPhones, ['+8613800138000']);
    expect(userClient.sentEmailBaseUrls, ['https://example.test']);
    expect(userClient.sentEmails, ['alice@example.test']);
    expect(verified, isTrue);
    expect(userClient.checkedEmails, ['alice@example.test']);
    expect(userClient.lookups, ['alice']);
    expect(status, HandleRegistrationStatus.registered);
  });

  test('maps handle not found into notRegistered', () async {
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: _FakeUserClient(lookupMissing: true),
    );

    expect(
      await service.lookupHandleRegistration(handle: 'missing'),
      HandleRegistrationStatus.notRegistered,
    );
  });
}

class _FakeUserClient extends AwikiOnboardingUtilityClient {
  _FakeUserClient({this.lookupMissing = false})
    : super(
        serviceClient: AwikiOnboardingUtilityHttpClient(
          baseUrl: 'https://example.test',
        ),
      );

  final bool lookupMissing;
  final List<String> sentOtpPhones = <String>[];
  final List<String> sentEmailBaseUrls = <String>[];
  final List<String> sentEmails = <String>[];
  final List<String> checkedEmails = <String>[];
  final List<String> lookups = <String>[];

  @override
  Future<void> sendOtp({required String phone}) async {
    sentOtpPhones.add(phone);
  }

  @override
  Future<void> sendEmailVerification({
    required String baseUrl,
    required String email,
  }) async {
    sentEmailBaseUrls.add(baseUrl);
    sentEmails.add(email);
  }

  @override
  Future<bool> checkEmailVerified({
    required String baseUrl,
    required String email,
  }) async {
    checkedEmails.add(email);
    return true;
  }

  @override
  Future<Map<String, Object?>> getPublicProfile({
    required String didOrHandle,
    String? bearerToken,
  }) async {
    lookups.add(didOrHandle);
    if (lookupMissing) {
      throw const AwikiOnboardingUtilityError(message: 'handle not found');
    }
    return const <String, Object?>{'did': 'did:wba:awiki.ai:alice:e1_123'};
  }
}
