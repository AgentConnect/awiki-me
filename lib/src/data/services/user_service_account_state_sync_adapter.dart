import '../../application/config/awiki_environment_config.dart';
import '../../application/models/product_local_models.dart';
import '../../application/ports/account_state_sync_port.dart';
import '../../domain/entities/profile_patch.dart';
import 'authenticated_user_service_rpc_client.dart';
import 'awiki_onboarding_utility_client.dart';

typedef AccountStateDeviceRegistryLoader =
    Future<AccountStateDeviceRegistrySnapshot> Function();

class UserServiceAccountStateSyncAdapter
    implements AccountStateSyncPort, AccountStateProfileMutationPort {
  UserServiceAccountStateSyncAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
    AccountStateDeviceRegistryLoader? deviceRegistryLoader,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _authenticatedClient = authenticatedClient,
       _deviceRegistryLoader = deviceRegistryLoader;

  factory UserServiceAccountStateSyncAdapter.fromEnvironment({
    AwikiEnvironmentConfig? environment,
  }) {
    final effective = environment ?? AwikiEnvironmentConfig.fromEnvironment();
    return UserServiceAccountStateSyncAdapter(
      userServiceUrl: effective.userServiceUrl,
    );
  }

  static const String accountStateEndpoint = '/user-service/account-state/rpc';
  static const String deviceAuthEndpoint = '/user-service/did-auth/rpc';
  static const String profileEndpoint = '/user-service/me/rpc';

  final AwikiOnboardingUtilityHttpClient _client;
  final AuthenticatedUserServiceRpcClient? _authenticatedClient;
  final AccountStateDeviceRegistryLoader? _deviceRegistryLoader;

  AwikiOnboardingUtilityHttpClient get httpClient => _client;

  UserServiceAccountStateSyncAdapter withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient authenticatedClient,
  ) {
    return UserServiceAccountStateSyncAdapter(
      userServiceUrl: _client.baseUrl,
      client: _client,
      authenticatedClient: authenticatedClient,
      deviceRegistryLoader: _deviceRegistryLoader,
    );
  }

  UserServiceAccountStateSyncAdapter withDeviceRegistryLoader(
    AccountStateDeviceRegistryLoader loader,
  ) {
    return UserServiceAccountStateSyncAdapter(
      userServiceUrl: _client.baseUrl,
      client: _client,
      authenticatedClient: _authenticatedClient,
      deviceRegistryLoader: loader,
    );
  }

  @override
  Future<AccountStateManifest> loadManifest() async {
    final result = await _accountStateCall('account_state.manifest_get');
    _expectExactKeys(result, const <String>{
      'account_id',
      'current_did',
      'identity_generation',
      'versions',
      'server_time',
    }, 'manifest');
    final versions = _expectMap(result['versions'], 'manifest.versions');
    _expectExactKeys(versions, const <String>{
      'profile',
      'agent_inventory',
      'agent_status',
      'device_registry',
    }, 'manifest.versions');
    return AccountStateManifest(
      accountId: _requiredString(result, 'account_id', 'manifest'),
      currentDid: _requiredString(result, 'current_did', 'manifest'),
      identityGeneration: _requiredDecimalString(
        result,
        'identity_generation',
        'manifest',
      ),
      versions: <ProductAccountDomain, String>{
        ProductAccountDomain.profile: _requiredDecimalString(
          versions,
          'profile',
          'manifest.versions',
        ),
        ProductAccountDomain.agentInventory: _requiredDecimalString(
          versions,
          'agent_inventory',
          'manifest.versions',
        ),
        ProductAccountDomain.agentStatus: _requiredDecimalString(
          versions,
          'agent_status',
          'manifest.versions',
        ),
        ProductAccountDomain.deviceRegistry: _requiredDecimalString(
          versions,
          'device_registry',
          'manifest.versions',
        ),
      },
      serverTime: _requiredUtcDateTime(result, 'server_time', 'manifest'),
    );
  }

  @override
  Future<AccountStateAgentInventorySnapshot> loadAgentInventory() async {
    final result = await _accountStateCall('account_state.agent_inventory_get');
    _expectExactKeys(result, const <String>{
      'account_id',
      'inventory_version',
      'agents',
    }, 'agent_inventory');
    final agents = _requiredList(result, 'agents', 'agent_inventory');
    return AccountStateAgentInventorySnapshot(
      accountId: _requiredString(result, 'account_id', 'agent_inventory'),
      inventoryVersion: _requiredDecimalString(
        result,
        'inventory_version',
        'agent_inventory',
      ),
      agents: agents.map(
        (value) => _parseAgentInventoryEntry(
          _expectMap(value, 'agent_inventory.agents[]'),
        ),
      ),
    );
  }

  @override
  Future<AccountStateAgentStatusSnapshot> loadAgentStatus() async {
    final result = await _accountStateCall('account_state.agent_status_get');
    _expectExactKeys(result, const <String>{
      'account_id',
      'agent_status_version',
      'statuses',
    }, 'agent_status');
    final statuses = _requiredList(result, 'statuses', 'agent_status');
    return AccountStateAgentStatusSnapshot(
      accountId: _requiredString(result, 'account_id', 'agent_status'),
      agentStatusVersion: _requiredDecimalString(
        result,
        'agent_status_version',
        'agent_status',
      ),
      statuses: statuses.map(
        (value) => _parseAgentStatusEntry(
          _expectMap(value, 'agent_status.statuses[]'),
        ),
      ),
    );
  }

  @override
  Future<AccountStateProfileSnapshot> loadProfile() async {
    final result = await _accountStateCall('account_state.profile_get');
    _expectExactKeys(result, const <String>{
      'account_id',
      'profile_version',
      'profile',
    }, 'profile');
    final profile = _expectMap(result['profile'], 'profile.profile');
    _expectExactKeys(profile, const <String>{
      'nick_name',
      'avatar_url',
      'gender',
      'tags',
      'bio',
      'profile_md',
    }, 'profile.profile');
    return AccountStateProfileSnapshot(
      accountId: _requiredString(result, 'account_id', 'profile'),
      profileVersion: _requiredDecimalString(
        result,
        'profile_version',
        'profile',
      ),
      profile: AccountStateProfile(
        nickName: _nullableString(profile, 'nick_name', 'profile.profile'),
        avatarUrl: _nullableString(profile, 'avatar_url', 'profile.profile'),
        gender: _nullableString(profile, 'gender', 'profile.profile'),
        tags: _requiredStringList(profile, 'tags', 'profile.profile'),
        bio: _nullableString(profile, 'bio', 'profile.profile'),
        profileMd: _nullableString(profile, 'profile_md', 'profile.profile'),
      ),
    );
  }

  @override
  Future<AccountStateDeviceRegistrySnapshot> loadDeviceRegistry() async {
    final loader = _deviceRegistryLoader;
    if (loader != null) {
      return loader();
    }
    final result = await _rpcCall(
      path: deviceAuthEndpoint,
      method: 'device_registry_get',
    );
    _expectExactKeys(result, const <String>{
      'did',
      'checkpoint',
      'devices',
    }, 'device_registry');
    final checkpoint = _expectMap(
      result['checkpoint'],
      'device_registry.checkpoint',
    );
    _expectExactKeys(checkpoint, const <String>{
      'document_version',
      'document_hash',
      'registry_version',
    }, 'device_registry.checkpoint');
    _requiredWireDecimal(
      checkpoint,
      'document_version',
      'device_registry.checkpoint',
    );
    _requiredString(checkpoint, 'document_hash', 'device_registry.checkpoint');
    final devices = _requiredList(result, 'devices', 'device_registry');
    return AccountStateDeviceRegistrySnapshot(
      did: _requiredString(result, 'did', 'device_registry'),
      registryVersion: _requiredWireDecimal(
        checkpoint,
        'registry_version',
        'device_registry.checkpoint',
      ),
      devices: devices.map(
        (value) => _parseDeviceRegistryEntry(
          _expectMap(value, 'device_registry.devices[]'),
        ),
      ),
    );
  }

  @override
  Future<AccountStateProfileMutationResult> updateAccountProfile(
    ProfilePatch patch,
  ) async {
    final result = await _rpcCall(
      path: profileEndpoint,
      method: 'update_me',
      params: <String, Object?>{
        if (patch.effectiveDisplayName != null)
          'nick_name': patch.effectiveDisplayName,
        if (patch.avatarUri != null) 'avatar_url': patch.avatarUri,
        if (patch.tags != null) 'tags': patch.tags,
        if (patch.bio != null) 'bio': patch.bio,
        if (patch.profileMarkdown != null) 'profile_md': patch.profileMarkdown,
      },
    );
    return AccountStateProfileMutationResult(
      profileVersion: _requiredDecimalString(
        result,
        'profile_version',
        'profile_mutation',
      ),
      profile: AccountStateProfile(
        nickName: _nullableString(result, 'nick_name', 'profile_mutation'),
        avatarUrl: _nullableString(result, 'avatar_url', 'profile_mutation'),
        gender: _nullableString(result, 'gender', 'profile_mutation'),
        tags: _requiredStringList(result, 'tags', 'profile_mutation'),
        bio: _nullableString(result, 'bio', 'profile_mutation'),
        profileMd: _nullableString(result, 'profile_md', 'profile_mutation'),
      ),
      profileUri: _nullableString(result, 'profile_url', 'profile_mutation'),
    );
  }

  Future<Map<String, Object?>> _accountStateCall(String method) {
    return _rpcCall(path: accountStateEndpoint, method: method);
  }

  Future<Map<String, Object?>> _rpcCall({
    required String path,
    required String method,
    Map<String, Object?> params = const <String, Object?>{},
  }) {
    final authenticatedClient = _authenticatedClient;
    if (authenticatedClient != null) {
      return authenticatedClient.rpcCall(
        path: path,
        method: method,
        params: params,
      );
    }
    throw StateError('account_state_device_access_auth_required');
  }
}

