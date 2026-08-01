import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/device_revoke_outcome.dart';
import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';
import 'device_test_support.dart';

const _session = SessionIdentity(
  did: testDid,
  credentialName: 'alice',
  displayName: 'Alice',
  handle: 'alice',
);

void main() {
  test('stale Join inbox result cannot populate the next identity', () async {
    final blocked = Completer<List<DeviceJoinRequestNotice>>();
    final refreshStarted = Completer<void>();
    var joinInboxReads = 0;
    final core = FakeDeviceManagementCore()
      ..registry = _rootTransferRegistry()
      ..joinRequestsLoader = (selector) {
        joinInboxReads += 1;
        if (joinInboxReads == 1) {
          return Future<List<DeviceJoinRequestNotice>>.value(
            const <DeviceJoinRequestNotice>[],
          );
        }
        refreshStarted.complete();
        return blocked.future;
      };
    final container = _deviceContainer(core);
    addTearDown(() {
      if (!blocked.isCompleted) {
        blocked.complete(const <DeviceJoinRequestNotice>[]);
      }
      container.dispose();
    });
    final controller = container.read(devicesProvider.notifier);

    await controller.loadManagement();
    final refresh = controller.refreshJoinInbox();
    await refreshStarted.future;
    container.read(sessionProvider.notifier).setSession(_bobSession);
    blocked.complete(<DeviceJoinRequestNotice>[
      _request(protocolDeviceId: 'alice-pending-device'),
    ]);
    await refresh;

    final state = container.read(devicesProvider);
    expect(state.registry, isNull);
    expect(state.joinRequests, isEmpty);
    expect(state.activeJoin, isNull);
    expect(state.error, isNull);
  });

  test('stale Join inbox error cannot populate the next identity', () async {
    final blocked = Completer<List<DeviceJoinRequestNotice>>();
    final refreshStarted = Completer<void>();
    var joinInboxReads = 0;
    final core = FakeDeviceManagementCore()
      ..registry = _rootTransferRegistry()
      ..joinRequestsLoader = (selector) {
        joinInboxReads += 1;
        if (joinInboxReads == 1) {
          return Future<List<DeviceJoinRequestNotice>>.value(
            const <DeviceJoinRequestNotice>[],
          );
        }
        refreshStarted.complete();
        return blocked.future;
      };
    final container = _deviceContainer(core);
    addTearDown(() {
      if (!blocked.isCompleted) {
        blocked.complete(const <DeviceJoinRequestNotice>[]);
      }
      container.dispose();
    });
    final controller = container.read(devicesProvider.notifier);

    await controller.loadManagement();
    final refresh = controller.refreshJoinInbox();
    await refreshStarted.future;
    container.read(sessionProvider.notifier).setSession(_bobSession);
    blocked.completeError(StateError('alice_join_inbox_failed'));
    await refresh;

    final state = container.read(devicesProvider);
    expect(state.registry, isNull);
    expect(state.joinRequests, isEmpty);
    expect(state.activeJoin, isNull);
    expect(state.error, isNull);
  });

  testWidgets(
    'authenticated shell exposes trusted pending Join as an explicit review entry',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..registry = const DeviceRegistrySnapshot(
          did: testDid,
          devices: <DeviceSummary>[
            DeviceSummary(
              protocolDeviceId: 'admin-current',
              signingKeyId: '$testDid#admin-sign',
              e2eeKeyId: '$testDid#admin-e2ee',
              status: DeviceStatus.active,
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
          ],
        )
        ..joinRequests = <DeviceJoinRequestNotice>[
          _request(protocolDeviceId: 'device-waiting'),
        ];
      final gateway = FakeAwikiGateway()
        ..myProfile = const UserProfile(
          did: testDid,
          nickName: 'Alice',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'alice',
        );

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          gateway: gateway,
          session: _session,
          providerOverrides: <Override>[
            deviceManagementCorePortProvider.overrideWithValue(core),
          ],
        ),
      );
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      await container.read(devicesProvider.notifier).loadManagement();
      await tester.pump();

      final entry = find.bySemanticsIdentifier('device-join-request-entry');
      expect(entry, findsOneWidget);
      expect(find.text('device-waiting'), findsOneWidget);
      expect(core.startVerificationCalls, 0);
      expect(core.rejectCalls, 0);
      expect(core.confirmCalls, 0);

      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(DeviceJoinApprovalSheet), findsOneWidget);
      expect(core.startVerificationCalls, 0);
      expect(core.rejectCalls, 0);
      expect(core.confirmCalls, 0);
    },
  );

  testWidgets('settings exposes device management by default', (tester) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: _session,
        providerOverrides: <Override>[
          deviceManagementCorePortProvider.overrideWithValue(core),
        ],
      ),
    );

    expect(find.text('设备'), findsOneWidget);
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('devices-page')), findsOneWidget);
  });

  testWidgets('revoke remains an independent device action gate', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: _session,
        providerOverrides: <Override>[
          multiDeviceDeviceRevokeEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(core),
        ],
      ),
    );

    expect(find.text('设备'), findsOneWidget);
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('devices-page')), findsOneWidget);
    expect(core.registryCalls, 1);
    expect(core.localSessionCalls, 1);
  });

  testWidgets('onboarding exposes new-device Join by default', (tester) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        providerOverrides: <Override>[
          deviceManagementCorePortProvider.overrideWithValue(core),
          directoryApplicationServiceProvider.overrideWithValue(
            FakeJoinDirectory(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('将此设备加入已有账户'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-join-page')), findsOneWidget);
  });

  testWidgets('macOS onboarding exposes new-device Join by default', (
    tester,
  ) async {
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        providerOverrides: <Override>[
          deviceManagementCorePortProvider.overrideWithValue(core),
          directoryApplicationServiceProvider.overrideWithValue(
            FakeJoinDirectory(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.text('将此设备加入已有账户');
    expect(entry, findsOneWidget);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-join-page')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'device list distinguishes current/admin/member and join notice',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..registry = const DeviceRegistrySnapshot(
          did: testDid,
          devices: <DeviceSummary>[
            DeviceSummary(
              protocolDeviceId: 'phone-current',
              signingKeyId: '$testDid#phone-sign',
              e2eeKeyId: '$testDid#phone-e2ee',
              status: DeviceStatus.active,
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
            DeviceSummary(
              protocolDeviceId: 'pc-member',
              signingKeyId: '$testDid#pc-sign',
              e2eeKeyId: '$testDid#pc-e2ee',
              status: DeviceStatus.active,
              role: DeviceRole.member,
              managementReady: false,
              isCurrent: false,
            ),
          ],
        )
        ..joinRequests = <DeviceJoinRequestNotice>[
          _request(protocolDeviceId: 'pc-new'),
        ];

      await tester.pumpWidget(_app(const DevicesPage(), core));
      await tester.pumpAndSettle();

      expect(find.textContaining('phone-current · 当前设备'), findsOneWidget);
      expect(find.textContaining('管理设备 · 有效 · 可管理其他设备'), findsOneWidget);
      expect(find.textContaining('普通设备 · 有效'), findsOneWidget);
      expect(find.text('pc-new'), findsOneWidget);
    },
  );

  testWidgets(
    'permanent revoke requires explicit intent then one user-presence prompt',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..registry = DeviceRegistrySnapshot(
          did: testDid,
          devices: <DeviceSummary>[
            _device(
              id: 'admin-current',
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
            _device(id: 'member-target', role: DeviceRole.member),
          ],
        );
      final presence = FakeUserPresence();
      await tester.pumpWidget(
        _app(
          const DevicesPage(),
          core,
          presence: presence,
          deviceRevokeEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('device-revoke-protection-hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('device-revoke-admin-current')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('device-revoke-member-target')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('device-revoke-confirm-dialog')),
        findsOneWidget,
      );
      expect(core.revokeCalls, 0);
      expect(presence.calls, 0);

      await tester.tap(find.byKey(const Key('device-revoke-confirm-action')));
      await tester.pumpAndSettle();

      expect(presence.calls, 1);
      expect(core.revokeCalls, 1);
      expect(core.lastRevokedDeviceId, 'member-target');
      expect(core.lastRevokePresenceConfirmed, isTrue);
      expect(find.textContaining('普通设备 · 已撤销'), findsOneWidget);
      expect(find.textContaining('auth_generation'), findsNothing);
      expect(find.textContaining('root_proof'), findsNothing);
      expect(find.textContaining('system_type'), findsNothing);
    },
  );

  testWidgets('revoke rollout off does not expose destructive action', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..registry = DeviceRegistrySnapshot(
        did: testDid,
        devices: <DeviceSummary>[
          _device(
            id: 'admin-current',
            role: DeviceRole.admin,
            managementReady: true,
            isCurrent: true,
          ),
          _device(id: 'member-target', role: DeviceRole.member),
        ],
      );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(const DevicesPage(), core));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-revoke-member-target')), findsNothing);
    expect(core.revokeCalls, 0);
  });

  testWidgets(
    'a full Registry read completed before revoke RPC cannot classify outcome',
    (tester) async {
      final revokeRpc = Completer<DeviceRevokeResult>();
      final core = FakeDeviceManagementCore()
        ..registry = _revokeRegistry()
        ..revokeLoader =
            ({
              required selector,
              required targetDeviceId,
              required userPresenceConfirmed,
            }) => revokeRpc.future;
      await tester.pumpWidget(
        _app(const DevicesPage(), core, deviceRevokeEnabled: true),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('devices-page'))),
      );
      final controller = container.read(devicesProvider.notifier);
      final revokeFuture = controller.revokeDevice(
        target: _revokeTarget(container),
        presenceReason: 'Confirm focused revoke',
      );
      await tester.pump();

      await controller.loadManagement();
      var state = container.read(devicesProvider);
      expect(state.revokeSubmittingDeviceId, 'member-target');
      expect(state.revokeConfirmingDeviceId, isNull);
      expect(state.revokeRetryAllowedDeviceId, isNull);

      revokeRpc.completeError(StateError('revoke outcome unknown'));
      await revokeFuture;
      state = container.read(devicesProvider);
      expect(state.revokeSubmittingDeviceId, isNull);
      expect(state.revokeConfirmingDeviceId, 'member-target');
      expect(state.revokeRetryAllowedDeviceId, 'member-target');
    },
  );

  testWidgets(
    'stale revoke read reuses cancellation when newer active read applies',
    (tester) async {
      final revokeRpc = Completer<DeviceRevokeResult>();
      final revokeRead = Completer<DeviceRegistrySnapshot>();
      final newerRead = Completer<DeviceRegistrySnapshot>();
      final revokeReadStarted = Completer<void>();
      var reads = 0;
      final core = FakeDeviceManagementCore()
        ..registry = _revokeRegistry()
        ..revokeLoader =
            ({
              required selector,
              required targetDeviceId,
              required userPresenceConfirmed,
            }) => revokeRpc.future;
      await tester.pumpWidget(
        _app(const DevicesPage(), core, deviceRevokeEnabled: true),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('devices-page'))),
      );
      final controller = container.read(devicesProvider.notifier);
      final revokeFuture = controller.revokeDevice(
        target: _revokeTarget(container),
        presenceReason: 'Confirm focused revoke',
      );
      await tester.pump();
      core.registryLoader = (_) {
        reads += 1;
        if (reads == 1) {
          revokeReadStarted.complete();
          return revokeRead.future;
        }
        return newerRead.future;
      };

      revokeRpc.completeError(
        const DeviceRevokeException(
          DeviceRevokeOutcomeCategory.cancelledBeforeSubmit,
        ),
      );
      await revokeReadStarted.future;
      final newerRefresh = controller.refreshRegistryOnly();
      await tester.pump();
      revokeRead.complete(_revokeRegistry());
      await revokeFuture;

      var state = container.read(devicesProvider);
      expect(state.revokeSubmittingDeviceId, isNull);
      expect(state.revokeConfirmingDeviceId, 'member-target');
      expect(state.revokeRetryAllowedDeviceId, isNull);

      newerRead.complete(_revokeRegistry());
      await newerRefresh;
      state = container.read(devicesProvider);
      expect(state.revokeConfirmingDeviceId, isNull);
      expect(state.revokeRetryAllowedDeviceId, isNull);
      expect(state.revokeNotice, isNull);
    },
  );

  testWidgets(
    'post-RPC Registry failure cannot accept a pre-RPC revoked snapshot',
    (tester) async {
      final revokeRpc = Completer<DeviceRevokeResult>();
      final core = FakeDeviceManagementCore()
        ..registry = _revokeRegistry()
        ..revokeLoader =
            ({
              required selector,
              required targetDeviceId,
              required userPresenceConfirmed,
            }) => revokeRpc.future;
      await tester.pumpWidget(
        _app(const DevicesPage(), core, deviceRevokeEnabled: true),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('devices-page'))),
      );
      final controller = container.read(devicesProvider.notifier);
      final revokeFuture = controller.revokeDevice(
        target: _revokeTarget(container),
        presenceReason: 'Confirm focused revoke',
      );
      await tester.pump();

      core.registry = _revokedRegistry();
      await controller.loadManagement();
      expect(
        container.read(devicesProvider).revokeSubmittingDeviceId,
        'member-target',
      );
      core.registryLoader = (_) => Future<DeviceRegistrySnapshot>.error(
        StateError('post-RPC Registry unavailable'),
      );

      revokeRpc.completeError(StateError('revoke outcome unknown'));
      expect(await revokeFuture, isFalse);
      final state = container.read(devicesProvider);
      expect(state.registry, isNull);
      expect(state.revokeSubmittingDeviceId, isNull);
      expect(state.revokeConfirmingDeviceId, 'member-target');
      expect(state.revokeRetryAllowedDeviceId, isNull);
      expect(state.revokeNotice, DeviceRevokeNotice.outcomeUnknown);
    },
  );

  testWidgets(
    'stale full Registry failure cannot clear a newer confirming result',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..registry = _revokeRegistry()
        ..revokeError = StateError('revoke outcome unknown');
      await tester.pumpWidget(
        _app(const DevicesPage(), core, deviceRevokeEnabled: true),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('devices-page'))),
      );
      await _enterUnknownRevoke(container);

      final stale = Completer<DeviceRegistrySnapshot>();
      final newer = Completer<DeviceRegistrySnapshot>();
      var reads = 0;
      core.registryLoader = (_) {
        reads += 1;
        return reads == 1 ? stale.future : newer.future;
      };
      final staleLoad = container
          .read(devicesProvider.notifier)
          .loadManagement();
      await tester.pump();
      final newerRefresh = container
          .read(devicesProvider.notifier)
          .refreshRegistryOnly();
      await tester.pump();
      newer.complete(_revokeRegistry());
      await newerRefresh;
      stale.completeError(StateError('stale full refresh failed'));
      await staleLoad;

      final state = container.read(devicesProvider);
      expect(state.registry, isNotNull);
      expect(
        state.registry?.devices
            .singleWhere((device) => device.protocolDeviceId == 'member-target')
            .status,
        DeviceStatus.active,
      );
      expect(state.revokeConfirmingDeviceId, 'member-target');
      expect(state.revokeRetryAllowedDeviceId, 'member-target');
    },
  );

  testWidgets(
    'stale read-only Registry failure cannot clear a newer confirming result',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..registry = _revokeRegistry()
        ..revokeError = StateError('revoke outcome unknown');
      await tester.pumpWidget(
        _app(const DevicesPage(), core, deviceRevokeEnabled: true),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('devices-page'))),
      );
      await _enterUnknownRevoke(container);

      final stale = Completer<DeviceRegistrySnapshot>();
      final newer = Completer<DeviceRegistrySnapshot>();
      var reads = 0;
      core.registryLoader = (_) {
        reads += 1;
        return reads == 1 ? stale.future : newer.future;
      };
      final staleRefresh = container
          .read(devicesProvider.notifier)
          .refreshRegistryOnly();
      await tester.pump();
      final newerRefresh = container
          .read(devicesProvider.notifier)
          .refreshRegistryOnly();
      await tester.pump();
      newer.complete(_revokeRegistry());
      await newerRefresh;
      stale.completeError(StateError('stale read-only refresh failed'));
      await staleRefresh;

      final state = container.read(devicesProvider);
      expect(state.registry, isNotNull);
      expect(state.revokeConfirmingDeviceId, 'member-target');
      expect(state.revokeRetryAllowedDeviceId, 'member-target');
    },
  );

  testWidgets(
    'current read-only Registry failure hides the old active projection',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..registry = _revokeRegistry()
        ..revokeError = StateError('revoke outcome unknown');
      await tester.pumpWidget(
        _app(const DevicesPage(), core, deviceRevokeEnabled: true),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('devices-page'))),
      );
      await _enterUnknownRevoke(container);

      core.registryLoader = (_) => Future<DeviceRegistrySnapshot>.error(
        StateError('current refresh failed'),
      );
      await container.read(devicesProvider.notifier).refreshRegistryOnly();

      final state = container.read(devicesProvider);
      expect(state.registry, isNull);
      expect(state.revokeConfirmingDeviceId, 'member-target');
      expect(state.revokeRetryAllowedDeviceId, isNull);
    },
  );

  testWidgets('authorized member activates the exact DID once', (tester) async {
    final core = FakeDeviceManagementCore()
      ..beginResult = DeviceJoinProgress(
        joinSessionId: 'join-1',
        did: testDid,
        protocolDeviceId: 'member-new',
        side: DeviceJoinSide.newDevice,
        phase: DeviceJoinPhase.authorized,
        remoteState: DeviceJoinRemoteState.consumed,
        expiresAt: DateTime.utc(2030),
        authorizedDevice: _device(
          id: 'member-new',
          role: DeviceRole.member,
          isCurrent: true,
        ),
      );
    final gateway = FakeAwikiGateway()
      ..loginResult = const SessionIdentity(
        did: testDid,
        credentialName: 'member-new-local',
        displayName: 'Alice',
        handle: 'alice',
      );
    await tester.pumpWidget(
      _app(
        const DeviceJoinPage(autoPoll: false),
        core,
        gateway: gateway,
        session: null,
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'alice');
    await tester.enterText(fields.at(1), '+8613800138000');
    await tester.enterText(fields.at(2), '987580');
    await tester.tap(find.text('开始关联'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('device-join-page'))),
    );
    expect(gateway.loginCalls, 1);
    expect(gateway.lastLoginCredentialName, testDid);
    expect(container.read(sessionProvider).session?.did, testDid);
    expect(container.read(appRuntimeProvider).activatedDid, testDid);
    final terminalJoin = container.read(devicesProvider).activeJoin;
    expect(terminalJoin?.phase, DeviceJoinPhase.authorized);
    expect(terminalJoin?.authorizedDevice?.protocolDeviceId, 'member-new');
    expect(find.text('管理设备等待根密钥'), findsNothing);
  });

  testWidgets(
    'disposing during new-device poll cannot resume page activation',
    (tester) async {
      final pollStarted = Completer<void>();
      final pollResult = Completer<DeviceJoinProgress>();
      final core = FakeDeviceManagementCore()
        ..localSessions = <DeviceJoinProgress>[
          testJoinProgress(
            side: DeviceJoinSide.newDevice,
            phase: DeviceJoinPhase.pending,
            remoteState: DeviceJoinRemoteState.pending,
            sas: null,
          ),
        ]
        ..pollNewLoader = (joinSessionId) {
          if (!pollStarted.isCompleted) pollStarted.complete();
          return pollResult.future;
        };
      final gateway = FakeAwikiGateway()
        ..loginResult = const SessionIdentity(
          did: testDid,
          credentialName: 'member-new-local',
          displayName: 'Alice',
          handle: 'alice',
        );

      await tester.pumpWidget(
        _app(
          const DeviceJoinPage(autoPoll: false),
          core,
          gateway: gateway,
          session: null,
        ),
      );
      await tester.pump();
      await pollStarted.future;
      await tester.pumpWidget(const SizedBox.shrink());
      pollResult.complete(
        _authorizedNewDeviceProgress(
          authorizedDevice: _device(
            id: 'member-new',
            role: DeviceRole.member,
            isCurrent: true,
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(gateway.loginCalls, 0);
    },
  );

  testWidgets(
    'restart rehydrates authorized device projection before activation',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..localSessions = <DeviceJoinProgress>[_authorizedNewDeviceProgress()]
        ..pollNewResult = _authorizedNewDeviceProgress(
          authorizedDevice: _device(
            id: 'member-new',
            role: DeviceRole.member,
            isCurrent: true,
          ),
        );
      final gateway = FakeAwikiGateway()
        ..loginResult = const SessionIdentity(
          did: testDid,
          credentialName: 'member-new-local',
          displayName: 'Alice',
          handle: 'alice',
        );

      await tester.pumpWidget(
        _app(
          const DeviceJoinPage(autoPoll: false),
          core,
          gateway: gateway,
          session: null,
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('device-join-page'))),
      );
      expect(core.pollCalls, 1);
      expect(gateway.loginCalls, 1);
      expect(gateway.lastLoginCredentialName, testDid);
      expect(container.read(sessionProvider).session?.did, testDid);
      expect(container.read(appRuntimeProvider).activatedDid, testDid);
    },
  );

  testWidgets(
    'missing authorized projection fails closed and can retry hydration',
    (tester) async {
      final core = FakeDeviceManagementCore()
        ..localSessions = <DeviceJoinProgress>[_authorizedNewDeviceProgress()]
        ..pollNewResult = _authorizedNewDeviceProgress();
      final gateway = FakeAwikiGateway()
        ..loginResult = const SessionIdentity(
          did: testDid,
          credentialName: 'member-new-local',
          displayName: 'Alice',
          handle: 'alice',
        );

      await tester.pumpWidget(
        _app(
          const DeviceJoinPage(autoPoll: false),
          core,
          gateway: gateway,
          session: null,
        ),
      );
      await tester.pumpAndSettle();

      expect(core.pollCalls, 1);
      expect(gateway.loginCalls, 0);
      expect(find.text('重试设备激活'), findsOneWidget);
      expect(find.text('完成'), findsNothing);

      core.pollNewResult = _authorizedNewDeviceProgress(
        authorizedDevice: _device(
          id: 'member-new',
          role: DeviceRole.member,
          isCurrent: true,
        ),
      );
      await tester.tap(find.text('重试设备激活'));
      await tester.pumpAndSettle();

      expect(core.pollCalls, 2);
      expect(gateway.loginCalls, 1);
    },
  );

  testWidgets('restart rejects an authorized projection for another device', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..localSessions = <DeviceJoinProgress>[
        _authorizedNewDeviceProgress(
          authorizedDevice: _device(
            id: 'member-other',
            role: DeviceRole.member,
            isCurrent: true,
          ),
        ),
      ];
    final gateway = FakeAwikiGateway()
      ..loginResult = const SessionIdentity(
        did: testDid,
        credentialName: 'member-new-local',
        displayName: 'Alice',
        handle: 'alice',
      );

    await tester.pumpWidget(
      _app(
        const DeviceJoinPage(autoPoll: false),
        core,
        gateway: gateway,
        session: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 0);
    expect(find.byKey(const Key('device-join-error')), findsOneWidget);
    expect(find.text('完成'), findsNothing);
  });

  testWidgets(
    'approval remains completed after consumed request leaves the inbox',
    (tester) async {
      final request = _request(
        state: DeviceJoinRemoteState.responseVerified,
        claimedByCurrentDevice: true,
        canStartVerification: false,
      );
      final core = FakeDeviceManagementCore()
        ..registry = _rootTransferRegistry()
        ..joinRequests = <DeviceJoinRequestNotice>[request]
        ..verificationProgress = testJoinProgress();
      final presence = FakeUserPresence();
      await tester.pumpWidget(
        _app(
          DeviceJoinApprovalSheet(request: request),
          core,
          presence: presence,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('482917'), findsOneWidget);
      final switches = find.byType(CupertinoSwitch);
      expect(switches, findsOneWidget);
      expect(find.byKey(const Key('device-admin-toggle')), findsNothing);
      expect(find.textContaining('二维码'), findsNothing);
      expect(find.textContaining('扫码'), findsNothing);

      await tester.tap(switches.first);
      await tester.pump();
      await tester.tap(find.text('确认并授权'));
      await tester.pumpAndSettle();

      expect(core.lastPreparedSasConfirmed, isTrue);
      expect(core.lastPresenceConfirmed, isTrue);
      expect(presence.calls, 1);
      expect(find.text('设备已加入'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('确认并授权'), findsNothing);
      expect(find.text('验证码不一致'), findsNothing);
      expect(find.text('拒绝设备'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('device-join-approval-sheet'))),
      );
      core.joinRequests = const <DeviceJoinRequestNotice>[];
      await container.read(devicesProvider.notifier).refreshJoinInbox();
      await tester.pumpAndSettle();

      expect(core.localVerificationCalls, 1);
      expect(find.byKey(const Key('device-approval-error')), findsNothing);
      expect(find.text('设备已加入'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('等待管理设备响应'), findsNothing);
      expect(find.text('拒绝设备'), findsNothing);
    },
  );

  testWidgets(
    'just-completed Join prepares before one root-transfer confirmation',
    (tester) async {
      final request = _request(
        state: DeviceJoinRemoteState.responseVerified,
        claimedByCurrentDevice: true,
        canStartVerification: false,
      );
      final recipient = _device(id: 'device-new', role: DeviceRole.member);
      final core = FakeDeviceManagementCore()
        ..registry = DeviceRegistrySnapshot(
          did: testDid,
          devices: <DeviceSummary>[
            _device(
              id: 'admin-current',
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
            recipient,
          ],
        )
        ..joinRequests = <DeviceJoinRequestNotice>[request]
        ..verificationProgress = testJoinProgress()
        ..confirmResult = DeviceJoinProgress(
          joinSessionId: 'join-1',
          did: testDid,
          protocolDeviceId: 'device-new',
          side: DeviceJoinSide.admin,
          phase: DeviceJoinPhase.authorized,
          remoteState: DeviceJoinRemoteState.consumed,
          expiresAt: DateTime.utc(2030),
          authorizedDevice: recipient,
        );
      final transfer = FakeRootKeyTransferPort();
      final presence = FakeUserPresence();
      await tester.pumpWidget(
        _app(
          DeviceJoinApprovalSheet(request: request),
          core,
          presence: presence,
          rootTransfer: transfer,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pump();
      await tester.tap(find.text('确认并授权'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('root-transfer-grant-management')),
        findsOneWidget,
      );
      expect(transfer.prepareCalls, 0);
      expect(presence.calls, 1);

      await tester.tap(find.byKey(const Key('root-transfer-grant-management')));
      await tester.pumpAndSettle();

      expect(transfer.prepareCalls, 1);
      expect(transfer.confirmCalls, 0);
      expect(presence.calls, 1);
      expect(
        find.byKey(const Key('root-transfer-recipient-summary')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('root-transfer-confirm-send')));
      await tester.pumpAndSettle();

      expect(presence.calls, 2);
      expect(transfer.confirmCalls, 1);
      expect(transfer.lastUserPresenceConfirmed, isTrue);
      expect(find.byKey(const Key('root-transfer-sent')), findsOneWidget);
      expect(find.textContaining('root_private_key'), findsNothing);
      expect(find.textContaining('authorization_handle'), findsNothing);
    },
  );

  testWidgets('slow root preparation cannot return into a closed Join', (
    tester,
  ) async {
    final request = _request(
      state: DeviceJoinRemoteState.responseVerified,
      claimedByCurrentDevice: true,
      canStartVerification: false,
    );
    final recipient = _device(id: 'device-new', role: DeviceRole.member);
    final core = FakeDeviceManagementCore()
      ..registry = DeviceRegistrySnapshot(
        did: testDid,
        devices: <DeviceSummary>[
          _device(
            id: 'admin-current',
            role: DeviceRole.admin,
            managementReady: true,
            isCurrent: true,
          ),
          recipient,
        ],
      )
      ..joinRequests = <DeviceJoinRequestNotice>[request]
      ..verificationProgress = testJoinProgress()
      ..confirmResult = DeviceJoinProgress(
        joinSessionId: 'join-1',
        did: testDid,
        protocolDeviceId: 'device-new',
        side: DeviceJoinSide.admin,
        phase: DeviceJoinPhase.authorized,
        remoteState: DeviceJoinRemoteState.consumed,
        expiresAt: DateTime.utc(2030),
        authorizedDevice: recipient,
      );
    final transfer = FakeRootKeyTransferPort()..deferPrepare = true;
    final presence = FakeUserPresence();
    await tester.pumpWidget(
      _app(
        DeviceJoinApprovalSheet(request: request),
        core,
        presence: presence,
        rootTransfer: transfer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pump();
    await tester.tap(find.text('确认并授权'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('root-transfer-grant-management')));
    await tester.pump();
    await transfer.prepareStarted.future;
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('device-join-approval-sheet'))),
    );
    container.read(devicesProvider.notifier).clearActive();
    transfer.completeDeferredPrepare();
    await tester.pumpAndSettle();

    expect(transfer.confirmCalls, 1);
    expect(transfer.lastUserPresenceConfirmed, isFalse);
    expect(presence.calls, 1);
    expect(
      find.byKey(const Key('root-transfer-recipient-summary')),
      findsNothing,
    );
    expect(find.byKey(const Key('root-transfer-confirm-send')), findsNothing);
    expect(
      container.read(devicesProvider).rootTransfer.phase,
      RootKeyTransferPhase.idle,
    );
  });

  testWidgets('switching Join consumes and hides the previous root handle', (
    tester,
  ) async {
    final request = _request(
      state: DeviceJoinRemoteState.responseVerified,
      claimedByCurrentDevice: true,
      canStartVerification: false,
    );
    final recipient = _device(id: 'device-new', role: DeviceRole.member);
    final core = FakeDeviceManagementCore()
      ..registry = DeviceRegistrySnapshot(
        did: testDid,
        devices: <DeviceSummary>[
          _device(
            id: 'admin-current',
            role: DeviceRole.admin,
            managementReady: true,
            isCurrent: true,
          ),
          recipient,
        ],
      )
      ..joinRequests = <DeviceJoinRequestNotice>[request]
      ..verificationProgress = testJoinProgress()
      ..confirmResult = DeviceJoinProgress(
        joinSessionId: 'join-1',
        did: testDid,
        protocolDeviceId: 'device-new',
        side: DeviceJoinSide.admin,
        phase: DeviceJoinPhase.authorized,
        remoteState: DeviceJoinRemoteState.consumed,
        expiresAt: DateTime.utc(2030),
        authorizedDevice: recipient,
      );
    final transfer = FakeRootKeyTransferPort();
    final presence = FakeUserPresence();
    await tester.pumpWidget(
      _app(
        DeviceJoinApprovalSheet(request: request),
        core,
        presence: presence,
        rootTransfer: transfer,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pump();
    await tester.tap(find.text('确认并授权'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('root-transfer-grant-management')));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('device-join-approval-sheet'))),
    );
    await container
        .read(devicesProvider.notifier)
        .selectJoinRequest(
          _request(joinSessionId: 'join-2', protocolDeviceId: 'device-other'),
        );
    final sent = await container
        .read(devicesProvider.notifier)
        .confirmAndSendRootTransfer(presenceReason: 'Confirm root transfer');
    await tester.pumpAndSettle();

    expect(sent, isFalse);
    expect(transfer.confirmCalls, 1);
    expect(transfer.lastUserPresenceConfirmed, isFalse);
    expect(presence.calls, 1);
    expect(
      find.byKey(const Key('root-transfer-recipient-summary')),
      findsNothing,
    );
    expect(find.byKey(const Key('root-transfer-confirm-send')), findsNothing);
  });

  testWidgets('device list never exposes a generic root-transfer action', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()..registry = _rootTransferRegistry();
    await tester.pumpWidget(_app(const DevicesPage(), core));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('root-transfer-admin-new')), findsNothing);
    expect(find.text('继续授予管理权限'), findsNothing);
  });

  testWidgets('opening a notice is read-only until verification starts', (
    tester,
  ) async {
    final request = _request();
    final core = FakeDeviceManagementCore()
      ..joinRequests = <DeviceJoinRequestNotice>[request];
    await tester.pumpWidget(
      _app(DeviceJoinApprovalSheet(request: request), core),
    );
    await tester.pumpAndSettle();

    expect(core.startVerificationCalls, 0);
    expect(core.localVerificationCalls, 0);
    expect(find.byKey(const Key('device-approval-sas')), findsNothing);

    await tester.tap(find.text('开始验证'));
    await tester.pumpAndSettle();

    expect(core.startVerificationCalls, 1);
    expect(core.prepareCalls, 0);
    expect(core.confirmCalls, 0);
  });

  testWidgets('a request claimed by another admin stays read-only', (
    tester,
  ) async {
    final request = _request(
      state: DeviceJoinRemoteState.challengeSent,
      canStartVerification: false,
    );
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      _app(DeviceJoinApprovalSheet(request: request), core),
    );
    await tester.pumpAndSettle();

    expect(find.text('另一台管理设备正在处理此请求'), findsOneWidget);
    expect(find.text('开始验证'), findsNothing);
    expect(find.text('确认并授权'), findsNothing);
    expect(core.startVerificationCalls, 0);
    expect(core.localVerificationCalls, 0);
  });

  testWidgets(
    'claimed challenge waits locally and response notification restores SAS',
    (tester) async {
      final challenge = _request(
        state: DeviceJoinRemoteState.challengeSent,
        claimedByCurrentDevice: true,
        canStartVerification: false,
      );
      final core = FakeDeviceManagementCore()
        ..registry = _rootTransferRegistry()
        ..joinRequests = <DeviceJoinRequestNotice>[challenge]
        ..verificationProgress = testJoinProgress();
      await tester.pumpWidget(
        _app(DeviceJoinApprovalSheet(request: challenge), core),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('device-join-approval-sheet'))),
      );

      await container.read(devicesProvider.notifier).loadManagement();
      await tester.pumpAndSettle();

      expect(core.localVerificationCalls, 0);
      expect(find.byKey(const Key('device-approval-error')), findsNothing);
      expect(find.byKey(const Key('device-approval-sas')), findsNothing);

      core.joinRequests = <DeviceJoinRequestNotice>[
        _request(
          state: DeviceJoinRemoteState.responseVerified,
          claimedByCurrentDevice: true,
          canStartVerification: false,
        ),
      ];
      await container.read(devicesProvider.notifier).refreshJoinInbox();
      await tester.pumpAndSettle();

      expect(core.localVerificationCalls, 1);
      expect(find.byKey(const Key('device-approval-error')), findsNothing);
      expect(find.byKey(const Key('device-approval-sas')), findsOneWidget);
      expect(find.text('482917'), findsOneWidget);
    },
  );

  testWidgets('SAS mismatch rejects without preparing approval', (
    tester,
  ) async {
    final request = _request(
      state: DeviceJoinRemoteState.responseVerified,
      claimedByCurrentDevice: true,
      canStartVerification: false,
    );
    final core = FakeDeviceManagementCore()
      ..verificationProgress = testJoinProgress();
    await tester.pumpWidget(
      _app(DeviceJoinApprovalSheet(request: request), core),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('验证码不一致'));
    await tester.pumpAndSettle();

    expect(core.rejectCalls, 1);
    expect(core.lastRejectReason, DeviceJoinRejectReason.sasMismatch);
    expect(core.prepareCalls, 0);
    expect(core.confirmCalls, 0);
  });

  testWidgets('user-presence rejection never authorizes the device', (
    tester,
  ) async {
    final request = _request(
      state: DeviceJoinRemoteState.responseVerified,
      claimedByCurrentDevice: true,
      canStartVerification: false,
    );
    final core = FakeDeviceManagementCore()
      ..verificationProgress = testJoinProgress();
    final presence = FakeUserPresence(result: false);
    await tester.pumpWidget(
      _app(DeviceJoinApprovalSheet(request: request), core, presence: presence),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CupertinoSwitch).first);
    await tester.pump();
    await tester.tap(find.text('确认并授权'));
    await tester.pumpAndSettle();

    expect(core.lastPresenceConfirmed, isFalse);
    expect(presence.calls, 1);
    expect(find.textContaining('设备未获授权'), findsOneWidget);
    expect(find.text('设备已加入'), findsNothing);
  });

  testWidgets('new device restores a short-lived six-digit SAS after restart', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..localSessions = <DeviceJoinProgress>[
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.responsePrepared,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        ),
      ];
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('device-join-sas')), findsOneWidget);
    expect(find.text('482917'), findsOneWidget);
    expect(core.pollCalls, 1);
    expect(find.textContaining('服务器传输'), findsOneWidget);
    expect(find.textContaining('二维码'), findsNothing);
    expect(find.textContaining('扫码'), findsNothing);
  });

  testWidgets('new-device form clears OTP immediately after begin', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'alice');
    await tester.enterText(fields.at(1), '+8613800138000');
    await tester.enterText(fields.at(2), '987580');
    await tester.tap(find.text('开始关联'));
    await tester.pumpAndSettle();

    expect(core.beginCalls, 1);
    expect(core.lastOtp, '987580');
    expect(find.text('987580'), findsNothing);
    expect(find.text('等待管理设备响应'), findsOneWidget);
  });

  testWidgets('new-device form sends OTP through the Join auth boundary', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'alice');
    await tester.enterText(fields.at(1), '+8613800138000');
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();

    expect(core.sendOtpCalls, 1);
  });

  testWidgets('Join SMS rate limit shows retry reason and disables resend', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..sendOtpError = const DeviceJoinSmsOtpRateLimited(retryAfterSeconds: 2);
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(CupertinoTextField);
    await tester.enterText(fields.at(0), 'alice');
    await tester.enterText(fields.at(1), '+8613800138000');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();

    expect(find.text('验证码发送过于频繁，请 2 秒后重试'), findsOneWidget);
    expect(find.text('设备操作失败，请刷新后重试'), findsNothing);
    expect(find.text('重新发送（2秒）'), findsOneWidget);
    await tester.tap(find.text('重新发送（2秒）'));
    await tester.pump();
    expect(core.sendOtpCalls, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('验证码发送过于频繁，请 1 秒后重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.textContaining('验证码发送过于频繁'), findsNothing);
  });

  testWidgets('cancel is projected as one terminal state', (tester) async {
    final core = FakeDeviceManagementCore()
      ..localSessions = <DeviceJoinProgress>[
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.pending,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        ),
      ];
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消关联'));
    await tester.pumpAndSettle();

    expect(find.text('设备关联已取消'), findsOneWidget);
    expect(core.cancelCalls, 1);
  });

  testWidgets('expiration is projected without authorizing the device', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..localSessions = <DeviceJoinProgress>[
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.pending,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        ),
      ]
      ..pollNewResult = testJoinProgress(
        side: DeviceJoinSide.newDevice,
        phase: DeviceJoinPhase.expired,
        remoteState: DeviceJoinRemoteState.expired,
        sas: null,
      );
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('设备关联已过期，请重新发起'), findsOneWidget);
    expect(find.text('设备已加入'), findsNothing);
  });

  testWidgets('raw transport errors never reach the Join screen', (
    tester,
  ) async {
    const secret = 'token=must-not-render';
    final core = FakeDeviceManagementCore()
      ..localSessions = <DeviceJoinProgress>[
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.pending,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        ),
      ]
      ..pollError = StateError('remote failed $secret');
    await tester.pumpWidget(
      _app(const DeviceJoinPage(autoPoll: false), core, session: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('设备操作失败，请刷新后重试'), findsOneWidget);
    expect(find.textContaining(secret), findsNothing);
  });

  testWidgets('admin restart restores verified join notices', (tester) async {
    final core = FakeDeviceManagementCore()
      ..registry = _rootTransferRegistry()
      ..joinRequests = <DeviceJoinRequestNotice>[
        _request(
          state: DeviceJoinRemoteState.challengeSent,
          claimedByCurrentDevice: true,
          canStartVerification: false,
        ),
      ];
    await tester.pumpWidget(_app(const DevicesPage(), core));
    await tester.pumpAndSettle();

    expect(find.text('待审批'), findsOneWidget);
    expect(find.text('device-new'), findsOneWidget);
    expect(core.joinRequestCalls, 1);
  });
}

