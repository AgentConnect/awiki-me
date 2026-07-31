import 'dart:async';
import 'dart:collection';

import '../domain/entities/remote_push_event.dart';
import '../domain/services/remote_push_client.dart';
import 'models/remote_push_sync_receipt.dart';
import 'ports/message_sync_core_port.dart';
import 'ports/remote_push_sync_port.dart';
import 'remote_push_message_reference.dart';

typedef RemotePushInstallationRefresh =
    Future<void> Function(RemotePushSessionContext context);

class RemotePushMessageSyncCoordinator {
  RemotePushMessageSyncCoordinator({
    required RemotePushClient client,
    required RemotePushSyncPort sync,
    required RemotePushNavigationPort navigation,
    required RemotePushInstallationRefresh refreshInstallation,
    DateTime Function()? now,
  }) : _client = client,
       _sync = sync,
       _navigation = navigation,
       _refreshInstallation = refreshInstallation,
       _now = now ?? DateTime.now;

  final RemotePushClient _client;
  final RemotePushSyncPort _sync;
  final RemotePushNavigationPort _navigation;
  final RemotePushInstallationRefresh _refreshInstallation;
  final DateTime Function() _now;
  final LinkedHashMap<String, RemotePushEvent> _queuedEvents =
      LinkedHashMap<String, RemotePushEvent>();

  StreamSubscription<RemotePushEvent>? _subscription;
  RemotePushSessionContext? _activeSession;
  Future<void> _operationTail = Future<void>.value();
  bool _disposed = false;

  void start() {
    if (_disposed) {
      throw StateError('Remote Push message sync coordinator is disposed');
    }
    if (_subscription != null) return;
    _subscription = _client.events.listen(_onEvent);
  }

  Future<void> activateSession(RemotePushSessionContext context) {
    if (_disposed) {
      throw StateError('Remote Push message sync coordinator is disposed');
    }
    _activeSession = context;
    _mergePendingEvents();
    return _serialize(_drainOneBatch);
  }

  void deactivateSession(RemotePushSessionContext context) {
    if (context.matches(_activeSession)) {
      _activeSession = null;
    }
  }

  Future<void> resume() {
    if (_disposed) return Future<void>.value();
    _mergePendingEvents();
    return _serialize(_drainOneBatch);
  }

  void _onEvent(RemotePushEvent event) {
    if (_disposed) return;
    switch (event.kind) {
      case RemotePushEventKind.messageReceived:
      case RemotePushEventKind.notificationReceived:
      case RemotePushEventKind.notificationReceivedInApp:
      case RemotePushEventKind.notificationOpened:
        _queuedEvents[event.deliveryId] = event;
        if (_activeSession != null) {
          unawaited(_serialize(_drainOneBatch));
        }
      case RemotePushEventKind.registrationChanged:
        final context = _activeSession;
        if (context != null) {
          unawaited(_serialize(() => _refreshAndDrain(context)));
        }
      case RemotePushEventKind.notificationRemoved:
        return;
    }
  }

  void _mergePendingEvents() {
    for (final event in _client.pendingEvents) {
      switch (event.kind) {
        case RemotePushEventKind.messageReceived:
        case RemotePushEventKind.notificationReceived:
        case RemotePushEventKind.notificationReceivedInApp:
        case RemotePushEventKind.notificationOpened:
          _queuedEvents[event.deliveryId] = event;
        case RemotePushEventKind.registrationChanged:
        case RemotePushEventKind.notificationRemoved:
          break;
      }
    }
  }

  Future<void> _refreshFor(RemotePushSessionContext context) async {
    if (!_isCurrent(context)) return;
    try {
      await _refreshInstallation(context);
    } on Object {
      return;
    }
    if (!_isCurrent(context)) return;
  }

  Future<void> _refreshAndDrain(RemotePushSessionContext context) async {
    await _refreshFor(context);
    if (!_isCurrent(context)) return;
    await _drainOneBatch();
    if (!_isCurrent(context)) return;
  }

