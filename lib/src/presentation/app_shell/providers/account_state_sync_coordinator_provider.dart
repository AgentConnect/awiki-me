import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../application/account_state_sync_request_bus.dart';
import '../../../application/account_state_sync_service.dart';
import '../../../application/models/product_local_models.dart';
import '../../../application/product_local_store.dart';
import '../../../domain/entities/device_management.dart';
import '../../../domain/entities/session_identity.dart';
import '../../agents/agents_provider.dart';
import '../../devices/devices_provider.dart';
import '../../profile/profile_provider.dart';
import 'session_provider.dart';

enum AccountStateSyncCoordinatorStatus {
  idle,
  syncing,
  ready,
  partialFailure,
  retryWaiting,
}

class AccountStateSyncCoordinatorState {
  const AccountStateSyncCoordinatorState({
    this.status = AccountStateSyncCoordinatorStatus.idle,
    this.pendingReason,
    this.lastReason,
    this.lastCompletedAt,
    this.domainVersions = const <ProductAccountDomain, String>{},
    this.domainErrors = const <ProductAccountDomain, Object>{},
    this.warnings = const <AccountStateSyncWarning>[],
  });

  final AccountStateSyncCoordinatorStatus status;
  final String? pendingReason;
  final String? lastReason;
  final DateTime? lastCompletedAt;
  final Map<ProductAccountDomain, String> domainVersions;
  final Map<ProductAccountDomain, Object> domainErrors;
  final List<AccountStateSyncWarning> warnings;

  bool get isSyncing => status == AccountStateSyncCoordinatorStatus.syncing;
}

