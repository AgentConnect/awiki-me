import 'dart:async';

import 'package:awiki_me/src/application/device_management_service.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('join SMS request stays on the device-management boundary', () async {
    final core = _FakeDeviceCore();

    await _service(core: core).sendJoinSmsOtp(' +8613800138000 ');

    expect(core.sentOtpPhone, '+8613800138000');
  });

  test(
    'SMS begin resolves Handle and never returns verification input',
    () async {
      final core = _FakeDeviceCore();
      final service = _service(core: core);

      final progress = await service.beginNewDeviceJoinWithSms(
        handle: ' Alice ',
        phone: '+8613800138000',
        otp: '123456',
        operationId: 'op-1',
      );

      expect(progress.joinSessionId, 'join-1');
      expect(core.beginDid, 'did:wba:awiki.info:user:alice:e1_test');
      expect(core.beginHandle, 'alice');
      expect(core.beginPhone, '+8613800138000');
      expect(core.beginOtp, '123456');
      expect(progress.toString(), isNot(contains('123456')));
    },
  );

  test(
    'approval binds displayed SAS and member role before presence',
    () async {
      final core = _FakeDeviceCore();
      final presence = _FakeUserPresence(result: true);
      final service = _service(core: core, presence: presence);
      final progress = _adminSasProgress();

      final result = await service.approve(
        selector: progress.did,
        progress: progress,
        displayedSas: '482917',
        role: DeviceRole.member,
        sasConfirmed: true,
        presenceReason: 'Confirm new device',
      );

      expect(result.phase, DeviceJoinPhase.authorized);
      expect(core.preparedRole, DeviceRole.member);
      expect(core.preparedSasConfirmed, isTrue);
      expect(core.confirmedHandle, 'approval-1');
      expect(core.confirmedPresence, isTrue);
      expect(presence.calls, 1);
    },
  );

  test('admin is granted only when explicitly supplied', () async {
    final core = _FakeDeviceCore();
    final service = _service(core: core);

    await service.approve(
      selector: 'did:wba:awiki.info:user:alice:e1_test',
      progress: _adminSasProgress(),
      displayedSas: '482917',
      role: DeviceRole.admin,
      sasConfirmed: true,
      presenceReason: 'Confirm new device',
    );

    expect(core.preparedRole, DeviceRole.admin);
  });

  test('SAS mismatch fails before preparing or prompting', () async {
    final core = _FakeDeviceCore();
    final presence = _FakeUserPresence(result: true);
    final service = _service(core: core, presence: presence);

    await expectLater(
      service.approve(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        progress: _adminSasProgress(),
        displayedSas: '000000',
        role: DeviceRole.member,
        sasConfirmed: true,
        presenceReason: 'Confirm new device',
      ),
      throwsA(
        isA<DeviceManagementException>().having(
          (error) => error.code,
          'code',
          'join_not_ready_for_approval',
        ),
      ),
    );
    expect(core.prepareCalls, 0);
    expect(presence.calls, 0);
  });

  test('revoke confirms user presence before calling Core', () async {
    final core = _FakeDeviceCore();
    final presence = _FakeUserPresence(result: true);
    final service = _service(core: core, presence: presence);

    final result = await service.revoke(
      selector: 'did:wba:awiki.info:user:alice:e1_test',
      targetDeviceId: 'device-member',
      presenceReason: 'Confirm revocation',
    );

    expect(presence.calls, 1);
    expect(core.revokeCalls, 1);
    expect(core.revokedTarget, 'device-member');
    expect(core.revokedPresence, isTrue);
    expect(result.status, DeviceRevokeStatus.revoked);
  });

  test('revoke presence denial never calls Core', () async {
    final core = _FakeDeviceCore();
    final presence = _FakeUserPresence(result: false);
    final service = _service(core: core, presence: presence);

    await expectLater(
      service.revoke(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        targetDeviceId: 'device-member',
        presenceReason: 'Confirm revocation',
      ),
      throwsA(
        isA<DeviceManagementException>().having(
          (error) => error.code,
          'code',
          'user_presence_denied',
        ),
      ),
    );
    expect(presence.calls, 1);
    expect(core.revokeCalls, 0);
  });

  test('presence denial consumes the one-time handle with false', () async {
    final core = _FakeDeviceCore();
    final presence = _FakeUserPresence(result: false);
    final service = _service(core: core, presence: presence);

    await expectLater(
      service.approve(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        progress: _adminSasProgress(),
        displayedSas: '482917',
        role: DeviceRole.member,
        sasConfirmed: true,
        presenceReason: 'Confirm new device',
      ),
      throwsA(
        isA<DeviceManagementException>().having(
          (error) => error.code,
          'code',
          'user_presence_denied',
        ),
      ),
    );
    expect(presence.calls, 1);
    expect(core.confirmedHandle, 'approval-1');
    expect(core.confirmedPresence, isFalse);
  });

  test('concurrent approval cannot prompt user presence twice', () async {
    final core = _FakeDeviceCore();
    final completer = Completer<bool>();
    final presence = _FakeUserPresence(completer: completer);
    final service = _service(core: core, presence: presence);
    final first = service.approve(
      selector: 'did:wba:awiki.info:user:alice:e1_test',
      progress: _adminSasProgress(),
      displayedSas: '482917',
      role: DeviceRole.member,
      sasConfirmed: true,
      presenceReason: 'Confirm new device',
    );
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      service.approve(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        progress: _adminSasProgress(),
        displayedSas: '482917',
        role: DeviceRole.member,
        sasConfirmed: true,
        presenceReason: 'Confirm new device',
      ),
      throwsA(
        isA<DeviceManagementException>().having(
          (error) => error.code,
          'code',
          'approval_already_in_progress',
        ),
      ),
    );
    expect(presence.calls, 1);
    completer.complete(true);
    await first;
  });

  test('malformed SAS from Core fails closed', () async {
    final core = _FakeDeviceCore()
      ..localSessions = <DeviceJoinProgress>[
        DeviceJoinProgress(
          joinSessionId: 'join-1',
          did: 'did:wba:awiki.info:user:alice:e1_test',
          protocolDeviceId: 'dev-new',
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.responsePrepared,
          remoteState: DeviceJoinRemoteState.responseVerified,
          expiresAt: DateTime.utc(2030),
          sas: '12345',
        ),
      ];

    await expectLater(
      _service(core: core).restoreLocalJoins(),
      throwsA(
        isA<DeviceManagementException>().having(
          (error) => error.code,
          'code',
          'invalid_sas_projection',
        ),
      ),
    );
  });
}

