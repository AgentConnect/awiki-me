// [INPUT]: Session identity, Device Registry/Join/revoke services, root-transfer service, and UI intents.
// [OUTPUT]: Secret-free device list, Join, revoke, and admin-readiness presentation state.
// [POS]: Riverpod controller for device management; Registry remains the durable readiness truth.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/device_management_service.dart';
import '../../application/ports/root_key_transfer_port.dart';
import '../../application/root_key_transfer_service.dart';
import '../../domain/entities/device_management.dart';
import '../app_shell/providers/session_provider.dart';

enum DeviceManagementErrorKind {
  unavailable,
  expired,
  conflict,
  sasMismatch,
  userPresenceDenied,
  protectedDevice,
  network,
  failed,
}

class DevicesState {
  const DevicesState({
    this.registry,
    this.joinRequests = const <DeviceJoinRequestNotice>[],
    this.localJoins = const <DeviceJoinProgress>[],
    this.activeJoin,
    this.isLoading = false,
    this.isActionPending = false,
    this.rootTransfer = const RootKeyTransferUiState(),
    this.error,
  });

  final DeviceRegistrySnapshot? registry;
  final List<DeviceJoinRequestNotice> joinRequests;
  final List<DeviceJoinProgress> localJoins;
  final DeviceJoinProgress? activeJoin;
  final bool isLoading;
  final bool isActionPending;
  final RootKeyTransferUiState rootTransfer;
  final DeviceManagementErrorKind? error;

  List<DeviceJoinRequestNotice> get visibleJoinRequests => joinRequests
      .where((request) => !request.isTerminal)
      .toList(growable: false);

  bool get currentDeviceCanManage =>
      registry?.currentDevice?.canManageDevices == true;

  DeviceManagementReadiness? readinessFor(DeviceSummary device) {
    if (device.role != DeviceRole.admin ||
        device.status != DeviceStatus.active) {
      return null;
    }
    if (device.managementReady) {
      return DeviceManagementReadiness.ready;
    }
    return DeviceManagementReadiness.adminAwaitingRoot;
  }

  bool canRevokeDevice(DeviceSummary device) =>
      currentDeviceCanManage &&
      !device.isCurrent &&
      device.status == DeviceStatus.active;

