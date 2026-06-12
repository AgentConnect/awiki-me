import '../../application/config/awiki_environment_config.dart';
import '../../application/peer_identity_service.dart';
import '../../domain/entities/peer_agent_identity.dart';
import 'awiki_onboarding_utility_client.dart';

class UserServicePeerIdentityService implements PeerIdentityService {
  UserServicePeerIdentityService({
    required this.userServiceUrl,
    AwikiOnboardingUtilityClient? userClient,
  }) : _userClient = userClient;

  factory UserServicePeerIdentityService.fromEnvironment() {
    final userServiceUrl =
        AwikiEnvironmentConfig.fromEnvironment().userServiceUrl;
    return UserServicePeerIdentityService(userServiceUrl: userServiceUrl);
  }

  final String userServiceUrl;
  final AwikiOnboardingUtilityClient? _userClient;
  AwikiOnboardingUtilityClient? _cachedUserClient;

  AwikiOnboardingUtilityClient get _users {
    return _userClient ??
        (_cachedUserClient ??= AwikiOnboardingUtilityClient(
          serviceClient: AwikiOnboardingUtilityHttpClient(
            baseUrl: userServiceUrl,
          ),
        ));
  }

  @override
  Future<PeerAgentIdentity> resolveAgentIdentity(String didOrHandle) async {
    final identity = didOrHandle.trim();
    if (identity.isEmpty) {
      return const PeerAgentIdentity.human();
    }
    final result = await _users.getPublicProfile(didOrHandle: identity);
    return PeerAgentIdentity.fromJson(result);
  }
}
