import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/handle_recovery_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/handle_recovery_completion.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'begin OTP and exchange bind exact purpose target Handle/domain',
    () async {
      final port = _FakeRecoveryPort();
      final service = _service(port);

      await service.sendBeginSmsOtp(
        handle: ' Alice ',
        handleDomain: 'AWIKI.INFO',
        phone: '+8613800138000',
      );
      final progress = await service.beginWithSms(
        handle: ' Alice ',
        handleDomain: 'AWIKI.INFO',
        phone: '+8613800138000',
        otp: '123456',
      );

      expect(progress.phase, HandleRecoveryPhase.cooling);
      expect(port.lastBeginOtpHandle, 'alice');
      expect(port.lastBeginOtpDomain, 'awiki.info');
      expect(port.lastBeginHandle, 'alice');
      expect(port.lastBeginDomain, 'awiki.info');
      expect(port.lastBeginOtp, '123456');
    },
  );

  test('begin rejects a projection for another Handle scope', () async {
    final port = _FakeRecoveryPort()..projectedHandleDomain = 'other.example';

    await expectLater(
      _service(port).beginWithSms(
        handle: 'alice',
        handleDomain: 'awiki.info',
        phone: '+8613800138000',
        otp: '123456',
      ),
      _throwsCode('invalid_begin_projection'),
    );
  });

  test('final OTP and finalize bind exact Handle/domain/session', () async {
    final port = _FakeRecoveryPort();
    final service = _service(port);
    final ready = port.progress(phase: HandleRecoveryPhase.ready);

    await service.sendFinalizeSmsOtp(current: ready, phone: '+8613800138000');
    final completion = await service.finalizeWithSms(
      current: ready,
      phone: '+8613800138000',
      otp: '654321',
      intentConfirmed: true,
      presenceReason: 'Confirm recovery',
    );

    expect(port.lastFinalizeOtpHandle, 'alice');
    expect(port.lastFinalizeOtpDomain, 'awiki.info');
    expect(port.lastFinalizeOtpSessionId, 'recovery-1');
    expect(port.lastFinalizeHandle, 'alice');
    expect(port.lastFinalizeDomain, 'awiki.info');
    expect(port.lastFinalizeSessionId, 'recovery-1');
    expect(completion.progress.localActivationPending, isTrue);
  });

  test('cancel requires explicit intent before user presence', () async {
    final port = _FakeRecoveryPort();
    final presence = _FakeUserPresence();
    final admin = port.progress(
      side: HandleRecoverySide.oldAdmin,
      canCancel: true,
    );

    await expectLater(
      _service(port, presence).cancel(
        current: admin,
        intentConfirmed: false,
        presenceReason: 'Confirm cancellation',
      ),
      _throwsCode('recovery_intent_not_confirmed'),
    );
    expect(presence.calls, 0);
    expect(port.cancelCalls, 0);
  });

  test('cancel fails closed when user presence is rejected', () async {
    final port = _FakeRecoveryPort();
    final presence = _FakeUserPresence(confirmed: false);
    final admin = port.progress(
      side: HandleRecoverySide.oldAdmin,
      canCancel: true,
    );

    await expectLater(
      _service(port, presence).cancel(
        current: admin,
        intentConfirmed: true,
        presenceReason: 'Confirm cancellation',
      ),
      _throwsCode('user_presence_denied'),
    );
    expect(presence.calls, 1);
    expect(port.cancelCalls, 0);
  });

  test('old ready admin cancellation binds old DID and session', () async {
    final port = _FakeRecoveryPort();
    final admin = port.progress(
      side: HandleRecoverySide.oldAdmin,
      canCancel: true,
    );
    final cancelled = await _service(port).cancel(
      current: admin,
      intentConfirmed: true,
      presenceReason: 'Confirm cancellation',
    );

    expect(cancelled.phase, HandleRecoveryPhase.cancelled);
    expect(port.lastCancelSelector, admin.oldDid);
    expect(port.lastCancelRecoverySessionId, admin.recoverySessionId);
  });

  test('finalize requires explicit intent before user presence', () async {
    final port = _FakeRecoveryPort();
    final presence = _FakeUserPresence();

    await expectLater(
      _service(port, presence).finalizeWithSms(
        current: port.progress(phase: HandleRecoveryPhase.ready),
        phone: '+8613800138000',
        otp: '654321',
        intentConfirmed: false,
        presenceReason: 'Confirm recovery',
      ),
      _throwsCode('recovery_intent_not_confirmed'),
    );
    expect(presence.calls, 0);
    expect(port.finalizeCalls, 0);
  });

  test('finalize fails closed when user presence is rejected', () async {
    final port = _FakeRecoveryPort();
    final presence = _FakeUserPresence(confirmed: false);

    await expectLater(
      _service(port, presence).finalizeWithSms(
        current: port.progress(phase: HandleRecoveryPhase.ready),
        phone: '+8613800138000',
        otp: '654321',
        intentConfirmed: true,
        presenceReason: 'Confirm recovery',
      ),
      _throwsCode('user_presence_denied'),
    );
    expect(presence.calls, 1);
    expect(port.finalizeCalls, 0);
  });

  test(
    'finalize rejects a consumed projection that reuses the old DID',
    () async {
      final port = _FakeRecoveryPort()..reuseOldDidOnFinalize = true;

      await expectLater(
        _service(port).finalizeWithSms(
          current: port.progress(phase: HandleRecoveryPhase.ready),
          phone: '+8613800138000',
          otp: '654321',
          intentConfirmed: true,
          presenceReason: 'Confirm recovery',
        ),
        _throwsCode('invalid_finalize_projection'),
      );
    },
  );

  test('finalize rejects an unauthenticated replacement session', () async {
    final port = _FakeRecoveryPort()..authenticatedOnFinalize = false;

    await expectLater(
      _service(port).finalizeWithSms(
        current: port.progress(phase: HandleRecoveryPhase.ready),
        phone: '+8613800138000',
        otp: '654321',
        intentConfirmed: true,
        presenceReason: 'Confirm recovery',
      ),
      _throwsCode('invalid_finalize_projection'),
    );
  });

  test('finalize rejects a completion bound to another session', () async {
    final port = _FakeRecoveryPort()..finalizeSessionMismatch = true;

    await expectLater(
      _service(port).finalizeWithSms(
        current: port.progress(phase: HandleRecoveryPhase.ready),
        phone: '+8613800138000',
        otp: '654321',
        intentConfirmed: true,
        presenceReason: 'Confirm recovery',
      ),
      _throwsCode('recovery_projection_mismatch'),
    );
  });

  test(
    'restore fails closed instead of choosing among active requesters',
    () async {
      final port = _FakeRecoveryPort()
        ..localSessions = <HandleRecoveryProgress>[
          portProgress('recovery-1'),
          portProgress('recovery-2'),
        ];

      await expectLater(
        _service(port).restoreLocalRecoveries(),
        _throwsCode('multiple_active_recoveries'),
      );
    },
  );

  test('status polling rejects a ready to cooling regression', () async {
    final port = _FakeRecoveryPort()..pollPhase = HandleRecoveryPhase.cooling;

    await expectLater(
      _service(port).poll(port.progress(phase: HandleRecoveryPhase.ready)),
      _throwsCode('invalid_recovery_transition'),
    );
  });

  test('restore rejects pending activation that reuses the old DID', () async {
    final port = _FakeRecoveryPort();
    port.localSessions = <HandleRecoveryProgress>[
      port.progress(
        phase: HandleRecoveryPhase.consumed,
        newDid: 'did:wba:awiki.info:user:alice:e1_old',
        localActivationPending: true,
      ),
    ];

    await expectLater(
      _service(port).restoreLocalRecoveries(),
      _throwsCode('invalid_activation_projection'),
    );
  });

  test(
    'resume rejects a replacement session that reuses the old DID',
    () async {
      final port = _FakeRecoveryPort()..reuseOldDidOnResume = true;
      final pending = port.progress(
        phase: HandleRecoveryPhase.consumed,
        newDid: 'did:wba:awiki.info:user:alice:e1_new',
        localActivationPending: true,
      );

      await expectLater(
        _service(port).resumeActivation(pending),
        _throwsCode('invalid_activation_projection'),
      );
    },
  );

  test('canonical Handle uses the protocol dot form', () {
    expect(portProgress('recovery-1').canonicalHandle, 'alice.awiki.info');
  });
}

