import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/handle_recovery_service.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _scope = HandleRecoveryIdentityScope(localIdentityId: 'identity-alice');

void main() {
  test(
    'OTP response loss retries the pre-generated operation id and prepare reuses it',
    () async {
      final core = _FakeHandleRecoveryCore(requestOtpErrorsRemaining: 1);
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
        local: InMemoryAwikiProductLocalStore(),
        operationIdFactory: () => 'recover-operation-fixed',
      );
      final container = ProviderContainer(
        overrides: <Override>[
          handleRecoveryServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(handleRecoveryProvider.notifier);

      await controller.requestOtp(
        scope: _scope,
        handle: ' Alice.AWIKI.INFO ',
        phone: ' +8613800138000 ',
      );
      var state = container.read(handleRecoveryProvider);
      expect(state.otpRequested, isFalse);
      expect(state.otpOperationId, 'recover-operation-fixed');
      expect(state.error, HandleRecoveryUiError.outcomeUnknown);

      await controller.requestOtp(
        scope: _scope,
        handle: ' Alice.AWIKI.INFO ',
        phone: ' +8613800138000 ',
      );
      state = container.read(handleRecoveryProvider);
      expect(state.otpRequested, isTrue);
      expect(core.requestOperationIds, <String>[
        'recover-operation-fixed',
        'recover-operation-fixed',
      ]);

      await controller.prepare(
        scope: _scope,
        handle: ' Alice.AWIKI.INFO ',
        phone: ' +8613800138000 ',
        otp: '987580',
      );
      expect(core.lastPrepareOperationId, 'recover-operation-fixed');
    },
  );

  testWidgets(
    'pre-prepare restart re-enters phone and retries the durable operation id',
    (tester) async {
      final core = _FakeHandleRecoveryCore(requestOtpErrorsRemaining: 1);
      final local = InMemoryAwikiProductLocalStore();
      final firstService = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
        local: local,
        operationIdFactory: () => 'recover-operation-fixed',
      );
      final first = ProviderContainer(
        overrides: <Override>[
          handleRecoveryServiceProvider.overrideWithValue(firstService),
        ],
      );
      await first
          .read(handleRecoveryProvider.notifier)
          .requestOtp(
            scope: _scope,
            handle: 'alice.awiki.info',
            phone: '+8613800138000',
          );
      expect(
        first.read(handleRecoveryProvider).error,
        HandleRecoveryUiError.outcomeUnknown,
      );
      first.dispose();

      var restartedOperationIdFactoryCalls = 0;
      final restartedService = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
        local: local,
        operationIdFactory: () {
          restartedOperationIdFactoryCalls += 1;
          return 'unexpected-new-operation';
        },
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const HandleRecoveryPage(
            identityScope: _scope,
            initialHandle: 'wrong.awiki.info',
          ),
          providerOverrides: <Override>[
            handleRecoveryServiceProvider.overrideWithValue(restartedService),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final fields = tester
          .widgetList<AppTextField>(find.byType(AppTextField))
          .toList(growable: false);
      expect(fields[0].controller.text, 'alice.awiki.info');
      expect(fields[0].enabled, isFalse, reason: 'the durable Handle is fixed');
      expect(
        tester
            .widget<AppTextField>(
              find.byKey(const Key('handle-recovery-phone')),
            )
            .enabled,
        isTrue,
        reason: 'phone is transient and must be re-entered after restart',
      );

      await tester.enterText(
        find.byKey(const Key('handle-recovery-phone')),
        '+8613800138000',
      );
      await tester.tap(find.byKey(const Key('handle-recovery-send-otp')));
      await tester.pumpAndSettle();

      final restartedContainer = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('handle-recovery-page'))),
      );
      final restartedState = restartedContainer.read(handleRecoveryProvider);
      expect(restartedState.otpRequested, isTrue);
      expect(restartedState.otpOperationId, 'recover-operation-fixed');
      expect(restartedState.otpPhone, '+8613800138000');
      expect(restartedOperationIdFactoryCalls, 0);
      expect(core.requestOperationIds, <String>[
        'recover-operation-fixed',
        'recover-operation-fixed',
      ]);
      final locator = await local.loadHandleRecoveryLocator(
        localIdentityId: _scope.localIdentityId,
      );
      expect(locator?.operationId, 'recover-operation-fixed');
      expect(locator?.fullHandle, 'alice.awiki.info');
      expect(locator?.recoveryId, isNull);
    },
  );

  test('cancelling a pending OTP response clears only host state', () async {
    final core = _FakeHandleRecoveryCore(requestOtpErrorsRemaining: 1);
    final service = HandleRecoveryService(
      core: core,
      userPresence: _FakeUserPresence(),
      local: InMemoryAwikiProductLocalStore(),
      operationIdFactory: () => 'recover-operation-fixed',
    );
    final container = ProviderContainer(
      overrides: <Override>[
        handleRecoveryServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(handleRecoveryProvider.notifier);

    await controller.requestOtp(
      scope: _scope,
      handle: 'alice.awiki.info',
      phone: '+8613800138000',
    );
    await controller.cancelPendingOtp();

    final state = container.read(handleRecoveryProvider);
    expect(state.otpOperationId, isNull);
    expect(state.otpRequested, isFalse);
    expect(core.requestOtpCalls, 1);
    expect(core.prepareCalls, 0);
    expect(core.activateCalls, 0);
  });

  test(
    'ProviderContainer rebuild restores the durable exact identity locator through read-only status',
    () async {
      final core = _FakeHandleRecoveryCore(
        includeRegistryReset: true,
        statusPhase: HandleRecoveryProgressPhase.identityTransitionPending,
        includeStatusRegistryReset: true,
      );
      final local = InMemoryAwikiProductLocalStore();
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
        local: local,
      );
      final first = ProviderContainer(
        overrides: <Override>[
          handleRecoveryServiceProvider.overrideWithValue(service),
        ],
      );
      await first
          .read(handleRecoveryProvider.notifier)
          .requestOtp(
            scope: _scope,
            handle: 'alice.awiki.info',
            phone: '+8613800138000',
          );
      await first
          .read(handleRecoveryProvider.notifier)
          .prepare(
            scope: _scope,
            handle: 'alice.awiki.info',
            phone: '+8613800138000',
            otp: '987580',
          );
      first.dispose();

      final restartedContainer = ProviderContainer(
        overrides: <Override>[
          handleRecoveryServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(restartedContainer.dispose);
      final restarted = restartedContainer.read(
        handleRecoveryProvider.notifier,
      );

      await restarted.restoreForIdentity(_scope.localIdentityId);

      expect(core.statusCalls, 1);
      expect(core.lastRecoveryId, 'recovery-1');
      expect(
        restartedContainer.read(handleRecoveryProvider).progress?.phase,
        HandleRecoveryProgressPhase.identityTransitionPending,
      );
      expect(
        await local.loadDeviceRegistryEpoch(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'identity-alice',
            accountId: 'account-1',
          ),
        ),
        isNull,
        reason: 'status is read-only and must not apply the reset marker',
      );

      await restarted.resume();
      expect(core.resumeCalls, 1);
      final restoredEpoch = await local.loadDeviceRegistryEpoch(
        binding: const ProductAccountBinding(
          ownerIdentityId: 'identity-alice',
          accountId: 'account-1',
        ),
      );
      expect(restoredEpoch?.currentDid, 'did:wba:awiki.info:users:alice-new');
      expect(restoredEpoch?.bindingGeneration, '8');
    },
  );

  test(
    'user-presence cancellation never reaches Recovery activation',
    () async {
      final core = _FakeHandleRecoveryCore();
      final presence = _FakeUserPresence(confirmed: false);
      final service = HandleRecoveryService(
        core: core,
        userPresence: presence,
        local: InMemoryAwikiProductLocalStore(),
      );

      await expectLater(
        service.activate(
          recoveryId: 'recovery-1',
          presenceReason: 'confirm recovery',
        ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.userPresenceRequired,
          ),
        ),
      );
      expect(presence.calls, 1);
      expect(core.activateCalls, 0);
    },
  );

  test(
    'provider keeps confirmation App-owned and resumes by recovery id',
    () async {
      final core = _FakeHandleRecoveryCore(includeRegistryReset: true);
      final presence = _FakeUserPresence();
      final local = InMemoryAwikiProductLocalStore();
      await local.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'identity-alice',
            accountId: 'account-1',
          ),
          epoch: const ProductDeviceRegistryEpoch(
            currentDid: 'did:wba:awiki.info:users:alice-old',
            bindingGeneration: '7',
          ),
          domainVersion: '9',
          refreshedAt: DateTime.utc(2026, 8, 3),
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'old-device',
              authGeneration: '4',
              payloadJson: '{"status":"active"}',
            ),
          ],
        ),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(presence),
          productLocalStoreProvider.overrideWithValue(local),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(handleRecoveryProvider.notifier);

      await controller.requestOtp(
        scope: _scope,
        handle: ' Alice.AWIKI.INFO ',
        phone: ' +8613800138000 ',
      );
      expect(core.requestOtpCalls, 1);
      expect(container.read(handleRecoveryProvider).otpRequested, isTrue);

      await controller.prepare(
        scope: _scope,
        handle: ' Alice.AWIKI.INFO ',
        phone: ' +8613800138000 ',
        otp: '987580',
      );
      var state = container.read(handleRecoveryProvider);
      expect(core.lastOtp, '987580');
      expect(core.lastPrepareOperationId, core.lastRequestOperationId);
      expect(state.progress?.phase, HandleRecoveryProgressPhase.prepared);
      expect(state.riskConfirmed, isFalse);

      await controller.activate(presenceReason: 'confirm recovery');
      expect(core.activateCalls, 0);
      expect(presence.calls, 0);
      expect(
        container.read(handleRecoveryProvider).error,
        HandleRecoveryUiError.riskConfirmationRequired,
      );

      controller.setRiskConfirmed(true);
      await controller.activate(presenceReason: 'confirm recovery');
      state = container.read(handleRecoveryProvider);
      expect(presence.calls, 1);
      expect(core.activateCalls, 1);
      expect(core.lastRecoveryId, 'recovery-1');
      expect(
        state.progress?.phase,
        HandleRecoveryProgressPhase.remoteCommitPending,
      );

      await controller.resume();
      expect(core.resumeCalls, 1);
      expect(core.lastRecoveryId, 'recovery-1');
      expect(
        container.read(handleRecoveryProvider).progress?.phase,
        HandleRecoveryProgressPhase.completed,
      );
      final store = container.read(productLocalStoreProvider);
      expect(
        await store.loadDeviceRegistryEpochResetReceipt(
          authorization: const ProductDeviceRegistryEpochResetAuthorization(
            reference: ProductDeviceRegistryEpochResetReference(
              accountUserId: 'account-1',
              ownerIdentityId: 'identity-alice',
              previousDid: 'did:wba:awiki.info:users:alice-old',
              currentDid: 'did:wba:awiki.info:users:alice-new',
              bindingGeneration: '8',
            ),
            handle: 'alice.awiki.info',
            sourceKind: ProductIdentityTransitionSourceKind.initiator,
            sourceId: 'recover-001',
          ),
        ),
        isNotNull,
      );
    },
  );

  test(
    'authorized Join rejects a reset marker from the wrong source',
    () async {
      final local = InMemoryAwikiProductLocalStore();
      final container = ProviderContainer(
        overrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(
            _FakeHandleRecoveryCore(
              includeJoinRegistryReset: true,
              joinResetSourceKind: HandleRecoveryTransitionSourceKind.initiator,
            ),
          ),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          productLocalStoreProvider.overrideWithValue(local),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(handleRecoveryServiceProvider)
            .activateAuthorizedJoin(
              scope: _scope,
              phone: '+8613800138000',
              otp: '987580',
              handle: 'alice.awiki.info',
              did: 'did:wba:awiki.info:users:alice-new',
              operationId: 'join-operation-1',
              presenceReason: 'confirm recovery join',
            ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.transitionMismatch,
          ),
        ),
      );
      expect(
        await local.loadDeviceRegistryEpoch(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'identity-alice',
            accountId: 'account-1',
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'authorized Join applies an exact consumed reset once and preserves ordinary Join projection',
    () async {
      final core = _FakeHandleRecoveryCore(includeJoinRegistryReset: true);
      final presence = _FakeUserPresence();
      final local = InMemoryAwikiProductLocalStore();
      final service = HandleRecoveryService(
        core: core,
        userPresence: presence,
        local: local,
      );

      final first = await service.activateAuthorizedJoin(
        scope: _scope,
        phone: '+8613800138000',
        otp: '987580',
        handle: 'alice.awiki.info',
        did: 'did:wba:awiki.info:users:alice-new',
        operationId: 'join-operation-1',
        presenceReason: 'confirm recovery join',
      );
      final second = await service.resumeAuthorizedJoinActivation(
        joinSessionId: first.joinSessionId,
      );

      expect(presence.calls, 1);
      expect(core.activateJoinCalls, 1);
      expect(core.resumeJoinCalls, 1);
      expect(first.cause, DeviceJoinCause.handleRecovery);
      expect(first.handleRecovery?.handle, 'alice.awiki.info');
      expect(second.joinSessionId, first.joinSessionId);
      expect(
        await local.loadDeviceRegistryEpochResetReceipt(
          authorization: ProductDeviceRegistryEpochResetAuthorization(
            reference: const ProductDeviceRegistryEpochResetReference(
              accountUserId: 'account-1',
              ownerIdentityId: 'identity-alice',
              previousDid: 'did:wba:awiki.info:users:alice-old',
              currentDid: 'did:wba:awiki.info:users:alice-new',
              bindingGeneration: '8',
            ),
            handle: 'alice.awiki.info',
            sourceKind: ProductIdentityTransitionSourceKind.joinedDevice,
            sourceId: first.joinSessionId,
          ),
        ),
        isNotNull,
      );
    },
  );

  test(
    'pending authorized Join never advances the Product Registry epoch',
    () async {
      final local = InMemoryAwikiProductLocalStore();
      final service = HandleRecoveryService(
        core: _FakeHandleRecoveryCore(
          includeJoinRegistryReset: true,
          joinPhase: DeviceJoinPhase.pending,
          joinRemoteState: DeviceJoinRemoteState.pending,
        ),
        userPresence: _FakeUserPresence(),
        local: local,
      );

      final progress = await service.activateAuthorizedJoin(
        scope: _scope,
        phone: '+8613800138000',
        otp: '987580',
        handle: 'alice.awiki.info',
        did: 'did:wba:awiki.info:users:alice-new',
        operationId: 'join-operation-1',
        presenceReason: 'confirm recovery join',
      );

      expect(progress.cause, DeviceJoinCause.handleRecovery);
      expect(progress.phase, DeviceJoinPhase.pending);
      expect(
        await local.loadDeviceRegistryEpoch(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'identity-alice',
            accountId: 'account-1',
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'authorized Join resume rejects a non-canonical session before Core',
    () async {
      final core = _FakeHandleRecoveryCore();
      final local = InMemoryAwikiProductLocalStore();
      final service = HandleRecoveryService(
        core: core,
        userPresence: _FakeUserPresence(),
        local: local,
      );

      await expectLater(
        service.resumeAuthorizedJoinActivation(
          joinSessionId: 'join session\u0000',
        ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.transitionMismatch,
          ),
        ),
      );
      expect(core.resumeJoinCalls, 0);
      expect(
        await local.loadDeviceRegistryEpoch(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'identity-alice',
            accountId: 'account-1',
          ),
        ),
        isNull,
      );
    },
  );

  test(
    'pre-transition progress cannot apply a Registry reset marker',
    () async {
      final local = InMemoryAwikiProductLocalStore();
      const binding = ProductAccountBinding(
        ownerIdentityId: 'identity-alice',
        accountId: 'account-1',
      );
      await local.replaceDeviceRegistrySnapshot(
        ProductDeviceRegistrySnapshot(
          binding: binding,
          epoch: const ProductDeviceRegistryEpoch(
            currentDid: 'did:wba:awiki.info:users:alice-old',
            bindingGeneration: '7',
          ),
          domainVersion: '9',
          refreshedAt: DateTime.utc(2026, 8, 3),
          devices: const <ProductDeviceRegistryItem>[
            ProductDeviceRegistryItem(
              protocolDeviceId: 'old-device',
              authGeneration: '4',
              payloadJson: '{"status":"active"}',
            ),
          ],
        ),
      );
      final service = HandleRecoveryService(
        core: _FakeHandleRecoveryCore(
          activationPhase: HandleRecoveryProgressPhase.remoteCommitted,
          includeActivationRegistryReset: true,
        ),
        userPresence: _FakeUserPresence(),
        local: local,
      );

      await expectLater(
        service.activate(
          recoveryId: 'recovery-1',
          presenceReason: 'confirm recovery',
        ),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.transitionMismatch,
          ),
        ),
      );
      expect(
        await local.loadDeviceRegistryEpochResetReceipt(
          authorization: const ProductDeviceRegistryEpochResetAuthorization(
            reference: ProductDeviceRegistryEpochResetReference(
              accountUserId: 'account-1',
              ownerIdentityId: 'identity-alice',
              previousDid: 'did:wba:awiki.info:users:alice-old',
              currentDid: 'did:wba:awiki.info:users:alice-new',
              bindingGeneration: '8',
            ),
            handle: 'alice.awiki.info',
            sourceKind: ProductIdentityTransitionSourceKind.initiator,
            sourceId: 'recover-001',
          ),
        ),
        isNull,
      );
      final retained = await local.loadDeviceRegistrySnapshot(binding: binding);
      expect(retained?.epoch.currentDid, 'did:wba:awiki.info:users:alice-old');
      expect(retained?.domainVersion, '9');
      expect(retained?.devices.single.protocolDeviceId, 'old-device');
    },
  );

  test('all eight closed Core errors map to an explicit safe UI action', () {
    const expected = <HandleRecoveryFailureCode, HandleRecoveryUiAction>{
      HandleRecoveryFailureCode.notPrepared: HandleRecoveryUiAction.terminal,
      HandleRecoveryFailureCode.userPresenceRequired:
          HandleRecoveryUiAction.userAction,
      HandleRecoveryFailureCode.transitionMismatch:
          HandleRecoveryUiAction.terminal,
      HandleRecoveryFailureCode.transitionChainUnsupported:
          HandleRecoveryUiAction.terminal,
      HandleRecoveryFailureCode.remoteStateChanged:
          HandleRecoveryUiAction.exactResume,
      HandleRecoveryFailureCode.outcomeUnknown:
          HandleRecoveryUiAction.exactResume,
      HandleRecoveryFailureCode.localStateUnavailable:
          HandleRecoveryUiAction.localBlocked,
      HandleRecoveryFailureCode.blocked: HandleRecoveryUiAction.localBlocked,
    };

    for (final entry in expected.entries) {
      final mapped = handleRecoveryUiErrorFrom(
        HandleRecoveryFailure(entry.key),
      );
      expect(mapped.code, entry.key);
      expect(mapped.action, entry.value);
      expect(mapped.safeCode, entry.key.name);
    }
  });

  testWidgets(
    'structured OTP rate limit survives cancelling and changing the target',
    (tester) async {
      final retryAt = DateTime.now().toUtc().add(const Duration(seconds: 30));
      final core = _FakeHandleRecoveryCore(
        requestOtpError: HandleRecoveryOtpRateLimited(
          retryAfterSeconds: 30,
          retryAt: retryAt,
        ),
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const HandleRecoveryPage(
            identityScope: _scope,
            initialHandle: 'alice.awiki.info',
          ),
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('handle-recovery-phone')),
        '+8613800138000',
      );
      await tester.tap(find.byKey(const Key('handle-recovery-send-otp')));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('handle-recovery-page'))),
      );
      expect(core.requestOtpCalls, 1);
      expect(
        container.read(handleRecoveryProvider).error,
        HandleRecoveryUiError.rateLimited,
      );
      expect(
        container.read(smsOtpCooldownProvider).remainingSeconds,
        inInclusiveRange(29, 30),
      );

      await tester.tap(find.byKey(const Key('handle-recovery-cancel-otp')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('handle-recovery-phone')),
        '+8613900139000',
      );
      expect(
        tester
            .widget<AppSecondaryButton>(
              find.byKey(const Key('handle-recovery-send-otp')),
            )
            .onPressed,
        isNull,
      );
      expect(core.requestOtpCalls, 1);
    },
  );

  testWidgets('page collects OTP, gates activation, and renders V1 risks', (
    tester,
  ) async {
    final core = _FakeHandleRecoveryCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const HandleRecoveryPage(
          identityScope: _scope,
          initialHandle: 'alice.awiki.info',
        ),
        providerOverrides: <Override>[
          handleRecoveryCorePortProvider.overrideWithValue(core),
          userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
        ],
      ),
    );

    await tester.enterText(
      find.byKey(const Key('handle-recovery-phone')),
      '+8613800138000',
    );
    await tester.enterText(
      find.byKey(const Key('handle-recovery-otp')),
      '987580',
    );
    await tester.tap(find.byKey(const Key('handle-recovery-send-otp')));
    await tester.pumpAndSettle();
    expect(core.requestOtpCalls, 1);

    await tester.tap(find.byKey(const Key('handle-recovery-verify')));
    await tester.pumpAndSettle();
    expect(core.prepareCalls, 1);
    expect(core.lastOtp, '987580');
    expect(find.text('987580'), findsNothing);
    expect(find.textContaining('你的 Handle 会保留'), findsOneWidget);
    expect(find.textContaining('所有旧设备'), findsOneWidget);
    expect(find.textContaining('P5 PreKey'), findsOneWidget);
    expect(find.textContaining('A′ 是唯一批准者'), findsOneWidget);
    expect(find.textContaining('DID-only 群'), findsOneWidget);

    final activate = find.byKey(const Key('handle-recovery-activate'));
    await tester.scrollUntilVisible(
      activate,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<AppPrimaryButton>(activate).onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    await tester.pump();
    expect(tester.widget<AppPrimaryButton>(activate).onPressed, isNotNull);

    await tester.tap(activate);
    await tester.pumpAndSettle();
    expect(core.activateCalls, 1);
    expect(find.textContaining('远端恢复结果'), findsOneWidget);

    await tester.tap(find.byKey(const Key('handle-recovery-resume')));
    await tester.pumpAndSettle();
    expect(core.resumeCalls, 1);
    expect(find.textContaining('身份恢复已完成'), findsOneWidget);
  });

  for (final locale in <Locale>[const Locale('zh'), const Locale('en')]) {
    testWidgets('renders the exact irreversible V1 risks in ${locale.languageCode}', (
      tester,
    ) async {
      final core = _FakeHandleRecoveryCore();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          locale: locale,
          home: const HandleRecoveryPage(
            identityScope: _scope,
            initialHandle: 'alice.awiki.info',
          ),
          providerOverrides: <Override>[
            handleRecoveryCorePortProvider.overrideWithValue(core),
            userPresencePortProvider.overrideWithValue(_FakeUserPresence()),
          ],
        ),
      );
      await tester.enterText(
        find.byKey(const Key('handle-recovery-phone')),
        '+8613800138000',
      );
      await tester.enterText(
        find.byKey(const Key('handle-recovery-otp')),
        '987580',
      );
      await tester.tap(find.byKey(const Key('handle-recovery-send-otp')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('handle-recovery-verify')));
      await tester.pumpAndSettle();

      final expected = locale.languageCode == 'zh'
          ? <String>[
              '此恢复不可撤销。',
              '你的 Handle 会保留，但身份将切换到新的 DID。',
              '所有旧设备会立即失效，之后只能通过普通设备加入重新接入。',
              '本机只迁移普通数据。',
              '旧的 P5 PreKey、Ratchet、MLS 及其他 E2EE 密钥不会迁移。',
              'V1 不会自动恢复任何 E2EE 群或 DID-only 群。',
              '在第二台 ready 管理设备建立前，恢复后的 A′ 是唯一批准者。',
            ]
          : <String>[
              'This recovery is irreversible.',
              'Your Handle is preserved, but the identity moves to a new DID.',
              'All old devices are invalidated immediately and can return only through ordinary Device Join.',
              'Only ordinary local data is migrated on this device.',
              'Old P5 PreKeys, Ratchet, MLS, and other E2EE keys are not migrated.',
              'V1 does not automatically restore any E2EE or DID-only group.',
              'Until a second ready admin device exists, recovered A′ is the only approver.',
            ];
      for (final text in expected) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.textContaining('只有唯一批准者的 E2EE 群不支持'), findsNothing);
    });
  }
}

