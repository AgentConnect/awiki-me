Map<String, Object?> acpMap(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : const {};
List<Map<String, Object?>> acpMaps(Object? value) => value is List
    ? value.whereType<Map>().map(acpMap).toList(growable: false)
    : const [];

/// A projection of a complete, committed Daemon snapshot. It owns no messages.
class AcpSession {
  AcpSession._(this.data, this.conversationId);
  final Map<String, Object?> data;

  /// Local routing identity comes from Core's committed message, since each
  /// participant has its own Direct conversation ID.
  final String conversationId;
  static AcpSession? parse(Object? value, {String? localConversationId}) {
    final data = acpMap(value);
    if (data['schema'] != 'awiki.acp.session.v1' ||
        data['revision'] is! int ||
        (data['revision']! as int) < 1) {
      return null;
    }
    for (final key in ['session_key', 'agent_did', 'conversation_id']) {
      if (data[key] is! String || (data[key]! as String).trim().isEmpty) {
        return null;
      }
    }
    return AcpSession._(
      Map.unmodifiable(data),
      localConversationId ?? data['conversation_id']! as String,
    );
  }

  String get key => data['session_key']! as String;
  String get agentDid => data['agent_did']! as String;
  int get revision => data['revision']! as int;
  bool get group => data['group'] == true;
  bool get stopping => data['stopping'] == true;
  bool get contextLost => data['context_lost'] == true;
  bool get waitingPaused => data['waiting_paused'] == true;
  Map<String, Object?> get active => acpMap(data['active']);
  Map<String, Object?> get waiting => acpMap(data['waiting']);
  bool get busy => active.isNotEmpty;
  bool get canSelectModel => !busy && waiting.isEmpty && !contextLost;
  String get text => data['text']?.toString() ?? '';
  List<Map<String, Object?>> get tools => acpMaps(data['tools']);
  List<Map<String, Object?>> get questions => acpMaps(data['questions']);
  List<Map<String, Object?>> get models => acpMaps(data['models']);
  List<Map<String, Object?>> get history => acpMaps(data['history']);
  Map<String, Object?>? taskFor(Set<String> messageIds) {
    if (messageIds.contains(active['source_message_id'])) {
      return {...active, 'state': stopping ? 'stopping' : 'running'};
    }
    if (messageIds.contains(waiting['source_message_id'])) {
      return {...waiting, 'state': 'waiting'};
    }
    for (final task in history.reversed) {
      if (messageIds.contains(task['source_message_id'])) return task;
    }
    return null;
  }
}

enum AcpSendBlock {
  offline,
  waitingFull,
  groupBusy,
  contextLost,
  modelChanging,
}

AcpSendBlock? acpSendBlock({
  required AcpSession? session,
  required bool daemonOffline,
  required bool group,
  required bool invokesAgent,
}) {
  if (!invokesAgent) return null;
  if (daemonOffline) return AcpSendBlock.offline;
  if (session?.contextLost == true) return AcpSendBlock.contextLost;
  if (group) return session?.busy == true ? AcpSendBlock.groupBusy : null;
  return session?.waiting.isNotEmpty == true ? AcpSendBlock.waitingFull : null;
}
