import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const structuredUrgentCueChannelName = 'ai.awiki.awikime/structured_urgent_cue';
const structuredUrgentCueDuration = Duration(seconds: 30);

final class PlatformStructuredUrgentCue {
  PlatformStructuredUrgentCue({
    MethodChannel? channel,
    bool Function()? isAndroid,
  }) : _channel =
           channel ?? const MethodChannel(structuredUrgentCueChannelName),
       _isAndroid = isAndroid ?? _defaultIsAndroid;

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  Future<void> play() async {
    if (!_isAndroid()) {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
      return;
    }
    final started = await _channel.invokeMethod<bool>('start', <String, Object>{
      'max_duration_ms': structuredUrgentCueDuration.inMilliseconds,
    });
    if (started != true) {
      throw PlatformException(code: 'structured_urgent_cue_unavailable');
    }
  }

  Future<void> stop() async {
    if (_isAndroid()) {
      await _channel.invokeMethod<void>('stop');
    }
  }
}

bool _defaultIsAndroid() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