HandleRecoveryService _service(
  _FakeRecoveryPort port, [
  _FakeUserPresence? presence,
]) {
  return HandleRecoveryService(
    recovery: port,
    userPresence: presence ?? _FakeUserPresence(),
    sessions: _FakeSessions(),
  );
}

Matcher _throwsCode(String code) => throwsA(
  isA<HandleRecoveryException>().having((error) => error.code, 'code', code),
);

HandleRecoveryProgress portProgress(String recoverySessionId) {
  return HandleRecoveryProgress(
    recoverySessionId: recoverySessionId,
    handle: 'alice',
    handleDomain: 'awiki.info',
    oldDid: 'did:wba:awiki.info:user:alice:e1_old',
    side: HandleRecoverySide.requester,
    phase: HandleRecoveryPhase.cooling,
    coolingUntil: DateTime.utc(2026, 7, 20),
    expiresAt: DateTime.utc(2026, 7, 21),
  );
}

class _FakeUserPresence implements UserPresencePort {
  _FakeUserPresence({this.confirmed = true});

  final bool confirmed;
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    return confirmed;
  }
}

class _FakeRecoveryPort implements HandleRecoveryPort {
  bool reuseOldDidOnFinalize = false;
  bool authenticatedOnFinalize = true;
  bool finalizeSessionMismatch = false;
  bool reuseOldDidOnResume = false;
  HandleRecoveryPhase pollPhase = HandleRecoveryPhase.ready;
  String projectedHandleDomain = 'awiki.info';
  List<HandleRecoveryProgress> localSessions = <HandleRecoveryProgress>[];
  String? lastBeginOtpHandle;
  String? lastBeginOtpDomain;
  String? lastBeginHandle;
  String? lastBeginDomain;
  String? lastBeginOtp;
  String? lastFinalizeOtpHandle;
  String? lastFinalizeOtpDomain;
  String? lastFinalizeOtpSessionId;
  String? lastFinalizeHandle;
  String? lastFinalizeDomain;
  String? lastFinalizeSessionId;
  String? lastCancelSelector;
  String? lastCancelRecoverySessionId;
  int cancelCalls = 0;
  int finalizeCalls = 0;

