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

  Future<List<AgentSummary>> removeAgentFromAccount({required String agentDid});

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
    required String preferredLanguage,
    String? driverId,
    String? workspaceMode,
    String? defaultSandbox,
    String? defaultModel,
    Map<String, Object?>? driverConfig,
  });
}

class AgentInventoryMutationReceipt {
  const AgentInventoryMutationReceipt({required this.inventoryVersion});

  /// Canonical decimal for version-aware adapters; null only for a legacy
  /// implementation that cannot expose the committed domain version.
  final String? inventoryVersion;
}

class AgentInventoryMutationResult<T> extends AgentInventoryMutationReceipt {
  const AgentInventoryMutationResult({
    required this.value,
    required super.inventoryVersion,
  });

  final T value;
}

/// Optional version-preserving mutation boundary.
///
/// Legacy adapters can keep implementing [AgentInventoryPort]. The production
/// User Service adapter implements this interface so its committed account
/// domain version is not discarded at the App boundary.
abstract interface class VersionedAgentInventoryMutationPort {
  Future<AgentInventoryMutationResult<AgentSummary>>
  updateDisplayNameVersioned({
    required String agentDid,
    required String displayName,
  });

  Future<AgentInventoryMutationReceipt> unbindAgentVersioned({
    required String agentDid,
  });

  Future<AgentInventoryMutationResult<List<AgentSummary>>>
  removeAgentFromAccountVersioned({required String agentDid});

  Future<AgentInventoryMutationResult<AgentInvocationPolicy>>
  updateInvocationPolicyVersioned({
    required String agentDid,
    required AgentInvocationPolicy policy,
  });
}
