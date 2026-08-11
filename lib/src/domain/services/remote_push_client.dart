import '../entities/remote_push_event.dart';

class RemotePushRegistration {
  const RemotePushRegistration({
    required this.provider,
    required this.providerDeviceId,
    required this.platform,
    required this.clientProduct,
    required this.clientVersion,
    required this.capabilities,
    this.appId,
    this.logicalDeviceId,
  });

  final String provider;
  final String providerDeviceId;
  final String platform;
  final String clientProduct;
  final String clientVersion;
  final List<String> capabilities;
  final String? appId;
  final String? logicalDeviceId;

  RemotePushRegistration withLogicalDeviceId(String? value) {
    final normalized = value?.trim();
    return RemotePushRegistration(
      provider: provider,
      providerDeviceId: providerDeviceId,
      platform: platform,
      clientProduct: clientProduct,
      clientVersion: clientVersion,
      capabilities: capabilities,
      appId: appId,
      logicalDeviceId: normalized == null || normalized.isEmpty
          ? null
          : normalized,
    );
  }
}

abstract interface class RemotePushClient {
  Stream<RemotePushEvent> get events;

  RemotePushRegistration? get registration;

  List<RemotePushEvent> get pendingEvents;

  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds);

  Future<RemotePushRegistration?> initialize();

  Future<void> dispose();
}

abstract interface class RemotePushPresentationTargetClient {
  Future<void> setActiveNotificationTargetReference(String? targetReference);
}
