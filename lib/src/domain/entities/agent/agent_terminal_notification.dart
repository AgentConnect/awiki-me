import 'dart:async';
import 'dart:collection';

enum AgentTerminalKind { completed, blocked, actionRequired, runtimeFailed }

class AgentTerminalNotification {
  const AgentTerminalNotification({
    required this.eventId,
    required this.runId,
    required this.kind,
    this.summary,
    this.nextStep,
    this.finalMessageId,
  });

  final String eventId;
  final String runId;
  final AgentTerminalKind kind;
  final String? summary;
  final String? nextStep;
  final String? finalMessageId;

  String get dedupeKey => '$runId:${kind.name}';

  static AgentTerminalNotification? fromStatusPayload(
    Map<String, Object?> payload,
  ) {
    if (_string(payload['schema']) != 'awiki.agent.status.v1') {
      return null;
    }
    final eventId = _string(payload['event_id']);
    final runId = _string(payload['run_id']) ?? _runString(payload, 'run_id');
    final state = _string(payload['state']) ?? _runString(payload, 'status');
    if (eventId == null || runId == null || state == null) {
      return null;
    }

    final outcome =
        _string(payload['business_outcome']) ??
        _runString(payload, 'business_outcome');
    if (outcome == null) {
      if (state != 'failed') {
        return null;
      }
      return AgentTerminalNotification(
        eventId: eventId,
        runId: runId,
        kind: AgentTerminalKind.runtimeFailed,
      );
    }
    if (state != 'finished') {
      return null;
    }
    final kind = switch (outcome) {
      'completed' => AgentTerminalKind.completed,
      'blocked' => AgentTerminalKind.blocked,
      'action_required' => AgentTerminalKind.actionRequired,
      _ => null,
    };
    if (kind == null) {
      return null;
    }
    final summary = _safeNotificationText(
      _string(payload['summary']) ?? _runString(payload, 'summary'),
    );
    final nextStep = _safeNotificationText(
      _string(payload['next_step']) ?? _runString(payload, 'next_step'),
    );
    if (summary == null ||
        ((kind == AgentTerminalKind.blocked ||
                kind == AgentTerminalKind.actionRequired) &&
            nextStep == null)) {
      return null;
    }
    return AgentTerminalNotification(
      eventId: eventId,
      runId: runId,
      kind: kind,
      summary: summary,
      nextStep: nextStep,
      finalMessageId:
          _string(payload['final_message_id']) ??
          _runString(payload, 'final_message_id'),
    );
  }
}

class AgentTerminalNotificationDeduplicator {
  static const Duration runtimeMessageCorrelationWindow = Duration(seconds: 1);
  static const int _maxRecentMessageIds = 256;
  static const int _maxTerminalKeys = 512;
  static const int _maxTerminalMessageIds = 512;
  static const int _maxPendingRuntimeMessages = 64;

  final LinkedHashSet<String> _terminalKeys = LinkedHashSet<String>();
  final LinkedHashSet<String> _terminalMessageIds = LinkedHashSet<String>();
  final LinkedHashSet<String> _recentMessageIds = LinkedHashSet<String>();
  final LinkedHashSet<_PendingRuntimeMessageNotification>
  _pendingRuntimeMessages =
      LinkedHashSet<_PendingRuntimeMessageNotification>.identity();
  final Map<String, _PendingRuntimeMessageNotification> _pendingByMessageId =
      <String, _PendingRuntimeMessageNotification>{};

  AgentTerminalNotification? acceptStatus(Map<String, Object?> payload) {
    final notification = AgentTerminalNotification.fromStatusPayload(payload);
    if (notification == null) {
      return null;
    }
    final finalMessageId = notification.finalMessageId;
    if (finalMessageId != null) {
      _rememberBounded(
        _terminalMessageIds,
        finalMessageId,
        _maxTerminalMessageIds,
      );
    }
    if (_terminalKeys.contains(notification.dedupeKey)) {
      return null;
    }
    _rememberBounded(_terminalKeys, notification.dedupeKey, _maxTerminalKeys);
    if (finalMessageId != null) {
      final pending = _pendingByMessageId[finalMessageId];
      if (pending != null) {
        _cancelPending(pending);
        return notification;
      }
      if (_recentMessageIds.contains(finalMessageId)) {
        return null;
      }
    }
    return notification;
  }

