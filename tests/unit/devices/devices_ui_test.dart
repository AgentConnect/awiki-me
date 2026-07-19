import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
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
  testWidgets('feature off keeps the legacy settings surface unchanged', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: _session,
        providerOverrides: <Override>[
          multiDeviceJoinEnabledProvider.overrideWithValue(false),
          deviceManagementCorePortProvider.overrideWithValue(core),
        ],
      ),
    );

    expect(find.text('设备'), findsNothing);
    expect(find.text('设备管理'), findsNothing);
    expect(core.registryCalls, 0);
  });

  testWidgets('feature on exposes device management from settings', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: _session,
        providerOverrides: <Override>[
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(core),
        ],
      ),
    );

    expect(find.text('设备'), findsOneWidget);
    await tester.tap(find.text('设备'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('devices-page')), findsOneWidget);
  });

  testWidgets('feature off keeps the legacy onboarding surface unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        providerOverrides: <Override>[
          multiDeviceJoinEnabledProvider.overrideWithValue(false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('将此设备加入已有账户'), findsNothing);
  });

  testWidgets('feature on exposes new-device Join from onboarding', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        providerOverrides: <Override>[
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
          deviceManagementCorePortProvider.overrideWithValue(core),
          directoryApplicationServiceProvider.overrideWithValue(
            FakeJoinDirectory(),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('将此设备加入已有账户'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device-join-page')), findsOneWidget);
  });

  testWidgets('feature on exposes new-device Join from macOS onboarding', (
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
          multiDeviceJoinEnabledProvider.overrideWithValue(true),
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

  testWidgets('device list distinguishes current/admin/member and pending', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..registry = DeviceRegistrySnapshot(
        did: testDid,
        devices: const <DeviceSummary>[
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
        pendingJoins: <PendingDeviceJoinSummary>[
          PendingDeviceJoinSummary(
            joinSessionId: 'join-1',
            protocolDeviceId: 'pc-new',
            signingKeyId: '$testDid#new-sign',
            e2eeKeyId: '$testDid#new-e2ee',
            requestedRole: DeviceRole.member,
            issuedAt: DateTime.utc(2026, 7, 19),
            expiresAt: DateTime.utc(2030),
          ),
        ],
      );

    await tester.pumpWidget(_app(const DevicesPage(), core));
    await tester.pumpAndSettle();

    expect(find.textContaining('phone-current · 当前设备'), findsOneWidget);
    expect(find.textContaining('管理设备 · 有效 · 可管理其他设备'), findsOneWidget);
    expect(find.textContaining('普通设备 · 有效'), findsOneWidget);
    expect(find.text('pc-new'), findsOneWidget);
  });

  testWidgets('approval defaults to member and prompts presence exactly once', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    final presence = FakeUserPresence();
    await tester.pumpWidget(
      _app(
        DeviceJoinApprovalSheet(pending: _pending(), autoPoll: false),
        core,
        presence: presence,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('482917'), findsOneWidget);
    final switches = find.byType(CupertinoSwitch);
    expect(switches, findsNWidgets(2));
    expect(tester.widget<CupertinoSwitch>(switches.at(1)).value, isFalse);
    expect(find.textContaining('二维码'), findsNothing);
    expect(find.textContaining('扫码'), findsNothing);

    await tester.tap(switches.first);
    await tester.pump();
    await tester.tap(find.text('确认并授权'));
    await tester.pumpAndSettle();

    expect(core.lastPreparedRole, DeviceRole.member);
    expect(core.lastPreparedSasConfirmed, isTrue);
    expect(core.lastPresenceConfirmed, isTrue);
    expect(presence.calls, 1);
    expect(find.text('设备已加入'), findsOneWidget);
  });

  testWidgets('admin role requires an explicit second switch', (tester) async {
    final core = FakeDeviceManagementCore();
    await tester.pumpWidget(
      _app(DeviceJoinApprovalSheet(pending: _pending(), autoPoll: false), core),
    );
    await tester.pumpAndSettle();

    final switches = find.byType(CupertinoSwitch);
    await tester.tap(switches.first);
    await tester.tap(switches.at(1));
    await tester.pump();
    await tester.tap(find.text('确认并授权'));
    await tester.pumpAndSettle();

    expect(core.lastPreparedRole, DeviceRole.admin);
  });

  testWidgets('user-presence rejection never authorizes the device', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore();
    final presence = FakeUserPresence(result: false);
    await tester.pumpWidget(
      _app(
        DeviceJoinApprovalSheet(pending: _pending(), autoPoll: false),
        core,
        presence: presence,
      ),
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
          remoteState: DeviceJoinRemoteState.notObserved,
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
    await tester.enterText(fields.at(1), '+8613800138000');
    await tester.tap(find.text('发送验证码'));
    await tester.pumpAndSettle();

    expect(core.sendOtpCalls, 1);
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

  testWidgets('admin restart projection exposes unfinished join', (
    tester,
  ) async {
    final core = FakeDeviceManagementCore()
      ..localSessions = <DeviceJoinProgress>[
        testJoinProgress(
          phase: DeviceJoinPhase.challengePrepared,
          remoteState: DeviceJoinRemoteState.challengeSent,
        ),
      ];
    await tester.pumpWidget(_app(const DevicesPage(), core));
    await tester.pumpAndSettle();

    expect(find.text('未完成的设备关联'), findsOneWidget);
    expect(find.text('device-new'), findsOneWidget);
    expect(find.text('继续'), findsOneWidget);
  });
}

PendingDeviceJoinSummary _pending() => PendingDeviceJoinSummary(
  joinSessionId: 'join-1',
  protocolDeviceId: 'device-new',
  signingKeyId: '$testDid#new-sign',
  e2eeKeyId: '$testDid#new-e2ee',
  requestedRole: DeviceRole.member,
  issuedAt: DateTime.utc(2026, 7, 19),
  expiresAt: DateTime.utc(2030),
);

Widget _app(
  Widget home,
  FakeDeviceManagementCore core, {
  FakeUserPresence? presence,
  SessionIdentity? session = _session,
}) {
  return buildLocalizedTestApp(
    home: home,
    session: session,
    providerOverrides: <Override>[
      multiDeviceJoinEnabledProvider.overrideWithValue(true),
      deviceManagementCorePortProvider.overrideWithValue(core),
      directoryApplicationServiceProvider.overrideWithValue(
        FakeJoinDirectory(),
      ),
      userPresencePortProvider.overrideWithValue(
        presence ?? FakeUserPresence(),
      ),
    ],
  );
}
