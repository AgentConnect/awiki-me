import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/models/group_collection_page.dart';
import 'package:awiki_me/src/application/ports/group_encryption_core_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/group_encryption_status.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
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
  test(
    'successful revoke immediately attempts each known group once',
    () async {
      final core = FakeDeviceManagementCore()..registry = _activeRegistry();
      final groups = _FakeGroups(<GroupSummary>[
        _group('group-a'),
        _group('group-b'),
      ]);
      final encryption = _FakeGroupEncryption();
      final sessions = FakeAppSessionService(
        FakeAwikiGateway()..loginResult = _session,
      );
      final container = _container(
        core,
        groups,
        encryption,
        sessions: sessions,
      );
      addTearDown(container.dispose);

      final controller = container.read(devicesProvider.notifier);
      await controller.loadManagement();
      final target = container
          .read(devicesProvider)
          .registry!
          .devices
          .singleWhere((device) => device.protocolDeviceId == 'member-target');

      expect(
        await controller.revokeDevice(
          target: target,
          presenceReason: 'Confirm focused revoke',
        ),
        isTrue,
      );
      await _drainMicrotasks();

      expect(sessions.deviceMutationRefreshCalls, 1);
      expect(encryption.repairCalls, <String>['group-a', 'group-b']);
      expect(
        container.read(devicesProvider).revokeNotice,
        DeviceRevokeNotice.revoked,
      );
    },
  );

  test(
    'one failed group does not block other groups or revoke success',
    () async {
      final core = FakeDeviceManagementCore()..registry = _activeRegistry();
      final groups = _FakeGroups(<GroupSummary>[
        _group('group-a'),
        _group('group-b'),
      ]);
      final encryption = _FakeGroupEncryption(failingGroupId: 'group-a');
      final container = _container(core, groups, encryption);
      addTearDown(container.dispose);

      final controller = container.read(devicesProvider.notifier);
      await controller.loadManagement();
      final target = container
          .read(devicesProvider)
          .registry!
          .devices
          .singleWhere((device) => device.protocolDeviceId == 'member-target');

      expect(
        await controller.revokeDevice(
          target: target,
          presenceReason: 'Confirm focused revoke',
        ),
        isTrue,
      );
      await _drainMicrotasks();

      expect(encryption.repairCalls, <String>['group-a', 'group-b']);
      expect(
        container.read(devicesProvider).revokeNotice,
        DeviceRevokeNotice.revokedGroupsRepairPartial,
      );
    },
  );
}

ProviderContainer _container(
  FakeDeviceManagementCore core,
  GroupApplicationService groups,
  GroupEncryptionCorePort encryption, {
  FakeAppSessionService? sessions,
}) => ProviderContainer(
  overrides: <Override>[
    multiDeviceDeviceRevokeEnabledProvider.overrideWithValue(true),
    deviceManagementCorePortProvider.overrideWithValue(core),
    userPresencePortProvider.overrideWithValue(FakeUserPresence()),
    groupApplicationServiceProvider.overrideWithValue(groups),
    groupEncryptionCorePortProvider.overrideWithValue(encryption),
    appSessionServiceProvider.overrideWithValue(
      sessions ??
          FakeAppSessionService(FakeAwikiGateway()..loginResult = _session),
    ),
    sessionProvider.overrideWith(
      (ref) => SessionController()..setSession(_session),
    ),
  ],
);

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

DeviceRegistrySnapshot _activeRegistry() => const DeviceRegistrySnapshot(
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
    DeviceSummary(
      protocolDeviceId: 'member-target',
      signingKeyId: '$testDid#member-sign',
      e2eeKeyId: '$testDid#member-e2ee',
      status: DeviceStatus.active,
      role: DeviceRole.member,
      managementReady: false,
      isCurrent: false,
    ),
  ],
);

GroupSummary _group(String groupId) => GroupSummary(
  conversationId: 'conversation-$groupId',
  groupId: groupId,
  displayName: groupId,
  description: '',
  memberCount: 2,
  lastMessageAt: null,
);

class _FakeGroups implements GroupApplicationService {
  _FakeGroups(this.groups);

  final List<GroupSummary> groups;

  @override
  Future<GroupCollectionPage<GroupSummary>> listGroups({
    int limit = 100,
    String? cursor,
  }) async => GroupCollectionPage<GroupSummary>(items: groups, hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected group application call.');
}

class _FakeGroupEncryption implements GroupEncryptionCorePort {
  _FakeGroupEncryption({this.failingGroupId});

  final String? failingGroupId;
  final List<String> repairCalls = <String>[];

  @override
  Future<GroupEncryptionStatus> retry(String groupDid) async {
    repairCalls.add(groupDid);
    if (groupDid == failingGroupId) {
      throw StateError('focused_repair_failure');
    }
    return GroupEncryptionStatus(
      groupDid: groupDid,
      readiness: GroupEncryptionReadiness.ready,
      canSendSecure: true,
      retryable: false,
    );
  }

  @override
  Future<GroupEncryptionStatus> status(String groupDid) => retry(groupDid);
}
