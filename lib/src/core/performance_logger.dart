import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class AwikiPerformanceLogger {
  const AwikiPerformanceLogger._();

  static const bool enabled = bool.fromEnvironment('AWIKI_PERF_LOG');
  static const int slowFrameThresholdMs = int.fromEnvironment(
    'AWIKI_PERF_SLOW_FRAME_MS',
    defaultValue: 24,
  );

  static T sync<T>(
    String event,
    T Function() action, {
    Map<String, Object?> fields = const <String, Object?>{},
    int minMs = 0,
  }) {
    if (!enabled) {
      return action();
    }
    final watch = Stopwatch()..start();
    try {
      return action();
    } finally {
      watch.stop();
      log(event, elapsed: watch.elapsed, fields: fields, minMs: minMs);
    }
  }

  static Future<T> async<T>(
    String event,
    Future<T> Function() action, {
    Map<String, Object?> fields = const <String, Object?>{},
    int minMs = 0,
  }) async {
    if (!enabled) {
      return action();
    }
    final watch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      watch.stop();
      log(event, elapsed: watch.elapsed, fields: fields, minMs: minMs);
    }
  }

  static void log(
    String event, {
    Duration? elapsed,
    Map<String, Object?> fields = const <String, Object?>{},
    int minMs = 0,
  }) {
    if (!enabled) {
      return;
    }
    final elapsedMs = elapsed?.inMilliseconds;
    if (elapsedMs != null && elapsedMs < minMs) {
      return;
    }
    final details = <String>[
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
