import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_presentation_service.dart';
import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/message_sync_diagnostics.dart';
import 'package:awiki_me/src/application/models/remote_push_sync_receipt.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/application/ports/remote_push_sync_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/data/services/method_channel_app_presentation_service.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_terminal_notification_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'test_support.dart';
import 'devices/device_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remote Push without an authenticated session is ignored', () async {
    final sync = FakeMessageSyncService();
    final container = _container(FakeAwikiGateway(), sync);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).clear();

    final receipt = await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestRemotePushSync();

    expect(receipt.disposition, RemotePushSyncDisposition.ignored);
    expect(receipt.canAcknowledge, isFalse);
    expect(sync.syncReasons, isEmpty);
  });

  test(
    'remote Push succeeds only after the post-commit projection refresh',
    () async {
      final message = _incomingMessage(logicalId: 'logical-projection');
      final committed = CommittedIncomingMessage(
        eventId: 'event-projection',
        logicalMessageId: 'logical-projection',
        message: message,
      );
      final gateway = _PostCommitRefreshBlockingGateway(_conversation());
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[committed],
        ),
      );
      final container = _container(gateway, sync, syncV2ReadEnabled: true);
      addTearDown(() {
        gateway.release();
        container.dispose();
      });
      final RemotePushSyncPort coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      var completed = false;
      final pending = coordinator.requestRemotePushSync().whenComplete(
        () => completed = true,
      );
      await gateway.postCommitRefreshStarted.future;

      expect(completed, isFalse);
      expect(sync.syncReasons, ['remote_push']);

      gateway.release();
      final receipt = await pending;

      expect(receipt.disposition, RemotePushSyncDisposition.succeeded);
      expect(receipt.canAcknowledge, isTrue);
      expect(receipt.committedIncomingMessages, [committed]);
    },
  );

  test('remote Push maps every terminal Core outcome exactly', () async {
    const cases = <MessageSyncStatus, RemotePushSyncDisposition>{
      MessageSyncStatus.idle: RemotePushSyncDisposition.succeeded,
      MessageSyncStatus.changed: RemotePushSyncDisposition.succeeded,
      MessageSyncStatus.retryableFailure:
          RemotePushSyncDisposition.retryableFailure,
      MessageSyncStatus.recoveryRequired:
          RemotePushSyncDisposition.recoveryRequired,
      MessageSyncStatus.authRevoked: RemotePushSyncDisposition.authRevoked,
    };

    for (final entry in cases.entries) {
      final container = _container(
        FakeAwikiGateway(),
        FakeMessageSyncService(
          deltaResult: MessageSyncOutcome(
            status: entry.key,
            eventsApplied: 0,
            pagesFetched: 1,
          ),
        ),
      );
      final receipt = await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestRemotePushSync();

      expect(
        receipt.disposition,
        entry.value,
        reason: 'Core ${entry.key.name}',
      );
      expect(
        receipt.canAcknowledge,
        entry.value == RemotePushSyncDisposition.succeeded,
      );
      container.dispose();
    }
  });

  test('remote Push maps a thrown sync error to retryable failure', () async {
    final container = _container(
      FakeAwikiGateway(),
      _FailingMessageSyncService(),
    );
    addTearDown(container.dispose);

    final receipt = await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestRemotePushSync();

    expect(receipt.disposition, RemotePushSyncDisposition.retryableFailure);
    expect(receipt.canAcknowledge, isFalse);
  });

  test('remote Push completion after an identity change is stale', () async {
    final completion = Completer<void>();
    final sync = FakeMessageSyncService()..syncNowCompleter = completion;
    final container = _container(FakeAwikiGateway(), sync);
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final pending = coordinator.requestRemotePushSync();
    await pumpEventQueue();
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:test:next',
            credentialName: 'next',
            displayName: 'Next',
          ),
        );
    completion.complete();

    final receipt = await pending;

    expect(receipt.disposition, RemotePushSyncDisposition.staleSession);
    expect(receipt.canAcknowledge, isFalse);
  });

  test(
    'remote Push joins an active normal run and suppresses its presentation',
    () async {
      final completion = Completer<void>();
      final notifications = FakeNotificationFacade();
      final committed = _committedIncoming(
        eventId: 'event-active',
        logicalId: 'logical-active',
      );
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[committed],
        ),
      )..syncNowCompleter = completion;
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      final normal = coordinator.requestSync('websocket_hint', immediate: true);
      await pumpEventQueue();
      final remote = coordinator.requestRemotePushSync();
      completion.complete();

      final receipt = await remote;
      await normal;
      await pumpEventQueue();

      expect(receipt.disposition, RemotePushSyncDisposition.succeeded);
      expect(sync.syncReasons, ['websocket_hint']);
      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
    },
  );

  test(
    'queued suppression is sticky when a later normal request coalesces',
    () async {
      final first = _committedIncoming(
        eventId: 'event-queue-first',
        logicalId: 'logical-queue-first',
      );
      final second = _committedIncoming(
        eventId: 'event-queue-second',
        logicalId: 'logical-queue-second',
      );
      final sync = _SequencedMessageSyncService(<MessageSyncOutcome>[
        MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[first],
        ),
        MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[second],
        ),
      ]);
      final joinStarted = Completer<void>();
      final joinGate = Completer<List<DeviceJoinRequestNotice>>();
      final devices = _deviceCoreWithBlockingJoinInbox(
        started: joinStarted,
        gate: joinGate,
      );
      final notifications = FakeNotificationFacade();
      final container = _container(
        FakeAwikiGateway(),
        sync,
        devices: devices,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(() {
        if (!joinGate.isCompleted) {
          joinGate.complete(const <DeviceJoinRequestNotice>[]);
        }
        container.dispose();
      });
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      final normal = coordinator.requestSync('startup', immediate: true);
      await joinStarted.future;
      final remote = coordinator.requestRemotePushSync();
      unawaited(coordinator.requestSync('websocket_hint', immediate: true));
      joinGate.complete(const <DeviceJoinRequestNotice>[]);

      await normal;
      final receipt = await remote;
      await pumpEventQueue();

      expect(receipt.disposition, RemotePushSyncDisposition.succeeded);
      expect(sync.syncReasons, ['startup', 'websocket_hint']);
      expect(notifications.inAppCalls, 1);
      expect(notifications.systemCalls, 0);
    },
  );

  test('a follow-up queued behind remote Push inherits suppression', () async {
    final firstGate = Completer<void>();
    final firstStarted = Completer<void>();
    final secondCompleted = Completer<void>();
    final sync = _FirstGatedSequencedMessageSyncService(
      outcomes: <MessageSyncOutcome>[
        const MessageSyncOutcome(
          status: MessageSyncStatus.idle,
          eventsApplied: 0,
          pagesFetched: 1,
        ),
        MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[
            _committedIncoming(
              eventId: 'event-inherited',
              logicalId: 'logical-inherited',
            ),
          ],
        ),
      ],
      firstGate: firstGate,
      firstStarted: firstStarted,
      secondCompleted: secondCompleted,
    );
    final notifications = FakeNotificationFacade();
    final container = _container(
      FakeAwikiGateway(),
      sync,
      notifications: notifications,
      syncV2ReadEnabled: true,
    );
    addTearDown(() {
      if (!firstGate.isCompleted) {
        firstGate.complete();
      }
      container.dispose();
    });
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final remote = coordinator.requestRemotePushSync();
    await firstStarted.future;
    unawaited(coordinator.requestSync('websocket_hint', immediate: true));
    firstGate.complete();

    await remote;
    await secondCompleted.future;
    await pumpEventQueue();

    expect(sync.syncReasons, ['remote_push', 'websocket_hint']);
    expect(notifications.inAppCalls, 0);
    expect(notifications.systemCalls, 0);
  });

  test(
    'a pending normal timer inherits suppression from an active remote Push',
    () async {
      final remoteGate = Completer<void>();
      final remoteStarted = Completer<void>();
      final followUpCompleted = Completer<void>();
      final sync = _PendingTimerRaceMessageSyncService(
        outcomes: <MessageSyncOutcome>[
          const MessageSyncOutcome(
            status: MessageSyncStatus.idle,
            eventsApplied: 0,
            pagesFetched: 1,
          ),
          const MessageSyncOutcome(
            status: MessageSyncStatus.idle,
            eventsApplied: 0,
            pagesFetched: 1,
          ),
          MessageSyncOutcome(
            status: MessageSyncStatus.changed,
            eventsApplied: 2,
            pagesFetched: 1,
            committedIncomingMessages: <CommittedIncomingMessage>[
              _committedIncoming(
                eventId: 'event-timer-ordinary',
                logicalId: 'logical-timer-ordinary',
              ),
              _committedIncoming(
                eventId: 'event-timer-runtime',
                logicalId: 'logical-timer-runtime',
                senderDid: 'did:agent:runtime',
              ),
            ],
          ),
        ],
        remoteGate: remoteGate,
        remoteStarted: remoteStarted,
        followUpCompleted: followUpCompleted,
      );
      final notifications = FakeNotificationFacade();
      final container = _container(
        FakeAwikiGateway(),
        sync,
        minInterval: const Duration(milliseconds: 100),
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(() {
        if (!remoteGate.isCompleted) {
          remoteGate.complete();
        }
        container.dispose();
      });
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'codex',
              'status': 'ready',
            },
          ],
        },
      );
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      await coordinator.requestSync('seed', immediate: true);
      final delayed = coordinator.requestSync('delayed_normal');
      final remote = coordinator.requestRemotePushSync();
      await remoteStarted.future;
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(sync.syncReasons, ['seed', 'remote_push']);

      remoteGate.complete();
      await remote;
      await delayed;
      await followUpCompleted.future;
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(sync.syncReasons, ['seed', 'remote_push', 'delayed_normal']);
      expect(sync.maxActiveCalls, 1);
      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
    },
  );

  test(
    'suppressed commits retain event logical and message identity ledgers',
    () async {
      final first = _committedIncoming(
        eventId: 'event-ledger',
        logicalId: 'logical-ledger',
        localId: 'local-ledger',
        remoteId: 'remote-ledger',
      );
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[first],
        ),
      );
      final notifications = FakeNotificationFacade();
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await coordinator.requestRemotePushSync();
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          _committedIncoming(
            eventId: 'event-ledger',
            logicalId: 'logical-event-duplicate',
          ),
        ],
      );
      await coordinator.requestSync('websocket_hint', immediate: true);
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          _committedIncoming(
            eventId: 'event-logical-duplicate',
            logicalId: 'logical-ledger',
          ),
        ],
      );
      await coordinator.requestSync('websocket_hint', immediate: true);
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          _committedIncoming(
            eventId: 'event-message-duplicate',
            logicalId: 'logical-message-duplicate',
            localId: 'local-ledger',
            remoteId: 'remote-ledger',
          ),
        ],
      );
      await coordinator.requestSync('websocket_hint', immediate: true);

      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
    },
  );

  test('remote Push suppresses delayed Runtime Agent presentation', () async {
    final notifications = FakeNotificationFacade();
    final committed = _committedIncoming(
      eventId: 'event-runtime-suppressed',
      logicalId: 'logical-runtime-suppressed',
      senderDid: 'did:agent:runtime',
    );
    final sync = FakeMessageSyncService(
      deltaResult: MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[committed],
      ),
    );
    final container = _container(
      FakeAwikiGateway(),
      sync,
      notifications: notifications,
      syncV2ReadEnabled: true,
    );
    addTearDown(container.dispose);
    container.read(agentsProvider.notifier).applyControlPayload(
      const <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'snapshot',
        'daemon_agent_did': 'did:agent:daemon',
        'daemon': <String, Object?>{
          'agent_did': 'did:agent:daemon',
          'status': 'ready',
        },
        'runtimes': <Object?>[
          <String, Object?>{
            'agent_did': 'did:agent:runtime',
            'daemon_agent_did': 'did:agent:daemon',
            'runtime': 'codex',
            'status': 'ready',
          },
        ],
      },
    );

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestRemotePushSync();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(notifications.inAppCalls, 0);
    expect(notifications.systemCalls, 0);
  });

  test('automatic retry inherits remote Push suppression', () async {
    final notifications = FakeNotificationFacade();
    final sync = FakeMessageSyncService(
      deltaResult: MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          _committedIncoming(
            eventId: 'event-retry',
            logicalId: 'logical-retry',
          ),
        ],
      ),
    )..nextDeltaError = StateError('transient_remote_push_failure');
    final container = _container(
      FakeAwikiGateway(),
      sync,
      notifications: notifications,
      syncV2ReadEnabled: true,
      failureSurfaceDelay: const Duration(seconds: 30),
    );
    addTearDown(container.dispose);

    final receipt = await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestRemotePushSync();
    await pumpEventQueue();

    expect(receipt.disposition, RemotePushSyncDisposition.retryableFailure);
    expect(sync.syncReasons, ['remote_push', 'automatic_retry']);
    expect(notifications.inAppCalls, 0);
    expect(notifications.systemCalls, 0);
  });

  test('single-flight coalesces concurrent sync requests', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final firstSync = Completer<void>();
    final sync = FakeMessageSyncService()..syncNowCompleter = firstSync;
    final container = _container(gateway, sync);
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final first = coordinator.requestSync('startup', immediate: true);
    await pumpEventQueue();
    final second = coordinator.requestSync('app_resumed', immediate: true);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup']);
    expect(sync.activeSyncNowCalls, 1);
    expect(sync.maxActiveSyncNowCalls, 1);

    firstSync.complete();
    await Future.wait(<Future<void>>[first, second]);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup', 'app_resumed']);
    expect(sync.maxActiveSyncNowCalls, 1);
    expect(
      container.read(conversationListProvider).conversations,
      hasLength(1),
    );
  });

  test(
    'first sync prepares one bounded conversation seed without prewarming',
    () async {
      final conversation = _conversation();
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[conversation];
      final sync = FakeMessageSyncService();
      final container = _container(gateway, sync, syncV2ReadEnabled: true);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);

      expect(gateway.listConversationsCalls, 2);
      expect(sync.syncReasons, ['startup']);
      expect(gateway.fetchLocalDmHistoryCalls, 0);
      expect(gateway.fetchLocalGroupHistoryCalls, 0);
      expect(gateway.fetchDmHistoryCalls, 0);
      expect(container.read(conversationListProvider).conversations, [
        conversation,
      ]);
    },
  );

  test('subsequent sync does not reseed or prewarm local histories', () async {
    final conversation = _conversation();
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('startup', immediate: true);
    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('realtime_hint', immediate: true);
    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('websocket_reconnect', immediate: true);

    expect(gateway.listConversationsCalls, 4);
    expect(sync.syncReasons, [
      'startup',
      'realtime_hint',
      'websocket_reconnect',
    ]);
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchLocalGroupHistoryCalls, 0);
  });

  test(
    'sync commit forces a fresh recents read past a blocked pre-sync refresh',
    () async {
      final stale = _conversation();
      final committed = stale.copyWith(
        lastMessagePreview: 'new unread after identity switch',
        lastMessageAt: stale.lastMessageAt.add(const Duration(seconds: 1)),
        unreadCount: 1,
      );
      final gateway = _PostCommitConversationGateway(stale);
      final sync = _PublishingMessageSyncService(
        gateway: gateway,
        committed: committed,
      );
      final conversations = _BoundReadyConversationService(
        gateway,
        ownerIdentityId: 'owner-a',
      );
      final container = _container(
        gateway,
        sync,
        session: _boundSession(deviceAuthGeneration: '1'),
        conversationService: conversations,
      );
      addTearDown(container.dispose);
      addTearDown(gateway.releaseFirstIfPending);

      final preSyncRefresh = container
          .read(conversationListProvider.notifier)
          .refreshFastLocal();
      await gateway.firstRefreshStarted.future;

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('identity_switch_startup', immediate: true)
          .timeout(const Duration(seconds: 1));

      expect(gateway.listConversationsCalls, 2);
      expect(
        container.read(conversationListProvider).conversations.single,
        committed,
      );

      gateway.releaseFirst();
      await preSyncRefresh.timeout(const Duration(seconds: 1));
      await pumpEventQueue();

      expect(
        container.read(conversationListProvider).conversations.single,
        committed,
      );
      expect(container.read(messageSyncCoordinatorProvider).lastError, isNull);
    },
  );

  test('replacing a delayed sync completes all coalesced waiters', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final sync = FakeMessageSyncService();
    final container = _container(
      gateway,
      sync,
      minInterval: const Duration(milliseconds: 50),
    );
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    await coordinator.requestSync('startup', immediate: true);
    final firstDelayed = coordinator.requestSync('app_resumed');
    final secondDelayed = coordinator.requestSync('realtime_gap');

    await Future.wait(<Future<void>>[
      firstDelayed,
      secondDelayed,
    ]).timeout(const Duration(seconds: 1));

    expect(sync.syncReasons, ['startup', 'realtime_gap']);
  });

  test('sync completion after dispose is ignored', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final sync = _BlockingMessageSyncService();
    final container = _container(gateway, sync);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final request = coordinator.requestSync('startup', immediate: true);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup']);

    container.dispose();
    sync.complete();

    await request.timeout(const Duration(seconds: 1));
    await pumpEventQueue();
  });

  test(
    'an active identity sync cannot satisfy or coalesce the next identity sync',
    () async {
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[_conversation()];
      final sync = _QueuedBlockingMessageSyncService();
      final container = _container(gateway, sync);
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      final aliceSync = coordinator.requestSync(
        'alice_startup',
        immediate: true,
      );
      await pumpEventQueue();
      expect(sync.syncReasons, ['alice_startup']);

      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:bob',
              credentialName: 'bob',
              displayName: 'Bob',
            ),
          );
      var bobCompleted = false;
      final bobSync = coordinator
          .requestSync('bob_startup', immediate: true)
          .whenComplete(() => bobCompleted = true);
      await pumpEventQueue();

      expect(sync.syncReasons, ['alice_startup']);
      expect(bobCompleted, isFalse);
      expect(container.read(messageSyncCoordinatorProvider).isSyncing, isFalse);

      sync.completeNext();
      await aliceSync;
      await pumpEventQueue();

      expect(sync.syncReasons, ['alice_startup', 'bob_startup']);
      expect(bobCompleted, isFalse);

      sync.completeNext();
      await bobSync;
      await pumpEventQueue();

      expect(gateway.listConversationsCalls, 3);
      expect(
        container.read(messageSyncCoordinatorProvider).lastReason,
        'bob_startup',
      );
      expect(container.read(messageSyncCoordinatorProvider).lastError, isNull);
    },
  );

  test('rapid identity replacement drops a delayed stale request', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final sync = FakeMessageSyncService();
    final container = _container(
      gateway,
      sync,
      minInterval: const Duration(seconds: 1),
    );
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    await coordinator.requestSync('alice_startup', immediate: true);
    final staleDelayed = coordinator.requestSync('alice_resume');
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:test:bob',
            credentialName: 'bob',
            displayName: 'Bob',
          ),
        );
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:test:carol',
            credentialName: 'carol',
            displayName: 'Carol',
          ),
        );

    await staleDelayed.timeout(const Duration(seconds: 1));
    await coordinator.requestSync('carol_startup', immediate: true);

    expect(sync.syncReasons, ['alice_startup', 'carol_startup']);
    expect(
      container.read(messageSyncCoordinatorProvider).lastReason,
      'carol_startup',
    );
  });

  test(
    'bound startup records Patch subscribe and reset before reliable sync',
    () async {
      final gateway = FakeAwikiGateway();
      final conversations = _BoundReadyConversationService(
        gateway,
        ownerIdentityId: 'owner-a',
      );
      final container = _container(
        gateway,
        FakeMessageSyncService(),
        session: _boundSession(deviceAuthGeneration: '1'),
        conversationService: conversations,
      );
      addTearDown(container.dispose);
      addTearDown(conversations.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);

      final observation = container
          .read(conversationListProvider.notifier)
          .patchStartupObservation;
      expect(observation, isNotNull);
      expect(observation!.provesSubscribeBeforeFirstReliableSync, isTrue);
      expect(
        observation.subscriptionStartedSequence,
        lessThan(observation.patchReadySequence!),
      );
      expect(
        observation.patchReadySequence,
        lessThan(observation.firstReliableSyncStartedSequence!),
      );
    },
  );

  test(
    'same DID auth-generation change rejects stale sync completion',
    () async {
      final gateway = FakeAwikiGateway();
      final syncCompletion = Completer<void>();
      final sync = FakeMessageSyncService()..syncNowCompleter = syncCompletion;
      final devices = FakeDeviceManagementCore();
      final conversations = _BoundReadyConversationService(
        gateway,
        ownerIdentityId: 'owner-a',
      );
      final container = _container(
        gateway,
        sync,
        devices: devices,
        session: _boundSession(deviceAuthGeneration: '1'),
        conversationService: conversations,
      );
      addTearDown(container.dispose);
      addTearDown(conversations.dispose);

      final oldSync = container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);
      await pumpEventQueue();
      expect(sync.syncReasons, ['startup']);

      container
          .read(sessionProvider.notifier)
          .setSession(_boundSession(deviceAuthGeneration: '2'));
      container.read(messageSyncCoordinatorProvider.notifier).resetForSession();
      syncCompletion.complete();
      await oldSync;
      await pumpEventQueue();

      expect(devices.registryCalls, 0);
      expect(devices.joinRequestCalls, 0);
      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.idle,
      );
    },
  );

  test('successful reliable sync refreshes the verified Join inbox', () async {
    final gateway = FakeAwikiGateway();
    final sync = FakeMessageSyncService();
    final devices = FakeDeviceManagementCore()
      ..registry = const DeviceRegistrySnapshot(
        did: 'did:test:me',
        devices: <DeviceSummary>[
          DeviceSummary(
            protocolDeviceId: 'admin-current',
            signingKeyId: 'did:test:me#admin-sign',
            e2eeKeyId: 'did:test:me#admin-e2ee',
            status: DeviceStatus.active,
            role: DeviceRole.admin,
            managementReady: true,
            isCurrent: true,
          ),
        ],
      );
    final container = _container(gateway, sync, devices: devices);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('system_notification_changed', immediate: true);

    expect(devices.registryCalls, 1);
    expect(devices.joinRequestCalls, 1);
  });

  test('safe diagnostics refresh is typed and best-effort', () async {
    final gateway = FakeAwikiGateway();
    final successAt = DateTime.utc(2026, 7, 29, 8);
    final retryAt = DateTime.utc(2026, 7, 29, 8, 1);
    final messaging = _DiagnosticMessagingService(
      gateway,
      diagnostics: AppMessageSyncDiagnostics(
        lastSuccessAt: successAt,
        mode: AppMessageSyncMode.retryable,
        pendingMutationCount: 2,
        dirtyDomains: const <AppMessageSyncDirtyDomain>[
          AppMessageSyncDirtyDomain.messages,
          AppMessageSyncDirtyDomain.readState,
        ],
        retryState: AppMessageSyncRetryState.scheduled,
        nextRetryAt: retryAt,
      ),
    );
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync, messagingService: messaging);
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    await coordinator.requestSync('startup', immediate: true);

    var state = container.read(messageSyncCoordinatorProvider);
    expect(messaging.diagnosticsCalls, 1);
    expect(state.lastSuccessAt, successAt);
    expect(state.mode, AppMessageSyncMode.retryable);
    expect(state.pendingMutationCount, 2);
    expect(state.dirtyDomains, <AppMessageSyncDirtyDomain>[
      AppMessageSyncDirtyDomain.messages,
      AppMessageSyncDirtyDomain.readState,
    ]);
    expect(state.retryState, AppMessageSyncRetryState.scheduled);
    expect(state.nextRetryAt, retryAt);
    final firstSafe = state.safeDiagnostics;
    expect(firstSafe.isCurrent, isTrue);
    expect(firstSafe.refreshAttemptSequence, 1);
    expect(firstSafe.refreshSuccessSequence, 1);
    expect(firstSafe.refreshedAt, isNotNull);
    expect(firstSafe.toJson(), <String, Object?>{
      'schema_version': 2,
      'current': true,
      'refresh_attempt_sequence': 1,
      'refresh_success_sequence': 1,
      'refreshed_at': firstSafe.refreshedAt!.toUtc().toIso8601String(),
      'last_success_at': successAt.toIso8601String(),
      'mode': 'retryable',
      'pending_mutation_count': 2,
      'dirty_domains': <String>['messages', 'readState'],
      'retry_state': 'scheduled',
      'next_retry_at': retryAt.toIso8601String(),
      'first_retryable_failure_at': null,
      'last_failure_at': null,
      'last_failure_stage': null,
      'last_failure_category': null,
      'last_failure_code': null,
      'last_failure_http_status': null,
      'retryable_failure_surface_at': null,
      'retryable_failure_visible': false,
      'consecutive_retryable_failures': 0,
      'automatic_retry_pending': true,
    });

    messaging.nextDiagnosticsError = StateError('diagnostics unavailable');
    sync.deltaResult = const MessageSyncOutcome(
      status: MessageSyncStatus.changed,
      eventsApplied: 1,
      pagesFetched: 1,
    );
    await coordinator.requestSync('realtime_hint', immediate: true);

    state = container.read(messageSyncCoordinatorProvider);
    expect(messaging.diagnosticsCalls, 2);
    expect(state.status, MessageSyncCoordinatorStatus.idle);
    expect(state.lastStatus, MessageSyncStatus.changed);
    expect(state.lastError, isNull);
    expect(state.lastSuccessAt, successAt);
    expect(state.pendingMutationCount, 2);
    final staleSafe = state.safeDiagnostics;
    expect(staleSafe.isCurrent, isFalse);
    expect(staleSafe.refreshAttemptSequence, 2);
    expect(staleSafe.refreshSuccessSequence, 1);
    expect(staleSafe.refreshedAt, firstSafe.refreshedAt);
    expect(staleSafe.toJson()['current'], isFalse);
  });

  test('successful sync honors the Core mutation retry deadline', () async {
    final gateway = FakeAwikiGateway();
    final retryAt = DateTime.now().add(const Duration(milliseconds: 40));
    final retryObserved = Completer<void>();
    final messaging = _SequencedDiagnosticMessagingService(
      gateway,
      diagnostics: <AppMessageSyncDiagnostics>[
        AppMessageSyncDiagnostics(
          mode: AppMessageSyncMode.retryable,
          pendingMutationCount: 1,
          dirtyDomains: const <AppMessageSyncDirtyDomain>[
            AppMessageSyncDirtyDomain.readState,
          ],
          retryState: AppMessageSyncRetryState.scheduled,
          nextRetryAt: retryAt,
        ),
        const AppMessageSyncDiagnostics(
          mode: AppMessageSyncMode.idle,
          pendingMutationCount: 0,
          retryState: AppMessageSyncRetryState.none,
        ),
      ],
      onSecondRefresh: retryObserved,
    );
    final sync = FakeMessageSyncService();
    final container = _container(
      gateway,
      sync,
      minInterval: const Duration(milliseconds: 5),
      messagingService: messaging,
    );
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    await coordinator.requestSync('startup', immediate: true);

    expect(sync.syncReasons, ['startup']);
    expect(
      container.read(messageSyncCoordinatorProvider).automaticRetryPending,
      isTrue,
    );

    await retryObserved.future.timeout(const Duration(seconds: 1));
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup', 'core_directed_retry']);
    final state = container.read(messageSyncCoordinatorProvider);
    expect(state.status, MessageSyncCoordinatorStatus.idle);
    expect(state.pendingMutationCount, 0);
    expect(state.retryState, AppMessageSyncRetryState.none);
    expect(state.automaticRetryPending, isFalse);
    expect(state.lastError, isNull);
  });

  test(
    'v2 committed live incoming message notifies once by event and message',
    () async {
      final message = ChatMessage(
        localId: 'message-1',
        remoteId: 'message-1',
        conversationId: 'dm:peer-scope:v1:peer',
        threadId: 'dm:peer-scope:v1:peer',
        senderDid: 'did:test:peer',
        senderName: 'Peer',
        receiverDid: 'did:test:me',
        content: 'committed hello',
        createdAt: DateTime.utc(2026, 7, 28, 9),
        isMine: false,
        sendState: MessageSendState.sent,
      );
      final committed = CommittedIncomingMessage(
        eventId: 'event-1',
        logicalMessageId: 'message-1',
        message: message,
      );
      final notifications = FakeNotificationFacade();
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[committed],
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      await coordinator.requestSync('realtime_message', immediate: true);
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          CommittedIncomingMessage(
            eventId: 'event-2',
            logicalMessageId: 'message-1',
            message: message,
          ),
        ],
      );
      await coordinator.requestSync(
        'realtime_duplicate_message',
        immediate: true,
      );
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          CommittedIncomingMessage(
            eventId: 'event-1',
            logicalMessageId: 'message-2',
            message: message,
          ),
        ],
      );
      await coordinator.requestSync(
        'realtime_duplicate_event',
        immediate: true,
      );
      await pumpEventQueue();

      expect(notifications.inAppCalls, 1);
      expect(notifications.lastInAppTitle, 'Peer');
      expect(notifications.lastInAppBody, 'committed hello');
    },
  );

  test(
    'macOS inactive window uses a system notification while Flutter is resumed',
    () async {
      const channel = MethodChannel('ai.awiki.awikime/app_presentation');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getState');
            return <String, Object?>{
              'applicationActive': false,
              'windowVisible': true,
              'windowMiniaturized': true,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final message = ChatMessage(
        localId: 'message-background-1',
        remoteId: 'message-background-1',
        conversationId: 'dm:peer-scope:v1:peer',
        threadId: 'dm:peer-scope:v1:peer',
        senderDid: 'did:test:peer',
        senderName: 'Peer',
        receiverDid: 'did:test:me',
        content: 'background hello',
        createdAt: DateTime.utc(2026, 7, 30, 9),
        isMine: false,
        sendState: MessageSendState.sent,
      );
      final notifications = FakeNotificationFacade();
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[
            CommittedIncomingMessage(
              eventId: 'event-background-1',
              logicalMessageId: 'message-background-1',
              message: message,
            ),
          ],
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        appPresentationService: MethodChannelAppPresentationService(
          channel: channel,
          isMacOS: () => true,
        ),
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('realtime_message', immediate: true);
      await pumpEventQueue();

      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 1);
      expect(notifications.lastSystemTitle, 'Peer');
      expect(notifications.lastSystemBody, 'background hello');
    },
  );

  test(
    'system notification prefers the current Agent inventory display name',
    () async {
      const channel = MethodChannel('ai.awiki.awikime/app_presentation');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getState');
            return <String, Object?>{
              'applicationActive': false,
              'windowVisible': true,
              'windowMiniaturized': true,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      const skillDid =
          'did:wba:agent-connect.cn:agent:skill:skill-test:e1_skill';
      final message = ChatMessage(
        localId: 'message-skill-background-1',
        remoteId: 'message-skill-background-1',
        conversationId: 'dm:peer-scope:v1:skill',
        threadId: 'dm:peer-scope:v1:skill',
        senderDid: skillDid,
        senderName: 'skill-cc44721e0153c892',
        receiverDid: 'did:test:me',
        content: 'completed notification',
        createdAt: DateTime.utc(2026, 7, 30, 9, 30),
        isMine: false,
        sendState: MessageSendState.sent,
      );
      final notifications = FakeNotificationFacade();
      final agentControl = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: skillDid,
            kind: AgentKind.daemon,
            displayName: 'AWiki Skill Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[
            CommittedIncomingMessage(
              eventId: 'event-skill-background-1',
              logicalMessageId: 'message-skill-background-1',
              message: message,
            ),
          ],
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        appPresentationService: MethodChannelAppPresentationService(
          channel: channel,
          isMacOS: () => true,
        ),
        agentControl: agentControl,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      expect(container.read(agentsProvider).agents, isEmpty);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('realtime_message', immediate: true);
      await pumpEventQueue();

      expect(
        container
            .read(agentsProvider)
            .agents
            .singleWhere((agent) => agent.agentDid == skillDid)
            .displayName,
        'AWiki Skill Agent',
      );
      expect(notifications.systemCalls, 1);
      expect(notifications.lastSystemTitle, 'AWiki Skill Agent');
    },
  );

  test(
    'v2 committed Runtime Agent final message shares terminal deduplication',
    () async {
      final message = ChatMessage(
        localId: 'runtime-final-1',
        remoteId: 'runtime-final-1',
        conversationId: 'dm:runtime',
        threadId: 'dm:runtime',
        senderDid: 'did:agent:runtime',
        senderName: 'Codex',
        receiverDid: 'did:test:me',
        content: 'ordinary final reply',
        createdAt: DateTime.utc(2026, 7, 29, 9),
        isMine: false,
        sendState: MessageSendState.sent,
      );
      final notifications = FakeNotificationFacade();
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[
            CommittedIncomingMessage(
              eventId: 'event-runtime-final-1',
              logicalMessageId: 'runtime-final-1',
              message: message,
            ),
          ],
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'codex',
              'status': 'ready',
            },
          ],
        },
      );
      container
          .read(agentTerminalNotificationDeduplicatorProvider)
          .acceptStatus(const <String, Object?>{
            'schema': 'awiki.agent.status.v1',
            'event_id': 'evt_run_terminal:run_1:completed',
            'run_id': 'run_1',
            'state': 'finished',
            'business_outcome': 'completed',
            'summary': '任务已完成',
            'final_message_id': 'runtime-final-1',
          });

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('realtime_agent_control', immediate: true);

      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
    },
  );

  test('recovery-required outcome never synthesizes a notification', () async {
    final notifications = FakeNotificationFacade();
    final container = _container(
      FakeAwikiGateway(),
      FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.recoveryRequired,
          eventsApplied: 0,
          pagesFetched: 1,
        ),
      ),
      notifications: notifications,
      syncV2ReadEnabled: true,
    );
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('startup', immediate: true);

    expect(notifications.inAppCalls, 0);
    expect(notifications.systemCalls, 0);
  });

  test(
    'outgoing bootstrap recovery history and replay outcomes do not notify',
    () async {
      final notifications = FakeNotificationFacade();
      final sync = FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      for (final reason in <String>[
        'outgoing',
        'bootstrap',
        'recovery',
        'history',
        'replay',
      ]) {
        await coordinator.requestSync(reason, immediate: true);
      }

      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
    },
  );

  test('failed reliable sync does not refresh the Join inbox', () async {
    final gateway = FakeAwikiGateway();
    final devices = FakeDeviceManagementCore();
    final container = _container(
      gateway,
      _FailingMessageSyncService(),
      devices: devices,
    );
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('system_notification_changed', immediate: true);
    await pumpEventQueue();

    expect(devices.registryCalls, 0);
    expect(devices.joinRequestCalls, 0);
    expect(
      container.read(messageSyncCoordinatorProvider).lastError,
      isA<StateError>(),
    );
  });

  test(
    'one retryable failure retries once without surfacing a global failure',
    () async {
      final sync = FakeMessageSyncService()
        ..nextDeltaError = StateError('transient_sync_failure');
      final container = _container(
        FakeAwikiGateway(),
        sync,
        failureSurfaceDelay: const Duration(seconds: 1),
      );
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('foreground_periodic', immediate: true);
      await pumpEventQueue();

      final state = container.read(messageSyncCoordinatorProvider);
      expect(sync.syncReasons, ['foreground_periodic', 'automatic_retry']);
      expect(state.status, MessageSyncCoordinatorStatus.idle);
      expect(state.consecutiveRetryableFailures, 0);
      expect(state.automaticRetryPending, isFalse);
      expect(state.shouldSurfaceRetryableFailure, isFalse);
      expect(state.lastError, isNull);
    },
  );

  test(
    'failure count does not surface before the duration threshold',
    () async {
      final sync = _FailingMessageSyncService();
      final container = _container(
        FakeAwikiGateway(),
        sync,
        failureBackoff: const Duration(seconds: 1),
        failureSurfaceDelay: const Duration(seconds: 1),
      );
      addTearDown(container.dispose);

      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );
      await coordinator.requestSync('foreground_periodic', immediate: true);
      await coordinator.requestSync('manual_refresh', immediate: true);

      final state = container.read(messageSyncCoordinatorProvider);
      expect(state.status, MessageSyncCoordinatorStatus.retryableFailure);
      expect(state.consecutiveRetryableFailures, 2);
      expect(state.shouldSurfaceRetryableFailure, isFalse);
      expect(state.lastError, isA<StateError>());
    },
  );

  test('typed retryable outcome preserves a safe transport category', () async {
    final sync = FakeMessageSyncService(
      deltaResult: const MessageSyncOutcome(
        status: MessageSyncStatus.retryableFailure,
        eventsApplied: 0,
        pagesFetched: 0,
        errorCode: 'TRANSPORT_UNAVAILABLE',
      ),
    );
    final container = _container(FakeAwikiGateway(), sync);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('foreground_periodic', immediate: true);

    final diagnostics = container
        .read(messageSyncCoordinatorProvider)
        .safeDiagnostics;
    expect(
      diagnostics.lastFailureCategory,
      AppMessageSyncFailureCategory.transport,
    );
    expect(diagnostics.lastFailureCode, 'TRANSPORT_UNAVAILABLE');
  });

  test(
    'thrown HTTP auth rejection is terminal and never auto-retried',
    () async {
      final sync = FakeMessageSyncService()
        ..nextDeltaError = const MessageSyncCoreFailure(
          category: AppMessageSyncFailureCategory.auth,
          code: 'message content leaked',
          httpStatus: 401,
        );
      final container = _container(FakeAwikiGateway(), sync);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('foreground_periodic', immediate: true);

      final state = container.read(messageSyncCoordinatorProvider);
      expect(sync.syncReasons, ['foreground_periodic']);
      expect(state.status, MessageSyncCoordinatorStatus.authRevoked);
      expect(state.automaticRetryPending, isFalse);
      expect(
        state.safeDiagnostics.lastFailureCategory,
        AppMessageSyncFailureCategory.auth,
      );
      expect(state.safeDiagnostics.lastFailureCode, 'message_sync_failure');
      expect(state.safeDiagnostics.lastFailureHttpStatus, 401);
      expect(
        state.safeDiagnostics.toJson().toString(),
        isNot(contains('message content')),
      );
    },
  );

  test(
    'one sustained failure surfaces when the duration threshold elapses',
    () async {
      final sync = _FailingMessageSyncService();
      final container = _container(
        FakeAwikiGateway(),
        sync,
        failureBackoff: const Duration(seconds: 1),
        failureSurfaceDelay: const Duration(milliseconds: 30),
      );
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('foreground_periodic', immediate: true);

      var state = container.read(messageSyncCoordinatorProvider);
      expect(state.consecutiveRetryableFailures, 1);
      expect(state.shouldSurfaceRetryableFailure, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 45));
      state = container.read(messageSyncCoordinatorProvider);
      expect(state.consecutiveRetryableFailures, 1);
      expect(state.shouldSurfaceRetryableFailure, isTrue);
      expect(
        state.safeDiagnostics.lastFailureStage,
        AppMessageSyncFailureStage.coreSync,
      );
      expect(
        state.safeDiagnostics.lastFailureCategory,
        AppMessageSyncFailureCategory.unknown,
      );
      expect(state.safeDiagnostics.lastFailureCode, 'message_sync_core_failed');
    },
  );

  test(
    'post-commit projection failure does not become a sync failure',
    () async {
      final gateway = FakeAwikiGateway();
      final conversations = _PostCommitFailingConversationService(gateway);
      final sync = FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
        ),
      );
      final container = _container(
        gateway,
        sync,
        conversationService: conversations,
      );
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('foreground_periodic', immediate: true);

      final state = container.read(messageSyncCoordinatorProvider);
      expect(state.lastStatus, MessageSyncStatus.changed);
      expect(
        state.status,
        MessageSyncCoordinatorStatus.projectionRefreshFailed,
      );
      expect(state.consecutiveRetryableFailures, 0);
      expect(state.automaticRetryPending, isFalse);
      expect(
        state.safeDiagnostics.lastFailureStage,
        AppMessageSyncFailureStage.postCommitProjection,
      );
      expect(
        state.safeDiagnostics.lastFailureCategory,
        AppMessageSyncFailureCategory.projection,
      );
      expect(
        state.safeDiagnostics.lastFailureCode,
        'message_sync_projection_refresh_failed',
      );
    },
  );

  test(
    'identity change while Join inbox waits stops the stale sync projection',
    () async {
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[_conversation()];
      final sync = FakeMessageSyncService();
      final joinInbox = Completer<List<DeviceJoinRequestNotice>>();
      final joinInboxStarted = Completer<void>();
      final devices = FakeDeviceManagementCore()
        ..registry = const DeviceRegistrySnapshot(
          did: 'did:test:me',
          devices: <DeviceSummary>[
            DeviceSummary(
              protocolDeviceId: 'admin-current',
              signingKeyId: 'did:test:me#admin-sign',
              e2eeKeyId: 'did:test:me#admin-e2ee',
              status: DeviceStatus.active,
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
          ],
        )
        ..joinRequestsLoader = (selector) {
          joinInboxStarted.complete();
          return joinInbox.future;
        };
      final container = _container(gateway, sync, devices: devices);
      addTearDown(() {
        if (!joinInbox.isCompleted) {
          joinInbox.complete(const <DeviceJoinRequestNotice>[]);
        }
        container.dispose();
      });
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      final staleSync = coordinator.requestSync(
        'alice_system_notification',
        immediate: true,
      );
      await joinInboxStarted.future;
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:bob',
              credentialName: 'bob',
              displayName: 'Bob',
            ),
          );
      joinInbox.complete(const <DeviceJoinRequestNotice>[]);
      await staleSync;

      expect(gateway.listConversationsCalls, 1);
      expect(container.read(messageSyncCoordinatorProvider).lastReason, isNull);
      expect(container.read(messageSyncCoordinatorProvider).lastError, isNull);
    },
  );
}

