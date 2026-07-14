import 'dart:async';

import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
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

  test('inventory failure keeps ordinary conversations visible', () async {
    final service = ImCoreConversationService(
      conversations: _FakeConversations(
        items: <ConversationSummary>[
          _conversation('dm:human:runtime', targetDid: 'did:agent:runtime'),
        ],
      ),
      localStore: InMemoryAwikiProductLocalStore(),
      agentInventory: const _ThrowingAgentInventory(),
    );

    final conversations = await service.listConversations(
      ownerDid: 'did:human:me',
    );

    expect(conversations.single.targetDid, 'did:agent:runtime');
  });

  test('control payload conversation is hidden without inventory', () async {
    final service = ImCoreConversationService(
      conversations: _FakeConversations(
        items: <ConversationSummary>[
          _conversation(
            'dm:human:daemon-control',
            targetDid: 'did:agent:unknown-daemon',
            lastMessagePayloadJson:
                '{"schema":"awiki.agent.status.v1","status_scope":"daemon"}',
            lastMessagePreview: '',
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

  test(
    'visible control payload preview stays out of recent messages',
    () async {
      final service = ImCoreConversationService(
        conversations: _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:human:runtime-control',
              targetDid: 'did:agent:runtime',
              lastMessagePayloadJson:
                  '{"schema":"awiki.agent.status.v1","status_scope":"runtime"}',
              lastMessagePreview: 'Agent 已准备好。',
            ),
          ],
        ),
        localStore: InMemoryAwikiProductLocalStore(),
        agentInventory: const _ThrowingAgentInventory(),
      );

      final conversations = await service.listConversations(
        ownerDid: 'did:human:me',
      );

      expect(conversations, isEmpty);
    },
  );

  test('self and daemon fallback conversations stay out of recents', () async {
    final service = ImCoreConversationService(
      conversations: _FakeConversations(
        items: <ConversationSummary>[
          _conversation(
            'dm:self',
            targetDid: 'did:human:me',
            targetPeer: 'did:human:me',
          ),
          _conversation(
            'dm:daemon',
            targetDid: 'did:wba:awiki.ai:agent:daemon:edgehost_1:e1_owner',
            targetPeer: 'edgehost-1.awiki.ai',
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

    expect(conversations.map((item) => item.threadId), ['dm:human:runtime']);
  });

  test(
    'service list deduplicates projection rows only by canonical ID',
    () async {
      final service = ImCoreConversationService(
        conversations: _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:did:human:me:did:agent:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'did:agent:runtime',
              lastMessagePreview: 'legacy preview',
              lastMessageAt: DateTime.utc(2026, 7, 3, 10),
            ).copyWith(conversationId: 'dm:peer-scope:v1:runtime-thread'),
            _conversation(
              'dm:peer-scope:v1:runtime-thread',
              targetDid: 'did:agent:runtime',
              targetPeer: 'runtime.awiki.ai',
              lastMessagePreview: 'peer scoped reply',
              lastMessageAt: DateTime.utc(2026, 7, 3, 10, 1),
              unreadCount: 1,
            ),
          ],
        ),
        localStore: InMemoryAwikiProductLocalStore(),
        agentInventory: const _ThrowingAgentInventory(),
      );

      final conversations = await service.listConversations(
        ownerDid: 'did:human:me',
      );

      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, 'dm:peer-scope:v1:runtime-thread');
      expect(conversations.single.lastMessagePreview, 'peer scoped reply');
      expect(conversations.single.unreadCount, 1);
    },
  );

  test(
    'service list keeps ambiguous peer-scoped direct rows separate',
    () async {
      final service = ImCoreConversationService(
        conversations: _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:did:human:me:did:agent:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'did:agent:runtime',
            ),
            _conversation(
              'dm:peer-scope:v1:controller',
              targetDid: 'did:agent:runtime',
              targetPeer: 'runtime.awiki.ai',
            ),
            _conversation(
              'dm:peer-scope:v1:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'runtime.awiki.ai',
            ),
          ],
        ),
        localStore: InMemoryAwikiProductLocalStore(),
        agentInventory: const _ThrowingAgentInventory(),
      );

      final conversations = await service.listConversations(
        ownerDid: 'did:human:me',
      );

      expect(
        conversations.map((item) => item.threadId),
        containsAll(<String>[
          'dm:did:human:me:did:agent:runtime',
          'dm:peer-scope:v1:controller',
          'dm:peer-scope:v1:runtime',
        ]),
      );
    },
  );
}

ConversationSummary _conversation(
  String threadId, {
  required String targetDid,
  String? targetPeer,
  String? lastMessagePayloadJson,
  String lastMessagePreview = 'preview',
  DateTime? lastMessageAt,
  int unreadCount = 0,
}) {
  return ConversationSummary(
    threadId: threadId,
    conversationId: threadId,
    displayName: threadId,
    lastMessagePreview: lastMessagePreview,
    lastMessageAt: lastMessageAt ?? DateTime.utc(2026, 6, 4),
    unreadCount: unreadCount,
    isGroup: false,
    targetDid: targetDid,
    targetPeer: targetPeer,
    lastMessagePayloadJson: lastMessagePayloadJson,
  );
}

class _FakeConversations implements ConversationCorePort {
  @override
  Future<void> ensureConversation(String conversationId) async {}

  const _FakeConversations({required this.items});

  final List<ConversationSummary> items;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot() async {
    return const <ConversationSummary>[];
  }

  @override
  Future<void> clearConversationSnapshot() async {}

  @override
  Stream<CoreConversationPatch> watchConversationPatches() {
    return StreamController<CoreConversationPatch>().stream;
  }

  @override
  Future<CoreConversationPatch> repairConversationStore() async {
    return const CoreConversationPatch(
      kind: CoreConversationPatchKind.reset,
      ownerDid: 'did:owner',
      version: 1,
      unreadTotal: 0,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return (await listConversationPage(
      limit: limit,
      unreadOnly: unreadOnly,
    )).items;
  }

  @override
  Future<CoreConversationPage> listConversationPage({
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return CoreConversationPage(
      items: items.take(limit).toList(),
      hasMore: false,
    );
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {}
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
    required String preferredLanguage,
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
  Future<List<AgentSummary>> removeAgentFromAccount({
    required String agentDid,
  }) {
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
