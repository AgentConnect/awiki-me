// [INPUT]: Session identity, Device Registry/Join/revoke services, root-transfer service, and UI intents.
// [OUTPUT]: Secret-free device list, Join, revoke, and admin-readiness presentation state.
// [POS]: Riverpod controller for device management; Registry remains the durable readiness truth.

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
  sessionEstablishmentPending,
  protectedDevice,
  network,
  failed,
}

class DevicesState {
  const DevicesState({
    this.registry,
    this.localJoins = const <DeviceJoinProgress>[],
    this.activeJoin,
    this.isLoading = false,
    this.isActionPending = false,
    this.rootTransfers = const <String, RootKeyTransferSummary>{},
    this.rootSessionEstablishingDeviceIds = const <String>{},
    this.error,
  });

  final DeviceRegistrySnapshot? registry;
  final List<DeviceJoinProgress> localJoins;
  final DeviceJoinProgress? activeJoin;
  final bool isLoading;
  final bool isActionPending;
  final Map<String, RootKeyTransferSummary> rootTransfers;
  final Set<String> rootSessionEstablishingDeviceIds;
  final DeviceManagementErrorKind? error;

  bool get currentDeviceCanManage =>
      registry?.currentDevice?.canManageDevices == true;

  RootKeyTransferSummary? rootTransferFor(DeviceSummary device) =>
      rootTransfers[device.protocolDeviceId];

  bool isRootSessionEstablishing(DeviceSummary device) =>
      rootSessionEstablishingDeviceIds.contains(device.protocolDeviceId);

  DeviceManagementReadiness? readinessFor(DeviceSummary device) {
    if (device.role != DeviceRole.admin ||
        device.status != DeviceStatus.active) {
      return null;
    }
    if (device.managementReady) {
      return DeviceManagementReadiness.ready;
    }
    return switch (rootTransferFor(device)?.status) {
      RootKeyTransferStatus.failed => DeviceManagementReadiness.failed,
      RootKeyTransferStatus.pendingDelivery ||
      RootKeyTransferStatus.awaitingImport ||
      RootKeyTransferStatus.importing ||
      RootKeyTransferStatus.completed => DeviceManagementReadiness.importing,
      null => DeviceManagementReadiness.adminAwaitingRoot,
    };
  }

  bool canStartRootTransfer(DeviceSummary device) =>
      currentDeviceCanManage &&
      !device.isCurrent &&
      device.status == DeviceStatus.active &&
      device.role == DeviceRole.admin &&
      !device.managementReady &&
      rootTransferFor(device) == null;

  bool canRetryRootTransfer(DeviceSummary device) {
    final current = registry?.currentDevice;
    final transfer = rootTransferFor(device);
    if (current == null ||
        transfer == null ||
        !transfer.retryable ||
        device.status != DeviceStatus.active ||
        device.role != DeviceRole.admin ||
        device.managementReady ||
        transfer.recipientDeviceId != device.protocolDeviceId) {
      return false;
    }
    if (transfer.senderDeviceId == current.protocolDeviceId) {
      return current.canManageDevices;
    }
    return transfer.recipientDeviceId == current.protocolDeviceId;
  }

  bool canRevokeDevice(DeviceSummary device) =>
      currentDeviceCanManage &&
      !device.isCurrent &&
      device.status == DeviceStatus.active;

