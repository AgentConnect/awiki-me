import '../entities/remote_push_event.dart';

class RemotePushRegistration {
  const RemotePushRegistration({
    required this.provider,
    required this.providerDeviceId,
    required this.platform,
  });

  final String provider;
  final String providerDeviceId;
  final String platform;
}

abstract interface class RemotePushClient {
  Stream<RemotePushEvent> get events;

  RemotePushRegistration? get registration;

  List<RemotePushEvent> get pendingEvents;

  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds);

  Future<RemotePushRegistration?> initialize();

  Future<void> dispose();
}
