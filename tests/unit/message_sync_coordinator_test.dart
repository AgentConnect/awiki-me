import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/app_presentation_service.dart';
import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/message_sync_diagnostics.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/data/services/method_channel_app_presentation_service.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_terminal_notification_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';
import 'devices/device_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      'schema_version': 1,
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
      final container = _container(FakeAwikiGateway(), sync);
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
    'two consecutive retryable failures stop automatic retry and surface error',
    () async {
      final sync = _FailingMessageSyncService();
      final container = _container(FakeAwikiGateway(), sync);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('foreground_periodic', immediate: true);
      await pumpEventQueue();

      final state = container.read(messageSyncCoordinatorProvider);
      expect(sync.syncReasons, ['foreground_periodic', 'automatic_retry']);
      expect(state.status, MessageSyncCoordinatorStatus.retryableFailure);
      expect(state.consecutiveRetryableFailures, 2);
      expect(state.automaticRetryPending, isFalse);
      expect(state.shouldSurfaceRetryableFailure, isTrue);
      expect(state.lastError, isA<StateError>());
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

ProviderContainer _container(
  FakeAwikiGateway gateway,
  MessageSyncService sync, {
  Duration minInterval = Duration.zero,
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
          failureBackoff: Duration.zero,
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
