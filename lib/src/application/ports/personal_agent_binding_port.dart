import '../../domain/entities/agent/personal_agent_binding.dart';

abstract interface class PersonalAgentBindingPort {
  Future<PersonalAgentBinding> ensureBinding({
    required String userDid,
    required String daemonAgentDid,
    required String personalAgentDid,
    required String runtimeProvider,
    required Map<String, Object?> runtimeProfile,
    required String delegatedKeyVerificationMethod,
  });

  Future<PersonalAgentBinding?> getActiveBinding();

  Future<PersonalAgentBinding> disableBinding({
    String? bindingId,
    String? personalAgentDid,
  });

  Future<PersonalAgentBinding> revokeBinding({
    String? bindingId,
    String? personalAgentDid,
  });
}
