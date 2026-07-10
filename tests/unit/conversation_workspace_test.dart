// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_agent_identity.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/agents/agent_status_indicator.dart';
import 'package:awiki_me/src/presentation/agents/agent_visual_status.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> items,
  ) {
    state = ConversationListState(conversations: items);
  }

  void replaceConversations(List<ConversationSummary> conversations) {
    state = ConversationListState(conversations: conversations);
    final selected = ref.read(selectedConversationProvider);
    if (selected == null) {
      return;
    }
    final selectedConversationId = selected.effectiveConversationId.trim();
    final selectedThreadId = selected.threadId.trim();
    for (final conversation in conversations) {
      if ((selectedConversationId.isNotEmpty &&
              conversation.effectiveConversationId.trim() ==
                  selectedConversationId) ||
          (selectedThreadId.isNotEmpty &&
              conversation.threadId.trim() == selectedThreadId)) {
        ref
            .read(selectedConversationProvider.notifier)
            .selectConversation(conversation);
        return;
      }
    }
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshFastLocal() async {}

  @override
  Future<void> restoreConversation(ConversationSummary conversation) async {}
}

class _BlockingRestoreConversationListController
    extends _StaticConversationListController {
  _BlockingRestoreConversationListController(
    super.ref,
    super.items, {
    required this.restoreStarted,
    required this.restoreCompleter,
  });

  final Completer<void> restoreStarted;
  final Completer<void> restoreCompleter;

  @override
  Future<void> restoreConversation(ConversationSummary conversation) {
    if (!restoreStarted.isCompleted) {
      restoreStarted.complete();
    }
    return restoreCompleter.future;
  }
}

