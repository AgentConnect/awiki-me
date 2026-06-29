import 'dart:async';

import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/conversation_core_port.dart';
import 'package:awiki_me/src/application/ports/message_core_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImCoreConversationService', () {
    test('applies product overlays without making them primary data', () async {
      final core = _FakeConversations(
        items: <ConversationSummary>[
          _conversation('thread-hidden', minutesAgo: 1),
          _conversation('thread-normal', minutesAgo: 2),
          _conversation('thread-pinned', minutesAgo: 10),
        ],
      );
      final store = InMemoryAwikiProductLocalStore();
      final now = DateTime.utc(2026, 5, 23, 9);
      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'thread-pinned',
          pinned: true,
          customTitle: 'Pinned title',
          avatarSeed: 'seed-pinned',
          updatedAt: now,
        ),
      );
      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'thread-hidden',
          hidden: true,
          updatedAt: now,
        ),
      );
      final service = ImCoreConversationService(
        conversations: core,
        localStore: store,
      );

      final conversations = await service.listConversations(
        ownerDid: 'did:alice',
      );

      expect(conversations.map((item) => item.threadId), [
        'thread-pinned',
        'thread-normal',
      ]);
      expect(conversations.first.displayName, 'Pinned title');
      expect(conversations.first.avatarSeed, 'seed-pinned');
      expect(core.listCount, 1);
    });

    test('markThreadRead delegates to core boundary', () async {
      final core = _FakeConversations();
      final service = ImCoreConversationService(
        conversations: core,
        localStore: InMemoryAwikiProductLocalStore(),
      );

      await service.markThreadRead(const AppThreadRef.direct('did:bob'));

      expect(core.markReadCount, 1);
    });

    test(
      'conversation page forwards cursor and preserves page metadata',
      () async {
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation('thread-2', minutesAgo: 2),
            _conversation('thread-3', minutesAgo: 3),
          ],
          nextCursor: 'cursor-3',
          hasMore: true,
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: InMemoryAwikiProductLocalStore(),
        );

        final page = await service.listConversationsPage(
          ownerDid: 'did:alice',
          limit: 2,
          cursor: 'cursor-1',
        );

        expect(core.listCount, 1);
        expect(core.lastLimit, 2);
        expect(core.lastCursor, 'cursor-1');
        expect(page.items.map((item) => item.threadId), [
          'thread-2',
          'thread-3',
        ]);
        expect(page.nextCursor, 'cursor-3');
        expect(page.hasMore, isTrue);
      },
    );

    test(
      'snapshot load applies app overlays without caching them in core',
      () async {
        final snapshotRow = _conversation(
          'dm:did:alice:did:bob',
          targetDid: 'did:bob',
          minutesAgo: 1,
          displayName: 'Bob from snapshot',
        );
        final hiddenSnapshotRow = _conversation(
          'dm:did:alice:did:stale',
          targetDid: 'did:stale',
          minutesAgo: 2,
          displayName: 'Stale from snapshot',
        );
        final core = _FakeConversations(
          snapshotItems: <ConversationSummary>[snapshotRow, hiddenSnapshotRow],
        );
        final store = InMemoryAwikiProductLocalStore();
        await store.upsertConversationOverlay(
          ProductConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'dm:did:alice:did:bob',
            customTitle: 'Bob local title',
            avatarSeed: 'local-seed',
            updatedAt: DateTime.utc(2026, 5, 23, 9),
          ),
        );
        await store.upsertConversationOverlay(
          ProductConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'dm:did:alice:did:stale',
            hidden: true,
            updatedAt: DateTime.utc(2026, 5, 23, 9),
          ),
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: store,
        );

        final conversations = await service.loadConversationSnapshot(
          ownerDid: 'did:alice',
        );

        expect(core.snapshotCount, 1);
        expect(core.listCount, 0);
        expect(conversations, hasLength(1));
        expect(conversations.single.displayName, 'Bob local title');
        expect(conversations.single.avatarSeed, 'local-seed');
        expect(snapshotRow.displayName, 'Bob from snapshot');
        expect(snapshotRow.avatarSeed, isNull);
      },
    );

    test('snapshot load applies pinned sort using app overlays', () async {
      final recentRow = _conversation(
        'thread-recent',
        minutesAgo: 1,
        displayName: 'Recent',
      );
      final pinnedRow = _conversation(
        'thread-pinned',
        minutesAgo: 20,
        displayName: 'Pinned from snapshot',
      );
      final core = _FakeConversations(
        snapshotItems: <ConversationSummary>[recentRow, pinnedRow],
      );
      final store = InMemoryAwikiProductLocalStore();
      await store.upsertConversationOverlay(
        ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'thread-pinned',
          pinned: true,
          customTitle: 'Pinned local',
          updatedAt: DateTime.utc(2026, 5, 23, 9),
        ),
      );
      final service = ImCoreConversationService(
        conversations: core,
        localStore: store,
      );

      final conversations = await service.loadConversationSnapshot(
        ownerDid: 'did:alice',
      );

      expect(conversations.map((item) => item.threadId), [
        'thread-pinned',
        'thread-recent',
      ]);
      expect(conversations.first.displayName, 'Pinned local');
      expect(pinnedRow.displayName, 'Pinned from snapshot');
    });

    test(
      'watchConversationPatches normalizes upsert and repair patches',
      () async {
        final core = _FakeConversations();
        final store = InMemoryAwikiProductLocalStore();
        await store.upsertConversationOverlay(
          ProductConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'thread-patched',
            customTitle: 'Patched local title',
            updatedAt: DateTime.utc(2026, 5, 23, 9),
          ),
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: store,
        );
        final patchStream = service.watchConversationPatches(
          ownerDid: 'did:alice',
        );
        final firstPatch = patchStream.first;
        await Future<void>.delayed(Duration.zero);

        core.emitPatch(
          CoreConversationPatch(
            kind: CoreConversationPatchKind.upsert,
            ownerDid: 'did:alice',
            version: 1,
            unreadTotal: 1,
            item: _conversation(
              'thread-patched',
              minutesAgo: 1,
              displayName: 'Patched core title',
            ),
          ),
        );
        final patch = await firstPatch.timeout(const Duration(seconds: 1));
        expect(patch.kind, ConversationListPatchKind.upsert);
        expect(patch.item?.displayName, 'Patched local title');

        final repairPatchStream = service.watchConversationPatches(
          ownerDid: 'did:alice',
        );
        final repairPatchFuture = repairPatchStream.first;
        await Future<void>.delayed(Duration.zero);
        core.emitPatch(
          const CoreConversationPatch(
            kind: CoreConversationPatchKind.repairRequired,
            ownerDid: 'did:alice',
            version: 2,
            unreadTotal: 1,
            reason: 'subscriber_lag',
          ),
        );
        final repairPatch = await repairPatchFuture.timeout(
          const Duration(seconds: 1),
        );
        expect(repairPatch.kind, ConversationListPatchKind.repairRequired);
        expect(repairPatch.reason, 'subscriber_lag');

        final reorderPatchStream = service.watchConversationPatches(
          ownerDid: 'did:alice',
        );
        final reorderPatchFuture = reorderPatchStream.first;
        await Future<void>.delayed(Duration.zero);
        core.emitPatch(
          const CoreConversationPatch(
            kind: CoreConversationPatchKind.reorder,
            ownerDid: 'did:alice',
            version: 3,
            unreadTotal: 1,
            threadId: 'thread-patched',
            index: 0,
          ),
        );
        final reorderPatch = await reorderPatchFuture.timeout(
          const Duration(seconds: 1),
        );
        expect(reorderPatch.kind, ConversationListPatchKind.reorder);
        expect(reorderPatch.threadId, 'thread-patched');
        expect(reorderPatch.index, 0);

        await service.repairConversationStore(ownerDid: 'did:alice');
        expect(core.repairCount, 1);
      },
    );

    test(
      'snapshot load merges cached runtime DID and handle agent rows',
      () async {
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:did:human:did:agent:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'did:agent:runtime',
              minutesAgo: 2,
              displayName: 'zhuocheng-test-hermes',
            ),
          ],
          snapshotItems: <ConversationSummary>[
            _conversation(
              'dm:did:human:did:agent:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'did:agent:runtime',
              minutesAgo: 2,
              displayName: 'zhuocheng-test-hermes',
            ),
            _conversation(
              'dm:peer-scope:v1:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'zhuocheng-test-hermes.anpclaw.com',
              minutesAgo: 1,
              displayName: 'zhuocheng-test-hermes.anpclaw.com',
            ),
          ],
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: InMemoryAwikiProductLocalStore(),
          agentInventory: const _FakeAgentInventory(
            agents: <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                handle: 'zhuocheng-test-hermes',
                displayName: '改名后的智能体',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ],
          ),
        );

        await service.listConversations(ownerDid: 'did:human');
        final conversations = await service.loadConversationSnapshot(
          ownerDid: 'did:human',
        );

        expect(core.snapshotCount, 1);
        expect(conversations, hasLength(1));
        expect(conversations.single.threadId, 'dm:peer-scope:v1:runtime');
        expect(conversations.single.targetDid, 'did:agent:runtime');
        expect(
          conversations.single.targetPeer,
          'zhuocheng-test-hermes.anpclaw.com',
        );
        expect(conversations.single.displayName, '改名后的智能体');
      },
    );

    test(
      'fast local summaries do not wait for agent inventory projection',
      () async {
        final inventory = _BlockingAgentInventory(
          agents: const <AgentSummary>[
            AgentSummary(
              agentDid: 'did:agent:daemon',
              kind: AgentKind.daemon,
              displayName: '代理',
              activeState: 'active',
              latest: AgentLatestStatus(status: 'ready'),
            ),
          ],
        );
        final service = ImCoreConversationService(
          conversations: _FakeConversations(
            items: <ConversationSummary>[
              _conversation(
                'dm:alice:daemon',
                targetDid: 'did:agent:daemon',
                minutesAgo: 1,
              ),
              _conversation('dm:alice:bob', minutesAgo: 2),
            ],
          ),
          localStore: InMemoryAwikiProductLocalStore(),
          agentInventory: inventory,
        );

        final fast = await service
            .listConversationSummariesFast(ownerDid: 'did:alice')
            .timeout(const Duration(milliseconds: 50));

        expect(fast.map((item) => item.threadId), [
          'dm:alice:daemon',
          'dm:alice:bob',
        ]);
        expect(inventory.listCount, 0);
      },
    );

    test(
      'fast local summaries apply product overlays before enrichment',
      () async {
        final store = InMemoryAwikiProductLocalStore();
        final now = DateTime.utc(2026, 5, 23, 9);
        await store.upsertConversationOverlay(
          ProductConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'thread-hidden',
            hidden: true,
            updatedAt: now,
          ),
        );
        await store.upsertConversationOverlay(
          ProductConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'thread-pinned',
            pinned: true,
            customTitle: 'Pinned local title',
            avatarSeed: 'pinned-seed',
            updatedAt: now,
          ),
        );
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation('thread-hidden', minutesAgo: 1),
            _conversation('thread-normal', minutesAgo: 2),
            _conversation('thread-pinned', minutesAgo: 10),
          ],
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: store,
        );

        final conversations = await service.listConversationSummariesFast(
          ownerDid: 'did:alice',
        );

        expect(core.listCount, 1);
        expect(conversations.map((item) => item.threadId), [
          'thread-pinned',
          'thread-normal',
        ]);
        expect(conversations.first.displayName, 'Pinned local title');
        expect(conversations.first.avatarSeed, 'pinned-seed');
      },
    );

    test(
      'enrichment applies delayed agent projection and product overlays',
      () async {
        final inventory = _BlockingAgentInventory(
          agents: const <AgentSummary>[
            AgentSummary(
              agentDid: 'did:agent:daemon',
              kind: AgentKind.daemon,
              displayName: '代理',
              activeState: 'active',
              latest: AgentLatestStatus(status: 'ready'),
            ),
            AgentSummary(
              agentDid: 'did:agent:runtime',
              kind: AgentKind.runtime,
              daemonAgentDid: 'did:agent:daemon',
              runtime: 'hermes',
              displayName: '写作助手',
              activeState: 'active',
              latest: AgentLatestStatus(status: 'ready'),
            ),
          ],
        );
        final store = InMemoryAwikiProductLocalStore();
        await store.upsertConversationOverlay(
          ProductConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'thread-pinned',
            pinned: true,
            customTitle: '置顶会话',
            updatedAt: DateTime.utc(2026, 6, 27),
          ),
        );
        final service = ImCoreConversationService(
          conversations: _FakeConversations(),
          localStore: store,
          agentInventory: inventory,
        );
        final base = <ConversationSummary>[
          _conversation(
            'dm:alice:daemon',
            targetDid: 'did:agent:daemon',
            minutesAgo: 1,
          ),
          _conversation(
            'dm:alice:runtime',
            targetDid: 'did:agent:runtime',
            displayName: 'runtime-handle',
            minutesAgo: 2,
          ),
          _conversation('thread-pinned', minutesAgo: 20),
        ];

        final enriching = service.enrichConversationSummaries(
          ownerDid: 'did:alice',
          conversations: base,
        );
        expect(inventory.listCount, 1);
        inventory.complete();
        final enriched = await enriching;

        expect(enriched.map((item) => item.threadId), [
          'thread-pinned',
          'dm:alice:runtime',
        ]);
        expect(enriched.first.displayName, '置顶会话');
        expect(enriched.last.displayName, '写作助手');
      },
    );

    test(
      'hides recents by stable direct DID and keeps handle as fallback',
      () async {
        final conversation = _conversation(
          'dm:alice:old-did',
          targetDid: 'did:old-bob',
          targetPeer: 'bob.anpclaw.com',
          minutesAgo: 1,
        );
        final core = _FakeConversations(
          items: <ConversationSummary>[conversation],
        );
        final store = InMemoryAwikiProductLocalStore();
        final service = ImCoreConversationService(
          conversations: core,
          localStore: store,
        );

        await service.hideConversationFromRecents(
          ownerDid: 'did:alice',
          conversation: conversation,
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:alice',
        );

        expect(conversations, isEmpty);
        expect(
          (await store.loadConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'direct-did:did:old-bob',
          ))?.hidden,
          isTrue,
        );
        expect(
          (await store.loadConversationOverlay(
            ownerDid: 'did:alice',
            threadId: 'direct-handle:bob.anpclaw.com',
          ))?.hidden,
          isTrue,
        );
      },
    );

    test(
      'does not hide a newer message after local delete waterline',
      () async {
        final conversation = _conversation(
          'dm:alice:old-did',
          targetDid: 'did:old-bob',
          targetPeer: 'bob.anpclaw.com',
          minutesAgo: 1,
        );
        final newerConversation = _conversation(
          'dm:alice:old-did',
          targetDid: 'did:old-bob',
          targetPeer: 'bob.anpclaw.com',
          minutesAgo: 0,
        );
        final store = InMemoryAwikiProductLocalStore();
        final service = ImCoreConversationService(
          conversations: _FakeConversations(
            items: <ConversationSummary>[newerConversation],
          ),
          localStore: store,
        );

        await service.hideConversationFromRecents(
          ownerDid: 'did:alice',
          conversation: conversation,
          updatedAt: DateTime.utc(2026, 5, 23, 8, 59, 30),
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:alice',
        );

        expect(conversations, hasLength(1));
        expect(conversations.single.threadId, 'dm:alice:old-did');
      },
    );

    test('restores hidden direct conversation when opened again', () async {
      final conversation = _conversation(
        'dm:alice:old-did',
        targetDid: 'did:old-bob',
        targetPeer: 'bob.anpclaw.com',
        minutesAgo: 1,
      );
      final core = _FakeConversations(
        items: <ConversationSummary>[conversation],
      );
      final store = InMemoryAwikiProductLocalStore();
      final service = ImCoreConversationService(
        conversations: core,
        localStore: store,
      );

      await service.hideConversationFromRecents(
        ownerDid: 'did:alice',
        conversation: conversation,
      );
      await service.restoreConversationToRecents(
        ownerDid: 'did:alice',
        conversation: conversation,
      );

      final conversations = await service.listConversations(
        ownerDid: 'did:alice',
      );

      expect(conversations.map((item) => item.threadId), ['dm:alice:old-did']);
    });

    test('filters known daemon agent control conversations', () async {
      final core = _FakeConversations(
        items: <ConversationSummary>[
          _conversation(
            'dm:alice:daemon',
            targetDid: 'did:agent:daemon',
            minutesAgo: 1,
          ),
          _conversation(
            'dm:alice:runtime',
            targetDid: 'did:agent:runtime',
            minutesAgo: 2,
          ),
          _conversation('dm:alice:bob', targetDid: 'did:bob', minutesAgo: 3),
        ],
      );
      final service = ImCoreConversationService(
        conversations: core,
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
        ownerDid: 'did:alice',
      );

      expect(conversations.map((item) => item.targetDid), [
        'did:agent:runtime',
        'did:bob',
      ]);
      expect(core.listCount, 1);
    });

    test(
      'keeps archived runtime conversations and marks them deleted',
      () async {
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:alice:daemon',
              targetDid: 'did:agent:daemon',
              minutesAgo: 1,
            ),
            _conversation(
              'dm:alice:runtime',
              targetDid: 'did:agent:runtime',
              minutesAgo: 2,
            ),
            _conversation('dm:alice:bob', targetDid: 'did:bob', minutesAgo: 3),
          ],
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: InMemoryAwikiProductLocalStore(),
          agentInventory: const _FakeAgentInventory(
            agents: <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:daemon',
                kind: AgentKind.daemon,
                displayName: '代理 1',
                activeState: 'archived',
                latest: AgentLatestStatus(status: 'archived'),
              ),
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                displayName: 'Hermes',
                activeState: 'archived',
                latest: AgentLatestStatus(status: 'archived'),
              ),
            ],
          ),
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:alice',
        );

        expect(conversations.map((item) => item.targetDid), [
          'did:agent:runtime',
          'did:bob',
        ]);
        expect(conversations.first.isDeletedAgentConversation, isTrue);
        expect(conversations.last.isDeletedAgentConversation, isFalse);
      },
    );

    test(
      'projects runtime agent display name onto direct conversations',
      () async {
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:alice:runtime',
              targetDid: 'did:agent:runtime',
              minutesAgo: 1,
              displayName: 'awiki-agent-random',
            ),
          ],
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: InMemoryAwikiProductLocalStore(),
          agentInventory: const _FakeAgentInventory(
            agents: <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                displayName: '写作助手',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ],
          ),
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:alice',
        );

        expect(conversations.single.displayName, '写作助手');
      },
    );

    test(
      'merges runtime DID and handle conversations into one current agent row',
      () async {
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:did:human:did:agent:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'did:agent:runtime',
              minutesAgo: 2,
              displayName: 'zhuocheng-test-hermes',
            ),
            _conversation(
              'dm:peer-scope:v1:runtime',
              targetDid: 'did:agent:runtime',
              targetPeer: 'zhuocheng-test-hermes.anpclaw.com',
              minutesAgo: 1,
              displayName: 'zhuocheng-test-hermes.anpclaw.com',
            ),
          ],
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: InMemoryAwikiProductLocalStore(),
          agentInventory: const _FakeAgentInventory(
            agents: <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                handle: 'zhuocheng-test-hermes',
                displayName: '改名后的智能体',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ],
          ),
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:human',
        );

        expect(conversations, hasLength(1));
        expect(conversations.single.threadId, 'dm:peer-scope:v1:runtime');
        expect(conversations.single.targetDid, 'did:agent:runtime');
        expect(
          conversations.single.targetPeer,
          'zhuocheng-test-hermes.anpclaw.com',
        );
        expect(conversations.single.displayName, '改名后的智能体');
      },
    );

    test(
      'hides merged runtime conversation by agent key across DID and handle rows',
      () async {
        final didRow = _conversation(
          'dm:did:human:did:agent:runtime',
          targetDid: 'did:agent:runtime',
          targetPeer: 'did:agent:runtime',
          minutesAgo: 2,
          displayName: 'zhuocheng-test-hermes',
        );
        final handleRow = _conversation(
          'dm:peer-scope:v1:runtime',
          targetDid: 'did:agent:runtime',
          targetPeer: 'zhuocheng-test-hermes.anpclaw.com',
          minutesAgo: 1,
          displayName: 'zhuocheng-test-hermes.anpclaw.com',
        );
        final core = _FakeConversations(
          items: <ConversationSummary>[didRow, handleRow],
        );
        final store = InMemoryAwikiProductLocalStore();
        final service = ImCoreConversationService(
          conversations: core,
          localStore: store,
          agentInventory: const _FakeAgentInventory(
            agents: <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                handle: 'zhuocheng-test-hermes',
                displayName: '改名后的智能体',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ],
          ),
        );

        final merged = await service.listConversations(ownerDid: 'did:human');
        await service.hideConversationFromRecents(
          ownerDid: 'did:human',
          conversation: merged.single,
        );
        final conversations = await service.listConversations(
          ownerDid: 'did:human',
        );

        expect(merged.single.visibilityKey, 'runtime:did:agent:runtime');
        for (final key in <String>[
          'runtime:did:agent:runtime',
          'direct:did:agent:runtime',
          'direct-handle:zhuocheng-test-hermes.anpclaw.com',
          'direct-handle:zhuocheng-test-hermes',
          'dm:peer-scope:v1:runtime',
        ]) {
          expect(
            (await store.loadConversationOverlay(
              ownerDid: 'did:human',
              threadId: key,
            ))?.hidden,
            isTrue,
            reason: key,
          );
        }
        expect(conversations, isEmpty);
      },
    );

    test(
      'does not merge different DIDs that temporarily share one handle',
      () async {
        final core = _FakeConversations(
          items: <ConversationSummary>[
            _conversation(
              'dm:alice:old-bob',
              targetDid: 'did:old-bob',
              targetPeer: 'bob.anpclaw.com',
              minutesAgo: 2,
            ),
            _conversation(
              'dm:alice:new-bob',
              targetDid: 'did:new-bob',
              targetPeer: 'bob.anpclaw.com',
              minutesAgo: 1,
            ),
          ],
        );
        final service = ImCoreConversationService(
          conversations: core,
          localStore: InMemoryAwikiProductLocalStore(),
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:alice',
        );

        expect(conversations, hasLength(2));
        expect(
          conversations.map((conversation) => conversation.conversationKey),
          containsAll(<String>[
            'direct-did:did:old-bob',
            'direct-did:did:new-bob',
          ]),
        );
      },
    );

    test(
      'hidden DID conversation also suppresses an older handle-only projection',
      () async {
        final conversation = _conversation(
          'dm:alice:old-bob',
          targetDid: 'did:old-bob',
          targetPeer: 'bob.anpclaw.com',
          minutesAgo: 1,
        );
        final handleOnlyConversation = _conversation(
          'dm:peer-scope:bob',
          targetDid: '',
          targetPeer: 'bob.anpclaw.com',
          minutesAgo: 1,
        );
        final store = InMemoryAwikiProductLocalStore();
        final service = ImCoreConversationService(
          conversations: _FakeConversations(
            items: <ConversationSummary>[handleOnlyConversation],
          ),
          localStore: store,
        );

        await service.hideConversationFromRecents(
          ownerDid: 'did:alice',
          conversation: conversation,
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:alice',
        );

        expect(conversations, isEmpty);
      },
    );

    test(
      'keeps runtime conversation hidden when agent projection is unavailable',
      () async {
        final didRow = _conversation(
          'dm:did:human:did:agent:runtime',
          targetDid: 'did:agent:runtime',
          targetPeer: 'did:agent:runtime',
          minutesAgo: 1,
          displayName: 'zhuocheng-test-hermes',
        );
        final store = InMemoryAwikiProductLocalStore();
        await store.setConversationHidden(
          ownerDid: 'did:human',
          conversationKey: 'runtime:did:agent:runtime',
          hidden: true,
          updatedAt: DateTime.utc(2026, 5, 23, 9),
        );
        final service = ImCoreConversationService(
          conversations: _FakeConversations(
            items: <ConversationSummary>[didRow],
          ),
          localStore: store,
        );

        final conversations = await service.listConversations(
          ownerDid: 'did:human',
        );

        expect(conversations, isEmpty);
      },
    );

    test(
      'restores hidden runtime conversation by agent key from a raw row',
      () async {
        final didRow = _conversation(
          'dm:did:human:did:agent:runtime',
          targetDid: 'did:agent:runtime',
          targetPeer: 'did:agent:runtime',
          minutesAgo: 2,
          displayName: 'zhuocheng-test-hermes',
        );
        final handleRow = _conversation(
          'dm:peer-scope:v1:runtime',
          targetDid: 'did:agent:runtime',
          targetPeer: 'zhuocheng-test-hermes.anpclaw.com',
          minutesAgo: 1,
          displayName: 'zhuocheng-test-hermes.anpclaw.com',
        );
        final core = _FakeConversations(
          items: <ConversationSummary>[didRow, handleRow],
        );
        final store = InMemoryAwikiProductLocalStore();
        final service = ImCoreConversationService(
          conversations: core,
          localStore: store,
          agentInventory: const _FakeAgentInventory(
            agents: <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                handle: 'zhuocheng-test-hermes',
                displayName: '改名后的智能体',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ],
          ),
        );

        final merged = await service.listConversations(ownerDid: 'did:human');
        await service.hideConversationFromRecents(
          ownerDid: 'did:human',
          conversation: merged.single,
        );
        await service.restoreConversationToRecents(
          ownerDid: 'did:human',
          conversation: didRow,
        );
        final conversations = await service.listConversations(
          ownerDid: 'did:human',
        );

        expect(
          (await store.loadConversationOverlay(
            ownerDid: 'did:human',
            threadId: 'runtime:did:agent:runtime',
          ))?.hidden,
          isFalse,
        );
        expect(conversations, hasLength(1));
        expect(conversations.single.visibilityKey, 'runtime:did:agent:runtime');
      },
    );
  });

  group('ImCoreMessagingService', () {
    test(
      'delegates send history local history and retry to message port',
      () async {
        final messages = _FakeMessages();
        final service = ImCoreMessagingService(messages: messages);
        const thread = AppThreadRef.direct('did:bob');

        await service.sendText(thread: thread, content: 'hello');
        await service.loadHistory(thread, limit: 20, cursor: 'cursor-1');
        await service.loadLocalHistory(
          thread,
          limit: 10,
          cursor: 'cursor-local',
        );
        await service.retryByResendOriginalContent(_message('failed'));

        expect(messages.sentContents, ['hello']);
        expect(messages.historyRequests.single.limit, 20);
        expect(messages.localHistoryRequests.single.limit, 10);
        expect(messages.localHistoryRequests.single.cursor, 'cursor-local');
        expect(messages.retriedIds, ['failed']);
      },
    );
  });
}

