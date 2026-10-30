import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:awiki_me/src/application/pin_recovery_service.dart';
import 'package:awiki_me/src/application/ports/pin_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/pin_recovery.dart';
import 'package:awiki_me/src/presentation/pin_recovery/pin_recovery_page.dart';
import 'package:awiki_me/src/presentation/pin_recovery/pin_recovery_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

const target = PinRecoveryTarget(
  targetId: 'target-a',
  fullHandle: 'alice.awiki.info',
  did: 'did:wba:awiki.info:user:alice',
  bindingGeneration: '1',
  canEnable: true,
  canRecover: true,
);
PinRecoveryProgress progress({
  PinRecoveryKind kind = PinRecoveryKind.recover,
  PinRecoveryPhase phase = PinRecoveryPhase.awaitingPin,
  List<PinRecoveryAction> actions = const [PinRecoveryAction.submitPin],
  int attempts = 0,
  String? deviceLabel,
  String? recoveredIdentityId,
}) => PinRecoveryProgress(
  operationId: 'operation-a',
  kind: kind,
  phase: phase,
  allowedActions: actions,
  target: target,
  attemptsUsed: attempts,
  attemptsLimit: 10,
  needsPhoneVerification: false,
  secureReadiness: PinRecoverySecureReadiness.notStarted,
  cleanupRemaining: 0,
  deviceLabel: deviceLabel,
  recoveredIdentityId: recoveredIdentityId,
);

class Presence implements UserPresencePort {
  bool confirmed = true;
  @override
  Future<bool> confirm({required String reason}) async => confirmed;
}

class FakePinCore implements PinRecoveryCorePort {
  @override
  String? tenantId = 'tenant';
  bool supported = true;
  PinBackupState backupState = PinBackupState.notEnabled;
  List<PinRecoveryProgress> pendingOperations = [];
  List<PinRecoveryTarget> targets = [target];
  String? selectedTargetId;
  @override
  Future<PinBackupStatus> backupStatus(String localIdentityId) async =>
      PinBackupStatus(did: 'did:wba:awiki.info:user:alice', state: backupState);
  int begins = 0, submissions = 0, confirmations = 0;
  String? lastOperation;
  PinRecoveryProgress current = progress();
  bool wrongPin = false;
  @override
  Future<bool> canBackup(String localIdentityId) async => supported;
  @override
  Future<List<PinRecoveryProgress>> listPending() async => pendingOperations;
  @override
  Future<PinPhoneChallenge> requestPhoneCode(
    String phone, {
    String? resumeOperationId,
  }) async => const PinPhoneChallenge(
    handle: 'challenge',
    maskedPhone: '***',
    resendAfterSeconds: 0,
  );
  @override
  Future<String> verifyPhoneCode({
    required String challengeHandle,
    required String code,
  }) async => 'discovery';
  @override
  Future<List<PinRecoveryTarget>> listTargets(String discoveryHandle) async =>
      targets;
  @override
  Future<String> selectTarget({
    required String discoveryHandle,
    required String targetId,
  }) async {
    selectedTargetId = targetId;
    return 'session';
  }

  @override
  Future<PinRecoveryProgress> beginEnable({
    required String sessionHandle,
    required String localIdentityId,
    required bool userPresenceConfirmed,
  }) async {
    begins++;
    return current;
  }

  @override
  Future<PinRecoveryProgress> beginRecover({
    required String sessionHandle,
    required String deviceLabel,
  }) async {
    begins++;
    return current;
  }

  @override
  Future<PinRecoveryProgress> submitPin({
    required String operationId,
    required String pin,
  }) async {
    submissions++;
    lastOperation = operationId;
    if (wrongPin) {
      current = progress(attempts: 1);
      throw const PinRecoveryFailure('invalid_pin');
    }
    return current;
  }

  @override
  Future<PinRecoveryProgress> confirmDevice({
    required String operationId,
    required bool userPresenceConfirmed,
  }) async {
    confirmations++;
    return current;
  }

