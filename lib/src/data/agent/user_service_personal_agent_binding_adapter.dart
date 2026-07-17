import '../../application/ports/personal_agent_binding_port.dart';
import '../../domain/entities/agent/personal_agent_binding.dart';
import '../services/authenticated_user_service_rpc_client.dart';
import '../services/awiki_onboarding_utility_client.dart';

class UserServicePersonalAgentBindingAdapter
    implements PersonalAgentBindingPort {
  UserServicePersonalAgentBindingAdapter({
    required String userServiceUrl,
    AwikiOnboardingUtilityHttpClient? client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client =
           client ?? AwikiOnboardingUtilityHttpClient(baseUrl: userServiceUrl),
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  UserServicePersonalAgentBindingAdapter._({
    required AwikiOnboardingUtilityHttpClient client,
    String? Function()? bearerTokenProvider,
    AuthenticatedUserServiceRpcClient? authenticatedClient,
  }) : _client = client,
       _bearerTokenProvider = bearerTokenProvider,
       _authenticatedClient = authenticatedClient;

  UserServicePersonalAgentBindingAdapter withAuthenticatedClient(
    AuthenticatedUserServiceRpcClient authenticatedClient,
  ) {
    return UserServicePersonalAgentBindingAdapter._(
      client: _client,
      bearerTokenProvider: _bearerTokenProvider,
      authenticatedClient: authenticatedClient,
    );
  }

  static const String endpoint = '/user-service/personal-agent/rpc';
  static const String legacyEndpoint = '/user-service/message-agent/rpc';

  AwikiOnboardingUtilityHttpClient get httpClient => _client;

  final AwikiOnboardingUtilityHttpClient _client;
  final String? Function()? _bearerTokenProvider;
  final AuthenticatedUserServiceRpcClient? _authenticatedClient;

  @override
  Future<PersonalAgentBinding> ensureBinding({
    required String userDid,
    required String daemonAgentDid,
    required String personalAgentDid,
    required String runtimeProvider,
    required Map<String, Object?> runtimeProfile,
    required String delegatedKeyVerificationMethod,
  }) async {
    final result = await _rpcCall(
      method: 'ensure_binding',
      params: <String, Object?>{
        'user_did': userDid,
        'daemon_agent_did': daemonAgentDid,
        'personal_agent_did': personalAgentDid,
        'runtime_provider': runtimeProvider,
        'runtime_profile': runtimeProfile,
        'delegated_key_verification_method': delegatedKeyVerificationMethod,
      },
    );
    final binding = result['binding'];
    if (binding is Map) {
      return PersonalAgentBinding.fromJson(
        binding.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    throw StateError('ensure_binding returned an invalid binding.');
  }

  @override
  Future<PersonalAgentBinding?> getActiveBinding() async {
    final result = await _rpcCall(
      method: 'get_active_binding',
      params: const <String, Object?>{},
    );
    final binding = result['binding'];
    if (binding == null) {
      return null;
    }
    if (binding is Map) {
      return PersonalAgentBinding.fromJson(
        binding.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    throw StateError('get_active_binding returned an invalid binding.');
  }

  @override
  Future<PersonalAgentBinding> disableBinding({
    String? bindingId,
    String? personalAgentDid,
  }) {
    return _mutateBinding(
      method: 'disable_binding',
      bindingId: bindingId,
      personalAgentDid: personalAgentDid,
    );
  }

  @override
  Future<PersonalAgentBinding> revokeBinding({
    String? bindingId,
    String? personalAgentDid,
  }) {
    return _mutateBinding(
      method: 'revoke_binding',
      bindingId: bindingId,
      personalAgentDid: personalAgentDid,
    );
  }

  Future<PersonalAgentBinding> _mutateBinding({
    required String method,
    String? bindingId,
    String? personalAgentDid,
  }) async {
    final params = <String, Object?>{
      if (_nonEmpty(bindingId) != null) 'binding_id': _nonEmpty(bindingId),
      if (_nonEmpty(personalAgentDid) != null)
        'personal_agent_did': _nonEmpty(personalAgentDid),
    };
    if (params.isEmpty) {
      throw ArgumentError('bindingId or personalAgentDid is required.');
    }
    final result = await _rpcCall(method: method, params: params);
    final binding = result['binding'];
    if (binding is Map) {
      return PersonalAgentBinding.fromJson(
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
  }) async {
    try {
      return await _rpcCallAt(path: endpoint, method: method, params: params);
    } on AwikiOnboardingUtilityError catch (error) {
      if (!_supportsLegacyEndpointFallback(error)) {
        rethrow;
      }
      return _rpcCallAt(
        path: legacyEndpoint,
        method: method,
        params: _legacyParams(params),
      );
    }
  }

  Future<Map<String, Object?>> _rpcCallAt({
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

bool _supportsLegacyEndpointFallback(AwikiOnboardingUtilityError error) {
  if (error.statusCode == 404 ||
      error.statusCode == 405 ||
      error.statusCode == 501 ||
      error.rpcCode == -32601) {
    return true;
  }
  final message = error.message.toLowerCase();
  return message.contains('route not found') ||
      message.contains('method not found') ||
      message.contains('unsupported endpoint');
}

Map<String, Object?> _legacyParams(Map<String, Object?> params) {
  final legacy = <String, Object?>{};
  for (final entry in params.entries) {
    if (entry.key == 'personal_agent_did') {
      legacy['message_agent_did'] = entry.value;
      continue;
    }
    if (entry.key == 'runtime_profile' && entry.value is Map) {
      final profile = (entry.value as Map).map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      if (profile['profile'] == 'personal_agent') {
        profile['profile'] = 'message_agent';
      }
      legacy[entry.key] = profile;
      continue;
    }
    legacy[entry.key] = entry.value;
  }
  return legacy;
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
