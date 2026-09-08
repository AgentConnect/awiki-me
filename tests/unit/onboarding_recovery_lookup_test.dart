import 'dart:async';

import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/recovery/pending_handle_recovery_entry.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

final _tenantProvider = StateProvider<AppTenantProfile>(
  (ref) => defaultTenantProfile(),
);
const _alice = 'alice.awiki.me';
final _continue = find.byKey(const Key('onboarding-continue-recovery'));
final _retry = find.byKey(const Key('onboarding-recovery-lookup-retry'));

void main() {
  test('terminal start-new-only history is not a pending resume entry', () {
    final progress = _operation(_alice);
    expect(
      hasPendingHandleRecovery(
        HandleRecoveryContext(
          handle: _alice,
          progress: progress,
          allowedActions: const [HandleRecoveryAction.startNew],
        ),
      ),
      isFalse,
    );
    expect(
      hasPendingHandleRecovery(
        HandleRecoveryContext(
          handle: _alice,
          progress: progress,
          allowedActions: const [],
          blockedReason: HandleRecoveryFailureCode.localKeyUnavailable,
        ),
      ),
      isTrue,
    );
  });

  testWidgets(
    'rapid Handle edits only query the latest target after debounce',
    (tester) async {
      final run = await _LookupRun.open(tester);
      await tester.enterText(run.handleField, 'alice');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(run.handleField, 'bob');
      await run.settleLookup();

      expect(run.core.lookups, ['bob.awiki.me']);
      expect(run.gateway.registerHandleCalls, 0);
      expect(run.core.mutations, 0);
    },
  );

  testWidgets(
    'late lookup for an old Handle cannot expose its recovery entry',
    (tester) async {
      final run = await _LookupRun.open(tester);
      final pending = run.core.defer(_alice);
      await tester.enterText(run.handleField, 'alice');
      await run.settleLookup();
      await tester.enterText(run.handleField, 'bob');
      await run.settleLookup();
      pending.complete([_operation(_alice)]);
      await tester.pumpAndSettle();

      expect(run.core.lookups, [_alice, 'bob.awiki.me']);
      expect(_continue, findsNothing);
      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(run.core.mutations, 0);
    },
  );

  testWidgets(
    'late lookup from the previous tenant cannot expose a recovery entry',
    (tester) async {
      final run = await _LookupRun.open(tester);
      final pending = run.core.defer(_alice);
      await tester.enterText(run.handleField, 'alice');
      await run.settleLookup();
      run.switchTenant();
      await tester.pump();
      await run.settleLookup();
      pending.complete([_operation(_alice)]);
      await tester.pumpAndSettle();

      expect(run.core.lookups, contains('alice.awiki.ai'));
      expect(_continue, findsNothing);
      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(run.core.mutations, 0);
    },
  );

  testWidgets(
    'lookup failure can retry and continue without registration or OTP',
    (tester) async {
      final run = await _LookupRun.open(tester);
      final failed = run.core.defer(_alice);
      await tester.enterText(run.handleField, 'alice');
      await run.settleLookup();
      failed.completeError(StateError('lookup unavailable'));
      await tester.pumpAndSettle();
      expect(_retry, findsOneWidget);
      expect(_continue, findsNothing);

      run.core.results[_alice] = [_operation(_alice)];
      await run.tap(_retry);
      await run.settleLookup();
      expect(_retry, findsNothing);
      expect(_continue, findsOneWidget);
      await run.tap(_continue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HandleRecoveryPage>(find.byType(HandleRecoveryPage))
            .initialHandle,
        _alice,
      );
      expect(run.gateway.registerHandleCalls, 0);
      expect(run.core.mutations, 0);
    },
  );

  testWidgets('closing onboarding discards a late lookup failure', (
    tester,
  ) async {
    final run = await _LookupRun.open(tester);
    final pending = run.core.defer(_alice);
    await tester.enterText(run.handleField, 'alice');
    await run.settleLookup();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late lookup failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(run.core.mutations, 0);
  });

  for (final outcome in ['pending', 'empty', 'error']) {
    testWidgets(
      'submitted lookup $outcome is discarded after the Handle changes',
      (tester) async {
        final run = await _LookupRun.open(tester);
        await run.prepareSubmit();
        final pending = run.core.defer(_alice);
        await run.tap(find.text('登录/注册'));
        await tester.pump();
        expect(
          run.core.lookups.where((handle) => handle == _alice),
          hasLength(2),
        );
        await tester.enterText(run.handleField, 'bob');
        _finish(pending, outcome);
        await run.settleLookup();

        expect(find.byType(HandleRecoveryPage), findsNothing);
        expect(find.text('错误详情'), findsNothing);
        expect(run.gateway.registerHandleCalls, 0);
        expect(run.core.mutations, 0);
      },
    );
  }

  testWidgets(
    'submitted lookup stays superseded when the Handle changes away and back',
    (tester) async {
      final run = await _LookupRun.open(tester);
      await run.prepareSubmit();
      final pending = run.core.defer(_alice);
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      await tester.enterText(run.handleField, 'bob');
      await tester.enterText(run.handleField, 'alice');
      pending.complete([_operation(_alice)]);
      await run.settleLookup();

      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(run.gateway.registerHandleCalls, 0);
    },
  );

  for (final outcome in ['pending', 'error']) {
    testWidgets('submitted lookup $outcome cannot affect a new tenant', (
      tester,
    ) async {
      final run = await _LookupRun.open(tester);
      await run.prepareSubmit();
      final pending = run.core.defer(_alice);
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      run.switchTenant();
      await tester.pump();
      _finish(pending, outcome);
      await run.settleLookup();

      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(find.text('错误详情'), findsNothing);
      expect(run.gateway.registerHandleCalls, 0);
      expect(run.core.mutations, 0);
    });
  }

  testWidgets(
    'switching tenants away and back does not revive an old submission',
    (tester) async {
      final run = await _LookupRun.open(tester);
      await run.prepareSubmit();
      final originalTenant = run.container.read(_tenantProvider);
      final pending = run.core.defer(_alice);
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      run.switchTenant();
      await tester.pumpAndSettle();
      run.container.read(_tenantProvider.notifier).state = originalTenant;
      await tester.pumpAndSettle();
      pending.complete([_operation(_alice)]);
      await run.settleLookup();

      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(run.gateway.registerHandleCalls, 0);
    },
  );

  testWidgets(
    'an obsolete submission cannot block or unlock the newer target lookup',
    (tester) async {
      final run = await _LookupRun.open(tester);
      await run.prepareSubmit();
      final old = run.core.defer(_alice);
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      run.now = run.now.add(const Duration(seconds: 61));
      await tester.pump(
        const Duration(seconds: 61),
      ); // Registration OTP cooldown only.
      await run.prepareSubmit(handle: 'bob');
      final current = run.core.defer('bob.awiki.me');
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      expect(
        run.core.lookups.where((handle) => handle == 'bob.awiki.me'),
        hasLength(2),
      );

      old.complete([]);
      await tester.pumpAndSettle();
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      expect(
        run.core.lookups.where((handle) => handle == 'bob.awiki.me'),
        hasLength(2),
      );
      expect(run.gateway.registerHandleCalls, 0);
      current.complete([_operation('bob.awiki.me')]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<HandleRecoveryPage>(find.byType(HandleRecoveryPage))
            .initialHandle,
        'bob.awiki.me',
      );
      expect(run.core.mutations, 0);
    },
  );

  testWidgets(
    'failed submission lookup can retry the same target without registration',
    (tester) async {
      final run = await _LookupRun.open(tester);
      await run.prepareSubmit();
      final failed = run.core.defer(_alice);
      await run.tap(find.text('登录/注册'));
      await tester.pump();
      failed.completeError(StateError('lookup unavailable'));
      await tester.pumpAndSettle();
      expect(find.text('错误详情'), findsOneWidget);
      expect(run.gateway.registerHandleCalls, 0);
      await run.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      run.core.results[_alice] = [_operation(_alice)];
      await run.tap(find.text('登录/注册'));
      await tester.pumpAndSettle();
      expect(find.byType(HandleRecoveryPage), findsOneWidget);
      expect(run.gateway.registerHandleCalls, 0);
      expect(run.core.mutations, 0);
    },
  );
}

