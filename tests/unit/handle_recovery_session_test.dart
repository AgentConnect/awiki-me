import 'dart:async';

import 'package:awiki_me/src/application/handle_recovery_service.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/application/sms_otp_cooldown_service.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_session.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'failed status before presence leaves the old session active and sends no commit',
    () async {
      final run = await _RecoveryRun.open();
      run.core.onStatus = () async => throw StateError('status unavailable');
      await run.controller.activate(presenceReason: 'test');

      expect(run.events, isEmpty);
      expect(run.session.currentOwner, 'old-owner');
      expect(run.core.activateCalls, 0);
      expect(run.state.error, HandleRecoveryUiError.localStateUnavailable);
      expect(run.controller.isBusy, isFalse);
    },
  );

  test(
    'cancelled presence leaves the old session active without a commit',
    () async {
      final run = await _RecoveryRun.open();
      run.presence.confirmed = false;
      await run.controller.activate(presenceReason: 'test');

      expect(run.session.currentOwner, 'old-owner');
      expect(run.events, ['presence']);
      expect(run.state.error, HandleRecoveryUiError.userPresenceRequired);
      expect(run.controller.isBusy, isFalse);
    },
  );

  test(
    'pre-commit failure restores the old session only after status confirms it',
    () async {
      final run = await _RecoveryRun.open();
      run.core.onActivate = () async => throw StateError('commit not sent');
      run.core.onStatus = () async {
        if (run.core.activateCalls != 0) run.events.add('confirmed-pre-commit');
        return run.core.progress;
      };
      await run.controller.activate(presenceReason: 'test');

      expect(run.events, [
        'presence',
        'pause',
        'activate',
        'confirmed-pre-commit',
        'restore',
      ]);
      expect(run.session.currentOwner, 'old-owner');
      expect(run.state.progress?.operationId, 'operation-1');
      expect(run.state.progress?.commitAttempted, isFalse);
      expect(run.controller.isBusy, isFalse);
    },
  );

  test(
    'failed status after a commit attempt never restores the stale old session',
    () async {
      final run = await _RecoveryRun.open();
      run.core.onActivate = () async => throw StateError('response lost');
      run.core.onStatus = () async {
        if (run.core.activateCalls != 0) throw StateError('status unavailable');
        return run.core.progress;
      };
      await run.controller.activate(presenceReason: 'test');

      expect(run.session.currentOwner, isNull);
      expect(run.events, ['presence', 'pause', 'activate']);
      expect(run.state.error, HandleRecoveryUiError.localStateUnavailable);
      expect(run.state.canActivate, isFalse);
      expect(run.state.canRequestOtp, isFalse);
      expect(run.controller.isBusy, isFalse);
    },
  );

  for (final phase in [
    HandleRecoveryLifecycleClass.remoteUnresolved,
    HandleRecoveryLifecycleClass.localTransitionPending,
  ]) {
    test(
      '$phase failure preserves the operation and never restores the old session',
      () async {
        final run = await _RecoveryRun.open();
        run.core.onActivate = () async {
          run.core.progress = _progress(phase);
          throw StateError('commit response interrupted');
        };
        run.core.onReconcile = () async =>
            throw StateError('continuation unavailable');
        await run.controller.activate(presenceReason: 'test');

        expect(run.events, ['presence', 'pause', 'activate', 'reconcile']);
        expect(run.session.currentOwner, isNull);
        expect(run.state.progress?.operationId, 'operation-1');
        expect(run.state.progress?.lifecycleClass, phase);
        expect(run.state.canRequestOtp, isFalse);
        expect(run.controller.isBusy, isFalse);
        // There is one bounded automatic attempt; an explicit retry uses the same operation.
        await run.controller.resume();
        expect(run.core.reconciledOperations, ['operation-1', 'operation-1']);
        expect(run.events.where((event) => event == 'restore'), isEmpty);
      },
    );
  }

  test(
    'pre-commit failure stays busy until the old session has been restored',
    () async {
      final run = await _RecoveryRun.open();
      final restored = Completer<void>();
      run.session.beforeRestore = () => restored.future;
      run.core.onActivate = () async => throw StateError('commit not sent');
      final task = run.controller.activate(presenceReason: 'test');
      await Future<void>.delayed(Duration.zero);

      expect(run.controller.isBusy, isTrue);
      expect(run.session.currentOwner, isNull);
      await run.controller.activate(presenceReason: 'duplicate');
      expect(run.core.activateCalls, 1);
      restored.complete();
      await task;
      expect(run.session.currentOwner, 'old-owner');
      expect(run.controller.isBusy, isFalse);
    },
  );

  test(
    'old-session restoration failure releases busy state without reporting recovery success',
    () async {
      final run = await _RecoveryRun.open();
      run.session.beforeRestore = () async =>
          throw StateError('old session unavailable');
      run.core.onActivate = () async => throw StateError('commit not sent');
      await run.controller.activate(presenceReason: 'test');

      expect(run.session.currentOwner, isNull);
      expect(run.state.error, HandleRecoveryUiError.failed);
      expect(run.state.sessionActivated, isFalse);
      expect(run.state.progress?.operationId, 'operation-1');
      expect(run.controller.isBusy, isFalse);
    },
  );

  test(
    'resuming a committed operation activates only the recovered owner',
    () async {
      final run = await _RecoveryRun.open(
        HandleRecoveryLifecycleClass.localTransitionPending,
      );
      run.core.onReconcile = () async =>
          _progress(HandleRecoveryLifecycleClass.applied);
      await run.controller.resume();

      expect(run.events, ['pause', 'reconcile', 'enter:recovered-owner']);
      expect(run.session.currentOwner, 'recovered-owner');
      expect(run.state.sessionActivated, isTrue);
      expect(run.controller.isBusy, isFalse);
    },
  );
}

