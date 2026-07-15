import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

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
}

ProviderContainer _container(
  FakeAwikiGateway gateway,
  FakeMessageSyncService sync, {
  Duration minInterval = Duration.zero,
}) {
  return ProviderContainer(
    overrides: <Override>[
      awikiGatewayProvider.overrideWithValue(gateway),
      notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
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
