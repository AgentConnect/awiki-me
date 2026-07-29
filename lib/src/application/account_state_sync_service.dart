import 'dart:collection';
import 'dart:convert';

import 'models/product_local_models.dart';
import 'ports/account_state_sync_port.dart';
import 'product_local_store.dart';

typedef AccountStateSessionValidator =
    bool Function(ProductAccountBinding binding, int sessionGeneration);

class AccountStateSyncService {
  AccountStateSyncService({
    required AccountStateSyncPort remote,
    required ProductLocalStore local,
    DateTime Function()? clock,
  }) : _remote = remote,
       _local = local,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AccountStateSyncPort _remote;
  final ProductLocalStore _local;
  final DateTime Function() _clock;

  Future<AccountStateReconcileResult> reconcile({
    required ProductAccountBinding binding,
    required String expectedCurrentDid,
    required String expectedIdentityGeneration,
    required int sessionGeneration,
    required AccountStateSessionValidator isSessionCurrent,
  }) async {
    validateProductAccountBinding(binding);
    if (expectedCurrentDid.isEmpty ||
        expectedCurrentDid.trim() != expectedCurrentDid) {
      throw ArgumentError.value(
        expectedCurrentDid,
        'expectedCurrentDid',
        'must be a non-empty normalized DID',
      );
    }
    if (!isCanonicalProductDecimal(expectedIdentityGeneration)) {
      throw ArgumentError.value(
        expectedIdentityGeneration,
        'expectedIdentityGeneration',
        'must be a canonical decimal string',
      );
    }
    if (sessionGeneration < 0) {
      throw ArgumentError.value(
        sessionGeneration,
        'sessionGeneration',
        'must be non-negative',
      );
    }
    final accumulator = _ReconcileAccumulator();
    if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
      return accumulator.result(sessionInvalidated: true);
    }

