import 'dart:convert';
import 'dart:math';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../services/app_key_value_store.dart';
import 'awiki_im_core_paths.dart';

const int awikiImCoreVaultRootKeyLength = 32;

class AwikiImCoreVaultSecrets {
  const AwikiImCoreVaultSecrets({
    required this.rootKey,
    required this.deviceId,
  });

  final core.DeviceVaultRootKey rootKey;
  final String deviceId;
}

abstract interface class AwikiImCoreVaultSecretProvider {
  Future<AwikiImCoreVaultSecrets> getOrCreateSecrets({
    required String stateNamespace,
  });
}

class StoredAwikiImCoreVaultSecretProvider
    implements AwikiImCoreVaultSecretProvider {
  StoredAwikiImCoreVaultSecretProvider({
    required AppKeyValueStore storage,
    List<int> Function(int length)? randomBytes,
    String keyPrefix = 'awiki_me.im_core.identity_vault',
  }) : _storage = storage,
       _randomBytes = randomBytes ?? _secureRandomBytes,
       _keyPrefix = keyPrefix;

  final AppKeyValueStore _storage;
  final List<int> Function(int length) _randomBytes;
  final String _keyPrefix;
  final Map<String, Future<AwikiImCoreVaultSecrets>> _inFlight =
      <String, Future<AwikiImCoreVaultSecrets>>{};

  @override
  Future<AwikiImCoreVaultSecrets> getOrCreateSecrets({
    required String stateNamespace,
  }) {
    final namespace = normalizeAwikiStateNamespace(stateNamespace);
    final existing = _inFlight[namespace];
    if (existing != null) {
      return existing;
    }
    final created = _getOrCreateSecrets(namespace);
    _inFlight[namespace] = created;
    return created.whenComplete(() {
      if (identical(_inFlight[namespace], created)) {
        _inFlight.remove(namespace);
      }
    });
  }

  Future<AwikiImCoreVaultSecrets> _getOrCreateSecrets(String namespace) async {
    final rootKeyBytes = await _getOrCreateRootKey(namespace);
    final deviceId = await _getOrCreateDeviceId(namespace);
    return AwikiImCoreVaultSecrets(
      rootKey: core.DeviceVaultRootKey.fromList(rootKeyBytes),
      deviceId: deviceId,
    );
  }

  Future<List<int>> _getOrCreateRootKey(String namespace) async {
    final key = '$_keyPrefix.$namespace.root_key_b64';
    final existing = await _storage.read(key: key);
    if (existing != null && existing.trim().isNotEmpty) {
      return _decodeRootKey(existing);
    }
    if (await _strictStoreAlreadyExists()) {
      throw StateError('identity_vault_root_key_unavailable');
    }
    final generated = _randomBytes(awikiImCoreVaultRootKeyLength);
    if (generated.length != awikiImCoreVaultRootKeyLength) {
      throw StateError(
        'identity_vault_root_key_generation_failed: expected '
        '$awikiImCoreVaultRootKeyLength bytes.',
      );
    }
    await _storage.write(key: key, value: base64Encode(generated));
    return List<int>.from(generated);
  }

  Future<bool> _strictStoreAlreadyExists() async {
    final storage = _storage;
    if (storage is! FileAppKeyValueStore || !storage.strictRead) {
      return false;
    }
    return storage.storeExists();
  }

  Future<String> _getOrCreateDeviceId(String namespace) async {
    final key = '$_keyPrefix.$namespace.device_id';
    final existing = await _storage.read(key: key);
    final trimmed = existing?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    final random = _randomBytes(16);
    final encoded = base64UrlEncode(random).replaceAll('=', '');
    final deviceId = 'app-device-$encoded';
    await _storage.write(key: key, value: deviceId);
    return deviceId;
  }
}

List<int> _decodeRootKey(String encoded) {
  try {
    final decoded = base64Decode(encoded.trim());
    if (decoded.length != awikiImCoreVaultRootKeyLength) {
      throw const FormatException('wrong root key length');
    }
    return decoded;
  } catch (_) {
    throw StateError(
      'identity_vault_root_key_invalid: stored root key must decode to '
      '$awikiImCoreVaultRootKeyLength bytes.',
    );
  }
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
