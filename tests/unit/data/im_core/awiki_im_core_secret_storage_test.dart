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
      expect(store.writeCount, 2);
      expect(
        store.writeKeys,
        containsAll(<String>[
          'awiki_me.im_core.identity_vault.tenant-alpha.secrets_v1',
          'awiki_me.im_core.identity_vault.tenant-beta.secrets_v1',
        ]),
      );
      expect(_touchedLegacySplitKey(store), isFalse);
    },
  );

  test('stored vault provider reads an existing secret bundle once', () async {
    final rootKey = List<int>.generate(
      awikiImCoreVaultRootKeyLength,
      (index) => index,
    );
    final store = _MemoryStore()
      ..values['awiki_me.im_core.identity_vault.default.secrets_v1'] =
          jsonEncode(<String, Object?>{
            'schema': 1,
            'root_key_b64': base64Encode(rootKey),
            'device_id': 'app-device-existing',
          });
    final provider = StoredAwikiImCoreVaultSecretProvider(storage: store);

    final secrets = await provider.getOrCreateSecrets(
      stateNamespace: 'default',
    );

    expect(secrets.rootKey.bytes, rootKey);
    expect(secrets.deviceId, 'app-device-existing');
    expect(store.readCount, 1);
    expect(store.writeCount, 0);
    expect(store.readKeys, <String>[
      'awiki_me.im_core.identity_vault.default.secrets_v1',
    ]);
  });

  test(
    'stored vault provider does not read split legacy Keychain items',
    () async {
      final store = _MemoryStore()
        ..values['awiki_me.im_core.identity_vault.default.root_key_b64'] =
            base64Encode(List<int>.filled(awikiImCoreVaultRootKeyLength, 1))
        ..values['awiki_me.im_core.identity_vault.default.device_id'] =
            'app-device-legacy';
      final provider = StoredAwikiImCoreVaultSecretProvider(
        storage: store,
        randomBytes: (length) => List<int>.filled(length, 7),
      );

      final secrets = await provider.getOrCreateSecrets(
        stateNamespace: 'default',
      );

      expect(secrets.rootKey.bytes, List<int>.filled(32, 7));
      expect(secrets.deviceId, isNot('app-device-legacy'));
      expect(store.readKeys, <String>[
        'awiki_me.im_core.identity_vault.default.secrets_v1',
      ]);
      expect(store.writeKeys, <String>[
        'awiki_me.im_core.identity_vault.default.secrets_v1',
      ]);
      expect(_touchedLegacySplitKey(store), isFalse);
    },
  );

  test(
    'stored vault provider rejects corrupted secret bundle without echoing value',
    () async {
      const secret = 'short-secret-material';
      final store = _MemoryStore()
        ..values['awiki_me.im_core.identity_vault.default.secrets_v1'] =
            jsonEncode(<String, Object?>{
              'schema': 1,
              'root_key_b64': base64Encode(utf8.encode(secret)),
              'device_id': 'app-device-existing',
            });
      final provider = StoredAwikiImCoreVaultSecretProvider(storage: store);

      await expectLater(
        provider.getOrCreateSecrets(stateNamespace: 'default'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains('identity_vault_secret_bundle_invalid'),
              isNot(contains(secret)),
            ),
          ),
        ),
      );
    },
  );

  test(
    'strict file secret store does not recreate a missing bundle in an existing file',
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
            contains('identity_vault_secret_bundle_unavailable'),
          ),
        ),
      );
    },
  );

  test(
    'stored vault provider coalesces concurrent secret bundle creation',
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
      expect(store.readCount, 1);
      expect(store.writeCount, 1);
      expect(store.writeKeys, <String>[
        'awiki_me.im_core.identity_vault.default.secrets_v1',
      ]);
    },
  );
}

class _MemoryStore implements AppKeyValueStore {
  _MemoryStore({this.readDelay});

  final Duration? readDelay;
  final Map<String, String> values = <String, String>{};
  final List<String> readKeys = <String>[];
  final List<String> writeKeys = <String>[];
  final List<String> deleteKeys = <String>[];
  int readCount = 0;
  int writeCount = 0;

  @override
  Future<void> delete({required String key}) async {
    deleteKeys.add(key);
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    readCount += 1;
    readKeys.add(key);
    final delay = readDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writeCount += 1;
    writeKeys.add(key);
    values[key] = value;
  }
}

bool _touchedLegacySplitKey(_MemoryStore store) {
  return <String>[
    ...store.readKeys,
    ...store.writeKeys,
    ...store.deleteKeys,
  ].any((key) => key.endsWith('.root_key_b64') || key.endsWith('.device_id'));
}
