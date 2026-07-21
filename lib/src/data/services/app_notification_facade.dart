import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;

import '../../application/desktop_shell_service.dart';
import '../../domain/entities/notification_target.dart';
import '../../domain/services/notification_facade.dart';
import 'mac_menu_bar_status_service.dart';

class AppNotificationFacade implements NotificationFacade {
  AppNotificationFacade._(
    this._plugin,
    this._menuBarStatus,
    this._desktopShell,
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final MacMenuBarStatusService _menuBarStatus;
  final DesktopShellService _desktopShell;
  final StreamController<NotificationActivation> _activations =
      StreamController<NotificationActivation>.broadcast(sync: true);
  int _lastBadgeCount = 0;
  Future<void>? _initialization;
  NotificationActivation? _initialActivation;
  bool _disposed = false;

  static Future<AppNotificationFacade> create({
    DesktopShellService? desktopShell,
  }) async {
    final facade = AppNotificationFacade._(
      FlutterLocalNotificationsPlugin(),
      MacMenuBarStatusService(),
      desktopShell ?? const NoopDesktopShellService(),
    );
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
    final windowsIconPath = p.join(
      p.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
      'assets',
      'branding',
      'awiki-me-logo.png',
    );
    final settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: WindowsInitializationSettings(
        appName: 'AWiki Me',
        appUserModelId: 'AWiki.AWikiMe',
        guid: '42f66431-9bea-46c4-ac14-475b9044a2be',
        iconPath: windowsIconPath,
      ),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        if (!_disposed) {
          _activations.add(
            NotificationActivation.fromPayload(response.payload),
          );
        }
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _initialActivation = NotificationActivation.fromPayload(
        launchDetails?.notificationResponse?.payload,
      );
    }

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
  Stream<NotificationActivation> get activations => _activations.stream;

  @override
  Future<NotificationActivation?> initialActivation() async {
    await _initialization;
    final activation = _initialActivation;
    _initialActivation = null;
    return activation;
  }

  @override
  Future<void> showSystemNotification({
    required String title,
    required String body,
    required NotificationTarget target,
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
      const windows = WindowsNotificationDetails(
        duration: WindowsNotificationDuration.short,
      );
      const details = NotificationDetails(
        android: android,
        iOS: darwin,
        macOS: darwin,
        windows: windows,
      );
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: target.encode(),
      );
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
    final normalizedCount = max(0, count);
    if (_lastBadgeCount == normalizedCount) {
      return;
    }
    _lastBadgeCount = normalizedCount;
    try {
      await _menuBarStatus.setUnreadCount(normalizedCount);
    } catch (error) {
      debugPrint('[awiki_me][menu-bar-status][error] $error');
    }
    try {
      await _desktopShell.setUnreadCount(normalizedCount);
    } catch (error) {
      debugPrint('[awiki_me][desktop-shell-unread][error] $error');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _initialization;
    if (Platform.isWindows) {
      _plugin
          .resolvePlatformSpecificImplementation<
            FlutterLocalNotificationsWindows
          >()
          ?.dispose();
    }
    await _activations.close();
  }
}