  DevicesState copyWith({
    DeviceRegistrySnapshot? registry,
    List<DeviceJoinRequestNotice>? joinRequests,
    List<DeviceJoinProgress>? localJoins,
    DeviceJoinProgress? activeJoin,
    bool clearActiveJoin = false,
    bool? isLoading,
    bool? isActionPending,
    RootKeyTransferUiState? rootTransfer,
    bool clearRootTransfer = false,
    DeviceManagementErrorKind? error,
    bool clearError = false,
  }) {
    return DevicesState(
      registry: registry ?? this.registry,
      joinRequests: joinRequests ?? this.joinRequests,
      localJoins: localJoins ?? this.localJoins,
      activeJoin: clearActiveJoin ? null : (activeJoin ?? this.activeJoin),
      isLoading: isLoading ?? this.isLoading,
      isActionPending: isActionPending ?? this.isActionPending,
      rootTransfer: clearRootTransfer
          ? const RootKeyTransferUiState()
          : (rootTransfer ?? this.rootTransfer),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this.ref) : super(const DevicesState());

  final Ref ref;
  int _generation = 0;
  String? _selectedAdminJoinSessionId;

  bool get _deviceRevokeEnabled =>
      ref.read(multiDeviceDeviceRevokeEnabledProvider);

  String? get _selector {
    final did = ref.read(sessionProvider).session?.did.trim();
    return did == null || did.isEmpty ? null : did;
  }

  Future<void> loadManagement() async {
    final selector = _selector;
    if (selector == null) {
      state = state.copyWith(error: DeviceManagementErrorKind.unavailable);
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = ref.read(deviceManagementServiceProvider);
      final registry = await service.loadRegistry(selector);
      final results = await Future.wait<Object>(<Future<Object>>[
        service.restoreLocalJoins(),
        if (registry.currentDevice?.canManageDevices == true)
          service.restoreAdminJoinRequests(selector),
      ]);
      if (!mounted || generation != _generation) return;
      var resultIndex = 0;
      final localJoins = (results[resultIndex++] as List<DeviceJoinProgress>)
          .where((session) => session.side == DeviceJoinSide.newDevice)
          .toList(growable: false);
      final joinRequests = registry.currentDevice?.canManageDevices == true
          ? results[resultIndex++] as List<DeviceJoinRequestNotice>
          : const <DeviceJoinRequestNotice>[];
      state = DevicesState(
        registry: registry,
        joinRequests: joinRequests,
        localJoins: localJoins,
        activeJoin: state.activeJoin,
        rootTransfer: state.rootTransfer,
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        error: _classifyDeviceError(error),
      );
    }
  }

  Future<void> refreshJoinInbox() async {
    final selector = _selector;
    final registry = state.registry;
    if (selector == null) {
      return;
    }
    if (registry == null) {
      await loadManagement();
      return;
    }
    if (registry.currentDevice?.canManageDevices != true) {
      if (state.joinRequests.isNotEmpty) {
        state = state.copyWith(joinRequests: const <DeviceJoinRequestNotice>[]);
      }
      return;
    }
    try {
      final service = ref.read(deviceManagementServiceProvider);
      final requests = await service.restoreAdminJoinRequests(selector);
      if (!mounted) return;
      var activeJoin = state.activeJoin;
      var clearActiveJoin = false;
      final selectedJoinSessionId = activeJoin?.side == DeviceJoinSide.admin
          ? activeJoin!.joinSessionId
          : _selectedAdminJoinSessionId;
      if (selectedJoinSessionId != null) {
        final request = _findJoinRequest(requests, selectedJoinSessionId);
        if (request == null || request.isTerminal) {
          if (activeJoin?.side == DeviceJoinSide.admin &&
              activeJoin?.joinSessionId == selectedJoinSessionId) {
            activeJoin = null;
            clearActiveJoin = true;
          }
          if (_selectedAdminJoinSessionId == selectedJoinSessionId) {
            _selectedAdminJoinSessionId = null;
          }
        } else if (activeJoin?.isTerminal != true &&
            request.claimedByCurrentDevice &&
            request.state == DeviceJoinRemoteState.responseVerified) {
          activeJoin = await service.restoreAdminVerificationProgress(
            selector: selector,
            joinSessionId: request.joinSessionId,
          );
          if (!mounted) return;
        }
      }
      state = state.copyWith(
        joinRequests: requests,
        activeJoin: activeJoin,
        clearActiveJoin: clearActiveJoin,
        clearError: true,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(error: _classifyDeviceError(error));
    }
  }

  Future<void> loadNewDevice() async {
    final existing = state.activeJoin;
    if (existing != null && !existing.isTerminal) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final sessions = await ref
          .read(deviceManagementServiceProvider)
          .restoreLocalJoins();
      if (!mounted || generation != _generation) return;
      final resumable = sessions
          .where(
            (session) =>
                session.side == DeviceJoinSide.newDevice && !session.isTerminal,
          )
          .toList();
      final authorized = sessions
          .where(
            (session) =>
                session.side == DeviceJoinSide.newDevice &&
                session.phase == DeviceJoinPhase.authorized,
          )
          .toList();
      state = DevicesState(
        localJoins: sessions
            .where((session) => session.side == DeviceJoinSide.newDevice)
            .toList(growable: false),
        activeJoin: resumable.isNotEmpty
            ? resumable.last
            : authorized.isEmpty
            ? null
            : authorized.last,
      );
      if (resumable.isNotEmpty) {
        await pollNewDeviceActive();
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        error: _classifyDeviceError(error),
      );
    }
  }

  Future<bool> beginNewDeviceJoin({
    required String handle,
    required String phone,
    required String otp,
  }) async {
    if (state.isActionPending) return false;
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final progress = await ref
          .read(deviceManagementServiceProvider)
          .beginNewDeviceJoinWithSms(
            handle: handle,
            phone: phone,
            otp: otp,
            operationId: _newOperationId('join'),
          );
      if (!mounted) return false;
      state = state.copyWith(
        activeJoin: progress,
        localJoins: _replaceJoin(state.localJoins, progress),
        isActionPending: false,
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
      return false;
    }
  }

  Future<void> selectJoinRequest(DeviceJoinRequestNotice request) async {
    final selector = _selector;
    final stalePreparation = state.rootTransfer.preparation;
    _selectedAdminJoinSessionId = request.isTerminal
        ? null
        : request.joinSessionId;
    state = state.copyWith(
      clearActiveJoin: true,
      clearRootTransfer: true,
      clearError: true,
    );
    if (stalePreparation != null) {
      await ref.read(rootKeyTransferServiceProvider).discard(stalePreparation);
      if (!mounted) return;
    }
    if (selector == null ||
        request.isTerminal ||
        !request.claimedByCurrentDevice ||
        request.state != DeviceJoinRemoteState.responseVerified) {
      return;
    }
    try {
      final progress = await ref
          .read(deviceManagementServiceProvider)
          .restoreAdminVerificationProgress(
            selector: selector,
            joinSessionId: request.joinSessionId,
          );
      if (!mounted) return;
      state = state.copyWith(activeJoin: progress);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(error: _classifyDeviceError(error));
    }
  }

  Future<bool> startVerification(DeviceJoinRequestNotice request) async {
    final selector = _selector;
    if (selector == null ||
        state.isActionPending ||
        request.isTerminal ||
        request.claimedByOther ||
        !request.canStartVerification) {
      return false;
    }
    _selectedAdminJoinSessionId = request.joinSessionId;
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final progress = await ref
          .read(deviceManagementServiceProvider)
          .startVerification(
            selector: selector,
            joinSessionId: request.joinSessionId,
            operationId: 'awiki-me-verify-${request.joinSessionId}',
          );
      if (!mounted) return false;
      state = state.copyWith(activeJoin: progress, isActionPending: false);
      await refreshJoinInbox();
      return true;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
      return false;
    }
  }

