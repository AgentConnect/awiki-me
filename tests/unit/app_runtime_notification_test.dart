import 'dart:async';

import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
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
    late FakeMessageSyncService messageSyncService;
    late ProviderContainer container;

    setUp(() {
      gateway = FakeAwikiGateway();
      realtimeGateway = FakeRealtimeGateway();
      notificationFacade = FakeNotificationFacade();
      messageSyncService = FakeMessageSyncService();
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
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
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
        conversationHint: ConversationSummary(
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

    ConversationSummary staleSelectedConversation() {
      return ConversationSummary(
        threadId: 'group:old-group',
        displayName: '旧身份群聊',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 4, 5, 12),
        unreadCount: 0,
        isGroup: true,
        groupId: 'old-group',
      );
    }

    test('激活身份时清理上一身份的选中会话', () async {
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());

      await activate();

      expect(container.read(selectedConversationProvider), isNull);
    });

    test('退出登录时清理当前选中会话', () async {
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              handle: 'me',
              jwtToken: 'token',
            ),
          );
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());

      await container.read(appRuntimeProvider.notifier).logout();

      expect(container.read(selectedConversationProvider), isNull);
    });

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

    test('激活身份后后台调度 startup 可靠同步', () async {
      await activate();
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('startup'));
      expect(container.read(appRuntimeProvider).isBusy, isFalse);
    });

    test('恢复前台时调度 app_resumed 可靠同步', () async {
      await activate();
      messageSyncService.syncReasons.clear();

      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('app_resumed'));
    });

    test('恢复前台时不强制刷新已加载的智能体列表', () async {
      final agentControl = _CountingAgentControlService();
      final lifecycleContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          agentControlServiceProvider.overrideWithValue(agentControl),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(lifecycleContainer.dispose);

      await lifecycleContainer
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
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final callsAfterStartup = agentControl.listAgentsCalls;

      lifecycleContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      lifecycleContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(messageSyncService.syncReasons, contains('app_resumed'));
      expect(agentControl.listAgentsCalls, callsAfterStartup);
    });

    test('进入后台时裁剪隐藏会话缓存但保留可见会话', () async {
      final visibleConversation = ConversationSummary(
        threadId: 'dm:visible',
        displayName: 'Visible',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:visible',
      );
      final hiddenConversation = ConversationSummary(
        threadId: 'dm:hidden',
        displayName: 'Hidden',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:hidden',
      );
      final cacheContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          chatThreadsProvider.overrideWith(
            (ref) => ChatThreadsController(
              ref,
              cachePolicy: const ThreadMemoryCachePolicy(
                hotThreadMessageLimit: 10,
                warmThreadMessageLimit: 4,
                coldThreadMessageLimit: 1,
                maxTotalCachedMessages: 20,
                maxCachedCanonicalThreads: 20,
              ),
            ),
          ),
        ],
      );
      addTearDown(cacheContainer.dispose);
      final controller = cacheContainer.read(chatThreadsProvider.notifier);
      controller.markConversationVisible(visibleConversation);
      for (var i = 0; i < 4; i += 1) {
        controller.applyRealtimeUpdate(
          _runtimeTestMessage(visibleConversation, i),
        );
        controller.applyRealtimeUpdate(
          _runtimeTestMessage(hiddenConversation, i),
        );
      }

      cacheContainer.read(appRuntimeProvider);
      cacheContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      expect(
        cacheContainer
            .read(chatThreadProvider(visibleConversation.threadId))
            .messages,
        hasLength(4),
      );
      expect(
        cacheContainer
            .read(chatThreadProvider(hiddenConversation.threadId))
            .messages,
        hasLength(1),
      );
    });

    test('内存压力会回收隐藏会话缓存但保留可见会话', () {
      final visibleConversation = ConversationSummary(
        threadId: 'dm:memory-visible',
        displayName: 'Visible',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:memory-visible',
      );
      final hiddenConversation = ConversationSummary(
        threadId: 'dm:memory-hidden',
        displayName: 'Hidden',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:memory-hidden',
      );
      final cacheContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          chatThreadsProvider.overrideWith(
            (ref) => ChatThreadsController(
              ref,
              cachePolicy: const ThreadMemoryCachePolicy(
                hotThreadMessageLimit: 10,
                warmThreadMessageLimit: 4,
                coldThreadMessageLimit: 1,
                maxTotalCachedMessages: 20,
                maxCachedCanonicalThreads: 20,
              ),
            ),
          ),
        ],
      );
      addTearDown(cacheContainer.dispose);
      final controller = cacheContainer.read(chatThreadsProvider.notifier);
      controller.markConversationVisible(visibleConversation);
      for (var i = 0; i < 4; i += 1) {
        controller.applyRealtimeUpdate(
          _runtimeTestMessage(visibleConversation, i),
        );
        controller.applyRealtimeUpdate(
          _runtimeTestMessage(hiddenConversation, i),
        );
      }

      controller.trimForMemoryPressure();

      expect(
        cacheContainer
            .read(chatThreadProvider(visibleConversation.threadId))
            .messages,
        hasLength(4),
      );
      expect(
        cacheContainer
            .read(chatThreadProvider(hiddenConversation.threadId))
            .messages,
        isEmpty,
      );
      expect(controller.debugCacheStats().evictedThreadCount, 1);
    });

    test('realtime gap hint 只调度 delta，不直接改消息投影', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: buildUpdate().message,
        conversationHint: buildUpdate().conversationHint,
        syncDirty: true,
        gapDetected: true,
        syncEventSeq: '42',
        syncEventType: 'message.created',
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_gap'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
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
        conversationHint: ConversationSummary(
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

    test('激活身份先刷新本地会话列表，不等待 profile/agents/friends/groups', () async {
      final slowProfile = Completer<void>();
      gateway.myProfile = null;
      final conversations = _RecordingConversationService(<ConversationSummary>[
        buildUpdate().conversationHint!,
      ]);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
          ),
          conversationServiceProvider.overrideWithValue(conversations),
          profileApplicationServiceProvider.overrideWithValue(
            _BlockingProfileService(slowProfile),
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );

      await activate();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(conversations.fastCalls, 1);
      expect(conversations.enrichCalls, 1);
      expect(
        container.read(conversationListProvider).conversations.single.threadId,
        'dm:1',
      );
      slowProfile.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('恢复和重连短时间重复触发时复用同一次后台刷新', () async {
      final slowProfile = Completer<void>();
      final sync = FakeMessageSyncService();
      gateway.myProfile = null;
      final conversations = _RecordingConversationService(<ConversationSummary>[
        buildUpdate().conversationHint!,
      ]);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: sync,
          ),
          conversationServiceProvider.overrideWithValue(conversations),
          profileApplicationServiceProvider.overrideWithValue(
            _BlockingProfileService(slowProfile),
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );

      await activate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sync.syncReasons, contains('startup'));
      expect(sync.syncReasons, contains('app_resumed'));
      expect(conversations.fastCalls, 2);
      expect(conversations.enrichCalls, 2);
      slowProfile.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('实时附件消息通知使用附件预览', () async {
      container.read(appLocaleModeProvider.notifier).state =
          AppLocaleMode.zhHans;
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'remote-attachment',
          remoteId: 'remote-attachment',
          threadId: 'dm:attachment',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          receiverDid: 'did:test:me',
          content: '',
          originalType: 'application/anp-attachment-manifest+json',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
          attachment: const ChatAttachment(
            attachmentId: 'att-1',
            filename: 'report.pdf',
            mimeType: 'application/pdf',
          ),
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:attachment',
          displayName: 'Peer',
          lastMessagePreview: '[附件] report.pdf',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:test:peer',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastSystemTitle, 'Peer');
      expect(notificationFacade.lastSystemBody, '附件：report.pdf');
    });

    test('实时 direct 与 group 消息只调度 core sync，不直接写 list/timeline', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);
      messageSyncService.syncReasons.clear();

      gateway.nextRealtimeUpdate = buildUpdate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(notificationFacade.lastInAppTitle, 'Peer');
      expect(notificationFacade.lastInAppBody, 'hello');

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
        conversationHint: ConversationSummary(
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
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(
        container.read(chatThreadProvider('group:group-1')).messages,
        isEmpty,
      );
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(groupProvider).groups.single.groupId, 'group-1');
      expect(notificationFacade.lastInAppTitle, 'Peer');
      expect(notificationFacade.lastInAppBody, 'hello group');
    });

    test('实时消息更新最近会话但不会覆盖未读 @ 我状态', () async {
      final conversationService = _RecordingConversationService(
        const <ConversationSummary>[],
      );
      addTearDown(conversationService.dispose);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          conversationServiceProvider.overrideWithValue(conversationService),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
      await activate();
      await pumpEventQueue();

      final mentionedConversation = ConversationSummary(
        threadId: 'group:group-mention',
        displayName: '群聊',
        lastMessagePreview: '@me 请看',
        lastMessageAt: DateTime(2026, 4, 5, 12),
        unreadCount: 1,
        unreadMentionCount: 1,
        firstUnreadMentionMessageId: 'msg-mention-1',
        isGroup: true,
        groupId: 'group-mention',
      );
      conversationService.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:test:me',
          version: 1,
          unreadTotal: 1,
          item: mentionedConversation,
        ),
      );
      await pumpEventQueue();

      final afterMentionPatch = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(afterMentionPatch.unreadCount, 1);
      expect(afterMentionPatch.unreadMentionCount, 1);
      expect(afterMentionPatch.firstUnreadMentionMessageId, 'msg-mention-1');

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'msg-normal-2',
          remoteId: 'msg-normal-2',
          threadId: 'group:group-mention',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          groupId: 'group-mention',
          content: '普通消息',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'group:group-mention',
          displayName: '群聊',
          lastMessagePreview: '普通消息',
          lastMessageAt: DateTime(2026, 4, 5, 12, 1),
          unreadCount: 1,
          unreadMentionCount: 0,
          isGroup: true,
          groupId: 'group-mention',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      final afterRealtime = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(afterRealtime.lastMessagePreview, '@me 请看');
      expect(afterRealtime.unreadCount, 1);
      expect(afterRealtime.unreadMentionCount, 1);
      expect(afterRealtime.firstUnreadMentionMessageId, 'msg-mention-1');
      expect(
        container.read(chatThreadProvider('group:group-mention')).messages,
        isEmpty,
      );

      conversationService.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:test:me',
          version: 2,
          unreadTotal: 2,
          item: mentionedConversation.copyWith(
            lastMessagePreview: '普通消息',
            lastMessageAt: DateTime(2026, 4, 5, 12, 1),
            unreadCount: 2,
            unreadMentionCount: 1,
            firstUnreadMentionMessageId: 'msg-mention-1',
          ),
        ),
      );
      await pumpEventQueue();

      final afterPatch = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(afterPatch.lastMessagePreview, '普通消息');
      expect(afterPatch.unreadCount, 2);
      expect(afterPatch.unreadMentionCount, 1);
      expect(afterPatch.firstUnreadMentionMessageId, 'msg-mention-1');
    });

    test('实时 direct peer-scoped 消息只调度 core sync，不预热 alias', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      final conversation = ConversationSummary(
        threadId: 'direct-handle:alice.awiki.info',
        displayName: 'Alice',
        lastMessagePreview: 'hello alias',
        lastMessageAt: DateTime(2026, 4, 5, 12, 10),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:alice',
        targetPeer: 'alice.awiki.info',
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'alias-direct-1',
          remoteId: 'alias-direct-1',
          threadId: 'dm:peer-scope:v1:alice',
          senderDid: 'did:test:alice',
          senderName: 'Alice',
          receiverDid: 'did:test:me',
          content: 'hello alias',
          createdAt: DateTime(2026, 4, 5, 12, 10),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: conversation,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      for (final key in <String>[
        'dm:peer-scope:v1:alice',
        'direct-handle:alice.awiki.info',
        'did:test:alice',
        'direct:did:test:alice',
        'direct-did:did:test:alice',
        'direct:alice.awiki.info',
        'direct-handle:alice',
        'dm:pending:alice.awiki.info',
        'dm:did:test:alice:did:test:me',
      ]) {
        expect(
          container.read(chatThreadProvider(key)).messages,
          isEmpty,
          reason: 'realtime payload must not prewarm $key directly',
        );
      }

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'alias-direct-1',
          remoteId: 'alias-direct-1',
          threadId: 'dm:peer-scope:v1:alice',
          senderDid: 'did:test:alice',
          senderName: 'Alice',
          receiverDid: 'did:test:me',
          content: 'hello alias',
          createdAt: DateTime(2026, 4, 5, 12, 10),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: conversation,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});
      await pumpEventQueue();

      expect(
        container.read(chatThreadProvider('dm:peer-scope:v1:alice')).messages,
        isEmpty,
      );
      expect(
        container
            .read(chatThreadProvider('direct-handle:alice.awiki.info'))
            .messages,
        isEmpty,
      );
    });

    test('实时 group 消息只调度 core sync，不预热 canonical 或 alias thread', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'alias-group-1',
          remoteId: 'alias-group-1',
          threadId: 'sdk-group-thread-alpha',
          senderDid: 'did:test:alice',
          senderName: 'Alice',
          groupId: 'did:test:group:alpha',
          content: 'hello group alias',
          createdAt: DateTime(2026, 4, 5, 12, 15),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'group:did:test:group:alpha',
          displayName: 'Alpha',
          lastMessagePreview: 'hello group alias',
          lastMessageAt: DateTime(2026, 4, 5, 12, 15),
          unreadCount: 1,
          isGroup: true,
          groupId: 'did:test:group:alpha',
        ),
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
      await pumpEventQueue();

      for (final key in <String>[
        'group:did:test:group:alpha',
        'sdk-group-thread-alpha',
      ]) {
        expect(
          container.read(chatThreadProvider(key)).messages,
          isEmpty,
          reason: 'realtime payload must not prewarm $key directly',
        );
      }
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(
        container.read(chatThreadProvider('did:test:group:alpha')).messages,
        isEmpty,
      );
    });

    test('Daemon Agent 普通实时消息不进入聊天、未读或通知', () async {
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
              'runtime': 'hermes',
              'status': 'ready',
            },
          ],
        },
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'daemon-normal',
          remoteId: 'daemon-normal',
          threadId: 'dm:daemon',
          senderDid: 'did:agent:daemon',
          senderName: '代理 1',
          receiverDid: 'did:test:me',
          content: 'control-plane text should be hidden',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:daemon',
          displayName: '代理 1',
          lastMessagePreview: 'control-plane text should be hidden',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:daemon',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(container.read(chatThreadProvider('dm:daemon')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(conversationListProvider).unreadCount, 0);
      expect(notificationFacade.lastBadgeCount, 0);
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('Runtime Agent 普通实时消息只触发通知和 core sync', () async {
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
              'runtime': 'hermes',
              'status': 'ready',
            },
          ],
        },
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'runtime-normal',
          remoteId: 'runtime-normal',
          threadId: 'dm:runtime',
          senderDid: 'did:agent:runtime',
          senderName: 'Hermes',
          receiverDid: 'did:test:me',
          content: 'Hermes reply',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:runtime',
          displayName: 'Hermes',
          lastMessagePreview: 'Hermes reply',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:runtime',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      messageSyncService.syncReasons.clear();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(
        container.read(chatThreadProvider('dm:runtime')).messages,
        isEmpty,
      );
      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, isEmpty);
      expect(container.read(conversationListProvider).unreadCount, 0);
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(notificationFacade.lastInAppTitle, 'Hermes');
      expect(notificationFacade.lastInAppBody, 'Hermes reply');
    });

    test('实时 Agent hint 不覆盖现有会话，只调度 core sync', () async {
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
              'agent_did': 'did:agent:runtime:hermes',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'handle': 'hermes',
              'display_name': 'Hermes',
              'status': 'ready',
            },
          ],
        },
      );
      final pendingAlias = ConversationSummary(
        threadId: 'dm:pending:hermes.awiki.info',
        displayName: 'Hermes',
        lastMessagePreview: '在吗？',
        lastMessageAt: DateTime(2026, 7, 3, 12, 0),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:agent:runtime:hermes',
        targetPeer: 'hermes.awiki.info',
      );
      container
          .read(conversationListProvider.notifier)
          .upsertConversation(pendingAlias);
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'runtime-normalized',
          remoteId: 'runtime-normalized',
          threadId: 'dm:peer-scope:v1:hermes-runtime',
          senderDid: 'did:agent:runtime:hermes',
          senderName: 'Hermes',
          receiverDid: 'did:test:me',
          content: '在的',
          createdAt: DateTime(2026, 7, 3, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:peer-scope:v1:hermes-runtime',
          displayName: 'hermes',
          lastMessagePreview: '在的',
          lastMessageAt: DateTime(2026, 7, 3, 12, 1),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'hermes',
          targetPeer: 'hermes',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      messageSyncService.syncReasons.clear();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, pendingAlias.threadId);
      expect(conversations.single.targetDid, 'did:agent:runtime:hermes');
      expect(conversations.single.targetPeer, 'hermes.awiki.info');
      expect(conversations.single.lastMessagePreview, '在吗？');
      expect(
        container
            .read(chatThreadProvider('dm:peer-scope:v1:hermes-runtime'))
            .messages,
        isEmpty,
      );
      expect(
        container.read(chatThreadProvider(pendingAlias.threadId)).messages,
        isEmpty,
      );
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(notificationFacade.lastInAppTitle, 'Hermes');
    });

    test('实时消息的过期 conversation hint 不会污染最近会话', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: ChatMessage(
          localId: 'runtime-stale-hint',
          remoteId: 'runtime-stale-hint',
          threadId: 'dm:peer-scope:v1:runtime',
          senderDid: 'did:agent:runtime',
          senderName: 'Hermes',
          receiverDid: 'did:test:me',
          content: 'runtime reply',
          createdAt: DateTime(2026, 4, 5, 12, 2),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:human',
          displayName: 'zhuocheng',
          lastMessagePreview: 'runtime reply',
          lastMessageAt: DateTime(2026, 4, 5, 12, 2),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:human:zhuocheng',
        ),
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(
        container.read(chatThreadProvider('dm:peer-scope:v1:runtime')).messages,
        isEmpty,
      );
      expect(container.read(chatThreadProvider('dm:human')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(conversationListProvider).unreadCount, 0);
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(notificationFacade.lastInAppTitle, 'Hermes');
    });

    test('实时控制状态只更新智能体状态', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        agentControlPayload: <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'daemon',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
            'version': '0.2.0',
            'platform': 'darwin-arm64',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'needs_config',
            },
          ],
        },
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'status'});

      final agents = container.read(agentsProvider).agents;
      final daemon = agents.singleWhere((agent) => agent.isDaemon);
      final runtime = agents.singleWhere((agent) => agent.isRuntime);
      expect(daemon.agentDid, 'did:agent:daemon');
      expect(daemon.latest.status, 'ready');
      expect(daemon.latest.version, '0.2.0');
      expect(runtime.agentDid, 'did:agent:runtime');
      expect(runtime.kind, AgentKind.runtime);
      expect(runtime.daemonAgentDid, 'did:agent:daemon');
      expect(runtime.latest.status, 'needs_config');
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(
        container.read(chatThreadProvider('did:agent:daemon')).messages,
        isEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('实时可见控制状态不进入最近会话、消息或通知', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        agentControlPayload: const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'runtime',
          'runtime_agent_did': 'did:agent:runtime',
          'runtime': <String, Object?>{
            'agent_did': 'did:agent:runtime',
            'status': 'ready',
          },
        },
        conversation: ConversationSummary(
          threadId: 'dm:runtime',
          displayName: 'Hermes',
          lastMessagePreview: 'Agent 已准备好。',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:runtime',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'status'});

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, isEmpty);
      expect(
        container.read(chatThreadProvider('dm:runtime')).messages,
        isEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('实时 Message Agent 控制 payload 回收到 chat provider', () async {
      final conversation = ConversationSummary(
        threadId: 'direct:did:human:bob',
        displayName: 'Bob',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 6, 19, 10, 0),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:human:bob',
      );
      container
          .read(conversationListProvider.notifier)
          .upsertConversation(conversation);
      container
          .read(chatThreadsProvider.notifier)
          .applyRealtimeUpdate(
            ChatMessage(
              localId: 'msg_1',
              remoteId: 'msg_1',
              threadId: conversation.threadId,
              senderDid: 'did:human:bob',
              receiverDid: 'did:test:me',
              content: 'hello',
              createdAt: DateTime(2026, 6, 19, 10, 0),
              isMine: false,
              sendState: MessageSendState.sent,
            ),
          );
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
            'display_name': 'Message Daemon',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'ready',
              'display_name': 'Hermes Message Agent',
            },
          ],
        },
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        agentControlPayload: <String, Object?>{
          'schema': 'awiki.app.action.v1',
          'action_id': 'act_draft',
          'action': 'message.create_draft',
          'state': 'requires_confirmation',
          'runtime_agent_did': 'did:agent:runtime',
          'run_id': 'run_1',
          'source_message_id': 'msg_1',
          'conversation_id': 'direct:did:human:bob',
          'requires_confirmation': true,
          'args': <String, Object?>{'draft_text': '收到，我会处理。'},
        },
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'control'});

      final action = container
          .read(chatThreadProvider(conversation.threadId))
          .appActionRecords['act_draft'];
      expect(action, isNotNull);
      expect(action!.state, 'requires_confirmation');
      expect(action.request?.args['draft_text'], '收到，我会处理。');
      expect(
        container.read(conversationListProvider).conversations,
        isNotEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('实时连接失败时刷新会话数据但不使用相同 token 循环重连', () async {
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              handle: 'me',
              jwtToken: 'token',
            ),
          );
      container.read(appRuntimeProvider);

      realtimeGateway.setStatus(RealtimeConnectionStatus.failed);
      await pumpEventQueue();

      expect(gateway.refreshSessionCalls, 1);
      expect(gateway.listConversationsCalls, 1);
      expect(realtimeGateway.connectionStatus, RealtimeConnectionStatus.failed);
    });
  });
}

