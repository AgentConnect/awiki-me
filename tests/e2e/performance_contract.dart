const Set<String> desktopE2ePerformanceRequiredDatasetFields = <String>{
  'conversationCountTarget',
  'conversationCountObserved',
  'warmupConversationCountObserved',
  'visibleConversationCountObserved',
  'longThreadMessageCountTarget',
  'longThreadMessageCountObserved',
};

const Set<String> desktopE2ePerformanceRequiredCounters = <String>{
  'performance_dataset.existing_count',
  'performance_dataset.created_count',
  'performance_dataset.long_thread_initial_count',
  'performance_dataset.long_thread_created_count',
  'performance_dataset.long_thread_observed_count',
  'message_sync.warmup_events_applied',
  'message_sync.warmup_pages_fetched',
  'message_sync.warmup_recovery_required_count',
  'conversation_list.fast_local_pages_fetched',
  'conversation_list.full_pages_fetched',
  'conversation.full_refresh_during_send_receive_count',
  'conversation.list_conversations_calls_total',
  'conversation.patch_apply_count',
  'conversation.patch_repair_count',
  'cache.trimmed_message_count',
  'cache.evicted_thread_count',
  'cache.protected_overflow_count',
};

Map<String, Object?> buildDesktopE2ePerformanceProductReport({
  required String runId,
  required String caseName,
  required Map<String, Object?> dataset,
  required Map<String, num> metrics,
  required Map<String, int> counters,
  required List<Map<String, Object?>> appProductTimings,
}) {
  final missingDataset =
      desktopE2ePerformanceRequiredDatasetFields
          .difference(dataset.keys.toSet())
          .toList()
        ..sort();
  final missingCounters =
      desktopE2ePerformanceRequiredCounters
          .difference(counters.keys.toSet())
          .toList()
        ..sort();
  if (missingDataset.isNotEmpty || missingCounters.isNotEmpty) {
    throw StateError(
      'performance_product_report_incomplete'
      ':dataset=${missingDataset.join(',')}'
      ':counters=${missingCounters.join(',')}',
    );
  }
  return <String, Object?>{
    'runId': runId,
    'case': caseName,
    'dataset': dataset,
    'metrics': metrics,
    'counters': counters,
    'appProductTimings': appProductTimings,
  };
}
