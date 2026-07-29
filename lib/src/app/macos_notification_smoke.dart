import '../domain/services/notification_facade.dart';

Future<void> runMacosNotificationSmoke({
  required NotificationFacade notificationFacade,
  required bool enabled,
  required bool isMacOS,
  required bool isReleaseMode,
  required Duration delay,
}) async {
  if (!enabled || !isMacOS || isReleaseMode) {
    return;
  }
  await Future<void>.delayed(delay);
  await notificationFacade.showSystemNotification(
    title: 'AWiki Me · Coding Agent 已完成',
    body: 'macOS 通知探针已完成；下一步验证真实终态消息。',
  );
}
