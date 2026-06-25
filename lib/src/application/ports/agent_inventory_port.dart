import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';

abstract interface class AgentInventoryPort {
  Future<List<AgentSummary>> listAgents({bool includeInactive = false});

  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  });

  Future<void> unbindAgent({required String agentDid});

  Future<AgentInvocationPolicy> getInvocationPolicy({required String agentDid});

  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  });

  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  });

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
  });
}
