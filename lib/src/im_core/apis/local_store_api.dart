abstract class ImLocalStoreApi {
  Future<ImStoreStatsDto> stats();
  Future<void> clear(ImClearStoreRequest request);
  Future<void> compact();
}

class ImStoreStatsDto {
  const ImStoreStatsDto({
    required this.messageCount,
    required this.conversationCount,
    required this.groupCount,
    required this.outboxCount,
    required this.unreadCount,
    required this.schemaVersion,
    required this.storePath,
  });

  final int messageCount;
  final int conversationCount;
  final int groupCount;
  final int outboxCount;
  final int unreadCount;
  final int schemaVersion;
  final String storePath;
}

class ImClearStoreRequest {
  const ImClearStoreRequest({this.ownerDid, this.includeOutbox = true});

  final String? ownerDid;
  final bool includeOutbox;
}
