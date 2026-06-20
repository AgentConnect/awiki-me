import '../../domain/entities/agent/message_agent_binding.dart';

abstract interface class MessageAgentBindingPort {
  Future<MessageAgentBinding> ensureBinding({
    required String userDid,
    required String daemonAgentDid,
    required String messageAgentDid,
    required String runtimeProvider,
    required Map<String, Object?> runtimeProfile,
    required String delegatedKeyVerificationMethod,
  });

  Future<MessageAgentBinding?> getActiveBinding();

  Future<MessageAgentBinding> disableBinding({
    String? bindingId,
    String? messageAgentDid,
  });

  Future<MessageAgentBinding> revokeBinding({
    String? bindingId,
    String? messageAgentDid,
  });
}
