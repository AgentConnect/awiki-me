import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS remote push configuration', () {
    test(
      'uses the official AlicloudPush SDK without a second Flutter plugin',
      () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        final podfile = File('ios/Podfile').readAsStringSync();

        expect(pubspec, isNot(contains('aliyun_push:')));
        expect(podfile, contains("pod 'AlicloudPush', '>= 3.2.4', '< 4.0'"));
        expect(podfile, contains('github.com/aliyun/aliyun-specs.git'));
      },
    );

    test('registers EMAS and APNs callbacks on the shared native channel', () {
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      final sceneDelegate = File(
        'ios/Runner/SceneDelegate.swift',
      ).readAsStringSync();
      final bridge = File(
        'ios/Runner/RemotePushEventBridge.swift',
      ).readAsStringSync();

      expect(delegate, contains('RemotePushEventBridge.shared.prepare'));
      expect(
        delegate,
        contains('didRegisterForRemoteNotificationsWithDeviceToken'),
      );
      expect(delegate, contains('handleForegroundNotification'));
      expect(delegate, contains('handleNotificationOpened'));
      expect(sceneDelegate, contains('connectionOptions.notificationResponse'));
      expect(sceneDelegate, contains('RemotePushEventBridge.shared.prepare'));
      expect(bridge, contains('CloudPushSDK.start(withAppkey:'));
      expect(bridge, contains('CloudPushSDK.registerDevice'));
      expect(bridge, contains('CloudPushSDK.getDeviceId'));
      expect(bridge, contains('onRemotePushEvents'));
      expect(bridge, contains('flushPendingAcknowledgements'));
    });

    test('enables APNs and background remote notifications', () {
      final info = File('ios/Runner/Info.plist').readAsStringSync();
      final entitlements = File(
        'ios/Runner/Runner.entitlements',
      ).readAsStringSync();
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();

      expect(info, contains('<string>remote-notification</string>'));
      expect(entitlements, contains('<key>aps-environment</key>'));
      expect(entitlements, contains(r'$(APS_ENVIRONMENT)'));
      expect(project, contains('RemotePushEventBridge.swift in Sources'));
    });

    test('keeps iOS credentials in ignored per-configuration files', () {
      final gitignore = File('.gitignore').readAsStringSync();
      final example = File(
        'ios/Flutter/Emas.xcconfig.example',
      ).readAsStringSync();
      final debug = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
      final profile = File('ios/Flutter/Profile.xcconfig').readAsStringSync();
      final release = File('ios/Flutter/Release.xcconfig').readAsStringSync();

      expect(gitignore, contains('ios/Flutter/Emas.Debug.xcconfig'));
      expect(gitignore, contains('ios/Flutter/Emas.Profile.xcconfig'));
      expect(gitignore, contains('ios/Flutter/Emas.Release.xcconfig'));
      expect(example, contains('REPLACE_WITH_IOS_EMAS_APP_KEY'));
      expect(example, contains('REPLACE_WITH_IOS_EMAS_APP_SECRET'));
      expect(debug, contains('#include? "Emas.Debug.xcconfig"'));
      expect(profile, contains('#include? "Emas.Profile.xcconfig"'));
      expect(release, contains('#include? "Emas.Release.xcconfig"'));
      expect(release, contains('APS_ENVIRONMENT = production'));
    });

    test('persists only bounded allowlisted cold-start metadata', () {
      final bridge = File(
        'ios/Runner/RemotePushEventBridge.swift',
      ).readAsStringSync();

      expect(bridge, contains('maxPendingEvents = 32'));
      expect(
        bridge,
        contains('maxPendingAgeMilliseconds = 24 * 60 * 60 * 1000'),
      );
      expect(bridge, contains('envelopeKeys: Set<String>'));
      expect(bridge, contains('eventForPersistence'));
      expect(bridge, isNot(contains('payload["title"]')));
      expect(bridge, isNot(contains('payload["body"]')));
      expect(bridge, isNot(contains('payload["openUrl"]')));
    });
  });
}
