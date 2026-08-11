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

  /// Plays one bounded foreground cue without creating a tray notification.
  Future<StructuredUrgentCueResult> playStructuredUrgentCue();

  Future<void> updateBadgeCount(int count);

  Future<void> dispose();
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
