import 'dart:convert';

import '../../application/models/product_local_models.dart';
import '../../application/product_local_store.dart';

class InMemoryAwikiProductLocalStore implements ProductLocalStore {
  final Map<String, ProductConversationOverlay> _overlays =
      <String, ProductConversationOverlay>{};
  final Map<String, MessageDraft> _drafts = <String, MessageDraft>{};
  final Map<String, LocalUiPreference> _preferences =
      <String, LocalUiPreference>{};
  final Map<String, LocalAgentState> _agentStates = <String, LocalAgentState>{};
  final Map<String, String> _accountIdsByOwnerIdentity = <String, String>{};
  final Map<String, ProductAgentInventorySnapshot> _agentInventorySnapshots =
      <String, ProductAgentInventorySnapshot>{};
  final Map<String, ProductAgentStatusSnapshot> _agentStatusSnapshots =
      <String, ProductAgentStatusSnapshot>{};
  final Map<String, ProductProfileSnapshot> _profileSnapshots =
      <String, ProductProfileSnapshot>{};
  final Map<String, ProductDeviceRegistrySnapshot> _deviceRegistrySnapshots =
      <String, ProductDeviceRegistrySnapshot>{};

  @override
  Future<void> warmUp() async {}

  @override
  Future<ProductConversationOverlay?> loadConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    return _overlays[_compoundKey(ownerDid, threadId)] ??
        _firstOverlayWhere(
          (overlay) =>
              overlay.ownerDid == ownerDid && overlay.threadId == threadId,
        );
  }

  @override
  Future<ProductConversationOverlay?> loadConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
  }) async {
    return _overlays[_compoundKey(ownerDid, conversationId)] ??
        _firstOverlayWhere(
          (overlay) =>
              overlay.ownerDid == ownerDid &&
              overlay.conversationId == conversationId,
        );
  }

  @override
  Future<Map<String, ProductConversationOverlay>> loadConversationOverlays({
    required String ownerDid,
    Iterable<String>? threadIds,
  }) async {
    final allowed = threadIds?.toSet();
    return Map<String, ProductConversationOverlay>.fromEntries(
      _overlays.values
          .where((overlay) => overlay.ownerDid == ownerDid)
          .where(
            (overlay) => allowed == null || allowed.contains(overlay.threadId),
          )
          .map((overlay) => MapEntry(overlay.threadId, overlay)),
    );
  }

  @override
  Future<Map<String, ProductConversationOverlay>>
  loadConversationOverlaysByConversationId({
    required String ownerDid,
    Iterable<String>? conversationIds,
  }) async {
    final allowed = conversationIds?.toSet();
    if (allowed != null && allowed.isEmpty) {
      return const <String, ProductConversationOverlay>{};
    }
    final result = <String, ProductConversationOverlay>{};
    for (final overlay in _overlays.values) {
      if (overlay.ownerDid != ownerDid) {
        continue;
      }
      final conversationId = overlay.conversationId;
      if (allowed != null && !allowed.contains(conversationId)) {
        continue;
      }
      final existing = result[conversationId];
      if (existing == null || _preferConversationOverlay(overlay, existing)) {
        result[conversationId] = overlay;
      }
    }
    return result;
  }

  @override
  Future<void> upsertConversationOverlay(
    ProductConversationOverlay overlay,
  ) async {
    _overlays[_compoundKey(overlay.ownerDid, overlay.threadId)] = overlay;
  }

  @override
  Future<void> upsertConversationOverlayByConversationId(
    ProductConversationOverlay overlay,
  ) async {
    final conversationId = overlay.conversationId;
    _overlays[_compoundKey(overlay.ownerDid, conversationId)] = overlay
        .copyWith(threadId: conversationId, conversationId: conversationId);
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    await setConversationHidden(
      ownerDid: ownerDid,
      conversationKey: threadId,
      hidden: hidden,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> setConversationHidden({
    required String ownerDid,
    required String conversationKey,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final key = _compoundKey(ownerDid, conversationKey);
    final existing = _overlays[key];
    _overlays[key] =
        (existing ??
                ProductConversationOverlay(
                  ownerDid: ownerDid,
                  threadId: conversationKey,
                  conversationId: conversationKey,
                  updatedAt: updatedAt,
                ))
            .copyWith(hidden: hidden, updatedAt: updatedAt);
  }

  @override
  Future<void> setConversationHiddenByConversationId({
    required String ownerDid,
    required String conversationId,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final key = _compoundKey(ownerDid, conversationId);
    final existing = _overlays[key];
    _overlays[key] =
        (existing ??
                ProductConversationOverlay(
                  ownerDid: ownerDid,
                  threadId: conversationId,
                  conversationId: conversationId,
                  updatedAt: updatedAt,
                ))
            .copyWith(
              threadId: conversationId,
              conversationId: conversationId,
              hidden: hidden,
              updatedAt: updatedAt,
            );
  }

  @override
  Future<void> deleteConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    _overlays.remove(_compoundKey(ownerDid, threadId));
    _overlays.removeWhere(
      (_, overlay) =>
          overlay.ownerDid == ownerDid && overlay.threadId == threadId,
    );
  }

  @override
  Future<void> deleteConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
  }) async {
    _overlays.remove(_compoundKey(ownerDid, conversationId));
    _overlays.removeWhere(
      (_, overlay) =>
          overlay.ownerDid == ownerDid &&
          overlay.conversationId == conversationId,
    );
  }

  @override
  Future<MessageDraft?> loadDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    return _drafts[_compoundKey(ownerDid, threadId)];
  }

  @override
  Future<void> saveDraft(MessageDraft draft) async {
    _drafts[_compoundKey(draft.ownerDid, draft.threadId)] = draft;
  }

  @override
  Future<void> deleteDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    _drafts.remove(_compoundKey(ownerDid, threadId));
  }

  @override
  Future<LocalUiPreference?> loadUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    return _preferences[_compoundKey(ownerDid, key)];
  }

  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    _preferences[_compoundKey(preference.ownerDid, preference.key)] =
        preference;
  }

  @override
  Future<void> deleteUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    _preferences.remove(_compoundKey(ownerDid, key));
  }

  @override
  Future<List<LocalAgentState>> loadAgentStates({
    required String ownerDid,
  }) async {
    return _agentStates.values
        .where((state) => state.ownerDid == ownerDid)
        .toList();
  }

  @override
  Future<void> saveAgentState(LocalAgentState state) async {
    _agentStates[_compoundKey(state.ownerDid, state.agentDid)] = state;
  }

  @override
  Future<void> deleteAgentState({
    required String ownerDid,
    required String agentDid,
  }) async {
    _agentStates.remove(_compoundKey(ownerDid, agentDid));
  }

  @override
  Future<ProductAccountDomainSyncState?> loadDomainSyncState({
    required ProductAccountBinding binding,
    required ProductAccountDomain domain,
  }) async {
    validateProductAccountBinding(binding);
    _assertAccountBinding(binding);
    return _domainSyncState(binding, domain);
  }

  @override
  Future<Map<ProductAccountDomain, ProductAccountDomainSyncState>>
  loadDomainSyncStates({required ProductAccountBinding binding}) async {
    validateProductAccountBinding(binding);
    _assertAccountBinding(binding);
    return <ProductAccountDomain, ProductAccountDomainSyncState>{
      for (final domain in ProductAccountDomain.values)
        if (_domainSyncState(binding, domain) case final state?) domain: state,
    };
  }

  @override
  Future<ProductAgentInventorySnapshot?> loadAgentInventorySnapshot({
    required ProductAccountBinding binding,
    String? legacyOwnerDid,
  }) async {
    validateProductAccountBinding(binding);
    _assertAccountBinding(binding);
    final existing = _agentInventorySnapshots[binding.ownerIdentityId];
    if (existing != null) {
      return _copyAgentInventorySnapshot(existing);
    }
    if (legacyOwnerDid == null) {
      return null;
    }
    _requireLegacyOwnerDid(legacyOwnerDid);
    final legacy = _agentStates.values
        .where((state) => state.ownerDid == legacyOwnerDid)
        .toList(growable: false);
    final snapshot = ProductAgentInventorySnapshot(
      binding: binding,
      domainVersion: '0',
      payloadHash: productLegacyAgentSeedPayloadHash,
      refreshedAt: _legacyRefreshedAt(legacy.map((state) => state.updatedAt)),
      agents: legacy.map(
        (state) => ProductAgentInventoryItem(
          agentDid: state.agentDid,
          activeState: _legacyAgentActiveState(state.valueJson),
          payloadJson: state.valueJson,
        ),
      ),
    );
    validateProductAgentInventorySnapshot(snapshot);
    _claimAccountBinding(binding);
    _agentInventorySnapshots[binding.ownerIdentityId] =
        _copyAgentInventorySnapshot(snapshot);
    return _copyAgentInventorySnapshot(snapshot);
  }

  @override
  Future<void> replaceAgentInventorySnapshot(
    ProductAgentInventorySnapshot snapshot,
  ) async {
    validateProductAgentInventorySnapshot(snapshot);
    _assertAccountBinding(snapshot.binding);
    _assertNonRegressingVersion(
      snapshot.domainVersion,
      _agentInventorySnapshots[snapshot.binding.ownerIdentityId]?.domainVersion,
    );
    final replacement = _copyAgentInventorySnapshot(snapshot);
    _claimAccountBinding(snapshot.binding);
    _agentInventorySnapshots[snapshot.binding.ownerIdentityId] = replacement;
  }

  @override
  Future<ProductAgentStatusSnapshot?> loadAgentStatusSnapshot({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    _assertAccountBinding(binding);
    final snapshot = _agentStatusSnapshots[binding.ownerIdentityId];
    return snapshot == null ? null : _copyAgentStatusSnapshot(snapshot);
  }

  @override
  Future<void> replaceAgentStatusSnapshot(
    ProductAgentStatusSnapshot snapshot,
  ) async {
    validateProductAgentStatusSnapshot(snapshot);
    _assertAccountBinding(snapshot.binding);
    _assertNonRegressingVersion(
      snapshot.domainVersion,
      _agentStatusSnapshots[snapshot.binding.ownerIdentityId]?.domainVersion,
    );
    final replacement = _copyAgentStatusSnapshot(snapshot);
    _claimAccountBinding(snapshot.binding);
    _agentStatusSnapshots[snapshot.binding.ownerIdentityId] = replacement;
  }

  @override
  Future<ProductProfileSnapshot?> loadProfileSnapshot({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    _assertAccountBinding(binding);
    final snapshot = _profileSnapshots[binding.ownerIdentityId];
    return snapshot == null ? null : _copyProfileSnapshot(snapshot);
  }

  @override
  Future<void> replaceProfileSnapshot(ProductProfileSnapshot snapshot) async {
    validateProductProfileSnapshot(snapshot);
    _assertAccountBinding(snapshot.binding);
    _assertNonRegressingVersion(
      snapshot.domainVersion,
      _profileSnapshots[snapshot.binding.ownerIdentityId]?.domainVersion,
    );
    final replacement = _copyProfileSnapshot(snapshot);
    _claimAccountBinding(snapshot.binding);
    _profileSnapshots[snapshot.binding.ownerIdentityId] = replacement;
  }

  @override
  Future<ProductDeviceRegistrySnapshot?> loadDeviceRegistrySnapshot({
    required ProductAccountBinding binding,
  }) async {
    validateProductAccountBinding(binding);
    _assertAccountBinding(binding);
    final snapshot = _deviceRegistrySnapshots[binding.ownerIdentityId];
    return snapshot == null ? null : _copyDeviceRegistrySnapshot(snapshot);
  }

  @override
  Future<void> replaceDeviceRegistrySnapshot(
    ProductDeviceRegistrySnapshot snapshot,
  ) async {
    validateProductDeviceRegistrySnapshot(snapshot);
    _assertAccountBinding(snapshot.binding);
    _assertNonRegressingVersion(
      snapshot.domainVersion,
      _deviceRegistrySnapshots[snapshot.binding.ownerIdentityId]?.domainVersion,
    );
    final replacement = _copyDeviceRegistrySnapshot(snapshot);
    _claimAccountBinding(snapshot.binding);
    _deviceRegistrySnapshots[snapshot.binding.ownerIdentityId] = replacement;
  }

  void _assertAccountBinding(ProductAccountBinding binding) {
    final existing = _accountIdsByOwnerIdentity[binding.ownerIdentityId];
    if (existing != null && existing != binding.accountId) {
      throw const ProductAccountBindingMismatchException();
    }
  }

  void _claimAccountBinding(ProductAccountBinding binding) {
    _accountIdsByOwnerIdentity[binding.ownerIdentityId] = binding.accountId;
  }

  ProductAccountDomainSyncState? _domainSyncState(
    ProductAccountBinding binding,
    ProductAccountDomain domain,
  ) {
    return switch (domain) {
      ProductAccountDomain.agentInventory =>
        _agentInventorySnapshots[binding.ownerIdentityId]?.syncState,
      ProductAccountDomain.agentStatus =>
        _agentStatusSnapshots[binding.ownerIdentityId]?.syncState,
      ProductAccountDomain.profile =>
        _profileSnapshots[binding.ownerIdentityId]?.syncState,
      ProductAccountDomain.deviceRegistry =>
        _deviceRegistrySnapshots[binding.ownerIdentityId]?.syncState,
    };
  }

  ProductConversationOverlay? _firstOverlayWhere(
    bool Function(ProductConversationOverlay overlay) test,
  ) {
    for (final overlay in _overlays.values) {
      if (test(overlay)) {
        return overlay;
      }
    }
    return null;
  }
}

String _compoundKey(String ownerDid, String id) => '$ownerDid\u0000$id';

void _assertNonRegressingVersion(String incoming, String? existing) {
  if (existing != null &&
      compareProductDecimalVersions(incoming, existing) < 0) {
    throw const ProductDomainVersionRegressionException();
  }
}

void _requireLegacyOwnerDid(String value) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(
      value,
      'legacyOwnerDid',
      'must be non-empty and contain no surrounding whitespace',
    );
  }
}

