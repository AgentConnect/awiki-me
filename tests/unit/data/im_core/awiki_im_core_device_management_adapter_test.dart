import '../../identity_method_test_support.dart';
import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_device_management_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Web Join remains ordinary member approval without Root management',
    () async {
      final sdk = _WebApprovalCore();
      final adapter = _adapterWithCore(sdk);
      final prompt = await adapter.prepareDeviceJoinApproval(
        selector: sdk.resolvedDid,
        joinSessionId: 'web-join',
        sasConfirmed: true,
      );
      await adapter.confirmDeviceJoinApproval(
        approvalHandle: prompt.approvalHandle,
        userPresenceConfirmed: true,
      );
      expect(sdk.ordinaryCalls, 1);
    },
  );

  test(
    'App approval selects the explicit SDK management authorization',
    () async {
      final sdk = _ManagementApprovalCore();
      final adapter = _adapterWithCore(sdk);
      await adapter.confirmDeviceJoinApproval(
        approvalHandle: 'opaque-prompt-handle',
        userPresenceConfirmed: true,
      );
      expect(sdk.managementCalls, 1);
      expect(sdk.confirmed, isTrue);
    },
  );

  test(
    'local management readiness requires exact-device active root capability',
    () async {
      for (final ready in [false, true]) {
        final sdk = _IdentityDeviceSummaryCore(
          (_) async => _identityDeviceSummary(
            protocolDeviceId: 'device-new',
            role: core.IdentityDeviceRole.admin,
            readiness: ready
                ? core.IdentityDeviceReadiness.adminReady
                : core.IdentityDeviceReadiness.memberReady,
          ),
        );
        final adapter = _adapterWithCore(sdk);
        expect(
          await adapter.localManagementReady(
            selector: _did,
            protocolDeviceId: 'device-new',
          ),
          ready,
        );
        await expectLater(
          adapter.localManagementReady(
            selector: _did,
            protocolDeviceId: 'other-device',
          ),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          adapter.localManagementReady(
            selector: 'did:wba:example.test:other',
            protocolDeviceId: 'device-new',
          ),
          throwsA(isA<StateError>()),
        );
      }
    },
  );

  test(
    'Core Web Handle resolution may use a different identity domain',
    () async {
      final native = _PublicMethodCore()
        ..resolvedDid = 'did:web:identity.example:awiki:web:alice'
        ..capabilities = coreWebMethodCapabilities;
      final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
        coreInstance: () async => native,
        userServiceUrl: 'https://provider.example',
        targetHandleDomain: 'provider.example',
      );
      expect(await adapter.resolveJoinDid('alice'), native.resolvedDid);
      expect(native.resolvedHandle, 'alice.provider.example');
    },
  );

  test('sends Join SMS codes through the mounted auth endpoint', () async {
    late http.Request request;
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient((value) async {
        request = value;
        return http.Response('{"message":"Code sent."}', 200);
      }),
      beginDeviceJoin:
          ({
            required did,
            required operationId,
            required ttlSeconds,
            required accountVerificationGrant,
          }) async => _coreProgress(),
    );

    final receipt = await adapter.sendJoinSmsOtp(
      handle: ' Alice.AWIKI.INFO ',
      phone: ' +8613800138000 ',
    );

    expect(
      request.url.toString(),
      'https://awiki.info/user-service/v1/auth/sms-codes',
    );
    expect(jsonDecode(request.body), <String, Object?>{
      'phone': '+8613800138000',
      'purpose': 'awiki.device.join.v1',
      'target_handle': 'alice',
      'target_handle_domain': 'awiki.info',
      'rate_limit_seconds': 60,
    });
    expect(receipt.retryAfterSeconds, 60);
  });

  test('maps SMS 429 Retry-After to a bounded typed error', () async {
    const sensitive = 'provider-secret-must-not-escape';
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"detail":"$sensitive"}',
          429,
          headers: const <String, String>{'Retry-After': '17'},
        ),
      ),
    );

    Object? error;
    try {
      await adapter.sendJoinSmsOtp(handle: 'alice', phone: '+8613800138000');
    } catch (caught) {
      error = caught;
    }

    expect(
      error,
      isA<DeviceJoinSmsOtpRateLimited>().having(
        (value) => value.retryAfterSeconds,
        'retryAfterSeconds',
        17,
      ),
    );
    expect(error.toString(), isNot(contains(sensitive)));
  });

  test('uses safe SMS retry default when 429 metadata is absent', () async {
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient((_) async => http.Response('{}', 429)),
    );

    await expectLater(
      adapter.sendJoinSmsOtp(handle: 'alice', phone: '+8613800138000'),
      throwsA(
        isA<DeviceJoinSmsOtpRateLimited>().having(
          (value) => value.retryAfterSeconds,
          'retryAfterSeconds',
          60,
        ),
      ),
    );
  });

  test(
    'exchanges SMS OTP and immediately passes a redacted grant to Core',
    () async {
      const token = 'join-account-token-must-not-escape';
      late Map<String, Object?> requestBody;
      final native = _PublicMethodCore();
      var beginCalls = 0;
      final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
        coreInstance: () async => native,
        userServiceUrl: 'https://awiki.info',
        targetHandleDomain: 'awiki.info',
        httpClient: MockClient((request) async {
          expect(
            request.url.path,
            '/user-service/v1/auth/account-verification/exchange',
          );
          requestBody = (jsonDecode(request.body) as Map)
              .cast<String, Object?>();
          return http.Response(
            jsonEncode(<String, Object?>{
              'account_verification_token': token,
              'purpose': 'awiki.device.join.v1',
              'expires_at': '2026-07-19T00:05:00Z',
            }),
            200,
          );
        }),
        beginDeviceJoin:
            ({
              required did,
              required operationId,
              required ttlSeconds,
              required accountVerificationGrant,
            }) async {
              beginCalls += 1;
              expect(did, _did);
              expect(operationId, 'join-op-1');
              expect(ttlSeconds, 600);
              expect(
                accountVerificationGrant.toString(),
                contains('<redacted>'),
              );
              expect(
                accountVerificationGrant.toString(),
                isNot(contains(token)),
              );
              return _coreProgress();
            },
      );

      final progress = await adapter.beginDeviceJoinWithSms(
        handle: 'alice',
        phone: '+8613800138000',
        otp: '987580',
        operationId: 'join-op-1',
        ttlSeconds: 600,
      );

      expect(beginCalls, 1);
      expect(native.resolvedHandle, 'alice.awiki.info');
      expect(requestBody, <String, Object?>{
        'provider': 'sms',
        'purpose': 'awiki.device.join.v1',
        'phone': '+8613800138000',
        'code': '987580',
        'target_handle': 'alice',
        'target_handle_domain': 'awiki.info',
        'idempotency_scope': 'join-op-1',
      });
      expect(progress.joinSessionId, 'join-1');
      expect(progress.phase, DeviceJoinPhase.responsePrepared);
      expect(progress.sas, '482917');
    },
  );

  test('Core rejects a Handle binding before OTP exchange', () async {
    var requestCalls = 0;
    var beginCalls = 0;
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: () async => _PublicMethodCore()
        ..resolutionError = const core.AwikiImCoreException(
          code: 'permission_denied',
          message: 'invalid binding',
        ),
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient((request) async {
        requestCalls += 1;
        throw StateError('OTP exchange must not run');
      }),
      beginDeviceJoin:
          ({
            required did,
            required operationId,
            required ttlSeconds,
            required accountVerificationGrant,
          }) async {
            beginCalls += 1;
            return _coreProgress();
          },
    );

    await expectLater(
      adapter.beginDeviceJoinWithSms(
        handle: 'alice',
        phone: '+8613800138000',
        otp: '123456',
        operationId: 'join-op-invalid-domain',
        ttlSeconds: 600,
      ),
      throwsA(
        isA<DeviceManagementTransportException>().having(
          (error) => error.code,
          'code',
          'join_target_resolution_invalid',
        ),
      ),
    );
    expect(requestCalls, 0);
    expect(beginCalls, 0);
  });

  test('redacts Core discovery failures before OTP exchange', () async {
    const sensitive = 'profile-response-must-not-escape';
    var beginCalls = 0;
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: () async =>
          _PublicMethodCore()..resolutionError = StateError(sensitive),
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient(
        (_) async => http.Response('{"detail":"$sensitive"}', 503),
      ),
      beginDeviceJoin:
          ({
            required did,
            required operationId,
            required ttlSeconds,
            required accountVerificationGrant,
          }) async {
            beginCalls += 1;
            return _coreProgress();
          },
    );

    Object? error;
    try {
      await adapter.beginDeviceJoinWithSms(
        handle: 'alice',
        phone: '+8613800138000',
        otp: '123456',
        operationId: 'join-op-profile-error',
        ttlSeconds: 600,
      );
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<DeviceManagementTransportException>());
    expect(error.toString(), contains('join_target_resolution_failed'));
    expect(error.toString(), isNot(contains(sensitive)));
    expect(beginCalls, 0);
  });

  test('uses the qualified Handle domain for the internal exchange', () async {
    late Map<String, Object?> requestBody;
    String? resolvedHandle;
    String? resolvedDomain;
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: () async =>
          _PublicMethodCore()..resolvedDid = 'did:wba:example.org:user:e1_test',
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient((request) async {
        requestBody = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return http.Response(
          '{"account_verification_token":"token","purpose":"awiki.device.join.v1"}',
          200,
        );
      }),
      beginDeviceJoin:
          ({
            required did,
            required operationId,
            required ttlSeconds,
            required accountVerificationGrant,
          }) async => _coreProgress(),
      resolveJoinTarget: ({required handle, required domain}) async {
        resolvedHandle = handle;
        resolvedDomain = domain;
        return 'did:wba:example.org:user:e1_test';
      },
    );

    await adapter.beginDeviceJoinWithSms(
      handle: '@alice.example.org',
      phone: '+8613800138000',
      otp: '123456',
      operationId: 'join-op-2',
      ttlSeconds: 300,
    );

    expect(requestBody['target_handle'], 'alice');
    expect(requestBody['target_handle_domain'], 'example.org');
    expect(resolvedHandle, 'alice');
    expect(resolvedDomain, 'example.org');
  });

  test('never includes an exchange response body or token in errors', () async {
    const token = 'server-accidentally-echoed-secret-token';
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"detail":"$token","account_verification_token":"$token"}',
          503,
        ),
      ),
      beginDeviceJoin:
          ({
            required did,
            required operationId,
            required ttlSeconds,
            required accountVerificationGrant,
          }) async => _coreProgress(),
      resolveJoinTarget: _resolveAwikiJoinTarget,
    );

    Object? error;
    try {
      await adapter.beginDeviceJoinWithSms(
        handle: 'alice',
        phone: '+8613800138000',
        otp: '123456',
        operationId: 'join-op-3',
        ttlSeconds: 600,
      );
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<DeviceManagementTransportException>());
    expect(error.toString(), contains('account_verification_http_503'));
    expect(error.toString(), isNot(contains(token)));
  });

  test(
    'maps authorized registry roles and readiness without pending requests',
    () {
      final snapshot = deviceRegistryFromCore(
        const core.DeviceJoinRegistrySnapshot(
          did: _did,
          registryVersion: '7',
          devices: <core.DeviceRegistryAuthorizedDeviceSummary>[
            core.DeviceRegistryAuthorizedDeviceSummary(
              protocolDeviceId: 'admin-1',
              signingKeyId: 'did:key:sign',
              e2eeKeyId: 'did:key:e2ee',
              status: core.DeviceJoinAuthorizationStatus.active,
              role: core.DeviceJoinRole.admin,
              managementReady: false,
              isCurrent: true,
              authGeneration: '2',
            ),
          ],
        ),
      );

      expect(snapshot.did, _did);
      expect(snapshot.registryVersion, '7');
      expect(snapshot.currentDevice?.role, DeviceRole.admin);
      expect(snapshot.currentDevice?.managementReady, isFalse);
    },
  );

  test('maps an inactive Registry caller to a stable App error', () async {
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      userServiceUrl: 'https://awiki.info',
      targetHandleDomain: 'awiki.info',
      identityDeviceRegistry: ({required selector}) async {
        throw const core.AwikiImCoreException(
          code: 'service_error',
          message: 'localized server diagnostic',
          statusCode: 200,
          serviceCode: 'device.inactive',
        );
      },
    );

    await expectLater(
      adapter.identityDeviceRegistry(_did),
      throwsA(
        isA<DeviceManagementTransportException>().having(
          (error) => error.code,
          'code',
          'device_authorization_inactive',
        ),
      ),
    );
  });

  test('maps verified Join request notice without raw proof material', () {
    final request = deviceJoinRequestFromCore(
      const core.DeviceJoinRequestNotice(
        eventId: 'event-1',
        joinSessionId: 'join-2',
        did: _did,
        protocolDeviceId: 'member-2',
        candidateKeyFingerprint: 'sha256:fingerprint',
        issuedAt: '2026-07-19T00:00:00Z',
        expiresAt: '2026-07-19T00:10:00Z',
        state: core.DeviceJoinRemoteState.pending,
        claimedByCurrentDevice: false,
        canStartVerification: true,
      ),
    );

    expect(request.joinSessionId, 'join-2');
    expect(request.candidateKeyFingerprint, 'sha256:fingerprint');
    expect(request.canStartVerification, isTrue);
    expect(request.expiresAt.isUtc, isTrue);
    expect(request.toString(), isNot(contains('proof')));
  });

  test('local session summaries default to pending until a local refresh', () {
    final progress = deviceJoinSessionFromCore(
      const core.DeviceJoinSessionSummary(
        joinSessionId: 'join-local',
        did: _did,
        protocolDeviceId: 'device-local',
        side: core.DeviceJoinSide.admin,
        phase: core.DeviceJoinPhase.cancelled,
        expiresAt: '2026-07-19T00:10:00Z',
      ),
    );

    expect(progress.side, DeviceJoinSide.admin);
    expect(progress.phase, DeviceJoinPhase.cancelled);
    expect(progress.remoteState, DeviceJoinRemoteState.pending);
    expect(progress.isTerminal, isTrue);
  });

  test(
    'device revoke forwards only safe inputs and maps safe result',
    () async {
      core.IdentitySelector? capturedSelector;
      String? capturedTarget;
      bool? capturedPresence;
      final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
        coreInstance: _unusedCore,
        userServiceUrl: 'https://awiki.info',
        targetHandleDomain: 'awiki.info',
        revokeDevice:
            ({
              required selector,
              required targetDeviceId,
              required userPresenceConfirmed,
            }) async {
              capturedSelector = selector;
              capturedTarget = targetDeviceId;
              capturedPresence = userPresenceConfirmed;
              return const core.DeviceRevokeResult(
                did: _did,
                targetDeviceId: 'device-member',
                status: core.DeviceRevokeStatus.revoked,
              );
            },
      );

      final result = await adapter.revokeDevice(
        selector: _did,
        targetDeviceId: ' device-member ',
        userPresenceConfirmed: true,
      );

      expect(capturedSelector, isA<core.DidIdentitySelector>());
      expect((capturedSelector! as core.DidIdentitySelector).did, _did);
      expect(capturedTarget, 'device-member');
      expect(capturedPresence, isTrue);
      expect(result.did, _did);
      expect(result.targetDeviceId, 'device-member');
      expect(result.status, DeviceRevokeStatus.revoked);
      expect(result.toString(), isNot(contains('auth_generation')));
      expect(result.toString(), isNot(contains('document_hash')));
    },
  );

  test(
    'authorized Join binding matches the exact local DID and device',
    () async {
      core.IdentitySelector? capturedSelector;
      final sdk = _IdentityDeviceSummaryCore((selector) async {
        capturedSelector = selector;
        return _identityDeviceSummary(protocolDeviceId: 'device-new');
      });
      final adapter = _adapterWithCore(sdk);

      expect(
        await adapter.localIdentityMatchesDevice(
          did: _did,
          protocolDeviceId: 'device-new',
        ),
        isTrue,
      );
      expect(capturedSelector, isA<core.DidIdentitySelector>());
      expect((capturedSelector! as core.DidIdentitySelector).did, _did);
    },
  );

  test('same local DID with another device does not match', () async {
    final adapter = _adapterWithCore(
      _IdentityDeviceSummaryCore(
        (_) async => _identityDeviceSummary(protocolDeviceId: 'device-other'),
      ),
    );

    expect(
      await adapter.localIdentityMatchesDevice(
        did: _did,
        protocolDeviceId: 'device-new',
      ),
      isFalse,
    );
  });

  test(
    'missing local identity makes an authorized Join non-resumable',
    () async {
      final adapter = _adapterWithCore(
        _IdentityDeviceSummaryCore(
          (_) async => throw const core.AwikiImCoreException(
            code: 'identity_not_found',
            message: 'not found',
          ),
        ),
      );

      expect(
        await adapter.localIdentityMatchesDevice(
          did: _did,
          protocolDeviceId: 'device-new',
        ),
        isFalse,
      );
    },
  );

  test('unexpected Core failures are not mistaken for a missing identity', () {
    const failure = core.AwikiImCoreException(
      code: 'local_state_unavailable',
      message: 'vault unavailable',
    );
    final adapter = _adapterWithCore(
      _IdentityDeviceSummaryCore((_) async => throw failure),
    );

    expect(
      adapter.localIdentityMatchesDevice(
        did: _did,
        protocolDeviceId: 'device-new',
      ),
      throwsA(same(failure)),
    );
  });
}

