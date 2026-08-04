import 'dart:async';

import 'package:awiki_me/src/application/models/remote_push_sync_receipt.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/application/ports/remote_push_sync_port.dart';
import 'package:awiki_me/src/application/remote_push_message_reference.dart';
import 'package:awiki_me/src/application/remote_push_message_sync_coordinator.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:awiki_me/src/domain/services/remote_push_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'starts listening only after start and drains pending on activation',
    () async {
      final beforeStart = _event('before-start');
      final pending = _event('pending');
      final client = _FakeRemotePushClient(pending: <RemotePushEvent>[pending]);
      final sync = _FakeRemotePushSyncPort();
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });

      client.emit(beforeStart);
      await _flushEvents();
      expect(sync.callCount, 0);

      coordinator.start();
      await coordinator.activateSession(_alice);

      expect(sync.callCount, 1);
      expect(client.acknowledged, <List<String>>[
        <String>['pending'],
      ]);
    },
  );

  test('live and pending copies of one delivery ID join one batch', () async {
    final duplicate = _event('duplicate');
    final client = _FakeRemotePushClient(pending: <RemotePushEvent>[duplicate]);
    final sync = _FakeRemotePushSyncPort();
    final navigation = _FakeRemotePushNavigationPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });

    coordinator.start();
    client.emit(duplicate);
    await _flushEvents();
    await coordinator.activateSession(_alice);

    expect(sync.callCount, 1);
    expect(client.acknowledged, <List<String>>[
      <String>['duplicate'],
    ]);
  });

  for (final kind in <RemotePushEventKind>[
    RemotePushEventKind.messageReceived,
    RemotePushEventKind.notificationReceived,
    RemotePushEventKind.notificationReceivedInApp,
    RemotePushEventKind.notificationOpened,
  ]) {
    test('${kind.wireName} requests immediate remote Push sync', () async {
      final client = _FakeRemotePushClient();
      final sync = _FakeRemotePushSyncPort();
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      client.emit(_event('delivery', kind: kind));
      await sync.waitForCalls(1);
      await _flushEvents();

      expect(sync.callCount, 1);
      expect(client.acknowledged.single, <String>['delivery']);
      expect(sync.presentations.single, switch (kind) {
        RemotePushEventKind.notificationReceived ||
        RemotePushEventKind.notificationOpened =>
          RemotePushPresentationDisposition.providerPresented,
        _ => RemotePushPresentationDisposition.appPresentationRequired,
      });
    });
  }

  test('a provider-presented event suppresses a mixed batch', () async {
    final client = _FakeRemotePushClient(
      pending: <RemotePushEvent>[
        _event('in-app', kind: RemotePushEventKind.notificationReceivedInApp),
        _event('provider', kind: RemotePushEventKind.notificationReceived),
      ],
    );
    final sync = _FakeRemotePushSyncPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: _FakeRemotePushNavigationPort(),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();

    await coordinator.activateSession(_alice);

    expect(sync.presentations, <RemotePushPresentationDisposition>[
      RemotePushPresentationDisposition.providerPresented,
    ]);
  });

  test(
    'session activation installs and deactivation clears target fence',
    () async {
      final client = _FakeRemotePushClient();
      final coordinator = _coordinator(
        client: client,
        sync: _FakeRemotePushSyncPort(),
        navigation: _FakeRemotePushNavigationPort(),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();

      await coordinator.activateSession(_alice);
      expect(client.activeTargetReferences, <String?>[
        'target__O36e96xvUp2bpAWguuIrcdZ',
      ]);

      coordinator.deactivateSession(_alice);
      await _flushEvents();

      expect(client.activeTargetReferences.last, isNull);
    },
  );

  test(
    'ordinary Push for another local account stays pending until account switch',
    () async {
      final event = _event(
        'bob-foreground',
        kind: RemotePushEventKind.notificationReceivedInApp,
        type: 'direct_message',
        target: remotePushOpaqueTargetReference(_bob.ownerDid),
      );
      final client = _FakeRemotePushClient(pending: <RemotePushEvent>[event]);
      final sync = _FakeRemotePushSyncPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: _FakeRemotePushNavigationPort(),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();

      await coordinator.activateSession(_alice);

      expect(sync.callCount, 0);
      expect(client.acknowledged, isEmpty);
      expect(client.pendingEvents, <RemotePushEvent>[event]);

      await coordinator.activateSession(_bob);

      expect(sync.callCount, 1);
      expect(sync.presentations, <RemotePushPresentationDisposition>[
        RemotePushPresentationDisposition.appPresentationRequired,
      ]);
      expect(client.acknowledged, <List<String>>[
        <String>['bob-foreground'],
      ]);
      expect(client.pendingEvents, isEmpty);
    },
  );

  test('ordinary Push with matching target drains immediately', () async {
    final event = _event(
      'alice-foreground',
      kind: RemotePushEventKind.notificationReceivedInApp,
      type: 'group_message',
      target: remotePushOpaqueTargetReference(_alice.ownerDid),
    );
    final client = _FakeRemotePushClient(pending: <RemotePushEvent>[event]);
    final sync = _FakeRemotePushSyncPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: _FakeRemotePushNavigationPort(),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();

    await coordinator.activateSession(_alice);

    expect(sync.callCount, 1);
    expect(client.acknowledged, <List<String>>[
      <String>['alice-foreground'],
    ]);
  });

  test('registration change refreshes installation without syncing', () async {
    final client = _FakeRemotePushClient();
    final sync = _FakeRemotePushSyncPort();
    final navigation = _FakeRemotePushNavigationPort();
    final refreshed = <RemotePushSessionContext>[];
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
      refreshInstallation: (context) async => refreshed.add(context),
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();
    await coordinator.activateSession(_alice);

    client.emit(
      _event('registration', kind: RemotePushEventKind.registrationChanged),
    );
    await _flushEvents();

    expect(refreshed, <RemotePushSessionContext>[_alice]);
    expect(sync.callCount, 0);
    expect(client.acknowledged, isEmpty);
  });

  test('notification removal performs no work', () async {
    final client = _FakeRemotePushClient();
    final sync = _FakeRemotePushSyncPort();
    final navigation = _FakeRemotePushNavigationPort();
    var refreshCount = 0;
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
      refreshInstallation: (_) async => refreshCount += 1,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();
    await coordinator.activateSession(_alice);

    client.emit(
      _event('removed', kind: RemotePushEventKind.notificationRemoved),
    );
    await _flushEvents();

    expect(sync.callCount, 0);
    expect(refreshCount, 0);
    expect(client.acknowledged, isEmpty);
  });

  test('successful sync acknowledges exactly its captured batch', () async {
    final first = _event('first');
    final second = _event('second');
    final client = _FakeRemotePushClient(
      pending: <RemotePushEvent>[first, second],
    );
    final sync = _FakeRemotePushSyncPort();
    final navigation = _FakeRemotePushNavigationPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();

    await coordinator.activateSession(_alice);

    expect(sync.callCount, 1);
    expect(client.acknowledged, <List<String>>[
      <String>['first', 'second'],
    ]);
    expect(client.pendingEvents, isEmpty);
  });

  test(
    'non-success dispositions retain pending events without retrying',
    () async {
      for (final disposition in RemotePushSyncDisposition.values.where(
        (value) => value != RemotePushSyncDisposition.succeeded,
      )) {
        final pending = _event('pending-${disposition.name}');
        final client = _FakeRemotePushClient(
          pending: <RemotePushEvent>[pending],
        );
        final sync = _FakeRemotePushSyncPort(
          receipts: <RemotePushSyncReceipt>[
            RemotePushSyncReceipt(disposition: disposition),
          ],
        );
        final navigation = _FakeRemotePushNavigationPort();
        final coordinator = _coordinator(
          client: client,
          sync: sync,
          navigation: navigation,
        );
        coordinator.start();

        await coordinator.activateSession(_alice);
        await _flushEvents();

        expect(sync.callCount, 1, reason: disposition.name);
        expect(client.acknowledged, isEmpty, reason: disposition.name);
        expect(client.pendingEvents, <RemotePushEvent>[pending]);
        await coordinator.dispose();
        await client.dispose();
      }
    },
  );

  test('thrown sync retains pending event without a busy retry', () async {
    final pending = _event('thrown');
    final client = _FakeRemotePushClient(pending: <RemotePushEvent>[pending]);
    final sync = _FakeRemotePushSyncPort(error: StateError('sync failed'));
    final navigation = _FakeRemotePushNavigationPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();

    await coordinator.activateSession(_alice);
    await _flushEvents();

    expect(sync.callCount, 1);
    expect(client.acknowledged, isEmpty);
    expect(client.pendingEvents, <RemotePushEvent>[pending]);
  });

  test('acknowledgement failure leaves the native event pending', () async {
    final pending = _event('ack-failure');
    final client = _FakeRemotePushClient(
      pending: <RemotePushEvent>[pending],
      acknowledgeError: StateError('native ack failed'),
    );
    final sync = _FakeRemotePushSyncPort();
    final navigation = _FakeRemotePushNavigationPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();

    await coordinator.activateSession(_alice);
    await _flushEvents();

    expect(sync.callCount, 1);
    expect(client.pendingEvents, <RemotePushEvent>[pending]);
  });

  test(
    'resume is the real trigger that retries retained native events',
    () async {
      final pending = _event('resume-retry');
      final client = _FakeRemotePushClient(pending: <RemotePushEvent>[pending]);
      final sync = _FakeRemotePushSyncPort(
        receipts: const <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.retryableFailure,
          ),
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      await coordinator.resume();

      expect(sync.callCount, 2);
      expect(client.acknowledged, <List<String>>[
        <String>['resume-retry'],
      ]);
      expect(client.pendingEvents, isEmpty);
    },
  );

  test(
    'resume retries a live-only notification after retryable failure',
    () async {
      final client = _FakeRemotePushClient();
      final sync = _FakeRemotePushSyncPort(
        receipts: const <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.retryableFailure,
          ),
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      client.emit(
        _event(
          'live-notification',
          kind: RemotePushEventKind.notificationReceived,
        ),
      );
      await sync.waitForCalls(1);
      await _flushEvents();

      expect(sync.callCount, 1);
      expect(client.acknowledged, isEmpty);

      await coordinator.resume();

      expect(sync.callCount, 2);
      expect(client.acknowledged, <List<String>>[
        <String>['live-notification'],
      ]);
    },
  );

  test(
    'a new callback retries a live-only in-app event after a throw',
    () async {
      final client = _FakeRemotePushClient();
      final sync = _FakeRemotePushSyncPort(error: StateError('first throw'));
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      client.emit(
        _event(
          'live-in-app',
          kind: RemotePushEventKind.notificationReceivedInApp,
        ),
      );
      await sync.waitForCalls(1);
      await _flushEvents();

      expect(sync.callCount, 1);
      expect(client.acknowledged, isEmpty);

      sync.error = null;
      client.emit(_event('new-live-trigger'));
      await _flushEvents();

      expect(sync.callCount, 2);
      expect(client.acknowledged, <List<String>>[
        <String>['live-in-app', 'new-live-trigger'],
      ]);
    },
  );

  test(
    'resume retries a live-only event after native acknowledgement failure',
    () async {
      final client = _FakeRemotePushClient(
        acknowledgeError: StateError('first ack failed'),
      );
      final sync = _FakeRemotePushSyncPort(
        receipts: const <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
          ),
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      client.emit(
        _event(
          'live-ack-failure',
          kind: RemotePushEventKind.notificationReceived,
        ),
      );
      await sync.waitForCalls(1);
      await _flushEvents();

      expect(sync.callCount, 1);
      expect(client.acknowledged, isEmpty);

      client.acknowledgeError = null;
      await coordinator.resume();

      expect(sync.callCount, 2);
      expect(client.acknowledged, <List<String>>[
        <String>['live-ack-failure'],
      ]);
    },
  );

  test(
    'registration refresh is a real retry trigger for a retained batch',
    () async {
      final client = _FakeRemotePushClient();
      final sync = _FakeRemotePushSyncPort(
        receipts: const <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.retryableFailure,
          ),
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final calls = <String>[];
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
        refreshInstallation: (_) async => calls.add('refresh'),
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      client.emit(
        _event(
          'retained-live',
          kind: RemotePushEventKind.notificationReceivedInApp,
        ),
      );
      await sync.waitForCalls(1);
      await _flushEvents();
      expect(sync.callCount, 1);

      client.emit(
        _event(
          'registration-trigger',
          kind: RemotePushEventKind.registrationChanged,
        ),
      );
      await _flushEvents();

      expect(calls, <String>['refresh']);
      expect(sync.callCount, 2);
      expect(client.acknowledged, <List<String>>[
        <String>['retained-live'],
      ]);
    },
  );

  test(
    'a live event arriving during a successful batch drains once afterward',
    () async {
      final first = _event('first-concurrent');
      final firstGate = Completer<RemotePushSyncReceipt>();
      final client = _FakeRemotePushClient(pending: <RemotePushEvent>[first]);
      final sync = _SequencedRemotePushSyncPort(<Future<RemotePushSyncReceipt>>[
        firstGate.future,
        Future<RemotePushSyncReceipt>.value(
          const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
          ),
        ),
      ]);
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = RemotePushMessageSyncCoordinator(
        client: client,
        sync: sync,
        navigation: navigation,
        refreshInstallation: (_) async {},
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      final activation = coordinator.activateSession(_alice);
      await sync.firstCallStarted.future;

      client.emit(_event('second-concurrent'));
      await _flushEvents();
      firstGate.complete(
        const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.succeeded,
        ),
      );
      await activation;
      await _flushEvents();

      expect(sync.callCount, 2);
      expect(client.acknowledged, <List<String>>[
        <String>['first-concurrent'],
        <String>['second-concurrent'],
      ]);
    },
  );

  test('session deactivation fences a stale sync completion', () async {
    final syncGate = Completer<RemotePushSyncReceipt>();
    final client = _FakeRemotePushClient();
    final sync = _FakeRemotePushSyncPort(gate: syncGate);
    final navigation = _FakeRemotePushNavigationPort();
    final coordinator = _coordinator(
      client: client,
      sync: sync,
      navigation: navigation,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });
    coordinator.start();
    await coordinator.activateSession(_alice);

    client.emit(
      _event(
        'opened',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'message_xoHiCNuDN3nIPLC3HI_ay7zP',
      ),
    );
    await sync.waitForCalls(1);
    coordinator.deactivateSession(_alice);
    syncGate.complete(
      RemotePushSyncReceipt(
        disposition: RemotePushSyncDisposition.succeeded,
        committedIncomingMessages: <CommittedIncomingMessage>[
          _committed(logicalId: 'message-sensitive-id'),
        ],
      ),
    );
    await _flushEvents();

    expect(client.acknowledged, isEmpty);
    expect(navigation.calls, isEmpty);
  });

  test(
    'successful ack clears the captured batch across a session replacement',
    () async {
      final ackGate = Completer<void>();
      final client = _FakeRemotePushClient(acknowledgeGate: ackGate);
      final committed = _committed(logicalId: 'logical-fixed');
      final sync = _FakeRemotePushSyncPort(
        receipts: <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[committed],
          ),
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[committed],
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        if (!ackGate.isCompleted) ackGate.complete();
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      client.emit(
        _event(
          'opened-ack-race',
          kind: RemotePushEventKind.notificationOpened,
          mid: 'message_9vzrcTxg4y85mTjGIeHXdQxQ',
          exp: 1800000000,
        ),
      );
      await client.acknowledgementStarted.future;

      final replacement = coordinator.activateSession(_bob);
      ackGate.complete();
      await replacement;
      await _flushEvents();

      expect(sync.callCount, 1);
      expect(client.acknowledged, <List<String>>[
        <String>['opened-ack-race'],
      ]);
      expect(navigation.calls, <String>[
        'list:${_alice.storageScopeId.value}',
        'open:${_alice.storageScopeId.value}:conversation-canonical',
      ]);
    },
  );

  test(
    'successful ack clears a same-delivery callback received while awaiting',
    () async {
      final ackGate = Completer<void>();
      final client = _FakeRemotePushClient(acknowledgeGate: ackGate);
      final committed = _committed(logicalId: 'logical-fixed');
      final sync = _FakeRemotePushSyncPort(
        receipts: <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[committed],
          ),
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[committed],
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        if (!ackGate.isCompleted) ackGate.complete();
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();
      await coordinator.activateSession(_alice);

      final first = _event(
        'same-delivery',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'message_9vzrcTxg4y85mTjGIeHXdQxQ',
        exp: 1800000000,
      );
      client.emit(first);
      await client.acknowledgementStarted.future;

      client.emit(
        RemotePushEvent(
          deliveryId: first.deliveryId,
          kind: first.kind,
          payload: Map<String, Object?>.of(first.payload),
          receivedAt: first.receivedAt.add(const Duration(milliseconds: 1)),
        ),
      );
      await _flushEvents();
      ackGate.complete();
      await _flushEvents();
      await coordinator.resume();

      expect(sync.callCount, 1);
      expect(client.acknowledged, <List<String>>[
        <String>['same-delivery'],
      ]);
      expect(navigation.calls, <String>[
        'list:${_alice.storageScopeId.value}',
        'open:${_alice.storageScopeId.value}:conversation-canonical',
      ]);
    },
  );

  const matchCases = <({String label, String mid})>[
    (label: 'logical', mid: 'message_9vzrcTxg4y85mTjGIeHXdQxQ'),
    (label: 'remote', mid: 'message_CQwklv8EJcnkivoOl17IzlMv'),
    (label: 'local', mid: 'message_FpVJsIMCIKCBks8mMwpiMu2L'),
  ];
  for (final matchCase in matchCases) {
    test(
      'opened ${matchCase.label} receipt ID selects canonical conversation',
      () async {
        final opened = _event(
          'opened-${matchCase.label}',
          kind: RemotePushEventKind.notificationOpened,
          mid: matchCase.mid,
          exp: 1800000000,
        );
        final client = _FakeRemotePushClient(
          pending: <RemotePushEvent>[opened],
        );
        final sync = _FakeRemotePushSyncPort(
          receipts: <RemotePushSyncReceipt>[
            RemotePushSyncReceipt(
              disposition: RemotePushSyncDisposition.succeeded,
              committedIncomingMessages: <CommittedIncomingMessage>[
                _committed(
                  logicalId: 'logical-fixed',
                  remoteId: 'remote-fixed',
                  localId: 'local-fixed',
                ),
              ],
            ),
          ],
        );
        final navigation = _FakeRemotePushNavigationPort();
        final coordinator = _coordinator(
          client: client,
          sync: sync,
          navigation: navigation,
        );
        coordinator.start();

        await coordinator.activateSession(_alice);

        expect(navigation.calls, <String>[
          'list:${_alice.storageScopeId.value}',
          'open:${_alice.storageScopeId.value}:conversation-canonical',
        ]);
        expect(client.acknowledged, <List<String>>[
          <String>['opened-${matchCase.label}'],
        ]);
        await coordinator.dispose();
        await client.dispose();
      },
    );
  }

  test('unsafe opened references fall back to the conversation list', () async {
    final unsafeEvents = <RemotePushEvent>[
      _event('absent', kind: RemotePushEventKind.notificationOpened),
      _event(
        'missing-expiry',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'message_9vzrcTxg4y85mTjGIeHXdQxQ',
      ),
      _event(
        'expired',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'message_9vzrcTxg4y85mTjGIeHXdQxQ',
        exp: 1700000000,
      ),
      _event(
        'malformed',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'logical-fixed',
        exp: 1800000000,
      ),
      _event(
        'malformed-expiry',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'message_9vzrcTxg4y85mTjGIeHXdQxQ',
        exp: 9999999999999,
      ),
      _event(
        'unmatched',
        kind: RemotePushEventKind.notificationOpened,
        mid: 'message_AAAAAAAAAAAAAAAAAAAAAAAA',
        exp: 1800000000,
      ),
    ];

    for (final event in unsafeEvents) {
      final client = _FakeRemotePushClient(pending: <RemotePushEvent>[event]);
      final sync = _FakeRemotePushSyncPort(
        receipts: <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[
              _committed(logicalId: 'logical-fixed'),
            ],
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      coordinator.start();

      await coordinator.activateSession(_alice);

      expect(navigation.calls, <String>[
        'list:${_alice.storageScopeId.value}',
      ], reason: event.deliveryId);
      await coordinator.dispose();
      await client.dispose();
    }
  });

  test(
    'Push payload metadata never becomes message or navigation truth',
    () async {
      final event = RemotePushEvent(
        deliveryId: 'dirty-payload',
        kind: RemotePushEventKind.notificationOpened,
        receivedAt: DateTime.utc(2026, 7, 30),
        payload: <String, Object?>{
          'mid': 'message_9vzrcTxg4y85mTjGIeHXdQxQ',
          'conversationId': 'attacker-conversation',
          'groupId': 'attacker-group',
          'system': true,
          'structured': <String, Object?>{'route': 'attacker-route'},
          'extraMap': <String, Object?>{
            'mid': 'message_AAAAAAAAAAAAAAAAAAAAAAAA',
            'exp': 1800000000,
            'conversationId': 'nested-attacker-conversation',
          },
        },
      );
      final client = _FakeRemotePushClient(pending: <RemotePushEvent>[event]);
      final sync = _FakeRemotePushSyncPort(
        receipts: <RemotePushSyncReceipt>[
          RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[
              _committed(logicalId: 'message-sensitive-id'),
            ],
          ),
        ],
      );
      final navigation = _FakeRemotePushNavigationPort();
      final coordinator = _coordinator(
        client: client,
        sync: sync,
        navigation: navigation,
      );
      addTearDown(() async {
        await coordinator.dispose();
        await client.dispose();
      });
      coordinator.start();

      await coordinator.activateSession(_alice);

      expect(navigation.calls, <String>['list:${_alice.storageScopeId.value}']);
    },
  );
}

