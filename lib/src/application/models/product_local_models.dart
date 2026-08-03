import 'dart:convert';

import '../../domain/entities/session_identity.dart';
import '../../domain/entities/device_management.dart';

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

class ProductDeviceRegistryEpoch {
  const ProductDeviceRegistryEpoch({
    required this.currentDid,
    required this.bindingGeneration,
  });

  final String currentDid;
  final String bindingGeneration;

  bool matches(ProductDeviceRegistryEpoch other) =>
      currentDid == other.currentDid &&
      bindingGeneration == other.bindingGeneration;
}

class ProductDeviceRegistryEpochResetReference {
  const ProductDeviceRegistryEpochResetReference({
    required this.accountUserId,
    required this.ownerIdentityId,
    required this.previousDid,
    required this.currentDid,
    required this.bindingGeneration,
  });

  final String accountUserId;
  final String ownerIdentityId;
  final String previousDid;
  final String currentDid;
  final String bindingGeneration;

  ProductAccountBinding get binding => ProductAccountBinding(
    ownerIdentityId: ownerIdentityId,
    accountId: accountUserId,
  );

  ProductDeviceRegistryEpoch get targetEpoch => ProductDeviceRegistryEpoch(
    currentDid: currentDid,
    bindingGeneration: bindingGeneration,
  );

  bool matches(ProductDeviceRegistryEpochResetReference other) =>
      accountUserId == other.accountUserId &&
      ownerIdentityId == other.ownerIdentityId &&
      previousDid == other.previousDid &&
      currentDid == other.currentDid &&
      bindingGeneration == other.bindingGeneration;
}

enum ProductIdentityTransitionSourceKind { initiator, joinedDevice }

String productIdentityTransitionSourceKindWireName(
  ProductIdentityTransitionSourceKind sourceKind,
) => switch (sourceKind) {
  ProductIdentityTransitionSourceKind.initiator => 'initiator',
  ProductIdentityTransitionSourceKind.joinedDevice => 'joined_device',
};

class ProductDeviceRegistryEpochResetAuthorization {
  const ProductDeviceRegistryEpochResetAuthorization({
    required this.reference,
    required this.handle,
    required this.sourceKind,
    required this.sourceId,
  });

  final ProductDeviceRegistryEpochResetReference reference;
  final String handle;
  final ProductIdentityTransitionSourceKind sourceKind;
  final String sourceId;

  bool matches(ProductDeviceRegistryEpochResetAuthorization other) =>
      reference.matches(other.reference) &&
      handle == other.handle &&
      sourceKind == other.sourceKind &&
      sourceId == other.sourceId;
}

class ProductDeviceRegistryEpochResetReceipt {
  const ProductDeviceRegistryEpochResetReceipt({
    required this.authorization,
    required this.appliedAt,
  });

  final ProductDeviceRegistryEpochResetAuthorization authorization;
  final DateTime appliedAt;

  ProductDeviceRegistryEpochResetReference get reference =>
      authorization.reference;
}

/// Secret-free host locator for reopening the Core-owned Handle Recovery
/// state machine. Phone numbers, OTPs, grants, proofs, phases, and key
/// material must never be added to this projection.
class ProductHandleRecoveryLocator {
  const ProductHandleRecoveryLocator({
    required this.localIdentityId,
    required this.operationId,
    required this.fullHandle,
    this.recoveryId,
  });

  final String localIdentityId;
  final String operationId;
  final String fullHandle;
  final String? recoveryId;

  ProductHandleRecoveryLocator withRecoveryId(String value) =>
      ProductHandleRecoveryLocator(
        localIdentityId: localIdentityId,
        operationId: operationId,
        fullHandle: fullHandle,
        recoveryId: value,
      );
}

/// Core-certified proof that a pre-v5 Registry checkpoint belongs to the
/// currently active ordinary identity binding and has no Recovery transition.
class LegacyRegistryEpochAdoptionAuthority {
  const LegacyRegistryEpochAdoptionAuthority({
    required this.ownerIdentityId,
    required this.accountUserId,
    required this.currentDid,
    required this.bindingGeneration,
    required this.protocolDeviceId,
    required this.deviceAuthGeneration,
    required this.provenanceId,
  });

  final String ownerIdentityId;
  final String accountUserId;
  final String currentDid;
  final String bindingGeneration;
  final String protocolDeviceId;
  final String deviceAuthGeneration;
  final String provenanceId;

  ProductAccountBinding get binding => ProductAccountBinding(
    ownerIdentityId: ownerIdentityId,
    accountId: accountUserId,
  );

  ProductDeviceRegistryEpoch get epoch => ProductDeviceRegistryEpoch(
    currentDid: currentDid,
    bindingGeneration: bindingGeneration,
  );

  bool matches(LegacyRegistryEpochAdoptionAuthority other) =>
      ownerIdentityId == other.ownerIdentityId &&
      accountUserId == other.accountUserId &&
      currentDid == other.currentDid &&
      bindingGeneration == other.bindingGeneration &&
      protocolDeviceId == other.protocolDeviceId &&
      deviceAuthGeneration == other.deviceAuthGeneration &&
      provenanceId == other.provenanceId;
}