CommittedIncomingMessage _committedIncoming({
  required String eventId,
  required String logicalId,
  String? localId,
  String? remoteId,
  String senderDid = 'did:test:peer',
}) {
  return CommittedIncomingMessage(
    eventId: eventId,
    logicalMessageId: logicalId,
    message: _incomingMessage(
      logicalId: logicalId,
      localId: localId,
      remoteId: remoteId,
      senderDid: senderDid,
    ),
  );
}

ChatMessage _incomingMessage({
  required String logicalId,
  String? localId,
  String? remoteId,
  String senderDid = 'did:test:peer',
}) {
  return ChatMessage(
    localId: localId ?? 'local-$logicalId',
    remoteId: remoteId ?? 'remote-$logicalId',
    conversationId: 'dm:peer-scope:v1:peer',
    threadId: 'dm:peer-scope:v1:peer',
    senderDid: senderDid,
    senderName: senderDid == 'did:agent:runtime' ? 'Codex' : 'Peer',
    receiverDid: 'did:test:me',
    content: 'committed $logicalId',
    createdAt: DateTime.utc(2026, 7, 30, 9),
    isMine: false,
    sendState: MessageSendState.sent,
  );
}

FakeDeviceManagementCore _deviceCoreWithBlockingJoinInbox({
  required Completer<void> started,
  required Completer<List<DeviceJoinRequestNotice>> gate,
}) {
  return FakeDeviceManagementCore()
    ..registry = const DeviceRegistrySnapshot(
      did: 'did:test:me',
      devices: <DeviceSummary>[
        DeviceSummary(
          protocolDeviceId: 'admin-current',
          signingKeyId: 'did:test:me#admin-sign',
          e2eeKeyId: 'did:test:me#admin-e2ee',
          status: DeviceStatus.active,
          role: DeviceRole.admin,
          managementReady: true,
          isCurrent: true,
        ),
      ],
    )
    ..joinRequestsLoader = (selector) {
      if (!started.isCompleted) {
        started.complete();
      }
      return gate.future;
    };
}