void _finish(Completer<List<HandleRecoveryProgress>> pending, String outcome) {
  switch (outcome) {
    case 'pending':
      pending.complete([_operation(_alice)]);
    case 'empty':
      pending.complete([]);
    case 'error':
      pending.completeError(StateError('superseded lookup failed'));
  }
}

class _LookupRun {
  _LookupRun(this.tester);
  final WidgetTester tester;
  final core = _LookupCore();
  final gateway = FakeAwikiGateway();
  DateTime now = DateTime.now();
  late ProviderContainer container;
  Finder get handleField => find.byType(CupertinoTextField).at(1);

  static Future<_LookupRun> open(WidgetTester tester) async {
    final run = _LookupRun(tester);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        gateway: run.gateway,
        providerOverrides: [
          activeAppTenantProvider.overrideWith(
            (ref) => ref.watch(_tenantProvider),
          ),
          handleRecoveryCorePortProvider.overrideWithValue(run.core),
          smsOtpCooldownClockProvider.overrideWithValue(() => run.now),
        ],
      ),
    );
    await tester.pumpAndSettle();
    run.container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    return run;
  }

  Future<void> settleLookup() async {
    // Apply input/tenant rebuilds before advancing the debounce clock.
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  Future<void> prepareSubmit({String handle = 'alice'}) async {
    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      '13800138000',
    );
    await tester.enterText(handleField, handle);
    await settleLookup();
    await tester.enterText(find.byType(CupertinoTextField).at(2), '123456');
    await tap(find.text('发送验证码'));
    await tester.pumpAndSettle();
  }

  void switchTenant() {
    container.read(_tenantProvider.notifier).state = officialTenantProfile(
      AppTenantOfficialKey.secondary,
    );
  }
}

