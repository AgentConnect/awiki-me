import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum AwikiPerformanceLogLevel { summary, verbose }

class AwikiPerformanceLogger {
  const AwikiPerformanceLogger._();

  static const bool _legacyEnabled = bool.fromEnvironment('AWIKI_PERF_LOG');
  static const String configuredLevel = String.fromEnvironment(
    'AWIKI_PERF_LOG_LEVEL',
    defaultValue: 'off',
  );
  static const int maxLogsPerEvent = int.fromEnvironment(
    'AWIKI_PERF_MAX_EVENT_LOGS',
    defaultValue: 120,
  );
  static const int slowFrameThresholdMs = int.fromEnvironment(
    'AWIKI_PERF_SLOW_FRAME_MS',
    defaultValue: 24,
  );

  static final Map<String, int> _eventCounts = <String, int>{};
  static final Set<String> _suppressedEvents = <String>{};

  static bool get enabled {
    if (_legacyEnabled) {
      return true;
    }
    return switch (_normalizedConfiguredLevel) {
      'summary' || 'verbose' => true,
      _ => false,
    };
  }

  static bool get verboseEnabled => _normalizedConfiguredLevel == 'verbose';

  static String get effectiveLevel {
    if (!enabled) {
      return 'off';
    }
    return verboseEnabled ? 'verbose' : 'summary';
  }

  static String get _normalizedConfiguredLevel =>
      configuredLevel.trim().toLowerCase();

  static T sync<T>(
    String event,
    T Function() action, {
    Map<String, Object?> fields = const <String, Object?>{},
    int minMs = 0,
    AwikiPerformanceLogLevel level = AwikiPerformanceLogLevel.summary,
  }) {
    if (!_shouldMeasure(level)) {
      return action();
    }
    final watch = Stopwatch()..start();
    try {
      return action();
    } finally {
      watch.stop();
      log(
        event,
        elapsed: watch.elapsed,
        fields: fields,
        minMs: minMs,
        level: level,
      );
    }
  }

  static Future<T> async<T>(
    String event,
    Future<T> Function() action, {
    Map<String, Object?> fields = const <String, Object?>{},
    int minMs = 0,
    AwikiPerformanceLogLevel level = AwikiPerformanceLogLevel.summary,
  }) async {
    if (!_shouldMeasure(level)) {
      return action();
    }
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      watch.stop();
      log(
        event,
        elapsed: watch.elapsed,
        fields: fields,
        minMs: minMs,
        level: level,
      );
    }
  }

  static void log(
    String event, {
    Duration? elapsed,
    Map<String, Object?> fields = const <String, Object?>{},
    int minMs = 0,
    AwikiPerformanceLogLevel level = AwikiPerformanceLogLevel.summary,
  }) {
    if (!_shouldMeasure(level)) {
      return;
    }
    final elapsedMs = elapsed?.inMilliseconds;
    if (elapsedMs != null && elapsedMs < minMs) {
      return;
    }
    if (!_recordEventAndShouldPrint(event, level)) {
      return;
    }
    final details = <String>[
      'level=${level.name}',
      if (elapsedMs != null) 'elapsed_ms=$elapsedMs',
      for (final entry in fields.entries)
        if (entry.value != null) '${entry.key}=${_formatValue(entry.value)}',
    ];
    debugPrint(
      details.isEmpty
          ? '[awiki_me][perf] event=$event'
          : '[awiki_me][perf] event=$event ${details.join(' ')}',
    );
  }

  static void registerFrameTimings() {
    if (!enabled) {
      return;
    }
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final timing in timings) {
        final buildMs = timing.buildDuration.inMilliseconds;
        final rasterMs = timing.rasterDuration.inMilliseconds;
        final totalMs = buildMs + rasterMs;
        if (totalMs < slowFrameThresholdMs) {
          continue;
        }
        log(
          'frame.slow',
          fields: <String, Object?>{
            'build_ms': buildMs,
            'raster_ms': rasterMs,
            'total_ms': totalMs,
          },
        );
      }
    });
  }

  static String safeHash(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return 'empty';
    }
    return crypto.sha256
        .convert(utf8.encode(normalized))
        .toString()
        .substring(0, 12);
  }

  static Map<String, Object?> threadField(String threadId) {
    return <String, Object?>{'thread_hash': safeHash(threadId)};
  }

  static bool _shouldMeasure(AwikiPerformanceLogLevel level) {
    if (!enabled) {
      return false;
    }
    return switch (level) {
      AwikiPerformanceLogLevel.summary => true,
      AwikiPerformanceLogLevel.verbose => verboseEnabled,
    };
  }

  static bool _recordEventAndShouldPrint(
    String event,
    AwikiPerformanceLogLevel level,
  ) {
    if (maxLogsPerEvent <= 0) {
      return true;
    }
    final count = (_eventCounts[event] ?? 0) + 1;
    _eventCounts[event] = count;
    if (count <= maxLogsPerEvent) {
      return true;
    }
    if (_suppressedEvents.add(event)) {
      debugPrint(
        '[awiki_me][perf] event=$event level=${level.name} suppressed_after=$maxLogsPerEvent',
      );
    }
    return false;
  }

  static Object _formatValue(Object? value) {
    return switch (value) {
      null => '',
      bool() || num() => value,
      DateTime() => value.toUtc().toIso8601String(),
      Iterable() => value.length,
      Map() => value.length,
      _ => _collapseWhitespace(value),
    };
  }

  static String _collapseWhitespace(Object value) {
    final buffer = StringBuffer();
    var lastWasWhitespace = false;
    for (final rune in value.toString().runes) {
      final char = String.fromCharCode(rune);
      if (char.trim().isEmpty) {
        if (!lastWasWhitespace) {
          buffer.write('_');
        }
        lastWasWhitespace = true;
        continue;
      }
      buffer.write(char);
      lastWasWhitespace = false;
    }
    return buffer.toString();
  }
}
