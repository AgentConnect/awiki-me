import 'dart:async';

import 'package:awiki_me/src/application/models/push_installation.dart';
import 'package:awiki_me/src/application/ports/push_installation_port.dart';
import 'package:awiki_me/src/application/remote_push_installation_coordinator.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:awiki_me/src/domain/services/remote_push_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'first bind initializes Push and upserts session metadata once',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final installations = _FakePushInstallationPort();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );

      await coordinator.bindActiveSession(_alice(logicalDeviceId: 'logical-a'));

      expect(client.initializeCount, 1);
      expect(installations.upserts, hasLength(1));
      expect(installations.upserts.single.providerDeviceId, 'device-a');
      expect(installations.upserts.single.logicalDeviceId, 'logical-a');
    },
  );

  test('same session and registration bind is idempotent', () async {
    final client = _FakeRemotePushClient(_registration('device-a'));
    final installations = _FakePushInstallationPort();
    final coordinator = RemotePushInstallationCoordinator(
      client: client,
      installations: installations,
    );
    final session = _alice();

    await coordinator.bindActiveSession(session);
    await coordinator.bindActiveSession(session);

    expect(installations.upserts, hasLength(1));
    expect(installations.disables, isEmpty);
  });

  test('registration refresh replaces the prior provider DeviceId', () async {
    final client = _FakeRemotePushClient(_registration('device-a'));
    final installations = _FakePushInstallationPort();
    final coordinator = RemotePushInstallationCoordinator(
      client: client,
      installations: installations,
    );
    final session = _alice();
    await coordinator.bindActiveSession(session);

    client.registrationValue = _registration('device-b');
    await coordinator.refreshActiveSession(session);

    expect(installations.calls, <String>[
      'upsert:device-a',
      'disable:installation-1',
      'upsert:device-b',
    ]);
  });

  test(
    'same epoch logical device metadata refresh replaces the installation',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final installations = _FakePushInstallationPort();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );
      await coordinator.bindActiveSession(_alice());

      await coordinator.refreshActiveSession(
        _alice(logicalDeviceId: 'device-D'),
      );

      expect(installations.calls, <String>[
        'upsert:device-a',
        'disable:installation-1',
        'upsert:device-a',
      ]);
      expect(
        installations.upserts.map((item) => item.logicalDeviceId),
        <String?>[null, 'device-D'],
      );
    },
  );

  test('disable after metadata refresh uses the latest installation', () async {
    final client = _FakeRemotePushClient(_registration('device-a'));
    final installations = _FakePushInstallationPort();
    final coordinator = RemotePushInstallationCoordinator(
      client: client,
      installations: installations,
    );
    await coordinator.bindActiveSession(_alice());
    final sessionWithDevice = _alice(logicalDeviceId: 'device-D');
    await coordinator.refreshActiveSession(sessionWithDevice);

    await coordinator.disableActiveInstallation(sessionWithDevice);
    await coordinator.refreshActiveSession(sessionWithDevice);

    expect(installations.disables, <String>[
      'installation-1',
      'installation-2',
    ]);
    expect(installations.upserts, hasLength(2));
  });

  test(
    'concurrent metadata refresh fences the older bind completion',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final operationGate = Completer<void>();
      final installations = _FakePushInstallationPort()
        ..nextOperationGate = operationGate;
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );

      final firstBind = coordinator.bindActiveSession(_alice());
      await installations.firstOperationStarted.future;
      final refresh = coordinator.refreshActiveSession(
        _alice(logicalDeviceId: 'device-D'),
      );
      operationGate.complete();
      await Future.wait(<Future<void>>[firstBind, refresh]);

      expect(installations.calls, <String>[
        'upsert:device-a',
        'disable:installation-1',
        'upsert:device-a',
      ]);
      expect(
        installations.upserts.map((item) => item.logicalDeviceId),
        <String?>[null, 'device-D'],
      );
    },
  );

  test(
    'session replacement disables old installation before new bind',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final installations = _FakePushInstallationPort();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );
      await coordinator.bindActiveSession(_alice());

      client.registrationValue = _registration('device-b');
      await coordinator.bindActiveSession(_bob());

      expect(installations.calls, <String>[
        'upsert:device-a',
        'disable:installation-1',
        'upsert:device-b',
      ]);
    },
  );

  for (final replacement
      in <({String name, RemotePushInstallationSession session})>[
        (name: 'identity generation', session: _alice(generation: 2)),
        (
          name: 'tenant scope',
          session: _alice(scopeValue: '33333333-3333-4333-8333-333333333333'),
        ),
      ]) {
    test('${replacement.name} replacement disables the old binding', () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final installations = _FakePushInstallationPort();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );
      await coordinator.bindActiveSession(_alice());

      client.registrationValue = _registration('device-b');
      await coordinator.bindActiveSession(replacement.session);

      expect(installations.calls, <String>[
        'upsert:device-a',
        'disable:installation-1',
        'upsert:device-b',
      ]);
    });
  }

  test(
    'logout disable uses the last successful server installation id',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final installations = _FakePushInstallationPort();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );
      final session = _alice();
      await coordinator.bindActiveSession(session);
      client.registrationValue = _registration('device-b');
      await coordinator.refreshActiveSession(session);

      await coordinator.disableActiveInstallation(session);

      expect(installations.disables, <String>[
        'installation-1',
        'installation-2',
      ]);
    },
  );

  test(
    'stale bind completion cannot activate the invalidated session',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final operationGate = Completer<void>();
      final installations = _FakePushInstallationPort()
        ..nextOperationGate = operationGate;
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );
      final session = _alice();

      final staleBind = coordinator.bindActiveSession(session);
      await installations.firstOperationStarted.future;
      coordinator.deactivateLocally(session);
      operationGate.complete();
      await staleBind;

      await coordinator.bindActiveSession(session);

      expect(installations.calls, <String>[
        'upsert:device-a',
        'disable:installation-1',
        'upsert:device-a',
      ]);
    },
  );

  test('failed upsert does not record an installation for disable', () async {
    final client = _FakeRemotePushClient(_registration('device-a'));
    final installations = _FakePushInstallationPort()
      ..upsertError = StateError('upsert failed');
    final coordinator = RemotePushInstallationCoordinator(
      client: client,
      installations: installations,
    );

    await expectLater(
      coordinator.bindActiveSession(_alice()),
      throwsStateError,
    );
    await coordinator.disableCurrentInstallation();

    expect(installations.disables, isEmpty);
  });

  test('failed disable remains retryable after local deactivation', () async {
    final client = _FakeRemotePushClient(_registration('device-a'));
    final installations = _FakePushInstallationPort();
    final coordinator = RemotePushInstallationCoordinator(
      client: client,
      installations: installations,
    );
    final session = _alice();
    await coordinator.bindActiveSession(session);
    coordinator.deactivateLocally(session);
    installations.disableError = StateError('disable failed');

    await expectLater(
      coordinator.disableActiveInstallation(session),
      throwsStateError,
    );
    await coordinator.refreshActiveSession(session);
    installations.disableError = null;
    await coordinator.disableCurrentInstallation();

    expect(installations.upserts, hasLength(1));
    expect(installations.disables, <String>[
      'installation-1',
      'installation-1',
    ]);
  });

  test(
    'concurrent bind refresh and disable mutations are serialized',
    () async {
      final client = _FakeRemotePushClient(_registration('device-a'));
      final installations = _FakePushInstallationPort();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: installations,
      );
      await coordinator.bindActiveSession(_alice());

      client.registrationValue = _registration('device-b');
      final operationGate = Completer<void>();
      final operationStarted = Completer<void>();
      installations
        ..nextOperationGate = operationGate
        ..nextOperationStarted = operationStarted;
      final refresh = coordinator.refreshActiveSession(_alice());
      await operationStarted.future;
      final replacementBind = coordinator.bindActiveSession(_bob());
      final disable = coordinator.disableCurrentInstallation();
      var replacementCompleted = false;
      var disableCompleted = false;
      replacementBind.then((_) => replacementCompleted = true);
      disable.then((_) => disableCompleted = true);

      await Future<void>.delayed(Duration.zero);
      expect(replacementCompleted, isFalse);
      expect(disableCompleted, isFalse);
      operationGate.complete();

      await Future.wait(<Future<void>>[refresh, replacementBind, disable]);

      expect(installations.maximumConcurrentOperations, 1);
      expect(installations.calls, <String>[
        'upsert:device-a',
        'disable:installation-1',
      ]);
    },
  );
}

