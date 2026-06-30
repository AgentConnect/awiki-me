part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyPerformanceRegression({
  required WidgetTester tester,
  required Duration bootstrapCreateElapsed,
  required Duration shellVisibleElapsed,
  required _PerformanceWarmupResult warmup,
  required MessagingService messaging,
  required MessageSyncService messageSync,
  required _CountingConversationService conversations,
  required AppThreadRef thread,
  required String ownerDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final recorder = _E2ePerformanceRecorder(config: config);
  recorder.record(
    'app.bootstrap_create_ms',
    bootstrapCreateElapsed,
    source: 'app',
  );
  recorder.record(
    'app.launch_to_shell_visible_ms',
    shellVisibleElapsed,
    source: 'ui',
  );
  recorder.record(
    'performance_dataset.prepare_ms',
    warmup.datasetElapsed,
    source: 'tooling',
    fields: <String, Object?>{
      'existing': warmup.datasetExistingCount,
      'created': warmup.datasetCreatedCount,
      'target': config.performance.datasetConversationCount,
    },
  );
  recorder.counter(
    'performance_dataset.existing_count',
    warmup.datasetExistingCount,
  );
  recorder.counter(
    'performance_dataset.created_count',
    warmup.datasetCreatedCount,
  );
  recorder.record(
    'conversation_list.remote_sync_warmup_ms',
    warmup.syncElapsed,
    source: 'app',
    fields: <String, Object?>{
      'eventsApplied': warmup.eventsApplied,
      'pagesFetched': warmup.pagesFetched,
      'snapshotRequired': warmup.snapshotRequired,
      'hasMore': warmup.hasMore,
      'warnings': warmup.warnings,
    },
  );
  recorder.record(
    'conversation_list.warmup_fast_local_ms',
    warmup.summaryElapsed,
    source: 'app',
    fields: <String, Object?>{'items': warmup.localConversationCount},
  );
  recorder.metric(
    'conversation_list.warmup_item_count',
    warmup.localConversationCount,
  );
  recorder.counter('message_sync.warmup_events_applied', warmup.eventsApplied);
  recorder.counter('message_sync.warmup_pages_fetched', warmup.pagesFetched);
  recorder.counter(
    'message_sync.warmup_snapshot_required_count',
    warmup.snapshotRequired ? 1 : 0,
  );
  recorder.counter(
    'message_sync.warmup_has_more_count',
    warmup.hasMore ? 1 : 0,
  );

  final initialConversations = await recorder.measureList(
    'conversation_list.snapshot_load_ms',
    () => conversations.loadConversationSnapshot(ownerDid: ownerDid),
    source: 'app',
  );
  final fastLocalConversations = await recorder.measureList(
    'conversation_list.fast_local_hydrate_ms',
    () => conversations.listConversationSummariesFast(
      ownerDid: ownerDid,
      limit: _conversationPageSize(config.performance.datasetConversationCount),
    ),
    source: 'app',
  );
  final hydratedConversations = await recorder.measureList(
    'conversation_list.full_hydrate_ms',
    () => conversations.listConversations(
      ownerDid: ownerDid,
      limit: _conversationPageSize(config.performance.datasetConversationCount),
    ),
    source: 'app',
  );
  final fastLocalPageScan = await _measureConversationPageScan(
    recorder: recorder,
    metricName: 'conversation_list.fast_local_page_scan_ms',
    pageCounterName: 'conversation_list.fast_local_pages_fetched',
    itemMetricName: 'conversation_list.fast_local_paged_item_count',
    target: config.performance.datasetConversationCount,
    source: 'app',
    fetchPage: ({required int limit, required String? cursor}) {
      return conversations.listConversationSummariesFastPage(
        ownerDid: ownerDid,
        limit: limit,
        cursor: cursor,
      );
    },
  );
  final hydratedPageScan = await _measureConversationPageScan(
    recorder: recorder,
    metricName: 'conversation_list.full_page_scan_ms',
    pageCounterName: 'conversation_list.full_pages_fetched',
    itemMetricName: 'conversation_list.full_paged_item_count',
    target: config.performance.datasetConversationCount,
    source: 'app',
    fetchPage: ({required int limit, required String? cursor}) {
      return conversations.listConversationsPage(
        ownerDid: ownerDid,
        limit: limit,
        cursor: cursor,
      );
    },
  );
  recorder.metric(
    'conversation_list.snapshot_item_count',
    initialConversations.length,
  );
  recorder.metric(
    'conversation_list.fast_local_item_count',
    fastLocalConversations.length,
  );
  recorder.metric(
    'conversation_list.full_hydrate_item_count',
    hydratedConversations.length,
  );
  recorder.metric(
    'conversation_list.first_non_empty_visible_ms',
    _firstNonEmptyMs(
      shellVisibleElapsed: shellVisibleElapsed,
      snapshotCount: initialConversations.length,
      fastLocalCount: fastLocalConversations.length,
      hydrateCount: hydratedConversations.length,
      snapshotMs: recorder.metricValue('conversation_list.snapshot_load_ms'),
      fastLocalMs: recorder.metricValue(
        'conversation_list.fast_local_hydrate_ms',
      ),
      hydrateMs: recorder.metricValue('conversation_list.full_hydrate_ms'),
    ),
  );

  recorder.record(
    'performance_dataset.long_thread_prepare_ms',
    warmup.longThreadElapsed,
    source: 'tooling',
    fields: <String, Object?>{
      'initial': warmup.longThreadInitialCount,
      'created': warmup.longThreadCreatedCount,
      'observed': warmup.longThreadObservedCount,
      'target': config.performance.longThreadMessageCount,
    },
  );
  recorder.counter(
    'performance_dataset.long_thread_initial_count',
    warmup.longThreadInitialCount,
  );
  recorder.counter(
    'performance_dataset.long_thread_created_count',
    warmup.longThreadCreatedCount,
  );
  recorder.counter(
    'performance_dataset.long_thread_observed_count',
    warmup.longThreadObservedCount,
  );

  final appToCliText = 'perf app to cli ${config.runId} $nonce';
  final cliToAppText = 'perf cli to app ${config.runId} $nonce';

  conversations.resetCounters();
  conversations.beginSendReceiveWindow();
  final appSendWatch = Stopwatch()..start();
  final appMessage = await messaging.sendText(
    thread: thread,
    content: appToCliText,
  );
  final appMessageId = appMessage.remoteId ?? appMessage.localId;
  recorder.metric(
    'message.app_send_to_local_visible_ms',
    appSendWatch.elapsedMilliseconds,
  );
  await _waitForCliInbox(
    config: config,
    expectedText: appToCliText,
    expectedMessageId: appMessageId,
  );
  recorder.metric(
    'message.app_send_to_cli_inbox_visible_ms',
    appSendWatch.elapsedMilliseconds,
  );
  await _waitForCliHistory(
    config: config,
    peerHandle: config.appHandle,
    expectedText: appToCliText,
    expectedMessageId: appMessageId,
  );
  appSendWatch.stop();
  recorder.metric(
    'message.app_send_to_cli_history_visible_ms',
    appSendWatch.elapsedMilliseconds,
  );

  final cliSendWatch = Stopwatch()..start();
  final cliSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--to',
    config.appHandle,
    '--text',
    cliToAppText,
  ]);
  if (cliSend.exitCode != 0) {
    fail('CLI performance msg send failed: ${_summarizeCliResult(cliSend)}');
  }
  final cliSentMessageId = _jsonStringAt(cliSend.stdout, const <Object>[
    'data',
    'message',
    'id',
  ]);
  expect(cliSentMessageId, isNotNull);
  final conversationForCliMessage = await _waitForAppConversationPreviewFast(
    conversations: conversations,
    ownerDid: ownerDid,
    expectedText: cliToAppText,
  );
  recorder.metric(
    'message.cli_send_to_conversation_preview_visible_ms',
    cliSendWatch.elapsedMilliseconds,
  );
  final realtimeOpenWatch = Stopwatch()..start();
  await _openConversationAndWaitForFirstPaint(
    tester: tester,
    conversation: conversationForCliMessage,
    expectedText: cliToAppText,
    expectedMessageId: cliSentMessageId,
  );
  realtimeOpenWatch.stop();
  recorder.record(
    'thread.realtime_open_first_paint_ms',
    realtimeOpenWatch.elapsed,
    source: 'ui',
    fields: <String, Object?>{
      'threadKind': conversationForCliMessage.isGroup ? 'group' : 'direct',
      'unread': conversationForCliMessage.unreadCount,
    },
  );
  recorder.metric(
    'message.cli_send_to_app_open_first_paint_ms',
    cliSendWatch.elapsedMilliseconds,
  );
  final threadAfterWatch = Stopwatch()..start();
  final threadAfter = await messageSync.syncThreadAfter(
    thread: thread,
    limit: 20,
  );
  threadAfterWatch.stop();
  recorder.record(
    'message.cli_send_app_thread_after_ms',
    threadAfterWatch.elapsed,
    source: 'app',
    fields: <String, Object?>{
      'items': threadAfter.messages.length,
      'hasMore': threadAfter.hasMore,
      'warnings': threadAfter.warnings,
    },
  );
  await _waitForAppHistory(
    messaging: messaging,
    thread: thread,
    expectedText: cliToAppText,
    expectedMessageId: cliSentMessageId,
  );
  recorder.metric(
    'message.cli_send_to_app_history_visible_ms',
    cliSendWatch.elapsedMilliseconds,
  );
  cliSendWatch.stop();
  conversations.endSendReceiveWindow();

  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: thread,
    expectedTexts: <String>[appToCliText, cliToAppText],
  );

  final threadOpenWatch = Stopwatch()..start();
  final longThreadMessages = await messaging.loadHistory(
    thread,
    limit: config.performance.longThreadMessageCount,
  );
  threadOpenWatch.stop();
  recorder.record(
    'thread.history_initial_load_ms',
    threadOpenWatch.elapsed,
    source: 'app',
    fields: <String, Object?>{'items': longThreadMessages.length},
  );
  recorder.metric(
    'thread.open_to_first_message_visible_ms',
    threadOpenWatch.elapsedMilliseconds,
  );
  recorder.metric('thread.initial_item_count', longThreadMessages.length);

  recorder.counter(
    'conversation.full_refresh_during_send_receive_count',
    conversations.fullRefreshDuringSendReceiveCount,
  );
  recorder.counter(
    'conversation.list_conversations_calls_total',
    conversations.listConversationsCalls,
  );
  recorder.counter(
    'conversation.patch_apply_count',
    conversations.patchApplyCount,
  );
  recorder.counter(
    'conversation.patch_repair_count',
    conversations.patchRepairCount,
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  recorder.cacheStats(
    container.read(chatThreadsProvider.notifier).debugCacheStats(),
  );

  recorder.dataset(
    warmupConversationCountObserved: warmup.localConversationCount,
    visibleConversationCountObserved: <int>[
      initialConversations.length,
      fastLocalConversations.length,
      hydratedConversations.length,
      fastLocalPageScan.items.length,
      hydratedPageScan.items.length,
    ].reduce((value, element) => value > element ? value : element),
    longThreadMessageCountObserved: longThreadMessages.length,
  );
  await recorder.write();
}

