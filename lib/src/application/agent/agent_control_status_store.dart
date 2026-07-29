abstract interface class AgentControlStatusStore {
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  });

  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  });

  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  });
}

final class AgentControlEvent {
  const AgentControlEvent({
    required this.messageId,
    required this.daemonAgentDid,
    required this.payload,
    required this.isReplay,
  });

  final String messageId;
  final String daemonAgentDid;
  final Map<String, Object?> payload;
  final bool isReplay;

  String get deduplicationKey {
    final eventId = payload['event_id']?.toString().trim();
    return eventId == null || eventId.isEmpty ? messageId : eventId;
  }
}

abstract interface class AgentControlEventStore {
  Stream<AgentControlEvent> watchDaemonControlEvents({
    required String daemonAgentDid,
  });
}

class NoopAgentControlStatusStore implements AgentControlStatusStore {
  const NoopAgentControlStatusStore();

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async {
    return null;
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) async {
    return null;
  }

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async {
    return null;
  }
}