const _bobSession = SessionIdentity(
  did: 'did:wba:awiki.info:user:bob:e1_test',
  credentialName: 'bob',
  displayName: 'Bob',
  handle: 'bob',
);

ProviderContainer _deviceContainer(FakeDeviceManagementCore core) {
  return ProviderContainer(
    overrides: <Override>[
      deviceManagementCorePortProvider.overrideWithValue(core),
      sessionProvider.overrideWith(
        (ref) => SessionController()..setSession(_session),
      ),
    ],
  );
}

DeviceJoinRequestNotice _request({
  String joinSessionId = 'join-1',
  String protocolDeviceId = 'device-new',
  DeviceJoinRemoteState state = DeviceJoinRemoteState.pending,
  bool claimedByCurrentDevice = false,
  bool canStartVerification = true,
}) => DeviceJoinRequestNotice(
  eventId: 'event-$joinSessionId',
  joinSessionId: joinSessionId,
  did: testDid,
  protocolDeviceId: protocolDeviceId,
  candidateKeyFingerprint: 'sha256:abc123',
  issuedAt: DateTime.utc(2026, 7, 19),
  expiresAt: DateTime.utc(2030),
  state: state,
  claimedByCurrentDevice: claimedByCurrentDevice,
  canStartVerification: canStartVerification,
);

