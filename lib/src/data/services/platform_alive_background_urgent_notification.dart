import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/services/notification_facade.dart';

final class PlatformAliveBackgroundUrgentNotification {
  PlatformAliveBackgroundUrgentNotification({
    MethodChannel? channel,
    bool Function()? isAndroid,
  }) : _channel =
           channel ??
           const MethodChannel(
             'ai.awiki.awikime/alive_background_urgent_notification',
           ),
       _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid);

  final MethodChannel _channel;
  final bool Function() _isAndroid;

  Future<AliveBackgroundNotificationState> currentState() async {
    if (!_isAndroid()) {
      return const AliveBackgroundNotificationState.unavailable();
    }
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('getState');
      return _decodeState(raw);
    } on MissingPluginException {
      return const AliveBackgroundNotificationState.unavailable();
    } on PlatformException {
      return const AliveBackgroundNotificationState.unavailable();
    }
  }

  Future<AliveBackgroundNotificationSubmission> submit(
    AliveBackgroundUrgentNotification notification,
  ) async {
    if (!_isAndroid()) {
      return AliveBackgroundNotificationSubmission.unavailable;
    }
    try {
      final raw = await _channel
          .invokeMethod<String>('submit', <String, Object>{
            'native_id': notification.nativeId,
            'agent_label': notification.agentLabel,
            'task_name': notification.taskName,
            'summary': notification.summary,
            'opaque_message_reference': notification.opaqueMessageReference,
            'expires_at_epoch_seconds': notification.expiresAtEpochSeconds,
          });
      return AliveBackgroundNotificationSubmission.values.firstWhere(
        (candidate) => candidate.name == raw,
        orElse: () => AliveBackgroundNotificationSubmission.unavailable,
      );
    } on MissingPluginException {
      return AliveBackgroundNotificationSubmission.unavailable;
    } on PlatformException {
      return AliveBackgroundNotificationSubmission.unavailable;
    }
  }

  Future<void> cancel(int nativeId) async {
    if (!_isAndroid()) return;
    try {
      await _channel.invokeMethod<void>('cancel', <String, Object>{
        'native_id': nativeId,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<bool> openFullScreenSettings() async {
    if (!_isAndroid()) return false;
    try {
      return await _channel.invokeMethod<bool>('openFullScreenSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  AliveBackgroundNotificationState _decodeState(Map<String, Object?>? raw) {
    if (raw == null ||
        raw['platform_supported'] is! bool ||
        raw['native_activity_resumed'] is! bool ||
        raw['flutter_channel_attached'] is! bool ||
        raw['notifications_allowed'] is! bool ||
        raw['channel_state'] is! String ||
        raw['full_screen_access'] is! String) {
      return const AliveBackgroundNotificationState.unavailable();
    }
    final channelState = AliveBackgroundNotificationChannelState.values
        .where((candidate) => candidate.name == raw['channel_state'])
        .firstOrNull;
    final fullScreenAccess = AliveBackgroundFullScreenAccess.values
        .where((candidate) => candidate.name == raw['full_screen_access'])
        .firstOrNull;
    if (channelState == null || fullScreenAccess == null) {
      return const AliveBackgroundNotificationState.unavailable();
    }
    return AliveBackgroundNotificationState(
      platformSupported: raw['platform_supported']! as bool,
      nativeActivityResumed: raw['native_activity_resumed']! as bool,
      flutterChannelAttached: raw['flutter_channel_attached']! as bool,
      notificationsAllowed: raw['notifications_allowed']! as bool,
      channelState: channelState,
      fullScreenAccess: fullScreenAccess,
    );
  }
}
