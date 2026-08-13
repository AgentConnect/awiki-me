import 'dart:io';

import 'package:awiki_me/src/data/services/platform_alive_background_urgent_notification.dart';
import 'package:awiki_me/src/domain/services/notification_channels.dart';
import 'package:awiki_me/src/domain/services/notification_facade.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'decodes exact native lifecycle permission channel and FSI state',
    () async {
      const channel = MethodChannel('test/alive-background-state');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getState');
            return <String, Object>{
              'platform_supported': true,
              'native_activity_resumed': false,
              'flutter_channel_attached': true,
              'notifications_allowed': true,
              'channel_state': 'high',
              'full_screen_access': 'denied',
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final platform = PlatformAliveBackgroundUrgentNotification(
        channel: channel,
        isAndroid: () => true,
      );

      final state = await platform.currentState();

      expect(state.isExactAliveBackground, isTrue);
      expect(state.fullScreenAccess, AliveBackgroundFullScreenAccess.denied);
    },
  );

  test(
    'submit carries committed UI and opaque reference with caller stable ID',
    () async {
      const channel = MethodChannel('test/alive-background-submit');
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return 'fallbackSubmitted';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final platform = PlatformAliveBackgroundUrgentNotification(
        channel: channel,
        isAndroid: () => true,
      );

      final result = await platform.submit(
        AliveBackgroundUrgentNotification(
          nativeId: 7301,
          agentLabel: 'Build Agent',
          taskName: 'Release validation',
          summary: 'Action is required',
          opaqueMessageReference: 'message_AAAAAAAAAAAAAAAAAAAAAAAA',
          expiresAtEpochSeconds: 1800000000,
        ),
      );

      expect(result, AliveBackgroundNotificationSubmission.fallbackSubmitted);
      expect(captured!.method, 'submit');
      expect((captured!.arguments as Map)['native_id'], 7301);
      expect((captured!.arguments as Map)['task_name'], 'Release validation');
      expect(
        (captured!.arguments as Map)['opaque_message_reference'],
        'message_AAAAAAAAAAAAAAAAAAAAAAAA',
      );
      expect((captured!.arguments as Map), isNot(contains('target')));
    },
  );

  test('malformed native state fails closed', () async {
    const channel = MethodChannel('test/alive-background-invalid');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => <String, Object>{});
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final platform = PlatformAliveBackgroundUrgentNotification(
      channel: channel,
      isAndroid: () => true,
    );

    final state = await platform.currentState();

    expect(state.platformSupported, isFalse);
    expect(state.isExactAliveBackground, isFalse);
  });

  test(
    'full-screen settings opens only through the typed user action',
    () async {
      const channel = MethodChannel('test/alive-background-settings');
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            captured = call;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final platform = PlatformAliveBackgroundUrgentNotification(
        channel: channel,
        isAndroid: () => true,
      );

      expect(await platform.openFullScreenSettings(), isTrue);
      expect(captured?.method, 'openFullScreenSettings');
    },
  );

  test('Dart and native activate the same immutable urgent channel ID', () {
    const dartId = awikiStructuredUrgentNotificationChannelId;
    final nativeSource = File(
      'android/app/src/main/kotlin/ai/awiki/awikime/'
      'AliveBackgroundUrgentNotificationController.kt',
    ).readAsStringSync();
    expect(dartId, 'awiki_me_urgent_v2');
    expect(nativeSource, contains('URGENT_CHANNEL_ID = "$dartId"'));
    expect(nativeSource, isNot(contains('awiki_me_alive_urgent_v1')));
    expect(nativeSource, contains('RingtoneManager.TYPE_RINGTONE'));
    expect(nativeSource, contains('USAGE_NOTIFICATION_RINGTONE'));
    expect(nativeSource, contains('StructuredUrgentCueController'));
    expect(nativeSource, isNot(contains('DEFAULT_NOTIFICATION_URI')));
    expect(
      nativeSource,
      contains('Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT'),
    );
    expect(
      nativeSource,
      contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE'),
    );
  });
}
