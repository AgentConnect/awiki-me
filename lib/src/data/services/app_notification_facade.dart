import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/services/notification_facade.dart';

class AppNotificationFacade implements NotificationFacade {
  AppNotificationFacade._(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;
  int _lastBadgeCount = 0;
  Future<void>? _initialization;

  static Future<AppNotificationFacade> create() async {
    final facade = AppNotificationFacade._(FlutterLocalNotificationsPlugin());
    facade._initializeInBackground();
    return facade;
  }

  void _initializeInBackground() {
    _initialization = _initialize()
        .timeout(const Duration(seconds: 5))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('[awiki_me][notification-init][error] $error');
        });
    unawaited(_initialization);
  }

  Future<void> _initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  @override
  Future<void> showSystemNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _initialization?.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      final id =
          DateTime.now().millisecondsSinceEpoch & Random().nextInt(0x7fffffff);
      const android = AndroidNotificationDetails(
        'awiki_me_messages',
        'Messages',
        channelDescription: 'AWiki Me message notifications',
        importance: Importance.max,
        priority: Priority.high,
      );
      const darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details = NotificationDetails(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );
      await _plugin.show(id, title, body, details);
    } catch (error) {
      debugPrint('[awiki_me][system-notification][error] $error');
    }
  }

  @override
  Future<void> showInAppBanner({
    required String title,
    required String body,
  }) async {
    debugPrint('[awiki_me][in-app-notification] $title: $body');
  }

  @override
  Future<void> updateBadgeCount(int count) async {
    if (_lastBadgeCount == count) {
      return;
    }
    _lastBadgeCount = count;
  }
}
