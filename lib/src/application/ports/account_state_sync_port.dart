import 'dart:collection';

import '../models/product_local_models.dart';
import '../../domain/entities/profile_patch.dart';

abstract interface class AccountStateSyncPort {
  Future<AccountStateManifest> loadManifest();

  Future<AccountStateAgentInventorySnapshot> loadAgentInventory();

  Future<AccountStateAgentStatusSnapshot> loadAgentStatus();

  Future<AccountStateProfileSnapshot> loadProfile();

  Future<AccountStateDeviceRegistrySnapshot> loadDeviceRegistry();
}

abstract interface class AccountStateProfileMutationPort {
  Future<AccountStateProfileMutationResult> updateAccountProfile(
    ProfilePatch patch,
  );
}

class AccountStateProfileMutationResult {
  const AccountStateProfileMutationResult({
    required this.profile,
    required this.profileVersion,
    this.profileUri,
  });

  final AccountStateProfile profile;
  final String profileVersion;
  final String? profileUri;
}

class AccountStateManifest {
  AccountStateManifest({
    required this.accountId,
    required this.currentDid,
    required this.identityGeneration,
    required Map<ProductAccountDomain, String> versions,
    required this.serverTime,
  }) : versions = UnmodifiableMapView<ProductAccountDomain, String>(versions);

  final String accountId;
  final String currentDid;
  final String identityGeneration;
  final Map<ProductAccountDomain, String> versions;
  final DateTime serverTime;

  String versionFor(ProductAccountDomain domain) => versions[domain]!;
}

class AccountStateAgentInventorySnapshot {
  AccountStateAgentInventorySnapshot({
    required this.accountId,
    required this.inventoryVersion,
    required Iterable<AccountStateAgentInventoryEntry> agents,
  }) : agents = List<AccountStateAgentInventoryEntry>.unmodifiable(agents);

  final String accountId;
  final String inventoryVersion;
  final List<AccountStateAgentInventoryEntry> agents;
}

class AccountStateAgentInventoryEntry {
  AccountStateAgentInventoryEntry({
    required this.agentDid,
    required this.agentKind,
    this.daemonAgentDid,
    required this.controllerFullHandle,
    this.runtime,
    this.handle,
    this.displayName,
    required Map<String, Object?> profileSummary,
    required this.activeState,
    required Map<String, Object?> invocationPolicy,
    required this.inventoryVersion,
  }) : profileSummary = UnmodifiableMapView<String, Object?>(profileSummary),
       invocationPolicy = UnmodifiableMapView<String, Object?>(
         invocationPolicy,
       );

  final String agentDid;
  final String agentKind;
  final String? daemonAgentDid;
  final String controllerFullHandle;
  final String? runtime;
  final String? handle;
  final String? displayName;
  final Map<String, Object?> profileSummary;
  final String activeState;
  final Map<String, Object?> invocationPolicy;
  final String inventoryVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'agent_did': agentDid,
    'agent_kind': agentKind,
    'daemon_agent_did': daemonAgentDid,
    'controller_full_handle': controllerFullHandle,
    'runtime': runtime,
    'handle': handle,
    'display_name': displayName,
    'profile_summary': profileSummary,
    'active_state': activeState,
    'invocation_policy': invocationPolicy,
    'inventory_version': inventoryVersion,
  };
}

class AccountStateAgentStatusSnapshot {
  AccountStateAgentStatusSnapshot({
    required this.accountId,
    required this.agentStatusVersion,
    required Iterable<AccountStateAgentStatusEntry> statuses,
  }) : statuses = List<AccountStateAgentStatusEntry>.unmodifiable(statuses);

  final String accountId;
  final String agentStatusVersion;
  final List<AccountStateAgentStatusEntry> statuses;
}

class AccountStateAgentStatusEntry {
  AccountStateAgentStatusEntry({
    required this.agentDid,
    this.status,
    this.lastSeenAt,
    this.version,
    this.latestVersion,
    this.minSupportedVersion,
    this.platform,
    this.service,
    required this.needsUpgrade,
    required this.needsConfig,
    this.lastErrorCode,
    this.lastErrorSummary,
    required Map<String, Object?> diagnosticsSummary,
  }) : diagnosticsSummary = UnmodifiableMapView<String, Object?>(
         diagnosticsSummary,
       );

  final String agentDid;
  final String? status;
  final String? lastSeenAt;
  final String? version;
  final String? latestVersion;
  final String? minSupportedVersion;
  final String? platform;
  final String? service;
  final bool needsUpgrade;
  final bool needsConfig;
  final String? lastErrorCode;
  final String? lastErrorSummary;
  final Map<String, Object?> diagnosticsSummary;

  Map<String, Object?> toJson() => <String, Object?>{
    'agent_did': agentDid,
    'status': status,
    'last_seen_at': lastSeenAt,
    'version': version,
    'latest_version': latestVersion,
    'min_supported_version': minSupportedVersion,
    'platform': platform,
    'service': service,
    'needs_upgrade': needsUpgrade,
    'needs_config': needsConfig,
    'last_error_code': lastErrorCode,
    'last_error_summary': lastErrorSummary,
    'diagnostics_summary': diagnosticsSummary,
  };
}

class AccountStateProfileSnapshot {
  AccountStateProfileSnapshot({
    required this.accountId,
    required this.profileVersion,
    required this.profile,
  });

  final String accountId;
  final String profileVersion;
  final AccountStateProfile profile;
}

class AccountStateProfile {
  AccountStateProfile({
    this.nickName,
    this.avatarUrl,
    this.gender,
    required Iterable<String> tags,
    this.bio,
    this.profileMd,
  }) : tags = List<String>.unmodifiable(tags);

  final String? nickName;
  final String? avatarUrl;
  final String? gender;
  final List<String> tags;
  final String? bio;
  final String? profileMd;

  Map<String, Object?> toJson() => <String, Object?>{
    'nick_name': nickName,
    'avatar_url': avatarUrl,
    'gender': gender,
    'tags': tags,
    'bio': bio,
    'profile_md': profileMd,
  };
}

class AccountStateDeviceRegistrySnapshot {
  AccountStateDeviceRegistrySnapshot({
    required this.did,
    required this.registryVersion,
    required Iterable<AccountStateDeviceRegistryEntry> devices,
  }) : devices = List<AccountStateDeviceRegistryEntry>.unmodifiable(devices);

  final String did;
  final String registryVersion;
  final List<AccountStateDeviceRegistryEntry> devices;
}

class AccountStateDeviceRegistryEntry {
  const AccountStateDeviceRegistryEntry({
    required this.protocolDeviceId,
    required this.signingKeyId,
    required this.e2eeKeyId,
    required this.status,
    required this.role,
    required this.managementReady,
    required this.authGeneration,
  });

  final String protocolDeviceId;
  final String signingKeyId;
  final String e2eeKeyId;
  final String status;
  final String role;
  final bool managementReady;
  final String authGeneration;

  Map<String, Object?> toJson() => <String, Object?>{
    'device_id': protocolDeviceId,
    'signing_key_id': signingKeyId,
    'e2ee_key_id': e2eeKeyId,
    'status': status,
    'role': role,
    'management_ready': managementReady,
    'auth_generation': authGeneration,
  };
}