class AccountStateSyncCoordinator
    extends StateNotifier<AccountStateSyncCoordinatorState> {
  AccountStateSyncCoordinator(
    this.ref, {
    this.failureBackoff = const Duration(seconds: 8),
  }) : super(const AccountStateSyncCoordinatorState()) {
    _requestBus = ref.read(accountStateSyncRequestBusProvider);
    _requestBus.attach(
      (reason, {force = false}) => request(reason, force: force),
    );
    _sessionSubscription = ref.listen<SessionState>(
      sessionProvider,
      _handleSessionChanged,
    );
  }

  final Ref ref;
  final Duration failureBackoff;

  late final ProviderSubscription<SessionState> _sessionSubscription;
  late final AccountStateSyncRequestBus _requestBus;
  Future<void>? _activeOperation;
  Timer? _retryTimer;
  bool _followUpRequested = false;
  String? _followUpReason;
  bool _disposed = false;

  Future<void> request(String reason, {bool force = false}) {
    if (_disposed) {
      return Future<void>.value();
    }
    final normalizedReason = reason.trim().isEmpty
        ? 'unspecified'
        : reason.trim();
    final active = _activeOperation;
    if (active != null) {
      _followUpRequested = true;
      _followUpReason = normalizedReason;
      state = AccountStateSyncCoordinatorState(
        status: state.status,
        pendingReason: normalizedReason,
        lastReason: state.lastReason,
        lastCompletedAt: state.lastCompletedAt,
        domainVersions: state.domainVersions,
        domainErrors: state.domainErrors,
        warnings: state.warnings,
      );
      return active;
    }
    if (force) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    final operation = _drain(normalizedReason);
    _activeOperation = operation;
    return operation.whenComplete(() {
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    });
  }

  void resetForSession() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _followUpRequested = false;
    _followUpReason = null;
    state = const AccountStateSyncCoordinatorState();
  }

  Future<void> _drain(String initialReason) async {
    var reason = initialReason;
    do {
      _followUpRequested = false;
      _followUpReason = null;
      await _runOnce(reason);
      reason = _followUpReason ?? 'coalesced_follow_up';
    } while (_followUpRequested && !_disposed);
  }

  Future<void> _runOnce(String reason) async {
    final fence = _AccountStateSessionFence.captureOrNull(
      ref.read(sessionProvider),
    );
    if (fence == null || !_isCurrent(fence)) {
      resetForSession();
      return;
    }
    state = AccountStateSyncCoordinatorState(
      status: AccountStateSyncCoordinatorStatus.syncing,
      lastReason: reason,
      lastCompletedAt: state.lastCompletedAt,
      domainVersions: state.domainVersions,
      domainErrors: state.domainErrors,
      warnings: state.warnings,
    );

    final projectionErrors = <ProductAccountDomain, Object>{};
    await _publishCachedSnapshots(fence, projectionErrors);
    if (!_isCurrent(fence)) {
      return;
    }

    AccountStateReconcileResult result;
    try {
      result = await ref
          .read(accountStateSyncServiceProvider)
          .reconcile(
            binding: fence.binding,
            expectedCurrentDid: fence.currentDid,
            expectedIdentityGeneration: fence.identityGeneration,
            sessionGeneration: fence.sessionGeneration,
            isSessionCurrent: (binding, generation) =>
                fence.matchesBinding(binding, generation) && _isCurrent(fence),
          );
    } on Object catch (error) {
      if (!_isCurrent(fence)) {
        return;
      }
      final failures = <ProductAccountDomain, Object>{
        for (final domain in ProductAccountDomain.values) domain: error,
      };
      await _finish(
        fence,
        reason,
        domainErrors: failures,
        warnings: const <AccountStateSyncWarning>[],
      );
      return;
    }
    if (result.sessionInvalidated || !_isCurrent(fence)) {
      return;
    }

    await _publishCachedSnapshots(fence, projectionErrors);
    if (!_isCurrent(fence)) {
      return;
    }
    await _finish(
      fence,
      reason,
      domainErrors: <ProductAccountDomain, Object>{
        ...result.failures,
        ...projectionErrors,
      },
      warnings: result.warnings,
    );
  }

  Future<void> _publishCachedSnapshots(
    _AccountStateSessionFence fence,
    Map<ProductAccountDomain, Object> projectionErrors,
  ) async {
    final store = ref.read(productLocalStoreProvider);
    final snapshots = await Future.wait<Object?>(<Future<Object?>>[
      _loadCachedDomain(
        ProductAccountDomain.agentInventory,
        () => store.loadAgentInventorySnapshot(
          binding: fence.binding,
          legacyOwnerDid: fence.currentDid,
        ),
        projectionErrors,
      ),
      _loadCachedDomain(
        ProductAccountDomain.agentStatus,
        () => store.loadAgentStatusSnapshot(binding: fence.binding),
        projectionErrors,
      ),
      _loadCachedDomain(
        ProductAccountDomain.profile,
        () => store.loadProfileSnapshot(binding: fence.binding),
        projectionErrors,
      ),
      _loadCachedDomain(
        ProductAccountDomain.deviceRegistry,
        () => store.loadDeviceRegistrySnapshot(binding: fence.binding),
        projectionErrors,
      ),
    ]);
    if (!_isCurrent(fence)) {
      return;
    }

    final inventory = snapshots[0] as ProductAgentInventorySnapshot?;
    final agentStatus = snapshots[1] as ProductAgentStatusSnapshot?;
    final profile = snapshots[2] as ProductProfileSnapshot?;
    final registry = snapshots[3] as ProductDeviceRegistrySnapshot?;

    if (inventory != null) {
      try {
        await ref
            .read(agentsProvider.notifier)
            .applyAccountStateSnapshots(
              inventory: inventory,
              status: agentStatus,
              isSessionCurrent: () => _isCurrent(fence),
            );
        projectionErrors.remove(ProductAccountDomain.agentInventory);
        projectionErrors.remove(ProductAccountDomain.agentStatus);
      } on Object catch (error) {
        projectionErrors[ProductAccountDomain.agentInventory] = error;
      }
    }
    if (!_isCurrent(fence)) {
      return;
    }
    if (profile != null) {
      try {
        ref
            .read(profileProvider.notifier)
            .applyAccountStateSnapshot(profile, session: fence.session);
        projectionErrors.remove(ProductAccountDomain.profile);
      } on Object catch (error) {
        projectionErrors[ProductAccountDomain.profile] = error;
      }
    }
    if (!_isCurrent(fence)) {
      return;
    }
    if (registry != null) {
      try {
        ref
            .read(devicesProvider.notifier)
            .applyCachedRegistry(_deviceRegistryProjection(registry, fence));
        projectionErrors.remove(ProductAccountDomain.deviceRegistry);
      } on Object catch (error) {
        projectionErrors[ProductAccountDomain.deviceRegistry] = error;
      }
    }
  }

  Future<void> _finish(
    _AccountStateSessionFence fence,
    String reason, {
    required Map<ProductAccountDomain, Object> domainErrors,
    required List<AccountStateSyncWarning> warnings,
  }) async {
    final store = ref.read(productLocalStoreProvider);
    final stateEntries =
        await Future.wait<
          MapEntry<ProductAccountDomain, ProductAccountDomainSyncState?>?
        >([
          for (final domain in ProductAccountDomain.values)
            _loadSyncState(domain, store, fence, domainErrors),
        ]);
    if (!_isCurrent(fence)) {
      return;
    }
    final versions = <ProductAccountDomain, String>{
      for (final entry in stateEntries)
        if (entry != null && entry.value != null)
          entry.key: entry.value!.domainVersion,
    };
    final hasFailures = domainErrors.isNotEmpty;
    state = AccountStateSyncCoordinatorState(
      status: hasFailures
          ? AccountStateSyncCoordinatorStatus.partialFailure
          : AccountStateSyncCoordinatorStatus.ready,
      lastReason: reason,
      lastCompletedAt: DateTime.now().toUtc(),
      domainVersions: versions,
      domainErrors: Map<ProductAccountDomain, Object>.unmodifiable(
        domainErrors,
      ),
      warnings: List<AccountStateSyncWarning>.unmodifiable(warnings),
    );
    if (hasFailures) {
      _scheduleRetry(fence);
    } else {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  Future<Object?> _loadCachedDomain(
    ProductAccountDomain domain,
    Future<Object?> Function() load,
    Map<ProductAccountDomain, Object> errors,
  ) async {
    try {
      final value = await load();
      errors.remove(domain);
      return value;
    } on Object catch (error) {
      errors[domain] = error;
      return null;
    }
  }

  Future<MapEntry<ProductAccountDomain, ProductAccountDomainSyncState?>?>
  _loadSyncState(
    ProductAccountDomain domain,
    ProductLocalStore store,
    _AccountStateSessionFence fence,
    Map<ProductAccountDomain, Object> errors,
  ) async {
    try {
      final value = await store.loadDomainSyncState(
        binding: fence.binding,
        domain: domain,
      );
      return MapEntry<ProductAccountDomain, ProductAccountDomainSyncState?>(
        domain,
        value,
      );
    } on Object catch (error) {
      errors[domain] = error;
      return null;
    }
  }

  void _scheduleRetry(_AccountStateSessionFence fence) {
    if (_retryTimer != null || _disposed) {
      return;
    }
    state = AccountStateSyncCoordinatorState(
      status: AccountStateSyncCoordinatorStatus.retryWaiting,
      lastReason: state.lastReason,
      lastCompletedAt: state.lastCompletedAt,
      domainVersions: state.domainVersions,
      domainErrors: state.domainErrors,
      warnings: state.warnings,
    );
    _retryTimer = Timer(failureBackoff, () {
      _retryTimer = null;
      if (_isCurrent(fence)) {
        request('failure_retry');
      }
    });
  }

  void _handleSessionChanged(SessionState? previous, SessionState next) {
    if (previous?.generation == next.generation) {
      return;
    }
    resetForSession();
  }

  bool _isCurrent(_AccountStateSessionFence fence) =>
      !_disposed && fence.matches(ref.read(sessionProvider));

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _requestBus.detach();
    _sessionSubscription.close();
    super.dispose();
  }
}