  @override
  Future<PinRecoveryProgress> status(String operationId) async {
    lastOperation = operationId;
    return current;
  }

  @override
  Future<PinRecoveryProgress> resume(
    String operationId, {
    String? sessionHandle,
  }) async {
    lastOperation = operationId;
    return current;
  }

  @override
  Future<PinRecoveryProgress> cancel(String operationId) async => current;
}

void main() {
  test(
    'PIN format and matching confirmation fail before native submission',
    () async {
      final core = FakePinCore();
      final service = PinRecoveryService(core: core, userPresence: Presence());
      for (final pin in ['123', '１２３４', '12345', '12 4']) {
        expect(
          () => service.submitPin(operationId: 'operation-a', pin: pin),
          throwsA(isA<PinRecoveryFailure>()),
        );
      }
      expect(
        () => service.submitPin(
          operationId: 'operation-a',
          pin: '0123',
          confirmation: '0124',
        ),
        throwsA(isA<PinRecoveryFailure>()),
      );
      expect(core.submissions, 0);
      await service.submitPin(
        operationId: 'operation-a',
        pin: '0123',
        confirmation: '0123',
      );
      expect(core.submissions, 1);
    },
  );
  test('cancelled presence cannot begin backup or confirm device', () async {
    final core = FakePinCore(), presence = Presence()..confirmed = false;
    final service = PinRecoveryService(core: core, userPresence: presence);
    await expectLater(
      service.beginEnable(
        sessionHandle: 's',
        localIdentityId: 'id',
        presenceReason: 'backup',
      ),
      throwsA(isA<PinRecoveryFailure>()),
    );
    await expectLater(
      service.confirmDevice('operation-a', presenceReason: 'join'),
      throwsA(isA<PinRecoveryFailure>()),
    );
    expect(core.begins, 0);
    expect(core.confirmations, 0);
  });
  test(
    'root recovery and activation are distinct; only exact active identity can enter',
    () {
      expect(
        progress(phase: PinRecoveryPhase.awaitingDeviceConfirmation).canEnter,
        false,
      );
      expect(
        progress(phase: PinRecoveryPhase.localActivationPending).canEnter,
        false,
      );
      expect(
        progress(
          kind: PinRecoveryKind.enable,
          phase: PinRecoveryPhase.completed,
        ).isProtected,
        true,
      );
      expect(
        progress(
          kind: PinRecoveryKind.enable,
          phase: PinRecoveryPhase.verifyingBackup,
        ).isProtected,
        false,
      );
    },
  );
  test('late presence cannot authorize a covered page', () async {
    final core = FakePinCore();
    final service = PinRecoveryService(core: core, userPresence: Presence());
    await expectLater(
      service.beginEnable(
        sessionHandle: 's',
        localIdentityId: 'id',
        presenceReason: 'backup',
        isCurrent: () => false,
      ),
      throwsA(isA<PinRecoveryFailure>()),
    );
    await expectLater(
      service.confirmDevice(
        'operation-a',
        presenceReason: 'join',
        isCurrent: () => false,
      ),
      throwsA(isA<PinRecoveryFailure>()),
    );
    expect(core.begins, 0);
    expect(core.confirmations, 0);
  });
  Future<void> mount(
    WidgetTester tester,
    FakePinCore core,
    Widget page, {
    List<Override> overrides = const [],
    FakeAwikiGateway? gateway,
  }) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: const SizedBox(key: Key('launcher')),
        gateway: gateway ?? FakeAwikiGateway(),
        providerOverrides: [
          pinRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(Presence()),
          ...overrides,
        ],
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byKey(const Key('launcher')));
    unawaited(
      Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => page)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('stale recovered selector cannot enter a replacement DID', (
    tester,
  ) async {
    final active = progress(
      phase: PinRecoveryPhase.completed,
      recoveredIdentityId: 'identity-a',
    );
    final core = FakePinCore()..current = active;
    final gateway = FakeAwikiGateway();
    await mount(
      tester,
      core,
      PinRecoveryPage(initialOperation: active),
      gateway: gateway,
      overrides: [
        identityCorePortProvider.overrideWithValue(_ReplacementIdentity()),
      ],
    );
    await tester.ensureVisible(find.byKey(const Key('pin-recovery-enter')));
    await tester.tap(find.byKey(const Key('pin-recovery-enter')));
    await tester.pumpAndSettle();
    expect(gateway.loginCalls, 0);
    expect(find.byKey(const Key('pin-recovery-error')), findsOneWidget);
    expect(find.byKey(const Key('pin-recovery-page')), findsOneWidget);
  });
  testWidgets(
    'editing the phone discards its OTP challenge and authorized targets',
    (tester) async {
      final core = FakePinCore();
      await mount(tester, core, const PinRecoveryPage());
      await tester.enterText(
        find.byKey(const Key('pin-recovery-phone')),
        'first-phone',
      );
      await tester.tap(find.byKey(const Key('pin-recovery-send-code')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pin-recovery-verify')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('pin-recovery-phone')),
        'second-phone',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pin-recovery-verify')), findsNothing);
      expect(find.byKey(const Key('pin-recovery-otp')), findsNothing);
      expect(core.begins, 0);
      expect(core.submissions, 0);
    },
  );
  Future<void> verifyPhone(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('pin-recovery-phone')),
      'verified-phone',
    );
    await tester.tap(find.byKey(const Key('pin-recovery-send-code')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pin-recovery-otp')), '123456');
    await tester.ensureVisible(find.byKey(const Key('pin-recovery-verify')));
    await tester.tap(find.byKey(const Key('pin-recovery-verify')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'verified phone keeps multiple recovery targets explicit and selects the requested target',
    (tester) async {
      const other = PinRecoveryTarget(
        targetId: 'target-b',
        fullHandle: 'bob.awiki.info',
        did: 'did:wba:awiki.info:user:bob',
        bindingGeneration: '1',
        canEnable: true,
        canRecover: true,
      );
      final core = FakePinCore()..targets = [other, target];
      await mount(tester, core, const PinRecoveryPage());
      await verifyPhone(tester);
      expect(
        find.byKey(const Key('pin-recovery-target-target-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pin-recovery-target-target-a')),
        findsOneWidget,
      );
      expect(core.selectedTargetId, isNull);
      expect(core.begins, 0);
      final selected = find.byKey(const Key('pin-recovery-target-target-a'));
      await tester.ensureVisible(selected);
      await tester.tap(selected);
      await tester.pumpAndSettle();
      expect(core.selectedTargetId, target.targetId);
      expect(core.begins, 1);
      expect(find.byKey(const Key('pin-recovery-pin')), findsOneWidget);
    },
  );
  testWidgets(
    'backup target selection is limited to the expected local DID and Handle',
    (tester) async {
      const otherDid = PinRecoveryTarget(
        targetId: 'target-other-did',
        fullHandle: 'alice.awiki.info',
        did: 'did:wba:awiki.info:user:replacement',
        bindingGeneration: '2',
        canEnable: true,
        canRecover: false,
      );
      const otherHandle = PinRecoveryTarget(
        targetId: 'target-other-handle',
        fullHandle: 'bob.awiki.info',
        did: 'did:wba:awiki.info:user:alice',
        bindingGeneration: '1',
        canEnable: true,
        canRecover: false,
      );
      final core = FakePinCore()
        ..targets = [otherDid, otherHandle, target]
        ..current = progress(kind: PinRecoveryKind.enable);
      await mount(
        tester,
        core,
        const PinRecoveryPage(
          localIdentityId: 'identity-a',
          expectedDid: 'did:wba:awiki.info:user:alice',
          expectedHandle: 'alice.awiki.info',
        ),
      );
      await verifyPhone(tester);
      expect(
        find.byKey(const Key('pin-recovery-target-target-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('pin-recovery-target-target-other-did')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('pin-recovery-target-target-other-handle')),
        findsNothing,
      );
      expect(core.selectedTargetId, isNull);
      expect(core.begins, 0);
    },
  );
  testWidgets('explicit skip never creates a backup operation', (tester) async {
    final core = FakePinCore();
    await mount(
      tester,
      core,
      const PinRecoveryPage(
        localIdentityId: 'identity-a',
        expectedDid: 'did:wba:awiki.info:user:alice',
        offerBackup: true,
      ),
    );
    expect(find.byKey(const Key('pin-backup-not-enabled')), findsOneWidget);
    expect(find.byKey(const Key('pin-recovery-pin')), findsNothing);
    await tester.tap(find.byKey(const Key('pin-backup-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('launcher')), findsOneWidget);
    expect(core.begins, 0);
    expect(core.submissions, 0);
  });
  for (final remoteState in [PinBackupState.unknown, PinBackupState.pending]) {
    testWidgets(
      'initial optional offer preserves $remoteState without claiming disabled',
      (tester) async {
        final core = FakePinCore()..backupState = remoteState;
        await mount(
          tester,
          core,
          const PinRecoveryPage(
            localIdentityId: 'identity-a',
            expectedDid: 'did:wba:awiki.info:user:alice',
            offerBackup: true,
          ),
        );
        expect(find.byKey(const Key('pin-backup-not-enabled')), findsNothing);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('pin-backup-current-status')))
              .data,
          remoteState == PinBackupState.unknown
              ? 'Backup status unavailable; verify again when connected.'
              : 'Root backup pending',
        );
        await tester.tap(find.byKey(const Key('pin-backup-skip')));
        await tester.pumpAndSettle();
        expect(core.begins, 0);
        expect(find.byKey(const Key('launcher')), findsOneWidget);
      },
    );
  }
  testWidgets('unknown remote status is never projected as disabled', (
    tester,
  ) async {
    final core = FakePinCore()..backupState = PinBackupState.unknown;
    await mount(
      tester,
      core,
      const PinRecoveryPage(
        localIdentityId: 'identity-a',
        expectedDid: 'did:wba:awiki.info:user:alice',
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('pin-backup-current-status')))
          .data,
      'Backup status unavailable; verify again when connected.',
    );
    expect(find.byKey(const Key('pin-backup-not-enabled')), findsNothing);
  });
  testWidgets('active backup is visible without offering a PIN reset', (
    tester,
  ) async {
    final core = FakePinCore()..backupState = PinBackupState.active;
    await mount(
      tester,
      core,
      const PinRecoveryPage(
        localIdentityId: 'identity-a',
        expectedDid: 'did:wba:awiki.info:user:alice',
      ),
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('pin-backup-current-status')))
          .data,
      'Root key protected',
    );
    expect(find.byKey(const Key('pin-recovery-phone')), findsNothing);
    expect(find.byKey(const Key('pin-backup-start')), findsNothing);
    expect(core.begins, 0);
  });
  testWidgets('pending backup resumes the exact Core operation', (
    tester,
  ) async {
    final pending = progress(
      kind: PinRecoveryKind.enable,
      phase: PinRecoveryPhase.registering,
      actions: [PinRecoveryAction.resume, PinRecoveryAction.cancel],
    );
    final core = FakePinCore()
      ..pendingOperations = [pending]
      ..current = pending;
    await mount(
      tester,
      core,
      const PinRecoveryPage(
        localIdentityId: 'identity-a',
        expectedDid: 'did:wba:awiki.info:user:alice',
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('pin-recovery-resume')));
    await tester.tap(find.byKey(const Key('pin-recovery-resume')));
    await tester.pumpAndSettle();
    expect(core.lastOperation, 'operation-a');
    expect(core.begins, 0);
    expect(find.byKey(const Key('pin-recovery-cancel')), findsOneWidget);
  });
  testWidgets('unsupported custody cannot create a backup', (tester) async {
    final core = FakePinCore()..supported = false;
    await mount(
      tester,
      core,
      const PinRecoveryPage(localIdentityId: 'identity-a', offerBackup: true),
    );
    expect(find.textContaining('no exportable root control'), findsOneWidget);
    expect(find.byKey(const Key('pin-backup-start')), findsNothing);
    expect(core.begins, 0);
  });
  testWidgets(
    'cancelling a local enable never claims a concurrent active backup is off',
    (tester) async {
      final pending = progress(
        kind: PinRecoveryKind.enable,
        actions: [PinRecoveryAction.cancel],
      );
      final core = FakePinCore()
        ..backupState = PinBackupState.active
        ..pendingOperations = [pending]
        ..current = progress(
          kind: PinRecoveryKind.enable,
          phase: PinRecoveryPhase.cancelled,
          actions: [],
        );
      await mount(
        tester,
        core,
        PinRecoveryPage(
          localIdentityId: 'identity-a',
          expectedDid: target.did,
          initialOperation: pending,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('pin-recovery-cancel')));
      await tester.tap(find.byKey(const Key('pin-recovery-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Operation cancelled.'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('pin-backup-current-status')))
            .data,
        'Root key protected',
      );
      expect(find.text('PIN backup is off'), findsNothing);
    },
  );
  testWidgets(
    'cold recovery confirmation displays the Core-fixed device name',
    (tester) async {
      final core = FakePinCore();
      await mount(
        tester,
        core,
        PinRecoveryPage(
          initialOperation: progress(
            phase: PinRecoveryPhase.awaitingDeviceConfirmation,
            actions: [PinRecoveryAction.confirmDevice],
            deviceLabel: 'Home Linux',
          ),
        ),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('pin-recovery-device-label-confirmed')),
            )
            .data,
        'New device name: Home Linux',
      );
      expect(
        find.byKey(const Key('pin-recovery-confirm-device')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'wrong PIN clears secret, refreshes exact budget and never auto retries',
    (tester) async {
      final core = FakePinCore()..wrongPin = true;
      await mount(tester, core, PinRecoveryPage(initialOperation: progress()));
      await tester.enterText(find.byKey(const Key('pin-recovery-pin')), '1234');
      await tester.ensureVisible(
        find.byKey(const Key('pin-recovery-submit-pin')),
      );
      await tester.tap(find.byKey(const Key('pin-recovery-submit-pin')));
      await tester.pumpAndSettle();
      expect(core.submissions, 1);
      expect(core.lastOperation, 'operation-a');
      expect(find.text('Online attempts: 1/10'), findsOneWidget);
      final input = tester.widget<CupertinoTextField>(
        find.byKey(const Key('pin-recovery-pin')),
      );
      expect(input.obscureText, true);
      expect(input.controller!.text, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(core.submissions, 1);
      expect(core.begins, 0);
    },
  );
  testWidgets('forgot PIN allows returning without initiating V4', (
    tester,
  ) async {
    final core = FakePinCore();
    await mount(tester, core, PinRecoveryPage(initialOperation: progress()));
    await tester.ensureVisible(find.byKey(const Key('pin-recovery-forgot')));
    await tester.tap(find.byKey(const Key('pin-recovery-forgot')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Changing or resetting the backup PIN'),
      findsOneWidget,
    );
    expect(find.text('Choose recovery to a new identity'), findsOneWidget);
    await tester.tap(find.text('Return and keep using existing devices'));
    await tester.pumpAndSettle();
    expect(core.begins, 0);
    expect(core.submissions, 0);
    expect(core.confirmations, 0);
    expect(find.byKey(const Key('launcher')), findsOneWidget);
    expect(find.byKey(const Key('pin-recovery-page')), findsNothing);
  });
}

class _ReplacementIdentity extends Fake implements IdentityCorePort {
  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async =>
      const AppSession(
        did: 'did:wba:awiki.info:user:replacement',
        identityId: 'identity-a',
        displayName: 'Replacement',
      );
}
