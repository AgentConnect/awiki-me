import 'dart:async';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_realtime_adapter.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stale owner stop cannot clear a replacement realtime run', () async {
    final oldStop = Completer<void>();
    final firstClient = _FakeCoreClient(
      ownerDid: 'did:wba:awiki.ai:alice:e1_first',
      session: _FakeRealtimeSession(onStop: () => oldStop.future),
    );
    final secondClient = _FakeCoreClient(
      ownerDid: 'did:wba:awiki.ai:bob:e1_second',
      session: _FakeRealtimeSession(),
    );
    final runtime = _FakeRuntime(firstClient);
    final adapter = AwikiImCoreRealtimeAdapter(runtime: runtime);
    final updates = <RealtimeUpdate>[];
    final statuses = <RealtimeConnectionStatus>[];
    final updateSubscription = adapter.updates.listen(updates.add);
    final statusSubscription = adapter.connectionStates.listen(statuses.add);

    await adapter.start();
    final firstStop = adapter.stop();
    await pumpEventQueue();
    expect(firstClient.realtimeApi.session.stopCount, 1);
    expect(adapter.isRunning, isFalse);

    runtime.selectedClient = secondClient;
    await adapter.start();
    expect(adapter.isRunning, isTrue);

    firstClient.addEvent(_groupUpdate('stale-first'));
    secondClient.addEvent(_groupUpdate('second-live'));
    await pumpEventQueue();
    expect(updates.map((update) => update.syncEventSeq), <String?>[
      'second-live',
    ]);

    oldStop.complete();
    await firstStop;
    expect(adapter.isRunning, isTrue);
    expect(statuses.last, isNot(RealtimeConnectionStatus.disconnected));

    secondClient.addEvent(_groupUpdate('second-after-old-stop'));
    await pumpEventQueue();
    expect(updates.map((update) => update.syncEventSeq), <String?>[
      'second-live',
      'second-after-old-stop',
    ]);

    await adapter.stop();
    await updateSubscription.cancel();
    await statusSubscription.cancel();
    await firstClient.close();
    await secondClient.close();
  });

  test('concurrent start and repeated stop are idempotent', () async {
    final startGate = Completer<void>();
    final stopGate = Completer<void>();
    final client = _FakeCoreClient(
      ownerDid: 'did:wba:awiki.ai:alice:e1_owner',
      session: _FakeRealtimeSession(onStop: () => stopGate.future),
      onStart: () => startGate.future,
    );
    final adapter = AwikiImCoreRealtimeAdapter(runtime: _FakeRuntime(client));

    final firstStart = adapter.start();
    final secondStart = adapter.start();
    await pumpEventQueue();
    expect(client.realtimeApi.startCount, 1);
    expect(adapter.isRunning, isTrue);

    startGate.complete();
    await Future.wait(<Future<void>>[firstStart, secondStart]);

    final firstStop = adapter.stop();
    final secondStop = adapter.stop();
    var secondStopCompleted = false;
    unawaited(secondStop.then((_) => secondStopCompleted = true));
    await pumpEventQueue();
    expect(client.realtimeApi.session.stopCount, 1);
    expect(adapter.isRunning, isFalse);
    expect(secondStopCompleted, isFalse);

    stopGate.complete();
    await Future.wait(<Future<void>>[firstStop, secondStop]);
    expect(secondStopCompleted, isTrue);
    expect(client.realtimeApi.session.stopCount, 1);
    await client.close();
  });

  test('rapid replacement survives completion of a stale start', () async {
    final oldStart = Completer<void>();
    final firstClient = _FakeCoreClient(
      ownerDid: 'did:wba:awiki.ai:alice:e1_first',
      session: _FakeRealtimeSession(),
      onStart: () => oldStart.future,
    );
    final secondClient = _FakeCoreClient(
      ownerDid: 'did:wba:awiki.ai:bob:e1_second',
      session: _FakeRealtimeSession(),
    );
    final runtime = _FakeRuntime(firstClient);
    final adapter = AwikiImCoreRealtimeAdapter(runtime: runtime);
    final updates = <RealtimeUpdate>[];
    final updateSubscription = adapter.updates.listen(updates.add);

    final firstStart = adapter.start();
    await pumpEventQueue();
    final firstStop = adapter.stop();
    runtime.selectedClient = secondClient;
    await adapter.start();

    oldStart.complete();
    await firstStart;
    await firstStop;
    expect(adapter.isRunning, isTrue);
    expect(firstClient.realtimeApi.session.stopCount, 1);
    expect(secondClient.realtimeApi.session.stopCount, 0);

    firstClient.addEvent(_groupUpdate('stale-first'));
    secondClient.addEvent(_groupUpdate('second-live'));
    await pumpEventQueue();
    expect(updates.map((update) => update.syncEventSeq), <String?>[
      'second-live',
    ]);

    await adapter.stop();
    await updateSubscription.cancel();
    await firstClient.close();
    await secondClient.close();
  });
}

