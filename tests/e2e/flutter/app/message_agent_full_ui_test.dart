import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../unit/test_support.dart' as test_support;
import '../support/fake_app_bootstrap.dart';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> conversations,
  ) {
    state = ConversationListState(conversations: conversations);
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Message Agent full UI enables Hermes runtime and lifecycle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'test-jwt',
    );
    final harness = createFakeAwikiMeAppHarness(session: session);
    final control =
        harness.bootstrap.agentControlService!
            as test_support.FakeAgentControlService;
    control.agents = const <AgentSummary>[
      AgentSummary(
        agentDid: 'did:test:daemon:message',
        kind: AgentKind.daemon,
        handle: 'daemon-message',
        displayName: 'Message Daemon',
        activeState: 'active',
        latest: AgentLatestStatus(
          status: 'ready',
          version: '0.5.26',
          platform: 'linux-amd64',
          diagnosticsSummary: <String, Object?>{
            'bootstrap_key_id': 'did:test:daemon:message#key-3',
            'bootstrap_public_key_b64u':
                'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            'bootstrap_key_algorithm': 'x25519',
          },
        ),
      ),
      AgentSummary(
        agentDid: 'did:test:agent:message',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:test:daemon:message',
        runtime: 'hermes',
        handle: 'hermes-msg-app-default',
        displayName: 'Hermes Message Agent',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      ),
    ];

    try {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: harness.bootstrap,
          providerOverrides: <Override>[
            ...harness.providerOverrides,
            agentImEnabledProvider.overrideWithValue(true),
          ],
        ),
      );
      await _pumpFrame(tester);

      expect(find.byType(AppShell), findsOneWidget);
      await _tapFirstFound(tester, <Finder>[
        find.bySemanticsIdentifier('e2e-agents-tab'),
        find.bySemanticsLabel('智能体'),
        find.bySemanticsLabel('Agents'),
        find.text('智能体'),
        find.text('Agents'),
      ]);
      await _pumpFrame(tester);

      expect(find.text('Message Daemon'), findsWidgets);
      expect(find.text('消息处理 Agent'), findsOneWidget);
      expect(find.text('运行 Daemon'), findsOneWidget);
      expect(find.text('Hermes'), findsOneWidget);
      expect(find.text('所有可处理会话'), findsOneWidget);
      expect(find.text('0.5.26 · linux-amd64'), findsOneWidget);
      expect(find.text('Hermes message runtime'), findsOneWidget);
      expect(find.text('已上报公钥'), findsOneWidget);
      expect(find.text('启用消息处理 Agent'), findsOneWidget);
      expect(find.text('暂停处理消息'), findsOneWidget);
      expect(find.text('删除消息处理 Agent'), findsOneWidget);
      expect(find.text('撤销 Daemon 消息授权'), findsOneWidget);
      expect(find.textContaining('自动回复'), findsNothing);
      expect(find.textContaining('代发'), findsNothing);

      await tester.tap(find.text('启用消息处理 Agent'));
      await _pumpFrame(tester);

      expect(control.lastBootstrapDaemonDid, 'did:test:daemon:message');
      expect(control.lastBootstrapControllerDid, 'did:test:me');
      expect(
        control.lastBootstrapDaemonPublicKey?.keyId,
        'did:test:daemon:message#key-3',
      );

      await tester.tap(find.text('暂停处理消息'));
      await _pumpFrame(tester);
      expect(
        find.text('暂停后，消息处理 Agent 不再读取和处理新消息；runtime 和授权仍会保留，可以重新启用。'),
        findsOneWidget,
      );
      await tester.tap(find.text('暂停'));
      await _pumpFrame(tester);
      expect(
        control.lastPausedMessageAgentDaemonDid,
        'did:test:daemon:message',
      );
      expect(control.lastPausedMessageAgentDid, 'did:test:agent:message');

      await tester.tap(find.text('删除消息处理 Agent'));
      await _pumpFrame(tester);
      expect(
        find.text('删除前会先暂停消息处理，然后归档对应 runtime。Daemon 和授权不会被删除。'),
        findsOneWidget,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.text('删除'),
            )
            .last,
      );
      await _pumpFrame(tester);
      expect(
        control.lastDeletedMessageAgentDaemonDid,
        'did:test:daemon:message',
      );
      expect(control.lastDeletedMessageAgentDid, 'did:test:agent:message');

      await tester.tap(find.text('撤销 Daemon 消息授权'));
      await _pumpFrame(tester);
      expect(find.textContaining('签名 DID Document 更新'), findsOneWidget);
      await tester.tap(find.text('撤销授权'));
      await _pumpFrame(tester);
      expect(
        control.lastRevokedMessageAgentDaemonDid,
        'did:test:daemon:message',
      );
      expect(control.lastRevokedMessageAgentDid, 'did:test:agent:message');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets(
    'Message Agent full UI recovers runtime result and draft action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      const session = SessionIdentity(
        did: 'did:test:me',
        credentialName: 'default',
        handle: 'me',
        displayName: 'Me',
        jwtToken: 'test-jwt',
      );
      final conversation = ConversationSummary(
        threadId: 'direct:did:human:bob',
        displayName: 'Bob',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 6, 19, 10, 0),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:human:bob',
      );
      final history = <ChatMessage>[
        ChatMessage(
          localId: 'msg_1',
          remoteId: 'msg_1',
          threadId: conversation.threadId,
          senderDid: 'did:human:bob',
          receiverDid: session.did,
          content: 'hello',
          createdAt: DateTime(2026, 6, 19, 10, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ];
      final harness = createFakeAwikiMeAppHarness(session: session);
      harness.gateway
        ..conversations = <ConversationSummary>[conversation]
        ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
          'did:human:bob': history,
        };
      final control =
          harness.bootstrap.agentControlService!
              as test_support.FakeAgentControlService;
      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: 'Message Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

      try {
        await tester.pumpWidget(
          AwikiMeApp(
            bootstrap: harness.bootstrap,
            providerOverrides: <Override>[
              ...harness.providerOverrides,
              conversationListProvider.overrideWith(
                (ref) => _StaticConversationListController(
                  ref,
                  <ConversationSummary>[conversation],
                ),
              ),
            ],
          ),
        );
        await _pumpFrame(tester);

        expect(find.byType(AppShell), findsOneWidget);
        expect(find.text('最近会话'), findsOneWidget);
        await tester.tap(find.text('Bob').first);
        await _pumpFrame(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        container
            .read(chatThreadsProvider.notifier)
            .applyMessageAgentControlPayload(const <String, Object?>{
              'schema': 'awiki.message.sync.v1',
              'sync_type': 'runtime_final',
              'runtime_agent_did': 'did:agent:runtime',
              'run_id': 'run_1',
              'source_message_id': 'msg_1',
              'source_conversation_id': 'direct:did:human:bob',
              'state': 'finished',
              'has_text': true,
              'retention_class': 'hash_only',
            });
        container
            .read(chatThreadsProvider.notifier)
            .applyMessageAgentControlPayload(const <String, Object?>{
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
            });
        await _pumpFrame(tester);

        expect(find.text('消息 Agent 已完成处理'), findsOneWidget);
        expect(find.text('消息 Agent 生成了草稿'), findsOneWidget);
        await tester.tap(find.text('使用草稿'));
        await _pumpFrame(tester);

        expect(find.text('草稿已放入输入框'), findsOneWidget);
        expect(harness.gateway.lastSentPayloadPeerDid, 'did:agent:daemon');
        expect(harness.gateway.lastSentPayload?['state'], 'succeeded');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    },
  );
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapFirstFound(
  WidgetTester tester,
  List<Finder> candidates,
) async {
  for (final finder in candidates) {
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      return;
    }
  }
  fail('No tappable finder matched among ${candidates.length} candidates.');
}