class _FakeHandleRecoveryCore implements HandleRecoveryCorePort {
  _FakeHandleRecoveryCore({
    this.includeRegistryReset = false,
    this.includeJoinRegistryReset = false,
    this.includeActivationRegistryReset = false,
    this.activationPhase = HandleRecoveryProgressPhase.remoteCommitPending,
    this.statusPhase = HandleRecoveryProgressPhase.prepared,
    this.includeStatusRegistryReset = false,
    this.requestOtpErrorsRemaining = 0,
    this.requestOtpError,
    this.joinResetSourceKind = HandleRecoveryTransitionSourceKind.joinedDevice,
    this.joinPhase = DeviceJoinPhase.authorized,
    this.joinRemoteState = DeviceJoinRemoteState.consumed,
  });

  final bool includeRegistryReset;
  final bool includeJoinRegistryReset;
  final bool includeActivationRegistryReset;
  final HandleRecoveryProgressPhase activationPhase;
  final HandleRecoveryProgressPhase statusPhase;
  final bool includeStatusRegistryReset;
  int requestOtpErrorsRemaining;
  final Object? requestOtpError;
  final HandleRecoveryTransitionSourceKind joinResetSourceKind;
  final DeviceJoinPhase joinPhase;
  final DeviceJoinRemoteState joinRemoteState;
  int requestOtpCalls = 0;
  int prepareCalls = 0;
  int activateCalls = 0;
  int resumeCalls = 0;
  int statusCalls = 0;
  int activateJoinCalls = 0;
  int resumeJoinCalls = 0;
  String? lastOtp;
  String? lastRecoveryId;
  String? lastRequestOperationId;
  String? lastPrepareOperationId;
  final List<String> requestOperationIds = <String>[];

