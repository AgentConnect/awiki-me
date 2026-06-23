import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/conversation_core_port.dart';
import 'package:awiki_me/src/application/ports/message_core_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
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

    test('hides recents by stable direct peer key', () async {
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
          threadId: 'direct:bob.anpclaw.com',
        ))?.hidden,
        isTrue,
      );
    });

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
    test('delegates send history and retry to message port', () async {
      final messages = _FakeMessages();
      final service = ImCoreMessagingService(messages: messages);
      const thread = AppThreadRef.direct('did:bob');

      await service.sendText(thread: thread, content: 'hello');
      await service.loadHistory(thread, limit: 20, cursor: 'cursor-1');
      await service.retryByResendOriginalContent(_message('failed'));

      expect(messages.sentContents, ['hello']);
      expect(messages.historyRequests.single.limit, 20);
      expect(messages.retriedIds, ['failed']);
    });
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
  _FakeConversations({this.items = const <ConversationSummary>[]});

  final List<ConversationSummary> items;
  int listCount = 0;
  int markReadCount = 0;

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    listCount += 1;
    return items.take(limit).toList();
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {
    markReadCount += 1;
  }
}

class _FakeMessages implements MessageCorePort {
  final List<String> sentContents = <String>[];
  final List<_HistoryRequest> historyRequests = <_HistoryRequest>[];
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
  }) async {
    historyRequests.add(_HistoryRequest(limit: limit, cursor: cursor));
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

class _HistoryRequest {
  const _HistoryRequest({required this.limit, this.cursor});

  final int limit;
  final String? cursor;
}