ConversationSummary _conversation(
  String threadId, {
  required int minutesAgo,
  String targetDid = 'did:bob',
  String? targetPeer,
  String? displayName,
}) {
  return ConversationSummary(
    threadId: threadId,
    displayName: displayName ?? threadId,
    lastMessagePreview: 'preview',
    lastMessageAt: DateTime.utc(
      2026,
      5,
      23,
      9,
    ).subtract(Duration(minutes: minutesAgo)),
    unreadCount: 0,
    isGroup: false,
    targetDid: targetDid,
    targetPeer: targetPeer,
  );
}

ChatMessage _message(String id) {
  return ChatMessage(
    localId: id,
    threadId: 'dm:alice:bob',
    senderDid: 'did:alice',
    receiverDid: 'did:bob',
    content: 'hello again',
    createdAt: DateTime.utc(2026, 5, 23),
    isMine: true,
    sendState: MessageSendState.failed,
  );
}

class _FakeConversations implements ConversationCorePort {
  _FakeConversations({
    this.items = const <ConversationSummary>[],
    this.snapshotItems = const <ConversationSummary>[],
    this.nextCursor,
    this.hasMore = false,
  });

  final List<ConversationSummary> items;
  final List<ConversationSummary> snapshotItems;
  final String? nextCursor;
  final bool hasMore;
  final StreamController<CoreConversationPatch> _patches =
      StreamController<CoreConversationPatch>.broadcast(sync: true);
  int listCount = 0;
  int snapshotCount = 0;
  int markReadCount = 0;
  int repairCount = 0;
  int? lastLimit;
  String? lastCursor;

