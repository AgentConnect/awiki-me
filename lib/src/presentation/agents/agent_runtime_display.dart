import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_summary.dart';

class AgentRuntimeDisplay {
  const AgentRuntimeDisplay({
    required this.label,
    required this.isKnown,
    this.runtime,
    this.driverId,
  });

  final String label;
  final bool isKnown;
  final String? runtime;
  final String? driverId;
}

AgentRuntimeDisplay agentRuntimeDisplay(AgentSummary agent) {
  final runtime = _normalizeToken(agent.runtime);
  final driverId = _normalizeToken(agent.latest.runtimeCard?.driverId);
  return agentRuntimeDisplayFor(runtime: runtime, driverId: driverId);
}

AgentRuntimeDisplay agentRuntimeDisplayFor({
  String? runtime,
  String? driverId,
}) {
  runtime = _normalizeToken(runtime);
  driverId = _normalizeToken(driverId);
  final kind = _runtimeKindFor(runtime: runtime, driverId: driverId);
  if (kind != null) {
    return AgentRuntimeDisplay(
      label: kind.displayLabel,
      isKnown: true,
      runtime: runtime,
      driverId: driverId,
    );
  }
  return AgentRuntimeDisplay(
    label: 'Agent',
    isKnown: false,
    runtime: runtime,
    driverId: driverId,
  );
}

RuntimeAgentKind? _runtimeKindFor({String? runtime, String? driverId}) {
  for (final kind in RuntimeAgentKind.values) {
    final kindDriverId = kind.driverId;
    if (runtime == kind.runtime ||
        (driverId != null &&
            kindDriverId != null &&
            driverId == kindDriverId)) {
      return kind;
    }
  }
  if (runtime == 'claude_code' || driverId == 'claude_code') {
    return RuntimeAgentKind.claudeCode;
  }
  if (runtime == 'codex-cli') {
    return RuntimeAgentKind.codex;
  }
  return null;
}

String? _normalizeToken(String? value) {
  final text = value?.trim().toLowerCase();
  return text == null || text.isEmpty ? null : text;
}
