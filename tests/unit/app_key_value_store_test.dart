import 'dart:io';

import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter/services.dart';
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

  test('FileAppKeyValueStore strict mode rejects invalid json', () async {
    final tempDir = await Directory.systemTemp.createTemp('awiki-store-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final file = File('${tempDir.path}/store.json');
    await file.writeAsString('{not-json');
    final store = FileAppKeyValueStore.forFile(file, strictRead: true);

    await expectLater(
      store.read(key: 'session_token'),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('key_value_store_file_invalid_json'),
        ),
      ),
    );
  });

  test(
    'FileAppKeyValueStore private mode writes private file permissions',
    () async {
      if (!(Platform.isLinux || Platform.isMacOS)) {
        return;
      }
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-store-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final file = File('${tempDir.path}/secret/store.json');
      final store = FileAppKeyValueStore.forFile(file, privateFile: true);
      await store.write(key: 'root_key_b64', value: 'redacted-test-value');

      final dirMode = await _mode('${tempDir.path}/secret');
      final fileMode = await _mode(file.path);
      expect(dirMode, '700');
      expect(fileMode, '600');
    },
  );

  test(
    'SecureAppKeyValueStore uses regular macOS Keychain for ad-hoc builds',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      await SecureAppKeyValueStore().write(key: 'probe', value: 'ok');

      expect(calls, hasLength(1));
      final arguments = calls.single.arguments as Map<Object?, Object?>;
      final options = arguments['options'] as Map<Object?, Object?>;
      expect(options['useDataProtectionKeyChain'], 'false');
    },
  );
}

Future<String> _mode(String path) async {
  final args = Platform.isMacOS
      ? <String>['-f', '%Lp', path]
      : <String>['-c', '%a', path];
  final result = await Process.run('stat', args);
  if (result.exitCode != 0) {
    throw StateError('stat failed: ${result.stderr}');
  }
  return result.stdout.toString().trim();
}
