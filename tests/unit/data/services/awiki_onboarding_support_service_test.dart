import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_support_service.dart';
import 'package:awiki_me/src/application/models/onboarding_server_info.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
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

    final receipt = await service.sendRegistrationOtp(
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
    expect(receipt.retryAfterSeconds, 60);
    expect(receipt.retryAt, DateTime.utc(2026, 8, 5, 6, 1));
    expect(userClient.sentEmailBaseUrls, ['https://example.test']);
    expect(userClient.sentEmails, ['alice@example.test']);
    expect(userClient.sentEmailHandles, ['alice']);
    expect(serverInfo.service.kind, 'user-service');
    expect(serverInfo.supportsPhoneHandleRecovery, isTrue);
    expect(serverInfo.agents.skillOnboarding.supportsCurrentProtocol, isTrue);
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

  test(
    'maps the structured server rate limit without parsing its message',
    () async {
      final userClient = _FakeUserClient(
        registrationOtpError: const AwikiOnboardingUtilityError(
          rpcCode: -32005,
          message: 'localized text may change',
          data: <String, Object?>{
            'code': 'otp_rate_limited',
            'retry_after_seconds': 37,
            'retry_at': '2026-08-05T06:00:37Z',
          },
        ),
      );
      final service = AwikiOnboardingSupportService(
        userServiceUrl: 'https://example.test',
        userClient: userClient,
      );

      await expectLater(
        service.sendRegistrationOtp(
          phone: '13800138000',
          handle: 'alice',
          domain: 'awiki.ai',
          fullHandle: 'alice.awiki.ai',
        ),
        throwsA(
          isA<RegistrationOtpRateLimited>()
              .having((error) => error.retryAfterSeconds, 'seconds', 37)
              .having(
                (error) => error.retryAt,
                'retryAt',
                DateTime.utc(2026, 8, 5, 6, 0, 37),
              ),
        ),
      );
    },
  );

  test(
    'fails closed when the registration OTP retry boundary is invalid',
    () async {
      final userClient = _FakeUserClient(
        registrationOtpResult: const <String, Object?>{
          'retry_after_seconds': 60,
          'retry_at': '2026-08-05T06:01:00+08:00',
        },
      );
      final service = AwikiOnboardingSupportService(
        userServiceUrl: 'https://example.test',
        userClient: userClient,
      );

      await expectLater(
        service.sendRegistrationOtp(
          phone: '13800138000',
          handle: 'alice',
          domain: 'awiki.ai',
          fullHandle: 'alice.awiki.ai',
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

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

  test(
    'handle Recovery selects one valid phone method and tolerates extensions',
    () {
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
            _recoveryMethod('future_method', 'future_verification'),
          ],
        }).supportsPhoneHandleRecovery,
        isTrue,
      );
      expect(
        _serverInfoWithRecovery(<String, Object?>{
          'methods': <Object?>[
            _recoveryMethod('phone', 'sms_otp'),
            _recoveryMethod('phone', 'sms_otp'),
          ],
        }).supportsPhoneHandleRecovery,
        isFalse,
      );
    },
  );

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

  test('Skill onboarding capability is optional and fails closed', () {
    expect(
      _serverInfoWithAgents(
        null,
      ).agents.skillOnboarding.supportsCurrentProtocol,
      isFalse,
    );
    expect(
      _serverInfoWithAgents(<String, Object?>{
        'skill_onboarding': <String, Object?>{
          'enabled': true,
          'protocol_version': 1,
          'onboarding_path': '/cli/onboarding.md',
          'display_name_binding': 'token_scope_v1',
        },
      }).agents.skillOnboarding.supportsDisplayNameBinding,
      isTrue,
    );
    final legacyCapability = _serverInfoWithAgents(<String, Object?>{
      'skill_onboarding': <String, Object?>{
        'enabled': true,
        'protocol_version': 1,
        'onboarding_path': '/cli/onboarding.md',
      },
    }).agents.skillOnboarding;
    expect(legacyCapability.supportsCurrentProtocol, isTrue);
    expect(legacyCapability.supportsDisplayNameBinding, isFalse);
    for (final malformed in <Object?>[
      <String, Object?>{
        'skill_onboarding': <String, Object?>{
          'enabled': true,
          'protocol_version': 2,
          'onboarding_path': '/cli/onboarding.md',
        },
      },
      <String, Object?>{
        'skill_onboarding': <String, Object?>{
          'enabled': true,
          'protocol_version': 1,
          'onboarding_path': 'https://example.com/onboarding.md',
        },
      },
      <String, Object?>{
        'skill_onboarding': <String, Object?>{
          'enabled': 'true',
          'protocol_version': 1,
          'onboarding_path': '/cli/onboarding.md',
        },
      },
      <String, Object?>{
        'skill_onboarding': <String, Object?>{
          'enabled': true,
          'protocol_version': '1',
          'onboarding_path': '/cli/onboarding.md',
        },
      },
    ]) {
      expect(
        _serverInfoWithAgents(
          malformed,
        ).agents.skillOnboarding.supportsCurrentProtocol,
        isFalse,
      );
    }
  });

  test('Skill group membership is independent and fails closed', () {
    final enabled = _serverInfoWithAgents(<String, Object?>{
      'skill_onboarding': <String, Object?>{
        'enabled': false,
        'protocol_version': 1,
        'onboarding_path': '/cli/onboarding.md',
      },
      'skill_group_membership': <String, Object?>{
        'enabled': true,
        'protocol_version': 1,
        'required_capability': 'group_membership_v1',
      },
    });
    expect(enabled.agents.skillOnboarding.supportsCurrentProtocol, isFalse);
    expect(enabled.agents.skillGroupMembership.supportsCurrentProtocol, isTrue);

    for (final malformed in <Object?>[
      null,
      <String, Object?>{'enabled': true},
      <String, Object?>{
        'enabled': true,
        'protocol_version': 2,
        'required_capability': 'group_membership_v1',
      },
      <String, Object?>{
        'enabled': true,
        'protocol_version': 1,
        'required_capability': 'future_capability',
      },
      <String, Object?>{
        'enabled': 'true',
        'protocol_version': 1,
        'required_capability': 'group_membership_v1',
      },
    ]) {
      expect(
        _serverInfoWithAgents(<String, Object?>{
          if (malformed != null) 'skill_group_membership': malformed,
        }).agents.skillGroupMembership.supportsCurrentProtocol,
        isFalse,
      );
    }
  });
}