RemotePushMessageSyncCoordinator _coordinator({
  required _FakeRemotePushClient client,
  required _FakeRemotePushSyncPort sync,
  required _FakeRemotePushNavigationPort navigation,
  Future<void> Function(RemotePushSessionContext context)? refreshInstallation,
}) {
  return RemotePushMessageSyncCoordinator(
    client: client,
    sync: sync,
    navigation: navigation,
    refreshInstallation: refreshInstallation ?? (_) async {},
    now: () => DateTime.utc(2026, 7, 30),
  );
}

final _alice = RemotePushSessionContext(
  storageScopeId: StorageScopeId.parse('11111111-1111-4111-8111-111111111111'),
  ownerDid: 'did:wba:example.test:alice',
  generation: 1,
);

final _bob = RemotePushSessionContext(
  storageScopeId: StorageScopeId.parse('22222222-2222-4222-8222-222222222222'),
  ownerDid: 'did:wba:example.test:bob',
  generation: 2,
);

RemotePushEvent _event(
  String deliveryId, {
  RemotePushEventKind kind = RemotePushEventKind.messageReceived,
  String? mid,
  int? exp,
  String? type,
  String? target,
}) {
  final extraMap = <String, Object?>{
    if (mid != null) 'mid': mid,
    if (exp != null) 'exp': exp,
    if (type != null) 'ty': type,
    if (target != null) 'ts': target,
  };
  return RemotePushEvent(
    deliveryId: deliveryId,
    kind: kind,
    payload: <String, Object?>{if (extraMap.isNotEmpty) 'extraMap': extraMap},
    receivedAt: DateTime.utc(2026, 7, 30),
  );
}

