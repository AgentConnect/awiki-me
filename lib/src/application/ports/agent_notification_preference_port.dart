import '../models/agent_notification_preference.dart';

abstract interface class AgentNotificationPreferencePort {
  Future<AgentNotificationPreference> getAgentNotificationPreference();

  Future<AgentNotificationPreference> setAgentNotificationPreference({
    required AgentNotificationUrgentPreference urgent,
  });
}
