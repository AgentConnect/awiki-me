import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/desktop_startup_presentation_service.dart';

final class MethodChannelDesktopStartupPresentationService
    implements DesktopStartupPresentationService {
  const MethodChannelDesktopStartupPresentationService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.awiki.awikime/desktop_startup';

  final MethodChannel _channel;

  @override
  Future<void> presentReadyContent() =>
      _channel.invokeMethod<void>('presentReadyContent');
}

DesktopStartupPresentationService buildDesktopStartupPresentationService({
  TargetPlatform? targetPlatform,
  MethodChannel? channel,
}) {
  final platform = targetPlatform ?? defaultTargetPlatform;
  if (platform == TargetPlatform.macOS || platform == TargetPlatform.windows) {
    return MethodChannelDesktopStartupPresentationService(channel: channel);
  }
  return const NoopDesktopStartupPresentationService();
}
