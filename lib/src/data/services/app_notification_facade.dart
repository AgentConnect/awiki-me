import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;

import '../../application/desktop_shell_service.dart';
import '../../domain/entities/notification_target.dart';
import '../../domain/services/notification_facade.dart';
import '../../domain/services/notification_channels.dart';
import 'mac_menu_bar_status_service.dart';
import 'notification_screen_wake.dart';
import 'platform_structured_urgent_cue.dart';
import 'platform_alive_background_urgent_notification.dart';

class AppNotificationFacade
    implements NotificationFacade, AliveBackgroundUrgentNotificationFacade {
  AppNotificationFacade._(
    FlutterLocalNotificationsPlugin plugin,
    MacMenuBarStatusService menuBarStatus,
    DesktopShellService desktopShell,
    NotificationScreenWake screenWake,
    PlatformStructuredUrgentCue urgentCue,
    PlatformAliveBackgroundUrgentNotification aliveBackgroundUrgent,
  ) : _plugin = plugin,
      _menuBarStatus = menuBarStatus,
      _desktopShell = desktopShell,
      _screenWake = screenWake,
      _structuredSubmit = plugin.show,
      _urgentCue = urgentCue.play,
      _urgentCueStop = urgentCue.stop,
      _aliveBackgroundUrgent = aliveBackgroundUrgent,
      _structuredEligibility = _StructuredNotificationEligibilityQuery(
        plugin,
      ).call;

  AppNotificationFacade.forTesting({
    required StructuredNotificationSubmit structuredSubmit,
    required Future<void> Function() urgentCue,
    Future<void> Function()? urgentCueStop,
    required Future<StructuredNotificationEligibility> Function()
    structuredEligibility,
    NotificationScreenWake? screenWake,
    PlatformAliveBackgroundUrgentNotification? aliveBackgroundUrgent,
  }) : _plugin = FlutterLocalNotificationsPlugin(),
       _menuBarStatus = MacMenuBarStatusService(isMacOS: () => false),
       _desktopShell = const NoopDesktopShellService(),
       _screenWake = screenWake ?? _NoopNotificationScreenWake(),
       _structuredSubmit = structuredSubmit,
       _urgentCue = urgentCue,
       _urgentCueStop = urgentCueStop ?? _noopUrgentCueStop,
       _aliveBackgroundUrgent =
           aliveBackgroundUrgent ?? PlatformAliveBackgroundUrgentNotification(),
       _structuredEligibility = structuredEligibility {
    _initialization = Future<void>.value();
  }

  final FlutterLocalNotificationsPlugin _plugin;
  final MacMenuBarStatusService _menuBarStatus;
  final DesktopShellService _desktopShell;
  final NotificationScreenWake _screenWake;
  final StructuredNotificationSubmit _structuredSubmit;
  final Future<void> Function() _urgentCue;
  final Future<void> Function() _urgentCueStop;
  final PlatformAliveBackgroundUrgentNotification _aliveBackgroundUrgent;
  final Future<StructuredNotificationEligibility> Function()
  _structuredEligibility;
  final StreamController<NotificationActivation> _activations =
      StreamController<NotificationActivation>.broadcast(sync: true);
  int _lastBadgeCount = 0;
  Future<void>? _initialization;
  NotificationActivation? _initialActivation;
  bool _disposed = false;

  static Future<AppNotificationFacade> create({
    DesktopShellService? desktopShell,
  }) async {
    final urgentCue = PlatformStructuredUrgentCue();
    final facade = AppNotificationFacade._(
      FlutterLocalNotificationsPlugin(),
      MacMenuBarStatusService(),
      desktopShell ?? const NoopDesktopShellService(),
      PlatformNotificationScreenWake(),
      urgentCue,
      PlatformAliveBackgroundUrgentNotification(),
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
      linux: const LinuxInitializationSettings(defaultActionName: 'Open'),
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

    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _initialActivation = NotificationActivation.fromPayload(
          launchDetails?.notificationResponse?.payload,
        );
      }
    } on UnimplementedError {
      // Some desktop plugin implementations do not expose launch details.
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
    NotificationTarget? target,
  }) async {
    try {
      await _initialization?.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      final id =
          DateTime.now().millisecondsSinceEpoch & Random().nextInt(0x7fffffff);
      const android = AndroidNotificationDetails(
        awikiMessageNotificationChannelId,
        awikiMessageNotificationChannelName,
        channelDescription: awikiMessageNotificationChannelDescription,
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
      await submitNotificationAndWake(
        submit: () => _plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
          payload: target?.encode(),
        ),
        screenWake: _screenWake,
      );
      debugPrint(
        '[awiki_me][system-notification][submitted] '
        'target=${target == null ? 'none' : 'conversation'}',
      );
    } catch (error) {
      debugPrint('[awiki_me][system-notification][error] $error');
    }
  }

  @override
  Future<StructuredNotificationSubmission> showStructuredNotification(
    StructuredNotification notification,
  ) async {
    try {
      await _initialization?.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      final eligibility = await _structuredEligibility();
      if (eligibility == StructuredNotificationEligibility.denied) {
        return StructuredNotificationSubmission.permissionDenied;
      }
      if (eligibility == StructuredNotificationEligibility.unavailable) {
        return StructuredNotificationSubmission.unavailable;
      }
      await _structuredSubmit(
        id: notification.nativeId,
        title: notification.title,
        body: notification.body,
        notificationDetails: structuredNotificationDetails(notification.level),
        payload: notification.target?.encode(),
      );
      debugPrint(
        '[awiki_me][structured-notification][submitted] '
        'level=${notification.level.name} '
        'target=${notification.target == null ? 'none' : 'conversation'}',
      );
      return StructuredNotificationSubmission.submitted;
    } on Object {
      debugPrint('[awiki_me][structured-notification][failed]');
      return StructuredNotificationSubmission.unavailable;
    }
  }

  @override
  Future<StructuredNotificationEligibility>
  structuredNotificationEligibility() async {
    try {
      await _initialization?.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {},
      );
      return await _structuredEligibility();
    } on Object {
      return StructuredNotificationEligibility.unavailable;
    }
  }

  @override
  Future<StructuredUrgentCueResult> playStructuredUrgentCue() async {
    try {
      await _urgentCue();
      return StructuredUrgentCueResult.played;
    } on Object {
      debugPrint('[awiki_me][structured-urgent-cue][failed]');
      return StructuredUrgentCueResult.failed;
    }
  }

  @override
  Future<void> stopStructuredUrgentCue() async {
    try {
      await _urgentCueStop();
    } on Object {
      debugPrint('[awiki_me][structured-urgent-cue-stop][failed]');
    }
  }

  @override
  Future<AliveBackgroundNotificationState> aliveBackgroundNotificationState() =>
      _aliveBackgroundUrgent.currentState();

  @override
  Future<AliveBackgroundNotificationSubmission>
  showAliveBackgroundUrgentNotification(
    AliveBackgroundUrgentNotification notification,
  ) => _aliveBackgroundUrgent.submit(notification);

  @override
  Future<void> cancelAliveBackgroundUrgentNotification(int nativeId) =>
      _aliveBackgroundUrgent.cancel(nativeId);

  @override
  Future<bool> openAliveBackgroundFullScreenSettings() =>
      _aliveBackgroundUrgent.openFullScreenSettings();

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
    await stopStructuredUrgentCue();
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

