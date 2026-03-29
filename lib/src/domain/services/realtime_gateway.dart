import '../entities/session_identity.dart';

typedef RealtimeMessageHandler = Future<void> Function(
  Map<String, Object?> event,
);

abstract class RealtimeGateway {
  Future<void> connect({
    required SessionIdentity session,
    required RealtimeMessageHandler onMessage,
  });

  Future<void> disconnect();

  bool get isConnected;
}
