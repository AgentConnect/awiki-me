import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_support_service.dart';
import 'package:awiki_me/src/application/models/onboarding_server_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends the closed Manifest registration OTP RPC payload', () async {
    final rpc = _RecordingRpcClient();
    final client = AwikiOnboardingUtilityClient(serviceClient: rpc);

    await client.sendRegistrationOtp(
      phone: '+8613800138000',
      purpose: AwikiOnboardingUtilityClient.registrationOtpPurpose,
      handle: 'alice',
      domain: 'awiki.ai',
      fullHandle: 'alice.awiki.ai',
    );

    expect(rpc.path, AwikiOnboardingUtilityClient.handleRpcEndpoint);
    expect(rpc.method, 'send_otp');
    expect(rpc.params, <String, Object?>{
      'phone': '+8613800138000',
      'purpose': 'awiki.identity.register.v1',
      'handle': 'alice',
      'domain': 'awiki.ai',
      'full_handle': 'alice.awiki.ai',
    });
  });

  test('delegates onboarding utility calls with normalized inputs', () async {
    final userClient = _FakeUserClient();
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: userClient,
    );

    await service.sendRegistrationOtp(
      phone: '13800138000',
      handle: ' Alice ',
      domain: ' AWIKI.AI ',
      fullHandle: 'alice.awiki.ai',
    );
    await service.sendEmailVerification(
      email: ' Alice@Example.Test ',
      handle: ' Alice ',
    );
    final serverInfo = await service.loadServerInfo();
    final verified = await service.checkEmailVerified(
      email: ' Alice@Example.Test ',
      handle: ' Alice ',
    );

    expect(userClient.sentOtpPhones, ['+8613800138000']);
    expect(userClient.sentOtpPurposes, ['awiki.identity.register.v1']);
    expect(userClient.sentOtpHandles, ['alice']);
    expect(userClient.sentOtpDomains, ['awiki.ai']);
    expect(userClient.sentOtpFullHandles, ['alice.awiki.ai']);
    expect(userClient.sentEmailBaseUrls, ['https://example.test']);
    expect(userClient.sentEmails, ['alice@example.test']);
    expect(userClient.sentEmailHandles, ['alice']);
    expect(serverInfo.service.kind, 'user-service');
    expect(serverInfo.supportsPhoneHandleRecovery, isTrue);
    expect(userClient.loadServerInfoCalls, 1);
    expect(verified, isTrue);
    expect(userClient.checkedEmails, ['alice@example.test']);
    expect(userClient.checkedEmailHandles, ['alice']);
  });

  test('rejects invalid phone without calling utility client', () async {
    final userClient = _FakeUserClient();
    final service = AwikiOnboardingSupportService(
      userServiceUrl: 'https://example.test',
      userClient: userClient,
    );

    expect(
      () => service.sendRegistrationOtp(
        phone: 'not-a-phone',
        handle: 'alice',
        domain: 'awiki.ai',
        fullHandle: 'alice.awiki.ai',
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(userClient.sentOtpPhones, isEmpty);
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

  test('handle Recovery capability is phone-only and fails closed', () {
    expect(
      _serverInfoWithRecovery(<String, Object?>{
        'methods': <Object?>[_recoveryMethod('phone', 'sms_otp')],
      }).supportsPhoneHandleRecovery,
      isTrue,
    );
    expect(
      _serverInfoWithRecovery(<String, Object?>{
        'enabled': false,
        'methods': <Object?>[_recoveryMethod('phone', 'sms_otp')],
      }).supportsPhoneHandleRecovery,
      isFalse,
    );
    expect(
      _serverInfoWithRecovery(<String, Object?>{
        'methods': <Object?>[_recoveryMethod('email', 'email_activation')],
      }).supportsPhoneHandleRecovery,
      isFalse,
    );
    expect(
      _serverInfoWithRecovery(<String, Object?>{
        'methods': <Object?>[
          _recoveryMethod('phone', 'sms_otp'),
          _recoveryMethod('email', 'email_activation'),
        ],
      }).supportsPhoneHandleRecovery,
      isFalse,
    );
  });

  test('missing or malformed handle Recovery advertisement fails closed', () {
    expect(_serverInfoWithRecovery(null).supportsPhoneHandleRecovery, isFalse);
    expect(
      _serverInfoWithRecovery(<String, Object?>{
        'methods': 'phone',
      }).supportsPhoneHandleRecovery,
      isFalse,
    );
    expect(
      _serverInfoWithRecovery(<String, Object?>{
        'methods': <Object?>[
          <String, Object?>{'id': 'phone', 'enabled': true},
        ],
      }).supportsPhoneHandleRecovery,
      isFalse,
    );
  });
}

OnboardingServerInfo _serverInfoWithRecovery(Object? recovery) {
  return OnboardingServerInfo.fromJson(<String, Object?>{
    'schema_version': 1,
    'service': <String, Object?>{
      'kind': 'user-service',
      'name': 'AWiki User Service',
    },
    'identity': <String, Object?>{
      'handle_registration': <String, Object?>{
        'enabled': true,
        'methods': <Object?>[_recoveryMethod('phone', 'sms_otp')],
      },
      if (recovery != null) 'handle_recovery': recovery,
    },
  });
}

Map<String, Object?> _recoveryMethod(String id, String verificationType) {
  return <String, Object?>{
    'id': id,
    'enabled': true,
    'verification': <String, Object?>{
      'required': true,
      'type': verificationType,
    },
  };
}

class _RecordingRpcClient extends AwikiOnboardingUtilityHttpClient {
  _RecordingRpcClient() : super(baseUrl: 'https://example.test');

  String? path;
  String? method;
  Map<String, Object?>? params;

  @override
  Future<Map<String, Object?>> rpcCall({
    required String path,
    required String method,
    required Map<String, Object?> params,
    String? bearerToken,
    String requestId = 'req-1',
  }) async {
    this.path = path;
    this.method = method;
    this.params = params;
    return const <String, Object?>{'ok': true};
  }
}

class _FakeUserClient extends AwikiOnboardingUtilityClient {
  _FakeUserClient({this.availabilityResult = const <String, Object?>{}})
    : super(
        serviceClient: AwikiOnboardingUtilityHttpClient(
          baseUrl: 'https://example.test',
        ),
      );

  final Map<String, Object?> availabilityResult;
  final List<String> sentOtpPhones = <String>[];
  final List<String> sentOtpPurposes = <String>[];
  final List<String> sentOtpHandles = <String>[];
  final List<String> sentOtpDomains = <String>[];
  final List<String> sentOtpFullHandles = <String>[];
  final List<String> sentEmailBaseUrls = <String>[];
  final List<String> sentEmails = <String>[];
  final List<String> sentEmailHandles = <String>[];
  final List<String> checkedEmails = <String>[];
  final List<String> checkedEmailHandles = <String>[];
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
  Future<void> sendRegistrationOtp({
    required String phone,
    required String purpose,
    required String handle,
    required String domain,
    required String fullHandle,
  }) async {
    sentOtpPhones.add(phone);
    sentOtpPurposes.add(purpose);
    sentOtpHandles.add(handle);
    sentOtpDomains.add(domain);
    sentOtpFullHandles.add(fullHandle);
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
  Future<Map<String, Object?>> validateHandle({
    required String handle,
    String? domain,
  }) async {
    validateHandleCalls.add('$handle@${domain ?? ''}');
    return availabilityResult;
  }
}
