import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/install_command.dart';

abstract interface class AgentInventoryPort {
  Future<List<AgentSummary>> listAgents({bool includeInactive = false});

  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  });

  Future<void> unbindAgent({required String agentDid});

  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String clientPlatform,
  });

  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
  });
}
