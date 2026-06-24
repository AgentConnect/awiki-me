import 'dart:io' show Platform;

import '../../application/config/awiki_environment_config.dart';
import '../../application/ports/agent_inventory_port.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/install_command.dart';
import '../services/authenticated_user_service_rpc_client.dart';
import '../services/awiki_onboarding_utility_client.dart';

class UserServiceAgentInventoryAdapter implements AgentInventoryPort {
  UserServiceAgentInventoryAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _environment = AwikiEnvironmentConfig(
         baseUrl: userServiceUrl,
         userServiceUrl: userServiceUrl,
       ),
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  UserServiceAgentInventoryAdapter._({
    required String userServiceUrl,
    required AwikiEnvironmentConfig environment,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _environment = environment,
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  factory UserServiceAgentInventoryAdapter.fromEnvironment({
    AwikiEnvironmentConfig? environment,
  }) {
    final effectiveEnvironment =
        environment ?? AwikiEnvironmentConfig.fromEnvironment();
    return UserServiceAgentInventoryAdapter._(
      userServiceUrl: effectiveEnvironment.userServiceUrl,
      environment: effectiveEnvironment,
    );
  }

  UserServiceAgentInventoryAdapter withBearerTokenProvider(
    String? Function() bearerTokenProvider,
  ) {
    return UserServiceAgentInventoryAdapter._(
      userServiceUrl: _client.baseUrl,
      environment: _environment,
      client: _client,
      bearerTokenProvider: bearerTokenProvider,
    );
  }

  UserServiceAgentInventoryAdapter withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient authenticatedClient,
  ) {
    return UserServiceAgentInventoryAdapter._(
      userServiceUrl: _client.baseUrl,
      environment: _environment,
      client: _client,
      bearerTokenProvider: _bearerTokenProvider,
      authenticatedClient: authenticatedClient,
    );
  }

  static const String inventoryEndpoint = '/user-service/agent-inventory/rpc';
  static const String registrationEndpoint =
      '/user-service/agent-registration/rpc';

  AwikiOnboardingUtilityHttpClient get httpClient => _client;

  final AwikiOnboardingUtilityHttpClient _client;
  final AwikiEnvironmentConfig _environment;
  final String? Function()? _bearerTokenProvider;
  final AuthenticatedUserServiceRpcClient? _authenticatedClient;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    final result = await _rpcCall(
      path: inventoryEndpoint,
      method: 'list_agents',
      params: <String, Object?>{'include_inactive': includeInactive},
    );
    final agents = result['agents'];
    if (agents is! List) {
      return const <AgentSummary>[];
    }
    return agents
        .whereType<Map>()
        .map(
          (item) => AgentSummary.fromJson(
            item.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();
  }

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) async {
    final result = await _rpcCall(
      path: inventoryEndpoint,
      method: 'update_display_name',
      params: <String, Object?>{
        'agent_did': agentDid,
        'display_name': displayName,
      },
    );
    final agent = result['agent'];
    if (agent is Map) {
      return AgentSummary.fromJson(
        agent.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    return AgentSummary.fromJson(result);
  }

  @override
  Future<void> unbindAgent({required String agentDid}) async {
    await _rpcCall(
      path: inventoryEndpoint,
      method: 'unbind_agent',
      params: <String, Object?>{'agent_did': agentDid},
    );
  }

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy({
    required String agentDid,
  }) async {
    final result = await _rpcCall(
      path: inventoryEndpoint,
      method: 'get_invocation_policy',
      params: <String, Object?>{'agent_did': agentDid},
    );
    return AgentInvocationPolicy.fromJson(result);
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    final result = await _rpcCall(
      path: inventoryEndpoint,
      method: 'update_invocation_policy',
      params: <String, Object?>{
        'agent_did': agentDid,
        'active_mode': policy.activeMode.wireValue,
        'whitelist_handles': policy.whitelistHandles,
        'blacklist_handles': policy.blacklistHandles,
      },
    );
    return AgentInvocationPolicy.fromJson(result);
  }

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) {
    final normalizedControllerHandle = controllerHandle
        .trim()
        .replaceFirst(RegExp(r'^@+'), '')
        .toLowerCase();
    if (normalizedControllerHandle.isEmpty) {
      throw ArgumentError.value(
        controllerHandle,
        'controllerHandle',
        'must not be empty for daemon registration tokens',
      );
    }
    return _issueToken(<String, Object?>{
      'agent_kind': 'daemon',
      'controller_did': controllerDid,
      'controller_handle': normalizedControllerHandle,
      'metadata': <String, Object?>{
        'default_display_name': '代理 1',
        'client': 'awiki-me',
        'client_platform': clientPlatform,
        'base_url': _environment.baseUrl,
        'daemon_download_base_url': _environment.daemonDownloadBaseUrl,
        'download_channel': 'stable',
      },
    });
  }

  @override
  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
    required String handle,
    required String displayName,
    String? driverId,
    String? workspaceMode,
    String? defaultSandbox,
    String? defaultModel,
    Map<String, Object?>? driverConfig,
  }) {
    final sanitizedDriverConfig = _runtimeTokenDriverConfig(driverConfig);
    return _issueToken(<String, Object?>{
      'agent_kind': 'runtime',
      'controller_did': controllerDid,
      'handle': handle,
      'metadata': <String, Object?>{
        'runtime': runtime,
        if (driverId != null) 'driver_id': driverId,
        'daemon_agent_did': daemonAgentDid,
        'default_display_name': displayName,
        if (workspaceMode != null) 'workspace_mode': workspaceMode,
        if (defaultSandbox != null) 'default_sandbox': defaultSandbox,
        if (defaultModel != null) 'default_model': defaultModel,
        if (sanitizedDriverConfig.isNotEmpty)
          'driver_config': sanitizedDriverConfig,
        'client_request_id':
            'app_req_${DateTime.now().toUtc().microsecondsSinceEpoch}',
      },
    });
  }

