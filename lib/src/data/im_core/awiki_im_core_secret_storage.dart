import 'dart:convert';
import 'dart:math';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../services/app_key_value_store.dart';
import 'awiki_im_core_paths.dart';

const int awikiImCoreVaultRootKeyLength = 32;
const int _vaultSecretBundleSchema = 1;

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
    final key = _bundleKey(namespace);
    final existing = await _storage.read(key: key);
    if (existing != null) {
      return _secretsFromBundle(_decodeBundle(existing));
    }
    if (await _strictStoreAlreadyExists()) {
      throw StateError('identity_vault_secret_bundle_unavailable');
    }
    final rootKeyBytes = _generateRootKeyBytes();
    final deviceId = _generateDeviceId();
    final bundle = _StoredVaultSecretBundle(
      schema: _vaultSecretBundleSchema,
      rootKeyB64: base64Encode(rootKeyBytes),
      deviceId: deviceId,
    );
    await _storage.write(key: key, value: jsonEncode(bundle.toJson()));
    return AwikiImCoreVaultSecrets(
      rootKey: core.DeviceVaultRootKey.fromList(rootKeyBytes),
      deviceId: deviceId,
    );
  }

  String _bundleKey(String namespace) {
    return '$_keyPrefix.$namespace.secrets_v1';
  }

  AwikiImCoreVaultSecrets _secretsFromBundle(_StoredVaultSecretBundle bundle) {
    final rootKeyBytes = _decodeRootKey(bundle.rootKeyB64);
    return AwikiImCoreVaultSecrets(
      rootKey: core.DeviceVaultRootKey.fromList(rootKeyBytes),
      deviceId: bundle.deviceId,
    );
  }

  List<int> _generateRootKeyBytes() {
    final generated = _randomBytes(awikiImCoreVaultRootKeyLength);
    if (generated.length != awikiImCoreVaultRootKeyLength) {
      throw StateError(
        'identity_vault_secret_bundle_generation_failed: expected '
        '$awikiImCoreVaultRootKeyLength bytes of root key material.',
      );
    }
    return List<int>.from(generated);
  }

  String _generateDeviceId() {
    final random = _randomBytes(16);
    final encoded = base64UrlEncode(random).replaceAll('=', '');
    return 'app-device-$encoded';
  }

  Future<bool> _strictStoreAlreadyExists() async {
    final storage = _storage;
    if (storage is! FileAppKeyValueStore || !storage.strictRead) {
      return false;
    }
    return storage.storeExists();
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
      'identity_vault_secret_bundle_invalid: stored root key must decode to '
      '$awikiImCoreVaultRootKeyLength bytes.',
    );
  }
}

_StoredVaultSecretBundle _decodeBundle(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('bundle must be an object');
    }
    final schema = decoded['schema'];
    final rootKeyB64 = decoded['root_key_b64'];
    final deviceId = decoded['device_id'];
    if (schema != _vaultSecretBundleSchema ||
        rootKeyB64 is! String ||
        rootKeyB64.trim().isEmpty ||
        deviceId is! String ||
        deviceId.trim().isEmpty) {
      throw const FormatException('invalid bundle fields');
    }
    return _StoredVaultSecretBundle(
      schema: schema,
      rootKeyB64: rootKeyB64,
      deviceId: deviceId.trim(),
    );
  } catch (_) {
    throw StateError('identity_vault_secret_bundle_invalid');
  }
}

class _StoredVaultSecretBundle {
  const _StoredVaultSecretBundle({
    required this.schema,
    required this.rootKeyB64,
    required this.deviceId,
  });

  final int schema;
  final String rootKeyB64;
  final String deviceId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': schema,
      'root_key_b64': rootKeyB64,
      'device_id': deviceId,
    };
  }
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
