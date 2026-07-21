import '../../application/ports/skill_onboarding_port.dart';
import '../../domain/entities/agent/skill_onboarding_instruction.dart';
import '../services/authenticated_user_service_rpc_client.dart';
import '../services/awiki_onboarding_utility_client.dart';

class UserServiceSkillOnboardingAdapter implements SkillOnboardingPort {
  UserServiceSkillOnboardingAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  static const registrationEndpoint = '/user-service/agent-registration/rpc';

  final AwikiOnboardingUtilityHttpClient _client;
  final String? Function()? _bearerTokenProvider;
  final AuthenticatedUserServiceRpcClient? _authenticatedClient;

  AwikiOnboardingUtilityHttpClient get httpClient => _client;

  UserServiceSkillOnboardingAdapter withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient authenticatedClient,
  ) {
    return UserServiceSkillOnboardingAdapter(
      userServiceUrl: _client.baseUrl,
      client: _client,
      bearerTokenProvider: _bearerTokenProvider,
      authenticatedClient: authenticatedClient,
    );
  }

  @override
  Future<SkillOnboardingGrant> issueSkillToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    final normalizedControllerHandle = controllerHandle
        .trim()
        .replaceFirst(RegExp(r'^@+'), '')
        .toLowerCase();
    if (controllerDid.trim().isEmpty || normalizedControllerHandle.isEmpty) {
      throw const FormatException('skill_onboarding_controller_required');
    }
    final result = await _rpcCall(
      params: <String, Object?>{
        'agent_kind': 'skill',
        'controller_did': controllerDid.trim(),
        'controller_handle': normalizedControllerHandle,
        'one_time': true,
        'metadata': <String, Object?>{
          'client': 'awiki-me',
          'client_platform': clientPlatform,
          'onboarding_version': 1,
        },
      },
    );
    final scope = result['scope'];
    final serviceOrigin = scope is Map
        ? scope['service_origin']?.toString().trim() ?? ''
        : '';
    final token = result['token']?.toString() ?? '';
    final tokenId = result['token_id']?.toString() ?? '';
    final responseControllerHandle =
        result['controller_full_handle']?.toString() ?? '';
    final agentHandle = result['handle']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(result['expires_at']?.toString() ?? '');
    if (token.isEmpty ||
        tokenId.isEmpty ||
        responseControllerHandle.isEmpty ||
        agentHandle.isEmpty ||
        serviceOrigin.isEmpty ||
        expiresAt == null) {
      throw const FormatException('invalid_skill_onboarding_response');
    }
    return SkillOnboardingGrant(
      token: token,
      tokenId: tokenId,
      controllerHandle: responseControllerHandle,
      agentHandle: agentHandle,
      serviceOrigin: serviceOrigin,
      expiresAt: expiresAt.toUtc(),
    );
  }

  Future<Map<String, Object?>> _rpcCall({
    required Map<String, Object?> params,
  }) {
    final authenticatedClient = _authenticatedClient;
    if (authenticatedClient != null) {
      return authenticatedClient.rpcCall(
        path: registrationEndpoint,
        method: 'issue_token',
        params: params,
      );
    }
    final bearer = _bearerTokenProvider?.call()?.trim();
    return _client.rpcCall(
      path: registrationEndpoint,
      method: 'issue_token',
      params: params,
      bearerToken: bearer == null || bearer.isEmpty ? null : bearer,
    );
  }
}