  Future<void> _drainOneBatch() async {
    final context = _activeSession;
    if (context == null || _queuedEvents.isEmpty || _disposed) return;

    final batch = List<RemotePushEvent>.unmodifiable(_queuedEvents.values);
    final deliveryIds = batch
        .map((event) => event.deliveryId)
        .toList(growable: false);

    final RemotePushSyncReceipt receipt;
    try {
      receipt = await _sync.requestRemotePushSync();
    } on Object {
      return;
    }
    if (!_isCurrent(context) || !receipt.canAcknowledge) return;

    final openedEvent = _lastOpenedEvent(batch);
    if (openedEvent != null) {
      final conversationId = _resolveConversationId(openedEvent, receipt);
      try {
        await _navigation.showConversationList(context);
      } on Object {
        return;
      }
      if (!_isCurrent(context)) return;
      if (conversationId != null) {
        try {
          await _navigation.openConversation(context, conversationId);
        } on Object {
          return;
        }
        if (!_isCurrent(context)) return;
      }
    }

    if (!_isCurrent(context)) return;
    try {
      await _client.acknowledgePendingEvents(deliveryIds);
    } on Object {
      return;
    }
    for (final deliveryId in deliveryIds) {
      _queuedEvents.remove(deliveryId);
    }
    if (!_isCurrent(context)) return;
  }

  RemotePushEvent? _lastOpenedEvent(List<RemotePushEvent> batch) {
    for (var index = batch.length - 1; index >= 0; index -= 1) {
      final event = batch[index];
      if (event.kind == RemotePushEventKind.notificationOpened) {
        return event;
      }
    }
    return null;
  }

  String? _resolveConversationId(
    RemotePushEvent event,
    RemotePushSyncReceipt receipt,
  ) {
    final opaqueReference = _openedOpaqueReference(event);
    if (opaqueReference == null) return null;
    for (final committed in receipt.committedIncomingMessages) {
      if (!_matchesCommittedMessage(opaqueReference, committed)) continue;
      final conversationId = committed.message.conversationId;
      if (conversationId != null &&
          conversationId.isNotEmpty &&
          conversationId.trim() == conversationId) {
        return conversationId;
      }
    }
    return null;
  }

  String? _openedOpaqueReference(RemotePushEvent event) {
    final extraMap = event.payload['extraMap'];
    if (extraMap is! Map) return null;
    final mid = extraMap['mid'];
    if (mid is! String || !_opaqueMessagePattern.hasMatch(mid)) return null;

    final rawExpiry = extraMap['exp'];
    if (rawExpiry == null) return null;
    final expirySeconds = _parseExpirySeconds(rawExpiry);
    if (expirySeconds == null ||
        expirySeconds <=
            _now().toUtc().millisecondsSinceEpoch ~/
                Duration.millisecondsPerSecond) {
      return null;
    }
    return mid;
  }

  bool _matchesCommittedMessage(
    String opaqueReference,
    CommittedIncomingMessage committed,
  ) {
    final messageIds = <String?>[
      committed.logicalMessageId,
      committed.message.remoteId,
      committed.message.localId,
    ];
    for (final messageId in messageIds) {
      if (messageId == null) continue;
      try {
        if (remotePushOpaqueMessageReference(messageId) == opaqueReference) {
          return true;
        }
      } on ArgumentError {
        // An invalid committed identifier cannot match a provider reference.
      }
    }
    return false;
  }

  int? _parseExpirySeconds(Object value) {
    if (value is int) return _validExpirySeconds(value);
    if (value is num) {
      if (!value.isFinite || value != value.truncateToDouble()) return null;
      return _validExpirySeconds(value.toInt());
    }
    if (value is String && value.trim() == value) {
      final seconds = int.tryParse(value);
      return seconds == null ? null : _validExpirySeconds(seconds);
    }
    return null;
  }

  int? _validExpirySeconds(int value) {
    return value > 0 && value <= _maxSupportedExpirySeconds ? value : null;
  }

  bool _isCurrent(RemotePushSessionContext context) {
    return !_disposed && context.matches(_activeSession);
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _operationTail.then((_) => operation());
    _operationTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _activeSession = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    await _operationTail;
    _queuedEvents.clear();
  }
}

final RegExp _opaqueMessagePattern = RegExp(r'^message_[A-Za-z0-9_-]{24}$');
const int _maxSupportedExpirySeconds = 8640000000000;