class _LookupCore implements HandleRecoveryCorePort {
  final lookups = <String>[];
  final results = <String, List<HandleRecoveryProgress>>{};
  final pending = <String, Completer<List<HandleRecoveryProgress>>>{};
  final operations = <String, HandleRecoveryProgress>{};
  int mutations = 0;
  Completer<List<HandleRecoveryProgress>> defer(String handle) {
    final completer = Completer<List<HandleRecoveryProgress>>();
    pending[handle] = completer;
    return completer;
  }

  @override
  Future<HandleRecoveryContext> inspectContext({
    required String handle,
    String? localIdentityId,
  }) async {
    lookups.add(handle);
    final deferred = pending.remove(handle);
    final found = deferred == null
        ? (results[handle] ?? [])
        : await deferred.future;
    for (final operation in found) {
      operations[operation.operationId] = operation;
    }
    results[handle] = found;
    return HandleRecoveryContext(
      handle: handle,
      localIdentityId: localIdentityId,
      progress: found.isEmpty ? null : found.single,
      allowedActions: found.isEmpty
          ? const [HandleRecoveryAction.startNew]
          : found.single.allowedActions,
    );
  }

  @override
  Future<HandleRecoveryProgress> getStatus(String operationId) async =>
      operations[operationId]!;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    mutations++;
    throw StateError('lookup must not mutate recovery');
  }
}

HandleRecoveryProgress _operation(String handle) => HandleRecoveryProgress(
  allowedActions: const [HandleRecoveryAction.resume],
  operationId: 'operation-$handle',
  ownerIdentityId: 'owner-$handle',
  accountUserId: 'account-$handle',
  handle: handle,
  lifecycleClass: HandleRecoveryLifecycleClass.localTransitionPending,
  impact: const HandleRecoveryImpact(
    localOrdinaryDataWillMigrate: true,
    otherDevicesMustRejoin: true,
  ),
  commitAttempted: true,
  keyState: HandleRecoveryKeyState.available,
  resultAbsent: false,
  readyToCommit: false,
  localMigration: HandleRecoveryLocalMigration.supported,
  discardAllowed: false,
  stateRootFingerprint:
      'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