    final firstManifest = await _remote.loadManifest();
    if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
      return accumulator.result(sessionInvalidated: true);
    }
    _validateManifest(
      firstManifest,
      binding,
      expectedCurrentDid,
      expectedIdentityGeneration,
    );

    final initialStates = await _loadDomainStatesIsolated(binding, accumulator);
    if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
      return accumulator.result(sessionInvalidated: true);
    }

    await Future.wait<void>([
      for (final domain in ProductAccountDomain.values)
        _reconcileDomainIfNeeded(
          domain: domain,
          binding: binding,
          sessionGeneration: sessionGeneration,
          isSessionCurrent: isSessionCurrent,
          manifest: firstManifest,
          localState: initialStates[domain],
          accumulator: accumulator,
        ),
    ]);
    if (accumulator.sessionInvalidated ||
        !_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
      return accumulator.result(sessionInvalidated: true);
    }

    final secondManifest = await _remote.loadManifest();
    if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
      return accumulator.result(sessionInvalidated: true);
    }
    _validateManifest(
      secondManifest,
      binding,
      expectedCurrentDid,
      expectedIdentityGeneration,
    );

    final secondPassDomains = <ProductAccountDomain>[
      for (final domain in ProductAccountDomain.values)
        if (compareProductDecimalVersions(
              secondManifest.versionFor(domain),
              firstManifest.versionFor(domain),
            ) >
            0)
          domain,
    ];
    if (secondPassDomains.isNotEmpty) {
      final currentStates = await _loadDomainStatesIsolated(
        binding,
        accumulator,
      );
      if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
        return accumulator.result(sessionInvalidated: true);
      }
      await Future.wait<void>([
        for (final domain in secondPassDomains)
          _reconcileDomainIfNeeded(
            domain: domain,
            binding: binding,
            sessionGeneration: sessionGeneration,
            isSessionCurrent: isSessionCurrent,
            manifest: secondManifest,
            localState: currentStates[domain],
            accumulator: accumulator,
          ),
      ]);
    }

    return accumulator.result(
      sessionInvalidated:
          accumulator.sessionInvalidated ||
          !_isCurrent(binding, sessionGeneration, isSessionCurrent),
    );
  }

  Future<Map<ProductAccountDomain, ProductAccountDomainSyncState>>
  _loadDomainStatesIsolated(
    ProductAccountBinding binding,
    _ReconcileAccumulator accumulator,
  ) async {
    final entries =
        await Future.wait<
          MapEntry<ProductAccountDomain, ProductAccountDomainSyncState?>?
        >([
          for (final domain in ProductAccountDomain.values)
            _loadDomainStateIsolated(binding, domain, accumulator),
        ]);
    return <ProductAccountDomain, ProductAccountDomainSyncState>{
      for (final entry in entries)
        if (entry != null && entry.value != null) entry.key: entry.value!,
    };
  }

  Future<MapEntry<ProductAccountDomain, ProductAccountDomainSyncState?>?>
  _loadDomainStateIsolated(
    ProductAccountBinding binding,
    ProductAccountDomain domain,
    _ReconcileAccumulator accumulator,
  ) async {
    try {
      return MapEntry<ProductAccountDomain, ProductAccountDomainSyncState?>(
        domain,
        await _local.loadDomainSyncState(binding: binding, domain: domain),
      );
    } on Object catch (error) {
      accumulator.failures[domain] = error;
      return null;
    }
  }

  Future<void> _reconcileDomainIfNeeded({
    required ProductAccountDomain domain,
    required ProductAccountBinding binding,
    required int sessionGeneration,
    required AccountStateSessionValidator isSessionCurrent,
    required AccountStateManifest manifest,
    required ProductAccountDomainSyncState? localState,
    required _ReconcileAccumulator accumulator,
  }) async {
    if (accumulator.sessionInvalidated) {
      return;
    }
    final remoteVersion = manifest.versionFor(domain);
    final localVersion = localState?.domainVersion;
    final isNonAuthoritativeLegacySeed =
        domain == ProductAccountDomain.agentInventory &&
        localState?.payloadHash == productLegacyAgentSeedPayloadHash;
    if (localVersion != null && !isNonAuthoritativeLegacySeed) {
      final comparison = compareProductDecimalVersions(
        remoteVersion,
        localVersion,
      );
      if (comparison < 0) {
        accumulator.warn(
          domain,
          AccountStateSyncWarningCode.manifestVersionRegressed,
          localVersion: localVersion,
          remoteVersion: remoteVersion,
        );
        return;
      }
      if (comparison == 0) {
        accumulator.unchanged.add(domain);
        return;
      }
    }

    try {
      final snapshot = await _fetchDomain(domain);
      if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
        accumulator.sessionInvalidated = true;
        return;
      }
      final snapshotVersion = _snapshotVersion(snapshot);
      final snapshotAccountId = _snapshotAccountId(snapshot);
      if (snapshotAccountId != null && snapshotAccountId != binding.accountId) {
        throw const AccountStateSyncProtocolException(
          'account_state_snapshot_account_mismatch',
        );
      }
      if (snapshot is AccountStateDeviceRegistrySnapshot &&
          snapshot.did != manifest.currentDid) {
        throw const AccountStateSyncProtocolException(
          'account_state_registry_did_mismatch',
        );
      }
      if (snapshot is AccountStateDeviceRegistrySnapshot &&
          snapshot.devices.isEmpty) {
        throw const AccountStateSyncProtocolException(
          'account_state_registry_empty',
        );
      }

      final currentState = await _local.loadDomainSyncState(
        binding: binding,
        domain: domain,
      );
      if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
        accumulator.sessionInvalidated = true;
        return;
      }
      final currentVersion = currentState?.domainVersion;
      final currentIsNonAuthoritativeLegacySeed =
          domain == ProductAccountDomain.agentInventory &&
          currentState?.payloadHash == productLegacyAgentSeedPayloadHash;
      if (currentVersion != null && !currentIsNonAuthoritativeLegacySeed) {
        final comparison = compareProductDecimalVersions(
          snapshotVersion,
          currentVersion,
        );
        if (comparison < 0) {
          accumulator.warn(
            domain,
            AccountStateSyncWarningCode.snapshotVersionRegressed,
            localVersion: currentVersion,
            remoteVersion: snapshotVersion,
          );
          return;
        }
        if (comparison == 0) {
          accumulator.unchanged.add(domain);
          return;
        }
      }

      final manifestComparison = compareProductDecimalVersions(
        snapshotVersion,
        remoteVersion,
      );
      if (manifestComparison < 0) {
        accumulator.warn(
          domain,
          AccountStateSyncWarningCode.snapshotOlderThanManifest,
          localVersion: currentVersion,
          remoteVersion: snapshotVersion,
        );
        return;
      }
      await _commitDomain(binding, domain, snapshot);
      if (!_isCurrent(binding, sessionGeneration, isSessionCurrent)) {
        accumulator.sessionInvalidated = true;
        return;
      }
      accumulator.committed.add(domain);
      accumulator.failures.remove(domain);
    } on Object catch (error) {
      accumulator.failures[domain] = error;
    }
  }

  Future<Object> _fetchDomain(ProductAccountDomain domain) {
    return switch (domain) {
      ProductAccountDomain.agentInventory => _remote.loadAgentInventory(),
      ProductAccountDomain.agentStatus => _remote.loadAgentStatus(),
      ProductAccountDomain.profile => _remote.loadProfile(),
      ProductAccountDomain.deviceRegistry => _remote.loadDeviceRegistry(),
    };
  }

  Future<void> _commitDomain(
    ProductAccountBinding binding,
    ProductAccountDomain domain,
    Object snapshot,
  ) {
    final refreshedAt = _clock().toUtc();
    return switch ((domain, snapshot)) {
      (
        ProductAccountDomain.agentInventory,
        AccountStateAgentInventorySnapshot value,
      ) =>
        _local.replaceAgentInventorySnapshot(
          ProductAgentInventorySnapshot(
            binding: binding,
            domainVersion: value.inventoryVersion,
            refreshedAt: refreshedAt,
            agents: value.agents.map(
              (agent) => ProductAgentInventoryItem(
                agentDid: agent.agentDid,
                activeState: agent.activeState,
                payloadJson: jsonEncode(agent.toJson()),
              ),
            ),
          ),
        ),
      (
        ProductAccountDomain.agentStatus,
        AccountStateAgentStatusSnapshot value,
      ) =>
        _local.replaceAgentStatusSnapshot(
          ProductAgentStatusSnapshot(
            binding: binding,
            domainVersion: value.agentStatusVersion,
            refreshedAt: refreshedAt,
            statuses: value.statuses.map(
              (status) => ProductAgentStatusItem(
                agentDid: status.agentDid,
                payloadJson: jsonEncode(status.toJson()),
              ),
            ),
          ),
        ),
      (ProductAccountDomain.profile, AccountStateProfileSnapshot value) =>
        _local.replaceProfileSnapshot(
          ProductProfileSnapshot(
            binding: binding,
            domainVersion: value.profileVersion,
            refreshedAt: refreshedAt,
            payloadJson: jsonEncode(value.profile.toJson()),
          ),
        ),
      (
        ProductAccountDomain.deviceRegistry,
        AccountStateDeviceRegistrySnapshot value,
      ) =>
        _local.replaceDeviceRegistrySnapshot(
          ProductDeviceRegistrySnapshot(
            binding: binding,
            domainVersion: value.registryVersion,
            refreshedAt: refreshedAt,
            devices: value.devices.map(
              (device) => ProductDeviceRegistryItem(
                protocolDeviceId: device.protocolDeviceId,
                authGeneration: device.authGeneration,
                payloadJson: jsonEncode(device.toJson()),
              ),
            ),
          ),
        ),
      _ => throw StateError('account_state_snapshot_domain_mismatch'),
    };
  }
}