core.RealtimeEvent _groupUpdate(String eventSequence) {
  return core.RealtimeEvent(
    kind: 'group_updated',
    sync: core.RealtimeSyncHint(
      eventSeq: eventSequence,
      syncDirty: true,
      gapDetected: false,
    ),
  );
}

class _FakeRuntime implements AwikiImCoreRuntime {
  _FakeRuntime(this.selectedClient);

  core.AwikiImClient selectedClient;

  @override
  Future<T> withCurrentClient<T>(
    Future<T> Function(core.AwikiImClient client) action,
  ) {
    return action(selectedClient);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoreClient implements core.AwikiImClient {
  _FakeCoreClient({
    required String ownerDid,
    required _FakeRealtimeSession session,
    Future<void> Function()? onStart,
  }) : identityApi = _FakeIdentityApi(ownerDid),
       realtimeApi = _FakeRealtimeApi(session: session, onStart: onStart);

  final _FakeIdentityApi identityApi;
  final _FakeRealtimeApi realtimeApi;
  final StreamController<core.RealtimeEvent> eventController =
      StreamController<core.RealtimeEvent>.broadcast();
  final StreamController<core.RealtimeConnectionState> connectionController =
      StreamController<core.RealtimeConnectionState>.broadcast();

  @override
  Stream<core.RealtimeConnectionState> get connectionStates =>
      connectionController.stream;

  @override
  Stream<core.RealtimeEvent> get events => eventController.stream;

  @override
  core.IdentityApi get identity => identityApi;

  @override
  core.RealtimeApi get realtime => realtimeApi;

  void addEvent(core.RealtimeEvent event) => eventController.add(event);

  Future<void> close() async {
    await eventController.close();
    await connectionController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentityApi implements core.IdentityApi {
  _FakeIdentityApi(this.ownerDid);

  final String ownerDid;

  @override
  Future<core.IdentitySummary> current() async {
    return core.IdentitySummary(
      id: ownerDid,
      did: ownerDid,
      isDefault: true,
      readyForAuth: true,
      readyForMessaging: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRealtimeApi implements core.RealtimeApi {
  _FakeRealtimeApi({required this.session, this.onStart});

  final _FakeRealtimeSession session;
  final Future<void> Function()? onStart;
  int startCount = 0;

  @override
  Future<core.RealtimeSession> start({
    core.RealtimeOptions options = const core.RealtimeOptions(),
  }) async {
    startCount += 1;
    await onStart?.call();
    return session;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRealtimeSession implements core.RealtimeSession {
  _FakeRealtimeSession({this.onStop});

  final Future<void> Function()? onStop;
  int stopCount = 0;

  @override
  Future<void> dispose() => stop();

  @override
  Future<void> stop() async {
    stopCount += 1;
    await onStop?.call();
  }
}
