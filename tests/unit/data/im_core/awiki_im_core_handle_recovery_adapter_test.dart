import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_handle_recovery_adapter.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'Recovery SMS requests bind exact purpose, target, and finalize session',
    () async {
      final requests = <http.Request>[];
      final adapter = _adapter(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"message":"Code sent."}', 200);
        }),
      );

      await adapter.sendRecoveryBeginSmsOtp(
        phone: ' +8613800138000 ',
        handle: 'alice',
        handleDomain: 'awiki.info',
      );
      await adapter.sendRecoveryFinalizeSmsOtp(
        phone: '+8613800138000',
        handle: 'alice',
        handleDomain: 'awiki.info',
        recoverySessionId: 'recovery-1',
      );

      expect(requests, hasLength(2));
      expect(
        requests.map((request) => request.url.toString()),
        everyElement('https://awiki.info/user-service/auth/sms-codes'),
      );
      expect(jsonDecode(requests[0].body), <String, Object?>{
        'phone': '+8613800138000',
        'purpose': AwikiImCoreHandleRecoveryAdapter.beginPurpose,
        'target_handle': 'alice',
        'target_handle_domain': 'awiki.info',
      });
      expect(jsonDecode(requests[1].body), <String, Object?>{
        'phone': '+8613800138000',
        'purpose': AwikiImCoreHandleRecoveryAdapter.finalizePurpose,
        'target_handle': 'alice',
        'target_handle_domain': 'awiki.info',
        'recovery_session_id': 'recovery-1',
      });
    },
  );

  test(
    'begin exchanges only the begin credential and consumes it in Core',
    () async {
      const token = 'begin-token-must-not-escape';
      late Map<String, Object?> requestBody;
      var beginCalls = 0;
      final adapter = _adapter(
        httpClient: MockClient((request) async {
          requestBody = (jsonDecode(request.body) as Map)
              .cast<String, Object?>();
          return http.Response(
            jsonEncode(<String, Object?>{
              'account_verification_token': token,
              'purpose': AwikiImCoreHandleRecoveryAdapter.beginPurpose,
              'expires_at': '2026-07-21T00:05:00Z',
            }),
            200,
          );
        }),
        begin: ({required handle, required verificationGrant}) async {
          beginCalls += 1;
          expect(handle, 'alice.awiki.info');
          expect(verificationGrant.toString(), contains('<redacted>'));
          expect(verificationGrant.toString(), isNot(contains(token)));
          return _coreProgress();
        },
        idempotencyScopeFactory: (_, _) => 'recovery-begin-scope',
      );

      final result = await adapter.beginHandleRecoveryWithSms(
        handle: 'alice',
        handleDomain: 'awiki.info',
        phone: '+8613800138000',
        otp: '123456',
      );

      expect(beginCalls, 1);
      expect(requestBody, <String, Object?>{
        'provider': 'sms',
        'purpose': AwikiImCoreHandleRecoveryAdapter.beginPurpose,
        'phone': '+8613800138000',
        'code': '123456',
        'target_handle': 'alice',
        'target_handle_domain': 'awiki.info',
        'idempotency_scope': 'recovery-begin-scope',
      });
      expect(result.recoverySessionId, 'recovery-1');
      expect(result.handle, 'alice');
      expect(result.handleDomain, 'awiki.info');
      expect(result.phase, HandleRecoveryPhase.cooling);
    },
  );

  test(
    'finalize uses the distinct session-bound reconfirmation credential',
    () async {
      const token = 'finalize-token-must-not-escape';
      late Map<String, Object?> requestBody;
      var finalizeCalls = 0;
      final adapter = _adapter(
        httpClient: MockClient((request) async {
          requestBody = (jsonDecode(request.body) as Map)
              .cast<String, Object?>();
          return http.Response(
            jsonEncode(<String, Object?>{
              'reconfirmation_token': token,
              'purpose': AwikiImCoreHandleRecoveryAdapter.finalizePurpose,
              'expires_at': '2026-07-21T00:05:00Z',
            }),
            200,
          );
        }),
        finalize:
            ({
              required recoverySessionId,
              required verificationGrant,
              required userPresenceConfirmed,
            }) async {
              finalizeCalls += 1;
              expect(recoverySessionId, 'recovery-1');
              expect(userPresenceConfirmed, isTrue);
              expect(verificationGrant.toString(), contains('<redacted>'));
              expect(verificationGrant.toString(), isNot(contains(token)));
              return core.HandleRecoveryFinalizeResult(
                progress: _coreProgress(
                  phase: core.HandleRecoveryPhase.consumed,
                  newDid: _newDid,
                  localActivationPending: true,
                ),
                identity: _identity(),
              );
            },
        idempotencyScopeFactory: (_, sessionId) {
          expect(sessionId, 'recovery-1');
          return 'recovery-finalize-scope';
        },
      );

      final result = await adapter.finalizeHandleRecoveryWithSms(
        recoverySessionId: 'recovery-1',
        handle: 'alice',
        handleDomain: 'awiki.info',
        phone: '+8613800138000',
        otp: '654321',
      );

      expect(finalizeCalls, 1);
      expect(requestBody, <String, Object?>{
        'provider': 'sms',
        'purpose': AwikiImCoreHandleRecoveryAdapter.finalizePurpose,
        'phone': '+8613800138000',
        'code': '654321',
        'target_handle': 'alice',
        'target_handle_domain': 'awiki.info',
        'idempotency_scope': 'recovery-finalize-scope',
        'recovery_session_id': 'recovery-1',
      });
      expect(result.progress.phase, HandleRecoveryPhase.consumed);
      expect(result.progress.localActivationPending, isTrue);
      expect(result.session.did, _newDid);
      expect(result.session.authenticated, isTrue);
      expect(result.session.jwtToken, isNull);
    },
  );

  test(
    'wrong-purpose or cross-field exchange responses fail before Core',
    () async {
      var beginCalls = 0;
      final adapter = _adapter(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'account_verification_token': 'begin-secret',
              'reconfirmation_token': 'wrong-field-secret',
              'purpose': AwikiImCoreHandleRecoveryAdapter.beginPurpose,
            }),
            200,
          ),
        ),
        begin: ({required handle, required verificationGrant}) async {
          beginCalls += 1;
          return _coreProgress();
        },
      );

      await expectLater(
        adapter.beginHandleRecoveryWithSms(
          handle: 'alice',
          handleDomain: 'awiki.info',
          phone: '+8613800138000',
          otp: '123456',
        ),
        throwsA(
          isA<HandleRecoveryTransportException>().having(
            (error) => error.code,
            'code',
            'account_verification_invalid_response',
          ),
        ),
      );
      expect(beginCalls, 0);
    },
  );

  test('HTTP errors never include an echoed OTP or token body', () async {
    const secret = 'server-echoed-secret';
    final adapter = _adapter(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"detail":"$secret","account_verification_token":"$secret"}',
          503,
        ),
      ),
    );

    Object? error;
    try {
      await adapter.beginHandleRecoveryWithSms(
        handle: 'alice',
        handleDomain: 'awiki.info',
        phone: '+8613800138000',
        otp: secret,
      );
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<HandleRecoveryTransportException>());
    expect(error.toString(), contains('account_verification_http_503'));
    expect(error.toString(), isNot(contains(secret)));
  });

  test(
    'local status, cancel, resume, and activation ACK stay secret-free',
    () async {
      var cancelPresence = false;
      var markedSession = '';
      final adapter = _adapter(
        localSessions: () async => <core.HandleRecoveryProgress>[
          _coreProgress(side: core.HandleRecoverySide.oldAdmin),
        ],
        poll: (_) async => _coreProgress(phase: core.HandleRecoveryPhase.ready),
        cancel:
            ({
              required oldIdentity,
              required recoverySessionId,
              required userPresenceConfirmed,
            }) async {
              cancelPresence = userPresenceConfirmed;
              expect(oldIdentity, isA<core.DidIdentitySelector>());
              return core.HandleRecoveryCancelResult(
                recoverySessionId: recoverySessionId,
                phase: core.HandleRecoveryPhase.cancelled,
              );
            },
        resumeActivation: (_) async => _identity(),
        markActivationComplete: (sessionId) async {
          markedSession = sessionId;
        },
      );

      final local = await adapter.localHandleRecoverySessions();
      final polled = await adapter.pollHandleRecovery('recovery-1');
      final cancelled = await adapter.cancelHandleRecovery(
        selector: _oldDid,
        recoverySessionId: 'recovery-1',
      );
      final identity = await adapter.resumeRecoveryActivation('recovery-1');
      await adapter.markRecoveryActivationComplete('recovery-1');

      expect(local.single.side, HandleRecoverySide.oldAdmin);
      expect(polled.phase, HandleRecoveryPhase.ready);
      expect(cancelled.phase, HandleRecoveryPhase.cancelled);
      expect(cancelPresence, isTrue);
      expect(identity.did, _newDid);
      expect(identity.authenticated, isTrue);
      expect(identity.jwtToken, isNull);
      expect(markedSession, 'recovery-1');
    },
  );

  test(
    'old-admin notice list get and local dismiss stay secret-free',
    () async {
      var listCalls = 0;
      var getCalls = 0;
      var dismissCalls = 0;
      final adapter = _adapter(
        listOldAdminNotices: ({required oldIdentity}) async {
          listCalls += 1;
          expect(oldIdentity, isA<core.DidIdentitySelector>());
          return <core.OldAdminRecoveryNotice>[_coreOldAdminNotice()];
        },
        getOldAdminNotice: ({required oldIdentity, required eventId}) async {
          getCalls += 1;
          expect(oldIdentity, isA<core.DidIdentitySelector>());
          expect(eventId, 'recovery-event-1');
          return _coreOldAdminNotice();
        },
        dismissOldAdminNotice:
            ({required oldIdentity, required eventId}) async {
              dismissCalls += 1;
              expect(oldIdentity, isA<core.DidIdentitySelector>());
              return core.OldAdminRecoveryNoticeDismissResult(
                eventId: eventId,
                dismissed: true,
              );
            },
      );

      final listed = await adapter.listOldAdminRecoveryNotices(_oldDid);
      final fetched = await adapter.getOldAdminRecoveryNotice(
        oldIdentity: _oldDid,
        eventId: 'recovery-event-1',
      );
      final dismissed = await adapter.dismissOldAdminRecoveryNotice(
        oldIdentity: _oldDid,
        eventId: 'recovery-event-1',
      );

      expect(listCalls, 1);
      expect(getCalls, 1);
      expect(dismissCalls, 1);
      expect(listed.single.eventId, 'recovery-event-1');
      expect(listed.single.canonicalHandle, 'alice.awiki.info');
      expect(listed.single.oldDid, _oldDid);
      expect(listed.single.requestedAt, DateTime.utc(2026, 7, 20));
      expect(fetched?.recoverySessionId, 'recovery-1');
      expect(dismissed.eventId, 'recovery-event-1');
      expect(dismissed.dismissed, isTrue);
      final rendered = listed.single.toString().toLowerCase();
      for (final forbidden in <String>[
        'sync_checkpoint',
        'token',
        'proof',
        'email',
        'secret',
      ]) {
        expect(rendered, isNot(contains(forbidden)));
      }
    },
  );

  test('cross-domain Recovery fails before HTTP or Core work', () async {
    var httpCalls = 0;
    var beginCalls = 0;
    final adapter = _adapter(
      httpClient: MockClient((_) async {
        httpCalls += 1;
        return http.Response('{}', 200);
      }),
      begin: ({required handle, required verificationGrant}) async {
        beginCalls += 1;
        return _coreProgress();
      },
    );

    await expectLater(
      adapter.beginHandleRecoveryWithSms(
        handle: 'alice',
        handleDomain: 'other.example',
        phone: '+8613800138000',
        otp: '123456',
      ),
      throwsA(
        isA<HandleRecoveryTransportException>().having(
          (error) => error.code,
          'code',
          'recovery_domain_mismatch',
        ),
      ),
    );
    expect(httpCalls, 0);
    expect(beginCalls, 0);
  });
}