  void resumeNewDevice(DeviceJoinProgress progress) {
    if (progress.side != DeviceJoinSide.newDevice) {
      throw StateError('invalid_new_device_join_progress');
    }
    state = state.copyWith(
      activeJoin: progress,
      localJoins: _replaceJoin(state.localJoins, progress),
      clearError: true,
    );
  }

  Future<void> pollNewDeviceActive() async {
    final progress = state.activeJoin;
    final requiresAuthorizedHydration =
        progress?.phase == DeviceJoinPhase.authorized &&
        progress?.authorizedDevice == null;
    if (progress == null ||
        progress.side != DeviceJoinSide.newDevice ||
        (progress.isTerminal && !requiresAuthorizedHydration) ||
        state.isActionPending) {
      return;
    }
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final next = await ref
          .read(deviceManagementServiceProvider)
          .pollNewDeviceJoin(progress: progress);
      if (!mounted) return;
      state = state.copyWith(
        activeJoin: next,
        localJoins: _replaceJoin(state.localJoins, next),
        isActionPending: false,
      );
      if (next.phase == DeviceJoinPhase.authorized && _selector != null) {
        await loadManagement();
      }
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
    }
  }

  Future<bool> approveActiveAsMember({
    required bool sasConfirmed,
    required String presenceReason,
  }) async {
    final selector = _selector;
    final progress = state.activeJoin;
    if (selector == null || progress?.sas == null || state.isActionPending) {
      return false;
    }
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final next = await ref
          .read(deviceManagementServiceProvider)
          .approveAsMember(
            selector: selector,
            progress: progress!,
            displayedSas: progress.sas!,
            sasConfirmed: sasConfirmed,
            presenceReason: presenceReason,
          );
      if (!mounted) return false;
      state = state.copyWith(activeJoin: next, isActionPending: false);
      await loadManagement();
      return true;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
      return false;
    }
  }

  Future<bool> rejectJoin({
    required DeviceJoinRequestNotice request,
    required DeviceJoinRejectReason reason,
  }) async {
    final selector = _selector;
    if (selector == null || state.isActionPending || request.isTerminal) {
      return false;
    }
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      await ref
          .read(deviceManagementServiceProvider)
          .rejectJoin(
            selector: selector,
            joinSessionId: request.joinSessionId,
            reason: reason,
          );
      if (!mounted) return false;
      state = state.copyWith(clearActiveJoin: true, isActionPending: false);
      await refreshJoinInbox();
      return true;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
      return false;
    }
  }

  Future<bool> prepareRootTransferForActiveJoin() async {
    final target = _activeRootTransferTarget();
    if (target == null) {
      return false;
    }
    if (state.rootTransfer.phase != RootKeyTransferPhase.idle) {
      if (state.rootTransfer.context == target.context) {
        return false;
      }
      state = state.copyWith(clearRootTransfer: true);
    }
    final context = target.context;
    state = state.copyWith(
      rootTransfer: RootKeyTransferUiState(
        phase: RootKeyTransferPhase.preparing,
        context: context,
      ),
      clearError: true,
    );
    try {
      final service = ref.read(rootKeyTransferServiceProvider);
      final preparation = await service.prepare(
        expectedDid: context.did,
        recipient: target.recipient,
      );
      if (!mounted) {
        await service.discard(preparation);
        return false;
      }
      if (state.rootTransfer.phase != RootKeyTransferPhase.preparing ||
          state.rootTransfer.context != context ||
          !_isActiveRootTransferContext(context)) {
        await service.discard(preparation);
        _failRootTransferIfCurrent(
          context,
          code: 'root_transfer.state_changed',
          retryable: true,
        );
        return false;
      }
      state = state.copyWith(
        rootTransfer: RootKeyTransferUiState(
          phase: RootKeyTransferPhase.awaitingConfirmation,
          context: context,
          preparation: preparation,
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      final failure = _rootTransferFailure(error);
      _failRootTransferIfCurrent(
        context,
        code: failure.code,
        retryable: failure.retryable,
      );
      return false;
    }
  }

  Future<bool> confirmAndSendRootTransfer({
    required String presenceReason,
  }) async {
    final transfer = state.rootTransfer;
    final context = transfer.context;
    final preparation = state.rootTransfer.preparation;
    final sender = state.registry?.currentDevice;
    if (context == null ||
        transfer.phase != RootKeyTransferPhase.awaitingConfirmation ||
        preparation == null ||
        sender == null) {
      return false;
    }
    if (!_isActiveRootTransferContext(context)) {
      await ref.read(rootKeyTransferServiceProvider).discard(preparation);
      _failRootTransferIfCurrent(
        context,
        code: 'root_transfer.state_changed',
        retryable: true,
      );
      return false;
    }
    state = state.copyWith(
      rootTransfer: RootKeyTransferUiState(
        phase: RootKeyTransferPhase.sending,
        context: context,
        preparation: preparation,
      ),
      clearError: true,
    );
    try {
      final receipt = await ref
          .read(rootKeyTransferServiceProvider)
          .confirmAndSend(
            expectedDid: context.did,
            sender: sender,
            preparation: preparation,
            presenceReason: presenceReason,
            contextStillValid: () =>
                mounted && _isActiveRootTransferContext(context),
          );
      if (!mounted) return false;
      if (state.rootTransfer.phase != RootKeyTransferPhase.sending ||
          state.rootTransfer.context != context ||
          !_isActiveRootTransferContext(context)) {
        return true;
      }
      state = state.copyWith(
        rootTransfer: RootKeyTransferUiState(
          phase: RootKeyTransferPhase.sent,
          context: context,
          preparation: preparation,
          receipt: receipt,
        ),
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      final failure = _rootTransferFailure(error);
      _failRootTransferIfCurrent(
        context,
        code: failure.code,
        retryable: failure.retryable,
      );
      return false;
    }
  }

  ({RootKeyTransferContext context, DeviceSummary recipient})?
  _activeRootTransferTarget() {
    final selector = _selector;
    final registry = state.registry;
    final progress = state.activeJoin;
    final recipient = progress?.authorizedDevice;
    final sender = registry?.currentDevice;
    final authoritativeRecipient = recipient == null
        ? null
        : _findDevice(registry, recipient.protocolDeviceId);
    if (selector == null ||
        registry == null ||
        registry.did != selector ||
        progress?.did != selector ||
        progress?.side != DeviceJoinSide.admin ||
        progress?.phase != DeviceJoinPhase.authorized ||
        recipient == null ||
        sender?.canManageDevices != true ||
        authoritativeRecipient == null ||
        sender!.protocolDeviceId == authoritativeRecipient.protocolDeviceId ||
        authoritativeRecipient.protocolDeviceId != progress!.protocolDeviceId ||
        authoritativeRecipient.signingKeyId != recipient.signingKeyId ||
        authoritativeRecipient.e2eeKeyId != recipient.e2eeKeyId ||
        authoritativeRecipient.status != recipient.status ||
        authoritativeRecipient.role != recipient.role ||
        authoritativeRecipient.managementReady != recipient.managementReady ||
        authoritativeRecipient.isCurrent != recipient.isCurrent) {
      return null;
    }
    return (
      context: RootKeyTransferContext(
        joinSessionId: progress.joinSessionId,
        did: selector,
        recipientDeviceId: authoritativeRecipient.protocolDeviceId,
        recipientSigningKeyId: authoritativeRecipient.signingKeyId,
        recipientE2eeKeyId: authoritativeRecipient.e2eeKeyId,
      ),
      recipient: authoritativeRecipient,
    );
  }

  bool _isActiveRootTransferContext(RootKeyTransferContext context) =>
      _activeRootTransferTarget()?.context == context;

  void _failRootTransferIfCurrent(
    RootKeyTransferContext context, {
    required String code,
    required bool retryable,
  }) {
    if (!mounted || state.rootTransfer.context != context) {
      return;
    }
    state = state.copyWith(
      rootTransfer: RootKeyTransferUiState(
        phase: RootKeyTransferPhase.failed,
        context: context,
        errorCode: code,
        retryable: retryable,
      ),
    );
  }

  Future<bool> revokeDevice({
    required DeviceSummary target,
    required String presenceReason,
  }) async {
    final selector = _selector;
    final authoritativeTarget = _findDevice(
      state.registry,
      target.protocolDeviceId,
    );
    if (!_deviceRevokeEnabled ||
        selector == null ||
        state.isActionPending ||
        authoritativeTarget == null ||
        !state.canRevokeDevice(authoritativeTarget)) {
      return false;
    }

    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      await ref
          .read(deviceManagementServiceProvider)
          .revoke(
            selector: selector,
            targetDeviceId: authoritativeTarget.protocolDeviceId,
            presenceReason: presenceReason,
          );
      if (!mounted) return false;
      await loadManagement();
      return true;
    } catch (error) {
      if (!mounted) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
      return false;
    }
  }

  Future<void> cancelNewDeviceActive() async {
    final progress = state.activeJoin;
    if (progress == null ||
        progress.side != DeviceJoinSide.newDevice ||
        state.isActionPending) {
      return;
    }
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final next = await ref
          .read(deviceManagementServiceProvider)
          .cancelNewDeviceJoin(progress: progress);
      if (!mounted) return;
      state = state.copyWith(
        activeJoin: next,
        localJoins: _replaceJoin(state.localJoins, next),
        isActionPending: false,
      );
      if (_selector != null) await loadManagement();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyDeviceError(error),
      );
    }
  }

  void clearActive() {
    final stalePreparation = state.rootTransfer.preparation;
    state = state.copyWith(
      clearActiveJoin: true,
      clearRootTransfer: true,
      clearError: true,
    );
    if (stalePreparation != null) {
      unawaited(
        ref.read(rootKeyTransferServiceProvider).discard(stalePreparation),
      );
    }
  }
}