ProviderContainer _container(
  FakeAwikiGateway gateway,
  MessageSyncService sync, {
  Duration minInterval = Duration.zero,
  Duration failureBackoff = Duration.zero,
  Duration failureSurfaceDelay = Duration.zero,
  FakeDeviceManagementCore? devices,
  FakeNotificationFacade? notifications,
  AppPresentationService? appPresentationService,
  FakeAgentControlService? agentControl,
  bool syncV2ReadEnabled = false,
  SessionIdentity? session,
  FakeMessagingService? messagingService,
  ConversationService? conversationService,
}) {
  return ProviderContainer(
    overrides: <Override>[
      awikiGatewayProvider.overrideWithValue(gateway),
      awikiEnvironmentConfigProvider.overrideWithValue(
        AwikiEnvironmentConfig(messageSyncV2ReadEnabled: syncV2ReadEnabled),
      ),
      notificationFacadeProvider.overrideWithValue(
        notifications ?? FakeNotificationFacade(),
      ),
      if (appPresentationService != null)
        appPresentationServiceProvider.overrideWithValue(
          appPresentationService,
        ),
      deviceManagementCorePortProvider.overrideWithValue(
        devices ?? FakeDeviceManagementCore(),
      ),
      ...fakeApplicationServiceOverrides(
        gateway,
        messageSyncService: sync,
        messagingService: messagingService,
        conversationService: conversationService,
        agentControlService: agentControl,
      ),
      messageSyncCoordinatorProvider.overrideWith(
        (ref) => MessageSyncCoordinator(
          ref,
          minInterval: minInterval,
          failureBackoff: failureBackoff,
          failureSurfaceDelay: failureSurfaceDelay,
        ),
      ),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        controller.setSession(
          session ??
              const SessionIdentity(
                did: 'did:test:me',
                credentialName: 'default',
                displayName: 'Me',
                handle: 'me',
              ),
        );
        return controller;
      }),
    ],
  );
}

