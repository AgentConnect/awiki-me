// [INPUT]: Performance YAML, product timing report, dataset coverage, and cache counters.
// [OUTPUT]: Typed budgets plus hard failures and soft warnings.
// [POS]: Performance report/oracle evaluation; does not execute product scenarios.

part of '../runner.dart';

class DesktopPerformanceDataset {
  const DesktopPerformanceDataset({
    required this.conversationCountTarget,
    required this.longThreadMessageCountTarget,
  });

  final int conversationCountTarget;
  final int longThreadMessageCountTarget;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'conversationCountTarget': conversationCountTarget,
      'longThreadMessageCountTarget': longThreadMessageCountTarget,
    };
  }
}

class DesktopPerformanceConfig {
  DesktopPerformanceConfig({
    required this.datasetConversationCount,
    required this.longThreadMessageCount,
    required this.requiredMetrics,
    required this.hardBudgetMs,
    required this.softBudgetMs,
    required this.maxFullRefreshDuringSendReceive,
  });

  static final DesktopPerformanceConfig defaults = DesktopPerformanceConfig(
    datasetConversationCount: 100,
    longThreadMessageCount: 100,
    requiredMetrics: _desktopCliPeerPerformanceRequiredMetrics,
    hardBudgetMs: const <String, int>{
      'app.launch_to_shell_visible_ms': 30000,
      'conversation_list.first_non_empty_visible_ms': 10000,
      'conversation_list.snapshot_load_ms': 5000,
      'conversation_list.fast_local_hydrate_ms': 5000,
      'conversation_list.fast_local_page_scan_ms': 30000,
      'conversation_list.full_hydrate_ms': 15000,
      'conversation_list.full_page_scan_ms': 60000,
      'message.app_send_to_cli_inbox_visible_ms': 90000,
      'message.app_send_to_cli_history_visible_ms': 90000,
      'message.cli_send_app_thread_after_ms': 90000,
      'message.cli_send_to_app_open_first_paint_ms': 90000,
      'message.cli_send_to_app_history_visible_ms': 90000,
      'message.cli_send_to_conversation_preview_visible_ms': 90000,
      'thread.realtime_open_first_paint_ms': 5000,
      'thread.open_to_first_message_visible_ms': 8000,
      'thread.history_initial_load_ms': 8000,
    },
    softBudgetMs: const <String, int>{
      'app.launch_to_shell_visible_ms': 15000,
      'conversation_list.first_non_empty_visible_ms': 3000,
      'conversation_list.snapshot_load_ms': 1000,
      'conversation_list.fast_local_hydrate_ms': 1500,
      'conversation_list.fast_local_page_scan_ms': 15000,
      'conversation_list.full_hydrate_ms': 5000,
      'conversation_list.full_page_scan_ms': 30000,
      'message.app_send_to_cli_inbox_visible_ms': 20000,
      'message.app_send_to_cli_history_visible_ms': 20000,
      'message.cli_send_app_thread_after_ms': 20000,
      'message.cli_send_to_app_open_first_paint_ms': 5000,
      'message.cli_send_to_app_history_visible_ms': 20000,
      'message.cli_send_to_conversation_preview_visible_ms': 20000,
      'thread.realtime_open_first_paint_ms': 1500,
      'thread.open_to_first_message_visible_ms': 3000,
      'thread.history_initial_load_ms': 3000,
    },
    maxFullRefreshDuringSendReceive: 0,
  );

  final int datasetConversationCount;
  final int longThreadMessageCount;
  final Set<String> requiredMetrics;
  final Map<String, int> hardBudgetMs;
  final Map<String, int> softBudgetMs;
  final int maxFullRefreshDuringSendReceive;

  Duration get flutterTimeout {
    const baseMinutes = 12;
    final extraConversations = datasetConversationCount - 500;
    if (extraConversations <= 0) {
      return const Duration(minutes: baseMinutes);
    }
    final extraBlocks = (extraConversations + 249) ~/ 250;
    return Duration(minutes: baseMinutes + extraBlocks * 6);
  }

