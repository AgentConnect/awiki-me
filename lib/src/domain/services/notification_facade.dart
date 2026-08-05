import '../entities/notification_target.dart';

abstract class NotificationFacade {
  Stream<NotificationActivation> get activations;

  Future<NotificationActivation?> initialActivation();

  Future<void> showSystemNotification({
    required String title,
    required String body,
    NotificationTarget? target,
  });

  Future<void> updateBadgeCount(int count);

  Future<void> dispose();
}
