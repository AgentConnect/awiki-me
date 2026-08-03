import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android remote push configuration', () {
    test('uses an Android-only EMAS SDK dependency', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final rootGradle = File('android/build.gradle').readAsStringSync();

      expect(pubspec, isNot(contains('aliyun_push:')));
      expect(gradle, contains('com.aliyun.ams:alicloud-android-push:3.10.1'));
      expect(
        rootGradle,
        contains('maven.aliyun.com/nexus/content/repositories/releases/'),
      );
    });

    test('limits R8 suppression to EMAS optional ping helper types', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final rules = File('android/app/proguard-rules.pro').readAsStringSync();

      expect(gradle, contains('proguardFiles "proguard-rules.pro"'));
      expect(rules, contains('-dontwarn org.android.netutil.PingEntry'));
      expect(rules, contains('-dontwarn org.android.netutil.PingResponse'));
      expect(rules, contains('-dontwarn org.android.netutil.PingTask'));
      expect(rules, isNot(contains('-dontwarn org.android.netutil.**')));
      expect(rules, isNot(contains('-dontwarn anet.channel.**')));
    });

    test(
      'initializes EMAS before Flutter and registers the AWiki receiver',
      () {
        final manifest = File(
          'android/app/src/main/AndroidManifest.xml',
        ).readAsStringSync();
        final application = File(
          'android/app/src/main/kotlin/ai/awiki/awikime/AwikiApplication.kt',
        ).readAsStringSync();

        expect(manifest, contains('android:name=".AwikiApplication"'));
        expect(manifest, contains('.push.AwikiAliyunPushReceiver'));
        expect(manifest, contains('com.alibaba.sdk.android.push.RECEIVE'));
        expect(application, contains('PushServiceFactory.init(config)'));
        expect(application, contains('BuildConfig.AWIKI_EMAS_ENABLED'));
      },
    );

    test('wakes a non-interactive device briefly when a notice arrives', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final receiver = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/'
        'AwikiAliyunPushReceiver.kt',
      ).readAsStringSync();
      final wakeController = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/'
        'NotificationScreenWakeController.kt',
      );

      expect(
        manifest,
        contains('android.permission.WAKE_LOCK'),
        reason: 'screen wake requires the platform wake-lock permission',
      );
      expect(wakeController.existsSync(), isTrue);
      if (!wakeController.existsSync()) return;
      final controllerSource = wakeController.readAsStringSync();
      expect(
        receiver,
        contains('NotificationScreenWakeController.wakeIfNeeded'),
      );
      final inAppCallback = RegExp(
        r'onNotificationReceivedInApp\(([\s\S]*?)\n    \}',
      ).firstMatch(receiver)?.group(1);
      expect(inAppCallback, isNotNull);
      expect(
        inAppCallback,
        isNot(contains('NotificationScreenWakeController.wakeIfNeeded')),
        reason: 'an in-app callback does not prove visible notification UI',
      );
      expect(controllerSource, contains('areNotificationsEnabled'));
      expect(controllerSource, contains('getNotificationChannel'));
      expect(controllerSource, contains('powerManager.isInteractive'));
      expect(controllerSource, contains('ACQUIRE_CAUSES_WAKEUP'));
      expect(controllerSource, contains('wakeLock.acquire(WAKE_DURATION_MS)'));
    });

    test('keeps native EMAS registration idempotent after SDK auto-retry', () {
      final bridge = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt',
      ).readAsStringSync();
      final state = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/'
        'RemotePushRegistrationState.kt',
      ).readAsStringSync();
      final coordinator = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/'
        'RemotePushInitializationCoordinator.kt',
      ).readAsStringSync();

      expect(bridge, contains('RemotePushInitializationCoordinator'));
      expect(coordinator, contains('RemotePushRegistrationState'));
      expect(coordinator, contains('pendingCompletions'));
      expect(coordinator, contains('readyDeviceId'));
      expect(coordinator, contains('PUSH_20110'));
      expect(coordinator, contains('completeSuccess'));
      expect(coordinator, contains('completeFailure'));
      expect(state, contains('JOIN_IN_FLIGHT'));
      expect(state, contains('completeFailure'));
      expect(state, isNot(contains('terminalFailure')));
      expect(bridge, isNot(contains('PushServiceFactory.init(')));
      expect(
        RegExp(r'getCloudPushService\(\)\.register\(').allMatches(bridge),
        hasLength(1),
      );
    });

    test('buffers cold-start events and attaches one process-level channel', () {
      final bridge = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt',
      ).readAsStringSync();
      final activity = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/MainActivity.kt',
      ).readAsStringSync();

      expect(bridge, contains('MAX_PENDING_EVENTS = 32'));
      expect(bridge, contains('loadPendingEvents'));
      expect(bridge, contains('acknowledgePendingEvents'));
      expect(bridge, contains('onRemotePushEvents'));
      expect(activity, contains('RemotePushEventBridge.attach'));
      expect(activity, contains('RemotePushEventBridge.detach'));
    });

    test('exposes the enabled EMAS AppKey without exposing its secret', () {
      final bridge = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt',
      ).readAsStringSync();
      final getAppIdHandler = RegExp(
        r'"getAppId"\s*->([\s\S]*?)"getDeviceId"\s*->',
      ).firstMatch(bridge)?.group(1);

      expect(getAppIdHandler, isNotNull);
      expect(getAppIdHandler, contains('BuildConfig.AWIKI_EMAS_APP_KEY'));
      expect(
        getAppIdHandler,
        isNot(contains('BuildConfig.AWIKI_EMAS_APP_SECRET')),
      );
    });

    test('keeps real EMAS credentials out of tracked configuration', () {
      final gitignore = File('.gitignore').readAsStringSync();
      final example = File(
        'android/emas.properties.example',
      ).readAsStringSync();
      final gradle = File('android/app/build.gradle').readAsStringSync();

      expect(gitignore, contains('android/emas.properties'));
      expect(
        example,
        contains('debug.appKey=REPLACE_WITH_ANDROID_DEBUG_EMAS_APP_KEY'),
      );
      expect(
        example,
        contains(
          'release.appSecret=REPLACE_WITH_ANDROID_RELEASE_EMAS_APP_SECRET',
        ),
      );
      expect(
        example,
        contains('appRsaSecret=REPLACE_WITH_EMAS_APP_RSA_SECRET'),
      );
      expect(gradle, isNot(contains('appRsaSecret')));
      expect(gradle, contains('loadEmasVariant("debug")'));
      expect(gradle, contains('loadEmasVariant("release")'));
      expect(gradle, contains('AWIKI_EMAS_LOG_DEVICE_ID'));
    });

    test('persists only allowlisted push metadata with a 24 hour TTL', () {
      final bridge = File(
        'android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt',
      ).readAsStringSync();

      expect(bridge, contains('PERSISTED_ENVELOPE_KEYS'));
      expect(bridge, contains('MAX_PENDING_AGE_MS'));
      expect(bridge, contains('eventForPersistence'));
      expect(bridge, contains('@Synchronized'));
      expect(bridge, contains('.commit()'));
      expect(bridge, isNot(contains('put("title"')));
      expect(bridge, isNot(contains('put("content"')));
      expect(bridge, isNot(contains('put("openUrl"')));
    });
  });
}