Future<_ConversationPageScanResult> _measureConversationPageScan({
  required _E2ePerformanceRecorder recorder,
  required String metricName,
  required String pageCounterName,
  required String itemMetricName,
  required int target,
  required String source,
  required Future<ConversationPage> Function({
    required int limit,
    required String? cursor,
  })
  fetchPage,
}) async {
  final watch = Stopwatch()..start();
  final byKey = <String, ConversationSummary>{};
  String? cursor;
  final seenCursors = <String>{};
  var pagesFetched = 0;
  var hasMore = true;
  while (hasMore && byKey.length < target) {
    final currentCursor = cursor?.trim();
    if (currentCursor != null &&
        currentCursor.isNotEmpty &&
        !seenCursors.add(currentCursor)) {
      fail('$metricName returned repeated cursor after $pagesFetched pages.');
    }
    final page = await fetchPage(
      limit: _conversationPageSize(target),
      cursor: cursor,
    );
    pagesFetched += 1;
    for (final conversation in page.items) {
      byKey[_conversationStableKey(conversation)] = conversation;
    }
    cursor = page.nextCursor;
    hasMore = page.hasMore && cursor != null && cursor.trim().isNotEmpty;
    if (page.items.isEmpty && !hasMore) {
      break;
    }
  }
  watch.stop();
  recorder.record(
    metricName,
    watch.elapsed,
    source: source,
    fields: <String, Object?>{
      'items': byKey.length,
      'pages': pagesFetched,
      'target': target,
      'hasMore': hasMore,
    },
  );
  recorder.metric(itemMetricName, byKey.length);
  recorder.counter(pageCounterName, pagesFetched);
  return _ConversationPageScanResult(byKey.values.toList(growable: false));
}

