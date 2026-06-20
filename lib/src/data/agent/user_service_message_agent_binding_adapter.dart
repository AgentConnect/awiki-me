import '../../application/ports/message_agent_binding_port.dart';
import '../../domain/entities/agent/message_agent_binding.dart';
import '../services/authenticated_user_service_rpc_client.dart';
import '../services/awiki_onboarding_utility_client.dart';

class UserServiceMessageAgentBindingAdapter implements MessageAgentBindingPort {
  UserServiceMessageAgentBindingAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  UserServiceMessageAgentBindingAdapter._({
    required AwikiOnboardingUtilityHttpClient client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client = client,
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  UserServiceMessageAgentBindingAdapter withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient authenticatedClient,
  ) {
    return UserServiceMessageAgentBindingAdapter._(
      client: _client,
      bearerTokenProvider: _bearerTokenProvider,
      authenticatedClient: authenticatedClient,
    );
  }

  static const String endpoint = '/user-service/message-agent/rpc';

  AwikiOnboardingUtilityHttpClient get httpClient => _client;

  final AwikiOnboardingUtilityHttpClient _client;
  final String? Function()? _bearerTokenProvider;
  final AuthenticatedUserServiceRpcClient? _authenticatedClient;

  @override
  Future<MessageAgentBinding> ensureBinding({
    required String userDid,
    required String daemonAgentDid,
    required String messageAgentDid,
    required String runtimeProvider,
    required Map<String, Object?> runtimeProfile,
    required String delegatedKeyVerificationMethod,
  }) async {
    final result = await _rpcCall(
      method: 'ensure_binding',
      params: <String, Object?>{
        'user_did': userDid,
        'daemon_agent_did': daemonAgentDid,
        'message_agent_did': messageAgentDid,
        'runtime_provider': runtimeProvider,
        'runtime_profile': runtimeProfile,
        'delegated_key_verification_method': delegatedKeyVerificationMethod,
      },
    );
    final binding = result['binding'];
    if (binding is Map) {
      return MessageAgentBinding.fromJson(
        binding.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    throw StateError('ensure_binding returned an invalid binding.');
  }

  @override
  Future<MessageAgentBinding?> getActiveBinding() async {
    final result = await _rpcCall(
      method: 'get_active_binding',
      params: const <String, Object?>{},
    );
    final binding = result['binding'];
    if (binding == null) {
      return null;
    }
    if (binding is Map) {
      return MessageAgentBinding.fromJson(
        binding.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    throw StateError('get_active_binding returned an invalid binding.');
  }

  @override
  Future<MessageAgentBinding> disableBinding({
    String? bindingId,
    String? messageAgentDid,
  }) {
    return _mutateBinding(
      method: 'disable_binding',
      bindingId: bindingId,
      messageAgentDid: messageAgentDid,
    );
  }

  @override
  Future<MessageAgentBinding> revokeBinding({
    String? bindingId,
    String? messageAgentDid,
  }) {
    return _mutateBinding(
      method: 'revoke_binding',
      bindingId: bindingId,
      messageAgentDid: messageAgentDid,
    );
  }

  Future<MessageAgentBinding> _mutateBinding({
    required String method,
    String? bindingId,
    String? messageAgentDid,
  }) async {
    final params = <String, Object?>{
      if (_nonEmpty(bindingId) != null) 'binding_id': _nonEmpty(bindingId),
      if (_nonEmpty(messageAgentDid) != null)
        'message_agent_did': _nonEmpty(messageAgentDid),
    };
    if (params.isEmpty) {
      throw ArgumentError('bindingId or messageAgentDid is required.');
    }
    final result = await _rpcCall(method: method, params: params);
    final binding = result['binding'];
    if (binding is Map) {
      return MessageAgentBinding.fromJson(
        binding.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    throw StateError('$method returned an invalid binding.');
  }

  Future<Map<String, Object?>> _rpcCall({
    required String method,
    required Map<String, Object?> params,
  }) {
    final authenticatedClient = _authenticatedClient;
    if (authenticatedClient != null) {
      return authenticatedClient.rpcCall(
        path: endpoint,
        method: method,
        params: params,
      );
    }
    return _client.rpcCall(
      path: endpoint,
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

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