  Future<AgentRegistrationToken> _issueToken(
    Map<String, Object?> params,
  ) async {
    final result = await _rpcCall(
      path: registrationEndpoint,
      method: 'issue_token',
      params: params,
    );
    final rawToken =
        result['token'] ?? result['registration_token'] ?? result['raw_token'];
    final token = rawToken?.toString() ?? '';
    if (token.isEmpty) {
      throw StateError('issue_token did not return a token.');
    }
    return AgentRegistrationToken(
      token: token,
      tokenId: result['token_id']?.toString(),
      expiresAt: DateTime.tryParse(result['expires_at']?.toString() ?? ''),
    );
  }

  Future<Map<String, Object?>> _rpcCall({
    required String path,
    required String method,
    required Map<String, Object?> params,
  }) {
    final authenticatedClient = _authenticatedClient;
    if (authenticatedClient != null) {
      return authenticatedClient.rpcCall(
        path: path,
        method: method,
        params: params,
      );
    }
    return _client.rpcCall(
      path: path,
      method: method,
      params: params,
      bearerToken: _bearerToken(),
    );
  }

  String? _bearerToken() {
    final rawToken = _bearerTokenProvider?.call();
    final token = rawToken?.trim();
    return token == null || token.isEmpty ? null : token;
  }
}

Map<String, Object?> _runtimeTokenDriverConfig(
  Map<String, Object?>? driverConfig,
) {
  if (driverConfig == null || driverConfig.isEmpty) {
    return const <String, Object?>{};
  }
  return <String, Object?>{
    for (final entry in driverConfig.entries)
      if (entry.key != 'binary_path' && !_looksSensitiveMetadataKey(entry.key))
        entry.key: entry.value,
  };
}

bool _looksSensitiveMetadataKey(String key) {
  final normalized = key.toLowerCase();
  return normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('private_key') ||
      normalized.contains('jwt') ||
      normalized.contains('oauth') ||
      normalized.contains('password');
}

String awikiClientPlatform() {
  if (Platform.isIOS) {
    return 'ios';
  }
  if (Platform.isAndroid) {
    return 'android';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  return Platform.operatingSystem;
}