  @override
  Future<HandleRecoveryOtpResult> requestHandleRecoveryOtp({
    required String handle,
    required String phone,
    required String operationId,
  }) async {
    requestOtpCalls += 1;
    lastRequestOperationId = operationId;
    requestOperationIds.add(operationId);
    if (requestOtpErrorsRemaining > 0) {
      requestOtpErrorsRemaining -= 1;
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.outcomeUnknown,
        retryable: true,
      );
    }
    final requestError = requestOtpError;
    if (requestError != null) throw requestError;
    return HandleRecoveryOtpResult(
      handle: handle,
      operationId: operationId,
      accepted: true,
      retryAfterSeconds: 60,
      retryAt: DateTime.now().toUtc().add(const Duration(seconds: 60)),
    );
  }

  @override
  Future<HandleRecoveryProgress> prepareHandleRecovery({
    required HandleRecoveryIdentityScope scope,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
  }) async {
    prepareCalls += 1;
    lastOtp = otp;
    lastPrepareOperationId = operationId;
    return _progress(HandleRecoveryProgressPhase.prepared);
  }

  @override
  Future<HandleRecoveryProgress> activateHandleRecovery({
    required String recoveryId,
    required bool userPresenceConfirmed,
  }) async {
    activateCalls += 1;
    lastRecoveryId = recoveryId;
    return _progress(
      activationPhase,
      includeRegistryReset: includeActivationRegistryReset,
    );
  }

  @override
  Future<HandleRecoveryProgress> resumeHandleRecovery({
    required String recoveryId,
  }) async {
    resumeCalls += 1;
    lastRecoveryId = recoveryId;
    return _progress(
      HandleRecoveryProgressPhase.completed,
      includeRegistryReset: includeRegistryReset,
    );
  }

  @override
  Future<HandleRecoveryProgress> handleRecoveryStatus(String recoveryId) async {
    statusCalls += 1;
    lastRecoveryId = recoveryId;
    return _progress(
      statusPhase,
      includeRegistryReset: includeStatusRegistryReset,
    );
  }

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> activateAuthorizedJoin({
    required HandleRecoveryIdentityScope scope,
    required String phone,
    required String otp,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required bool userPresenceConfirmed,
  }) async {
    activateJoinCalls += 1;
    return HandleRecoveryAuthorizedJoinProgress(
      join: _joinProgress(
        did: did,
        phase: joinPhase,
        remoteState: joinRemoteState,
      ),
      registryEpochReset: includeJoinRegistryReset
          ? _registryReset(sourceKind: joinResetSourceKind)
          : null,
    );
  }

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> resumeAuthorizedJoinActivation({
    required String joinSessionId,
  }) async {
    resumeJoinCalls += 1;
    return HandleRecoveryAuthorizedJoinProgress(
      join: _joinProgress(
        joinSessionId: joinSessionId,
        phase: joinPhase,
        remoteState: joinRemoteState,
      ),
      registryEpochReset: includeJoinRegistryReset
          ? _registryReset(
              sourceKind: joinResetSourceKind,
              sourceId: joinSessionId,
            )
          : null,
    );
  }
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