class _AccountStateSessionFence {
  const _AccountStateSessionFence({
    required this.session,
    required this.binding,
    required this.currentDid,
    required this.protocolDeviceId,
    required this.identityGeneration,
    required this.deviceAuthGeneration,
    required this.sessionGeneration,
  });

  factory _AccountStateSessionFence.capture(SessionState state) {
    final session = state.session!;
    final binding = session.accountBinding!;
    return _AccountStateSessionFence(
      session: session,
      binding: ProductAccountBinding.fromSession(binding),
      currentDid: binding.currentDid,
      protocolDeviceId: binding.protocolDeviceId,
      identityGeneration: binding.identityGeneration,
      deviceAuthGeneration: binding.deviceAuthGeneration,
      sessionGeneration: state.generation,
    );
  }

  static _AccountStateSessionFence? captureOrNull(SessionState state) {
    final session = state.session;
    final binding = session?.accountBinding;
    if (session == null ||
        binding == null ||
        binding.ownerIdentityId.trim().isEmpty ||
        binding.accountId.trim().isEmpty ||
        binding.currentDid.trim().isEmpty ||
        binding.protocolDeviceId.trim().isEmpty ||
        !isCanonicalProductDecimal(binding.identityGeneration) ||
        !isCanonicalProductDecimal(binding.deviceAuthGeneration) ||
        session.did != binding.currentDid) {
      return null;
    }
    return _AccountStateSessionFence.capture(state);
  }

