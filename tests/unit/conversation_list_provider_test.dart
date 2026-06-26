import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test(
    'refreshFastLocal emits base conversations before enrichment finishes',
    () async {
      final service = _SlowEnrichConversationService(
        base: <ConversationSummary>[
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'did:bob',
            unreadCount: 2,
          ),
        ],
        enriched: <ConversationSummary>[
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob',
            unreadCount: 2,
          ),
        ],
      );
      final notifications = FakeNotificationFacade();
      final container = ProviderContainer(
        overrides: <Override>[
          conversationServiceProvider.overrideWithValue(service),
          notificationFacadeProvider.overrideWithValue(notifications),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:alice',
                credentialName: 'alice',
                displayName: 'Alice',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(conversationListProvider.notifier)
          .refreshFastLocal()
          .timeout(const Duration(milliseconds: 50));

      expect(service.fastCalls, 1);
      expect(service.enrichCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'did:bob',
      );
      expect(notifications.lastBadgeCount, 2);

      service.completeEnrichment();
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'Bob',
      );
    },
  );

  test(
    'refresh merge uses indexed identity and keeps one local row per target',
    () async {
      final baseTime = DateTime.utc(2026, 6, 27, 2);
      final local = <ConversationSummary>[
        for (var i = 0; i < 500; i += 1)
          _conversation(
            threadId: 'dm:local:$i',
            displayName: 'Local $i',
            targetDid: 'did:local:$i',
          ).copyWith(
            lastMessagePreview: 'local $i',
            lastMessageAt: baseTime.subtract(Duration(minutes: i + 1)),
          ),
        _conversation(
          threadId: 'dm:did:human:did:agent',
          displayName: 'Hermes',
          targetDid: 'did:agent',
          targetPeer: 'did:agent',
        ).copyWith(
          lastMessagePreview: '旧回复',
          lastMessageAt: baseTime,
          unreadCount: 0,
        ),
      ];
      final refreshed = <ConversationSummary>[
        _conversation(
          threadId: 'dm:peer-scope:v1:hermes',
          displayName: 'Hermes Remote',
          targetDid: 'did:agent',
          targetPeer: 'hermes.awiki.example',
        ).copyWith(
          lastMessagePreview: '新回复',
          lastMessageAt: baseTime.add(const Duration(minutes: 1)),
          unreadCount: 1,
        ),
      ];
      final service = _StaticConversationService(conversations: refreshed);
      final container = ProviderContainer(
        overrides: <Override>[
          conversationServiceProvider.overrideWithValue(service),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:human',
                credentialName: 'human',
                displayName: 'Human',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      for (final conversation in local) {
        notifier.upsertConversation(conversation);
      }

      await notifier.refresh();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(
        conversations.where((item) => item.targetDid == 'did:agent'),
        hasLength(1),
      );
      final merged = conversations.singleWhere(
        (item) => item.targetDid == 'did:agent',
      );
      expect(merged.threadId, 'dm:peer-scope:v1:hermes');
      expect(merged.lastMessagePreview, '新回复');
      expect(conversations.length, local.length);
      expect(service.listCalls, 1);
    },
  );
}

ConversationSummary _conversation({
  required String threadId,
  required String displayName,
  int unreadCount = 0,
  String targetDid = 'did:bob',
  String? targetPeer,
}) {
  return ConversationSummary(
    threadId: threadId,
    displayName: displayName,
    lastMessagePreview: 'hello',
    lastMessageAt: DateTime.utc(2026, 6, 27, 2),
    unreadCount: unreadCount,
    isGroup: false,
    targetDid: targetDid,
    targetPeer: targetPeer,
  );
}

class _SlowEnrichConversationService implements ConversationService {
  _SlowEnrichConversationService({required this.base, required this.enriched});

  final List<ConversationSummary> base;
  final List<ConversationSummary> enriched;
  final Completer<void> _enrichCompleter = Completer<void>();
  int fastCalls = 0;
  int enrichCalls = 0;

  void completeEnrichment() {
    if (!_enrichCompleter.isCompleted) {
      _enrichCompleter.complete();
    }
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return base;
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    enrichCalls += 1;
    await _enrichCompleter.future;
    return enriched;
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return base;
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {}

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}
}

class _StaticConversationService implements ConversationService {
  _StaticConversationService({required this.conversations});

  final List<ConversationSummary> conversations;
  int listCalls = 0;

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    listCalls += 1;
    return conversations;
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return conversations;
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    return conversations;
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {}

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}
}