HandleRecoveryProgress _progress(
  HandleRecoveryProgressPhase phase, {
  bool includeRegistryReset = false,
}) {
  return HandleRecoveryProgress(
    recoveryId: 'recovery-1',
    handle: 'alice.awiki.info',
    phase: phase,
    impact: const HandleRecoveryImpact(
      localOrdinaryDataWillMigrate: true,
      otherDevicesMustRejoin: true,
      unsupportedE2eeGroupCount: 1,
      unsupportedDidOnlyGroupCount: 1,
    ),
    registryEpochReset: includeRegistryReset ? _registryReset() : null,
  );
}

HandleRecoveryRegistryEpochReset _registryReset({
  HandleRecoveryTransitionSourceKind sourceKind =
      HandleRecoveryTransitionSourceKind.initiator,
  String? sourceId,
}) {
  return HandleRecoveryRegistryEpochReset(
    accountUserId: 'account-1',
    ownerIdentityId: 'identity-alice',
    handle: 'alice.awiki.info',
    previousDid: 'did:wba:awiki.info:users:alice-old',
    currentDid: 'did:wba:awiki.info:users:alice-new',
    bindingGeneration: '8',
    sourceKind: sourceKind,
    sourceId:
        sourceId ??
        (sourceKind == HandleRecoveryTransitionSourceKind.initiator
            ? 'recover-001'
            : 'join-session-1'),
  );
}

DeviceJoinProgress _joinProgress({
  String joinSessionId = 'join-session-1',
  String did = 'did:wba:awiki.info:users:alice-new',
  DeviceJoinPhase phase = DeviceJoinPhase.authorized,
  DeviceJoinRemoteState remoteState = DeviceJoinRemoteState.consumed,
}) {
  return DeviceJoinProgress(
    joinSessionId: joinSessionId,
    did: did,
    protocolDeviceId: 'new-device',
    side: DeviceJoinSide.newDevice,
    phase: phase,
    remoteState: remoteState,
    expiresAt: DateTime.utc(2026, 8, 3, 1),
  );
}