AwikiImCoreHandleRecoveryAdapter _adapter({
  http.Client? httpClient,
  AwikiImCoreLocalHandleRecoverySessions? localSessions,
  AwikiImCoreListOldAdminRecoveryNotices? listOldAdminNotices,
  AwikiImCoreGetOldAdminRecoveryNotice? getOldAdminNotice,
  AwikiImCoreDismissOldAdminRecoveryNotice? dismissOldAdminNotice,
  AwikiImCoreBeginHandleRecovery? begin,
  AwikiImCorePollHandleRecovery? poll,
  AwikiImCoreCancelHandleRecovery? cancel,
  AwikiImCoreFinalizeHandleRecovery? finalize,
  AwikiImCoreResumeHandleRecoveryActivation? resumeActivation,
  AwikiImCoreMarkHandleRecoveryActivationComplete? markActivationComplete,
  RecoveryIdempotencyScopeFactory? idempotencyScopeFactory,
}) {
  return AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
    coreInstance: _unusedCore,
    userServiceUrl: 'https://awiki.info',
    targetHandleDomain: 'awiki.info',
    httpClient: httpClient,
    localSessions: localSessions,
    listOldAdminNotices: listOldAdminNotices,
    getOldAdminNotice: getOldAdminNotice,
    dismissOldAdminNotice: dismissOldAdminNotice,
    begin: begin,
    poll: poll,
    cancel: cancel,
    finalize: finalize,
    resumeActivation: resumeActivation,
    markActivationComplete: markActivationComplete,
    idempotencyScopeFactory: idempotencyScopeFactory,
  );
}