  DesktopPerformanceDataset get dataset => DesktopPerformanceDataset(
    conversationCountTarget: datasetConversationCount,
    longThreadMessageCountTarget: longThreadMessageCount,
  );

  Map<String, Object?> budgetsJson() {
    return <String, Object?>{
      'requiredMetrics': requiredMetrics.toList()..sort(),
      'hardBudgetMs': hardBudgetMs,
      'softBudgetMs': softBudgetMs,
      'maxFullRefreshDuringSendReceive': maxFullRefreshDuringSendReceive,
    };
  }

  static DesktopPerformanceConfig fromYaml(Map<String, Object?> map) {
    final defaults = DesktopPerformanceConfig.defaults;
    final dataset = _mapAt(map, 'dataset', optional: true);
    final budgets = _mapAt(map, 'budgets', optional: true);
    return DesktopPerformanceConfig(
      datasetConversationCount:
          _intAt(dataset, 'conversationCount') ??
          defaults.datasetConversationCount,
      longThreadMessageCount:
          _intAt(dataset, 'longThreadMessageCount') ??
          defaults.longThreadMessageCount,
      requiredMetrics: <String>{
        ...defaults.requiredMetrics,
        ...?_stringSetAt(budgets, 'requiredMetrics'),
      },
      hardBudgetMs: <String, int>{
        ...defaults.hardBudgetMs,
        ...?_intMapAt(budgets, 'hardBudgetMs'),
      },
      softBudgetMs: <String, int>{
        ...defaults.softBudgetMs,
        ...?_intMapAt(budgets, 'softBudgetMs'),
      },
      maxFullRefreshDuringSendReceive:
          _intAt(budgets, 'maxFullRefreshDuringSendReceive') ??
          defaults.maxFullRefreshDuringSendReceive,
    );
  }
}

class DesktopProductTimingReport {
  DesktopProductTimingReport({
    required this.dataset,
    required this.metrics,
    required this.counters,
    required this.appProductTimings,
  });

  final Map<String, Object?> dataset;
  final Map<String, num> metrics;
  final Map<String, int> counters;
  final List<Map<String, Object?>> appProductTimings;

  static DesktopProductTimingReport fromJson(Map<String, Object?> json) {
    final dataset = _jsonMapAt(json, 'dataset');
    final metrics = <String, num>{};
    for (final entry in _jsonMapAt(json, 'metrics').entries) {
      final value = entry.value;
      if (value is num) {
        metrics[entry.key] = value;
      }
    }
    final counters = <String, int>{};
    for (final entry in _jsonMapAt(json, 'counters').entries) {
      final value = entry.value;
      if (value is int) {
        counters[entry.key] = value;
      } else if (value is num) {
        counters[entry.key] = value.round();
      }
    }
    final productTimings = <Map<String, Object?>>[];
    final rawTimings = json['appProductTimings'];
    if (rawTimings is List) {
      for (final value in rawTimings) {
        if (value is Map) {
          productTimings.add(<String, Object?>{
            for (final entry in value.entries)
              entry.key.toString(): entry.value,
          });
        }
      }
    }
    return DesktopProductTimingReport(
      dataset: dataset,
      metrics: metrics,
      counters: counters,
      appProductTimings: productTimings,
    );
  }
}

class DesktopPerformanceBudgetResult {
  DesktopPerformanceBudgetResult({
    required this.hardFailures,
    required this.softWarnings,
  });

  final List<String> hardFailures;
  final List<String> softWarnings;