  final SessionIdentity session;
  final ProductAccountBinding binding;
  final String currentDid;
  final String protocolDeviceId;
  final String identityGeneration;
  final String deviceAuthGeneration;
  final int sessionGeneration;

  bool matches(SessionState state) {
    final next = captureOrNull(state);
    return next != null &&
        next.sessionGeneration == sessionGeneration &&
        next.binding.ownerIdentityId == binding.ownerIdentityId &&
        next.binding.accountId == binding.accountId &&
        next.currentDid == currentDid &&
        next.protocolDeviceId == protocolDeviceId &&
        next.identityGeneration == identityGeneration &&
        next.deviceAuthGeneration == deviceAuthGeneration;
  }

  bool matchesBinding(ProductAccountBinding candidate, int generation) =>
      generation == sessionGeneration &&
      candidate.ownerIdentityId == binding.ownerIdentityId &&
      candidate.accountId == binding.accountId;
}

DeviceRegistrySnapshot _deviceRegistryProjection(
  ProductDeviceRegistrySnapshot snapshot,
  _AccountStateSessionFence fence,
) {
  return DeviceRegistrySnapshot(
    did: fence.currentDid,
    registryVersion: snapshot.domainVersion,
    devices: snapshot.devices
        .map((item) {
          final payload = _jsonObject(item.payloadJson);
          return DeviceSummary(
            protocolDeviceId: item.protocolDeviceId,
            signingKeyId: _requiredString(payload, 'signing_key_id'),
            e2eeKeyId: _requiredString(payload, 'e2ee_key_id'),
            status: switch (_requiredString(payload, 'status')) {
              'active' => DeviceStatus.active,
              'revoked' => DeviceStatus.revoked,
              _ => throw const FormatException(
                'account_state_device_status_invalid',
              ),
            },
            role: switch (_requiredString(payload, 'role')) {
              'admin' => DeviceRole.admin,
              'member' => DeviceRole.member,
              _ => throw const FormatException(
                'account_state_device_role_invalid',
              ),
            },
            managementReady: _requiredBool(payload, 'management_ready'),
            isCurrent: item.protocolDeviceId == fence.protocolDeviceId,
            authGeneration: item.authGeneration,
          );
        })
        .toList(growable: false),
  );
}

Map<String, Object?> _jsonObject(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('account_state_payload_not_object');
  }
  return decoded.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

String _requiredString(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! String || item.trim().isEmpty) {
    throw FormatException('account_state_device_$key invalid');
  }
  return item;
}

bool _requiredBool(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is! bool) {
    throw FormatException('account_state_device_$key invalid');
  }
  return item;
}

final accountStateSyncCoordinatorProvider =
    StateNotifierProvider<
      AccountStateSyncCoordinator,
      AccountStateSyncCoordinatorState
    >((ref) => AccountStateSyncCoordinator(ref));