DeviceManagementService _service({
  required _FakeDeviceCore core,
  _FakeUserPresence? presence,
}) {
  return DeviceManagementService(
    core: core,
    directory: _FakeDirectory(),
    userPresence: presence ?? _FakeUserPresence(result: true),
  );
}

DeviceJoinProgress _adminSasProgress() => DeviceJoinProgress(
  joinSessionId: 'join-1',
  did: 'did:wba:awiki.info:user:alice:e1_test',
  protocolDeviceId: 'dev-new',
  side: DeviceJoinSide.admin,
  phase: DeviceJoinPhase.responseVerified,
  remoteState: DeviceJoinRemoteState.responseVerified,
  expiresAt: DateTime.utc(2030),
  sas: '482917',
);

class _FakeDirectory implements DirectoryApplicationService {
  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) async {
    return DirectoryPeerResolution(
      input: handle,
      did: 'did:wba:awiki.info:user:$handle:e1_test',
      handle: handle,
    );
  }

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async => const <PeerDisplayProfile>[];

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) =>
      lookupHandle(peer);
}

class _FakeUserPresence implements UserPresencePort {
  _FakeUserPresence({this.result, this.completer});

  final bool? result;
  final Completer<bool>? completer;
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    return completer?.future ?? result ?? false;
  }
}

class _FakeDeviceCore implements DeviceManagementCorePort {
  List<DeviceJoinProgress> localSessions = const <DeviceJoinProgress>[];
  String? beginDid;
  String? beginHandle;
  String? beginPhone;
  String? beginOtp;
  int prepareCalls = 0;
  DeviceRole? preparedRole;
  bool? preparedSasConfirmed;
  String? confirmedHandle;
  bool? confirmedPresence;
  String? sentOtpPhone;
  int revokeCalls = 0;
  String? revokedTarget;
  bool? revokedPresence;

  @override
  Future<void> sendJoinSmsOtp(String phone) async {
    sentOtpPhone = phone;
  }