RemotePushInstallationSession _alice({
  String scopeValue = '11111111-1111-4111-8111-111111111111',
  int generation = 1,
  String? logicalDeviceId,
}) => RemotePushInstallationSession(
  storageScopeId: StorageScopeId.parse(scopeValue),
  ownerDid: 'did:wba:example.test:alice',
  generation: generation,
  logicalDeviceId: logicalDeviceId,
);

RemotePushInstallationSession _bob() => RemotePushInstallationSession(
  storageScopeId: StorageScopeId.parse('22222222-2222-4222-8222-222222222222'),
  ownerDid: 'did:wba:example.test:bob',
  generation: 2,
);

RemotePushRegistration _registration(String providerDeviceId) =>
    RemotePushRegistration(
      provider: 'aliyun_emas',
      providerDeviceId: providerDeviceId,
      platform: 'android',
      appId: 'app-key',
    );

final class _FakeRemotePushClient implements RemotePushClient {
  _FakeRemotePushClient(this.registrationValue);

  RemotePushRegistration? registrationValue;
  int initializeCount = 0;

  @override
  Stream<RemotePushEvent> get events => const Stream<RemotePushEvent>.empty();

  @override
  List<RemotePushEvent> get pendingEvents => const <RemotePushEvent>[];

  @override
  RemotePushRegistration? get registration => registrationValue;

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<RemotePushRegistration?> initialize() async {
    initializeCount += 1;
    return registrationValue;
  }
}