AccountStateAgentInventoryEntry _parseAgentInventoryEntry(
  Map<String, Object?> value,
) {
  const context = 'agent_inventory.agents[]';
  _expectExactKeys(value, const <String>{
    'agent_did',
    'agent_kind',
    'daemon_agent_did',
    'controller_full_handle',
    'runtime',
    'handle',
    'display_name',
    'profile_summary',
    'active_state',
    'invocation_policy',
    'inventory_version',
  }, context);
  return AccountStateAgentInventoryEntry(
    agentDid: _requiredString(value, 'agent_did', context),
    agentKind: _requiredString(value, 'agent_kind', context),
    daemonAgentDid: _nullableString(value, 'daemon_agent_did', context),
    controllerFullHandle: _requiredString(
      value,
      'controller_full_handle',
      context,
    ),
    runtime: _nullableString(value, 'runtime', context),
    handle: _nullableString(value, 'handle', context),
    displayName: _nullableString(value, 'display_name', context),
    profileSummary: _expectMap(
      value['profile_summary'],
      '$context.profile_summary',
    ),
    activeState: _requiredString(value, 'active_state', context),
    invocationPolicy: _expectMap(
      value['invocation_policy'],
      '$context.invocation_policy',
    ),
    inventoryVersion: _requiredDecimalString(
      value,
      'inventory_version',
      context,
    ),
  );
}