final devicesProvider = StateNotifierProvider<DevicesController, DevicesState>(
  (ref) => DevicesController(ref),
);

List<DeviceJoinProgress> _replaceJoin(
  List<DeviceJoinProgress> sessions,
  DeviceJoinProgress replacement,
) {
  return <DeviceJoinProgress>[
    for (final session in sessions)
      if (session.joinSessionId != replacement.joinSessionId) session,
    replacement,
  ];
}

DeviceSummary? _findDevice(
  DeviceRegistrySnapshot? registry,
  String protocolDeviceId,
) {
  if (registry == null) return null;
  for (final device in registry.devices) {
    if (device.protocolDeviceId == protocolDeviceId) return device;
  }
  return null;
}

DeviceJoinRequestNotice? _findJoinRequest(
  List<DeviceJoinRequestNotice> requests,
  String joinSessionId,
) {
  for (final request in requests) {
    if (request.joinSessionId == joinSessionId) {
      return request;
    }
  }
  return null;
}

DeviceManagementErrorKind _classifyDeviceError(Object error) {
  final code = switch (error) {
    DeviceManagementException(:final code) => code,
    RootKeyTransferException(:final code) => code,
    RootKeyTransferPortException(:final code) => code,
    _ => error.toString().toLowerCase(),
  };
  if (code.contains('expired')) return DeviceManagementErrorKind.expired;
  if (code.contains('sas') || code.contains('prompt_mismatch')) {
    return DeviceManagementErrorKind.sasMismatch;
  }
  if (code.contains('presence') || code.contains('cancel')) {
    return DeviceManagementErrorKind.userPresenceDenied;
  }
  if (code.contains('permission_denied') ||
      code.contains('self_revoke') ||
      code.contains('last_ready_admin')) {
    return DeviceManagementErrorKind.protectedDevice;
  }
  if (code.contains('conflict') || code.contains('already_in_progress')) {
    return DeviceManagementErrorKind.conflict;
  }
  if (code.contains('network') ||
      code.contains('socket') ||
      code.contains('timeout')) {
    return DeviceManagementErrorKind.network;
  }
  if (code.contains('disabled') || code.contains('unavailable')) {
    return DeviceManagementErrorKind.unavailable;
  }
  return DeviceManagementErrorKind.failed;
}

({String code, bool retryable}) _rootTransferFailure(Object error) =>
    switch (error) {
      RootKeyTransferException(:final code, :final retryable) => (
        code: code,
        retryable: retryable,
      ),
      RootKeyTransferPortException(:final code, :final retryable) => (
        code: code,
        retryable: retryable,
      ),
      _ => (code: 'root_transfer.temporarily_unavailable', retryable: true),
    };

String _newOperationId(String prefix) {
  final bytes = List<int>.generate(12, (_) => Random.secure().nextInt(256));
  return 'awiki-me-$prefix-${base64UrlEncode(bytes).replaceAll('=', '')}';
}
