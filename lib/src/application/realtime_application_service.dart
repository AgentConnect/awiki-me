import '../domain/entities/realtime_update.dart';
import '../domain/services/realtime_gateway.dart';
import 'ports/realtime_core_port.dart';

abstract interface class RealtimeApplicationService {
  Stream<RealtimeConnectionStatus> get connectionStates;

  Stream<RealtimeUpdate> get updates;

  bool get isRunning;

  Future<void> start();

  Future<void> stop();
}

class ImCoreRealtimeApplicationService implements RealtimeApplicationService {
  const ImCoreRealtimeApplicationService({required RealtimeCorePort realtime})
    : _realtime = realtime;

  final RealtimeCorePort _realtime;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates =>
      _realtime.connectionStates;

  @override
  bool get isRunning => _realtime.isRunning;

  @override
  Stream<RealtimeUpdate> get updates => _realtime.updates;

  @override
  Future<void> start() => _realtime.start();

  @override
  Future<void> stop() => _realtime.stop();
}
