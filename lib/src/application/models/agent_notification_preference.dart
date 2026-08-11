enum AgentNotificationUrgentPreference { enabled, disabled, unset }

final class AgentNotificationPreference {
  const AgentNotificationPreference({
    required this.schema,
    required this.urgent,
    required this.updatedAt,
  });

  final String schema;
  final AgentNotificationUrgentPreference urgent;
  final DateTime? updatedAt;

  bool get urgentEnabled => urgent == AgentNotificationUrgentPreference.enabled;
}
