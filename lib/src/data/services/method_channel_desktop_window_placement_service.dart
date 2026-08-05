import 'package:flutter/services.dart';

import '../../application/desktop_window_placement_service.dart';

final class MethodChannelDesktopWindowPlacementService
    implements DesktopWindowPlacementService {
  const MethodChannelDesktopWindowPlacementService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.awiki.awikime/desktop_window';

  final MethodChannel _channel;

  @override
  Future<void> resetPlacement() =>
      _channel.invokeMethod<void>('resetPlacement');
}