const _did = 'did:wba:awiki.info:user:e1_test';

Future<core.AwikiImCore> _unusedCore() async => _PublicMethodCore();

class _PublicMethodCore implements core.AwikiImCore {
  Object? resolutionError;
  String? resolvedHandle;
  String resolvedDid = _did;
  core.IdentityMethodCapabilities capabilities = coreWbaMethodCapabilities;

  @override
  Future<String> resolveHandleForDeviceJoin(String handle) async {
    resolvedHandle = handle;
    if (resolutionError != null) throw resolutionError!;
    return resolvedDid;
  }

  @override
  Future<core.IdentityMethodCapabilities> identityMethodCapabilities(
    String did,
  ) async {
    if (did != resolvedDid) {
      throw const core.AwikiImCoreException(
        code: 'invalid_input',
        message: 'Unsupported DID',
      );
    }
    return capabilities;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AwikiImCoreDeviceManagementAdapter _adapterWithCore(core.AwikiImCore sdk) {
  return AwikiImCoreDeviceManagementAdapter.withCoreInstance(
    coreInstance: () async => sdk,
    userServiceUrl: 'https://awiki.info',
    targetHandleDomain: 'awiki.info',
  );
}

core.IdentityDeviceSummary _identityDeviceSummary({
  required String protocolDeviceId,
  core.IdentityDeviceRole role = core.IdentityDeviceRole.member,
  core.IdentityDeviceReadiness readiness =
      core.IdentityDeviceReadiness.memberReady,
}) {
  return core.IdentityDeviceSummary(
    identity: const core.IdentitySummary(
      id: 'identity-alice',
      did: _did,
      isDefault: true,
      readyForAuth: true,
      readyForMessaging: true,
    ),
    mode: core.IdentityDeviceMode.vNext,
    protocolDeviceId: protocolDeviceId,
    role: role,
    readiness: readiness,
  );
}

class _IdentityDeviceSummaryCore implements core.AwikiImCore {
  _IdentityDeviceSummaryCore(this.loader);

  final Future<core.IdentityDeviceSummary> Function(core.IdentitySelector)
  loader;

  @override
  Future<core.IdentityDeviceSummary> identityDeviceSummary(
    core.IdentitySelector selector,
  ) => loader(selector);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

core.DeviceJoinProgress _coreProgress() {
  return const core.DeviceJoinProgress(
    session: core.DeviceJoinSessionSummary(
      joinSessionId: 'join-1',
      did: _did,
      protocolDeviceId: 'device-new',
      side: core.DeviceJoinSide.newDevice,
      phase: core.DeviceJoinPhase.responsePrepared,
      expiresAt: '2026-07-19T00:10:00Z',
    ),
    remoteState: core.DeviceJoinRemoteState.challengeSent,
    sas: '482917',
  );
}

Future<String> _resolveAwikiJoinTarget({
  required String handle,
  required String domain,
}) async {
  expect(handle, 'alice');
  expect(domain, 'awiki.info');
  return _did;
}

class _ManagementApprovalCore implements core.AwikiImCore {
  int managementCalls = 0;
  bool? confirmed;
  @override
  Future<core.DeviceJoinProgress> confirmDeviceJoinWithManagement({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async {
    managementCalls++;
    confirmed = userPresenceConfirmed;
    return _coreProgress();
  }

  @override
  Future<core.DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async =>
      throw StateError('App must explicitly select management authorization');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WebApprovalCore extends _PublicMethodCore {
  _WebApprovalCore() {
    resolvedDid = 'did:web:awiki.info:awiki:web:alice';
    capabilities = coreWebMethodCapabilities;
  }
  int ordinaryCalls = 0;
  @override
  Future<core.DeviceJoinApprovalPrompt> prepareDeviceJoinApproval({
    required core.IdentitySelector selector,
    required String joinSessionId,
    required bool sasConfirmed,
  }) async => const core.DeviceJoinApprovalPrompt(
    approvalHandle: 'web-approval',
    joinSessionId: 'web-join',
    sas: '123456',
    expiresAt: '2030-01-01T00:00:00Z',
  );
  @override
  Future<core.DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async {
    ordinaryCalls++;
    return _coreProgress();
  }

  @override
  Future<core.DeviceJoinProgress> confirmDeviceJoinWithManagement({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async => throw StateError('Web has no Root management');
}
