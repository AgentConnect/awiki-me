import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/handle_recovery_completion.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('begin invalidates a slower restore projection', () async {
    final port = _RaceRecoveryPort();
    final container = ProviderContainer(
      overrides: <Override>[
        handleRecoveryEnabledProvider.overrideWithValue(true),
        handleRecoveryPortProvider.overrideWithValue(port),
        userPresencePortProvider.overrideWithValue(_AllowPresence()),
        appSessionServiceProvider.overrideWithValue(_NoopSessions()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(handleRecoveryProvider.notifier);

    final restore = controller.restore();
    await port.restoreStarted.future;
    await controller.begin(
      handle: 'alice',
      handleDomain: 'awiki.info',
      phone: '+8613800138000',
      otp: '123456',
    );
    port.restoreResult.complete(<HandleRecoveryProgress>[]);
    await restore;

    final state = container.read(handleRecoveryProvider);
    expect(state.activeRequester?.recoverySessionId, 'recovery-new');
    expect(state.isLoading, isFalse);
  });
}

class _AllowPresence implements UserPresencePort {
  @override
  Future<bool> confirm({required String reason}) async => true;
}

class _NoopSessions implements AppSessionService {
  @override
  Future<AppSession> activateIdentity(AppSession identity) async => identity;

  @override
  Future<AppSession?> currentSession() async => null;

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) =>
      throw UnsupportedError('unsupported');

  @override
  Future<List<AppSession>> listLocalIdentities() async => const <AppSession>[];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) =>
      throw UnsupportedError('unsupported');

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession?> refreshSession() async => null;

  @override
  Future<AppSession?> restoreSession() async => null;
}

class _RaceRecoveryPort implements HandleRecoveryPort {
  final Completer<void> restoreStarted = Completer<void>();
  final Completer<List<HandleRecoveryProgress>> restoreResult =
      Completer<List<HandleRecoveryProgress>>();

  HandleRecoveryProgress get progress => HandleRecoveryProgress(
    recoverySessionId: 'recovery-new',
    handle: 'alice',
    handleDomain: 'awiki.info',
    oldDid: 'did:wba:awiki.info:user:alice:e1_old',
    side: HandleRecoverySide.requester,
    phase: HandleRecoveryPhase.cooling,
    coolingUntil: DateTime.utc(2026, 7, 20),
    expiresAt: DateTime.utc(2026, 7, 21),
  );

  @override
  Future<List<HandleRecoveryProgress>> localHandleRecoverySessions() {
    restoreStarted.complete();
    return restoreResult.future;
  }

  @override
  Future<HandleRecoveryProgress> beginHandleRecoveryWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async => progress;

  @override
  Future<void> sendRecoveryBeginSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  }) async {}

  @override
  Future<void> sendRecoveryFinalizeSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
    required String recoverySessionId,
  }) async {}

  @override
  Future<HandleRecoveryProgress> pollHandleRecovery(
    String recoverySessionId,
  ) async => throw UnimplementedError();

  @override
  Future<HandleRecoveryCancelResult> cancelHandleRecovery({
    required String selector,
    required String recoverySessionId,
  }) async => throw UnimplementedError();

  @override
  Future<HandleRecoveryCompletion> finalizeHandleRecoveryWithSms({
    required String recoverySessionId,
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async => throw UnimplementedError();

  @override
  Future<AppSession> resumeRecoveryActivation(String recoverySessionId) async =>
      throw UnimplementedError();

  @override
  Future<void> markRecoveryActivationComplete(String recoverySessionId) async =>
      throw UnimplementedError();
}
