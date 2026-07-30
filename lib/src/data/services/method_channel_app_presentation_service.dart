import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/app_presentation_service.dart';

final class MethodChannelAppPresentationService
    implements AppPresentationService {
  MethodChannelAppPresentationService({
    MethodChannel? channel,
    bool Function()? isMacOS,
  }) : _channel =
           channel ?? const MethodChannel('ai.awiki.awikime/app_presentation'),
       _isMacOS = isMacOS ?? (() => Platform.isMacOS);

  final MethodChannel _channel;
  final bool Function() _isMacOS;

  @override
  Future<AppPresentationState?> currentState() async {
    if (!_isMacOS()) {
      return null;
    }
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getState');
      final applicationActive = raw?['applicationActive'];
      final windowVisible = raw?['windowVisible'];
      final windowMiniaturized = raw?['windowMiniaturized'];
      if (applicationActive is! bool ||
          windowVisible is! bool ||
          windowMiniaturized is! bool) {
        debugPrint(
          '[awiki_me][app-presentation][invalid-state] '
          'value_type=${raw.runtimeType}',
        );
        return null;
      }
      return AppPresentationState(
        applicationActive: applicationActive,
        windowVisible: windowVisible,
        windowMiniaturized: windowMiniaturized,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('[awiki_me][app-presentation][error] code=${error.code}');
      return null;
    }
  }
}