int _conversationPageSize(int remaining) {
  if (remaining <= 0) {
    return 1;
  }
  return remaining > 100 ? 100 : remaining;
}

String _conversationStableKey(ConversationSummary conversation) {
  final key = conversation.conversationKey?.trim();
  if (key != null && key.isNotEmpty) {
    return key;
  }
  return conversation.threadId;
}

class _ConversationPageScanResult {
  const _ConversationPageScanResult(this.items);

  final List<ConversationSummary> items;
}

Future<_LongThreadDatasetResult> _ensureLongThreadDataset({
  required MessagingService messaging,
  required AppThreadRef thread,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final target = config.performance.longThreadMessageCount;
  if (target <= 0) {
    return const _LongThreadDatasetResult(
      initialCount: 0,
      createdCount: 0,
      observedCount: 0,
    );
  }
  final initialMessages = await messaging.loadHistory(thread, limit: target);
  final initialCount = initialMessages.length;
  final missing = target - initialCount;
  if (missing <= 0) {
    return _LongThreadDatasetResult(
      initialCount: initialCount,
      createdCount: 0,
      observedCount: initialCount,
    );
  }
  for (var index = 0; index < missing; index += 1) {
    final number = initialCount + index + 1;
    await messaging.sendText(
      thread: thread,
      content: 'perf long thread ${config.runId} $nonce $number',
    );
  }
  var observedCount = initialCount;
  await _poll(
    description: 'App long thread history reaches $target messages',
    action: () async {
      final messages = await messaging.loadHistory(thread, limit: target);
      observedCount = messages.length;
      return observedCount >= target;
    },
    interval: const Duration(seconds: 1),
  );
  return _LongThreadDatasetResult(
    initialCount: initialCount,
    createdCount: missing,
    observedCount: observedCount,
  );
}

class _LongThreadDatasetResult {
  const _LongThreadDatasetResult({
    required this.initialCount,
    required this.createdCount,
    required this.observedCount,
  });

  final int initialCount;
  final int createdCount;
  final int observedCount;
}

Future<ConversationSummary> _waitForAppConversationPreviewFast({
  required ConversationService conversations,
  required String ownerDid,
  required String expectedText,
}) async {
  ConversationSummary? matched;
  await _poll(
    description: 'App fast conversation summary contains "$expectedText"',
    action: () async {
      final snapshot = await conversations.loadConversationSnapshot(
        ownerDid: ownerDid,
      );
      matched = _findConversationByPreview(snapshot, expectedText);
      if (matched != null) {
        return true;
      }
      final items = await conversations.listConversationSummariesFast(
        ownerDid: ownerDid,
        limit: 20,
      );
      matched = _findConversationByPreview(items, expectedText);
      return matched != null;
    },
    interval: const Duration(seconds: 1),
  );
  return matched!;
}

ConversationSummary? _findConversationByPreview(
  List<ConversationSummary> conversations,
  String expectedText,
) {
  for (final conversation in conversations) {
    if (conversation.lastMessagePreview.contains(expectedText)) {
      return conversation;
    }
  }
  return null;
}

Future<void> _openConversationAndWaitForFirstPaint({
  required WidgetTester tester,
  required ConversationSummary conversation,
  required String expectedText,
  String? expectedMessageId,
}) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  final targetThreadId = conversation.threadId;
  await container
      .read(chatThreadsProvider.notifier)
      .openConversation(conversation);
  container
      .read(selectedConversationProvider.notifier)
      .selectConversation(conversation);
  await tester.pump();
  await _poll(
    description: 'App open first paint contains exact "$expectedText"',
    action: () async {
      await tester.pump(const Duration(milliseconds: 50));
      final thread = container.read(chatThreadProvider(targetThreadId));
      return thread.messages.any(
        (message) => message._matchesText(
          expectedText,
          expectedMessageId: expectedMessageId,
        ),
      );
    },
    interval: const Duration(milliseconds: 100),
    timeout: const Duration(seconds: 30),
  );
}

