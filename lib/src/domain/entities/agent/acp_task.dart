import 'acp_session.dart';
import '../chat_message.dart';
import '../message_reply_reference.dart';

bool isAcpTerminalState(String state) =>
    const {'finished', 'cancelled', 'failed', 'interrupted'}.contains(state);

/// Execution metadata received through committed controls. It is not a message
/// store; only Core can bind a local conversation or provide a final reply.
class AcpTask {
  AcpTask._(this.data, this.conversationId);
  final Map<String, Object?> data;
  final String? conversationId;

  static AcpTask? parse(Object? value, {String? localConversationId}) {
    final data = acpMap(value);
    if (data['schema'] != 'awiki.acp.task.v1' ||
        data['revision'] is! int ||
        (data['revision']! as int) < 1) {
      return null;
    }
    for (final key in [
      'session_key',
      'agent_did',
      'run_id',
      'source_message_id',
      'state',
    ]) {
      if (data[key] is! String || (data[key]! as String).trim().isEmpty) {
        return null;
      }
    }
    if (!const {
      'running',
      'stopping',
      'waiting',
      'paused',
      'finished',
      'cancelled',
      'failed',
      'interrupted',
    }.contains(data['state'])) {
      return null;
    }
    return AcpTask._(Map.unmodifiable(data), localConversationId);
  }

  String get sessionKey => data['session_key']! as String;
  String get agentDid => data['agent_did']! as String;
  String get runId => data['run_id']! as String;
  String get sourceMessageId => data['source_message_id']! as String;
  String get state => data['state']! as String;
  String get key => '$agentDid:$runId';
  int get revision => data['revision']! as int;
  bool get group => data['group'] == true;
  bool get terminal => isAcpTerminalState(state);
  bool get running => state == 'running' || state == 'stopping';
  String get text => data['text']?.toString() ?? '';
  String? get requesterDid =>
      data['requester_did'] is String ? data['requester_did']! as String : null;
  String? get errorCode =>
      data['error_code'] is String ? data['error_code']! as String : null;
  List<Map<String, Object?>> get tools => acpMaps(data['tools']);
  List<Map<String, Object?>> get questions => acpMaps(data['questions']);
  int get omittedToolCount => data['omitted_tool_count'] is int
      ? (data['omitted_tool_count']! as int).clamp(0, 1 << 30)
      : 0;
  Map<String, Object?> get delivery => acpMap(data['delivery']);

  AcpTask withConversation(String id) => AcpTask._(data, id);
}

/// Handoff requires the committed reply's sender and exact task association.
/// A delivery acknowledgement alone never removes a visible preview.
ChatMessage? acpFinalReplyForTask(
  AcpTask task,
  Iterable<ChatMessage> messages,
) {
  for (final message in messages) {
    if (message.sendState != MessageSendState.sent ||
        message.isMine ||
        task.group != (message.groupId?.isNotEmpty == true) ||
        message.senderDid != task.agentDid ||
        message.conversationId != task.conversationId) {
      continue;
    }
    final reference = MessageReplyReference.tryParse(message.payloadJson);
    if (reference?.sourceMessageId != task.sourceMessageId) continue;
    if (reference!.runId != null && reference.runId != task.runId) continue;
    // Pre-upgrade ACP finals have a source ID but no run annotation. Source
    // messages are accepted at most once per agent/session.
    return message;
  }
  return null;
}
