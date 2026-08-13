import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../domain/entities/remote_push_event.dart';
import '../domain/services/remote_push_client.dart';
import 'models/remote_push_sync_receipt.dart';
import 'alive_urgent_click_binding_store.dart';
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
    required AliveUrgentClickBindingStore aliveUrgentClickBindings,
    DateTime Function()? now,
  }) : _client = client,
       _sync = sync,
       _navigation = navigation,
       _refreshInstallation = refreshInstallation,
       _aliveUrgentClickBindings = aliveUrgentClickBindings,
       _now = now ?? DateTime.now;

  final RemotePushClient _client;
  final RemotePushSyncPort _sync;
  final RemotePushNavigationPort _navigation;
  final RemotePushInstallationRefresh _refreshInstallation;
  final AliveUrgentClickBindingStore _aliveUrgentClickBindings;
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

  Future<void> pullPendingAndDrain() {
    if (_disposed) {
      throw StateError('Remote Push message sync coordinator is disposed');
    }
    return _serialize(() async {
      await _client.pullPendingEvents();
      _mergePendingEvents();
      await _drainOneBatch();
    });
  }

  Future<void> activateSession(RemotePushSessionContext context) {
    if (_disposed) {
      throw StateError('Remote Push message sync coordinator is disposed');
    }
    final previous = _activeSession;
    if (previous != null && !previous.matches(context)) {
      _aliveUrgentClickBindings.clearForSession(previous);
    }
    _activeSession = context;
    _mergePendingEvents();
    return _serialize(() => _activateAndDrain(context));
  }

  void deactivateSession(RemotePushSessionContext context) {
    if (context.matches(_activeSession)) {
      _aliveUrgentClickBindings.clearForSession(context);
      _activeSession = null;
      unawaited(
        _serialize(() async {
          if (_activeSession == null && !_disposed) {
            await _setActiveNotificationTargetReference(null);
          }
        }),
      );
    }
  }

  Future<void> _activateAndDrain(RemotePushSessionContext context) {
    if (!_isCurrent(context)) return Future<void>.value();
    if (_client case final RemotePushPresentationTargetClient targetClient) {
      return _installTargetAndDrain(context, targetClient);
    }
    return _drainOneBatch();
  }

  Future<void> _installTargetAndDrain(
    RemotePushSessionContext context,
    RemotePushPresentationTargetClient targetClient,
  ) async {
    try {
      await targetClient.setActiveNotificationTargetReference(
        remotePushOpaqueTargetReference(context.ownerDid),
      );
    } on Object {
      // Provider presentation remains enabled when the session fence cannot
      // be installed, so activation must remain best-effort.
    }
    if (!_isCurrent(context)) return;
    await _drainOneBatch();
  }

  Future<void> _setActiveNotificationTargetReference(String? value) async {
    if (_client case final RemotePushPresentationTargetClient targetClient) {
      await targetClient.setActiveNotificationTargetReference(value);
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
      case RemotePushEventKind.notificationRemoved:
        _queuedEvents[event.deliveryId] = event;
        if (_activeSession != null) {
          debugPrint(
            '[AWikiRemotePush] dart queued ${event.kind.wireName}',
          );
          unawaited(_serialize(_drainOneBatch));
        } else {
          debugPrint('[AWikiRemotePush] dart queued without session');
        }
      case RemotePushEventKind.registrationChanged:
        final context = _activeSession;
        if (context != null) {
          unawaited(_serialize(() => _refreshAndDrain(context)));
        }
    }
  }

  void _mergePendingEvents() {
    for (final event in _client.pendingEvents) {
      switch (event.kind) {
        case RemotePushEventKind.messageReceived:
        case RemotePushEventKind.notificationReceived:
        case RemotePushEventKind.notificationReceivedInApp:
        case RemotePushEventKind.notificationOpened:
        case RemotePushEventKind.notificationRemoved:
          _queuedEvents[event.deliveryId] = event;
        case RemotePushEventKind.registrationChanged:
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

    final batch = List<RemotePushEvent>.unmodifiable(
      _queuedEvents.values.where(
        (event) => _eventTargetsSession(event, context),
      ),
    );
    if (batch.isEmpty) return;
    final deliveryIds = batch
        .map((event) => event.deliveryId)
        .toList(growable: false);
    for (final removed in batch.where(
      (event) => event.kind == RemotePushEventKind.notificationRemoved,
    )) {
      _discardRemovedBinding(context, removed);
    }
    final syncBatch = batch
        .where((event) => event.kind != RemotePushEventKind.notificationRemoved)
        .toList(growable: false);
    if (syncBatch.isEmpty) {
      await _acknowledgeBatch(context, deliveryIds);
      return;
    }

    final RemotePushSyncReceipt receipt;
    try {
      receipt = await _sync.requestRemotePushSync(
        presentation: _presentationDisposition(syncBatch),
      );
    } on Object {
      debugPrint('[AWikiRemotePush] dart drain sync failed');
      return;
    }
    debugPrint(
      '[AWikiRemotePush] dart drain sync ok events=${syncBatch.length} '
      'disposition=${receipt.disposition.name} '
      'committed=${receipt.committedIncomingMessages.length} '
      'applied=${receipt.eventsApplied} '
      'dup=${receipt.duplicatesSkipped} '
      'status=${receipt.lastStatus ?? '-'} '
      'error=${receipt.errorCode ?? '-'} '
      'current=${_isCurrent(context)} '
      'canAck=${receipt.canAcknowledge}',
    );
    if (!_isCurrent(context) || !receipt.canAcknowledge) return;
    if (receipt.committedIncomingMessages.isEmpty &&
        _presentationDisposition(syncBatch) ==
            RemotePushPresentationDisposition.appPresentationRequired) {
      debugPrint(
        '[AWikiRemotePush] dart drain skip ack empty committed',
      );
      return;
    }

    final openedEvent = _lastOpenedEvent(syncBatch);
    if (openedEvent != null) {
      final conversationId = _resolveConversationId(
        context,
        openedEvent,
        receipt,
      );
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

    await _acknowledgeBatch(context, deliveryIds);
  }

  Future<void> _acknowledgeBatch(
    RemotePushSessionContext context,
    List<String> deliveryIds,
  ) async {
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

  void _discardRemovedBinding(
    RemotePushSessionContext context,
    RemotePushEvent event,
  ) {
    final removed = _opaqueReferenceAndExpiry(event);
    if (removed == null) return;
    _aliveUrgentClickBindings.discard(
      context: context,
      opaqueMessageReference: removed.reference,
      expiresAtEpochSeconds: removed.expiresAtEpochSeconds,
    );
  }

  bool _eventTargetsSession(
    RemotePushEvent event,
    RemotePushSessionContext context,
  ) {
    final extraMap = event.payload['extraMap'];
    if (extraMap is! Map) return true;
    if (extraMap['ty'] case final String type
        when _ordinaryMessageTypes.contains(type)) {
      final targetReference = extraMap['ts'];
      if (targetReference is! String ||
          !_opaqueTargetPattern.hasMatch(targetReference)) {
        return true;
      }
      try {
        return remotePushOpaqueTargetReference(context.ownerDid) ==
            targetReference;
      } on ArgumentError {
        return false;
      }
    }
    return true;
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

  RemotePushPresentationDisposition _presentationDisposition(
    List<RemotePushEvent> batch,
  ) {
    for (final event in batch) {
      if (event.kind == RemotePushEventKind.notificationReceived ||
          event.kind == RemotePushEventKind.notificationOpened) {
        return RemotePushPresentationDisposition.providerPresented;
      }
    }
    return RemotePushPresentationDisposition.appPresentationRequired;
  }

  String? _resolveConversationId(
    RemotePushSessionContext context,
    RemotePushEvent event,
    RemotePushSyncReceipt receipt,
  ) {
    final opened = _openedOpaqueReference(event);
    if (opened == null) return null;
    for (final committed in receipt.committedIncomingMessages) {
      if (!_matchesCommittedMessage(opened.reference, committed)) continue;
      final conversationId = committed.message.conversationId;
      if (conversationId != null &&
          conversationId.isNotEmpty &&
          conversationId.trim() == conversationId) {
        _aliveUrgentClickBindings.discard(
          context: context,
          opaqueMessageReference: opened.reference,
          expiresAtEpochSeconds: opened.expiresAtEpochSeconds,
        );
        return conversationId;
      }
    }
    return _aliveUrgentClickBindings.consume(
      context: context,
      opaqueMessageReference: opened.reference,
      expiresAtEpochSeconds: opened.expiresAtEpochSeconds,
    );
  }

  ({String reference, int expiresAtEpochSeconds})? _openedOpaqueReference(
    RemotePushEvent event,
  ) {
    final opened = _opaqueReferenceAndExpiry(event);
    if (opened == null || opened.expiresAtEpochSeconds <= _nowSeconds()) {
      return null;
    }
    return opened;
  }

  ({String reference, int expiresAtEpochSeconds})? _opaqueReferenceAndExpiry(
    RemotePushEvent event,
  ) {
    final extraMap = event.payload['extraMap'];
    if (extraMap is! Map) return null;
    final mid = extraMap['mid'];
    if (mid is! String || !_opaqueMessagePattern.hasMatch(mid)) return null;

    final rawExpiry = extraMap['exp'];
    if (rawExpiry == null) return null;
    final expirySeconds = _parseExpirySeconds(rawExpiry);
    if (expirySeconds == null) return null;
    return (reference: mid, expiresAtEpochSeconds: expirySeconds);
  }

  int _nowSeconds() =>
      _now().toUtc().millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond;

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
    _aliveUrgentClickBindings.clear();
    _activeSession = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    await _operationTail;
    try {
      await _setActiveNotificationTargetReference(null);
    } on Object {
      // The native bridge may already be detached during application teardown.
    }
    _queuedEvents.clear();
  }
}

final RegExp _opaqueMessagePattern = RegExp(r'^message_[A-Za-z0-9_-]{24}$');
final RegExp _opaqueTargetPattern = RegExp(r'^target_[A-Za-z0-9_-]{24}$');
const Set<String> _ordinaryMessageTypes = <String>{
  'direct_message',
  'group_message',
};
const int _maxSupportedExpirySeconds = 8640000000000;
