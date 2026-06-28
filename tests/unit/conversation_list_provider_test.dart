import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
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

  test(
    'refreshFastLocal shows snapshot before SQLite hydrate finishes',
    () async {
      final hydrateCompleter = Completer<List<ConversationSummary>>();
      final service = _CompleterConversationService(
        snapshot: <ConversationSummary>[
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob snapshot',
            unreadCount: 4,
          ),
        ],
        hydrateCompleter: hydrateCompleter,
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

      final refresh = container
          .read(conversationListProvider.notifier)
          .refreshFastLocal();
      await Future<void>.delayed(Duration.zero);

      expect(service.snapshotCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'Bob snapshot',
      );
      expect(container.read(conversationListProvider).isLoading, isTrue);
      expect(notifications.lastBadgeCount, 4);

      hydrateCompleter.complete(<ConversationSummary>[
        _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob hydrate',
          unreadCount: 1,
        ),
      ]);
      await refresh;

      expect(service.fastCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'Bob hydrate',
      );
      expect(container.read(conversationListProvider).unreadCount, 1);
    },
  );

  test('conversation patch upsert updates one row and badge count', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 3,
        item: _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob',
          unreadCount: 3,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.displayName, 'Bob');
    expect(conversations.single.unreadCount, 3);
    expect(notifications.lastBadgeCount, 3);
    expect(service.watchCalls, 1);
  });

  test('conversation patch upsert respects local hidden waterline', () async {
    final seed = _conversation(
      threadId: 'dm:alice:bob',
      displayName: 'Bob',
      unreadCount: 1,
      lastMessageAt: DateTime.utc(2026, 6, 27, 2),
    );
    final service = _PatchConversationService(
      conversations: <ConversationSummary>[seed],
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    await notifier.refreshFastLocal();
    await notifier.deleteFromRecents(seed);

    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(notifications.lastBadgeCount, 0);

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 1,
        item: seed.copyWith(lastMessagePreview: 'stale hidden row'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(conversationListProvider).conversations, isEmpty);

    final newerMessageAt = DateTime.now().toUtc().add(
      const Duration(minutes: 1),
    );
    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 2,
        unreadTotal: 2,
        item: seed.copyWith(
          lastMessagePreview: 'new message after hide',
          lastMessageAt: newerMessageAt,
          unreadCount: 2,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.lastMessagePreview, 'new message after hide');
    expect(conversations.single.unreadCount, 2);
    expect(notifications.lastBadgeCount, 2);
  });

  test('conversation patch reorder moves existing row without repair', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();
    for (final patch in <ConversationListPatch>[
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 0,
        item: _conversation(
          threadId: 'thread-a',
          displayName: 'A',
          targetDid: 'did:a',
        ),
      ),
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 2,
        unreadTotal: 0,
        item: _conversation(
          threadId: 'thread-b',
          displayName: 'B',
          targetDid: 'did:b',
        ),
      ),
      const ConversationListPatch(
        kind: ConversationListPatchKind.reorder,
        ownerDid: 'did:alice',
        version: 3,
        unreadTotal: 0,
        threadId: 'thread-b',
        index: 0,
      ),
    ]) {
      service.emitPatch(patch);
      await Future<void>.delayed(Duration.zero);
    }

    expect(
      container
          .read(conversationListProvider)
          .conversations
          .map((item) => item.threadId),
      <String>['thread-b', 'thread-a'],
    );
    expect(service.repairCalls, 0);
  });

  test('conversation patch repairRequired falls back to repaired list', () async {
    final repaired = <ConversationSummary>[
      _conversation(
        threadId: 'dm:alice:carol',
        displayName: 'Carol repaired',
        unreadCount: 2,
      ),
    ];
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
      repaired: repaired,
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    service.emitPatch(
      const ConversationListPatch(
        kind: ConversationListPatchKind.repairRequired,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 2,
        reason: 'subscriber_lag',
      ),
    );
    await pumpEventQueue();

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(service.repairCalls, 1);
    expect(conversations, hasLength(1));
    expect(conversations.single.displayName, 'Carol repaired');
    expect(notifications.lastBadgeCount, 2);
  });

  test('conversation patch repair resumes from repaired version', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
      repaired: <ConversationSummary>[
        _conversation(
          threadId: 'thread-repaired',
          displayName: 'Repaired',
          targetDid: 'did:repaired',
        ),
      ],
      repairVersion: 5,
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    service.emitPatch(
      const ConversationListPatch(
        kind: ConversationListPatchKind.repairRequired,
        ownerDid: 'did:alice',
        version: 3,
        unreadTotal: 0,
        reason: 'subscriber_lag',
      ),
    );
    await pumpEventQueue();
    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 6,
        unreadTotal: 1,
        item: _conversation(
          threadId: 'thread-after-repair',
          displayName: 'After repair',
          targetDid: 'did:after-repair',
          unreadCount: 1,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.repairCalls, 1);
    expect(
      container
          .read(conversationListProvider)
          .conversations
          .map((item) => item.threadId),
      containsAll(<String>['thread-repaired', 'thread-after-repair']),
    );
  });

  test('conversation patch stream does not repopulate after clear', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    await notifier.refreshFastLocal();
    await notifier.clear();

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 1,
        item: _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob stale',
          unreadCount: 1,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(service.cancelled, isTrue);
  });

  test('fast hydrate removes stale snapshot-only conversations', () async {
    final service = _StaticConversationService(
      conversations: const <ConversationSummary>[],
      snapshot: <ConversationSummary>[
        _conversation(
          threadId: 'dm:alice:stale',
          displayName: 'Stale snapshot',
          targetDid: 'did:stale',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: <Override>[
        conversationServiceProvider.overrideWithValue(service),
        notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
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

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    expect(service.snapshotCalls, 1);
    expect(container.read(conversationListProvider).conversations, isEmpty);
  });

  test('snapshot bootstrap does not repopulate after clear', () async {
    final snapshotCompleter = Completer<List<ConversationSummary>>();
    final hydrateCompleter = Completer<List<ConversationSummary>>();
    final service = _CompleterConversationService(
      snapshot: const <ConversationSummary>[],
      snapshotCompleter: snapshotCompleter,
      hydrateCompleter: hydrateCompleter,
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

    final refresh = container.read(conversationListProvider.notifier);
    final refreshFuture = refresh.refreshFastLocal();
    await Future<void>.delayed(Duration.zero);

    await refresh.clear();
    snapshotCompleter.complete(<ConversationSummary>[
      _conversation(
        threadId: 'dm:alice:stale',
        displayName: 'Stale snapshot',
        unreadCount: 9,
      ),
    ]);
    hydrateCompleter.complete(const <ConversationSummary>[]);
    await refreshFuture;

    expect(service.snapshotCalls, 1);
    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(notifications.lastBadgeCount, 0);
  });
}

ConversationSummary _conversation({
  required String threadId,
  required String displayName,
  int unreadCount = 0,
  String targetDid = 'did:bob',
  String? targetPeer,
  DateTime? lastMessageAt,
}) {
  return ConversationSummary(
    threadId: threadId,
    displayName: displayName,
    lastMessagePreview: 'hello',
    lastMessageAt: lastMessageAt ?? DateTime.utc(2026, 6, 27, 2),
    unreadCount: unreadCount,
    isGroup: false,
    targetDid: targetDid,
    targetPeer: targetPeer,
  );
}

ProviderContainer _conversationContainer({
  required ConversationService service,
  required FakeNotificationFacade notifications,
  required String ownerDid,
}) {
  return ProviderContainer(
    overrides: <Override>[
      conversationServiceProvider.overrideWithValue(service),
      notificationFacadeProvider.overrideWithValue(notifications),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        controller.setSession(
          SessionIdentity(
            did: ownerDid,
            credentialName: 'alice',
            displayName: 'Alice',
          ),
        );
        return controller;
      }),
    ],
  );
}

class _SlowEnrichConversationService implements ConversationService {
  _SlowEnrichConversationService({required this.base, required this.enriched});

  final List<ConversationSummary> base;
  final List<ConversationSummary> enriched;
  final Completer<void> _enrichCompleter = Completer<void>();
  int fastCalls = 0;
  int snapshotCalls = 0;
  int enrichCalls = 0;

  void completeEnrichment() {
    if (!_enrichCompleter.isCompleted) {
      _enrichCompleter.complete();
    }
  }

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    snapshotCalls += 1;
    return const <ConversationSummary>[];
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return StreamController<ConversationListPatch>().stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(conversations: base, version: 1);
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
  _StaticConversationService({
    required this.conversations,
    this.snapshot = const <ConversationSummary>[],
  });

  final List<ConversationSummary> conversations;
  final List<ConversationSummary> snapshot;
  int fastCalls = 0;
  int listCalls = 0;
  int snapshotCalls = 0;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    snapshotCalls += 1;
    return snapshot;
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return StreamController<ConversationListPatch>().stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(
      conversations: conversations,
      version: 1,
    );
  }

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
    fastCalls += 1;
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

class _CompleterConversationService extends _StaticConversationService {
  _CompleterConversationService({
    required super.snapshot,
    this.snapshotCompleter,
    required this.hydrateCompleter,
  }) : super(conversations: const <ConversationSummary>[]);

  final Completer<List<ConversationSummary>>? snapshotCompleter;
  final Completer<List<ConversationSummary>> hydrateCompleter;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    snapshotCalls += 1;
    final completer = snapshotCompleter;
    if (completer != null) {
      return completer.future;
    }
    return snapshot;
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return hydrateCompleter.future;
  }
}

class _PatchConversationService extends _StaticConversationService {
  _PatchConversationService({
    required super.conversations,
    this.repaired = const <ConversationSummary>[],
    this.repairVersion = 1,
  });

  final List<ConversationSummary> repaired;
  final int repairVersion;
  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);
  int watchCalls = 0;
  int repairCalls = 0;
  bool cancelled = false;

  void emitPatch(ConversationListPatch patch) {
    _patches.add(patch);
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    watchCalls += 1;
    late final StreamController<ConversationListPatch> controller;
    late final StreamSubscription<ConversationListPatch> subscription;
    controller = StreamController<ConversationListPatch>(
      sync: true,
      onListen: () {
        subscription = _patches.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        cancelled = true;
        await subscription.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    repairCalls += 1;
    return ConversationStoreRepairResult(
      conversations: repaired,
      version: repairVersion,
    );
  }
}