class AccountStateReconcileResult {
  AccountStateReconcileResult({
    required Set<ProductAccountDomain> committedDomains,
    required Set<ProductAccountDomain> unchangedDomains,
    required List<AccountStateSyncWarning> warnings,
    required Map<ProductAccountDomain, Object> failures,
    required this.sessionInvalidated,
  }) : committedDomains = UnmodifiableSetView<ProductAccountDomain>(
         committedDomains,
       ),
       unchangedDomains = UnmodifiableSetView<ProductAccountDomain>(
         unchangedDomains,
       ),
       warnings = List<AccountStateSyncWarning>.unmodifiable(warnings),
       failures = UnmodifiableMapView<ProductAccountDomain, Object>(failures);

  final Set<ProductAccountDomain> committedDomains;
  final Set<ProductAccountDomain> unchangedDomains;
  final List<AccountStateSyncWarning> warnings;
  final Map<ProductAccountDomain, Object> failures;
  final bool sessionInvalidated;
}

enum AccountStateSyncWarningCode {
  manifestVersionRegressed,
  snapshotVersionRegressed,
  snapshotOlderThanManifest,
}

class AccountStateSyncWarning {
  const AccountStateSyncWarning({
    required this.domain,
    required this.code,
    this.localVersion,
    required this.remoteVersion,
  });