DeviceJoinProgress _authorizedNewDeviceProgress({
  DeviceSummary? authorizedDevice,
}) {
  return DeviceJoinProgress(
    joinSessionId: 'join-1',
    did: testDid,
    protocolDeviceId: 'member-new',
    side: DeviceJoinSide.newDevice,
    phase: DeviceJoinPhase.authorized,
    remoteState: DeviceJoinRemoteState.consumed,
    expiresAt: DateTime.utc(2030),
    authorizedDevice: authorizedDevice,
  );
}

Widget _app(
  Widget home,
  FakeDeviceManagementCore core, {
  FakeUserPresence? presence,
  FakeRootKeyTransferPort? rootTransfer,
  FakeAwikiGateway? gateway,
  bool deviceRevokeEnabled = false,
  SessionIdentity? session = _session,
}) {
  return buildLocalizedTestApp(
    home: home,
    gateway: gateway,
    session: session,
    providerOverrides: <Override>[
      multiDeviceDeviceRevokeEnabledProvider.overrideWithValue(
        deviceRevokeEnabled,
      ),
      deviceManagementCorePortProvider.overrideWithValue(core),
      rootKeyTransferPortProvider.overrideWithValue(
        rootTransfer ?? FakeRootKeyTransferPort(),
      ),
      directoryApplicationServiceProvider.overrideWithValue(
        FakeJoinDirectory(),
      ),
      userPresencePortProvider.overrideWithValue(
        presence ?? FakeUserPresence(),
      ),
    ],
  );
}

