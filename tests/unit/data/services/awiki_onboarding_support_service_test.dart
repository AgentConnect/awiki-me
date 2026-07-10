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
    await service.sendEmailVerification(
      email: ' Alice@Example.Test ',
      handle: ' Alice ',
    );
    final serverInfo = await service.loadServerInfo();
    final verified = await service.checkEmailVerified(
      email: ' Alice@Example.Test ',
      handle: ' Alice ',
    );
    final status = await service.lookupHandleRegistration(handle: ' Alice ');

    expect(userClient.sentOtpPhones, ['+8613800138000']);
    expect(userClient.sentEmailBaseUrls, ['https://example.test']);
    expect(userClient.sentEmails, ['alice@example.test']);
    expect(userClient.sentEmailHandles, ['alice']);
    expect(serverInfo.service.kind, 'user-service');
    expect(userClient.loadServerInfoCalls, 1);
    expect(verified, isTrue);
    expect(userClient.checkedEmails, ['alice@example.test']);
    expect(userClient.checkedEmailHandles, ['alice']);
    expect(userClient.lookups, ['alice']);
    expect(status, HandleRegistrationStatus.registered);
  });

  test('rejects invalid phone without calling utility client', () async {
    final userClient = _FakeUserClient();
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: userClient,
    );

    expect(
      () => service.sendOtp(phone: 'not-a-phone'),
      throwsA(isA<ArgumentError>()),
    );

    expect(userClient.sentOtpPhones, isEmpty);
  });

  test('rejects invalid handle without calling utility client', () async {
    final userClient = _FakeUserClient();
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: userClient,
    );

    await expectLater(
      service.lookupHandleRegistration(handle: 'alice_test'),
      throwsA(isA<ArgumentError>()),
    );

    expect(userClient.lookups, isEmpty);
  });

  test('maps structured handle_not_found into notRegistered', () async {
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: _FakeUserClient(
        lookupError: const AwikiOnboardingUtilityError(
          rpcCode: -32004,
          message: 'not_found',
          data: <String, Object?>{'code': 'handle_not_found'},
        ),
      ),
    );

    expect(
      await service.lookupHandleRegistration(handle: 'missing'),
      HandleRegistrationStatus.notRegistered,
    );
  });

  test(
    'does not map generic open-server rpc not found into notRegistered',
    () async {
      final service = AwikiOnboardingSupportService(
        userServiceUrl: 'https://example.test',
        userClient: _FakeUserClient(
          lookupError: const AwikiOnboardingUtilityError(
            rpcCode: -32004,
            message: 'not_found',
          ),
        ),
      );

      await expectLater(
        service.lookupHandleRegistration(handle: 'missing'),
        throwsA(isA<AwikiOnboardingUtilityError>()),
      );
    },
  );

  test('maps user-service lookup not found into notRegistered', () async {
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: _FakeUserClient(
        lookupError: const AwikiOnboardingUtilityError(
          rpcCode: -32002,
          message: 'Handle not found',
          data: <String, Object?>{'code': 'handle_not_found'},
        ),
      ),
    );

    expect(
      await service.lookupHandleRegistration(handle: 'missing'),
      HandleRegistrationStatus.notRegistered,
    );
  });

  test(
    'does not map generic user-service rpc not found into notRegistered',
    () async {
      final service = AwikiOnboardingSupportService(
        userServiceUrl: 'https://example.test',
        userClient: _FakeUserClient(
          lookupError: const AwikiOnboardingUtilityError(
            rpcCode: -32002,
            message: 'Not found',
          ),
        ),
      );

      await expectLater(
        service.lookupHandleRegistration(handle: 'missing'),
        throwsA(isA<AwikiOnboardingUtilityError>()),
      );
    },
  );

  test(
    'maps exact legacy handle_not_found machine message into notRegistered',
    () async {
      final service = AwikiOnboardingSupportService(
        userServiceUrl: 'https://example.test',
        userClient: _FakeUserClient(
          lookupError: const AwikiOnboardingUtilityError(
            message: 'handle_not_found',
          ),
        ),
      );

      expect(
        await service.lookupHandleRegistration(handle: 'missing'),
        HandleRegistrationStatus.notRegistered,
      );
    },
  );

  test(
    'does not classify explanatory not found text as handle state',
    () async {
      final service = AwikiOnboardingSupportService(
        userServiceUrl: 'https://example.test',
        userClient: _FakeUserClient(
          lookupError: const AwikiOnboardingUtilityError(
            message: 'handle does not exist',
          ),
        ),
      );

      await expectLater(
        service.lookupHandleRegistration(handle: 'missing'),
        throwsA(isA<AwikiOnboardingUtilityError>()),
      );
    },
  );

  test('rejects non-e1 DID from handle lookup response', () async {
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: _FakeUserClient(
        lookupProfile: const <String, Object?>{
          'did': 'did:wba:awiki.ai:alice:k1_123',
        },
      ),
    );

    await expectLater(
      service.lookupHandleRegistration(handle: 'alice'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Only e1 DID identities are supported.',
        ),
      ),
    );
  });

  test('rejects handle lookup response without DID', () async {
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: _FakeUserClient(
        lookupProfile: const <String, Object?>{'handle': 'alice'},
      ),
    );

    await expectLater(
      service.lookupHandleRegistration(handle: 'alice'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Handle lookup response did not include a DID.',
        ),
      ),
    );
  });

  test('normalizes handle availability input and maps result fields', () async {
    final userClient = _FakeUserClient(
      availabilityResult: const <String, Object?>{
        'handle': 'alice',
        'domain': 'awiki.ai',
        'full_handle': 'alice.awiki.ai',
        'available': false,
        'reason': 'reserved',
        'message': 'Handle is reserved.',
      },
    );
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: userClient,
    );

    final result = await service.validateHandle(
      handle: ' Alice ',
      domain: ' AWIKI.AI ',
    );

    expect(userClient.validateHandleCalls, ['alice@awiki.ai']);
    expect(result.handle, 'alice');
    expect(result.domain, 'awiki.ai');
    expect(result.fullHandle, 'alice.awiki.ai');
    expect(result.available, isFalse);
    expect(result.reason, 'reserved');
    expect(result.message, 'Handle is reserved.');
  });
}

