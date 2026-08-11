import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_terminal_notification.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

Future<void> _activateRuntime(
  WidgetTester tester,
  SessionIdentity session,
) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
    listen: false,
  );
  final committed = await container
      .read(appSessionServiceProvider)
      .activateIdentity(
        AppSession(
          did: session.did,
          identityId: session.credentialName,
          displayName: session.displayName,
          handle: session.handle,
          localAlias: session.credentialName,
          authenticated: session.jwtToken != null,
          jwtToken: session.jwtToken,
          accountBinding: session.accountBinding,
        ),
      );
  await container
      .read(appRuntimeProvider.notifier)
      .activateCommittedSession(committed);
  await container.read(agentsProvider.notifier).syncRemoteInventory();
  await tester.pump();
}

FakeAgentControlService _runtimeAgentControl() {
  return FakeAgentControlService()
    ..agents = const <AgentSummary>[
      AgentSummary(
        agentDid: 'did:agent:daemon',
        kind: AgentKind.daemon,
        displayName: 'Daemon',
        activeState: 'active',
        latest: readyDaemonStatusWithGenericCliCapability,
      ),
      AgentSummary(
        agentDid: 'did:agent:runtime',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:agent:daemon',
        runtime: 'codex',
        displayName: 'Codex',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      ),
    ];
}

void main() {
  testWidgets('前台所有业务终态和运行失败均不显示 App 内横幅', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      displayName: 'Me',
      handle: 'me',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
    final realtimeGateway = FakeRealtimeGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        session: session,
      ),
    );
    await tester.pump();
    await _activateRuntime(tester, session);
    for (final entry in <(Map<String, Object?>, String)>[
      (
        <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'event_id': 'evt_run_terminal:run_widget_completed:completed',
          'run_id': 'run_widget_completed',
          'state': 'finished',
          'business_outcome': 'completed',
          'summary': '任务已完成',
          'next_step': null,
          'final_message_id': 'msg_widget_completed',
        },
        '智能体任务已完成: 任务已完成',
      ),
      (
        <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'event_id': 'evt_run_terminal:run_widget_blocked:blocked',
          'run_id': 'run_widget_blocked',
          'state': 'finished',
          'business_outcome': 'blocked',
          'summary': '缺少访问权限',
          'next_step': '补充访问权限',
          'final_message_id': 'msg_widget_blocked',
        },
        '已阻塞: 缺少访问权限. 下一步: 补充访问权限',
      ),
      (
        <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'event_id': 'evt_run_terminal:run_widget_action:action_required',
          'run_id': 'run_widget_action',
          'state': 'finished',
          'business_outcome': 'action_required',
          'summary': '需要确认范围',
          'next_step': '确认是否继续',
          'final_message_id': 'msg_widget_action',
        },
        '智能体任务等待确认: 需要确认范围. 下一步: 确认是否继续',
      ),
      (
        <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'event_id': 'evt_run_terminal:run_widget_failed:failed',
          'run_id': 'run_widget_failed',
          'state': 'failed',
        },
        '智能体任务处理失败',
      ),
    ]) {
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        agentControlPayload: entry.$1,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'status'});
      await tester.pump();
      await tester.pump();
      expect(find.text(entry.$2), findsNothing);
    }

    await tester.pump(const Duration(seconds: 8));
  });

  testWidgets('消息先到时 matching blocked 终态取消普通通知且前台静默', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      displayName: 'Me',
      handle: 'me',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
    final realtimeGateway = FakeRealtimeGateway();
    final notificationFacade = FakeNotificationFacade();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        notificationFacade: notificationFacade,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(_runtimeAgentControl()),
        ],
      ),
    );
    await tester.pump();
    await _activateRuntime(tester, session);
    gateway.nextRealtimeUpdate = const RealtimeUpdate(
      ownerDid: 'did:test:me',
      agentControlPayload: <String, Object?>{
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
    await realtimeGateway.emit(const <String, Object?>{'type': 'snapshot'});
    await tester.pump();

    gateway.nextRealtimeUpdate = RealtimeUpdate(
      ownerDid: 'did:test:me',
      message: ChatMessage(
        localId: 'msg_widget_final',
        remoteId: 'msg_widget_final',
        threadId: 'dm:runtime',
        senderDid: 'did:agent:runtime',
        senderName: 'Codex',
        receiverDid: 'did:test:me',
        content: 'ordinary final reply',
        createdAt: DateTime(2026, 7, 27, 12),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversationHint: ConversationSummary(
        conversationId: 'dm:runtime',
        threadId: 'dm:runtime',
        displayName: 'Codex',
        lastMessagePreview: 'ordinary final reply',
        lastMessageAt: DateTime(2026, 7, 27, 12),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:agent:runtime',
      ),
    );
    await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
    await tester.pump();
    expect(notificationFacade.inAppNotificationCount, 0);

    gateway.nextRealtimeUpdate = const RealtimeUpdate(
      ownerDid: 'did:test:me',
      agentControlPayload: <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'event_id': 'evt_run_terminal:run_widget_ordered:blocked',
        'run_id': 'run_widget_ordered',
        'state': 'finished',
        'business_outcome': 'blocked',
        'summary': '缺少访问权限',
        'next_step': '补充访问权限',
        'final_message_id': 'msg_widget_final',
      },
    );
    await realtimeGateway.emit(const <String, Object?>{'type': 'status'});
    await tester.pump();
    await tester.pump();
    expect(find.text('已阻塞: 缺少访问权限. 下一步: 补充访问权限'), findsNothing);

    await tester.pump(
      AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow,
    );
    expect(notificationFacade.inAppNotificationCount, 0);
    expect(notificationFacade.systemNotificationCount, 0);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('disposing AppShell cancels pending Runtime Agent notification', (
    tester,
  ) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      displayName: 'Me',
      handle: 'me',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
    final realtimeGateway = FakeRealtimeGateway();
    final notificationFacade = FakeNotificationFacade();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        notificationFacade: notificationFacade,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(_runtimeAgentControl()),
        ],
      ),
    );
    await tester.pump();
    await _activateRuntime(tester, session);
    gateway.nextRealtimeUpdate = const RealtimeUpdate(
      ownerDid: 'did:test:me',
      agentControlPayload: <String, Object?>{
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
    await realtimeGateway.emit(const <String, Object?>{'type': 'snapshot'});
    await tester.pump();
    gateway.nextRealtimeUpdate = RealtimeUpdate(
      ownerDid: 'did:test:me',
      message: ChatMessage(
        localId: 'msg_dispose_pending',
        remoteId: 'msg_dispose_pending',
        threadId: 'dm:runtime',
        senderDid: 'did:agent:runtime',
        senderName: 'Codex',
        receiverDid: 'did:test:me',
        content: 'pending ordinary notification',
        createdAt: DateTime(2026, 7, 27, 12),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversationHint: ConversationSummary(
        conversationId: 'dm:runtime',
        threadId: 'dm:runtime',
        displayName: 'Codex',
        lastMessagePreview: 'pending ordinary notification',
        lastMessageAt: DateTime(2026, 7, 27, 12),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:agent:runtime',
      ),
    );
    await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(
      AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow,
    );

    expect(notificationFacade.inAppNotificationCount, 0);
    expect(notificationFacade.systemNotificationCount, 0);
  });
}
