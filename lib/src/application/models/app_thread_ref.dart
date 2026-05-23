sealed class AppThreadRef {
  const AppThreadRef();

  const factory AppThreadRef.direct(String peerDidOrHandle) =
      AppDirectThreadRef;
  const factory AppThreadRef.group(String groupDid) = AppGroupThreadRef;
  const factory AppThreadRef.thread(String threadId) = AppMessageThreadRef;

  String get stableId;
}

class AppDirectThreadRef extends AppThreadRef {
  const AppDirectThreadRef(this.peerDidOrHandle);

  final String peerDidOrHandle;

  @override
  String get stableId => 'dm:$peerDidOrHandle';
}

class AppGroupThreadRef extends AppThreadRef {
  const AppGroupThreadRef(this.groupDid);

  final String groupDid;

  @override
  String get stableId => 'group:$groupDid';
}

class AppMessageThreadRef extends AppThreadRef {
  const AppMessageThreadRef(this.threadId);

  final String threadId;

  @override
  String get stableId => threadId;
}