SessionIdentity _boundSession({required String deviceAuthGeneration}) {
  return SessionIdentity(
    did: 'did:test:me',
    credentialName: 'owner-a',
    displayName: 'Me',
    handle: 'me',
    accountBinding: SessionAccountBinding(
      ownerIdentityId: 'owner-a',
      accountId: 'account-a',
      currentDid: 'did:test:me',
      protocolDeviceId: 'device-a',
      identityGeneration: '1',
      deviceAuthGeneration: deviceAuthGeneration,
    ),
  );
}

ConversationSummary _conversation() {
  return ConversationSummary(
    threadId: 'dm:did:test:me:did:test:peer',
    conversationId: 'dm:did:test:me:did:test:peer',
    displayName: 'Peer',
    lastMessagePreview: 'hello',
    lastMessageAt: DateTime.utc(2026, 6, 27, 9),
    unreadCount: 0,
    isGroup: false,
    targetDid: 'did:test:peer',
  );
}

class _BlockingMessageSyncService extends FakeMessageSyncService {
  final Completer<MessageSyncOutcome> _syncCompleter =
      Completer<MessageSyncOutcome>();

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) {
    syncReasons.add(reason);
    return _syncCompleter.future;
  }

  void complete() {
    if (_syncCompleter.isCompleted) {
      return;
    }
    _syncCompleter.complete(
      const MessageSyncOutcome(
        status: MessageSyncStatus.idle,
        eventsApplied: 0,
        pagesFetched: 0,
      ),
    );
  }
}

