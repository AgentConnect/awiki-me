import '../domain/entities/peer_agent_identity.dart';

abstract interface class PeerIdentityService {
  Future<PeerAgentIdentity> resolveAgentIdentity(String didOrHandle);
}