OnboardingServerInfo _serverInfoWithAgents(Object? agents) {
  return OnboardingServerInfo.fromJson(<String, Object?>{
    'schema_version': 1,
    'service': <String, Object?>{
      'kind': 'user-service',
      'name': 'AWiki User Service',
    },
    'identity': <String, Object?>{
      'handle_registration': <String, Object?>{
        'enabled': true,
        'methods': <Object?>[],
      },
    },
    if (agents != null) 'agents': agents,
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
  _FakeUserClient({
    this.availabilityResult = const <String, Object?>{},
    this.registrationOtpResult = const <String, Object?>{
      'retry_after_seconds': 60,
      'retry_at': '2026-08-05T06:01:00Z',
    },
    this.registrationOtpError,
  }) : super(
         serviceClient: AwikiOnboardingUtilityHttpClient(
           baseUrl: 'https://example.test',
         ),
       );

  final Map<String, Object?> availabilityResult;
  final Map<String, Object?> registrationOtpResult;
  final AwikiOnboardingUtilityError? registrationOtpError;
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
      'agents': <String, Object?>{
        'skill_onboarding': <String, Object?>{
          'enabled': true,
          'protocol_version': 1,
          'onboarding_path': '/cli/onboarding.md',
        },
      },
    };
  }

  @override
  Future<Map<String, Object?>> sendRegistrationOtp({
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
    final error = registrationOtpError;
    if (error != null) {
      throw error;
    }
    return registrationOtpResult;
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
