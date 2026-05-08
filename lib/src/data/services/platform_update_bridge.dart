import 'dart:io';

import 'package:flutter/services.dart';

abstract class PlatformUpdateBridge {
  Future<bool> canRequestPackageInstalls();

  Future<void> openInstallPermissionSettings();

  Future<void> installApk(String filePath);
}

class MethodChannelPlatformUpdateBridge implements PlatformUpdateBridge {
  static const MethodChannel _channel = MethodChannel(
    'ai.awiki.awikime/app_update',
  );

  @override
  Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return (await _channel.invokeMethod<bool>('canRequestPackageInstalls')) ??
        false;
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  @override
  Future<void> installApk(String filePath) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('APK install is only supported on Android.');
    }
    await _channel.invokeMethod<void>(
      'installApk',
      <String, Object?>{'filePath': filePath},
    );
  }
}