typedef StructuredNotificationSubmit =
    Future<void> Function({
      required int id,
      String? title,
      String? body,
      NotificationDetails? notificationDetails,
      String? payload,
    });

Future<void> _noopUrgentCueStop() async {}

final class _StructuredNotificationEligibilityQuery {
  const _StructuredNotificationEligibilityQuery(this.plugin);

  final FlutterLocalNotificationsPlugin plugin;

  Future<StructuredNotificationEligibility> call() async {
    if (kIsWeb) {
      return StructuredNotificationEligibility.unavailable;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final enabled = await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return switch (enabled) {
        true => StructuredNotificationEligibility.allowed,
        false => StructuredNotificationEligibility.denied,
        null => StructuredNotificationEligibility.unavailable,
      };
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final options = await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (options == null) {
        return StructuredNotificationEligibility.unavailable;
      }
      return options.isEnabled && options.isAlertEnabled
          ? StructuredNotificationEligibility.allowed
          : StructuredNotificationEligibility.denied;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final options = await plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      if (options == null) {
        return StructuredNotificationEligibility.unavailable;
      }
      return options.isEnabled && options.isAlertEnabled
          ? StructuredNotificationEligibility.allowed
          : StructuredNotificationEligibility.denied;
    }
    return StructuredNotificationEligibility.unavailable;
  }
}

final class _NoopNotificationScreenWake implements NotificationScreenWake {
  @override
  Future<void> wakeIfNeeded() async {}
}

@visibleForTesting
NotificationDetails structuredNotificationDetails(
  StructuredNotificationLevel level,
) {
  final urgent = level == StructuredNotificationLevel.urgent;
  final android = AndroidNotificationDetails(
    urgent
        ? awikiStructuredUrgentNotificationChannelId
        : awikiStructuredNormalNotificationChannelId,
    urgent
        ? awikiStructuredUrgentNotificationChannelName
        : awikiStructuredNormalNotificationChannelName,
    channelDescription: urgent
        ? awikiStructuredUrgentNotificationChannelDescription
        : awikiStructuredNormalNotificationChannelDescription,
    importance: urgent ? Importance.high : Importance.defaultImportance,
    priority: urgent ? Priority.high : Priority.defaultPriority,
    playSound: urgent,
    enableVibration: urgent,
    vibrationPattern: urgent ? Int64List.fromList(<int>[0, 180]) : null,
    onlyAlertOnce: true,
    channelBypassDnd: false,
    fullScreenIntent: false,
    category: AndroidNotificationCategory.message,
    visibility: NotificationVisibility.private,
  );
  final darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: urgent,
  );
  return NotificationDetails(
    android: android,
    iOS: darwin,
    macOS: darwin,
    windows: const WindowsNotificationDetails(
      duration: WindowsNotificationDuration.short,
    ),
  );
}
