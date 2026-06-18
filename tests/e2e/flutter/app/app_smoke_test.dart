import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Key, Size;
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
  Future<void> refresh() async {
    // The integration smoke seeds the list synchronously so AppRuntime
    // initialization cannot race the UI flow under test.
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AwikiMeApp starts with fake bootstrap and shows onboarding', (
    tester,
  ) async {
    final harness = createFakeAwikiMeAppHarness();

    await tester.pumpWidget(
      AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('切换身份'), findsWidgets);
    expect(find.text('登录或注册'), findsWidgets);
    expect(harness.gateway.listLocalCredentialsCalls, greaterThanOrEqualTo(1));
    expect(harness.realtimeGateway.isConnected, isFalse);
  });

  testWidgets('AwikiMeApp starts authenticated shell', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'test-jwt',
    );
    final harness = createFakeAwikiMeAppHarness(session: session);

    await tester.pumpWidget(
      AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('AwikiMeApp authenticated smoke opens profile and settings', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1200, 840));
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'test-jwt',
    );
    final harness = createFakeAwikiMeAppHarness(session: session);

    try {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: harness.bootstrap,
          providerOverrides: harness.providerOverrides,
        ),
      );
      await _pumpSmokeFrame(tester);

      expect(find.byType(AppShell), findsOneWidget);

      await _tapFirstFound(tester, <Finder>[
        find.bySemanticsIdentifier('e2e-profile-tab'),
        find.byKey(const Key('mac-me-rail-avatar')),
        find.bySemanticsLabel('我'),
        find.text('我'),
      ]);
      await _pumpSmokeFrame(tester);

      expect(find.text('Smoke test profile.'), findsOneWidget);

      await _tapFirstFound(tester, <Finder>[
        find.bySemanticsIdentifier('e2e-messages-tab'),
        find.bySemanticsLabel('消息'),
        find.text('消息'),
      ]);
      await _pumpSmokeFrame(tester);
      await _tapFirstFound(tester, <Finder>[
        find.bySemanticsIdentifier('e2e-settings-tab'),
        find.bySemanticsLabel('设置'),
        find.text('设置'),
      ]);
      await _pumpSmokeFrame(tester);

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('设置'), findsWidgets);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('导出身份凭证'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('AwikiMeApp authenticated smoke opens Message Agent settings', (
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
      await _pumpSmokeFrame(tester);

      expect(find.byType(AppShell), findsOneWidget);
      await _tapFirstFound(tester, <Finder>[
        find.bySemanticsIdentifier('e2e-agents-tab'),
        find.bySemanticsLabel('智能体'),
        find.bySemanticsLabel('Agents'),
        find.text('智能体'),
        find.text('Agents'),
      ]);
      await _pumpSmokeFrame(tester);

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
      await _pumpSmokeFrame(tester);

      expect(control.lastBootstrapDaemonDid, 'did:test:daemon:message');
      expect(control.lastBootstrapControllerDid, 'did:test:me');
      expect(
        control.lastBootstrapDaemonPublicKey?.keyId,
        'did:test:daemon:message#key-3',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets(
    'UI optimization smoke keeps conversation info closed and opens Agent info popup',
    (tester) async {
      const session = SessionIdentity(
        did: 'did:test:me',
        credentialName: 'default',
        handle: 'me',
        displayName: 'Me',
        jwtToken: 'test-jwt',
      );
      const runtimeDid = 'did:test:agent:hermes-ui';
      final conversation = ConversationSummary(
        threadId: 'dm:$runtimeDid',
        displayName: 'Hermes UI',
        lastMessagePreview: 'latest runtime reply',
        lastMessageAt: DateTime(2026, 6, 15, 10, 30),
        unreadCount: 0,
        isGroup: false,
        targetDid: runtimeDid,
      );
      final history = <ChatMessage>[
        ChatMessage(
          localId: 'agent-message-1',
          threadId: 'dm:$runtimeDid',
          senderDid: runtimeDid,
          senderName: 'Hermes UI',
          content: 'latest runtime reply',
          createdAt: DateTime(2026, 6, 15, 10, 30),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ];
      const profile = UserProfile(
        did: runtimeDid,
        nickName: 'Hermes UI',
        bio: 'Runtime Agent info popup smoke.',
        tags: <String>['Agent'],
        profileMarkdown: '# Hermes UI\n\nRuntime Agent info popup smoke.',
        handle: 'hermes-ui',
      );
      final harness = createFakeAwikiMeAppHarness(session: session);
      harness.gateway
        ..conversations = <ConversationSummary>[conversation]
        ..dmHistoryByPeerDid = <String, List<ChatMessage>>{runtimeDid: history}
        ..publicProfilesByQuery = <String, UserProfile>{runtimeDid: profile};
      final control =
          harness.bootstrap.agentControlService!
              as test_support.FakeAgentControlService;
      control.agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:test:daemon:local',
          kind: AgentKind.daemon,
          handle: 'daemon',
          displayName: 'Local Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        const AgentSummary(
          agentDid: runtimeDid,
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:test:daemon:local',
          runtime: 'hermes',
          handle: 'hermes-ui',
          displayName: 'Hermes UI',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.binding.setSurfaceSize(const Size(1600, 960));
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
        await tester.pumpAndSettle();

        expect(find.byType(AppShell), findsOneWidget);
        expect(find.text('最近会话'), findsOneWidget);
        await tester.tap(find.text('Hermes UI').first);
        await tester.pumpAndSettle();

        expect(find.text('会话信息'), findsNothing);
        expect(
          find.byKey(const Key('chat-conversation-info-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('chat-conversation-info-button')),
        );
        await tester.pump();
        expect(find.text('会话信息'), findsOneWidget);

        await tester.tap(find.text('身份卡').first);
        await tester.pumpAndSettle();

        expect(find.text('智能体信息'), findsOneWidget);
        expect(find.text('Runtime Agent'), findsOneWidget);
        expect(find.text('Agent 收件箱'), findsOneWidget);
        expect(
          find.byKey(const Key('peer-info-dialog-did-value')),
          findsOneWidget,
        );

        await tester.tap(find.text('Agent 收件箱'));
        await tester.pump();
        expect(find.byKey(const Key('peer-info-agent-inbox')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    },
  );
}

Future<void> _pumpSmokeFrame(WidgetTester tester) async {
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
