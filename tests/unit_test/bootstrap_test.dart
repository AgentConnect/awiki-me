// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS debug/profile account store avoids unsigned Keychain writes',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-bootstrap-test-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = await AppBootstrap.buildAccountStoreForTesting();
      expect(store, isA<FileAppKeyValueStore>());

      await store.write(key: 'credential', value: 'ok');
      final restored = FileAppKeyValueStore.forFile(
        File('${tempDir.path}/awiki_me_credentials.json'),
      );
      expect(await restored.read(key: 'credential'), 'ok');
    },
  );
}
