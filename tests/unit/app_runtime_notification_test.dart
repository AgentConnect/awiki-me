import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
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

    test('realtime gap hint 只调度 delta 不改变低延迟投影', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        message: buildUpdate().message,
        conversation: buildUpdate().conversation,
        syncDirty: true,
        gapDetected: true,
        syncEventSeq: '42',
        syncEventType: 'message.created',
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_gap'));
      expect(
        container.read(chatThreadProvider('dm:1')).messages.single.content,
        'hello',
      );
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

    test('激活身份先刷新本地会话列表，不等待 profile/agents/friends/groups', () async {
      final slowProfile = Completer<void>();
      gateway.myProfile = null;
      final conversations = _RecordingConversationService(<ConversationSummary>[
        buildUpdate().conversation!,
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
        buildUpdate().conversation!,
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
        conversation: ConversationSummary(
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
      expect(notificationFacade.lastSystemBody, '[附件] report.pdf');
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
        conversation: ConversationSummary(
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

    test('Runtime Agent 普通实时消息仍进入聊天、未读和通知', () async {
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
        conversation: ConversationSummary(
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
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(
        container
            .read(chatThreadProvider('dm:runtime'))
            .messages
            .single
            .content,
        'Hermes reply',
      );
      expect(
        container.read(conversationListProvider).conversations.single.targetDid,
        'did:agent:runtime',
      );
      expect(container.read(conversationListProvider).unreadCount, 1);
      expect(notificationFacade.lastBadgeCount, 1);
      expect(notificationFacade.lastInAppTitle, 'Hermes');
      expect(notificationFacade.lastInAppBody, 'Hermes reply');
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
  int fastCalls = 0;
  int enrichCalls = 0;
  int listCalls = 0;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    return const <ConversationSummary>[];
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
  Future<void> markThreadRead(AppThreadRef thread) async {}

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
