import 'dart:async';

import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/ports/root_key_transfer_port.dart';
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
  String resolvedJoinDid = testDid;
  DeviceRegistrySnapshot registry = const DeviceRegistrySnapshot(did: testDid);
  List<DeviceJoinRequestNotice> joinRequests =
      const <DeviceJoinRequestNotice>[];
  List<DeviceJoinProgress> localSessions = const <DeviceJoinProgress>[];
  DeviceJoinProgress? beginResult;
  Object? beginError;
  DeviceJoinProgress? verificationProgress;
  DeviceJoinProgress? pollNewResult;
  DeviceJoinProgress? confirmResult;
  DeviceJoinProgress? rejectResult;
  DeviceJoinProgress? cancelResult;
  Object? registryError;
  Future<DeviceRegistrySnapshot> Function(String selector)? registryLoader;
  Future<List<DeviceJoinRequestNotice>> Function(String selector)?
  joinRequestsLoader;
  Future<DeviceJoinProgress> Function(String joinSessionId)? pollNewLoader;
  Object? pollError;
  Object? sendOtpError;
  Future<DeviceJoinSmsOtpSendReceipt> Function()? sendOtpLoader;
  DeviceJoinSmsOtpSendReceipt sendOtpReceipt =
      const DeviceJoinSmsOtpSendReceipt(retryAfterSeconds: 60);
  Object? revokeError;
  Future<DeviceRevokeResult> Function({
    required String selector,
    required String targetDeviceId,
    required bool userPresenceConfirmed,
  })?
  revokeLoader;
  int registryCalls = 0;
  int localSessionCalls = 0;
  int sendOtpCalls = 0;
  int beginCalls = 0;
  int joinRequestCalls = 0;
  int localVerificationCalls = 0;
  int startVerificationCalls = 0;
  int pollCalls = 0;
  int prepareCalls = 0;
  int confirmCalls = 0;
  int rejectCalls = 0;
  int cancelCalls = 0;
  int revokeCalls = 0;
  String? lastPhone;
  String? lastOtp;
  bool? lastPreparedSasConfirmed;
  DeviceJoinRejectReason? lastRejectReason;
  bool? lastPresenceConfirmed;
  String? lastRevokedDeviceId;
  bool? lastRevokePresenceConfirmed;

  @override
  Future<DeviceJoinSmsOtpSendReceipt> sendJoinSmsOtp({
    required String handle,
    required String phone,
  }) async {
    sendOtpCalls += 1;
    lastPhone = phone;
    final error = sendOtpError;
    if (error != null) {
      throw error;
    }
    final loader = sendOtpLoader;
    return loader == null ? sendOtpReceipt : loader();
  }

  @override
  Future<String> resolveJoinDid(String handle) async => resolvedJoinDid;

  @override
  Future<DeviceJoinProgress> beginDeviceJoinWithSms({
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    required int ttlSeconds,
  }) async {
    beginCalls += 1;
    lastPhone = phone;
    lastOtp = otp;
    final error = beginError;
    if (error != null) {
      throw error;
    }
    return beginResult ??
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.pending,
          remoteState: DeviceJoinRemoteState.pending,
          sas: null,
        );
  }

  @override
  Future<DeviceJoinProgress> cancelNewDeviceJoin(String joinSessionId) async =>
      _cancel();

  Future<DeviceJoinProgress> _cancel() async {
    cancelCalls += 1;
    return cancelResult ??
        testJoinProgress(
          side: DeviceJoinSide.newDevice,
          phase: DeviceJoinPhase.cancelled,
          remoteState: DeviceJoinRemoteState.cancelled,
          sas: null,
        );
  }

  @override
  Future<List<DeviceJoinRequestNotice>> localDeviceJoinRequests(
    String selector,
  ) async {
    joinRequestCalls += 1;
    final loader = joinRequestsLoader;
    return loader == null ? joinRequests : loader(selector);
  }

  @override
  Future<DeviceJoinProgress> localDeviceJoinVerificationProgress({
    required String selector,
    required String joinSessionId,
  }) async {
    localVerificationCalls += 1;
    return verificationProgress ?? testJoinProgress();
  }

  @override
  Future<DeviceJoinProgress> startDeviceJoinVerification({
    required String selector,
    required String joinSessionId,
    required String operationId,
    required int challengeTtlSeconds,
  }) async {
    startVerificationCalls += 1;
    return verificationProgress ??
        testJoinProgress(
          phase: DeviceJoinPhase.challengePrepared,
          remoteState: DeviceJoinRemoteState.challengeSent,
          sas: null,
        );
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
    final loader = registryLoader;
    if (loader != null) return loader(selector);
    return registry;
  }

  @override
  Future<List<DeviceJoinProgress>> localDeviceJoinSessions() async {
    localSessionCalls += 1;
    return localSessions;
  }

  @override
  Future<DeviceRevokeResult> revokeDevice({
    required String selector,
    required String targetDeviceId,
    required bool userPresenceConfirmed,
  }) async {
    revokeCalls += 1;
    lastRevokedDeviceId = targetDeviceId;
    lastRevokePresenceConfirmed = userPresenceConfirmed;
    final loader = revokeLoader;
    if (loader != null) {
      return loader(
        selector: selector,
        targetDeviceId: targetDeviceId,
        userPresenceConfirmed: userPresenceConfirmed,
      );
    }
    if (revokeError != null) throw revokeError!;
    registry = DeviceRegistrySnapshot(
      did: registry.did,
      devices: <DeviceSummary>[
        for (final device in registry.devices)
          if (device.protocolDeviceId == targetDeviceId)
            DeviceSummary(
              protocolDeviceId: device.protocolDeviceId,
              signingKeyId: device.signingKeyId,
              e2eeKeyId: device.e2eeKeyId,
              status: DeviceStatus.revoked,
              role: device.role,
              managementReady: false,
              isCurrent: device.isCurrent,
            )
          else
            device,
      ],
    );
    return DeviceRevokeResult(
      did: registry.did,
      targetDeviceId: targetDeviceId,
      status: DeviceRevokeStatus.revoked,
    );
  }

  @override
  Future<DeviceJoinProgress> pollNewDeviceJoin(String joinSessionId) async {
    pollCalls += 1;
    if (pollError != null) throw pollError!;
    final loader = pollNewLoader;
    if (loader != null) return loader(joinSessionId);
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
    required bool sasConfirmed,
  }) async {
    prepareCalls += 1;
    lastPreparedSasConfirmed = sasConfirmed;
    return DeviceJoinApprovalPrompt(
      approvalHandle: 'approval-1',
      joinSessionId: joinSessionId,
      sas: '482917',
      expiresAt: DateTime.utc(2030),
    );
  }

  @override
  Future<DeviceJoinProgress> rejectDeviceJoin({
    required String selector,
    required String joinSessionId,
    required DeviceJoinRejectReason reason,
  }) async {
    rejectCalls += 1;
    lastRejectReason = reason;
    return rejectResult ??
        testJoinProgress(
          phase: DeviceJoinPhase.cancelled,
          remoteState: DeviceJoinRemoteState.rejected,
          sas: null,
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

class FakeRootKeyTransferPort implements RootKeyTransferPort {
  Object? error;
  bool deferPrepare = false;
  int prepareCalls = 0;
  int confirmCalls = 0;
  String? lastRecipientDeviceId;
  bool? lastUserPresenceConfirmed;
  final prepareStarted = Completer<void>();
  Completer<RootKeyTransferPreparation>? _pendingPreparation;

  @override
  Future<RootKeyTransferPreparation> prepare({
    required String recipientDeviceId,
  }) async {
    prepareCalls += 1;
    lastRecipientDeviceId = recipientDeviceId;
    if (error != null) throw error!;
    if (deferPrepare) {
      _pendingPreparation = Completer<RootKeyTransferPreparation>();
      if (!prepareStarted.isCompleted) {
        prepareStarted.complete();
      }
      return _pendingPreparation!.future;
    }
    return _preparation(recipientDeviceId);
  }

  void completeDeferredPrepare() {
    final recipientDeviceId = lastRecipientDeviceId;
    final pending = _pendingPreparation;
    if (recipientDeviceId == null || pending == null) {
      throw StateError('no deferred root-transfer preparation');
    }
    pending.complete(_preparation(recipientDeviceId));
  }

  RootKeyTransferPreparation _preparation(String recipientDeviceId) {
    return RootKeyTransferPreparation(
      authorizationHandle: const FakeRootKeyTransferAuthorizationHandle(),
      recipient: RootKeyTransferRecipientSummary(
        did: testDid,
        deviceId: recipientDeviceId,
        signingKeyId: '$testDid#$recipientDeviceId-sign',
        e2eeKeyId: '$testDid#$recipientDeviceId-e2ee',
        registryVersion: 7,
      ),
      expiresAt: DateTime.utc(2030),
    );
  }

  @override
  Future<RootKeyTransferReceipt> confirmAndSend({
    required RootKeyTransferAuthorizationHandle authorizationHandle,
    required bool userPresenceConfirmed,
  }) async {
    confirmCalls += 1;
    lastUserPresenceConfirmed = userPresenceConfirmed;
    if (error != null) throw error!;
    return RootKeyTransferReceipt(
      did: testDid,
      senderDeviceId: 'admin-current',
      recipientDeviceId: lastRecipientDeviceId!,
      messageId: 'root-transfer-message-1',
      acceptedAt: DateTime.utc(2026, 7, 24),
    );
  }
}

class FakeRootKeyTransferAuthorizationHandle
    implements RootKeyTransferAuthorizationHandle {
  const FakeRootKeyTransferAuthorizationHandle();
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