class _QueuedBlockingMessageSyncService extends FakeMessageSyncService {
  final List<Completer<MessageSyncOutcome>> _pending =
      <Completer<MessageSyncOutcome>>[];

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) {
    syncReasons.add(reason);
    final completer = Completer<MessageSyncOutcome>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext() {
    final completer = _pending.removeAt(0);
    completer.complete(
      const MessageSyncOutcome(
        status: MessageSyncStatus.idle,
        eventsApplied: 0,
        pagesFetched: 1,
      ),
    );
  }
}

class _PostCommitConversationGateway extends FakeAwikiGateway {
  _PostCommitConversationGateway(ConversationSummary stale) {
    conversations = <ConversationSummary>[stale];
  }

  final Completer<void> firstRefreshStarted = Completer<void>();
  final Completer<void> _releaseFirst = Completer<void>();
  int _calls = 0;

  @override
  Future<List<ConversationSummary>> listConversations() async {
    listConversationsCalls += 1;
    _calls += 1;
    final result = List<ConversationSummary>.of(conversations);
    if (_calls == 1) {
      firstRefreshStarted.complete();
      await _releaseFirst.future;
    }
    return result;
  }

  void releaseFirst() {
    if (!_releaseFirst.isCompleted) {
      _releaseFirst.complete();
    }
  }

