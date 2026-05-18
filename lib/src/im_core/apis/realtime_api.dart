import '../models/client_models.dart';

abstract class ImRealtimeApi {
  Future<void> connect(ImRealtimeConnectRequest request);
  Future<void> disconnect();
  Future<ImConnectionStateDto> status();
}

class ImRealtimeConnectRequest {
  const ImRealtimeConnectRequest({
    this.autoReconnect = true,
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 30),
    this.bootstrapFromSession = true,
  });

  final bool autoReconnect;
  final Duration reconnectBaseDelay;
  final Duration reconnectMaxDelay;
  final bool bootstrapFromSession;
}