class _RecoveryRun {
  final events = <String>[];
  late final _RecoveryCore core = _RecoveryCore(events);
  late final _Presence presence = _Presence(events);
  late final _Session session = _Session(events);
  late final cooldown = SmsOtpCooldownController(
    service: const NoopSmsOtpCooldownService(),
    now: DateTime.now,
  );
  final container = ProviderContainer();
  late final _controllerProvider =
      StateNotifierProvider<HandleRecoveryController, HandleRecoveryState>(
        (ref) => HandleRecoveryController(
          HandleRecoveryService(core: core, userPresence: presence),
          cooldown,
          session: session,
        ),
      );
  HandleRecoveryController get controller =>
      container.read(_controllerProvider.notifier);
  HandleRecoveryState get state => container.read(_controllerProvider);

  static Future<_RecoveryRun> open([
    HandleRecoveryLifecycleClass phase = HandleRecoveryLifecycleClass.preCommit,
  ]) async {
    final run = _RecoveryRun();
    run.core.progress = _progress(phase);
    addTearDown(() {
      run.container.dispose();
      run.cooldown.dispose();
    });
    await run.controller.open((
      handle: 'alice.awiki.me',
      localIdentityId: null,
    ));
    run.controller.setRiskConfirmed(true);
    return run;
  }
}

class _RecoveryCore implements HandleRecoveryCorePort {
  _RecoveryCore(this.events);
  final List<String> events;
  late HandleRecoveryProgress progress;
  Future<HandleRecoveryProgress> Function()? onActivate;
  Future<HandleRecoveryProgress> Function()? onReconcile;
  Future<HandleRecoveryProgress> Function()? onStatus;
  int activateCalls = 0;
  final reconciledOperations = <String>[];

  @override
  Future<List<HandleRecoveryProgress>> listOperationsForHandle(
    String handle,
  ) async => [progress];
  @override
  Future<HandleRecoveryProgress> getStatus(String operationId) async =>
      onStatus == null ? progress : onStatus!();
  @override
  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required bool userPresenceConfirmed,
  }) async {
    expect(operationId, 'operation-1');
    expect(userPresenceConfirmed, isTrue);
    activateCalls++;
    events.add('activate');
    return onActivate!();
  }

  @override
  Future<HandleRecoveryProgress> reconcile(String operationId) async {
    reconciledOperations.add(operationId);
    events.add('reconcile');
    return onReconcile!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected recovery mutation');
}

class _Presence implements UserPresencePort {
  _Presence(this.events);
  final List<String> events;
  bool confirmed = true;
  @override
  Future<bool> confirm({required String reason}) async {
    events.add('presence');
    return confirmed;
  }
}

class _Session implements HandleRecoverySession {
  _Session(this.events);
  final List<String> events;
  String? currentOwner = 'old-owner';
  String? previousOwner;
  Future<void> Function()? beforeRestore;
  @override
  Future<void> pauseCurrent() async {
    events.add('pause');
    previousOwner ??= currentOwner;
    currentOwner = null;
  }

  @override
  Future<void> restorePrevious() async {
    if (previousOwner == null) return;
    events.add('restore');
    await beforeRestore?.call();
    currentOwner = previousOwner;
    previousOwner = null;
  }

  @override
  Future<bool> activate(String ownerIdentityId) async {
    events.add('enter:$ownerIdentityId');
    currentOwner = ownerIdentityId;
    previousOwner = null;
    return true;
  }
}

HandleRecoveryProgress _progress(
  HandleRecoveryLifecycleClass phase,
) => HandleRecoveryProgress(
  operationId: 'operation-1',
  ownerIdentityId: 'recovered-owner',
  accountUserId: 'account-1',
  handle: 'alice.awiki.me',
  lifecycleClass: phase,
  impact: const HandleRecoveryImpact(
    localOrdinaryDataWillMigrate: true,
    otherDevicesMustRejoin: true,
  ),
  commitAttempted: phase != HandleRecoveryLifecycleClass.preCommit,
  keyState: HandleRecoveryKeyState.available,
  resultAbsent: false,
  readyToCommit: phase == HandleRecoveryLifecycleClass.preCommit,
  localMigration: HandleRecoveryLocalMigration.supported,
  discardAllowed: phase == HandleRecoveryLifecycleClass.preCommit,
  stateRootFingerprint:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
