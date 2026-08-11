import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class LocalDataRecoveryPlatform {
  bool get isSupported;

  Future<void> resetSecureStorage();
}

class MethodChannelLocalDataRecoveryPlatform
    implements LocalDataRecoveryPlatform {
  const MethodChannelLocalDataRecoveryPlatform({
    MethodChannel channel = const MethodChannel(_channelName),
    bool? isSupported,
  }) : _channel = channel,
       _isSupportedOverride = isSupported;

  static const String _channelName =
      'ai.awiki.awikime/android_local_data_recovery';

  final MethodChannel _channel;
  final bool? _isSupportedOverride;

  @override
  bool get isSupported =>
      _isSupportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<void> resetSecureStorage() async {
    if (!isSupported) {
      throw UnsupportedError('local_data_recovery_platform_unsupported');
    }
    await _channel.invokeMethod<void>('resetLocalSecureStorage');
  }
}
