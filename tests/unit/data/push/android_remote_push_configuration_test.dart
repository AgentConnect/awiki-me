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

    test('keeps the EMAS reflection and SPI surface in release builds', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final rules = File('android/app/proguard-rules.pro').readAsStringSync();
      final emasRules = File(
        'android/app/proguard-emas.pro',
      ).readAsStringSync();

      expect(
        gradle,
        contains('proguardFiles "proguard-rules.pro", "proguard-emas.pro"'),
      );
      expect(rules, contains('-dontwarn org.android.netutil.PingEntry'));
      expect(rules, contains('-dontwarn org.android.netutil.PingResponse'));
      expect(rules, contains('-dontwarn org.android.netutil.PingTask'));
      expect(rules, isNot(contains('-dontwarn org.android.netutil.**')));
      expect(rules, isNot(contains('-dontwarn anet.channel.**')));
      for (final namespace in <String>[
        'com.alibaba.**',
        'com.aliyun.**',
        'com.taobao.**',
        'anet.channel.**',
        'anetwork.channel.**',
        'org.android.agoo.**',
        'org.android.spdy.**',
        'mtopsdk.**',
      ]) {
        expect(emasRules, contains('-keep class $namespace { *; }'));
      }
      expect(emasRules, contains('RuntimeVisibleAnnotations'));
      expect(
        emasRules,
        contains('-dontwarn com.alibaba.mtl.appmonitor.AppMonitor'),
      );
      expect(
        emasRules,
        isNot(contains('-dontwarn com.alibaba.mtl.appmonitor.**')),
      );
      expect(emasRules, isNot(contains('-dontwarn anet.channel.**')));
    });

    test('disables Android backup for encrypted local state', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final scopeStore = File(
        'lib/src/data/storage/platform_scope_secret_repository.dart',
      ).readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(
        pubspec,
        contains(
          RegExp(r'^  flutter_secure_storage: 9\.2\.4$', multiLine: true),
        ),
      );
      expect(scopeStore, isNot(contains('migrateWithBackup')));
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

    test(
      'intercepts valid foreground ordinary notices for every local account',
      () {
        final receiver = File(
          'android/app/src/main/kotlin/ai/awiki/awikime/push/'
          'AwikiAliyunPushReceiver.kt',
        ).readAsStringSync();
        final bridge = File(
          'android/app/src/main/kotlin/ai/awiki/awikime/push/RemotePushEventBridge.kt',
        ).readAsStringSync();
        final activity = File(
          'android/app/src/main/kotlin/ai/awiki/awikime/MainActivity.kt',
        ).readAsStringSync();
        final presentationState = File(
          'android/app/src/main/kotlin/ai/awiki/awikime/push/'
          'RemotePushPresentationState.kt',
        ).readAsStringSync();

        expect(receiver, contains('override fun showNotificationNow'));
        expect(receiver, contains('shouldShowNotification(extraMap)'));
        expect(bridge, contains('setActiveNotificationTargetReference'));
        expect(activity, contains('setActivityResumed(true)'));
        expect(activity, contains('setActivityResumed(false)'));
        expect(
          presentationState,
          isNot(contains('if (!activityResumed || !windowFocused)')),
        );
        expect(
          presentationState,
          isNot(contains('activeTargetReference ?: return true')),
        );
        expect(
          presentationState,
          contains('targetReferencePattern.matches(targetReference)'),
        );
        expect(presentationState, contains('data["ext"]'));
        expect(presentationState, contains('JSONObject(rawEnvelope)'));
        expect(presentationState, contains('direct_message'));
        expect(presentationState, contains('group_message'));
      },
    );

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