  void releaseFirstIfPending() => releaseFirst();
}

class _PostCommitRefreshBlockingGateway extends FakeAwikiGateway {
  _PostCommitRefreshBlockingGateway(ConversationSummary conversation) {
    conversations = <ConversationSummary>[conversation];
  }

  final Completer<void> postCommitRefreshStarted = Completer<void>();
  final Completer<void> _release = Completer<void>();

  @override
  Future<List<ConversationSummary>> listConversations() async {
    listConversationsCalls += 1;
    if (listConversationsCalls == 2) {
      postCommitRefreshStarted.complete();
      await _release.future;
    }
    return List<ConversationSummary>.of(conversations);
  }

  void release() {
    if (!_release.isCompleted) {
      _release.complete();
    }
  }
}

class _SequencedMessageSyncService extends FakeMessageSyncService {
  _SequencedMessageSyncService(this.outcomes);

  final List<MessageSyncOutcome> outcomes;
  var _next = 0;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    return outcomes[_next++];
  }
}

class _FirstGatedSequencedMessageSyncService
    extends _SequencedMessageSyncService {
  _FirstGatedSequencedMessageSyncService({
    required List<MessageSyncOutcome> outcomes,
    required this.firstGate,
    required this.firstStarted,
    required this.secondCompleted,
  }) : super(outcomes);

  final Completer<void> firstGate;
  final Completer<void> firstStarted;
  final Completer<void> secondCompleted;
  var _calls = 0;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    _calls += 1;
    if (_calls == 1) {
      firstStarted.complete();
      await firstGate.future;
    }
    final result = await super.syncNow(reason: reason, limit: limit);
    if (_calls == 2 && !secondCompleted.isCompleted) {
      secondCompleted.complete();
    }
    return result;
  }
}