class LegacyRegistryEpochAdoptionReceipt {
  const LegacyRegistryEpochAdoptionReceipt({
    required this.authority,
    required this.adoptedAt,
  });

  final LegacyRegistryEpochAdoptionAuthority authority;
  final DateTime adoptedAt;
}

class ProductDeviceRegistrySnapshot {
  ProductDeviceRegistrySnapshot({
    required this.binding,
    required this.epoch,
    required this.domainVersion,
    this.payloadHash,
    required this.refreshedAt,
    required Iterable<ProductDeviceRegistryItem> devices,
  }) : devices = List<ProductDeviceRegistryItem>.unmodifiable(devices);

  final ProductAccountBinding binding;
  final ProductDeviceRegistryEpoch epoch;
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

class ProductDeviceRegistryEpochMismatchException implements Exception {
  const ProductDeviceRegistryEpochMismatchException();

  @override
  String toString() =>
      'ProductDeviceRegistryEpochMismatchException(product_device_registry_epoch_mismatch)';
}

class ProductLegacyRegistryEpochAdoptionMismatchException implements Exception {
  const ProductLegacyRegistryEpochAdoptionMismatchException();

  @override
  String toString() =>
      'ProductLegacyRegistryEpochAdoptionMismatchException(product_legacy_registry_epoch_adoption_mismatch)';
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
  validateProductDeviceRegistryEpoch(snapshot.epoch);
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

void validateProductDeviceRegistryEpoch(ProductDeviceRegistryEpoch epoch) {
  _requireExactNonEmpty(epoch.currentDid, 'currentDid');
  if (!epoch.currentDid.startsWith('did:wba:') ||
      RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(epoch.currentDid)) {
    throw ArgumentError.value(
      epoch.currentDid,
      'currentDid',
      'must be a canonical did:wba identifier',
    );
  }
  _requireCanonicalPositiveDecimal(
    epoch.bindingGeneration,
    'bindingGeneration',
  );
}

void validateProductDeviceRegistryEpochResetReference(
  ProductDeviceRegistryEpochResetReference reference,
) {
  validateProductAccountBinding(reference.binding);
  _requireExactNonEmpty(reference.previousDid, 'previousDid');
  validateProductDeviceRegistryEpoch(reference.targetEpoch);
  if (reference.previousDid == reference.currentDid) {
    throw ArgumentError.value(
      reference.currentDid,
      'currentDid',
      'must differ from previousDid',
    );
  }
}

void validateProductDeviceRegistryEpochResetAuthorization(
  ProductDeviceRegistryEpochResetAuthorization authorization,
) {
  validateProductDeviceRegistryEpochResetReference(authorization.reference);
  _requireExactNonEmpty(authorization.handle, 'handle');
  if (authorization.handle != authorization.handle.toLowerCase() ||
      !authorization.handle.contains('.') ||
      authorization.handle.endsWith('.')) {
    throw ArgumentError.value(
      authorization.handle,
      'handle',
      'must be a canonical full Handle',
    );
  }
  _requireExactNonEmpty(authorization.sourceId, 'sourceId');
  final invalidSourceId = switch (authorization.sourceKind) {
    ProductIdentityTransitionSourceKind.initiator =>
      authorization.sourceId.runes.length > 128 ||
          RegExp(
            r'[\s\x00-\x1f\x7f-\x9f]',
            unicode: true,
          ).hasMatch(authorization.sourceId),
    ProductIdentityTransitionSourceKind.joinedDevice =>
      !isCanonicalDeviceJoinSessionId(authorization.sourceId),
  };
  if (invalidSourceId) {
    throw ArgumentError.value(
      authorization.sourceId,
      'sourceId',
      'must be a canonical non-secret source reference',
    );
  }
}

void validateLegacyRegistryEpochAdoptionAuthority(
  LegacyRegistryEpochAdoptionAuthority authority,
) {
  validateProductAccountBinding(authority.binding);
  validateProductDeviceRegistryEpoch(authority.epoch);
  _requireExactNonEmpty(authority.protocolDeviceId, 'protocolDeviceId');
  _requireCanonicalDecimal(
    authority.deviceAuthGeneration,
    'deviceAuthGeneration',
  );
  _requireExactNonEmpty(authority.provenanceId, 'provenanceId');
  if (!authority.provenanceId.startsWith('sha256:') ||
      authority.provenanceId.runes.length > 128 ||
      RegExp(
        r'[\s\x00-\x1f\x7f-\x9f]',
        unicode: true,
      ).hasMatch(authority.provenanceId)) {
    throw ArgumentError.value(
      authority.provenanceId,
      'provenanceId',
      'must be an opaque sha256 provenance identifier',
    );
  }
}

void _requireCanonicalPositiveDecimal(String value, String name) {
  _requireCanonicalDecimal(value, name);
  if (value == '0') {
    throw ArgumentError.value(value, name, 'must be positive');
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
