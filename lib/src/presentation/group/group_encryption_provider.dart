// [INPUT]: Default-off rollout gate, Group DID, and the group-encryption Core port.
// [OUTPUT]: Redacted preparing/retry/ready state for the group detail surface.
// [POS]: Ephemeral presentation orchestration; durable MLS state remains in IM Core.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/group_encryption_status.dart';

class GroupEncryptionViewState {
  const GroupEncryptionViewState({
    this.status,
    this.isLoading = false,
    this.isRetrying = false,
  });

  final GroupEncryptionStatus? status;
  final bool isLoading;
  final bool isRetrying;

  GroupEncryptionViewState copyWith({
    GroupEncryptionStatus? status,
    bool? isLoading,
    bool? isRetrying,
  }) {
    return GroupEncryptionViewState(
      status: status ?? this.status,
      isLoading: isLoading ?? this.isLoading,
      isRetrying: isRetrying ?? this.isRetrying,
    );
  }
}

class GroupEncryptionController
    extends StateNotifier<GroupEncryptionViewState> {
  GroupEncryptionController(this.ref, this.groupDid)
    : super(const GroupEncryptionViewState());

  final Ref ref;
  final String groupDid;
  int _generation = 0;

  bool get _enabled => ref.read(multiDeviceGroupE2eeEnabledProvider);

  Future<void> load() async {
    if (!_enabled || state.isLoading || state.isRetrying) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(isLoading: true);
    try {
      final status = await ref
          .read(groupEncryptionCorePortProvider)
          .status(groupDid);
      if (!mounted || generation != _generation) {
        return;
      }
      state = GroupEncryptionViewState(status: status);
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      state = GroupEncryptionViewState(status: _unavailableStatus(groupDid));
    }
  }

  Future<void> retry() async {
    if (!_enabled || state.isLoading || state.isRetrying) {
      return;
    }
    final generation = ++_generation;
    state = state.copyWith(isRetrying: true);
    try {
      final status = await ref
          .read(groupEncryptionCorePortProvider)
          .retry(groupDid);
      if (!mounted || generation != _generation) {
        return;
      }
      state = GroupEncryptionViewState(status: status);
    } catch (_) {
      if (!mounted || generation != _generation) {
        return;
      }
      state = GroupEncryptionViewState(status: _retryStatus(groupDid));
    }
  }
}

final groupEncryptionProvider = StateNotifierProvider.autoDispose
    .family<GroupEncryptionController, GroupEncryptionViewState, String>(
      (ref, groupDid) => GroupEncryptionController(ref, groupDid),
    );

GroupEncryptionStatus _retryStatus(String groupDid) => GroupEncryptionStatus(
  groupDid: groupDid,
  readiness: GroupEncryptionReadiness.needsRetry,
  canSendSecure: false,
  retryable: true,
);

GroupEncryptionStatus _unavailableStatus(String groupDid) =>
    GroupEncryptionStatus(
      groupDid: groupDid,
      readiness: GroupEncryptionReadiness.unavailable,
      canSendSecure: false,
      retryable: false,
    );