class _PendingTimerRaceMessageSyncService extends FakeMessageSyncService {
  _PendingTimerRaceMessageSyncService({
    required this.outcomes,
    required this.remoteGate,
    required this.remoteStarted,
    required this.followUpCompleted,
  });

  final List<MessageSyncOutcome> outcomes;
  final Completer<void> remoteGate;
  final Completer<void> remoteStarted;
  final Completer<void> followUpCompleted;
  var _next = 0;
  var _activeCalls = 0;
  var maxActiveCalls = 0;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    _activeCalls += 1;
    if (_activeCalls > maxActiveCalls) {
      maxActiveCalls = _activeCalls;
    }
    final index = _next++;
    try {
      if (index == 1) {
        remoteStarted.complete();
        await remoteGate.future;
      }
      final result = outcomes[index];
      if (index == 2 && !followUpCompleted.isCompleted) {
        followUpCompleted.complete();
      }
      return result;
    } finally {
      _activeCalls -= 1;
    }
  }
}

class _PublishingMessageSyncService extends FakeMessageSyncService {
  _PublishingMessageSyncService({
    required this.gateway,
    required this.committed,
  });

  final FakeAwikiGateway gateway;
  final ConversationSummary committed;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    gateway.conversations = <ConversationSummary>[committed];
    return const MessageSyncOutcome(
      status: MessageSyncStatus.changed,
      eventsApplied: 1,
      pagesFetched: 1,
    );
  }
}

