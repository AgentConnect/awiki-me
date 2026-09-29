import 'ports/remote_push_sync_port.dart';
import 'remote_push_message_reference.dart';

/// A native presentation mirror, never the source of conversation mute state.
abstract interface class NotifyMuteSnapshotSource {
  Future<Set<String>> loadMutedNotificationPeerDids({required String ownerDid});
}

class TextNotifyMuteCoordinator {
  TextNotifyMuteCoordinator({
    required this.isCurrent,
    required this.loadMutedPeers,
    required this.begin,
    required this.replace,
  });

  final bool Function(RemotePushSessionContext) isCurrent;
  final Future<Set<String>> Function(RemotePushSessionContext) loadMutedPeers;
  final Future<int?> Function(String target) begin;
  final Future<bool> Function(
    String target,
    int revision,
    List<String> identities,
  )
  replace;
  Future<void> _tail = Future<void>.value();
  RemotePushSessionContext? _ready;

  Future<void> ensureReady(RemotePushSessionContext context) =>
      _serialize(() async {
        if (!isCurrent(context) || context.matches(_ready)) return;
        await _synchronize(context);
      });

  /// Invalidate the mirror before changing canonical data. A failed native write
  /// leaves presentation closed and is retried on the next foreground activation.
  Future<void> update(
    RemotePushSessionContext context,
    Future<void> Function() saveCanonical,
  ) => _serialize(() => _synchronize(context, saveCanonical: saveCanonical));

  Future<void> _synchronize(
    RemotePushSessionContext context, {
    Future<void> Function()? saveCanonical,
  }) async {
    if (!isCurrent(context)) throw StateError('notify_session_changed');
    _ready = null;
    final target = remotePushOpaqueTargetReference(context.ownerDid);
    final revision = await begin(target);
    if (revision == null) throw StateError('notify_mute_invalidation_failed');
    if (!isCurrent(context)) throw StateError('notify_session_changed');
    await saveCanonical?.call();
    if (!isCurrent(context)) throw StateError('notify_session_changed');
    final peers = await loadMutedPeers(context);
    if (!isCurrent(context)) throw StateError('notify_session_changed');
    final saved = await replace(
      target,
      revision,
      peers.map(remotePushOpaqueIdentityReference).toList(),
    );
    if (!saved) throw StateError('notify_mute_snapshot_failed');
    if (isCurrent(context)) _ready = context;
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.catchError((Object _) {});
    return result;
  }
}
