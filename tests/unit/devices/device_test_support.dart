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
  Object? revokeError;
  int registryCalls = 0;
  int localSessionCalls = 0;
  int sendOtpCalls = 0;
  int beginCalls = 0;
  int claimCalls = 0;
  int pollCalls = 0;
  int prepareCalls = 0;
  int confirmCalls = 0;
  int cancelCalls = 0;
  int revokeCalls = 0;
  String? lastOtp;
  DeviceRole? lastPreparedRole;
  bool? lastPreparedSasConfirmed;
  bool? lastPresenceConfirmed;
  String? lastRevokedDeviceId;
  bool? lastRevokePresenceConfirmed;

  @override
  Future<void> sendJoinSmsOtp(String phone) async {
    sendOtpCalls += 1;
  }

  @override
  Future<DeviceJoinProgress> beginDeviceJoinWithSms({
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
      pendingJoins: registry.pendingJoins,
    );
    return DeviceRevokeResult(
      did: registry.did,
      targetDeviceId: targetDeviceId,
      status: DeviceRevokeStatus.revoked,
    );
  }

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

class FakeRootKeyTransferPort implements RootKeyTransferPort {
  Object? error;
  List<RootKeyTransferSummary> summaries = <RootKeyTransferSummary>[];
  int calls = 0;
  int listCalls = 0;
  int retryCalls = 0;
  String? lastSelector;
  String? lastRecipientDeviceId;
  String? lastMessageId;
  bool? lastUserPresenceConfirmed;

  @override
  Future<List<RootKeyTransferSummary>> listRootKeyTransfers({
    required String selector,
    required bool includeCompleted,
  }) async {
    listCalls += 1;
    lastSelector = selector;
    return summaries
        .where(
          (summary) =>
              includeCompleted ||
              summary.status != RootKeyTransferStatus.completed,
        )
        .toList(growable: false);
  }

  @override
  Future<RootKeyTransferReceipt> sendRootKeyTransfer({
    required String selector,
    required String recipientDeviceId,
    required String messageId,
    required bool userPresenceConfirmed,
  }) async {
    calls += 1;
    lastSelector = selector;
    lastRecipientDeviceId = recipientDeviceId;
    lastMessageId = messageId;
    lastUserPresenceConfirmed = userPresenceConfirmed;
    if (!_isSessionEstablishmentPending(error)) {
      _replaceSummary(
        rootTransferSummary(
          messageId: messageId,
          recipientDeviceId: recipientDeviceId,
          status: error == null
              ? RootKeyTransferStatus.pendingDelivery
              : RootKeyTransferStatus.failed,
          retryable: error != null,
        ),
      );
    }
    if (error != null) throw error!;
    return RootKeyTransferReceipt(
      did: selector,
      senderDeviceId: 'admin-current',
      recipientDeviceId: recipientDeviceId,
      messageId: messageId,
      acceptedAt: DateTime.utc(2026, 7, 20),
    );
  }

  @override
  Future<RootKeyTransferSummary> retryRootKeyTransfer({
    required String selector,
    required String messageId,
    required bool userPresenceConfirmed,
  }) async {
    retryCalls += 1;
    lastSelector = selector;
    lastMessageId = messageId;
    lastUserPresenceConfirmed = userPresenceConfirmed;
    final existing = summaries.firstWhere(
      (summary) => summary.messageId == messageId,
    );
    final next = RootKeyTransferSummary(
      did: existing.did,
      senderDeviceId: existing.senderDeviceId,
      recipientDeviceId: existing.recipientDeviceId,
      messageId: existing.messageId,
      status: error == null
          ? RootKeyTransferStatus.importing
          : RootKeyTransferStatus.failed,
      createdAt: existing.createdAt,
      acceptedAt: existing.acceptedAt,
      completedAt: existing.completedAt,
      retryable: error != null,
    );
    _replaceSummary(next);
    if (error != null) throw error!;
    return next;
  }

  void _replaceSummary(RootKeyTransferSummary replacement) {
    summaries = <RootKeyTransferSummary>[
      for (final summary in summaries)
        if (summary.messageId != replacement.messageId) summary,
      replacement,
    ];
  }
}

bool _isSessionEstablishmentPending(Object? error) =>
    error is RootKeyTransferPortException &&
    error.capability == rootKeyTransferSessionEstablishmentPendingCapability;

RootKeyTransferSummary rootTransferSummary({
  String messageId = 'root-message-1',
  String senderDeviceId = 'admin-current',
  String recipientDeviceId = 'admin-new',
  RootKeyTransferStatus status = RootKeyTransferStatus.failed,
  bool retryable = true,
}) {
  return RootKeyTransferSummary(
    did: testDid,
    senderDeviceId: senderDeviceId,
    recipientDeviceId: recipientDeviceId,
    messageId: messageId,
    status: status,
    createdAt: DateTime.utc(2026, 7, 20),
    acceptedAt: DateTime.utc(2026, 7, 20, 0, 1),
    completedAt: status == RootKeyTransferStatus.completed
        ? DateTime.utc(2026, 7, 20, 0, 2)
        : null,
    retryable: retryable,
  );
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