  void emitPatch(CoreConversationPatch patch) {
    _patches.add(patch);
  }

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot() async {
    snapshotCount += 1;
    return snapshotItems;
  }

  @override
  Future<void> clearConversationSnapshot() async {}

  @override
  Stream<CoreConversationPatch> watchConversationPatches() {
    return _patches.stream;
  }

  @override
  Future<CoreConversationPatch> repairConversationStore() async {
    repairCount += 1;
    return const CoreConversationPatch(
      kind: CoreConversationPatchKind.reset,
      ownerDid: 'did:alice',
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
    listCount += 1;
    lastLimit = limit;
    lastCursor = cursor;
    return CoreConversationPage(
      items: items.take(limit).toList(),
      nextCursor: nextCursor,
      hasMore: hasMore,
    );
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {
    markReadCount += 1;
  }
}

class _FakeMessages implements MessageCorePort, LocalHistoryMessageCorePort {
  final List<String> sentContents = <String>[];
  final List<_HistoryRequest> historyRequests = <_HistoryRequest>[];
  final List<_HistoryRequest> localHistoryRequests = <_HistoryRequest>[];
  final List<String> retriedIds = <String>[];

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) async =>
      AttachmentDownloadResult(attachmentId: attachmentId ?? 'attachment-1');

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    historyRequests.add(_HistoryRequest(limit: limit, cursor: cursor));
    return <ChatMessage>[];
  }

  @override
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    localHistoryRequests.add(_HistoryRequest(limit: limit, cursor: cursor));
    return <ChatMessage>[];
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) async {
    retriedIds.add(failed.localId);
    return failed.copyWith(sendState: MessageSendState.sending);
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  }) async {
    return _message(caption ?? attachment.filename);
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    return _message('');
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    sentContents.add(content);
    return _message('sent');
  }
}

class _FakeAgentInventory implements AgentInventoryPort {
  const _FakeAgentInventory({required this.agents});

  final List<AgentSummary> agents;

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

class _BlockingAgentInventory implements AgentInventoryPort {
  _BlockingAgentInventory({required this.agents});

  final List<AgentSummary> agents;
  final Completer<void> _completer = Completer<void>();
  int listCount = 0;

  void complete() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
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
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listCount += 1;
    await _completer.future;
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

class _HistoryRequest {
  const _HistoryRequest({required this.limit, this.cursor});

  final int limit;
  final String? cursor;
}