Future<core.AwikiImCore> _unusedCore() async =>
    throw StateError('unexpected_core_call');

const _oldDid = 'did:wba:awiki.info:user:alice:e1_old';
const _newDid = 'did:wba:awiki.info:user:alice:e1_new';

core.HandleRecoveryProgress _coreProgress({
  core.HandleRecoverySide side = core.HandleRecoverySide.requester,
  core.HandleRecoveryPhase phase = core.HandleRecoveryPhase.cooling,
  String? newDid,
  bool localActivationPending = false,
}) {
  return core.HandleRecoveryProgress(
    recoverySessionId: 'recovery-1',
    handle: 'alice.awiki.info',
    oldDid: _oldDid,
    side: side,
    phase: phase,
    coolingUntil: '2026-07-21T00:00:00Z',
    expiresAt: '2026-07-22T00:00:00Z',
    canCancelFromThisDevice: side == core.HandleRecoverySide.oldAdmin,
    newDid: newDid,
    localActivationPending: localActivationPending,
  );
}

core.OldAdminRecoveryNotice _coreOldAdminNotice() =>
    const core.OldAdminRecoveryNotice(
      eventId: 'recovery-event-1',
      recoverySessionId: 'recovery-1',
      handle: 'alice.awiki.info',
      oldDid: _oldDid,
      requestedAt: '2026-07-20T00:00:00Z',
      cancellableUntil: '2026-07-21T00:00:00Z',
    );

core.IdentitySummary _identity() => const core.IdentitySummary(
  id: 'identity-new',
  did: _newDid,
  handle: 'alice.awiki.info',
  displayName: 'Alice',
  deviceId: 'device-new',
  isDefault: true,
  readyForAuth: true,
  readyForMessaging: true,
);