num _firstNonEmptyMs({
  required Duration shellVisibleElapsed,
  required int snapshotCount,
  required int fastLocalCount,
  required int hydrateCount,
  required num? snapshotMs,
  required num? fastLocalMs,
  required num? hydrateMs,
}) {
  final shellMs = shellVisibleElapsed.inMilliseconds;
  if (snapshotCount > 0 && snapshotMs != null) {
    return shellMs + snapshotMs;
  }
  if (fastLocalCount > 0 && fastLocalMs != null) {
    return shellMs + fastLocalMs;
  }
  if (hydrateCount > 0 && hydrateMs != null) {
    return shellMs + hydrateMs;
  }
  return shellMs;
}

class _CountingConversationService implements ConversationService {
  _CountingConversationService(this.delegate);

  final ConversationService delegate;
  bool _countSendReceiveRefreshes = false;
  int listConversationsCalls = 0;
  int fullRefreshDuringSendReceiveCount = 0;
  int patchApplyCount = 0;
  int patchRepairCount = 0;

  void resetCounters() {
    listConversationsCalls = 0;
    fullRefreshDuringSendReceiveCount = 0;
    patchApplyCount = 0;
    patchRepairCount = 0;
  }

  void beginSendReceiveWindow() {
    _countSendReceiveRefreshes = true;
    fullRefreshDuringSendReceiveCount = 0;
  }