final class _FakePushInstallationPort implements PushInstallationPort {
  final List<String> calls = <String>[];
  final List<RemotePushRegistration> upserts = <RemotePushRegistration>[];
  final List<String> disables = <String>[];
  final Completer<void> firstOperationStarted = Completer<void>();

  Completer<void>? nextOperationGate;
  Completer<void>? nextOperationStarted;
  Object? upsertError;
  Object? disableError;
  int maximumConcurrentOperations = 0;

  int _concurrentOperations = 0;
  int _nextInstallationNumber = 1;

  @override
  Future<PushInstallation> upsert(RemotePushRegistration registration) async {
    calls.add('upsert:${registration.providerDeviceId}');
    upserts.add(registration);
    return _track(() {
      final error = upsertError;
      if (error != null) {
        throw error;
      }
      final installationNumber = _nextInstallationNumber++;
      return PushInstallation(
        installationId: 'installation-$installationNumber',
        provider: registration.provider,
        providerDeviceId: registration.providerDeviceId,
        platform: registration.platform,
        status: 'active',
        logicalDeviceId: registration.logicalDeviceId,
        appId: registration.appId,
      );
    });
  }

  @override
  Future<PushInstallation> disable(String installationId) async {
    calls.add('disable:$installationId');
    disables.add(installationId);
    return _track(() {
      final error = disableError;
      if (error != null) {
        throw error;
      }
      return PushInstallation(
        installationId: installationId,
        provider: 'aliyun_emas',
        providerDeviceId: 'disabled-device',
        platform: 'android',
        status: 'disabled',
      );
    });
  }

  Future<T> _track<T>(T Function() complete) async {
    _concurrentOperations += 1;
    if (_concurrentOperations > maximumConcurrentOperations) {
      maximumConcurrentOperations = _concurrentOperations;
    }
    if (!firstOperationStarted.isCompleted) {
      firstOperationStarted.complete();
    }
    final operationStarted = nextOperationStarted;
    nextOperationStarted = null;
    operationStarted?.complete();
    final gate = nextOperationGate;
    nextOperationGate = null;
    try {
      if (gate != null) {
        await gate.future;
      }
      return complete();
    } finally {
      _concurrentOperations -= 1;
    }
  }
}
