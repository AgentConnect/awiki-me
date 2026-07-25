import '../../domain/entities/remote_push_event.dart';
import '../../domain/services/remote_push_client.dart';

class NoopRemotePushClient implements RemotePushClient {
  const NoopRemotePushClient();

  @override
  Stream<RemotePushEvent> get events => const Stream<RemotePushEvent>.empty();

  @override
  RemotePushRegistration? get registration => null;

  @override
  List<RemotePushEvent> get pendingEvents => const <RemotePushEvent>[];

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {}

  @override
  Future<RemotePushRegistration?> initialize() async => null;

  @override
  Future<void> dispose() async {}
}