  HandleRecoveryProgress progress({
    String recoverySessionId = 'recovery-1',
    HandleRecoverySide side = HandleRecoverySide.requester,
    HandleRecoveryPhase phase = HandleRecoveryPhase.cooling,
    bool canCancel = false,
    String? newDid,
    bool localActivationPending = false,
  }) {
    return HandleRecoveryProgress(
      recoverySessionId: recoverySessionId,
      handle: 'alice',
      handleDomain: projectedHandleDomain,
      oldDid: 'did:wba:awiki.info:user:alice:e1_old',
      side: side,
      phase: phase,
      coolingUntil: DateTime.utc(2026, 7, 20),
      expiresAt: DateTime.utc(2026, 7, 21),
      canCancelFromThisDevice: canCancel,
      newDid: newDid,
      localActivationPending: localActivationPending,
    );
  }

  @override
  Future<void> sendRecoveryBeginSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  }) async {
    lastBeginOtpHandle = handle;
    lastBeginOtpDomain = handleDomain;
  }

  @override
  Future<HandleRecoveryProgress> beginHandleRecoveryWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    lastBeginHandle = handle;
    lastBeginDomain = handleDomain;
    lastBeginOtp = otp;
    return progress();
  }

  @override
  Future<HandleRecoveryProgress> cancelHandleRecovery({
    required String selector,
    required String recoverySessionId,
  }) async {
    cancelCalls += 1;
    lastCancelSelector = selector;
    lastCancelRecoverySessionId = recoverySessionId;
    return progress(
      side: HandleRecoverySide.oldAdmin,
      phase: HandleRecoveryPhase.cancelled,
    );
  }

  @override
  Future<void> sendRecoveryFinalizeSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
    required String recoverySessionId,
  }) async {
    lastFinalizeOtpHandle = handle;
    lastFinalizeOtpDomain = handleDomain;
    lastFinalizeOtpSessionId = recoverySessionId;
  }

  @override
  Future<HandleRecoveryCompletion> finalizeHandleRecoveryWithSms({
    required String recoverySessionId,
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    finalizeCalls += 1;
    lastFinalizeSessionId = recoverySessionId;
    lastFinalizeHandle = handle;
    lastFinalizeDomain = handleDomain;
    final did = reuseOldDidOnFinalize
        ? 'did:wba:awiki.info:user:alice:e1_old'
        : 'did:wba:awiki.info:user:alice:e1_new';
    return HandleRecoveryCompletion(
      progress: progress(
        recoverySessionId: finalizeSessionMismatch
            ? 'recovery-other'
            : 'recovery-1',
        phase: HandleRecoveryPhase.consumed,
        newDid: did,
        localActivationPending: true,
      ),
      session: AppSession(
        did: did,
        identityId: did,
        displayName: 'alice',
        handle: 'alice.awiki.info',
        authenticated: authenticatedOnFinalize,
      ),
    );
  }

  @override
  Future<List<HandleRecoveryProgress>> localHandleRecoverySessions() async =>
      localSessions;

  @override
  Future<HandleRecoveryProgress> pollHandleRecovery(
    String recoverySessionId,
  ) async => progress(phase: pollPhase);

  @override
  Future<AppSession> resumeRecoveryActivation(String recoverySessionId) async {
    final did = reuseOldDidOnResume
        ? 'did:wba:awiki.info:user:alice:e1_old'
        : 'did:wba:awiki.info:user:alice:e1_new';
    return AppSession(
      did: did,
      identityId: did,
      displayName: 'alice',
      authenticated: true,
    );
  }

  @override
  Future<void> markRecoveryActivationComplete(String recoverySessionId) async {}
}

class _FakeSessions implements AppSessionService {
  AppSession? current;

  @override
  Future<AppSession> activateIdentity(AppSession identity) async {
    current = identity;
    return identity;
  }

  @override
  Future<AppSession?> currentSession() async => current;

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) =>
      throw UnsupportedError('unsupported');

  @override
  Future<List<AppSession>> listLocalIdentities() async => const <AppSession>[];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) =>
      throw UnsupportedError('unsupported');

  @override
  Future<void> logout() async {
    current = null;
  }

  @override
  Future<AppSession?> refreshSession() async => current;

  @override
  Future<AppSession?> restoreSession() async => current;
}
