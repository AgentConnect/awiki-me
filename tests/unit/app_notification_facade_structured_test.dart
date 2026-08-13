import 'package:awiki_me/src/data/services/app_notification_facade.dart';
import 'package:awiki_me/src/data/services/notification_screen_wake.dart';
import 'package:awiki_me/src/domain/services/notification_channels.dart';
import 'package:awiki_me/src/domain/services/notification_facade.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'structured urgent uses caller ID, one alert, and never wakes screen',
    () async {
      final submissions = <_Submission>[];
      final wake = _RecordingWake();
      var cueCalls = 0;
      var cueStopCalls = 0;
      final facade = AppNotificationFacade.forTesting(
        structuredSubmit:
            ({required id, title, body, notificationDetails, payload}) async {
              submissions.add(
                _Submission(id: id, details: notificationDetails!),
              );
            },
        urgentCue: () async => cueCalls += 1,
        urgentCueStop: () async => cueStopCalls += 1,
        structuredEligibility: () async =>
            StructuredNotificationEligibility.allowed,
        screenWake: wake,
      );

      final result = await facade.showStructuredNotification(
        StructuredNotification(
          nativeId: 421337,
          title: 'Trusted Agent',
          body: 'Attention needed',
          level: StructuredNotificationLevel.urgent,
        ),
      );
      expect(result, StructuredNotificationSubmission.submitted);
      expect(submissions.single.id, 421337);
      expect(
        submissions.single.details.android!.channelId,
        awikiStructuredUrgentNotificationChannelId,
      );
      expect(submissions.single.details.android!.onlyAlertOnce, isTrue);
      expect(submissions.single.details.android!.fullScreenIntent, isFalse);
      expect(submissions.single.details.android!.channelBypassDnd, isFalse);
      expect(submissions.single.details.android!.playSound, isTrue);
      expect(submissions.single.details.android!.enableVibration, isTrue);
      expect(wake.calls, 0);
      expect(cueCalls, 0, reason: 'tray submission is not a foreground cue');

      expect(
        await facade.playStructuredUrgentCue(),
        StructuredUrgentCueResult.played,
      );
      expect(cueCalls, 1);
      await facade.stopStructuredUrgentCue();
      expect(cueStopCalls, 1);
      expect(submissions, hasLength(1), reason: 'cue must not create a tray');
      expect(wake.calls, 0);
    },
  );

  test('structured normal channel is silent and permission is typed', () async {
    NotificationDetails? details;
    var eligibility = StructuredNotificationEligibility.denied;
    final facade = AppNotificationFacade.forTesting(
      structuredSubmit:
          ({required id, title, body, notificationDetails, payload}) async =>
              details = notificationDetails,
      urgentCue: () async {},
      structuredEligibility: () async => eligibility,
    );

    expect(
      await facade.structuredNotificationEligibility(),
      StructuredNotificationEligibility.denied,
    );
    eligibility = StructuredNotificationEligibility.allowed;
    await facade.showStructuredNotification(
      StructuredNotification(
        nativeId: 9,
        title: 'Agent',
        body: 'Update',
        level: StructuredNotificationLevel.normal,
      ),
    );
    expect(
      details!.android!.channelId,
      awikiStructuredNormalNotificationChannelId,
    );
    expect(details!.android!.playSound, isFalse);
    expect(details!.android!.enableVibration, isFalse);
    expect(details!.android!.onlyAlertOnce, isTrue);
    expect(details!.iOS!.presentSound, isFalse);
  });

  test('structured submit failure is returned to the policy owner', () async {
    final facade = AppNotificationFacade.forTesting(
      structuredSubmit:
          ({required id, title, body, notificationDetails, payload}) async =>
              throw StateError('native failure'),
      urgentCue: () async {},
      structuredEligibility: () async =>
          StructuredNotificationEligibility.allowed,
    );
    expect(
      await facade.showStructuredNotification(
        StructuredNotification(
          nativeId: 1,
          title: 'Agent',
          body: 'Update',
          level: StructuredNotificationLevel.normal,
        ),
      ),
      StructuredNotificationSubmission.unavailable,
    );
  });

  test(
    'permission denial never submits and is returned to policy owner',
    () async {
      var submissions = 0;
      final facade = AppNotificationFacade.forTesting(
        structuredSubmit:
            ({required id, title, body, notificationDetails, payload}) async =>
                submissions += 1,
        urgentCue: () async {},
        structuredEligibility: () async =>
            StructuredNotificationEligibility.denied,
      );
      expect(
        await facade.showStructuredNotification(
          StructuredNotification(
            nativeId: 2,
            title: 'Agent',
            body: 'Update',
            level: StructuredNotificationLevel.normal,
          ),
        ),
        StructuredNotificationSubmission.permissionDenied,
      );
      expect(submissions, 0);
    },
  );
}

final class _Submission {
  const _Submission({required this.id, required this.details});

  final int id;
  final NotificationDetails details;
}

final class _RecordingWake implements NotificationScreenWake {
  int calls = 0;

  @override
  Future<void> wakeIfNeeded() async {
    calls += 1;
  }
}
