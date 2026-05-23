import 'dart:async';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/realtime_core_port.dart';
import '../../domain/entities/realtime_update.dart';
import '../../domain/services/realtime_gateway.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreRealtimeAdapter implements RealtimeCorePort {
  AwikiImCoreRealtimeAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
    core.RealtimeOptions options = const core.RealtimeOptions(
      reconnect: core.RealtimeReconnectMode.exponential,
    ),
  }) : _runtime = runtime,
       _mappers = mappers,
       _options = options;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;
  final core.RealtimeOptions _options;

  final StreamController<RealtimeUpdate> _updatesController =
      StreamController<RealtimeUpdate>.broadcast();
  final StreamController<RealtimeConnectionStatus> _connectionController =
      StreamController<RealtimeConnectionStatus>.broadcast();

  core.AwikiImClient? _client;
  core.RealtimeSession? _session;
  StreamSubscription<core.RealtimeEvent>? _eventSubscription;
  StreamSubscription<core.RealtimeConnectionState>? _stateSubscription;
  String? _ownerDid;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates =>
      _connectionController.stream;

  @override
  bool get isRunning => _session != null;

  @override
  Stream<RealtimeUpdate> get updates => _updatesController.stream;

  @override
  Future<void> start() async {
    if (_session != null) {
      return;
    }
    final client = await _runtime.currentClient();
    _client = client;
    _ownerDid = (await client.identity.current()).did;
    _eventSubscription = client.events.listen(
      _handleEvent,
      onError: _updatesController.addError,
    );
    _stateSubscription = client.connectionStates.listen(
      (state) =>
          _connectionController.add(_mappers.connectionStatusFromCore(state)),
      onError: _connectionController.addError,
    );
    _connectionController.add(RealtimeConnectionStatus.connecting);
    _session = await client.realtime.start(options: _options);
  }

  @override
  Future<void> stop() async {
    final session = _session;
    _session = null;
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription = null;
    if (session != null) {
      await session.stop();
    } else {
      await _client?.realtime.stop();
    }
    _connectionController.add(RealtimeConnectionStatus.disconnected);
    _client = null;
    _ownerDid = null;
  }

  void _handleEvent(core.RealtimeEvent event) {
    final ownerDid = _ownerDid;
    if (ownerDid == null) {
      return;
    }
    final update = _mappers.realtimeUpdateFromCore(event, ownerDid: ownerDid);
    if (update != null) {
      _updatesController.add(update);
    }
  }
}