void main() {
  final conversation = ConversationSummary(
    threadId: 'dm:did:me:did:peer',
    displayName: 'Marcus Chen',
    lastMessagePreview: 'Hey! I just saw the updates.',
    lastMessageAt: DateTime(2026, 3, 28, 10, 24),
    unreadCount: 3,
    isGroup: false,
    targetDid: 'did:peer',
  );

  final history = <ChatMessage>[
    ChatMessage(
      localId: '1',
      threadId: 'dm:did:me:did:peer',
      senderDid: 'did:peer',
      senderName: 'Marcus Chen',
      content: 'Hey! I just saw the updates.',
      createdAt: DateTime(2026, 3, 28, 10, 24),
      isMine: false,
      sendState: MessageSendState.sent,
    ),
  ];

  testWidgets('最近会话显示未读 @ 我提示', (tester) async {
    final mentionConversation = ConversationSummary(
      threadId: 'group:did:group:mentions',
      displayName: '项目群',
      lastMessagePreview: '@Marcus 请看这里',
      lastMessageAt: DateTime(2026, 3, 28, 10, 30),
      unreadCount: 2,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'msg-mention-1',
      isGroup: true,
      groupId: 'did:group:mentions',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[mentionConversation];
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('项目群'), findsOneWidget);
    expect(find.text('未读 2'), findsOneWidget);
    expect(find.text('@我'), findsOneWidget);
  });

  testWidgets('macOS 宽度下聊天头部不显示身份卡或会话信息入口', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近会话'), findsOneWidget);
    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('安全协作中'), findsOneWidget);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.text('群聊信息'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('macOS 最近会话点击不等待恢复最近列表完成', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    final restoreStarted = Completer<void>();
    final restoreCompleter = Completer<void>();
    addTearDown(() {
      if (!restoreCompleter.isCompleted) {
        restoreCompleter.complete();
      }
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _BlockingRestoreConversationListController(
              ref,
              gateway.conversations,
              restoreStarted: restoreStarted,
              restoreCompleter: restoreCompleter,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pump();

    expect(restoreStarted.isCompleted, isTrue);
    expect(find.byType(ChatView), findsOneWidget);

    restoreCompleter.complete();
    await tester.pump();

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Runtime Agent 会话在非 Mac 聊天页显示收件箱入口并打开全屏页', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'token',
    );
    final runtimeConversation = ConversationSummary(
      threadId: 'dm:did:me:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[runtimeConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      }
      ..publicProfilesByQuery = const <String, UserProfile>{
        'did:agent:runtime': UserProfile(
          did: 'did:agent:runtime',
          nickName: 'Hermes',
          bio: 'Runtime Agent',
          tags: <String>['agent'],
          profileMarkdown: 'Hermes profile',
        ),
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ChatPage(conversation: runtimeConversation),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('Agent 收件箱'), findsNothing);
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();

    expect(find.text('智能体信息'), findsOneWidget);
    await tester.tap(find.text('Agent 收件箱'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Agent 收件箱'), findsOneWidget);
    expect(find.text('Hermes'), findsWidgets);
    expect(control.lastInboxDaemonDid, 'did:agent:daemon');
    expect(control.lastInboxRuntimeDid, 'did:agent:runtime');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话只给真实智能体显示 AI 标记且无会话信息入口', (tester) async {
    final humanConversation = ConversationSummary(
      conversationId: 'dm:did:test:human',
      threadId: 'dm:human',
      displayName: '普通用户',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 3, 28, 10, 24),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:human',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:test:agent',
      threadId: 'dm:agent',
      displayName: '远端智能体',
      lastMessagePreview: 'ready',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:agent',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        humanConversation,
        agentConversation,
      ]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:test:human': <ChatMessage>[],
        'did:test:agent': <ChatMessage>[],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:test:agent': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI'), findsOneWidget);

    await tester.tap(find.text('普通用户'));
    await tester.pumpAndSettle();
    expect(find.text('用户'), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    await tester.tap(find.text('远端智能体'));
    await tester.pumpAndSettle();
    expect(find.text('智能体'), findsWidgets);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('macOS 最近会话为正在处理的本地智能体显示状态圆点', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final initialDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(initialDot.status.kind, AgentVisualStatusKind.ready);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: agentConversation,
          content: '请处理',
          expectedAgentReplyDid: 'did:agent:runtime',
        );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('最近会话会主动加载本地智能体状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:agent:runtime': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final dot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(dot.status.kind, AgentVisualStatusKind.ready);
    expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话同步显示群聊触发的本地智能体处理中状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final groupConversation = ConversationSummary(
      conversationId: 'group:did:group:agent-room',
      threadId: 'group:did:group:agent-room',
      displayName: 'Agent 群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10, 1),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:group:agent-room',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        agentConversation,
        groupConversation,
      ]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      }
      ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
        'did:group:agent-room': <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:agent:runtime',
            did: 'did:agent:runtime',
            handle: 'hermes',
            role: 'member',
            displayName: 'Hermes',
            subjectType: GroupMemberSubjectType.agent,
          ),
        ],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final initialDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(initialDot.status.kind, AgentVisualStatusKind.ready);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: groupConversation,
          content: '@hermes 请处理',
          mentions: const <ChatMentionDraft>[
            ChatMentionDraft(
              localId: 'men_agent',
              surface: '@hermes',
              start: 0,
              end: 7,
              target: ChatMentionTargetDraft.member(
                kind: ChatMentionTargetKind.agent,
                did: 'did:agent:runtime',
                handle: 'hermes',
                displayName: 'Hermes',
              ),
            ),
          ],
        );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);
    final pendingTurn = container
        .read(chatThreadsProvider)[groupConversation.threadId]!
        .agentPendingTurns
        .single;

    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': groupConversation.threadId,
        'task_id': 'task_group_mention',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_group_mention',
            'message_id': 'task_group_mention',
            'source_message_id': pendingTurn.remoteMessageId,
            'mention_id': 'men_agent',
            'runtime_agent_did': 'did:agent:runtime',
            'conversation_id': groupConversation.threadId,
            'status': 'failed',
            'updated_at': DateTime(2026, 6, 4, 10, 2).toIso8601String(),
            'last_error_code': 'agent_invocation_denied',
          },
        ],
      },
    );
    await tester.pump(const Duration(milliseconds: 50));

    final settledDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(settledDot.status.kind, AgentVisualStatusKind.ready);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话用 Controller activity 显示本地智能体处理中状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final initialDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(initialDot.status.kind, AgentVisualStatusKind.ready);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_activity',
        'daemon_agent_did': 'did:agent:daemon',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_external_activity',
            'runtime_agent_did': 'did:agent:runtime',
            'requester_did': 'did:human:bob',
            'trigger_kind': 'external_direct',
            'status': 'running',
            'updated_at': DateTime(2026, 6, 4, 10, 2).toIso8601String(),
          },
        ],
      },
    );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);
    final thread = container.read(
      chatThreadProvider(agentConversation.threadId),
    );
    expect(thread.agentPendingTurns, isEmpty);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话用运行状态显示远端智能体处理中状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      threadId: 'dm:did:agent:remote-runtime',
      displayName: 'Remote Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:remote-runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:remote-runtime': <ChatMessage>[],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:agent:remote-runtime': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentStatusDot), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': 'direct:did:human:me',
        'task_id': 'task_external_direct',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_external_direct',
            'message_id': 'task_external_direct',
            'source_message_id': 'msg_external_direct',
            'runtime_agent_did': 'did:agent:remote-runtime',
            'conversation_id': 'direct:did:human:me',
            'status': 'running',
          },
        ],
      },
    );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话保留已删除智能体并显示状态', (tester) async {
    final deletedConversation = ConversationSummary(
      threadId: 'dm:deleted-agent',
      displayName: '旧智能体',
      lastMessagePreview: '旧回复',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:deleted-agent',
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[deletedConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:test:deleted-agent': <ChatMessage>[],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('旧智能体'), findsOneWidget);
    expect(find.text('智能体已删除'), findsOneWidget);

    await tester.tap(find.text('旧智能体'));
    await tester.pumpAndSettle();

    expect(find.text('智能体已删除，无法继续发送消息'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('手机宽度下已删除智能体状态显示在名称旁边', (tester) async {
    final deletedConversation = ConversationSummary(
      threadId: 'dm:deleted-agent-mobile',
      displayName: '旧智能体',
      lastMessagePreview: '旧回复',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:deleted-agent-mobile',
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[deletedConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:test:deleted-agent-mobile': <ChatMessage>[],
      };
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('旧智能体'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('智能体已删除'), findsOneWidget);

    await tester.tap(find.text('旧智能体'));
    await tester.pumpAndSettle();

    expect(find.text('智能体已删除'), findsOneWidget);
    expect(find.text('智能体已删除，无法继续发送消息'), findsOneWidget);
  });

  testWidgets('macOS 聊天头部移除身份卡按钮但头像仍可打开用户信息弹窗', (tester) async {
    const peerProfile = UserProfile(
      did: 'did:peer',
      nickName: 'Marcus Chen',
      bio: '融资协作 Agent',
      tags: <String>['Agent'],
      profileMarkdown: '# Marcus\n\n负责融资协作。',
      handle: 'marcus',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history}
      ..publicProfilesByQuery = <String, UserProfile>{'did:peer': peerProfile};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    await tester.tap(find.text('Marcus Chen').last);
    await tester.pumpAndSettle();

    expect(find.text('用户信息'), findsOneWidget);
    expect(find.text('负责融资协作。'), findsOneWidget);
    expect(find.text('@marcus'), findsOneWidget);
    expect(find.byKey(const Key('peer-info-dialog-did-value')), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('关闭信息弹窗'));
    await tester.pumpAndSettle();
    expect(find.text('用户信息'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('macOS 群聊头像打开统一信息弹窗且头部不显示入口', (tester) async {
    const groupId = 'did:test:group:funding';
    final group = GroupSummary(
      groupId: groupId,
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
          GroupMemberSummary(
            userId: 'did:test:member',
            did: 'did:test:member',
            handle: 'member.awiki',
            role: 'member',
          ),
        ],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('群聊信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.byType(GroupDetailPage), findsNothing);

    await tester.tap(find.text('融资协作群').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('群聊信息'), findsWidgets);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('2 人'), findsOneWidget);
    expect(find.text('owner'), findsWidgets);
    expect(
      find.byKey(const Key('group-info-dialog-did-value')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('group-info-dialog-refresh-members-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('group-info-dialog-add-member-button')),
      findsOneWidget,
    );
    expect(find.text('owner.awiki'), findsOneWidget);
    expect(find.text('member.awiki'), findsOneWidget);
    expect(find.text('did:test:owner'), findsNothing);
    expect(find.text('did:test:member'), findsNothing);
    expect(find.byType(GroupDetailPage), findsNothing);

    await tester.tap(find.bySemanticsLabel('关闭信息弹窗'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);

    const memberHandle = 'bob.awiki.ai';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    gateway.publicProfilesByQuery = const <String, UserProfile>{
      memberHandle: UserProfile(
        did: memberDid,
        nickName: 'Bob',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: memberHandle,
        fullHandle: memberHandle,
      ),
    };
    await tester.tap(
      find.byKey(const Key('group-info-dialog-add-member-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加群成员'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      memberHandle,
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, group.groupId);
    expect(gateway.lastAddedMemberRef, memberDid);
    expect(find.text(memberHandle), findsOneWidget);
    expect(find.text(memberDid), findsNothing);
    expect(find.text('3 人'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('移除成员').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除成员').last);
    await tester.pumpAndSettle();

    expect(gateway.lastRemovedGroupId, group.groupId);
    expect(gateway.lastRemovedMemberRef, memberDid);
    expect(find.text(memberHandle), findsNothing);
    expect(find.text('2 人'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊信息保留完整群权限避免按钮抖动', (tester) async {
    const groupId = 'did:test:group:funding';
    final fullGroup = GroupSummary(
      groupId: groupId,
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[fullGroup]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
          GroupMemberSummary(
            userId: 'did:test:member',
            did: 'did:test:member',
            handle: 'member.awiki',
            role: 'member',
          ),
        ],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('group-info-dialog-add-member-button')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('移除成员'), findsWidgets);

    gateway.groups = <GroupSummary>[
      GroupSummary(
        groupId: groupId,
        name: groupId,
        description: '',
        memberCount: 0,
        lastMessageAt: DateTime(2026, 3, 28, 10, 26),
      ),
    ];
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await container.read(groupProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('群聊信息'), findsWidgets);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('owner'), findsWidgets);
    expect(
      find.byKey(const Key('group-info-dialog-add-member-button')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('移除成员').last);
    await tester.pumpAndSettle();

    expect(find.text('移除成员'), findsNWidgets(2));

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 右侧栏空间不足时聊天头部仍不显示信息入口', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(900, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiDisplayScaleScope(
          scale: 1.12,
          child: ConversationWorkspacePage(),
        ),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen').first);
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 右侧栏空间不足时群聊头像打开统一信息弹窗', (tester) async {
    const groupId = 'did:test:group:funding';
    final group = GroupSummary(
      groupId: groupId,
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
        ],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(900, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiDisplayScaleScope(
          scale: 1.12,
          child: ConversationWorkspacePage(),
        ),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsNothing);
    expect(find.text('群聊信息'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsNothing);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('群聊信息'), findsWidgets);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('owner.awiki'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('关闭信息弹窗'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('同步融资材料和里程碑'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊成员刷新不受群详情空响应影响', (tester) async {
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupConversation.groupId!,
          name: '融资协作群',
          description: '同步融资材料和里程碑',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 3, 28, 10, 25),
          myRole: 'owner',
        ),
      ]
      ..getGroupError = StateError(
        'IM Core group response did not include a group.',
      );
    UiFeedbackEvent? feedback;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Consumer(
          builder: (context, ref, child) {
            feedback = ref.watch(uiFeedbackProvider);
            return const ConversationWorkspacePage();
          },
        ),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('暂无成员快照，先执行一次刷新群详情与成员。'), findsOneWidget);

    gateway.groupMembersByGroupId = <String, List<GroupMemberSummary>>{
      groupConversation.groupId!: const <GroupMemberSummary>[
        GroupMemberSummary(
          userId: 'did:test:late-member',
          did: 'did:test:late-member',
          handle: 'late-member.awiki',
          role: 'late-role-hidden',
        ),
      ],
    };

    await tester.tap(
      find.byKey(const Key('group-info-dialog-refresh-members-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(feedback, isNull);
    expect(find.text('late-member.awiki'), findsOneWidget);
    expect(find.text('did:test:late-member'), findsNothing);
    expect(find.text('late-role-hidden'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊成员刷新期间显示按钮级 loading', (tester) async {
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final group = GroupSummary(
      groupId: groupConversation.groupId!,
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 1,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
    );
    final memberRefresh = Completer<void>();
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        group.groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
        ],
      };
    addTearDown(() {
      if (!memberRefresh.isCompleted) {
        memberRefresh.complete();
      }
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();

    gateway.listGroupMembersCompleter = memberRefresh;
    await tester.tap(
      find.byKey(const Key('group-info-dialog-refresh-members-button')),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('group-info-dialog-refresh-members-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsOneWidget,
    );

    memberRefresh.complete();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('group-info-dialog-refresh-members-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 会话信息头部按钮已移除', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('macOS 主导航点击会切换模块并保持图标可点', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      nickName: 'Mia',
      bio: 'Product lead',
      tags: <String>['agent'],
      profileMarkdown: '',
      handle: 'mia',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        profile: profile,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AW'), findsNothing);
    expect(find.text('Me'), findsNothing);
    final railAvatar = find.byKey(const Key('mac-me-rail-avatar'));
    expect(
      find.descendant(of: railAvatar, matching: find.byType(AvatarBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: railAvatar, matching: find.text('M')),
      findsOneWidget,
    );
    expect(find.text('最近会话'), findsOneWidget);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('Agents'), findsNothing);
    expect(find.byKey(const Key('mac-messages-unread-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('mac-messages-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    final conversationRow = find.byKey(
      Key('conversation-row:${conversation.effectiveConversationId}'),
    );
    expect(conversationRow, findsOneWidget);
    expect(
      find.descendant(
        of: conversationRow,
        matching: find.byKey(const Key('conversation-preview-tag-unread')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务视图即将接入'), findsOneWidget);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    expect(find.text('朋友'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mac-me-rail-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('我'), findsOneWidget);

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.back), findsNothing);
    expect(find.byKey(const Key('mac-desktop-rail-slot')), findsOneWidget);
    final settingsPaneSize = tester.getSize(
      find.byKey(const Key('mac-settings-list-pane')),
    );
    expect(settingsPaneSize.width, closeTo(420, 0.1));
    expect(settingsPaneSize.width, lessThan(1280 - 72));

    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();
    expect(find.text('最近会话'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航智能体标签跟随语言', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('Agents'), findsNothing);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        locale: const Locale('en'),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('智能体'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航未选中项统一为空心轻量样式', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final inactiveIcons = <IconData>[
      CupertinoIcons.sparkles,
      CupertinoIcons.person_2,
      CupertinoIcons.checkmark_square,
      CupertinoIcons.square_grid_2x2,
      CupertinoIcons.gear_alt,
    ];
    for (final iconData in inactiveIcons) {
      final icon = tester.widget<Icon>(find.byIcon(iconData));
      expect(icon.color, const Color(0xFF7A879C));
      expect(icon.weight, 400);
    }
    expect(find.byIcon(CupertinoIcons.person_2_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.checkmark_square_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.square_grid_2x2_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.gear_alt_fill), findsNothing);

    final activeMessageIcon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.chat_bubble_2_fill),
    );
    expect(activeMessageIcon.color, const Color(0xFF0B65F8));
    expect(activeMessageIcon.weight, 700);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();

    final inactiveMessageIcon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.chat_bubble_2),
    );
    final activeContactsIcon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.person_2_fill),
    );
    expect(inactiveMessageIcon.color, const Color(0xFF7A879C));
    expect(inactiveMessageIcon.weight, 400);
    expect(activeContactsIcon.color, const Color(0xFF0B65F8));
    expect(activeContactsIcon.weight, 700);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航头像缺少身份文本时回退到 Me', (tester) async {
    const session = SessionIdentity(
      did: '',
      credentialName: 'empty.json',
      displayName: '',
      jwtToken: 'token',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const AppShell(), session: session),
    );
    await tester.pumpAndSettle();

    final railAvatar = find.byKey(const Key('mac-me-rail-avatar'));
    expect(
      find.descendant(of: railAvatar, matching: find.text('Me')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: railAvatar, matching: find.text('M')),
      findsNothing,
    );
    expect(
      find.descendant(of: railAvatar, matching: find.text('?')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航和消息工作区跟随显示缩放', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiDisplayScaleScope(scale: 1.12, child: AppShell()),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('mac-desktop-rail-slot'))).width,
      greaterThan(72),
    );
    expect(
      tester.getSize(find.byKey(const Key('mac-conversation-list-pane'))).width,
      greaterThan(340),
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航无未读时不显示消息角标', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final readConversation = ConversationSummary(
      threadId: 'dm:read',
      displayName: 'Read Chat',
      lastMessagePreview: 'read',
      lastMessageAt: DateTime(2026, 3, 28, 10, 24),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:read',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    final readOnlyGateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[readConversation];
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: readOnlyGateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(
              ref,
              <ConversationSummary>[readConversation],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsNothing);
    expect(find.text('2'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航消息角标显示真实未读数量', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final conversations = <ConversationSummary>[
      ConversationSummary(
        threadId: 'dm:read',
        displayName: 'Read Chat',
        lastMessagePreview: 'read',
        lastMessageAt: DateTime(2026, 3, 28, 10, 24),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:read',
      ),
      ConversationSummary(
        threadId: 'dm:unread',
        displayName: 'Unread Chat',
        lastMessagePreview: 'unread',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 2,
        isGroup: false,
        targetDid: 'did:unread',
      ),
    ];
    final gateway = FakeAwikiGateway()..conversations = conversations;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsNothing);
    expect(find.text('2'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主窗口压缩高度和宽度时不会出现布局溢出', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      nickName: 'Mia',
      bio: 'Product lead',
      tags: <String>['agent'],
      profileMarkdown: '',
      handle: 'mia',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    for (final size in <Size>[
      const Size(1280, 600),
      const Size(960, 560),
      const Size(720, 520),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          gateway: gateway,
          session: session,
          profile: profile,
          providerOverrides: <Override>[
            conversationListProvider.overrideWith(
              (ref) =>
                  _StaticConversationListController(ref, gateway.conversations),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('最近会话'), findsOneWidget);
      await tester.tap(find.text('Marcus Chen').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatView), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话列表分栏可以拖动调整宽度', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final before = tester
        .getSize(find.byKey(const Key('mac-conversation-list-pane')))
        .width;
    await tester.drag(
      find.byKey(const Key('awiki-pane-divider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    final after = tester
        .getSize(find.byKey(const Key('mac-conversation-list-pane')))
        .width;

    expect(after, greaterThan(before));

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话搜索支持标题和最近消息预览', (tester) async {
    final conversations = <ConversationSummary>[
      conversation,
      ConversationSummary(
        threadId: 'group:funding',
        displayName: '融资协作群',
        lastMessagePreview: '明早同步 deck',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 0,
        isGroup: true,
        groupId: 'did:test:group:funding',
      ),
      ConversationSummary(
        threadId: 'dm:did:me:did:ops',
        displayName: 'Ops Bot',
        lastMessagePreview: 'server alert recovered',
        lastMessageAt: DateTime(2026, 3, 28, 10, 26),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:ops',
      ),
    ];
    final gateway = FakeAwikiGateway()..conversations = conversations;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索会话'), findsOneWidget);
    expect(find.text('搜索会话或 Agent'), findsNothing);
    expect(find.text('Marcus Chen'), findsOneWidget);
    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('Ops Bot'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), '融资');
    await tester.pumpAndSettle();
    expect(find.text('Marcus Chen'), findsNothing);
    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('Ops Bot'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'recovered');
    await tester.pumpAndSettle();
    expect(find.text('Marcus Chen'), findsNothing);
    expect(find.text('融资协作群'), findsNothing);
    expect(find.text('Ops Bot'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'not-found');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关会话'), findsOneWidget);
    expect(find.text('换个关键词试试'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('手机宽度下点击会话进入独立聊天页', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(ChatView), findsOneWidget);
  });

  testWidgets('手机宽度下最近会话搜索支持标题和最近消息预览', (tester) async {
    final conversations = <ConversationSummary>[
      conversation,
      ConversationSummary(
        threadId: 'group:funding',
        displayName: '融资协作群',
        lastMessagePreview: '明早同步 deck',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 0,
        isGroup: true,
        groupId: 'did:test:group:funding',
      ),
      ConversationSummary(
        threadId: 'dm:did:me:did:ops',
        displayName: 'Ops Bot',
        lastMessagePreview: 'server alert recovered',
        lastMessageAt: DateTime(2026, 3, 28, 10, 26),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:ops',
      ),
    ];
    final gateway = FakeAwikiGateway()..conversations = conversations;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);
    expect(find.text('Marcus Chen'), findsOneWidget);
    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('Ops Bot'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), '融资');
    await tester.pumpAndSettle();
    expect(find.text('Marcus Chen'), findsNothing);
    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('Ops Bot'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'recovered');
    await tester.pumpAndSettle();
    expect(find.text('Marcus Chen'), findsNothing);
    expect(find.text('融资协作群'), findsNothing);
    expect(find.text('Ops Bot'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'not-found');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关会话'), findsOneWidget);
    expect(find.text('换个关键词试试'), findsOneWidget);
  });

  testWidgets('手机主导航显示中文文字标签并保持切换功能', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      nickName: 'Mia',
      bio: 'Product lead',
      tags: <String>['agent'],
      profileMarkdown: '',
      handle: 'mia',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        profile: profile,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('消息'), findsWidgets);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('联系人'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);
    expect(find.text('Agents'), findsNothing);
    final messagesTab = find.ancestor(
      of: find.text('消息').last,
      matching: find.byType(Row),
    );
    final navRow = messagesTab.first;
    expect(
      find.byKey(const Key('mobile-messages-unread-badge')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mobile-messages-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    final messageTabSize = tester.getSize(find.text('消息').last);
    final agentsTabSize = tester.getSize(find.text('智能体'));
    final contactsTabSize = tester.getSize(find.text('联系人'));
    final meTabSize = tester.getSize(find.text('我'));
    expect(messageTabSize.height, greaterThan(0));
    expect(agentsTabSize.height, greaterThan(0));
    expect(contactsTabSize.height, greaterThan(0));
    expect(meTabSize.height, greaterThan(0));
    final bottomNavHeight = tester.getSize(navRow).height;
    expect(bottomNavHeight, closeTo(52, 0.1));
    final navRowCenterY = tester.getCenter(navRow).dy;
    final messageLabelCenterY = tester.getCenter(find.text('消息').last).dy;
    expect(messageLabelCenterY, lessThan(navRowCenterY + 22));
    final navRowRect = tester.getRect(navRow);
    final mobileBadgeRect = tester.getRect(
      find.byKey(const Key('mobile-messages-unread-badge')),
    );
    expect(mobileBadgeRect.top, greaterThanOrEqualTo(navRowRect.top));
    expect(mobileBadgeRect.right, lessThanOrEqualTo(navRowRect.right));

    final navLabels = find
        .descendant(of: navRow, matching: find.byType(Text))
        .evaluate()
        .map((element) => (element.widget as Text).data)
        .whereType<String>()
        .where((label) => <String>{'消息', '智能体', '联系人', '我'}.contains(label))
        .toList();
    expect(navLabels, ['消息', '智能体', '联系人', '我']);

    await tester.tap(find.text('智能体'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentsWorkspacePage), findsOneWidget);
    expect(find.text('智能体'), findsWidgets);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    expect(find.text('朋友'), findsWidgets);

    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    expect(find.text('Product lead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机主导航英文环境显示 Agents', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        locale: const Locale('en'),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('智能体'), findsNothing);

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentsWorkspacePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机消息列表右侧元信息只展示时间和智能体状态，未读展示在预览前缀', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final richConversation = ConversationSummary(
      threadId: 'dm:mobile-right-meta',
      displayName: 'Mobile Runtime Agent',
      lastMessagePreview: '这是一段很长的最近消息预览，用来验证右侧时间、状态和未读数量不会被遮挡。',
      lastMessageAt: DateTime(2026, 12, 31, 23, 59),
      unreadCount: 120,
      isGroup: false,
      targetDid: 'did:wba:anpclaw.com:agent:runtime:mobile:e1_agent',
      targetPeer: 'mobile-agent.anpclaw.com',
      avatarSeed: 'Mobile Runtime Agent',
    );
    final agent = AgentSummary(
      agentDid: richConversation.targetDid!,
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:test:daemon',
      runtime: 'hermes',
      handle: 'mobile-agent',
      displayName: 'Mobile Runtime Agent',
      activeState: 'active',
      latest: const AgentLatestStatus(
        status: 'needs_config',
        needsConfig: true,
      ),
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[richConversation];
    final control = FakeAgentControlService()..agents = <AgentSummary>[agent];
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 780));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Runtime Agent'), findsOneWidget);
    expect(find.text('999+'), findsNothing);
    expect(find.text('未读 120'), findsOneWidget);
    expect(find.byType(AgentStatusDot), findsOneWidget);
    final rowRect = tester.getRect(
      find.ancestor(
        of: find.text('Mobile Runtime Agent'),
        matching: find.byType(AppPressableTile),
      ),
    );
    final metaRect = tester.getRect(
      find.byKey(const Key('conversation-row-right-meta')),
    );
    expect(
      find.byKey(const Key('conversation-row-unread-badge')),
      findsNothing,
    );
    final unreadTagRect = tester.getRect(find.text('未读 120'));
    final timeRect = tester.getRect(find.text('12-31'));
    expect(metaRect.right, lessThanOrEqualTo(rowRect.right));
    expect(timeRect.right, lessThanOrEqualTo(rowRect.right - 2));
    expect(unreadTagRect.left, greaterThanOrEqualTo(rowRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pad 宽度下展示双栏并在右侧更新聊天内容', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1024, 768));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsNothing);
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('Marcus Chen'), findsWidgets);
  });

  testWidgets('macOS 双栏刷新后按 exact thread 保持 peer-scoped 选中会话', (tester) async {
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
    const agentHandle = 'test-agent.awiki.ai';
    final controllerConversation = ConversationSummary(
      conversationId: 'dm:peer-scope:v1:controller',
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'Controller',
      lastMessagePreview: 'controller preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final runtimeConversation = ConversationSummary(
      conversationId: 'dm:peer-scope:v1:runtime',
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime Agent',
      lastMessagePreview: 'runtime preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        runtimeConversation,
        controllerConversation,
      ]
      ..localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    late _StaticConversationListController listController;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith((ref) {
            listController = _StaticConversationListController(
              ref,
              gateway.conversations,
            );
            return listController;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Controller'));
    await tester.pumpAndSettle();

    ChatView chatView() => tester.widget<ChatView>(find.byType(ChatView));
    expect(chatView().conversation.threadId, controllerConversation.threadId);

    listController.replaceConversations(<ConversationSummary>[
      runtimeConversation.copyWith(
        lastMessagePreview: 'runtime refreshed',
        lastMessageAt: DateTime(2026, 7, 3, 7, 12),
      ),
      controllerConversation.copyWith(
        displayName: 'Controller Refreshed',
        lastMessagePreview: 'controller refreshed',
        lastMessageAt: DateTime(2026, 7, 3, 7, 11),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(chatView().conversation.threadId, controllerConversation.threadId);
    expect(chatView().conversation.displayName, 'Controller Refreshed');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
}
