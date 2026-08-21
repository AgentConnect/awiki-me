import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/presentation/agents/personal_agent_feature_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const personalAgent = AgentSummary(
    agentDid: 'did:agent:personal',
    kind: AgentKind.runtime,
    runtime: 'hermes',
    handle: 'hermes-personal-app-default',
    displayName: 'Hermes Personal Agent',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
  );
  const regularAgent = AgentSummary(
    agentDid: 'did:agent:codex',
    kind: AgentKind.runtime,
    runtime: 'codex',
    handle: 'codex-worker',
    displayName: 'Codex Worker',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
  );
  const regularHermesAgent = AgentSummary(
    agentDid: 'did:agent:hermes-ui',
    kind: AgentKind.runtime,
    runtime: 'hermes',
    handle: 'hermes-ui',
    displayName: 'Hermes UI',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
  );
  const futurePersonalAgent = AgentSummary(
    agentDid: 'did:agent:future-personal',
    kind: AgentKind.runtime,
    runtime: 'generic-cli',
    handle: 'codex-msg-app-default',
    displayName: 'Codex Personal Agent',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
  );

  test('recognizes only the Personal Agent runtime', () {
    expect(isPersonalAgentRuntime(personalAgent), isTrue);
    expect(isPersonalAgentRuntime(regularAgent), isFalse);
    expect(isPersonalAgentRuntime(regularHermesAgent), isFalse);
    expect(isPersonalAgentRuntime(futurePersonalAgent), isTrue);
    expect(isEnabledPersonalAgentRuntime(personalAgent), isTrue);
    expect(isEnabledPersonalAgentRuntime(futurePersonalAgent), isFalse);
  });

  test(
    'hidden projection keeps ordinary conversations and their unread state',
    () {
      final conversations = <ConversationSummary>[
        _conversation(
          id: 'direct:did:human:bob',
          targetDid: 'did:human:bob',
          displayName: 'Bob',
          unreadCount: 2,
        ),
        _conversation(
          id: 'direct:did:agent:personal',
          targetDid: personalAgent.agentDid,
          displayName: 'Renamed runtime',
          unreadCount: 7,
        ),
      ];

      final visible = personalAgentVisibleConversations(
        conversations: conversations,
        agents: const <AgentSummary>[personalAgent, regularAgent],
        personalAgentVisible: false,
      );

      expect(visible.map((item) => item.conversationId), <String>[
        'direct:did:human:bob',
      ]);
      expect(visible.single.unreadCount, 2);
      expect(conversations.last.unreadCount, 7);
    },
  );

  test(
    'recognizes Personal Agent conversations before inventory is available',
    () {
      final byHandle = _conversation(
        id: 'direct:legacy-personal-agent',
        targetDid: 'did:agent:unknown',
        targetPeer: 'hermes-msg-app-default@awiki.ai',
        displayName: 'Renamed runtime',
        unreadCount: 0,
      );
      final byDisplayName = _conversation(
        id: 'direct:named-personal-agent',
        targetDid: 'did:agent:unknown-2',
        displayName: 'Hermes Personal Agent',
        unreadCount: 0,
      );

      expect(isPersonalAgentConversation(byHandle, const []), isTrue);
      expect(isPersonalAgentConversation(byDisplayName, const []), isTrue);
    },
  );

  test('keeps an ordinary Hermes runtime conversation visible', () {
    final conversation = _conversation(
      id: 'direct:did:agent:hermes-ui',
      targetDid: regularHermesAgent.agentDid,
      displayName: 'hermes-ui.awiki.ai',
      unreadCount: 0,
    );

    expect(
      isPersonalAgentConversation(conversation, const <AgentSummary>[
        regularHermesAgent,
      ]),
      isFalse,
    );
  });

  test('does not hide a human contact with a similar display name', () {
    final conversation = _conversation(
      id: 'direct:did:human:personal-agent',
      targetDid: 'did:human:personal-agent',
      displayName: 'Personal Agent',
      unreadCount: 1,
    );

    expect(isPersonalAgentConversation(conversation, const []), isFalse);
  });

  test('recognizes only control payloads owned by the Personal Agent', () {
    expect(
      isPersonalAgentControlPayload(
        const <String, Object?>{
          'runtime_agent_did': 'did:agent:personal',
          'runs': <Object?>[
            <String, Object?>{'agent_did': 'did:agent:personal'},
          ],
        },
        const <AgentSummary>[personalAgent, regularAgent],
      ),
      isTrue,
    );
    expect(
      isPersonalAgentControlPayload(
        const <String, Object?>{
          'runtime_agent_did': 'did:agent:codex',
          'runs': <Object?>[
            <String, Object?>{'agent_did': 'did:agent:codex'},
          ],
        },
        const <AgentSummary>[personalAgent, regularAgent],
      ),
      isFalse,
    );
  });

  test('visible projection preserves all conversations', () {
    final conversations = <ConversationSummary>[
      _conversation(
        id: 'direct:did:agent:personal',
        targetDid: personalAgent.agentDid,
        displayName: personalAgent.displayName,
        unreadCount: 1,
      ),
    ];

    expect(
      personalAgentVisibleConversations(
        conversations: conversations,
        agents: const <AgentSummary>[personalAgent],
        personalAgentVisible: true,
      ),
      conversations,
    );
  });
}

ConversationSummary _conversation({
  required String id,
  required String targetDid,
  required String displayName,
  required int unreadCount,
  String? targetPeer,
}) {
  return ConversationSummary(
    conversationId: id,
    threadId: id,
    displayName: displayName,
    lastMessagePreview: 'message',
    lastMessageAt: DateTime(2026, 8, 11),
    unreadCount: unreadCount,
    isGroup: false,
    targetDid: targetDid,
    targetPeer: targetPeer,
  );
}