AccountStateAgentStatusEntry _parseAgentStatusEntry(
  Map<String, Object?> value,
) {
  const context = 'agent_status.statuses[]';
  _expectExactKeys(value, const <String>{
    'agent_did',
    'status',
    'last_seen_at',
    'version',
    'latest_version',
    'min_supported_version',
    'platform',
    'service',
    'needs_upgrade',
    'needs_config',
    'last_error_code',
    'last_error_summary',
    'diagnostics_summary',
  }, context);
  return AccountStateAgentStatusEntry(
    agentDid: _requiredString(value, 'agent_did', context),
    status: _nullableString(value, 'status', context),
    lastSeenAt: _nullableString(value, 'last_seen_at', context),
    version: _nullableString(value, 'version', context),
    latestVersion: _nullableString(value, 'latest_version', context),
    minSupportedVersion: _nullableString(
      value,
      'min_supported_version',
      context,
    ),
    platform: _nullableString(value, 'platform', context),
    service: _nullableString(value, 'service', context),
    needsUpgrade: _requiredBool(value, 'needs_upgrade', context),
    needsConfig: _requiredBool(value, 'needs_config', context),
    lastErrorCode: _nullableString(value, 'last_error_code', context),
    lastErrorSummary: _nullableString(value, 'last_error_summary', context),
    diagnosticsSummary: _expectMap(
      value['diagnostics_summary'],
      '$context.diagnostics_summary',
    ),
  );
}