DeviceRegistrySnapshot _rootTransferRegistry({bool recipientReady = false}) {
  return DeviceRegistrySnapshot(
    did: testDid,
    devices: <DeviceSummary>[
      _device(
        id: 'admin-current',
        role: DeviceRole.admin,
        managementReady: true,
        isCurrent: true,
      ),
      _device(
        id: 'admin-new',
        role: DeviceRole.admin,
        managementReady: recipientReady,
      ),
    ],
  );
}

DeviceSummary _device({
  required String id,
  required DeviceRole role,
  DeviceStatus status = DeviceStatus.active,
  bool managementReady = false,
  bool isCurrent = false,
}) {
  return DeviceSummary(
    protocolDeviceId: id,
    signingKeyId: '$testDid#$id-sign',
    e2eeKeyId: '$testDid#$id-e2ee',
    status: status,
    role: role,
    managementReady: managementReady,
    isCurrent: isCurrent,
  );
}

DeviceRegistrySnapshot _revokeRegistry() => DeviceRegistrySnapshot(
  did: testDid,
  devices: <DeviceSummary>[
    _device(
      id: 'admin-current',
      role: DeviceRole.admin,
      managementReady: true,
      isCurrent: true,
    ),
    _device(id: 'member-target', role: DeviceRole.member),
  ],
);

DeviceRegistrySnapshot _revokedRegistry() => DeviceRegistrySnapshot(
  did: testDid,
  devices: <DeviceSummary>[
    _device(
      id: 'admin-current',
      role: DeviceRole.admin,
      managementReady: true,
      isCurrent: true,
    ),
    _device(
      id: 'member-target',
      role: DeviceRole.member,
      status: DeviceStatus.revoked,
    ),
  ],
);

Future<void> _enterUnknownRevoke(ProviderContainer container) async {
  await container
      .read(devicesProvider.notifier)
      .revokeDevice(
        target: _revokeTarget(container),
        presenceReason: 'Confirm focused revoke',
      );
  final state = container.read(devicesProvider);
  expect(state.revokeConfirmingDeviceId, 'member-target');
  expect(state.revokeRetryAllowedDeviceId, 'member-target');
}

DeviceSummary _revokeTarget(ProviderContainer container) => container
    .read(devicesProvider)
    .registry!
    .devices
    .singleWhere((device) => device.protocolDeviceId == 'member-target');