DateTime _legacyRefreshedAt(Iterable<DateTime> values) {
  var latest = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  for (final value in values) {
    final utc = value.toUtc();
    if (utc.isAfter(latest)) {
      latest = utc;
    }
  }
  return latest;
}

String _legacyAgentActiveState(String valueJson) {
  try {
    final value = jsonDecode(valueJson);
    if (value is Map) {
      final activeState = value['active_state']?.toString();
      if (activeState != null &&
          activeState.isNotEmpty &&
          activeState.trim() == activeState) {
        return activeState;
      }
    }
  } on FormatException {
    // Snapshot validation below reports malformed legacy payloads without
    // partially claiming the stable account binding.
  }
  return 'legacy_unknown';
}

ProductAgentInventorySnapshot _copyAgentInventorySnapshot(
  ProductAgentInventorySnapshot snapshot,
) {
  final agents = snapshot.agents.toList(growable: false)
    ..sort((left, right) => left.agentDid.compareTo(right.agentDid));
  return ProductAgentInventorySnapshot(
    binding: snapshot.binding,
    domainVersion: snapshot.domainVersion,
    payloadHash: snapshot.payloadHash,
    refreshedAt: snapshot.refreshedAt,
    agents: agents,
  );
}

ProductAgentStatusSnapshot _copyAgentStatusSnapshot(
  ProductAgentStatusSnapshot snapshot,
) {
  final statuses = snapshot.statuses.toList(growable: false)
    ..sort((left, right) => left.agentDid.compareTo(right.agentDid));
  return ProductAgentStatusSnapshot(
    binding: snapshot.binding,
    domainVersion: snapshot.domainVersion,
    payloadHash: snapshot.payloadHash,
    refreshedAt: snapshot.refreshedAt,
    statuses: statuses,
  );
}

