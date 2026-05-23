import 'dart:async';

import '../../application/realtime_application_service.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/services/realtime_gateway.dart';
import 'compat_awiki_gateway.dart';

class CompatRealtimeGateway implements RealtimeGateway {
  CompatRealtimeGateway({required RealtimeApplicationService realtime})
    : _realtime = realtime;

  final RealtimeApplicationService _realtime;

  StreamSubscription<RealtimeConnectionStatus>? _statusSubscription;
  StreamSubscription<Object?>? _updateSubscription;
  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.idle;

  @override
  RealtimeConnectionStatus get connectionStatus => _status;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  @override
  bool get isConnected => _status == RealtimeConnectionStatus.connected;

  @override
  Future<void> connect({
    required SessionIdentity session,
    required RealtimeMessageHandler onMessage,
  }) async {
    await disconnect();
    _setStatus(RealtimeConnectionStatus.connecting);
    _statusSubscription = _realtime.connectionStates.listen(_setStatus);
    _updateSubscription = _realtime.updates.listen((update) {
      unawaited(
        onMessage(<String, Object?>{compatRealtimeUpdateEventKey: update}),
      );
    });
    await _realtime.start();
  }

  @override
  Future<void> disconnect() async {
    await _statusSubscription?.cancel();
    await _updateSubscription?.cancel();
    _statusSubscription = null;
    _updateSubscription = null;
    if (_realtime.isRunning) {
      await _realtime.stop();
    }
    _setStatus(RealtimeConnectionStatus.disconnected);
  }

  void _setStatus(RealtimeConnectionStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}
