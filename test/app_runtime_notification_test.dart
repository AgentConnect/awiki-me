import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('AppRuntime notifications', () {
    late FakeAwikiGateway gateway;
    late FakeRealtimeGateway realtimeGateway;
    late FakeNotificationFacade notificationFacade;
    late ProviderContainer container;

    setUp(() {
      gateway = FakeAwikiGateway();
      realtimeGateway = FakeRealtimeGateway();
      notificationFacade = FakeNotificationFacade();
      gateway.myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
      gateway.conversations = const <ConversationSummary>[];
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> activate() async {
      await container
          .read(appRuntimeProvider.notifier)
          .activateSession(
            const SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              handle: 'me',
              jwtToken: 'token',
            ),
          );
    }

    RealtimeUpdate buildUpdate() {
      return RealtimeUpdate(
        message: ChatMessage(
          localId: 'remote-1',
          remoteId: 'remote-1',
          threadId: 'dm:1',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          receiverDid: 'did:test:me',
          content: 'hello',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation: ConversationSummary(
          threadId: 'dm:1',
          displayName: 'Peer',
          lastMessagePreview: 'hello',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:test:peer',
        ),
      );
    }

    test('前台收到消息时显示应用内提示', () async {
      gateway.nextRealtimeUpdate = buildUpdate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastInAppTitle, 'Peer');
      expect(notificationFacade.lastInAppBody, 'hello');
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('后台收到消息时触发系统通知', () async {
      gateway.nextRealtimeUpdate = buildUpdate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastSystemTitle, 'Peer');
      expect(notificationFacade.lastSystemBody, 'hello');
      expect(notificationFacade.lastInAppTitle, isNull);
    });

    test('后台系统通知标题使用发信人短昵称', () async {
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'remote-2',
          remoteId: 'remote-2',
          threadId: 'dm:2',
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          senderName: 'did:wba:awiki.ai:user:alice:e1_key',
          receiverDid: 'did:test:me',
          content: 'hello',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation: ConversationSummary(
          threadId: 'dm:2',
          displayName: 'did:wba:awiki.ai:user:alice:e1_key',
          lastMessagePreview: 'hello',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:wba:awiki.ai:user:alice:e1_key',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastSystemTitle, 'alice');
      expect(notificationFacade.lastSystemBody, 'hello');
    });

    test('实时 direct 与 group 消息会更新消息流和会话状态', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = buildUpdate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});

      var directThread = container.read(chatThreadProvider('dm:1'));
      expect(directThread.messages.single.content, 'hello');
      expect(
        container.read(conversationListProvider).conversations.single.threadId,
        'dm:1',
      );

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'group-remote-1',
          remoteId: 'group-remote-1',
          threadId: 'group:group-1',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          groupId: 'group-1',
          content: 'hello group',
          createdAt: DateTime(2026, 4, 5, 12, 5),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation: ConversationSummary(
          threadId: 'group:group-1',
          displayName: '融资协作群',
          lastMessagePreview: 'hello group',
          lastMessageAt: DateTime(2026, 4, 5, 12, 5),
          unreadCount: 1,
          isGroup: true,
          groupId: 'group-1',
        ),
        group: GroupSummary(
          groupId: 'group-1',
          name: '融资协作群',
          description: '',
          memberCount: 2,
          lastMessageAt: DateTime(2026, 4, 5, 12, 5),
          myRole: 'member',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'group'});

      final groupThread = container.read(chatThreadProvider('group:group-1'));
      expect(groupThread.messages.single.content, 'hello group');
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.threadId),
        contains('group:group-1'),
      );
      expect(container.read(groupProvider).groups.single.groupId, 'group-1');
      directThread = container.read(chatThreadProvider('dm:1'));
      expect(directThread.messages.single.content, 'hello');
    });
  });
}
