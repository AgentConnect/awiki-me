import 'dart:io';

import 'package:flutter/services.dart';

class MacMenuBarStatusService {
  MacMenuBarStatusService({MethodChannel? channel, bool Function()? isMacOS})
    : _channel =
          channel ?? const MethodChannel('ai.awiki.awikime/menu_bar_status'),
      _isMacOS = isMacOS ?? (() => Platform.isMacOS);

  final MethodChannel _channel;
  final bool Function() _isMacOS;

  Future<void> setUnreadCount(int count) async {
    if (!_isMacOS()) {
      return;
    }
    await _channel.invokeMethod<void>('setUnreadCount', <String, Object?>{
      'count': count < 0 ? 0 : count,
    });
  }
}
