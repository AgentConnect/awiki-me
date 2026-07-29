import 'dart:convert';

import '../../domain/entities/session_identity.dart';

class ProductConversationOverlay {
  const ProductConversationOverlay({
    required this.ownerDid,
    required this.threadId,
    required this.conversationId,
    this.pinned = false,
    this.muted = false,
    this.hidden = false,
    this.customTitle,
    this.avatarSeed,
    required this.updatedAt,
  });

  final String ownerDid;

  /// Canonical message-chain key owned by im-core.
  ///
  final String conversationId;
  final String threadId;
  final bool pinned;
  final bool muted;
  final bool hidden;
  final String? customTitle;
  final String? avatarSeed;
  final DateTime updatedAt;

  ProductConversationOverlay copyWith({
    String? threadId,
    String? conversationId,
    bool? pinned,
    bool? muted,
    bool? hidden,
    String? customTitle,
    String? avatarSeed,
    DateTime? updatedAt,
  }) {
    return ProductConversationOverlay(
      ownerDid: ownerDid,
      threadId: threadId ?? this.threadId,
      conversationId: conversationId ?? this.conversationId,
      pinned: pinned ?? this.pinned,
      muted: muted ?? this.muted,
      hidden: hidden ?? this.hidden,
      customTitle: customTitle ?? this.customTitle,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ProductConversationAliasMigration {
  const ProductConversationAliasMigration({
    required this.ownerDid,
    required this.legacyConversationId,
    required this.canonicalConversationId,
  });

  final String ownerDid;
  final String legacyConversationId;
  final String canonicalConversationId;
}

class MessageDraft {
  const MessageDraft({
    required this.ownerDid,
    required this.threadId,
    required this.draftText,
    required this.updatedAt,
  });

  final String ownerDid;
  final String threadId;
  final String draftText;
  final DateTime updatedAt;
}

class LocalUiPreference {
  const LocalUiPreference({
    required this.ownerDid,
    required this.key,
    required this.valueJson,
    required this.updatedAt,
  });

  final String ownerDid;
  final String key;
  final String valueJson;
  final DateTime updatedAt;
}

class LocalAgentState {
  const LocalAgentState({
    required this.ownerDid,
    required this.agentDid,
    required this.valueJson,
    required this.updatedAt,
  });

  final String ownerDid;
  final String agentDid;
  final String valueJson;
  final DateTime updatedAt;
}

enum ProductAccountDomain {
  profile,
  agentInventory,
  agentStatus,
  deviceRegistry;

  String get storageValue => switch (this) {
    ProductAccountDomain.profile => 'profile',
    ProductAccountDomain.agentInventory => 'agent_inventory',
    ProductAccountDomain.agentStatus => 'agent_status',
    ProductAccountDomain.deviceRegistry => 'device_registry',
  };
}

/// One-way legacy Agent seeds are display fallbacks, never remote truth.
///
/// Even when the first server manifest is version `0`, this marker forces one
/// authoritative Inventory fetch so removed legacy Agents cannot survive.
const String productLegacyAgentSeedPayloadHash =
    'legacy_agent_seed_non_authoritative_v1';

class ProductAccountBinding {
  const ProductAccountBinding({
    required this.ownerIdentityId,
    required this.accountId,
  });

  factory ProductAccountBinding.fromSession(SessionAccountBinding binding) {
    return ProductAccountBinding(
      ownerIdentityId: binding.ownerIdentityId,
      accountId: binding.accountId,
    );
  }

  final String ownerIdentityId;
  final String accountId;
}

class ProductAccountDomainSyncState {
  const ProductAccountDomainSyncState({
    required this.binding,
    required this.domain,
    required this.domainVersion,
    this.payloadHash,
    required this.refreshedAt,
  });

  final ProductAccountBinding binding;
  final ProductAccountDomain domain;
  final String domainVersion;
  final String? payloadHash;
  final DateTime refreshedAt;
}

class ProductAgentInventoryItem {
  const ProductAgentInventoryItem({
    required this.agentDid,
    required this.activeState,
    required this.payloadJson,
  });

  final String agentDid;
  final String activeState;
  final String payloadJson;
}

class ProductAgentInventorySnapshot {
  ProductAgentInventorySnapshot({
    required this.binding,
    required this.domainVersion,
    this.payloadHash,
    required this.refreshedAt,
    required Iterable<ProductAgentInventoryItem> agents,
  }) : agents = List<ProductAgentInventoryItem>.unmodifiable(agents);

  final ProductAccountBinding binding;
  final String domainVersion;
  final String? payloadHash;
  final DateTime refreshedAt;
  final List<ProductAgentInventoryItem> agents;

  ProductAccountDomainSyncState get syncState => ProductAccountDomainSyncState(
    binding: binding,
    domain: ProductAccountDomain.agentInventory,
    domainVersion: domainVersion,
    payloadHash: payloadHash,
    refreshedAt: refreshedAt,
  );
}

class ProductAgentStatusItem {
  const ProductAgentStatusItem({
    required this.agentDid,
    required this.payloadJson,
  });

  final String agentDid;
  final String payloadJson;
}

class ProductAgentStatusSnapshot {
  ProductAgentStatusSnapshot({
    required this.binding,
    required this.domainVersion,
    this.payloadHash,
    required this.refreshedAt,
    required Iterable<ProductAgentStatusItem> statuses,
  }) : statuses = List<ProductAgentStatusItem>.unmodifiable(statuses);

  final ProductAccountBinding binding;
  final String domainVersion;
  final String? payloadHash;
  final DateTime refreshedAt;
  final List<ProductAgentStatusItem> statuses;

  ProductAccountDomainSyncState get syncState => ProductAccountDomainSyncState(
    binding: binding,
    domain: ProductAccountDomain.agentStatus,
    domainVersion: domainVersion,
    payloadHash: payloadHash,
    refreshedAt: refreshedAt,
  );
}

class ProductProfileSnapshot {
  const ProductProfileSnapshot({
    required this.binding,
    required this.domainVersion,
    this.payloadHash,
    required this.refreshedAt,
    this.payloadJson,
  });

  final ProductAccountBinding binding;
  final String domainVersion;
  final String? payloadHash;
  final DateTime refreshedAt;

  /// Null represents an authoritative empty profile snapshot.
  final String? payloadJson;

  ProductAccountDomainSyncState get syncState => ProductAccountDomainSyncState(
    binding: binding,
    domain: ProductAccountDomain.profile,
    domainVersion: domainVersion,
    payloadHash: payloadHash,
    refreshedAt: refreshedAt,
  );
}

class ProductDeviceRegistryItem {
  const ProductDeviceRegistryItem({
    required this.protocolDeviceId,
    required this.authGeneration,
    required this.payloadJson,
  });

  final String protocolDeviceId;
  final String authGeneration;
  final String payloadJson;
}

class ProductDeviceRegistrySnapshot {
  ProductDeviceRegistrySnapshot({
    required this.binding,
    required this.domainVersion,
    this.payloadHash,
    required this.refreshedAt,
    required Iterable<ProductDeviceRegistryItem> devices,
  }) : devices = List<ProductDeviceRegistryItem>.unmodifiable(devices);

  final ProductAccountBinding binding;
  final String domainVersion;
  final String? payloadHash;
  final DateTime refreshedAt;
  final List<ProductDeviceRegistryItem> devices;

  ProductAccountDomainSyncState get syncState => ProductAccountDomainSyncState(
    binding: binding,
    domain: ProductAccountDomain.deviceRegistry,
    domainVersion: domainVersion,
    payloadHash: payloadHash,
    refreshedAt: refreshedAt,
  );
}

class ProductAccountBindingMismatchException implements Exception {
  const ProductAccountBindingMismatchException();

  @override
  String toString() =>
      'ProductAccountBindingMismatchException(product_account_binding_mismatch)';
}

class ProductDomainVersionRegressionException implements Exception {
  const ProductDomainVersionRegressionException();

  @override
  String toString() =>
      'ProductDomainVersionRegressionException(product_domain_version_regression)';
}

void validateProductAccountBinding(ProductAccountBinding binding) {
  _requireExactNonEmpty(binding.ownerIdentityId, 'ownerIdentityId');
  _requireExactNonEmpty(binding.accountId, 'accountId');
}

bool isCanonicalProductDecimal(String value) {
  if (value == '0') {
    return true;
  }
  if (value.isEmpty ||
      value.codeUnitAt(0) < 0x31 ||
      value.codeUnitAt(0) > 0x39) {
    return false;
  }
  for (var index = 1; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit < 0x30 || codeUnit > 0x39) {
      return false;
    }
  }
  return true;
}

int compareProductDecimalVersions(String left, String right) {
  _requireCanonicalDecimal(left, 'left');
  _requireCanonicalDecimal(right, 'right');
  return BigInt.parse(left).compareTo(BigInt.parse(right));
}

void validateProductAgentInventorySnapshot(
  ProductAgentInventorySnapshot snapshot,
) {
  validateProductAccountBinding(snapshot.binding);
  _validateSnapshotMetadata(
    snapshot.domainVersion,
    snapshot.payloadHash,
    snapshot.refreshedAt,
  );
  final agentDids = <String>{};
  for (final agent in snapshot.agents) {
    _requireExactNonEmpty(agent.agentDid, 'agentDid');
    _requireExactNonEmpty(agent.activeState, 'activeState');
    _requireJson(agent.payloadJson, 'payloadJson');
    if (!agentDids.add(agent.agentDid)) {
      throw ArgumentError.value(
        agent.agentDid,
        'agentDid',
        'must be unique within a snapshot',
      );
    }
  }
}

void validateProductAgentStatusSnapshot(ProductAgentStatusSnapshot snapshot) {
  validateProductAccountBinding(snapshot.binding);
  _validateSnapshotMetadata(
    snapshot.domainVersion,
    snapshot.payloadHash,
    snapshot.refreshedAt,
  );
  final agentDids = <String>{};
  for (final status in snapshot.statuses) {
    _requireExactNonEmpty(status.agentDid, 'agentDid');
    _requireJson(status.payloadJson, 'payloadJson');
    if (!agentDids.add(status.agentDid)) {
      throw ArgumentError.value(
        status.agentDid,
        'agentDid',
        'must be unique within a snapshot',
      );
    }
  }
}

void validateProductProfileSnapshot(ProductProfileSnapshot snapshot) {
  validateProductAccountBinding(snapshot.binding);
  _validateSnapshotMetadata(
    snapshot.domainVersion,
    snapshot.payloadHash,
    snapshot.refreshedAt,
  );
  final payloadJson = snapshot.payloadJson;
  if (payloadJson != null) {
    _requireJson(payloadJson, 'payloadJson');
  }
}

void validateProductDeviceRegistrySnapshot(
  ProductDeviceRegistrySnapshot snapshot,
) {
  validateProductAccountBinding(snapshot.binding);
  _validateSnapshotMetadata(
    snapshot.domainVersion,
    snapshot.payloadHash,
    snapshot.refreshedAt,
  );
  final deviceIds = <String>{};
  for (final device in snapshot.devices) {
    _requireExactNonEmpty(device.protocolDeviceId, 'protocolDeviceId');
    _requireCanonicalDecimal(device.authGeneration, 'authGeneration');
    _requireJson(device.payloadJson, 'payloadJson');
    if (!deviceIds.add(device.protocolDeviceId)) {
      throw ArgumentError.value(
        device.protocolDeviceId,
        'protocolDeviceId',
        'must be unique within a snapshot',
      );
    }
  }
}

void _validateSnapshotMetadata(
  String domainVersion,
  String? payloadHash,
  DateTime refreshedAt,
) {
  _requireCanonicalDecimal(domainVersion, 'domainVersion');
  if (payloadHash != null) {
    _requireExactNonEmpty(payloadHash, 'payloadHash');
  }
  if (refreshedAt.toUtc().millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(
      refreshedAt,
      'refreshedAt',
      'must not be before the Unix epoch',
    );
  }
}

void _requireCanonicalDecimal(String value, String name) {
  if (!isCanonicalProductDecimal(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a canonical non-negative decimal string',
    );
  }
}

void _requireExactNonEmpty(String value, String name) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(
      value,
      name,
      'must be non-empty and contain no surrounding whitespace',
    );
  }
}

void _requireJson(String value, String name) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(
      value,
      name,
      'must be non-empty JSON without surrounding whitespace',
    );
  }
  try {
    jsonDecode(value);
  } on FormatException {
    throw ArgumentError.value(value, name, 'must be valid JSON');
  }
}