ProductProfileSnapshot _copyProfileSnapshot(ProductProfileSnapshot snapshot) {
  return ProductProfileSnapshot(
    binding: snapshot.binding,
    domainVersion: snapshot.domainVersion,
    payloadHash: snapshot.payloadHash,
    refreshedAt: snapshot.refreshedAt,
    payloadJson: snapshot.payloadJson,
  );
}

ProductDeviceRegistrySnapshot _copyDeviceRegistrySnapshot(
  ProductDeviceRegistrySnapshot snapshot,
) {
  final devices = snapshot.devices.toList(growable: false)
    ..sort(
      (left, right) => left.protocolDeviceId.compareTo(right.protocolDeviceId),
    );
  return ProductDeviceRegistrySnapshot(
    binding: snapshot.binding,
    domainVersion: snapshot.domainVersion,
    payloadHash: snapshot.payloadHash,
    refreshedAt: snapshot.refreshedAt,
    devices: devices,
  );
}

bool _preferConversationOverlay(
  ProductConversationOverlay candidate,
  ProductConversationOverlay existing,
) {
  final candidateIsCanonical =
      candidate.threadId.trim() == candidate.conversationId;
  final existingIsCanonical =
      existing.threadId.trim() == existing.conversationId;
  if (candidateIsCanonical != existingIsCanonical) {
    return candidateIsCanonical;
  }
  return candidate.updatedAt.isAfter(existing.updatedAt);
}
