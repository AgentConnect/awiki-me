// [INPUT]: Session identity, Device Registry/Join/revoke services, root-transfer service, and UI intents.
// [OUTPUT]: Secret-free device list, Join continuity, revoke, and admin-readiness presentation state.
// [POS]: Riverpod controller for device management; Registry remains the durable readiness truth.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../app/app_services.dart';
import '../../application/device_management_service.dart';
import '../../application/models/product_local_models.dart';
import '../../application/models/device_revoke_outcome.dart';
import '../../application/ports/root_key_transfer_port.dart';
import '../../application/root_key_transfer_service.dart';
import '../../domain/entities/device_management.dart';
import '../app_shell/providers/session_provider.dart';
import '../app_shell/providers/app_lifecycle_provider.dart';

enum DeviceRevokeNotice {
  revoked,
  revokedGroupsSyncing,
  outcomeUnknown,
  rejected,
}

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
    this.cachedRegistry,
    this.joinRequests = const <DeviceJoinRequestNotice>[],
    this.localJoins = const <DeviceJoinProgress>[],
    this.activeJoin,
    this.isLoading = false,
    this.isActionPending = false,
    this.revokeSubmittingDeviceId,
    this.revokeConfirmingDeviceId,
    this.revokeRetryAllowedDeviceId,
    this.revokeNotice,
    this.rootTransfer = const RootKeyTransferUiState(),
    this.error,
  });

  final DeviceRegistrySnapshot? registry;

  /// Account-state cache used only for rendering the device list.
  ///
  /// Security decisions and mutations continue to use [registry], which is
  /// loaded directly from IM Core for the current session.
  final DeviceRegistrySnapshot? cachedRegistry;
  final List<DeviceJoinRequestNotice> joinRequests;
  final List<DeviceJoinProgress> localJoins;
  final DeviceJoinProgress? activeJoin;
  final bool isLoading;
  final bool isActionPending;
  final String? revokeSubmittingDeviceId;
  final String? revokeConfirmingDeviceId;
  final String? revokeRetryAllowedDeviceId;
  final DeviceRevokeNotice? revokeNotice;
  final RootKeyTransferUiState rootTransfer;
  final DeviceManagementErrorKind? error;

  List<DeviceJoinRequestNotice> get visibleJoinRequests => joinRequests
      .where((request) => !request.isTerminal)
      .toList(growable: false);

  bool get currentDeviceCanManage =>
      registry?.currentDevice?.canManageDevices == true;

  DeviceRegistrySnapshot? get displayRegistry {
    final fresh = registry;
    final cached = cachedRegistry;
    if (fresh == null) return cached;
    if (cached == null) return fresh;
    if (!isCanonicalProductDecimal(fresh.registryVersion) ||
        !isCanonicalProductDecimal(cached.registryVersion)) {
      return fresh;
    }
    return compareProductDecimalVersions(
              cached.registryVersion,
              fresh.registryVersion,
            ) >
            0
        ? cached
        : fresh;
  }

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

  bool canRevokeDevice(DeviceSummary device) {
    final ordinarilyAllowed =
        currentDeviceCanManage &&
        !device.isCurrent &&
        device.status == DeviceStatus.active;
    if (!ordinarilyAllowed) return false;
    final submitting = revokeSubmittingDeviceId;
    if (submitting != null) {
      return submitting == device.protocolDeviceId;
    }
    final confirming = revokeConfirmingDeviceId;
    if (confirming == null) return true;
    return confirming == device.protocolDeviceId &&
        revokeRetryAllowedDeviceId == device.protocolDeviceId;
  }

  DevicesState copyWith({
    DeviceRegistrySnapshot? registry,
    bool clearRegistry = false,
    DeviceRegistrySnapshot? cachedRegistry,
    bool clearCachedRegistry = false,
    List<DeviceJoinRequestNotice>? joinRequests,
    List<DeviceJoinProgress>? localJoins,
    DeviceJoinProgress? activeJoin,
    bool clearActiveJoin = false,
    bool? isLoading,
    bool? isActionPending,
    String? revokeSubmittingDeviceId,
    bool clearRevokeSubmitting = false,
    String? revokeConfirmingDeviceId,
    bool clearRevokeConfirming = false,
    String? revokeRetryAllowedDeviceId,
    bool clearRevokeRetryAllowed = false,
    DeviceRevokeNotice? revokeNotice,
    bool clearRevokeNotice = false,
    RootKeyTransferUiState? rootTransfer,
    bool clearRootTransfer = false,
    DeviceManagementErrorKind? error,
    bool clearError = false,
  }) {
    return DevicesState(
      registry: clearRegistry ? null : (registry ?? this.registry),
      cachedRegistry: clearCachedRegistry
          ? null
          : (cachedRegistry ?? this.cachedRegistry),
      joinRequests: joinRequests ?? this.joinRequests,
      localJoins: localJoins ?? this.localJoins,
      activeJoin: clearActiveJoin ? null : (activeJoin ?? this.activeJoin),
      isLoading: isLoading ?? this.isLoading,
      isActionPending: isActionPending ?? this.isActionPending,
      revokeSubmittingDeviceId: clearRevokeSubmitting
          ? null
          : (revokeSubmittingDeviceId ?? this.revokeSubmittingDeviceId),
      revokeConfirmingDeviceId: clearRevokeConfirming
          ? null
          : (revokeConfirmingDeviceId ?? this.revokeConfirmingDeviceId),
      revokeRetryAllowedDeviceId: clearRevokeRetryAllowed
          ? null
          : (revokeRetryAllowedDeviceId ?? this.revokeRetryAllowedDeviceId),
      revokeNotice: clearRevokeNotice
          ? null
          : (revokeNotice ?? this.revokeNotice),
      rootTransfer: clearRootTransfer
          ? const RootKeyTransferUiState()
          : (rootTransfer ?? this.rootTransfer),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this.ref) : super(const DevicesState()) {
    _sessionKey = _currentSessionKey();
    _sessionSubscription = ref.listen<SessionState>(
      sessionProvider,
      _handleSessionChanged,
    );
    _lifecycleSubscription = ref.listen<AppLifecycleState>(
      appLifecycleProvider,
      _handleLifecycleChanged,
    );
  }

  final Ref ref;
  int _generation = 0;
  int _sessionEpoch = 0;
  int _registryReadGeneration = 0;
  int _lastAppliedRegistryReadGeneration = 0;
  int _revokeOperationGeneration = 0;
  int? _revokeClosedOperationGeneration;
  int _revokePostRpcRegistryGenerationFloor = 0;
  String? _revokeOperationTargetDeviceId;
  DeviceRevokeOutcomeCategory? _revokeClosedOutcomeCategory;
  bool _revokeRpcCompleted = false;
  late String _sessionKey;
  late final ProviderSubscription<SessionState> _sessionSubscription;
  late final ProviderSubscription<AppLifecycleState> _lifecycleSubscription;
  String? _selectedAdminJoinSessionId;

  bool get _deviceRevokeEnabled =>
      ref.read(multiDeviceDeviceRevokeEnabledProvider);

  String? get _selector {
    final did = ref.read(sessionProvider).session?.did.trim();
    return did == null || did.isEmpty ? null : did;
  }

  String _currentSessionKey() {
    final session = ref.read(sessionProvider).session;
    return '${session?.did ?? ''}\u0000${session?.credentialName ?? ''}';
  }

  void _handleSessionChanged(SessionState? previous, SessionState next) {
    final nextKey =
        '${next.session?.did ?? ''}\u0000${next.session?.credentialName ?? ''}';
    if (nextKey == _sessionKey) return;
    _sessionKey = nextKey;
    _sessionEpoch += 1;
    _generation += 1;
    _registryReadGeneration += 1;
    _lastAppliedRegistryReadGeneration = 0;
    _revokeOperationGeneration += 1;
    _revokeClosedOperationGeneration = null;
    _revokePostRpcRegistryGenerationFloor = 0;
    _revokeOperationTargetDeviceId = null;
    _revokeClosedOutcomeCategory = null;
    _revokeRpcCompleted = false;
    final activeJoin = state.activeJoin;
    final preservesJoinedMember =
        previous?.session == null &&
        next.session?.did == activeJoin?.did &&
        activeJoin?.side == DeviceJoinSide.newDevice &&
        activeJoin?.phase == DeviceJoinPhase.authorized &&
        activeJoin?.remoteState == DeviceJoinRemoteState.consumed &&
        activeJoin?.sas == null;
    state = preservesJoinedMember
        ? DevicesState(
            activeJoin: activeJoin,
            localJoins: <DeviceJoinProgress>[activeJoin!],
          )
        : const DevicesState();
  }

  void _handleLifecycleChanged(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    if (next == AppLifecycleState.resumed &&
        (state.registry != null || state.revokeConfirmingDeviceId != null)) {
      unawaited(refreshRegistryOnly());
    }
  }

  @override
  void dispose() {
    _sessionSubscription.close();
    _lifecycleSubscription.close();
    super.dispose();
  }

  Future<void> loadManagement() async {
    final selector = _selector;
    if (selector == null) {
      state = state.copyWith(error: DeviceManagementErrorKind.unavailable);
      return;
    }
    final generation = ++_generation;
    final registryReadGeneration = ++_registryReadGeneration;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = ref.read(deviceManagementServiceProvider);
      final registry = await service.loadRegistry(selector);
      if (registry.did != selector) {
        throw StateError('device_registry_binding_mismatch');
      }
      final results = await Future.wait<Object>(<Future<Object>>[
        service.restoreLocalJoins(),
        if (registry.currentDevice?.canManageDevices == true)
          service.restoreAdminJoinRequests(selector),
      ]);
      if (!mounted ||
          generation != _generation ||
          registryReadGeneration != _registryReadGeneration) {
        return;
      }
      var resultIndex = 0;
      final localJoins = (results[resultIndex++] as List<DeviceJoinProgress>)
          .where((session) => session.side == DeviceJoinSide.newDevice)
          .toList(growable: false);
      final joinRequests = registry.currentDevice?.canManageDevices == true
          ? results[resultIndex++] as List<DeviceJoinRequestNotice>
          : const <DeviceJoinRequestNotice>[];
      final securityFactsChanged =
          _registrySecurityFingerprint(state.registry) !=
          _registrySecurityFingerprint(registry);
      state = DevicesState(
        registry: registry,
        cachedRegistry: state.cachedRegistry,
        joinRequests: joinRequests,
        localJoins: localJoins,
        activeJoin: state.activeJoin,
        rootTransfer: state.rootTransfer,
        revokeSubmittingDeviceId: state.revokeSubmittingDeviceId,
        revokeConfirmingDeviceId: state.revokeConfirmingDeviceId,
        revokeRetryAllowedDeviceId: state.revokeRetryAllowedDeviceId,
        revokeNotice: state.revokeNotice,
      );
      _lastAppliedRegistryReadGeneration = registryReadGeneration;
      if (securityFactsChanged) {
        ref.read(deviceSecurityFactsRevisionProvider.notifier).bump();
      }
      _reduceRevokeConfirmation(
        registry: registry,
        registryReadGeneration: registryReadGeneration,
      );
    } catch (error) {
      if (!mounted ||
          generation != _generation ||
          registryReadGeneration != _registryReadGeneration) {
        return;
      }
      _reduceRevokeConfirmation(
        refreshFailed: true,
        registryReadGeneration: registryReadGeneration,
      );
      state = state.copyWith(
        isLoading: false,
        error: _classifyDeviceError(error),
      );
    }
  }

  /// Publishes a durable account-state Registry snapshot for display only.
  ///
  /// This intentionally does not update [DevicesState.registry] or the
  /// security-facts revision. Join, revoke, and root-transfer flows must load a
  /// fresh Registry through IM Core before making authorization decisions.
  void applyCachedRegistry(DeviceRegistrySnapshot registry) {
    if (!mounted) {
      return;
    }
    state = state.copyWith(cachedRegistry: registry);
  }

  void clearAccountStateProjection() {
    if (!mounted || state.cachedRegistry == null) {
      return;
    }
    state = state.copyWith(clearCachedRegistry: true);
  }

  Future<void> refreshJoinInbox() async {
    final sessionEpoch = _sessionEpoch;
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
      if (!_isCurrentSessionOwner(
        selector: selector,
        sessionEpoch: sessionEpoch,
      )) {
        return;
      }
      var activeJoin = state.activeJoin;
      var clearActiveJoin = false;
      final selectedJoinSessionId = activeJoin?.side == DeviceJoinSide.admin
          ? activeJoin!.joinSessionId
          : _selectedAdminJoinSessionId;
      if (selectedJoinSessionId != null) {
        final request = _findJoinRequest(requests, selectedJoinSessionId);
        if (request == null || request.isTerminal) {
          final preserveAuthorizedCompletion =
              activeJoin?.side == DeviceJoinSide.admin &&
              activeJoin?.joinSessionId == selectedJoinSessionId &&
              activeJoin?.phase == DeviceJoinPhase.authorized;
          if (!preserveAuthorizedCompletion &&
              activeJoin?.side == DeviceJoinSide.admin &&
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
          if (!_isCurrentSessionOwner(
            selector: selector,
            sessionEpoch: sessionEpoch,
          )) {
            return;
          }
        }
      }
      state = state.copyWith(
        joinRequests: requests,
        activeJoin: activeJoin,
        clearActiveJoin: clearActiveJoin,
        clearError: true,
      );
    } catch (error) {
      if (!_isCurrentSessionOwner(
        selector: selector,
        sessionEpoch: sessionEpoch,
      )) {
        return;
      }
      state = state.copyWith(error: _classifyDeviceError(error));
    }
  }

  bool _isCurrentSessionOwner({
    required String selector,
    required int sessionEpoch,
  }) {
    return mounted && sessionEpoch == _sessionEpoch && selector == _selector;
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
        unawaited(
          ref
              .read(accountStateSyncRequestBusProvider)
              .request('device_join_authorized', force: true),
        );
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
      unawaited(
        ref
            .read(accountStateSyncRequestBusProvider)
            .request('device_join_approved', force: true),
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
        state.revokeSubmittingDeviceId != null ||
        authoritativeTarget == null ||
        !state.canRevokeDevice(authoritativeTarget)) {
      return false;
    }

    final targetDeviceId = authoritativeTarget.protocolDeviceId;
    final sessionEpoch = _sessionEpoch;
    final operationGeneration = ++_revokeOperationGeneration;
    _revokeOperationTargetDeviceId = targetDeviceId;
    _revokeClosedOperationGeneration = null;
    _revokeClosedOutcomeCategory = null;
    _revokeRpcCompleted = false;
    _revokePostRpcRegistryGenerationFloor = 0;
    state = state.copyWith(
      revokeSubmittingDeviceId: targetDeviceId,
      clearRevokeConfirming: true,
      clearRevokeRetryAllowed: true,
      clearRevokeNotice: true,
      clearError: true,
    );
    DeviceRevokeOutcomeCategory? closedOutcomeCategory;
    var freshTargetConfirmedActive = false;
    var freshRegistryLoaded = false;
    try {
      await ref
          .read(deviceManagementServiceProvider)
          .revoke(
            selector: selector,
            targetDeviceId: targetDeviceId,
            presenceReason: presenceReason,
          );
    } on DeviceRevokeException catch (error) {
      closedOutcomeCategory = error.category;
    } catch (_) {
      closedOutcomeCategory = DeviceRevokeOutcomeCategory.outcomeUnknown;
    }
    if (!mounted ||
        sessionEpoch != _sessionEpoch ||
        operationGeneration != _revokeOperationGeneration) {
      return false;
    }
    _revokeClosedOperationGeneration = operationGeneration;
    _revokeClosedOutcomeCategory = closedOutcomeCategory;
    _revokeRpcCompleted = true;
    _revokePostRpcRegistryGenerationFloor = _registryReadGeneration + 1;
    try {
      final applied = await _loadFreshRegistry(selector, sessionEpoch);
      if (!mounted ||
          sessionEpoch != _sessionEpoch ||
          operationGeneration != _revokeOperationGeneration) {
        return false;
      }
      freshRegistryLoaded = true;
      final registry = applied.registry;
      final freshTarget = _findDevice(registry, targetDeviceId);
      if (freshTarget?.status == DeviceStatus.revoked) {
        _finishRevokeOperation(operationGeneration);
        state = state.copyWith(
          clearRevokeSubmitting: true,
          clearRevokeConfirming: true,
          clearRevokeRetryAllowed: true,
          revokeNotice: DeviceRevokeNotice.revokedGroupsSyncing,
          clearError: true,
        );
        unawaited(
          ref
              .read(accountStateSyncRequestBusProvider)
              .request('device_revoked', force: true),
        );
        return true;
      }
      if (freshTarget?.status == DeviceStatus.active &&
          (closedOutcomeCategory ==
                  DeviceRevokeOutcomeCategory.cancelledBeforeSubmit ||
              closedOutcomeCategory ==
                  DeviceRevokeOutcomeCategory.rejectedBeforeCommit)) {
        _finishRevokeOperation(operationGeneration);
        state = state.copyWith(
          clearRevokeSubmitting: true,
          clearRevokeConfirming: true,
          clearRevokeRetryAllowed: true,
          revokeNotice:
              closedOutcomeCategory ==
                  DeviceRevokeOutcomeCategory.cancelledBeforeSubmit
              ? null
              : DeviceRevokeNotice.rejected,
          clearRevokeNotice:
              closedOutcomeCategory ==
              DeviceRevokeOutcomeCategory.cancelledBeforeSubmit,
        );
        return false;
      }
      freshTargetConfirmedActive = freshTarget?.status == DeviceStatus.active;
    } on _StaleDeviceRegistryRead {
      if (!mounted ||
          sessionEpoch != _sessionEpoch ||
          operationGeneration != _revokeOperationGeneration) {
        return false;
      }
      final latestRegistryIsPostRpc =
          _lastAppliedRegistryReadGeneration >=
          _revokePostRpcRegistryGenerationFloor;
      state = state.copyWith(
        clearRevokeSubmitting: true,
        revokeConfirmingDeviceId: targetDeviceId,
        clearRevokeRetryAllowed: true,
        revokeNotice: DeviceRevokeNotice.outcomeUnknown,
        clearError: true,
      );
      if (latestRegistryIsPostRpc) {
        _reduceRevokeConfirmation(
          registry: state.registry,
          registryReadGeneration: _lastAppliedRegistryReadGeneration,
        );
      }
      return latestRegistryIsPostRpc &&
          _findDevice(state.registry, targetDeviceId)?.status ==
              DeviceStatus.revoked;
    } catch (_) {
      // A failed refresh leaves the destructive outcome unknown.
    }
    if (!mounted ||
        sessionEpoch != _sessionEpoch ||
        operationGeneration != _revokeOperationGeneration) {
      return false;
    }
    state = state.copyWith(
      clearRegistry: !freshRegistryLoaded,
      clearRevokeSubmitting: true,
      revokeConfirmingDeviceId: targetDeviceId,
      revokeRetryAllowedDeviceId: freshTargetConfirmedActive
          ? targetDeviceId
          : null,
      clearRevokeRetryAllowed: !freshTargetConfirmedActive,
      revokeNotice: DeviceRevokeNotice.outcomeUnknown,
      clearError: true,
    );
    return false;
  }

  Future<void> refreshRegistryOnly() async {
    final selector = _selector;
    if (selector == null) return;
    final sessionEpoch = _sessionEpoch;
    try {
      final applied = await _loadFreshRegistry(selector, sessionEpoch);
      if (!mounted || sessionEpoch != _sessionEpoch) return;
      _reduceRevokeConfirmation(
        registry: applied.registry,
        registryReadGeneration: applied.registryReadGeneration,
      );
    } on _StaleDeviceRegistryRead {
      return;
    } catch (_) {
      if (!mounted || sessionEpoch != _sessionEpoch) return;
      _reduceRevokeConfirmation(
        refreshFailed: true,
        registryReadGeneration: _registryReadGeneration,
      );
    }
  }

  void _reduceRevokeConfirmation({
    DeviceRegistrySnapshot? registry,
    bool refreshFailed = false,
    required int registryReadGeneration,
  }) {
    final confirming =
        state.revokeConfirmingDeviceId ?? _revokeOperationTargetDeviceId;
    if (confirming == null || !_revokeRpcCompleted) return;
    if (_revokeClosedOperationGeneration != _revokeOperationGeneration) {
      return;
    }
    if (registryReadGeneration < _revokePostRpcRegistryGenerationFloor) {
      return;
    }
    if (refreshFailed) {
      state = state.copyWith(
        clearRegistry: true,
        clearRevokeSubmitting: true,
        revokeConfirmingDeviceId: confirming,
        clearRevokeRetryAllowed: true,
        revokeNotice: DeviceRevokeNotice.outcomeUnknown,
      );
      return;
    }
    final target = _findDevice(registry, confirming);
    if (target?.status == DeviceStatus.revoked) {
      _finishRevokeOperation(_revokeOperationGeneration);
      state = state.copyWith(
        clearRevokeSubmitting: true,
        clearRevokeConfirming: true,
        clearRevokeRetryAllowed: true,
        revokeNotice: DeviceRevokeNotice.revokedGroupsSyncing,
        clearError: true,
      );
      return;
    }
    if (target?.status == DeviceStatus.active) {
      final closedOutcomeCategory = _revokeClosedOutcomeCategory;
      if (closedOutcomeCategory ==
              DeviceRevokeOutcomeCategory.cancelledBeforeSubmit ||
          closedOutcomeCategory ==
              DeviceRevokeOutcomeCategory.rejectedBeforeCommit) {
        _finishRevokeOperation(_revokeOperationGeneration);
        state = state.copyWith(
          clearRevokeSubmitting: true,
          clearRevokeConfirming: true,
          clearRevokeRetryAllowed: true,
          revokeNotice:
              closedOutcomeCategory ==
                  DeviceRevokeOutcomeCategory.cancelledBeforeSubmit
              ? null
              : DeviceRevokeNotice.rejected,
          clearRevokeNotice:
              closedOutcomeCategory ==
              DeviceRevokeOutcomeCategory.cancelledBeforeSubmit,
        );
        return;
      }
      state = state.copyWith(
        clearRevokeSubmitting: true,
        revokeConfirmingDeviceId: confirming,
        revokeRetryAllowedDeviceId: confirming,
        revokeNotice: DeviceRevokeNotice.outcomeUnknown,
      );
      return;
    }
    state = state.copyWith(
      clearRevokeSubmitting: true,
      revokeConfirmingDeviceId: confirming,
      clearRevokeRetryAllowed: true,
      revokeNotice: DeviceRevokeNotice.outcomeUnknown,
    );
  }

  Future<_AppliedDeviceRegistry> _loadFreshRegistry(
    String selector,
    int sessionEpoch,
  ) async {
    final registryReadGeneration = ++_registryReadGeneration;
    late final DeviceRegistrySnapshot registry;
    try {
      registry = await ref
          .read(deviceManagementServiceProvider)
          .loadRegistry(selector);
    } catch (error, stackTrace) {
      if (!mounted ||
          sessionEpoch != _sessionEpoch ||
          registryReadGeneration != _registryReadGeneration) {
        throw const _StaleDeviceRegistryRead();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (!mounted ||
        sessionEpoch != _sessionEpoch ||
        registryReadGeneration != _registryReadGeneration) {
      throw const _StaleDeviceRegistryRead();
    }
    if (registry.did != selector) {
      throw StateError('device_registry_binding_mismatch');
    }
    final securityFactsChanged =
        _registrySecurityFingerprint(state.registry) !=
        _registrySecurityFingerprint(registry);
    state = state.copyWith(registry: registry, isLoading: false);
    _lastAppliedRegistryReadGeneration = registryReadGeneration;
    if (securityFactsChanged) {
      ref.read(deviceSecurityFactsRevisionProvider.notifier).bump();
    }
    return _AppliedDeviceRegistry(
      registry: registry,
      registryReadGeneration: registryReadGeneration,
    );
  }

  void _finishRevokeOperation(int operationGeneration) {
    if (operationGeneration != _revokeOperationGeneration) return;
    _revokeOperationGeneration += 1;
    _revokeClosedOperationGeneration = null;
    _revokeOperationTargetDeviceId = null;
    _revokeClosedOutcomeCategory = null;
    _revokeRpcCompleted = false;
    _revokePostRpcRegistryGenerationFloor = 0;
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

class DeviceSecurityFactsRevisionController extends StateNotifier<int> {
  DeviceSecurityFactsRevisionController() : super(0);

  void bump() => state += 1;
}

final deviceSecurityFactsRevisionProvider =
    StateNotifierProvider<DeviceSecurityFactsRevisionController, int>(
      (ref) => DeviceSecurityFactsRevisionController(),
    );

final devicesProvider = StateNotifierProvider<DevicesController, DevicesState>(
  (ref) => DevicesController(ref),
);

class _StaleDeviceRegistryRead implements Exception {
  const _StaleDeviceRegistryRead();
}

class _AppliedDeviceRegistry {
  const _AppliedDeviceRegistry({
    required this.registry,
    required this.registryReadGeneration,
  });

  final DeviceRegistrySnapshot registry;
  final int registryReadGeneration;
}

String _registrySecurityFingerprint(DeviceRegistrySnapshot? registry) {
  if (registry == null) return '';
  final deviceFacts =
      registry.devices
          .map(
            (device) => <String>[
              device.protocolDeviceId,
              device.signingKeyId,
              device.e2eeKeyId,
              device.status.name,
              device.role.name,
              '${device.managementReady}',
              '${device.isCurrent}',
            ].join('\u0001'),
          )
          .toList()
        ..sort();
  return '${registry.did}\u0002${deviceFacts.join('\u0003')}';
}

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
