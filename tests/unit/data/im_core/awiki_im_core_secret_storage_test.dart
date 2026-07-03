import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stored vault provider generates stable namespace scoped secrets',
    () async {
      var seed = 0;
      final store = _MemoryStore();
      final provider = StoredAwikiImCoreVaultSecretProvider(
        storage: store,
        randomBytes: (length) {
          final base = seed++;
          return List<int>.generate(length, (index) => (base + index) % 256);
        },
      );

      final first = await provider.getOrCreateSecrets(
        stateNamespace: 'Tenant Alpha',
      );
      final second = await provider.getOrCreateSecrets(
        stateNamespace: 'Tenant Alpha',
      );
      final other = await provider.getOrCreateSecrets(
        stateNamespace: 'Tenant Beta',
      );

      expect(first.rootKey.bytes, hasLength(awikiImCoreVaultRootKeyLength));
      expect(second.rootKey.bytes, first.rootKey.bytes);
      expect(second.deviceId, first.deviceId);
      expect(other.rootKey.bytes, isNot(first.rootKey.bytes));
      expect(other.deviceId, isNot(first.deviceId));
    },
  );

  test(
    'stored vault provider rejects corrupted root key without echoing value',
    () async {
      const secret = 'short-secret-material';
      final store = _MemoryStore();
      await store.write(
        key: 'awiki_me.im_core.identity_vault.default.root_key_b64',
        value: base64Encode(utf8.encode(secret)),
      );
      final provider = StoredAwikiImCoreVaultSecretProvider(storage: store);

      await expectLater(
        provider.getOrCreateSecrets(stateNamespace: 'default'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains('identity_vault_root_key_invalid'),
              isNot(contains(secret)),
            ),
          ),
        ),
      );
    },
  );

  test(
    'strict file secret store does not recreate a missing root key in an existing file',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-vault-store-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}/vault.json');
      await file.writeAsString(jsonEncode(<String, String>{}));
      final provider = StoredAwikiImCoreVaultSecretProvider(
        storage: FileAppKeyValueStore.forFile(file, strictRead: true),
      );

      await expectLater(
        provider.getOrCreateSecrets(stateNamespace: 'default'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('identity_vault_root_key_unavailable'),
          ),
        ),
      );
    },
  );

  test(
    'stored vault provider coalesces concurrent root key creation',
    () async {
      var seed = 0;
      final store = _MemoryStore(readDelay: const Duration(milliseconds: 10));
      final provider = StoredAwikiImCoreVaultSecretProvider(
        storage: store,
        randomBytes: (length) {
          final base = seed++;
          return List<int>.generate(length, (index) => (base + index) % 256);
        },
      );

      final results = await Future.wait(<Future<AwikiImCoreVaultSecrets>>[
        provider.getOrCreateSecrets(stateNamespace: 'default'),
        provider.getOrCreateSecrets(stateNamespace: 'default'),
      ]);

      expect(results.first.rootKey.bytes, results.last.rootKey.bytes);
      expect(results.first.deviceId, results.last.deviceId);
      expect(store.writeCount, 2);
    },
  );
}

class _MemoryStore implements AppKeyValueStore {
  _MemoryStore({this.readDelay});

  final Duration? readDelay;
  final Map<String, String> values = <String, String>{};
  int writeCount = 0;

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    final delay = readDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writeCount += 1;
    values[key] = value;
  }
}
