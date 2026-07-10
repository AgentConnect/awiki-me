import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/data/services/user_service_peer_identity_service.dart';
import 'package:awiki_me/src/domain/entities/peer_agent_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'blank identity resolves as human without calling user service',
    () async {
      final userClient = _FakeOnboardingUtilityClient();
      final service = UserServicePeerIdentityService(
        userServiceUrl: 'https://user.example',
        userClient: userClient,
      );

      final identity = await service.resolveAgentIdentity('   ');

      expect(identity.isAgent, isFalse);
      expect(userClient.requestedIdentities, isEmpty);
    },
  );

  test('resolves runtime agent identity from public profile', () async {
    final userClient = _FakeOnboardingUtilityClient(
      responses: <String, Map<String, Object?>>{
        'did:agent:runtime': <String, Object?>{
          'is_agent': true,
          'agent_kind': 'runtime',
        },
      },
    );
    final service = UserServicePeerIdentityService(
      userServiceUrl: 'https://user.example',
      userClient: userClient,
    );

    final identity = await service.resolveAgentIdentity(' did:agent:runtime ');

    expect(identity.isAgent, isTrue);
    expect(identity.agentKind, PeerAgentKind.runtime);
    expect(userClient.requestedIdentities, <String>['did:agent:runtime']);
  });

  test('unknown agent kind stays agent without guessing kind', () async {
    final userClient = _FakeOnboardingUtilityClient(
      responses: <String, Map<String, Object?>>{
        '@agent.example': <String, Object?>{
          'is_agent': true,
          'agent_kind': 'other',
        },
      },
    );
    final service = UserServicePeerIdentityService(
      userServiceUrl: 'https://user.example',
      userClient: userClient,
    );

    final identity = await service.resolveAgentIdentity('@agent.example');

    expect(identity.isAgent, isTrue);
    expect(identity.agentKind, isNull);
  });

  test('remote full handle is delegated to user service unchanged', () async {
    final userClient = _FakeOnboardingUtilityClient(
      responses: <String, Map<String, Object?>>{
        'agent.remote.example': <String, Object?>{
          'is_agent': true,
          'agent_kind': 'runtime',
          'handle': 'agent.remote.example',
          'did': 'did:wba:remote.example:user:agent:e1',
        },
      },
    );
    final service = UserServicePeerIdentityService(
      userServiceUrl: 'https://user.example',
      userClient: userClient,
    );

    final identity = await service.resolveAgentIdentity(
      '  agent.remote.example  ',
    );

    expect(identity.isAgent, isTrue);
    expect(identity.agentKind, PeerAgentKind.runtime);
    expect(userClient.requestedIdentities, <String>['agent.remote.example']);
  });
}

class _FakeOnboardingUtilityClient extends AwikiOnboardingUtilityClient {
  _FakeOnboardingUtilityClient({
    this.responses = const <String, Map<String, Object?>>{},
  }) : super(
         serviceClient: AwikiOnboardingUtilityHttpClient(
           baseUrl: 'https://unused.example',
         ),
       );

  final Map<String, Map<String, Object?>> responses;
  final List<String> requestedIdentities = <String>[];

  @override
  Future<Map<String, Object?>> getPublicProfile({
    required String didOrHandle,
  }) async {
    requestedIdentities.add(didOrHandle);
    return responses[didOrHandle] ?? const <String, Object?>{};
  }
}