CommittedIncomingMessage _committed({
  required String logicalId,
  String localId = 'local-fixed',
  String remoteId = 'remote-fixed',
}) {
  return CommittedIncomingMessage(
    eventId: 'event-$logicalId',
    logicalMessageId: logicalId,
    message: ChatMessage(
      localId: localId,
      remoteId: remoteId,
      conversationId: 'conversation-canonical',
      threadId: 'thread-canonical',
      senderDid: 'did:wba:example.test:peer',
      receiverDid: 'did:wba:example.test:alice',
      content: 'Core committed message',
      createdAt: DateTime.utc(2026, 7, 30),
      isMine: false,
      sendState: MessageSendState.sent,
    ),
  );
}

Future<void> _flushEvents() async {
  for (var index = 0; index < 6; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _FakeRemotePushClient
    implements RemotePushClient, RemotePushPresentationTargetClient {
  _FakeRemotePushClient({
    List<RemotePushEvent> pending = const <RemotePushEvent>[],
    this.acknowledgeError,
    this.acknowledgeGate,
  }) : _pending = <String, RemotePushEvent>{
         for (final event in pending) event.deliveryId: event,
       };

  final StreamController<RemotePushEvent> _events =
      StreamController<RemotePushEvent>.broadcast();
  final Map<String, RemotePushEvent> _pending;
  Object? acknowledgeError;
  final Completer<void>? acknowledgeGate;
  final Completer<void> acknowledgementStarted = Completer<void>();
  final List<List<String>> acknowledged = <List<String>>[];
  final List<String?> activeTargetReferences = <String?>[];

  void emit(RemotePushEvent event) => _events.add(event);

  @override
  Stream<RemotePushEvent> get events => _events.stream;

  @override
  RemotePushRegistration? get registration => null;

  @override
  List<RemotePushEvent> get pendingEvents =>
      List<RemotePushEvent>.unmodifiable(_pending.values);

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {
    if (!acknowledgementStarted.isCompleted) {
      acknowledgementStarted.complete();
    }
    final gate = acknowledgeGate;
    if (gate != null) await gate.future;
    if (acknowledgeError case final error?) {
      throw error;
    }
    final ids = deliveryIds.toList(growable: false);
    acknowledged.add(ids);
    for (final deliveryId in ids) {
      _pending.remove(deliveryId);
    }
  }

  @override
  Future<RemotePushRegistration?> initialize() async => null;

  @override
  Future<void> setActiveNotificationTargetReference(
    String? targetReference,
  ) async {
    activeTargetReferences.add(targetReference);
  }

  @override
  Future<void> dispose() => _events.close();
}

final class _FakeRemotePushSyncPort implements RemotePushSyncPort {
  _FakeRemotePushSyncPort({
    List<RemotePushSyncReceipt> receipts = const <RemotePushSyncReceipt>[
      RemotePushSyncReceipt(disposition: RemotePushSyncDisposition.succeeded),
    ],
    this.error,
    this.gate,
  }) : _receipts = List<RemotePushSyncReceipt>.of(receipts);

  final List<RemotePushSyncReceipt> _receipts;
  Object? error;
  final Completer<RemotePushSyncReceipt>? gate;
  final List<Completer<void>> _callWaiters = <Completer<void>>[];
  final List<RemotePushPresentationDisposition> presentations =
      <RemotePushPresentationDisposition>[];
  int callCount = 0;

  @override
  Future<RemotePushSyncReceipt> requestRemotePushSync({
    RemotePushPresentationDisposition presentation =
        RemotePushPresentationDisposition.providerPresented,
  }) async {
    callCount += 1;
    presentations.add(presentation);
    for (final waiter in _callWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    if (error case final value?) throw value;
    final pendingGate = gate;
    if (pendingGate != null) return pendingGate.future;
    if (_receipts.isEmpty) {
      throw StateError('No remote Push receipt configured');
    }
    return _receipts.removeAt(0);
  }

  Future<void> waitForCalls(int count) {
    if (callCount >= count) return Future<void>.value();
    final waiter = Completer<void>();
    _callWaiters.add(waiter);
    return waiter.future;
  }
}

final class _SequencedRemotePushSyncPort implements RemotePushSyncPort {
  _SequencedRemotePushSyncPort(this._results);

  final List<Future<RemotePushSyncReceipt>> _results;
  final Completer<void> firstCallStarted = Completer<void>();
  int callCount = 0;

  @override
  Future<RemotePushSyncReceipt> requestRemotePushSync({
    RemotePushPresentationDisposition presentation =
        RemotePushPresentationDisposition.providerPresented,
  }) {
    callCount += 1;
    if (!firstCallStarted.isCompleted) firstCallStarted.complete();
    if (_results.isEmpty) {
      throw StateError('No sequenced remote Push receipt configured');
    }
    return _results.removeAt(0);
  }
}

final class _FakeRemotePushNavigationPort implements RemotePushNavigationPort {
  final List<String> calls = <String>[];

  @override
  Future<void> showConversationList(RemotePushSessionContext context) async {
    calls.add('list:${context.storageScopeId.value}');
  }

  @override
  Future<void> openConversation(
    RemotePushSessionContext context,
    String conversationId,
  ) async {
    calls.add('open:${context.storageScopeId.value}:$conversationId');
  }
}
