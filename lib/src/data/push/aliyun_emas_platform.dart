import 'package:flutter/services.dart';

typedef RemotePushPlatformEventHandler =
    Future<void> Function(List<Object?> events);

abstract interface class AliyunEmasPlatform {
  Future<void> setEventHandler(RemotePushPlatformEventHandler? handler);

  Future<bool> isConfigured();

  Future<Map<dynamic, dynamic>> initialize();

  Future<String> getDeviceId();

  Future<Map<dynamic, dynamic>> createNotificationChannel({
    required String id,
    required String name,
    required String description,
  });

  Future<List<Object?>> loadPendingEvents();

  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds);

  Future<void> dispose();
}

class PluginAliyunEmasPlatform implements AliyunEmasPlatform {
  PluginAliyunEmasPlatform({MethodChannel? eventChannel})
    : _eventChannel =
          eventChannel ??
          const MethodChannel('ai.awiki.awikime/remote_push_events');

  final MethodChannel _eventChannel;
  RemotePushPlatformEventHandler? _handler;

  @override
  Future<void> setEventHandler(RemotePushPlatformEventHandler? handler) async {
    _handler = handler;
    _eventChannel.setMethodCallHandler(
      handler == null ? null : _handleMethodCall,
    );
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onRemotePushEvents') {
      throw MissingPluginException('Unsupported method ${call.method}');
    }
    final raw = call.arguments;
    if (raw is! List) {
      throw const FormatException('Remote push event batch must be a list');
    }
    await _handler?.call(raw.cast<Object?>());
    return true;
  }

  @override
  Future<bool> isConfigured() async {
    return await _eventChannel.invokeMethod<bool>('isConfigured') ?? false;
  }

  @override
  Future<Map<dynamic, dynamic>> initialize() async {
    return await _eventChannel.invokeMapMethod<dynamic, dynamic>(
          'initialize',
        ) ??
        <dynamic, dynamic>{};
  }

  @override
  Future<String> getDeviceId() async {
    return await _eventChannel.invokeMethod<String>('getDeviceId') ?? '';
  }

  @override
  Future<Map<dynamic, dynamic>> createNotificationChannel({
    required String id,
    required String name,
    required String description,
  }) async {
    return await _eventChannel.invokeMapMethod<dynamic, dynamic>(
          'createNotificationChannel',
          <String, Object?>{'id': id, 'name': name, 'description': description},
        ) ??
        <dynamic, dynamic>{};
  }

  @override
  Future<List<Object?>> loadPendingEvents() async {
    final events = await _eventChannel.invokeListMethod<Object?>(
      'loadPendingEvents',
    );
    return events ?? const <Object?>[];
  }

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) {
    return _eventChannel.invokeMethod<void>(
      'acknowledgePendingEvents',
      deliveryIds.toList(growable: false),
    );
  }

  @override
  Future<void> dispose() => setEventHandler(null);
}
