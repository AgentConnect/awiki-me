import 'package:flutter/foundation.dart';

import '../../domain/services/notification_facade.dart';

class AppNotificationFacade implements NotificationFacade {
  int _lastBadgeCount = 0;

  @override
  Future<void> showInAppBanner({
    required String title,
    required String body,
  }) async {
    debugPrint('[awiki_me][in-app-notification] $title: $body');
  }

  @override
  Future<void> updateBadgeCount(int count) async {
    _lastBadgeCount = count;
    debugPrint('[awiki_me][badge] unread=$_lastBadgeCount');
  }
}
