import 'dart:async';
import 'dart:io';

import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    'SecureAppKeyValueStore pins the Android preference namespace on plugin fallback',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const keychainChannel = MethodChannel('ai.awiki.awikime/keychain_access');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keychainChannel, null);
      final secureStorage = _CapturingSecureStorage();
      final store = SecureAppKeyValueStore(secureStorage: secureStorage);

      await store.write(key: 'active-session', value: 'identity-1');
      await store.read(key: 'active-session');
      await store.delete(key: 'active-session');

      final options = secureStorage.writeAndroidOptions;
      expect(options, isNotNull);
      expect(options, containsPair('encryptedSharedPreferences', 'false'));
      expect(options, containsPair('resetOnError', 'false'));
      expect(options, isNot(contains('migrateOnAlgorithmChange')));
      expect(options, isNot(contains('migrateWithBackup')));
      expect(
        options,
        containsPair('keyCipherAlgorithm', 'RSA_ECB_PKCS1Padding'),
      );
      expect(
        options,
        containsPair('storageCipherAlgorithm', 'AES_CBC_PKCS7Padding'),
      );
      expect(
        options,
        containsPair('sharedPreferencesName', 'FlutterSecureStorage'),
      );
      expect(
        options,
        containsPair(
          'preferencesKeyPrefix',
          'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg',
        ),
      );
      expect(secureStorage.readAndroidOptions, options);
      expect(secureStorage.deleteAndroidOptions, options);
    },
  );

  test(
    'SecureAppKeyValueStore writes macOS values through native Keychain service',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const keychainChannel = MethodChannel('ai.awiki.awikime/keychain_access');
      final legacyCalls = <MethodCall>[];
      final keychainCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (call) async {
            legacyCalls.add(call);
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keychainChannel, (call) async {
            keychainCalls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storageChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(keychainChannel, null);
      });

      await SecureAppKeyValueStore().write(
        key: 'native-write-key',
        value: 'ok',
      );

      expect(legacyCalls, isEmpty);
      expect(keychainCalls, hasLength(1));
      expect(keychainCalls.single.method, 'writeGenericPassword');
      expect(keychainCalls.single.arguments, <String, Object?>{
        'service': 'ai.awiki.awikime.secure_storage',
        'account': 'native-write-key',
        'value': 'ok',
      });
    },
  );

  test(
    'SecureAppKeyValueStore falls back to regular macOS Keychain bridge when native bridge is unavailable',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const keychainChannel = MethodChannel('ai.awiki.awikime/keychain_access');
      final legacyCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (call) async {
            legacyCalls.add(call);
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keychainChannel, null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storageChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(keychainChannel, null);
      });

      await SecureAppKeyValueStore().write(
        key: 'legacy-write-key',
        value: 'ok',
      );

      expect(legacyCalls, hasLength(1));
      final arguments = legacyCalls.single.arguments as Map<Object?, Object?>;
      final options = arguments['options'] as Map<Object?, Object?>;
      expect(options['useDataProtectionKeyChain'], 'false');
    },
  );

  test(
    'SecureAppKeyValueStore reads native macOS Keychain values first without ACL repair',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const keychainChannel = MethodChannel('ai.awiki.awikime/keychain_access');
      final legacyCalls = <MethodCall>[];
      final keychainCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (call) async {
            legacyCalls.add(call);
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keychainChannel, (call) async {
            keychainCalls.add(call);
            if (call.method == 'readGenericPassword') {
              return 'native-secret';
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storageChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(keychainChannel, null);
      });

      final value = await SecureAppKeyValueStore().read(key: 'native-read-key');
      await Future<void>.delayed(Duration.zero);

      expect(value, 'native-secret');
      expect(legacyCalls, isEmpty);
      expect(keychainCalls.map((call) => call.method), <String>[
        'readGenericPassword',
      ]);
      expect(keychainCalls.first.arguments, <String, Object?>{
        'service': 'ai.awiki.awikime.secure_storage',
        'account': 'native-read-key',
      });
    },
  );

  test(
    'SecureAppKeyValueStore does not repair legacy macOS ACL when native migration fails',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const keychainChannel = MethodChannel('ai.awiki.awikime/keychain_access');
      final legacyCalls = <MethodCall>[];
      final keychainCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (call) async {
            legacyCalls.add(call);
            if (call.method == 'read') {
              return 'legacy-secret';
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keychainChannel, (call) async {
            keychainCalls.add(call);
            if (call.method == 'writeGenericPassword') {
              throw PlatformException(code: 'write_failed');
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storageChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(keychainChannel, null);
      });

      expect(
        await SecureAppKeyValueStore().read(key: 'legacy-repair-key'),
        'legacy-secret',
      );
      expect(legacyCalls.map((call) => call.method), contains('read'));
      expect(legacyCalls.map((call) => call.method), isNot(contains('delete')));
      expect(keychainCalls.map((call) => call.method), <String>[
        'readGenericPassword',
        'writeGenericPassword',
      ]);
    },
  );

  test(
    'SecureAppKeyValueStore migrates legacy macOS reads to native Keychain and deletes legacy item',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      const keychainChannel = MethodChannel('ai.awiki.awikime/keychain_access');
      final legacyCalls = <MethodCall>[];
      final keychainCalls = <MethodCall>[];
      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (call) async {
            legacyCalls.add(call);
            if (call.method == 'read') {
              return 'legacy-secret';
            }
            if (call.method == 'delete') {
              deleteStarted.complete();
              await releaseDelete.future;
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(keychainChannel, (call) async {
            keychainCalls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storageChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(keychainChannel, null);
      });

      var readCompleted = false;
      final readFuture = SecureAppKeyValueStore()
          .read(key: 'legacy-read-key')
          .then((value) {
            readCompleted = true;
            return value;
          });
      await deleteStarted.future.timeout(const Duration(seconds: 1));
      expect(readCompleted, isFalse);

      releaseDelete.complete();
      final value = await readFuture;

      expect(value, 'legacy-secret');
      expect(readCompleted, isTrue);
      expect(legacyCalls.map((call) => call.method), contains('read'));
      expect(keychainCalls.map((call) => call.method), <String>[
        'readGenericPassword',
        'writeGenericPassword',
      ]);
      expect(keychainCalls[1].arguments, <String, Object?>{
        'service': 'ai.awiki.awikime.secure_storage',
        'account': 'legacy-read-key',
        'value': 'legacy-secret',
      });
      expect(legacyCalls.map((call) => call.method), contains('delete'));
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

class _CapturingSecureStorage extends FlutterSecureStorage {
  Map<String, String>? writeAndroidOptions;
  Map<String, String>? readAndroidOptions;
  Map<String, String>? deleteAndroidOptions;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writeAndroidOptions = aOptions?.toMap();
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    readAndroidOptions = aOptions?.toMap();
    return null;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteAndroidOptions = aOptions?.toMap();
  }
}
