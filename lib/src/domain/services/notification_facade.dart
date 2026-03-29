abstract class NotificationFacade {
  Future<void> showInAppBanner({
    required String title,
    required String body,
  });

  Future<void> updateBadgeCount(int count);
}

