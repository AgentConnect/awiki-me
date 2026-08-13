import '../entities/notification_target.dart';

abstract class NotificationFacade {
  Stream<NotificationActivation> get activations;

  Future<NotificationActivation?> initialActivation();

  Future<void> showSystemNotification({
    required String title,
    required String body,
    NotificationTarget? target,
  });

  /// Submits a validated structured-message presentation using the caller's
  /// durable native ID. Implementations must not wake the screen or bypass
  /// platform focus/DND policy.
  Future<StructuredNotificationSubmission> showStructuredNotification(
    StructuredNotification notification,
  );

  /// Reports whether App-owned tray presentation may be attempted. This is a
  /// policy input, not proof that a later notification became user-visible.
  Future<StructuredNotificationEligibility> structuredNotificationEligibility();

  /// Starts one bounded foreground cue without creating a tray notification.
  Future<StructuredUrgentCueResult> playStructuredUrgentCue();

  /// Stops any active foreground urgent cue. Implementations must be
  /// idempotent so every overlay dismissal path can call it safely.
  Future<void> stopStructuredUrgentCue();

  Future<void> updateBadgeCount(int count);

  Future<void> dispose();
}

/// Optional Android capability used only while the Flutter engine and remote
/// Push channel are alive. Implementations must re-check native lifecycle and
/// notification policy atomically before submitting a surface.
abstract interface class AliveBackgroundUrgentNotificationFacade {
  Future<AliveBackgroundNotificationState> aliveBackgroundNotificationState();

  Future<AliveBackgroundNotificationSubmission>
  showAliveBackgroundUrgentNotification(
    AliveBackgroundUrgentNotification notification,
  );

  Future<void> cancelAliveBackgroundUrgentNotification(int nativeId);

  /// Opens the Android 14+ per-App full-screen-intent settings screen. This
  /// must only be invoked from an explicit user gesture.
  Future<bool> openAliveBackgroundFullScreenSettings();
}

enum AliveBackgroundNotificationChannelState {
  high,
  userReduced,
  blocked,
  unavailable,
}

enum AliveBackgroundFullScreenAccess { allowed, denied, unavailable }

final class AliveBackgroundNotificationState {
  const AliveBackgroundNotificationState({
    required this.platformSupported,
    required this.nativeActivityResumed,
    required this.flutterChannelAttached,
    required this.notificationsAllowed,
    required this.channelState,
    required this.fullScreenAccess,
  });

  const AliveBackgroundNotificationState.unavailable()
    : platformSupported = false,
      nativeActivityResumed = false,
      flutterChannelAttached = false,
      notificationsAllowed = false,
      channelState = AliveBackgroundNotificationChannelState.unavailable,
      fullScreenAccess = AliveBackgroundFullScreenAccess.unavailable;

  final bool platformSupported;
  final bool nativeActivityResumed;
  final bool flutterChannelAttached;
  final bool notificationsAllowed;
  final AliveBackgroundNotificationChannelState channelState;
  final AliveBackgroundFullScreenAccess fullScreenAccess;

  bool get isExactAliveBackground =>
      platformSupported &&
      !nativeActivityResumed &&
      flutterChannelAttached &&
      notificationsAllowed &&
      channelState != AliveBackgroundNotificationChannelState.blocked &&
      channelState != AliveBackgroundNotificationChannelState.unavailable;
}

enum AliveBackgroundNotificationSubmission {
  fullScreenRequested,
  fallbackSubmitted,
  suppressedForeground,
  suppressedPermission,
  suppressedChannel,
  suppressedDetached,
  unavailable,
}

final class AliveBackgroundUrgentNotification {
  AliveBackgroundUrgentNotification({
    required this.nativeId,
    required String agentLabel,
    required String taskName,
    required String summary,
    required String opaqueMessageReference,
    required this.expiresAtEpochSeconds,
  }) : agentLabel = _required(agentLabel, 'agentLabel', 128),
       taskName = _required(taskName, 'taskName', 160),
       summary = _required(summary, 'summary', 240),
       opaqueMessageReference = _opaqueMessageReference(
         opaqueMessageReference,
       ) {
    if (nativeId < 0 || nativeId > 0x7fffffff) {
      throw ArgumentError.value(nativeId, 'nativeId');
    }
    if (expiresAtEpochSeconds <= 0) {
      throw ArgumentError.value(expiresAtEpochSeconds, 'expiresAtEpochSeconds');
    }
  }

  final int nativeId;
  final String agentLabel;
  final String taskName;
  final String summary;
  final String opaqueMessageReference;
  final int expiresAtEpochSeconds;

  static String _required(String value, String name, int maxLength) {
    if (value.trim().isEmpty ||
        value.trim() != value ||
        value.length > maxLength ||
        value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
      throw ArgumentError.value(value, name);
    }
    return value;
  }

  static String _opaqueMessageReference(String value) {
    if (!RegExp(r'^message_[A-Za-z0-9_-]{24}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'opaqueMessageReference');
    }
    return value;
  }
}

enum StructuredNotificationLevel { normal, urgent }

enum StructuredNotificationEligibility { allowed, denied, unavailable }

enum StructuredNotificationSubmission {
  submitted,
  permissionDenied,
  unavailable,
}

enum StructuredUrgentCueResult { played, failed }

final class StructuredNotification {
  StructuredNotification({
    required this.nativeId,
    required String title,
    required String body,
    required this.level,
    this.target,
  }) : title = _required(title, 'title'),
       body = _required(body, 'body') {
    if (nativeId < 0 || nativeId > 0x7fffffff) {
      throw ArgumentError.value(nativeId, 'nativeId');
    }
  }

  final int nativeId;
  final String title;
  final String body;
  final StructuredNotificationLevel level;
  final NotificationTarget? target;

  static String _required(String value, String name) {
    if (value.trim().isEmpty || value.trim() != value) {
      throw ArgumentError.value(value, name);
    }
    return value;
  }
}