  bool acceptMessageIds(Iterable<String?> messageIds) {
    final normalizedIds = _normalizedMessageIds(messageIds);
    if (normalizedIds.any(_terminalMessageIds.contains)) {
      return false;
    }
    if (normalizedIds.any(_recentMessageIds.contains)) {
      return false;
    }
    for (final messageId in normalizedIds) {
      _rememberRecentMessageId(messageId);
    }
    return true;
  }

  bool acceptRuntimeMessageIds(
    Iterable<String?> messageIds, {
    required void Function() releaseNotification,
  }) {
    final normalizedIds = _normalizedMessageIds(messageIds);
    if (normalizedIds.isEmpty) {
      releaseNotification();
      return true;
    }
    if (normalizedIds.any(_terminalMessageIds.contains) ||
        normalizedIds.any(_recentMessageIds.contains)) {
      return false;
    }
    for (final messageId in normalizedIds) {
      _rememberRecentMessageId(messageId);
    }
    while (_pendingRuntimeMessages.length >= _maxPendingRuntimeMessages) {
      _releasePending(_pendingRuntimeMessages.first);
    }
    late final _PendingRuntimeMessageNotification pending;
    pending = _PendingRuntimeMessageNotification(
      messageIds: normalizedIds,
      releaseNotification: releaseNotification,
      timer: Timer(runtimeMessageCorrelationWindow, () {
        _releasePending(pending);
      }),
    );
    _pendingRuntimeMessages.add(pending);
    for (final messageId in normalizedIds) {
      _pendingByMessageId[messageId] = pending;
    }
    return true;
  }

  void clear() {
    for (final pending in _pendingRuntimeMessages.toList(growable: false)) {
      _cancelPending(pending);
    }
    _terminalKeys.clear();
    _terminalMessageIds.clear();
    _recentMessageIds.clear();
  }

  void _rememberRecentMessageId(String value) {
    _recentMessageIds.remove(value);
    _recentMessageIds.add(value);
    while (_recentMessageIds.length > _maxRecentMessageIds) {
      _recentMessageIds.remove(_recentMessageIds.first);
    }
  }

  void _cancelPending(_PendingRuntimeMessageNotification pending) {
    if (!_pendingRuntimeMessages.remove(pending)) {
      return;
    }
    pending.timer.cancel();
    for (final messageId in pending.messageIds) {
      if (identical(_pendingByMessageId[messageId], pending)) {
        _pendingByMessageId.remove(messageId);
      }
    }
  }

  void _releasePending(_PendingRuntimeMessageNotification pending) {
    if (!_pendingRuntimeMessages.contains(pending)) {
      return;
    }
    _cancelPending(pending);
    pending.releaseNotification();
  }
}

class _PendingRuntimeMessageNotification {
  const _PendingRuntimeMessageNotification({
    required this.messageIds,
    required this.releaseNotification,
    required this.timer,
  });

  final Set<String> messageIds;
  final void Function() releaseNotification;
  final Timer timer;
}

Set<String> _normalizedMessageIds(Iterable<String?> messageIds) => messageIds
    .map((value) => value?.trim())
    .whereType<String>()
    .where((value) => value.isNotEmpty)
    .toSet();

void _rememberBounded(LinkedHashSet<String> values, String value, int limit) {
  values.remove(value);
  values.add(value);
  while (values.length > limit) {
    values.remove(values.first);
  }
}

String? _runString(Map<String, Object?> payload, String key) {
  final runs = payload['runs'];
  if (runs is! List || runs.isEmpty || runs.first is! Map) {
    return null;
  }
  final run = (runs.first as Map).map(
    (key, value) => MapEntry(key.toString(), value),
  );
  return _string(run[key]);
}

String? _string(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _safeNotificationText(String? value) {
  if (value == null ||
      value.length > 240 ||
      value.contains('\n') ||
      value.contains('\r') ||
      value.contains('```')) {
    return null;
  }
  final lower = value.toLowerCase();
  if (const <String>[
        'token',
        'secret',
        'password',
        'passwd',
        'private_key',
        'private key',
        'bearer ',
        'api_key',
        'api key',
        'jwt',
        'source code',
        '源码',
      ].any(lower.contains) ||
      RegExp("(^|[\\s:=\\(\\[\"'])/(?!/)").hasMatch(value) ||
      RegExp("(^|[\\s:=\\(\\[\"'])[A-Za-z]:[\\\\/]").hasMatch(value) ||
      lower.contains('file://')) {
    return null;
  }
  return value;
}
