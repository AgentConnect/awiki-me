import '../../domain/entities/realtime_update.dart';
import '../../domain/services/realtime_gateway.dart';

abstract interface class RealtimeCorePort {
  Stream<RealtimeConnectionStatus> get connectionStates;

  Stream<RealtimeUpdate> get updates;

  bool get isRunning;

  Future<void> start();

  Future<void> stop();
}