  static DesktopPerformanceBudgetResult evaluate({
    required DesktopPerformanceConfig config,
    required DesktopProductTimingReport? report,
  }) {
    final hardFailures = <String>[];
    final softWarnings = <String>[];
    if (report == null) {
      hardFailures.add('missing product timing report');
      return DesktopPerformanceBudgetResult(
        hardFailures: hardFailures,
        softWarnings: softWarnings,
      );
    }
    for (final metric in config.requiredMetrics) {
      if (!report.metrics.containsKey(metric)) {
        hardFailures.add('missing required metric $metric');
      }
    }
    for (final field in desktopE2ePerformanceRequiredDatasetFields) {
      if (!report.dataset.containsKey(field)) {
        hardFailures.add('missing required dataset field $field');
      }
    }
    for (final counter in desktopE2ePerformanceRequiredCounters) {
      if (!report.counters.containsKey(counter)) {
        hardFailures.add('missing required counter $counter');
      }
    }
    final observedConversations =
        _numFromJson(report.dataset['visibleConversationCountObserved']) ?? 0;
    if (observedConversations < config.datasetConversationCount) {
      hardFailures.add(
        'dataset conversation count $observedConversations is below target '
        '${config.datasetConversationCount}',
      );
    }
    final observedLongThread =
        _numFromJson(report.dataset['longThreadMessageCountObserved']) ?? 0;
    if (observedLongThread < config.longThreadMessageCount) {
      hardFailures.add(
        'long thread message count $observedLongThread is below target '
        '${config.longThreadMessageCount}',
      );
    }
    final fullRefreshCount =
        report
            .counters['conversation.full_refresh_during_send_receive_count'] ??
        0;
    if (fullRefreshCount > config.maxFullRefreshDuringSendReceive) {
      hardFailures.add(
        'conversation full refresh during send/receive count $fullRefreshCount '
        'exceeds ${config.maxFullRefreshDuringSendReceive}',
      );
    }
    final totalRetainedMessages =
        _numFromJson(report.metrics['cache.total_retained_messages']) ?? 0;
    final protectedOverflowCount =
        report.counters['cache.protected_overflow_count'] ?? 0;
    final maxRetainedMessages =
        _desktopCliPeerPerformanceMaxCachedMessages + protectedOverflowCount;
    if (totalRetainedMessages > maxRetainedMessages) {
      hardFailures.add(
        'cache total retained messages ${totalRetainedMessages.round()} '
        'exceeds $maxRetainedMessages',
      );
    }
    final canonicalThreadCount =
        _numFromJson(report.metrics['cache.canonical_thread_count']) ?? 0;
    final maxCanonicalThreads =
        _desktopCliPeerPerformanceMaxCachedCanonicalThreads +
        protectedOverflowCount;
    if (canonicalThreadCount > maxCanonicalThreads) {
      hardFailures.add(
        'cache canonical thread count ${canonicalThreadCount.round()} '
        'exceeds $maxCanonicalThreads',
      );
    }
    final activePatchSubscriptions =
        _numFromJson(report.metrics['cache.active_patch_subscription_count']) ??
        0;
    if (activePatchSubscriptions >
        _desktopCliPeerPerformanceMaxActivePatchSubscriptions) {
      hardFailures.add(
        'cache active patch subscription count '
        '${activePatchSubscriptions.round()} exceeds '
        '$_desktopCliPeerPerformanceMaxActivePatchSubscriptions',
      );
    }
    for (final entry in config.hardBudgetMs.entries) {
      final actual = report.metrics[entry.key];
      if (actual != null && actual > entry.value) {
        hardFailures.add(
          '${entry.key} ${actual.round()}ms exceeds hard budget '
          '${entry.value}ms',
        );
      }
    }
    for (final entry in config.softBudgetMs.entries) {
      final actual = report.metrics[entry.key];
      if (actual != null && actual > entry.value) {
        softWarnings.add(
          '${entry.key} ${actual.round()}ms exceeds soft budget '
          '${entry.value}ms',
        );
      }
    }
    return DesktopPerformanceBudgetResult(
      hardFailures: hardFailures,
      softWarnings: softWarnings,
    );
  }
}
