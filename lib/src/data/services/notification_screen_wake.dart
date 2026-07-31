import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class NotificationScreenWake {
  Future<void> wakeIfNeeded();
}

class PlatformNotificationScreenWake implements NotificationScreenWake {
  PlatformNotificationScreenWake({
    MethodChannel? channel,
    bool Function()? isAndroid,
  }) : _channel =
           channel ??
           const MethodChannel('ai.awiki.awikime/remote_push_events'),
       _isAndroid = isAndroid ?? _isAndroidPlatform;

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  static bool _isAndroidPlatform() => Platform.isAndroid;

  @override
  Future<void> wakeIfNeeded() async {
    if (!_isAndroid()) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('wakeNotificationScreen');
    } catch (error) {
      debugPrint('[awiki_me][notification-screen-wake][error] $error');
    }
  }
}

Future<void> submitNotificationAndWake({
  required Future<void> Function() submit,
  required NotificationScreenWake screenWake,
}) async {
  await submit();
  await screenWake.wakeIfNeeded();
}
