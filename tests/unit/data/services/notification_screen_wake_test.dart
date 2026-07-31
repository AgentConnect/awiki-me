import 'package:awiki_me/src/data/services/notification_screen_wake.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'requests screen wake only after the notification is submitted',
    () async {
      final events = <String>[];
      final wake = _RecordingNotificationScreenWake(events);

      await submitNotificationAndWake(
        submit: () async {
          events.add('notification_submitted');
        },
        screenWake: wake,
      );

      expect(events, <String>[
        'notification_submitted',
        'screen_wake_requested',
      ]);
    },
  );

  testWidgets('Android wake request crosses the native notification channel', (
    tester,
  ) async {
    const channel = MethodChannel('ai.awiki.awikime/remote_push_events');
    final receivedMethods = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      receivedMethods.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    final wake = PlatformNotificationScreenWake(
      channel: channel,
      isAndroid: () => true,
    );

    await wake.wakeIfNeeded();

    expect(receivedMethods, <String>['wakeNotificationScreen']);
  });
}

class _RecordingNotificationScreenWake implements NotificationScreenWake {
  _RecordingNotificationScreenWake(this.events);

  final List<String> events;

  @override
  Future<void> wakeIfNeeded() async {
    events.add('screen_wake_requested');
  }
}
