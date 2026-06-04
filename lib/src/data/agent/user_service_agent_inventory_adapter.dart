import 'dart:io' show Platform;

import '../../application/config/awiki_environment_config.dart';
import '../../application/ports/agent_inventory_port.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/install_command.dart';
import '../services/awiki_onboarding_utility_client.dart';

class UserServiceAgentInventoryAdapter implements AgentInventoryPort {
  UserServiceAgentInventoryAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _environment = AwikiEnvironmentConfig(
         baseUrl: userServiceUrl,
         userServiceUrl: userServiceUrl,
       ),
       _bearerTokenProvider = bearerTokenProvider;

  UserServiceAgentInventoryAdapter._({
    required String userServiceUrl,
    required AwikiEnvironmentConfig environment,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _environment = environment,
       _bearerTokenProvider = bearerTokenProvider;

  factory UserServiceAgentInventoryAdapter.fromEnvironment() {
    final environment = AwikiEnvironmentConfig.fromEnvironment();
    return UserServiceAgentInventoryAdapter._(
      userServiceUrl: environment.userServiceUrl,
      environment: environment,
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

  static const String inventoryEndpoint = '/user-service/agent-inventory/rpc';
  static const String registrationEndpoint =
      '/user-service/agent-registration/rpc';

  final AwikiOnboardingUtilityHttpClient _client;
  final AwikiEnvironmentConfig _environment;
  final String? Function()? _bearerTokenProvider;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    final result = await _client.rpcCall(
      path: inventoryEndpoint,
      method: 'list_agents',
      params: <String, Object?>{'include_inactive': includeInactive},
      bearerToken: _bearerToken(),
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
    final result = await _client.rpcCall(
      path: inventoryEndpoint,
      method: 'update_display_name',
      params: <String, Object?>{
        'agent_did': agentDid,
        'display_name': displayName,
      },
      bearerToken: _bearerToken(),
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
    await _client.rpcCall(
      path: inventoryEndpoint,
      method: 'unbind_agent',
      params: <String, Object?>{'agent_did': agentDid},
      bearerToken: _bearerToken(),
    );
  }

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String clientPlatform,
  }) {
    return _issueToken(<String, Object?>{
      'agent_kind': 'daemon',
      'controller_did': controllerDid,
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
  }) {
    return _issueToken(<String, Object?>{
      'agent_kind': 'runtime',
      'controller_did': controllerDid,
      'metadata': <String, Object?>{
        'runtime': runtime,
        'daemon_agent_did': daemonAgentDid,
        'default_display_name': 'Hermes',
        'client_request_id':
            'app_req_${DateTime.now().toUtc().microsecondsSinceEpoch}',
      },
    });
  }

  Future<AgentRegistrationToken> _issueToken(
    Map<String, Object?> params,
  ) async {
    final result = await _client.rpcCall(
      path: registrationEndpoint,
      method: 'issue_token',
      params: params,
      bearerToken: _bearerToken(),
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

  String? _bearerToken() {
    final rawToken = _bearerTokenProvider?.call();
    final token = rawToken?.trim();
    return token == null || token.isEmpty ? null : token;
  }
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
