enum ImThreadKind { direct, group }

enum ImMessageDirection { inbound, outbound, system }

enum ImMessageKind {
  text,
  attachment,
  system,
  directCipher,
  directInit,
  groupCipher,
  unknown,
}

enum ImSendState { draft, queued, sending, sent, delivered, failed }

enum ImReadState { unread, read }

enum ImSecurityMode { transportProtected, directE2ee, groupE2ee }

enum ImConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}

enum ImRuntimeMode { fake, http, websocket }

class ImPage<T> {
  const ImPage({required this.items, this.nextCursor, required this.hasMore});

  final List<T> items;
  final String? nextCursor;
  final bool hasMore;
}

class ImPeerRef {
  const ImPeerRef({this.did, this.handle, this.displayName});

  final String? did;
  final String? handle;
  final String? displayName;
}

class ImThreadRef {
  const ImThreadRef({
    required this.threadId,
    required this.kind,
    this.peerDid,
    this.peerHandle,
    this.groupId,
  });

  final String threadId;
  final ImThreadKind kind;
  final String? peerDid;
  final String? peerHandle;
  final String? groupId;
}
