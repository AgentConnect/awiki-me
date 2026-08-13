import 'package:awiki_me/src/app/macos_notification_smoke.dart';
import 'package:awiki_me/src/domain/entities/notification_target.dart';
import 'package:awiki_me/src/domain/services/notification_facade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'debug macOS smoke gate sends one AWiki Me system notification',
    () async {
      final notification = _RecordingNotificationFacade();

      await runMacosNotificationSmoke(
        notificationFacade: notification,
        enabled: true,
        isMacOS: true,
        isReleaseMode: false,
        delay: Duration.zero,
      );

      expect(notification.systemNotifications, <({String title, String body})>[
        (
          title: 'AWiki Me · Coding Agent 已完成',
          body: 'macOS 通知探针已完成；下一步验证真实终态消息。',
        ),
      ]);
    },
  );

  test('release build never runs the macOS notification smoke probe', () async {
    final notification = _RecordingNotificationFacade();

    await runMacosNotificationSmoke(
      notificationFacade: notification,
      enabled: true,
      isMacOS: true,
      isReleaseMode: true,
      delay: Duration.zero,
    );

    expect(notification.systemNotifications, isEmpty);
  });
}

class _RecordingNotificationFacade implements NotificationFacade {
  final List<({String title, String body})> systemNotifications =
      <({String title, String body})>[];

  @override
  Future<void> showSystemNotification({
    required String title,
    required String body,
    NotificationTarget? target,
  }) async {
    systemNotifications.add((title: title, body: body));
  }

  @override
  Future<StructuredNotificationSubmission> showStructuredNotification(
    StructuredNotification notification,
  ) async => StructuredNotificationSubmission.submitted;

  @override
  Future<StructuredNotificationEligibility>
  structuredNotificationEligibility() async =>
      StructuredNotificationEligibility.allowed;

  @override
  Future<StructuredUrgentCueResult> playStructuredUrgentCue() async =>
      StructuredUrgentCueResult.played;

  @override
  Future<void> stopStructuredUrgentCue() async {}

  @override
  Future<void> updateBadgeCount(int count) async {}

  @override
  Stream<NotificationActivation> get activations =>
      const Stream<NotificationActivation>.empty();

  @override
  Future<NotificationActivation?> initialActivation() async => null;

  @override
  Future<void> dispose() async {}
}
