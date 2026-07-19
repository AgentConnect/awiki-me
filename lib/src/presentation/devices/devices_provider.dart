import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/device_management_service.dart';
import '../../domain/entities/device_management.dart';
import '../app_shell/providers/session_provider.dart';

enum DeviceManagementErrorKind {
  unavailable,
  expired,
  conflict,
  sasMismatch,
  userPresenceDenied,
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
    this.error,
  });

  final DeviceRegistrySnapshot? registry;
  final List<DeviceJoinProgress> localJoins;
  final DeviceJoinProgress? activeJoin;
  final bool isLoading;
  final bool isActionPending;
  final DeviceManagementErrorKind? error;

  DevicesState copyWith({
    DeviceRegistrySnapshot? registry,
    List<DeviceJoinProgress>? localJoins,
    DeviceJoinProgress? activeJoin,
    bool clearActiveJoin = false,
    bool? isLoading,
    bool? isActionPending,
    DeviceManagementErrorKind? error,
    bool clearError = false,
  }) {
    return DevicesState(
      registry: registry ?? this.registry,
      localJoins: localJoins ?? this.localJoins,
      activeJoin: clearActiveJoin ? null : (activeJoin ?? this.activeJoin),
      isLoading: isLoading ?? this.isLoading,
      isActionPending: isActionPending ?? this.isActionPending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class DevicesController extends StateNotifier<DevicesState> {
  DevicesController(this.ref) : super(const DevicesState());

  final Ref ref;
  int _generation = 0;

  bool get _enabled => ref.read(multiDeviceJoinEnabledProvider);

  String? get _selector {
    final did = ref.read(sessionProvider).session?.did.trim();
    return did == null || did.isEmpty ? null : did;
  }

  Future<void> loadManagement() async {
    final selector = _selector;
    if (!_enabled || selector == null) {
      state = state.copyWith(error: DeviceManagementErrorKind.unavailable);
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final service = ref.read(deviceManagementServiceProvider);
      final results = await Future.wait<Object>(<Future<Object>>[
        service.loadRegistry(selector),
        service.restoreLocalJoins(),
      ]);
      if (!mounted || generation != _generation) return;
      state = DevicesState(
        registry: results[0] as DeviceRegistrySnapshot,
        localJoins: results[1] as List<DeviceJoinProgress>,
        activeJoin: state.activeJoin,
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
    if (!_enabled) {
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
    if (!_enabled || state.isActionPending) return false;
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
    if (!_enabled || selector == null || state.isActionPending) return false;
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
    if (!_enabled) return;
    state = state.copyWith(activeJoin: progress, clearError: true);
  }

  Future<void> pollActive() async {
    final progress = state.activeJoin;
    if (!_enabled ||
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
    if (!_enabled ||
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

  Future<void> cancelActive() async {
    final progress = state.activeJoin;
    if (!_enabled || progress == null || state.isActionPending) return;
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

DeviceManagementErrorKind _classifyDeviceError(Object error) {
  final code = switch (error) {
    DeviceManagementException(:final code) => code,
    _ => error.toString().toLowerCase(),
  };
  if (code.contains('expired')) return DeviceManagementErrorKind.expired;
  if (code.contains('sas') || code.contains('prompt_mismatch')) {
    return DeviceManagementErrorKind.sasMismatch;
  }
  if (code.contains('presence') || code.contains('cancel')) {
    return DeviceManagementErrorKind.userPresenceDenied;
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
