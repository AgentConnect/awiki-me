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

  _RealtimeRun? _activeRun;
  final Set<Future<void>> _drainingStops = <Future<void>>{};

  @override
  Stream<RealtimeConnectionStatus> get connectionStates =>
      _connectionController.stream;

  @override
  bool get isRunning => _activeRun != null;

  @override
  Stream<RealtimeUpdate> get updates => _updatesController.stream;

  @override
  Future<void> start() {
    final active = _activeRun;
    if (active != null) {
      return active.startOperation;
    }

    final run = _RealtimeRun();
    _activeRun = run;
    run.startOperation = _startRun(run);
    return run.startOperation;
  }

  @override
  Future<void> stop() {
    final run = _activeRun;
    if (run == null) {
      return _waitForDrainingStops();
    }

    // Invalidate synchronously. A replacement run can start while native
    // shutdown is still draining, and callbacks from this run are ignored.
    _activeRun = null;
    final operation = _stopRun(run);
    _trackDrainingStop(operation);
    return _waitForDrainingStops();
  }

  Future<void> _startRun(_RealtimeRun run) async {
    try {
      await _runtime.withCurrentClient((client) async {
        final ownerDid = (await client.identity.current()).did;
        if (!_isActive(run)) {
          return;
        }
        run.ownerDid = ownerDid;
        run.eventSubscription = client.events.listen(
          (event) => _handleEvent(run, event),
          onError: (Object error, StackTrace stackTrace) {
            if (_isActive(run)) {
              _updatesController.addError(error, stackTrace);
            }
          },
        );
        run.stateSubscription = client.connectionStates.listen(
          (state) {
            if (_isActive(run)) {
              _connectionController.add(
                _mappers.connectionStatusFromCore(state),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (_isActive(run)) {
              _connectionController.addError(error, stackTrace);
            }
          },
        );
        if (!_isActive(run)) {
          return;
        }
        _connectionController.add(RealtimeConnectionStatus.connecting);
        run.session = await client.realtime.start(options: _options);
      });
    } on Object catch (error, stackTrace) {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
      try {
        await _cleanupRun(run);
      } on Object {
        // Preserve the start failure. Cleanup remains best effort here and a
        // concurrent stop observes the same idempotent cleanup operation.
      }
      _publishDisconnectedIfIdle();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _stopRun(_RealtimeRun run) async {
    Object? startError;
    StackTrace? startStackTrace;
    try {
      await run.startOperation;
    } on Object catch (error, stackTrace) {
      startError = error;
      startStackTrace = stackTrace;
    }

    try {
      await _cleanupRun(run);
    } finally {
      _publishDisconnectedIfIdle();
    }

    if (startError != null) {
      Error.throwWithStackTrace(startError, startStackTrace!);
    }
  }

  Future<void> _cleanupRun(_RealtimeRun run) {
    return run.cleanupOperation ??= _performCleanup(run);
  }

  void _trackDrainingStop(Future<void> operation) {
    _drainingStops.add(operation);
    operation.then<void>(
      (_) => _drainingStops.remove(operation),
      onError: (Object _, StackTrace _) {
        _drainingStops.remove(operation);
      },
    );
  }

  Future<void> _waitForDrainingStops() {
    final pending = _drainingStops.toList(growable: false);
    if (pending.isEmpty) {
      return Future<void>.value();
    }
    return Future.wait(pending);
  }

  Future<void> _performCleanup(_RealtimeRun run) async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> cleanupStep(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    final eventSubscription = run.eventSubscription;
    run.eventSubscription = null;
    if (eventSubscription != null) {
      await cleanupStep(eventSubscription.cancel);
    }
    final stateSubscription = run.stateSubscription;
    run.stateSubscription = null;
    if (stateSubscription != null) {
      await cleanupStep(stateSubscription.cancel);
    }
    final session = run.session;
    run.session = null;
    if (session != null) {
      await cleanupStep(session.stop);
    }
    run.ownerDid = null;

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  bool _isActive(_RealtimeRun run) => identical(_activeRun, run);

  void _publishDisconnectedIfIdle() {
    if (_activeRun == null) {
      _connectionController.add(RealtimeConnectionStatus.disconnected);
    }
  }

  void _handleEvent(_RealtimeRun run, core.RealtimeEvent event) {
    final ownerDid = run.ownerDid;
    if (!_isActive(run) || ownerDid == null) {
      return;
    }
    final update = _mappers.realtimeUpdateFromCore(event, ownerDid: ownerDid);
    if (update != null) {
      _updatesController.add(update);
    }
  }
}

class _RealtimeRun {
  late Future<void> startOperation;
  Future<void>? cleanupOperation;
  core.RealtimeSession? session;
  StreamSubscription<core.RealtimeEvent>? eventSubscription;
  StreamSubscription<core.RealtimeConnectionState>? stateSubscription;
  String? ownerDid;
}