class _FakeUserClient extends AwikiOnboardingUtilityClient {
  _FakeUserClient({
    this.lookupError,
    this.lookupProfile = const <String, Object?>{
      'did': 'did:wba:awiki.ai:alice:e1_123',
    },
    this.availabilityResult = const <String, Object?>{},
  }) : super(
         serviceClient: AwikiOnboardingUtilityHttpClient(
           baseUrl: 'https://example.test',
         ),
       );

  final AwikiOnboardingUtilityError? lookupError;
  final Map<String, Object?> lookupProfile;
  final Map<String, Object?> availabilityResult;
  final List<String> sentOtpPhones = <String>[];
  final List<String> sentEmailBaseUrls = <String>[];
  final List<String> sentEmails = <String>[];
  final List<String> sentEmailHandles = <String>[];
  final List<String> checkedEmails = <String>[];
  final List<String> checkedEmailHandles = <String>[];
  final List<String> lookups = <String>[];
  final List<String> validateHandleCalls = <String>[];
  int loadServerInfoCalls = 0;

  @override
  Future<Map<String, Object?>> loadServerInfo() async {
    loadServerInfoCalls += 1;
    return <String, Object?>{
      'schema_version': 1,
      'service': <String, Object?>{
        'kind': 'user-service',
        'name': 'AWiki User Service',
      },
      'identity': <String, Object?>{
        'handle_registration': <String, Object?>{
          'enabled': true,
          'default_method': 'phone',
          'availability': 'open',
          'methods': <Object?>[
            <String, Object?>{
              'id': 'phone',
              'enabled': true,
              'verification': <String, Object?>{
                'required': true,
                'type': 'sms_otp',
              },
            },
          ],
        },
        'handle_recovery': <String, Object?>{
          'methods': <Object?>[
            <String, Object?>{
              'id': 'phone',
              'enabled': true,
              'verification': <String, Object?>{
                'required': true,
                'type': 'sms_otp',
              },
            },
          ],
        },
      },
    };
  }

  @override
  Future<void> sendOtp({required String phone}) async {
    sentOtpPhones.add(phone);
  }

  @override
  Future<void> sendEmailVerification({
    required String baseUrl,
    required String email,
    required String handle,
  }) async {
    sentEmailBaseUrls.add(baseUrl);
    sentEmails.add(email);
    sentEmailHandles.add(handle);
  }

  @override
  Future<bool> checkEmailVerified({
    required String baseUrl,
    required String email,
    required String handle,
  }) async {
    checkedEmails.add(email);
    checkedEmailHandles.add(handle);
    return true;
  }

  @override
  Future<Map<String, Object?>> getPublicProfile({
    required String didOrHandle,
    String? bearerToken,
  }) async {
    lookups.add(didOrHandle);
    final lookupError = this.lookupError;
    if (lookupError != null) {
      throw lookupError;
    }
    return lookupProfile;
  }

  @override
  Future<Map<String, Object?>> validateHandle({
    required String handle,
    String? domain,
  }) async {
    validateHandleCalls.add('$handle@${domain ?? ''}');
    return availabilityResult;
  }
}