  void endSendReceiveWindow() {
    _countSendReceiveRefreshes = false;
  }

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) {
    return delegate.loadConversationSnapshot(ownerDid: ownerDid);
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) async* {
    await for (final patch in delegate.watchConversationPatches(
      ownerDid: ownerDid,
    )) {
      switch (patch.kind) {
        case ConversationListPatchKind.reset:
        case ConversationListPatchKind.upsert:
        case ConversationListPatchKind.remove:
        case ConversationListPatchKind.reorder:
          patchApplyCount += 1;
        case ConversationListPatchKind.repairRequired:
          patchRepairCount += 1;
      }
      yield patch;
    }
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    patchRepairCount += 1;
    return delegate.repairConversationStore(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) {
    return delegate.listConversationSummariesFast(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
  }

  @override
  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) {
    return delegate.listConversationSummariesFastPage(
      ownerDid: ownerDid,
      limit: limit,
      cursor: cursor,
      unreadOnly: unreadOnly,
    );
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) {
    return delegate.enrichConversationSummaries(
      ownerDid: ownerDid,
      conversations: conversations,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) {
    listConversationsCalls += 1;
    if (_countSendReceiveRefreshes) {
      fullRefreshDuringSendReceiveCount += 1;
    }
    return delegate.listConversations(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
  }

  @override
  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) {
    listConversationsCalls += 1;
    if (_countSendReceiveRefreshes) {
      fullRefreshDuringSendReceiveCount += 1;
    }
    return delegate.listConversationsPage(
      ownerDid: ownerDid,
      limit: limit,
      cursor: cursor,
      unreadOnly: unreadOnly,
    );
  }

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) {
    return delegate.normalizeConversationForRecents(
      ownerDid: ownerDid,
      conversation: conversation,
    );
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) {
    return delegate.markThreadRead(thread, watermark: watermark);
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) {
    return delegate.setThreadHidden(
      ownerDid: ownerDid,
      threadId: threadId,
      hidden: hidden,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) {
    return delegate.hideConversationFromRecents(
      ownerDid: ownerDid,
      conversation: conversation,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) {
    return delegate.restoreConversationToRecents(
      ownerDid: ownerDid,
      conversation: conversation,
      updatedAt: updatedAt,
    );
  }
}

class _E2ePerformanceRecorder {
  _E2ePerformanceRecorder({required this.config});

  final _DesktopCliPeerSmokeConfig config;
  final Map<String, num> _metrics = <String, num>{};
  final Map<String, int> _counters = <String, int>{};
  final List<Map<String, Object?>> _timings = <Map<String, Object?>>[];
  Map<String, Object?> _dataset = const <String, Object?>{};

  Future<List<T>> measureList<T>(
    String name,
    Future<List<T>> Function() action, {
    required String source,
  }) async {
    final watch = Stopwatch()..start();
    final result = await action();
    watch.stop();
    record(
      name,
      watch.elapsed,
      source: source,
      fields: <String, Object?>{'items': result.length},
    );
    return result;
  }

  void record(
    String name,
    Duration elapsed, {
    required String source,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    metric(name, elapsed.inMilliseconds);
    _timings.add(<String, Object?>{
      'name': name,
      'source': source,
      'elapsedMs': elapsed.inMilliseconds,
      if (fields.isNotEmpty) 'fields': fields,
    });
  }

  void metric(String name, num value) {
    _metrics[name] = value;
  }

  num? metricValue(String name) => _metrics[name];

  void counter(String name, int value) {
    _counters[name] = value;
  }

  void cacheStats(ChatThreadCacheStats stats) {
    final values = stats.toJson();
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is! num) {
        continue;
      }
      metric(entry.key, value);
      if (entry.key == 'cache.trimmed_message_count' ||
          entry.key == 'cache.evicted_thread_count' ||
          entry.key == 'cache.protected_overflow_count') {
        counter(entry.key, value.round());
      }
    }
  }

  void dataset({
    required int warmupConversationCountObserved,
    required int visibleConversationCountObserved,
    required int longThreadMessageCountObserved,
  }) {
    _dataset = <String, Object?>{
      'conversationCountTarget': config.performance.datasetConversationCount,
      'conversationCountObserved': visibleConversationCountObserved,
      'warmupConversationCountObserved': warmupConversationCountObserved,
      'visibleConversationCountObserved': visibleConversationCountObserved,
      'longThreadMessageCountTarget': config.performance.longThreadMessageCount,
      'longThreadMessageCountObserved': longThreadMessageCountObserved,
    };
  }

  Future<void> write() async {
    final path = config.performance.productTimingsPath;
    if (path == null || path.trim().isEmpty) {
      fail('performance.productTimingsPath is required for performance E2E.');
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'runId': config.runId,
        'case': config.e2eCase.name,
        'dataset': _dataset,
        'metrics': _metrics,
        'counters': _counters,
        'appProductTimings': _timings,
      }),
      flush: true,
    );
  }
}
