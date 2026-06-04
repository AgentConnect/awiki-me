abstract class NotificationFacade {
  Future<void> showSystemNotification({
    required String title,
    required String body,
  });

  Future<void> showInAppBanner({required String title, required String body});

  Future<void> updateBadgeCount(int count);
}
