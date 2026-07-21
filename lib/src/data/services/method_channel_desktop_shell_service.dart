import 'dart:async';

import 'package:flutter/services.dart';

import '../../application/desktop_shell_service.dart';

class MethodChannelDesktopShellService implements DesktopShellService {
  MethodChannelDesktopShellService({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('ai.awiki.awikime/desktop_shell');

  final MethodChannel _channel;
  final StreamController<DesktopShellEvent> _events =
      StreamController<DesktopShellEvent>.broadcast(sync: true);
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<DesktopShellEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    _channel.setMethodCallHandler(handleMethodCall);
    try {
      await _channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // Non-Windows hosts intentionally use the no-op native boundary.
    }
  }

  Future<Object?> handleMethodCall(MethodCall call) async {
    if (call.method != 'shellEvent') {
      throw MissingPluginException(
        'Unsupported desktop shell call: ${call.method}',
      );
    }
    final event = DesktopShellEvent.tryParse(call.arguments);
    if (event == null) {
      throw PlatformException(code: 'desktop_shell_event_invalid');
    }
    if (!_disposed) {
      _events.add(event);
    }
    return null;
  }

  @override
  Future<DesktopStorageRoots> getStorageRoots() async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'getStorageRoots',
    );
    final support = _requiredPath(raw, 'support');
    final cache = _requiredPath(raw, 'cache');
    final temp = _requiredPath(raw, 'temp');
    return DesktopStorageRoots(support: support, cache: cache, temp: temp);
  }

  @override
  Future<void> showWindow() => _channel.invokeMethod<void>('showWindow');

  @override
  Future<void> hideWindow() => _channel.invokeMethod<void>('hideWindow');

  @override
  Future<void> setUnreadCount(int count) => _channel.invokeMethod<void>(
    'setUnreadCount',
    <String, Object?>{'count': count < 0 ? 0 : count},
  );

  @override
  Future<void> completeExit() => _channel.invokeMethod<void>('completeExit');

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_initialized) {
      _channel.setMethodCallHandler(null);
    }
    await _events.close();
  }

  String _requiredPath(Map<String, Object?>? raw, String key) {
    final value = raw?[key];
    if (value is! String || value.trim().isEmpty) {
      throw PlatformException(code: 'desktop_storage_roots_invalid');
    }
    return value.trim();
  }
}
