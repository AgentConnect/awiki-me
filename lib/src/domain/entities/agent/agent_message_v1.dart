/// Closed App projection of Core's typed `awiki.agent.message.v1` result.
/// Raw JSON is never accepted at this boundary.
sealed class AgentMessageProjection {
  const AgentMessageProjection();

  bool get isValid => this is ValidAgentMessageProjection;
}

final class ValidAgentMessageProjection extends AgentMessageProjection {
  const ValidAgentMessageProjection(this.message);

  final AgentMessageV1 message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidAgentMessageProjection && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

final class InvalidAgentMessageProjection extends AgentMessageProjection {
  const InvalidAgentMessageProjection();

  @override
  bool operator ==(Object other) => other is InvalidAgentMessageProjection;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class AgentMessageV1 {
  const AgentMessageV1({
    required this.eventId,
    required this.taskName,
    required this.kind,
    required this.level,
    required this.summary,
    required this.detail,
    required this.action,
  });

  static const schema = 'awiki.agent.message.v1';

  final String eventId;
  final String taskName;
  final AgentMessageKind kind;
  final AgentMessageLevel level;
  final String summary;
  final String? detail;
  final AgentMessageAction action;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentMessageV1 &&
          other.eventId == eventId &&
          other.taskName == taskName &&
          other.kind == kind &&
          other.level == level &&
          other.summary == summary &&
          other.detail == detail &&
          other.action == action;

  @override
  int get hashCode =>
      Object.hash(eventId, taskName, kind, level, summary, detail, action);
}

enum AgentMessageKind { message, taskResult, alert }

enum AgentMessageLevel { normal, urgent }

enum AgentMessageAction { openConversation }
