import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';

const testDid = 'did:wba:awiki.info:user:alice:e1_test';

DeviceJoinProgress testJoinProgress({
  DeviceJoinSide side = DeviceJoinSide.admin,
  DeviceJoinPhase phase = DeviceJoinPhase.responseVerified,
  DeviceJoinRemoteState remoteState = DeviceJoinRemoteState.responseVerified,
  String? sas = '482917',
}) {
  return DeviceJoinProgress(
    joinSessionId: 'join-1',
    did: testDid,
    protocolDeviceId: 'device-new',
    side: side,
    phase: phase,
    remoteState: remoteState,
    expiresAt: DateTime.utc(2030),
    sas: sas,
  );
}

class FakeDeviceManagementCore implements DeviceManagementCorePort {
  DeviceRegistrySnapshot registry = const DeviceRegistrySnapshot(did: testDid);
  List<DeviceJoinProgress> localSessions = const <DeviceJoinProgress>[];
  DeviceJoinProgress? beginResult;
  DeviceJoinProgress? claimResult;
  DeviceJoinProgress? pollAdminResult;
  DeviceJoinProgress? pollNewResult;
  DeviceJoinProgress? confirmResult;
  DeviceJoinProgress? cancelResult;
  Object? registryError;
  Object? pollError;
  int registryCalls = 0;
  int sendOtpCalls = 0;
  int beginCalls = 0;
  int claimCalls = 0;
  int pollCalls = 0;
  int prepareCalls = 0;
  int confirmCalls = 0;
  int cancelCalls = 0;
  String? lastOtp;
  DeviceRole? lastPreparedRole;
  bool? lastPreparedSasConfirmed;
  bool? lastPresenceConfirmed;

  @override
  Future<void> sendJoinSmsOtp(String phone) async {
    sendOtpCalls += 1;
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
    beginCalls += 1;
    lastOtp = otp;
    return beginResult ??
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.pending,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        );
  }

  @override
  Future<DeviceJoinProgress> cancelAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  }) async => _cancel(DeviceJoinSide.admin);

  @override
  Future<DeviceJoinProgress> cancelNewDeviceJoin(String joinSessionId) async =>
      _cancel(DeviceJoinSide.newDevice);

  Future<DeviceJoinProgress> _cancel(DeviceJoinSide side) async {
    cancelCalls += 1;
    return cancelResult ??
        testJoinProgress(
          side: side,
          phase: DeviceJoinPhase.cancelled,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        );
  }

  @override
  Future<DeviceJoinProgress> claimDeviceJoin({
    required String selector,
    required String joinSessionId,
    required String operationId,
    required int challengeTtlSeconds,
  }) async {
    claimCalls += 1;
    return claimResult ?? testJoinProgress();
  }

  @override
  Future<DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async {
    confirmCalls += 1;
    lastPresenceConfirmed = userPresenceConfirmed;
    return confirmResult ??
        testJoinProgress(
          phase: DeviceJoinPhase.authorized,
          remoteState: DeviceJoinRemoteState.consumed,
          sas: null,
        );
  }

  @override
  Future<DeviceRegistrySnapshot> identityDeviceRegistry(String selector) async {
    registryCalls += 1;
    if (registryError != null) throw registryError!;
    return registry;
  }

  @override
  Future<List<DeviceJoinProgress>> localDeviceJoinSessions() async =>
      localSessions;

  @override
  Future<DeviceJoinProgress> pollAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  }) async {
    pollCalls += 1;
    if (pollError != null) throw pollError!;
    return pollAdminResult ?? testJoinProgress();
  }

  @override
  Future<DeviceJoinProgress> pollNewDeviceJoin(String joinSessionId) async {
    pollCalls += 1;
    if (pollError != null) throw pollError!;
    return pollNewResult ??
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.responsePrepared,
        );
  }

  @override
  Future<DeviceJoinApprovalPrompt> prepareDeviceJoinApproval({
    required String selector,
    required String joinSessionId,
    required DeviceRole role,
    required bool sasConfirmed,
  }) async {
    prepareCalls += 1;
    lastPreparedRole = role;
    lastPreparedSasConfirmed = sasConfirmed;
    return DeviceJoinApprovalPrompt(
      approvalHandle: 'approval-1',
      joinSessionId: joinSessionId,
      role: role,
      sas: '482917',
      expiresAt: DateTime.utc(2030),
    );
  }
}

class FakeUserPresence implements UserPresencePort {
  FakeUserPresence({this.result = true});

  bool result;
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    return result;
  }
}

class FakeJoinDirectory implements DirectoryApplicationService {
  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) async {
    return DirectoryPeerResolution(input: handle, did: testDid, handle: handle);
  }

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async => const <PeerDisplayProfile>[];

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) =>
      lookupHandle(peer);
}