  final ProductAccountDomain domain;
  final AccountStateSyncWarningCode code;
  final String? localVersion;
  final String remoteVersion;
}

class AccountStateSyncProtocolException implements Exception {
  const AccountStateSyncProtocolException(this.code);

  final String code;

  @override
  String toString() => code;
}

class _ReconcileAccumulator {
  final Set<ProductAccountDomain> committed = <ProductAccountDomain>{};
  final Set<ProductAccountDomain> unchanged = <ProductAccountDomain>{};
  final List<AccountStateSyncWarning> warnings = <AccountStateSyncWarning>[];
  final Map<ProductAccountDomain, Object> failures =
      <ProductAccountDomain, Object>{};
  bool sessionInvalidated = false;

  void warn(
    ProductAccountDomain domain,
    AccountStateSyncWarningCode code, {
    String? localVersion,
    required String remoteVersion,
  }) {
    warnings.add(
      AccountStateSyncWarning(
        domain: domain,
        code: code,
        localVersion: localVersion,
        remoteVersion: remoteVersion,
      ),
    );
  }

  AccountStateReconcileResult result({required bool sessionInvalidated}) {
    return AccountStateReconcileResult(
      committedDomains: Set<ProductAccountDomain>.from(committed),
      unchangedDomains: Set<ProductAccountDomain>.from(unchanged),
      warnings: List<AccountStateSyncWarning>.from(warnings),
      failures: Map<ProductAccountDomain, Object>.from(failures),
      sessionInvalidated: sessionInvalidated,
    );
  }
}

bool _isCurrent(
  ProductAccountBinding binding,
  int sessionGeneration,
  AccountStateSessionValidator validator,
) {
  return validator(binding, sessionGeneration);
}

void _validateManifest(
  AccountStateManifest manifest,
  ProductAccountBinding binding,
  String expectedCurrentDid,
  String expectedIdentityGeneration,
) {
  if (manifest.accountId != binding.accountId) {
    throw const AccountStateSyncProtocolException(
      'account_state_manifest_account_mismatch',
    );
  }
  if (manifest.currentDid != expectedCurrentDid) {
    throw const AccountStateSyncProtocolException(
      'account_state_manifest_did_mismatch',
    );
  }
  if (!isCanonicalProductDecimal(manifest.identityGeneration)) {
    throw const AccountStateSyncProtocolException(
      'account_state_manifest_identity_generation_invalid',
    );
  }
  if (manifest.identityGeneration != expectedIdentityGeneration) {
    throw const AccountStateSyncProtocolException(
      'account_state_manifest_identity_generation_mismatch',
    );
  }
  for (final domain in ProductAccountDomain.values) {
    final version = manifest.versions[domain];
    if (version == null || !isCanonicalProductDecimal(version)) {
      throw const AccountStateSyncProtocolException(
        'account_state_manifest_domain_version_invalid',
      );
    }
  }
}

String _snapshotVersion(Object snapshot) {
  return switch (snapshot) {
    AccountStateAgentInventorySnapshot value => value.inventoryVersion,
    AccountStateAgentStatusSnapshot value => value.agentStatusVersion,
    AccountStateProfileSnapshot value => value.profileVersion,
    AccountStateDeviceRegistrySnapshot value => value.registryVersion,
    _ => throw StateError('account_state_snapshot_type_invalid'),
  };
}

String? _snapshotAccountId(Object snapshot) {
  return switch (snapshot) {
    AccountStateAgentInventorySnapshot value => value.accountId,
    AccountStateAgentStatusSnapshot value => value.accountId,
    AccountStateProfileSnapshot value => value.accountId,
    AccountStateDeviceRegistrySnapshot _ => null,
    _ => throw StateError('account_state_snapshot_type_invalid'),
  };
}
