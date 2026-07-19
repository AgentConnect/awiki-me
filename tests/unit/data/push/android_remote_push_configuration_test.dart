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
      expect(bridge, contains('AtomicBoolean'));
      expect(bridge, contains('compareAndSet(false, true)'));
      expect(bridge, isNot(contains('put("title"')));
      expect(bridge, isNot(contains('put("content"')));
      expect(bridge, isNot(contains('put("openUrl"')));
    });
  });
}
