import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_device_management_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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

    await adapter.sendJoinSmsOtp(' +8613800138000 ');

    expect(
      request.url.toString(),
      'https://awiki.info/user-service/auth/sms-codes',
    );
    expect(jsonDecode(request.body), <String, Object?>{
      'phone': '+8613800138000',
    });
  });

  test(
    'exchanges SMS OTP and immediately passes a redacted grant to Core',
    () async {
      const token = 'join-account-token-must-not-escape';
      late Map<String, Object?> requestBody;
      late Map<String, Object?> profileRequestBody;
      var beginCalls = 0;
      final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
        coreInstance: _unusedCore,
        userServiceUrl: 'https://awiki.info',
        targetHandleDomain: 'awiki.info',
        httpClient: MockClient((request) async {
          if (request.url.path == '/user-service/did/profile/rpc') {
            profileRequestBody = (jsonDecode(request.body) as Map)
                .cast<String, Object?>();
            return http.Response(
              jsonEncode(<String, Object?>{
                'jsonrpc': '2.0',
                'id': 'req-1',
                'result': <String, Object?>{'did': _did},
              }),
              200,
            );
          }
          expect(
            request.url.path,
            '/user-service/auth/account-verification/exchange',
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
      expect(profileRequestBody['method'], 'get_public_profile');
      expect(profileRequestBody['params'], <String, Object?>{
        'handle': 'alice.awiki.info',
      });
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

  test(
    'rejects a public profile from another DID domain before OTP exchange',
    () async {
      var requestCalls = 0;
      var beginCalls = 0;
      final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
        coreInstance: _unusedCore,
        userServiceUrl: 'https://awiki.info',
        targetHandleDomain: 'awiki.info',
        httpClient: MockClient((request) async {
          requestCalls += 1;
          expect(request.url.path, '/user-service/did/profile/rpc');
          return http.Response(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 'req-1',
              'result': <String, Object?>{
                'did': 'did:wba:other.example:user:alice:e1_test',
              },
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
      expect(requestCalls, 1);
      expect(beginCalls, 0);
    },
  );

  test(
    'redacts public profile response failures before OTP exchange',
    () async {
      const sensitive = 'profile-response-must-not-escape';
      var beginCalls = 0;
      final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
        coreInstance: _unusedCore,
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
    },
  );

  test('uses the qualified Handle domain for the internal exchange', () async {
    late Map<String, Object?> requestBody;
    String? resolvedHandle;
    String? resolvedDomain;
    final adapter = AwikiImCoreDeviceManagementAdapter.withCoreInstance(
      coreInstance: _unusedCore,
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

  test('maps registry roles, readiness, and pending requests', () {
    final snapshot = deviceRegistryFromCore(
      const core.DeviceJoinRegistrySnapshot(
        did: _did,
        devices: <core.DeviceJoinAuthorizedDeviceSummary>[
          core.DeviceJoinAuthorizedDeviceSummary(
            protocolDeviceId: 'admin-1',
            signingKeyId: 'did:key:sign',
            e2eeKeyId: 'did:key:e2ee',
            status: core.DeviceJoinAuthorizationStatus.active,
            role: core.DeviceJoinRole.admin,
            managementReady: false,
            isCurrent: true,
          ),
        ],
        pendingJoinRequests: <core.DeviceJoinPendingSummary>[
          core.DeviceJoinPendingSummary(
            joinSessionId: 'join-2',
            protocolDeviceId: 'member-2',
            signingKeyId: 'did:key:new-sign',
            e2eeKeyId: 'did:key:new-e2ee',
            requestedRole: core.DeviceJoinRole.member,
            issuedAt: '2026-07-19T00:00:00Z',
            expiresAt: '2026-07-19T00:10:00Z',
          ),
        ],
      ),
    );

    expect(snapshot.did, _did);
    expect(snapshot.currentDevice?.role, DeviceRole.admin);
    expect(snapshot.currentDevice?.managementReady, isFalse);
    expect(snapshot.pendingJoins.single.requestedRole, DeviceRole.member);
    expect(snapshot.pendingJoins.single.expiresAt.isUtc, isTrue);
  });

  test('local session summaries are explicitly marked not observed', () {
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
    expect(progress.remoteState, DeviceJoinRemoteState.notObserved);
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
}

const _did = 'did:wba:awiki.info:user:e1_test';

Future<core.AwikiImCore> _unusedCore() {
  throw StateError('Core access was not expected by this test.');
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
