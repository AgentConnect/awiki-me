import 'package:flutter/widgets.dart';

import '../../domain/entities/agent/agent_availability.dart';
import '../../l10n/l10n.dart';

String agentAvailabilityReasonText(
  BuildContext context,
  AgentAvailability value,
) => switch (value.reason) {
  'agent_deleted' => context.l10n.agentLifecycleDeletedReason,
  'agent_retired' => context.l10n.agentLifecycleRetiredReason,
  _ => context.l10n.agentLifecycleInactiveReason,
};