  @override
  Future<DeviceJoinProgress> beginDeviceJoinWithSms({
    required String did,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    required int ttlSeconds,
  }) async {
    beginDid = did;
    beginHandle = handle;
    beginPhone = phone;
    beginOtp = otp;
    return DeviceJoinProgress(
      joinSessionId: 'join-1',
      did: did,
      protocolDeviceId: 'dev-new',
      side: DeviceJoinSide.newDevice,
      phase: DeviceJoinPhase.pending,
      remoteState: DeviceJoinRemoteState.pending,
      expiresAt: DateTime.utc(2030),
    );
  }

  @override
  Future<DeviceJoinProgress> cancelAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  }) async => _cancelled(DeviceJoinSide.admin);

  @override
  Future<DeviceJoinProgress> cancelNewDeviceJoin(String joinSessionId) async =>
      _cancelled(DeviceJoinSide.newDevice);

  @override
  Future<DeviceJoinProgress> claimDeviceJoin({
    required String selector,
    required String joinSessionId,
    required String operationId,
    required int challengeTtlSeconds,
  }) async => _adminSasProgress();

  @override
  Future<DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async {
    confirmedHandle = approvalHandle;
    confirmedPresence = userPresenceConfirmed;
    return DeviceJoinProgress(
      joinSessionId: 'join-1',
      did: 'did:wba:awiki.info:user:alice:e1_test',
      protocolDeviceId: 'dev-new',
      side: DeviceJoinSide.admin,
      phase: DeviceJoinPhase.authorized,
      remoteState: DeviceJoinRemoteState.consumed,
      expiresAt: DateTime.utc(2030),
      authorizedDevice: const DeviceSummary(
        protocolDeviceId: 'dev-new',
        signingKeyId: 'did:#sign',
        e2eeKeyId: 'did:#e2ee',
        status: DeviceStatus.active,
        role: DeviceRole.member,
        managementReady: false,
        isCurrent: false,
      ),
    );
  }

  @override
  Future<DeviceRegistrySnapshot> identityDeviceRegistry(
    String selector,
  ) async => DeviceRegistrySnapshot(did: selector);

  @override
  Future<List<DeviceJoinProgress>> localDeviceJoinSessions() async =>
      localSessions;

  @override
  Future<DeviceRevokeResult> revokeDevice({
    required String selector,
    required String targetDeviceId,
    required bool userPresenceConfirmed,
  }) async {
    revokeCalls += 1;
    revokedTarget = targetDeviceId;
    revokedPresence = userPresenceConfirmed;
    return DeviceRevokeResult(
      did: selector,
      targetDeviceId: targetDeviceId,
      status: DeviceRevokeStatus.revoked,
    );
  }

  @override
  Future<DeviceJoinProgress> pollAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  }) async => _adminSasProgress();

  @override
  Future<DeviceJoinProgress> pollNewDeviceJoin(String joinSessionId) async =>
      DeviceJoinProgress(
        joinSessionId: joinSessionId,
        did: 'did:wba:awiki.info:user:alice:e1_test',
        protocolDeviceId: 'dev-new',
        side: DeviceJoinSide.newDevice,
        phase: DeviceJoinPhase.responsePrepared,
        remoteState: DeviceJoinRemoteState.responseVerified,
        expiresAt: DateTime.utc(2030),
        sas: '482917',
      );

  @override
  Future<DeviceJoinApprovalPrompt> prepareDeviceJoinApproval({
    required String selector,
    required String joinSessionId,
    required DeviceRole role,
    required bool sasConfirmed,
  }) async {
    prepareCalls += 1;
    preparedRole = role;
    preparedSasConfirmed = sasConfirmed;
    return DeviceJoinApprovalPrompt(
      approvalHandle: 'approval-1',
      joinSessionId: joinSessionId,
      role: role,
      sas: '482917',
      expiresAt: DateTime.utc(2030),
    );
  }

  DeviceJoinProgress _cancelled(DeviceJoinSide side) => DeviceJoinProgress(
    joinSessionId: 'join-1',
    did: 'did:wba:awiki.info:user:alice:e1_test',
    protocolDeviceId: 'dev-new',
    side: side,
    phase: DeviceJoinPhase.cancelled,
    remoteState: DeviceJoinRemoteState.pending,
    expiresAt: DateTime.utc(2030),
  );
}
