import 'dart:io';

import 'package:awiki_me/src/data/storage/local_data_recovery_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.awiki/local-data-recovery');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android recovery uses the dedicated native method', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    const platform = MethodChannelLocalDataRecoveryPlatform(
      channel: channel,
      isSupported: true,
    );

    await platform.resetSecureStorage();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'resetLocalSecureStorage');
    expect(calls.single.arguments, isNull);
  });

  test('unsupported platforms never invoke the Android channel', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls += 1;
          return null;
        });
    const platform = MethodChannelLocalDataRecoveryPlatform(
      channel: channel,
      isSupported: false,
    );

    await expectLater(
      platform.resetSecureStorage(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(calls, 0);
  });

  test('native recovery failures retain their structured platform code', () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'local_data_recovery_failed');
        });
    const platform = MethodChannelLocalDataRecoveryPlatform(
      channel: channel,
      isSupported: true,
    );

    expectLater(
      platform.resetSecureStorage(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'local_data_recovery_failed',
        ),
      ),
    );
  });

  test('Android native reset is limited to fixed AWiki secure state', () {
    final source = File(
      'android/app/src/main/kotlin/ai/awiki/awikime/MainActivity.kt',
    ).readAsStringSync();

    expect(source, contains('ai.awiki.awikime/android_local_data_recovery'));
    expect(source, contains('"resetLocalSecureStorage"'));
    for (final preferenceName in <String>[
      'awiki_me_app_state_v1',
      'awiki_me_scope_secrets_v1',
      'awiki_me_scope_secrets',
      'FlutterSecureStorage',
      'FlutterSecureKeyStorage',
      'FlutterSecureKeyStorage:awiki_me_app_state_v1',
      'FlutterSecureKeyStorage:awiki_me_scope_secrets_v1',
      'FlutterSecureStorageConfiguration:awiki_me_app_state_v1',
      'FlutterSecureStorageConfiguration:awiki_me_scope_secrets_v1',
      'FlutterSecureStorageConfiguration:awiki_me_scope_secrets',
    ]) {
      expect(source, contains('"$preferenceName"'));
    }
    expect(source, contains('alias.startsWith(appAliasPrefix)'));
    expect(source, contains('alias == "_androidx_security_master_key_"'));
    expect(source, isNot(contains('clearApplicationUserData')));
  });
}
