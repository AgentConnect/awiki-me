import 'dart:io';

import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'macOS secure storage can write, read, and delete a temporary value',
    (tester) async {
      final store = SecureAppKeyValueStore();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final key = 'awiki_me.e2e.secure_storage_smoke.$suffix';
      addTearDown(() async {
        try {
          await store.delete(key: key);
        } on Object {
          // Best-effort cleanup: preserve the primary failure signal.
        }
      });

      await store.write(key: key, value: 'ok');
      expect(await store.read(key: key), 'ok');

      await store.delete(key: key);
      expect(await store.read(key: key), isNull);
    },
    skip: !Platform.isMacOS,
  );
}