  DevicesState copyWith({
    DeviceRegistrySnapshot? registry,
    List<DeviceJoinProgress>? localJoins,
    DeviceJoinProgress? activeJoin,
    bool clearActiveJoin = false,
    bool? isLoading,
    bool? isActionPending,
    Map<String, RootKeyTransferSummary>? rootTransfers,
    Set<String>? rootSessionEstablishingDeviceIds,
    DeviceManagementErrorKind? error,
    bool clearError = false,
  }) {
    return DevicesState(
      registry: registry ?? this.registry,
      localJoins: localJoins ?? this.localJoins,
      activeJoin: clearActiveJoin ? null : (activeJoin ?? this.activeJoin),
      isLoading: isLoading ?? this.isLoading,
      isActionPending: isActionPending ?? this.isActionPending,
      rootTransfers: rootTransfers ?? this.rootTransfers,
      rootSessionEstablishingDeviceIds:
          rootSessionEstablishingDeviceIds ??
          this.rootSessionEstablishingDeviceIds,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this.ref) : super(const DevicesState());

  final Ref ref;
  int _generation = 0;
  final Map<String, String> _rootTransferStartMessageIds = <String, String>{};

  bool get _joinEnabled => ref.read(multiDeviceJoinEnabledProvider);

  bool get _rootTransferEnabled =>
      ref.read(multiDeviceRootTransferEnabledProvider);

  bool get _deviceRevokeEnabled =>
      ref.read(multiDeviceDeviceRevokeEnabledProvider);

  bool get _managementSurfaceEnabled => _joinEnabled || _deviceRevokeEnabled;

  String? get _selector {
    final did = ref.read(sessionProvider).session?.did.trim();
    return did == null || did.isEmpty ? null : did;
  }

  Future<void> loadManagement() async {
    final selector = _selector;
    if (!_managementSurfaceEnabled || selector == null) {
      state = state.copyWith(error: DeviceManagementErrorKind.unavailable);
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = ref.read(deviceManagementServiceProvider);
      final results = await Future.wait<Object>(<Future<Object>>[
        service.loadRegistry(selector),
        if (_joinEnabled)
          service.restoreLocalJoins()
        else
          Future<List<DeviceJoinProgress>>.value(const <DeviceJoinProgress>[]),
        if (_rootTransferEnabled)
          ref
              .read(rootKeyTransferServiceProvider)
              .list(selector: selector, includeCompleted: true),
      ]);
      if (!mounted || generation != _generation) return;
      final registry = results[0] as DeviceRegistrySnapshot;
      final transfers = _rootTransferEnabled
          ? _latestRootTransfersByRecipient(
              registry,
              results[2] as List<RootKeyTransferSummary>,
            )
          : const <String, RootKeyTransferSummary>{};
      final eligibleRecipients = registry.devices
          .where(
            (device) =>
                device.status == DeviceStatus.active &&
                device.role == DeviceRole.admin &&
                !device.managementReady,
          )
          .map((device) => device.protocolDeviceId)
          .toSet();
      if (!_rootTransferEnabled) {
        _rootTransferStartMessageIds.clear();
      } else {
        _rootTransferStartMessageIds.removeWhere(
          (deviceId, _) =>
              !eligibleRecipients.contains(deviceId) ||
              transfers.containsKey(deviceId),
        );
      }
      final establishingDeviceIds = _rootTransferEnabled
          ? state.rootSessionEstablishingDeviceIds
                .where(
                  (deviceId) =>
                      eligibleRecipients.contains(deviceId) &&
                      !transfers.containsKey(deviceId),
                )
                .toSet()
          : <String>{};
      state = DevicesState(
        registry: registry,
        localJoins: results[1] as List<DeviceJoinProgress>,
        activeJoin: state.activeJoin,
        rootTransfers: transfers,
        rootSessionEstablishingDeviceIds: Set.unmodifiable(
          establishingDeviceIds,
        ),
      );
    } catch (error) {
      if (!mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        error: _classifyDeviceError(error),
      );
    }
  }

  Future<void> loadNewDevice() async {
    if (!_joinEnabled) {
      state = state.copyWith(error: DeviceManagementErrorKind.unavailable);
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
      state = DevicesState(
        localJoins: sessions,
        activeJoin: resumable.isEmpty ? null : resumable.last,
      );
      if (resumable.isNotEmpty) {
        await pollActive();
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
    if (!_joinEnabled || state.isActionPending) return false;
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

  Future<bool> claim(PendingDeviceJoinSummary pending) async {
    final selector = _selector;
    if (!_joinEnabled || selector == null || state.isActionPending) {
      return false;
    }
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final progress = await ref
          .read(deviceManagementServiceProvider)
          .claim(
            selector: selector,
            joinSessionId: pending.joinSessionId,
            operationId: 'awiki-me-claim-${pending.joinSessionId}',
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

  void resume(DeviceJoinProgress progress) {
    if (!_joinEnabled) return;
    state = state.copyWith(activeJoin: progress, clearError: true);
  }

  Future<void> pollActive() async {
    final progress = state.activeJoin;
    if (!_joinEnabled ||
        progress == null ||
        progress.isTerminal ||
        state.isActionPending) {
      return;
    }
    final selector = _selector ?? progress.did;
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final next = await ref
          .read(deviceManagementServiceProvider)
          .poll(selector: selector, progress: progress);
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

  Future<bool> approveActive({
    required DeviceRole role,
    required bool sasConfirmed,
    required String presenceReason,
  }) async {
    final selector = _selector;
    final progress = state.activeJoin;
    if (!_joinEnabled ||
        selector == null ||
        progress?.sas == null ||
        state.isActionPending) {
      return false;
    }
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final next = await ref
          .read(deviceManagementServiceProvider)
          .approve(
            selector: selector,
            progress: progress!,
            displayedSas: progress.sas!,
            role: role,
            sasConfirmed: sasConfirmed,
            presenceReason: presenceReason,
          );
      if (!mounted) return false;
      state = state.copyWith(
        activeJoin: next,
        localJoins: _replaceJoin(state.localJoins, next),
        isActionPending: false,
      );
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

  Future<bool> startOrRetryRootTransfer({
    required DeviceSummary recipient,
    required String presenceReason,
  }) async {
    final selector = _selector;
    final authoritativeRecipient = _findDevice(
      state.registry,
      recipient.protocolDeviceId,
    );
    if (!_joinEnabled ||
        !_rootTransferEnabled ||
        selector == null ||
        state.isActionPending ||
        authoritativeRecipient == null ||
        authoritativeRecipient.status != DeviceStatus.active ||
        authoritativeRecipient.role != DeviceRole.admin ||
        authoritativeRecipient.managementReady) {
      return false;
    }

    final transfer = state.rootTransferFor(authoritativeRecipient);
    final canStart = state.canStartRootTransfer(authoritativeRecipient);
    final canRetry = state.canRetryRootTransfer(authoritativeRecipient);
    if (!canStart && !canRetry) return false;

    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final service = ref.read(rootKeyTransferServiceProvider);
      if (transfer == null) {
        final messageId = _rootTransferStartMessageIds.putIfAbsent(
          authoritativeRecipient.protocolDeviceId,
          () => _newOperationId('root-control'),
        );
        await service.start(
          selector: selector,
          recipientDeviceId: authoritativeRecipient.protocolDeviceId,
          messageId: messageId,
          presenceReason: presenceReason,
        );
      } else {
        await service.retry(
          selector: selector,
          messageId: transfer.messageId,
          presenceReason: presenceReason,
        );
      }
      if (!mounted) return false;
      await loadManagement();
      if (mounted) {
        state = state.copyWith(isActionPending: false);
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      final kind = _classifyDeviceError(error);
      try {
        await loadManagement();
      } catch (_) {
        // loadManagement already projects a stable error and never rethrows.
      }
      if (mounted) {
        final establishingDeviceIds = <String>{
          ...state.rootSessionEstablishingDeviceIds,
        };
        if (kind == DeviceManagementErrorKind.sessionEstablishmentPending) {
          establishingDeviceIds.add(authoritativeRecipient.protocolDeviceId);
        } else if (kind != DeviceManagementErrorKind.userPresenceDenied) {
          establishingDeviceIds.remove(authoritativeRecipient.protocolDeviceId);
        }
        state = state.copyWith(
          isActionPending: false,
          rootSessionEstablishingDeviceIds: Set.unmodifiable(
            establishingDeviceIds,
          ),
          error: kind,
        );
      }
      return false;
    }
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

  Future<void> cancelActive() async {
    final progress = state.activeJoin;
    if (!_joinEnabled || progress == null || state.isActionPending) return;
    final selector = _selector ?? progress.did;
    state = state.copyWith(isActionPending: true, clearError: true);
    try {
      final next = await ref
          .read(deviceManagementServiceProvider)
          .cancel(selector: selector, progress: progress);
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
    state = state.copyWith(clearActiveJoin: true, clearError: true);
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

Map<String, RootKeyTransferSummary> _latestRootTransfersByRecipient(
  DeviceRegistrySnapshot registry,
  List<RootKeyTransferSummary> transfers,
) {
  final currentDeviceId = registry.currentDevice?.protocolDeviceId;
  if (currentDeviceId == null) {
    if (transfers.isNotEmpty) {
      throw const RootKeyTransferException('root_transfer_device_mismatch');
    }
    return const <String, RootKeyTransferSummary>{};
  }
  final activeAdminIds = registry.devices
      .where(
        (device) =>
            device.status == DeviceStatus.active &&
            device.role == DeviceRole.admin &&
            !device.managementReady,
      )
      .map((device) => device.protocolDeviceId)
      .toSet();
  final latest = <String, RootKeyTransferSummary>{};
  for (final transfer in transfers) {
    if (transfer.did != registry.did ||
        (transfer.senderDeviceId != currentDeviceId &&
            transfer.recipientDeviceId != currentDeviceId)) {
      throw const RootKeyTransferException('root_transfer_device_mismatch');
    }
    if (!activeAdminIds.contains(transfer.recipientDeviceId)) continue;
    final previous = latest[transfer.recipientDeviceId];
    if (previous == null || transfer.createdAt.isAfter(previous.createdAt)) {
      latest[transfer.recipientDeviceId] = transfer;
    }
  }
  return Map<String, RootKeyTransferSummary>.unmodifiable(latest);
}

DeviceManagementErrorKind _classifyDeviceError(Object error) {
  if (error case RootKeyTransferPortException(
    capability: rootKeyTransferSessionEstablishmentPendingCapability,
  )) {
    return DeviceManagementErrorKind.sessionEstablishmentPending;
  }
  final code = switch (error) {
    DeviceManagementException(:final code) => code,
    RootKeyTransferException(:final code) => code,
    RootKeyTransferPortException(:final code, :final capability) =>
      '$code ${capability ?? ''}',
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

String _newOperationId(String prefix) {
  final bytes = List<int>.generate(12, (_) => Random.secure().nextInt(256));
  return 'awiki-me-$prefix-${base64UrlEncode(bytes).replaceAll('=', '')}';
}
