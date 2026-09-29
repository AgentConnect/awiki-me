import '../../domain/entities/agent/agent_availability.dart';

/// Optional additive facade. Older adapters can retain their inventory contract.
abstract interface class AgentAvailabilityPort {
  Future<List<AgentAvailability>> getAgentAvailability(List<String> agentDids);
}