AccountStateDeviceRegistryEntry _parseDeviceRegistryEntry(
  Map<String, Object?> value,
) {
  const context = 'device_registry.devices[]';
  _expectExactKeys(value, const <String>{
    'device_id',
    'signing_key_id',
    'e2ee_key_id',
    'status',
    'role',
    'management_ready',
    'auth_generation',
  }, context);
  return AccountStateDeviceRegistryEntry(
    protocolDeviceId: _requiredString(value, 'device_id', context),
    signingKeyId: _requiredString(value, 'signing_key_id', context),
    e2eeKeyId: _requiredString(value, 'e2ee_key_id', context),
    status: _requiredString(value, 'status', context),
    role: _requiredString(value, 'role', context),
    managementReady: _requiredBool(value, 'management_ready', context),
    authGeneration: _requiredWireDecimal(value, 'auth_generation', context),
  );
}

Map<String, Object?> _expectMap(Object? value, String context) {
  if (value is! Map) {
    throw FormatException('$context must be an object');
  }
  return value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

void _expectExactKeys(
  Map<String, Object?> value,
  Set<String> expected,
  String context,
) {
  if (value.length != expected.length || !value.keys.every(expected.contains)) {
    throw FormatException('$context has an invalid schema');
  }
}

String _requiredString(Map<String, Object?> value, String key, String context) {
  final item = value[key];
  if (item is! String || item.isEmpty || item.trim() != item) {
    throw FormatException('$context.$key must be a non-empty string');
  }
  return item;
}

String? _nullableString(
  Map<String, Object?> value,
  String key,
  String context,
) {
  if (!value.containsKey(key)) {
    throw FormatException('$context.$key is required');
  }
  final item = value[key];
  if (item == null) {
    return null;
  }
  if (item is! String || item.trim() != item) {
    throw FormatException('$context.$key must be a string or null');
  }
  return item;
}

String _requiredDecimalString(
  Map<String, Object?> value,
  String key,
  String context,
) {
  final item = value[key];
  if (item is! String || !isCanonicalProductDecimal(item)) {
    throw FormatException('$context.$key must be a canonical decimal string');
  }
  return item;
}

String _requiredWireDecimal(
  Map<String, Object?> value,
  String key,
  String context,
) {
  final item = value[key];
  final decimal = switch (item) {
    String item => item,
    int item when item >= 0 => item.toString(),
    _ => '',
  };
  if (!isCanonicalProductDecimal(decimal)) {
    throw FormatException('$context.$key must be a non-negative integer');
  }
  return decimal;
}

DateTime _requiredUtcDateTime(
  Map<String, Object?> value,
  String key,
  String context,
) {
  final raw = _requiredString(value, key, context);
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$context.$key must be an RFC3339 UTC time');
  }
  return parsed;
}

List<Object?> _requiredList(
  Map<String, Object?> value,
  String key,
  String context,
) {
  final item = value[key];
  if (item is! List) {
    throw FormatException('$context.$key must be an array');
  }
  return List<Object?>.from(item);
}

List<String> _requiredStringList(
  Map<String, Object?> value,
  String key,
  String context,
) {
  final values = _requiredList(value, key, context);
  final result = <String>[];
  for (final item in values) {
    if (item is! String || item.trim() != item) {
      throw FormatException('$context.$key must contain only strings');
    }
    result.add(item);
  }
  return result;
}

bool _requiredBool(Map<String, Object?> value, String key, String context) {
  final item = value[key];
  if (item is! bool) {
    throw FormatException('$context.$key must be a boolean');
  }
  return item;
}
