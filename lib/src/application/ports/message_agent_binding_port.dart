import '../../domain/entities/agent/message_agent_binding.dart';

abstract interface class MessageAgentBindingPort {
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
