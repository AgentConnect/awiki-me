import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/conversation_core_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daemon DID conversation is hidden from recent messages', () async {
    final service = ImCoreConversationService(
      conversations: _FakeConversations(
        items: <ConversationSummary>[
          _conversation('dm:human:daemon', targetDid: 'did:agent:daemon'),
          _conversation('dm:human:runtime', targetDid: 'did:agent:runtime'),
          _conversation('dm:human:bob', targetDid: 'did:human:bob'),
        ],
      ),
      localStore: InMemoryAwikiProductLocalStore(),
      agentInventory: const _FakeAgentInventory(
        agents: <AgentSummary>[
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
        ],
      ),
    );

    final conversations = await service.listConversations(
      ownerDid: 'did:human:me',
    );

    expect(conversations.map((item) => item.targetDid), [
      'did:agent:runtime',
      'did:human:bob',
    ]);
  });

  test(
    'inventory failure keeps conversations visible instead of over-filtering',
    () async {
      final service = ImCoreConversationService(
        conversations: _FakeConversations(
          items: <ConversationSummary>[
            _conversation('dm:human:daemon', targetDid: 'did:agent:daemon'),
          ],
        ),
        localStore: InMemoryAwikiProductLocalStore(),
        agentInventory: const _ThrowingAgentInventory(),
      );

      final conversations = await service.listConversations(
        ownerDid: 'did:human:me',
      );

      expect(conversations.single.targetDid, 'did:agent:daemon');
    },
  );

  test('control payload conversation is hidden without inventory', () async {
    final service = ImCoreConversationService(
      conversations: _FakeConversations(
        items: <ConversationSummary>[
          _conversation(
            'dm:human:daemon-control',
            targetDid: 'did:agent:unknown-daemon',
            lastMessagePayloadJson:
                '{"schema":"awiki.agent.status.v1","status_scope":"daemon"}',
          ),
          _conversation('dm:human:runtime', targetDid: 'did:agent:runtime'),
        ],
      ),
      localStore: InMemoryAwikiProductLocalStore(),
      agentInventory: const _ThrowingAgentInventory(),
    );

    final conversations = await service.listConversations(
      ownerDid: 'did:human:me',
    );

    expect(conversations.map((item) => item.targetDid), ['did:agent:runtime']);
  });
}

ConversationSummary _conversation(
  String threadId, {
  required String targetDid,
  String? lastMessagePayloadJson,
}) {
  return ConversationSummary(
    threadId: threadId,
    displayName: threadId,
    lastMessagePreview: 'preview',
    lastMessageAt: DateTime.utc(2026, 6, 4),
    unreadCount: 0,
    isGroup: false,
    targetDid: targetDid,
    lastMessagePayloadJson: lastMessagePayloadJson,
  );
}

class _FakeConversations implements ConversationCorePort {
  const _FakeConversations({required this.items});

  final List<ConversationSummary> items;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot() async {
    return const <ConversationSummary>[];
  }

  @override
  Future<void> clearConversationSnapshot() async {}

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return items.take(limit).toList();
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {}
}

class _FakeAgentInventory implements AgentInventoryPort {
  const _FakeAgentInventory({required this.agents});

  final List<AgentSummary> agents;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    return agents;
  }

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy({
    required String agentDid,
  }) async {
    return const AgentInvocationPolicy();
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    return policy;
  }

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
    required String handle,
    required String displayName,
    String? driverId,
    String? workspaceMode,
    String? defaultSandbox,
    String? defaultModel,
    Map<String, Object?>? driverConfig,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> unbindAgent({required String agentDid}) {
    throw UnimplementedError();
  }

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) {
    throw UnimplementedError();
  }
}

class _ThrowingAgentInventory extends _FakeAgentInventory {
  const _ThrowingAgentInventory() : super(agents: const <AgentSummary>[]);

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) {
    throw StateError('inventory unavailable');
  }
}
