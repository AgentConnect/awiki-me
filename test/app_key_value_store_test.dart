import 'dart:io';

import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FileAppKeyValueStore 会持久化读写结果', () async {
    final tempDir = await Directory.systemTemp.createTemp('awiki-store-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final file = File('${tempDir.path}/store.json');
    final firstStore = FileAppKeyValueStore.forFile(file);
    await firstStore.write(key: 'session_token', value: 'token-1');

    final secondStore = FileAppKeyValueStore.forFile(file);
    expect(await secondStore.read(key: 'session_token'), 'token-1');

    await secondStore.delete(key: 'session_token');

    final thirdStore = FileAppKeyValueStore.forFile(file);
    expect(await thirdStore.read(key: 'session_token'), isNull);
  });
}
