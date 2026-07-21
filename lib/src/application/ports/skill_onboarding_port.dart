import '../../domain/entities/agent/skill_onboarding_instruction.dart';

abstract interface class SkillOnboardingPort {
  Future<SkillOnboardingGrant> issueSkillToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  });
}
