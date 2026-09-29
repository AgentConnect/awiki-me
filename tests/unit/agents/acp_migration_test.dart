import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agent_runtime_display.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_support.dart';

AgentSummary runtime(String brand, {String? protocol, bool retired = false}) =>
    AgentSummary(
      agentDid: 'did:agent:runtime',
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:agent:daemon',
      runtime: brand,
      displayName: 'Agent',
      activeState: 'active',
      handle: 'hermes-personal-test',
      latest: AgentLatestStatus(
        status: retired ? 'needs_config' : 'ready',
        diagnosticsSummary: {
          if (retired) 'profile_status': 'retired',
          'config_summary': {
            if (protocol != null) 'protocol': protocol,
            'driver_id': brand,
          },
        },
      ),
    );

void main() {
  test(
    'protocol, not brand, identifies migrated instances; retirement wins',
    () {
      for (final kind in RuntimeAgentKind.values) {
        final agent = runtime(kind.runtime, protocol: 'acp');
        expect(agentUsesAcp(agent), isTrue);
        expect(agentRuntimeDisplay(agent).label, kind.displayLabel);
        final retired = runtime(kind.runtime, protocol: 'acp', retired: true);
        expect(retired.isRetiredRuntime, isTrue);
        expect(retired.usesAcp, isFalse);
        expect(
          AgentSummary.fromJson(retired.toJson()).isRetiredRuntime,
          isTrue,
        );
      }
      for (final brand in ['hermes', 'codex', 'claude-code']) {
        expect(runtime(brand).usesAcp, isFalse);
        expect(runtime(brand, protocol: 'legacy').isRetiredRuntime, isTrue);
      }
      expect(runtime('opencode').usesAcp, isTrue);
    },
  );

  test(
    'personal assistant lookup excludes retired and unproven legacy records',
    () {
      final old = runtime('hermes', protocol: 'legacy', retired: true);
      final legacy = runtime('hermes');
      final current = runtime('hermes', protocol: 'acp');
      final state = AgentsState(agents: [old, legacy, current]);
      expect(state.personalAgentRuntimeFor('did:agent:daemon'), same(current));
    },
  );

  testWidgets(
    'retired private chat retains history surface and disables composing and model controls',
    (tester) async {
      final conversation = ConversationSummary(
        conversationId: 'retired-chat',
        threadId: 'retired-chat',
        displayName: 'Agent',
        lastMessagePreview: '',
        lastMessageAt: DateTime.utc(2026),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:agent:runtime',
      );
      final control = FakeAgentControlService()
        ..agents.add(runtime('hermes', protocol: 'legacy', retired: true));
      await tester.pumpWidget(
        buildLocalizedTestApp(
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          home: CupertinoPageScaffold(
            child: ChatView(conversation: conversation, embedded: false),
          ),
          providerOverrides: [
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧版接入已停用，请重新创建智能体。聊天记录与草稿已保留。'), findsOneWidget);
      expect(find.byKey(const Key('chat-composer-input')), findsNothing);
      expect(find.text('选择模型'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatView)),
      );
      await container
          .read(chatThreadsProvider.notifier)
          .sendMessage(conversation: conversation, content: 'must not send');
      expect(
        container
            .read(chatThreadsProvider.notifier)
            .thread('retired-chat')
            .messages,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
