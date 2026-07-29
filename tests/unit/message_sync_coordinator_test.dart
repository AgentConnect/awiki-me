import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';
import 'devices/device_test_support.dart';

void main() {
  test('single-flight coalesces concurrent sync requests', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync);
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final first = coordinator.requestSync('startup', immediate: true);
    final second = coordinator.requestSync('app_resumed', immediate: true);
    await Future.wait(<Future<void>>[first, second]);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup', 'app_resumed']);
    expect(
      container.read(conversationListProvider).conversations,
      hasLength(1),
    );
  });

  test(
    'snapshot required records degraded state without refreshing recents',
    () async {
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[_conversation()];
      final sync = FakeMessageSyncService(
        deltaResult: const MessageSyncDeltaResult(
          eventsApplied: 0,
          pagesFetched: 1,
          hasMore: false,
          snapshotRequired: true,
        ),
      );
      final container = _container(gateway, sync);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);

      expect(
        container.read(messageSyncCoordinatorProvider).snapshotRequired,
        isTrue,
      );
      expect(gateway.listConversationsCalls, 0);
    },
  );

  test('startup sync prewarms local histories for fast first open', () async {
    final conversation = _conversation();
    final localMessage = ChatMessage(
      localId: 'local-1',
      remoteId: 'remote-1',
      threadId: conversation.threadId,
      senderDid: 'did:test:peer',
      receiverDid: 'did:test:me',
      content: 'prewarmed',
      createdAt: conversation.lastMessageAt,
      isMine: false,
      serverSequence: 1,
      sendState: MessageSendState.sent,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:test:peer': <ChatMessage>[localMessage],
      };
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('startup', immediate: true);

    expect(gateway.fetchLocalDmHistoryCalls, 1);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(
      container
          .read(chatThreadProvider(conversation.threadId))
          .messages
          .map((item) => item.content),
      ['prewarmed'],
    );
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
      final container = _container(gateway, sync);
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

  test('startup prewarm 不会因为本地尾部是自己发的消息而清掉未读', () async {
    final conversation = _conversation().copyWith(
      lastMessagePreview: 'remote unread',
      lastMessageAt: DateTime.utc(2026, 6, 27, 9, 1),
      unreadCount: 2,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'incoming-1',
    );
    final outgoingTail = ChatMessage(
      localId: 'local-outgoing-tail',
      remoteId: 'remote-outgoing-tail',
      threadId: conversation.threadId,
      senderDid: 'did:test:me',
      receiverDid: 'did:test:peer',
      content: 'my local tail',
      createdAt: conversation.lastMessageAt.add(const Duration(seconds: 10)),
      isMine: true,
      serverSequence: 2,
      sendState: MessageSendState.sent,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:test:peer': <ChatMessage>[outgoingTail],
      };
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('startup', immediate: true);

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(updated.lastMessagePreview, 'my local tail');
    expect(updated.unreadCount, 2);
    expect(updated.unreadMentionCount, 1);
    expect(updated.firstUnreadMentionMessageId, 'incoming-1');
  });

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

      expect(gateway.listConversationsCalls, 1);
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

    expect(devices.registryCalls, 0);
    expect(devices.joinRequestCalls, 0);
    expect(
      container.read(messageSyncCoordinatorProvider).lastError,
      isA<StateError>(),
    );
  });

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

      expect(gateway.listConversationsCalls, 0);
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
}) {
  return ProviderContainer(
    overrides: <Override>[
      awikiGatewayProvider.overrideWithValue(gateway),
      notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
      deviceManagementCorePortProvider.overrideWithValue(
        devices ?? FakeDeviceManagementCore(),
      ),
      ...fakeApplicationServiceOverrides(gateway, messageSyncService: sync),
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
  final Completer<MessageSyncDeltaResult> _syncCompleter =
      Completer<MessageSyncDeltaResult>();

  @override
  Future<MessageSyncDeltaResult> syncNow({
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
      const MessageSyncDeltaResult(
        eventsApplied: 0,
        pagesFetched: 0,
        hasMore: false,
        snapshotRequired: false,
      ),
    );
  }
}

class _QueuedBlockingMessageSyncService extends FakeMessageSyncService {
  final List<Completer<MessageSyncDeltaResult>> _pending =
      <Completer<MessageSyncDeltaResult>>[];

  @override
  Future<MessageSyncDeltaResult> syncNow({
    required String reason,
    int limit = 100,
  }) {
    syncReasons.add(reason);
    final completer = Completer<MessageSyncDeltaResult>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext() {
    final completer = _pending.removeAt(0);
    completer.complete(
      const MessageSyncDeltaResult(
        eventsApplied: 0,
        pagesFetched: 1,
        hasMore: false,
        snapshotRequired: false,
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
  Future<MessageSyncDeltaResult> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    gateway.conversations = <ConversationSummary>[committed];
    return const MessageSyncDeltaResult(
      eventsApplied: 1,
      pagesFetched: 1,
      hasMore: false,
      snapshotRequired: false,
    );
  }
}

class _FailingMessageSyncService extends FakeMessageSyncService {
  @override
  Future<MessageSyncDeltaResult> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    throw StateError('sync_failed');
  }
}