class _DiagnosticMessagingService extends FakeMessagingService
    implements MessageSyncDiagnosticsService {
  _DiagnosticMessagingService(super.gateway, {required this.diagnostics});

  AppMessageSyncDiagnostics diagnostics;
  Object? nextDiagnosticsError;
  int diagnosticsCalls = 0;

  @override
  Future<AppMessageSyncDiagnostics> syncDiagnostics() async {
    diagnosticsCalls += 1;
    final error = nextDiagnosticsError;
    nextDiagnosticsError = null;
    if (error != null) {
      throw error;
    }
    return diagnostics;
  }
}

class _SequencedDiagnosticMessagingService extends FakeMessagingService
    implements MessageSyncDiagnosticsService {
  _SequencedDiagnosticMessagingService(
    super.gateway, {
    required this.diagnostics,
    required this.onSecondRefresh,
  });

  final List<AppMessageSyncDiagnostics> diagnostics;
  final Completer<void> onSecondRefresh;
  int _index = 0;

  @override
  Future<AppMessageSyncDiagnostics> syncDiagnostics() async {
    final current = diagnostics[_index.clamp(0, diagnostics.length - 1)];
    _index += 1;
    if (_index == 2 && !onSecondRefresh.isCompleted) {
      onSecondRefresh.complete();
    }
    return current;
  }
}

class _BoundReadyConversationService extends FakeConversationService {
  _BoundReadyConversationService(
    super.gateway, {
    required this.ownerIdentityId,
  });

  final String ownerIdentityId;
  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    scheduleMicrotask(() {
      if (_patches.isClosed) {
        return;
      }
      _patches.add(
        ConversationListPatch(
          kind: ConversationListPatchKind.reset,
          ownerIdentityId: ownerIdentityId,
          ownerDid: ownerDid,
          version: 1,
          unreadTotal: 0,
          items: gateway.conversations,
        ),
      );
    });
    return _patches.stream;
  }

  Future<void> dispose() => _patches.close();
}

class _PostCommitFailingConversationService extends FakeConversationService {
  _PostCommitFailingConversationService(super.gateway);

  var _fastListCalls = 0;

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) {
    _fastListCalls += 1;
    if (_fastListCalls >= 2) {
      throw StateError('projection_refresh_failed');
    }
    return super.listConversationSummariesFast(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
  }
}

class _FailingMessageSyncService extends FakeMessageSyncService {
  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    throw StateError('sync_failed');
  }
}