class _RecordingConversationService implements ConversationService {
  _RecordingConversationService(this.items);

  final List<ConversationSummary> items;
  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);
  int fastCalls = 0;
  int enrichCalls = 0;
  int listCalls = 0;

  void emitPatch(ConversationListPatch patch) {
    _patches.add(patch);
  }

  Future<void> dispose() {
    return _patches.close();
  }

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    return const <ConversationSummary>[];
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return _patches.stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(conversations: items, version: 1);
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return items;
  }

  @override
  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversationSummariesFast(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    enrichCalls += 1;
    return conversations;
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    listCalls += 1;
    return items;
  }

  @override
  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversations(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}
}

class _BlockingProfileService implements ProfileApplicationService {
  _BlockingProfileService(this.completer);

  final Completer<void> completer;

  @override
  Future<UserProfile> loadMyProfile() async {
    await completer.future;
    return const UserProfile(
      did: 'did:test:me',
      nickName: 'Me',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'me',
    );
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

class _CountingAgentControlService extends FakeAgentControlService {
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listAgentsCalls += 1;
    return super.listAgents(includeInactive: includeInactive);
  }
}

ChatMessage _runtimeTestMessage(ConversationSummary conversation, int index) {
  return ChatMessage(
    localId: '${conversation.threadId}:local:$index',
    remoteId: '${conversation.threadId}:remote:$index',
    threadId: conversation.threadId,
    senderDid: conversation.targetDid ?? 'did:test:peer',
    receiverDid: 'did:test:me',
    content: 'message $index',
    createdAt: DateTime(2026, 6, 29, 10, index),
    isMine: false,
    sendState: MessageSendState.sent,
  );
}
