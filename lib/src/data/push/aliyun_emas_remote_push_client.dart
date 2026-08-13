import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../domain/entities/remote_push_event.dart';
import '../../domain/services/notification_channels.dart';
import '../../domain/services/remote_push_client.dart';
import 'aliyun_emas_platform.dart';

const String aliyunEmasPushProvider = 'aliyun_emas';
const String awikiMeClientProduct = 'awiki-me';
const String awikiAgentMessageV1Capability = 'awiki.agent.message.v1';
const String _aliyunEmasSuccessCode = '10000';
const int _maxPendingEvents = 32;
const Duration _maxPendingEventAge = Duration(hours: 24);
const int _maxPendingStringLength = 256;
const Set<String> _pendingEnvelopeKeys = <String>{
  'v',
  'eid',
  'ty',
  'ts',
  'ir',
  'tr',
  'mid',
  'exp',
};

class RemotePushInitializationException implements Exception {
  const RemotePushInitializationException({
    required this.operation,
    required this.code,
    this.message,
  });

  final String operation;
  final String code;
  final String? message;

  @override
  String toString() {
    final detail = message == null || message!.isEmpty ? '' : ': $message';
    return 'RemotePushInitializationException($operation, $code)$detail';
  }
}

class AliyunEmasRemotePushClient
    implements RemotePushClient, RemotePushPresentationTargetClient {
  AliyunEmasRemotePushClient({
    AliyunEmasPlatform? platform,
    this.clientPlatform = 'android',
    Future<PackageInfo> Function()? packageInfoLoader,
  }) : assert(clientPlatform == 'android' || clientPlatform == 'ios'),
       _platform = platform ?? PluginAliyunEmasPlatform(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform;

  final AliyunEmasPlatform _platform;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final String clientPlatform;
  final StreamController<RemotePushEvent> _events =
      StreamController<RemotePushEvent>.broadcast();
  final Map<String, RemotePushEvent> _pendingEvents =
      <String, RemotePushEvent>{};
  Future<RemotePushRegistration?>? _initialization;
  RemotePushRegistration? _registration;
  bool _disposed = false;

  @override
  Stream<RemotePushEvent> get events => _events.stream;

  @override
  RemotePushRegistration? get registration => _registration;

  @override
  List<RemotePushEvent> get pendingEvents {
    _removeExpiredPendingEvents();
    return List<RemotePushEvent>.unmodifiable(_pendingEvents.values);
  }

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {
    final ids = deliveryIds.toSet();
    if (ids.isEmpty) return;
    await _platform.acknowledgePendingEvents(ids);
    _pendingEvents.removeWhere((deliveryId, _) => ids.contains(deliveryId));
  }

  @override
  Future<void> setActiveNotificationTargetReference(String? targetReference) {
    return _platform.setActiveNotificationTargetReference(targetReference);
  }

  @override
  Future<RemotePushRegistration?> initialize() {
    if (_disposed) {
      throw StateError('Remote push client is disposed');
    }
    return _initialization ??= _initializeAndResetAfterFailure();
  }

  @override
  Future<void> pullPendingEvents() async {
    if (_disposed) {
      throw StateError('Remote push client is disposed');
    }
    await _acceptPlatformEvents(await _platform.loadPendingEvents());
  }

  Future<RemotePushRegistration?> _initializeAndResetAfterFailure() async {
    try {
      return await _initialize();
    } on Object {
      _initialization = null;
      rethrow;
    }
  }

  Future<RemotePushRegistration?> _initialize() async {
    await _platform.setEventHandler(_acceptPlatformEvents);
    await _acceptPlatformEvents(await _platform.loadPendingEvents());
    if (!await _platform.isConfigured()) {
      return null;
    }

    _requireSuccess(
      'create_notification_channel',
      await _platform.createNotificationChannel(
        id: awikiMessageNotificationChannelId,
        name: awikiMessageNotificationChannelName,
        description: awikiMessageNotificationChannelDescription,
      ),
      alsoAccept: const <String>{'10005'},
    );
    _requireSuccess(
      'create_structured_normal_notification_channel',
      await _platform.createNotificationChannel(
        id: awikiStructuredNormalNotificationChannelId,
        name: awikiStructuredNormalNotificationChannelName,
        description: awikiStructuredNormalNotificationChannelDescription,
      ),
      alsoAccept: const <String>{'10005'},
    );
    _requireSuccess('initialize', await _platform.initialize());
    final deviceId = (await _platform.getDeviceId()).trim();
    if (deviceId.isEmpty) {
      throw const RemotePushInitializationException(
        operation: 'get_device_id',
        code: 'empty_device_id',
      );
    }
    final appId = await _loadAndroidAppId();
    final clientVersion = await _loadClientVersion();
    return _registration = RemotePushRegistration(
      provider: aliyunEmasPushProvider,
      providerDeviceId: deviceId,
      platform: clientPlatform,
      clientProduct: awikiMeClientProduct,
      clientVersion: clientVersion,
      capabilities: const <String>[awikiAgentMessageV1Capability],
      appId: appId,
    );
  }

  Future<void> _acceptPlatformEvents(List<Object?> rawEvents) async {
    for (final rawEvent in rawEvents) {
      try {
        final event = RemotePushEvent.fromPlatform(rawEvent);
        if (event.kind == RemotePushEventKind.registrationChanged) {
          await _refreshRegistration();
        }
        _removeExpiredPendingEvents();
        final alreadyPending = _pendingEvents.containsKey(event.deliveryId);
        _retainPendingEvent(event);
        debugPrint(
          '[AWikiRemotePush] dart '
          '${alreadyPending ? 'alreadyPending' : 'firstSeen'} '
          '${event.kind.wireName}',
        );
        // Replays of a retained delivery must re-enter the coordinator so a
        // failed drain can run again inside the WorkManager window.
        if (!_events.isClosed) {
          _events.add(event);
        }
      } on FormatException catch (error) {
        debugPrint('[awiki_me][remote-push][invalid-event] $error');
      }
    }
  }

  Future<void> _refreshRegistration() async {
    final current = _registration;
    final deviceId = (await _platform.getDeviceId()).trim();
    if (deviceId.isEmpty) return;
    final appId = current?.appId ?? await _loadAndroidAppId();
    final clientVersion = current?.clientVersion ?? await _loadClientVersion();
    _registration = RemotePushRegistration(
      provider: aliyunEmasPushProvider,
      providerDeviceId: deviceId,
      platform: clientPlatform,
      clientProduct: current?.clientProduct ?? awikiMeClientProduct,
      clientVersion: clientVersion,
      capabilities:
          current?.capabilities ??
          const <String>[awikiAgentMessageV1Capability],
      appId: appId,
    );
  }

  Future<String> _loadClientVersion() async {
    final packageInfo = await _packageInfoLoader();
    final version = packageInfo.version.trim();
    final build = packageInfo.buildNumber.trim();
    final value = build.isEmpty || version.endsWith('+$build')
        ? version
        : '$version+$build';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$').hasMatch(value)) {
      throw const RemotePushInitializationException(
        operation: 'get_client_version',
        code: 'invalid_client_version',
      );
    }
    return value;
  }

  Future<String?> _loadAndroidAppId() async {
    if (clientPlatform != 'android') return null;
    final appId = (await _platform.getAppId()).trim();
    if (appId.isEmpty) {
      throw const RemotePushInitializationException(
        operation: 'get_app_id',
        code: 'empty_app_id',
      );
    }
    return appId;
  }

  void _retainPendingEvent(RemotePushEvent event) {
    if (event.kind != RemotePushEventKind.notificationOpened &&
        event.kind != RemotePushEventKind.messageReceived &&
        event.kind != RemotePushEventKind.notificationReceived &&
        event.kind != RemotePushEventKind.notificationReceivedInApp) {
      return;
    }
    final payload = <String, Object?>{};
    final messageId = event.payload['msgId'];
    if (messageId is String && messageId.trim().isNotEmpty) {
      payload['msgId'] = _boundedString(messageId);
    }
    final extraMap = event.payload['extraMap'];
    if (extraMap is Map<String, Object?>) {
      final envelope = <String, Object?>{};
      for (final key in _pendingEnvelopeKeys) {
        final value = extraMap[key];
        if (value is String) {
          envelope[key] = _boundedString(value);
        } else if (value is num || value is bool) {
          envelope[key] = value;
        }
      }
      if (envelope.isNotEmpty) payload['extraMap'] = envelope;
    }
    _removeExpiredPendingEvents();
    if (!_pendingEvents.containsKey(event.deliveryId) &&
        _pendingEvents.length == _maxPendingEvents) {
      _pendingEvents.remove(_pendingEvents.keys.first);
    }
    _pendingEvents[event.deliveryId] = RemotePushEvent(
      deliveryId: event.deliveryId,
      kind: event.kind,
      payload: payload,
      receivedAt: event.receivedAt,
    );
  }

  void _removeExpiredPendingEvents() {
    final cutoff = DateTime.now().toUtc().subtract(_maxPendingEventAge);
    _pendingEvents.removeWhere((_, event) => event.receivedAt.isBefore(cutoff));
  }

  String _boundedString(String value) {
    return value.length <= _maxPendingStringLength
        ? value
        : value.substring(0, _maxPendingStringLength);
  }

  void _requireSuccess(
    String operation,
    Map<dynamic, dynamic> result, {
    Set<String> alsoAccept = const <String>{},
  }) {
    final code = result['code']?.toString() ?? 'missing_code';
    if (code == _aliyunEmasSuccessCode || alsoAccept.contains(code)) {
      return;
    }
    throw RemotePushInitializationException(
      operation: operation,
      code: code,
      message: result['errorMsg']?.toString(),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _platform.dispose();
    await _events.close();
  }
}
