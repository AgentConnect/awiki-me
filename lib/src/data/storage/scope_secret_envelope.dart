import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../application/tenant/app_tenant.dart';

const int scopeSecretEnvelopeSchemaVersion = 1;
const int identityVaultRootKeyLength = 32;

typedef SecureByteGenerator = Uint8List Function(int length);

final class ScopeSecretEnvelope {
  ScopeSecretEnvelope._({
    required this.scopeId,
    required this.revision,
    required this.identityVaultRoot,
  });

  factory ScopeSecretEnvelope.create({
    required StorageScopeId scopeId,
    SecureByteGenerator? randomBytes,
    Random? uuidRandom,
  }) {
    final material = (randomBytes ?? _secureRandomBytes)(
      identityVaultRootKeyLength,
    );
    if (material.length != identityVaultRootKeyLength) {
      throw const FormatException('scope_secret_key_length_invalid');
    }
    return ScopeSecretEnvelope._(
      scopeId: scopeId,
      revision: 1,
      identityVaultRoot: IdentityVaultRootSecret._(
        keyId: SecretKeyId.generate(random: uuidRandom),
        keyVersion: 1,
        material: material,
      ),
    );
  }

  factory ScopeSecretEnvelope.decodeForScope({
    required StorageScopeId expectedScopeId,
    required String encoded,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(encoded);
    } on FormatException {
      throw const FormatException('scope_secret_envelope_invalid_json');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('scope_secret_envelope_invalid_shape');
    }
    if (decoded['schema_version'] != scopeSecretEnvelopeSchemaVersion) {
      throw const FormatException('scope_secret_envelope_schema_unsupported');
    }
    if (!_hasExactKeys(decoded, const <String>{
      'schema_version',
      'scope_id',
      'revision',
      'active_secrets',
    })) {
      throw const FormatException('scope_secret_envelope_invalid_shape');
    }
    final scopeValue = decoded['scope_id'];
    final revision = decoded['revision'];
    final activeSecrets = decoded['active_secrets'];
    if (scopeValue is! String ||
        revision is! int ||
        revision < 1 ||
        activeSecrets is! Map<String, Object?> ||
        !_hasExactKeys(activeSecrets, const <String>{'identity_vault_root'})) {
      throw const FormatException('scope_secret_envelope_invalid_shape');
    }
    final scopeId = StorageScopeId.parse(scopeValue);
    if (scopeId != expectedScopeId) {
      throw const FormatException('scope_secret_scope_mismatch');
    }
    final root = activeSecrets['identity_vault_root'];
    if (root is! Map<String, Object?> ||
        !_hasExactKeys(root, const <String>{
          'key_id',
          'key_version',
          'algorithm',
          'material_b64',
        })) {
      throw const FormatException('scope_secret_envelope_invalid_shape');
    }
    final keyIdValue = root['key_id'];
    final keyVersion = root['key_version'];
    final algorithm = root['algorithm'];
    final materialValue = root['material_b64'];
    if (keyIdValue is! String ||
        keyVersion != 1 ||
        algorithm != 'raw-256' ||
        materialValue is! String) {
      throw const FormatException('scope_secret_envelope_invalid_secret');
    }
    // Key IDs use the same canonical UUIDv4 grammar but have no storage role.
    final keyId = SecretKeyId.parse(keyIdValue);
    final Uint8List material;
    try {
      material = base64Decode(materialValue);
    } on FormatException {
      throw const FormatException('scope_secret_material_invalid');
    }
    if (material.length != identityVaultRootKeyLength ||
        base64Encode(material) != materialValue) {
      throw const FormatException('scope_secret_key_length_invalid');
    }
    return ScopeSecretEnvelope._(
      scopeId: scopeId,
      revision: revision,
      identityVaultRoot: IdentityVaultRootSecret._(
        keyId: keyId,
        keyVersion: keyVersion as int,
        material: material,
      ),
    );
  }

  final StorageScopeId scopeId;
  final int revision;
  final IdentityVaultRootSecret identityVaultRoot;

  ScopeSecretEnvelope nextRevision() => ScopeSecretEnvelope._(
    scopeId: scopeId,
    revision: revision + 1,
    identityVaultRoot: identityVaultRoot,
  );

  String encode() => jsonEncode(<String, Object?>{
    'schema_version': scopeSecretEnvelopeSchemaVersion,
    'scope_id': scopeId.value,
    'revision': revision,
    'active_secrets': <String, Object?>{
      'identity_vault_root': <String, Object?>{
        'key_id': identityVaultRoot.keyId.value,
        'key_version': identityVaultRoot.keyVersion,
        'algorithm': 'raw-256',
        'material_b64': base64Encode(identityVaultRoot._material),
      },
    },
  });

  @override
  String toString() =>
      'ScopeSecretEnvelope(scopeId: ${scopeId.value}, revision: $revision, activeSecrets: <redacted>)';
}

final class IdentityVaultRootSecret {
  IdentityVaultRootSecret._({
    required this.keyId,
    required this.keyVersion,
    required Uint8List material,
  }) : _material = Uint8List.fromList(material);

  final SecretKeyId keyId;
  final int keyVersion;
  final Uint8List _material;

  /// Returns a short-lived defensive copy for the im-core open boundary.
  Uint8List copyMaterial() => Uint8List.fromList(_material);

  @override
  String toString() =>
      'IdentityVaultRootSecret(keyId: $keyId, keyVersion: $keyVersion, material: <redacted>)';
}

final class SecretKeyId {
  SecretKeyId._(this.value);

  factory SecretKeyId.parse(String value) {
    if (!_isCanonicalUuidV4(value)) {
      throw const FormatException('scope_secret_key_id_invalid');
    }
    return SecretKeyId._(value);
  }

  factory SecretKeyId.generate({Random? random}) {
    final source = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => source.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return SecretKeyId.parse(
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}',
    );
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      other is SecretKeyId && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => value;
}

bool _hasExactKeys(Map<String, Object?> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

Uint8List _secureRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(length, (_) => random.nextInt(256), growable: false),
  );
}

bool _isCanonicalUuidV4(String value) {
  if (value.length != 36 ||
      value[8] != '-' ||
      value[13] != '-' ||
      value[18] != '-' ||
      value[23] != '-' ||
      value[14] != '4' ||
      !const <String>{'8', '9', 'a', 'b'}.contains(value[19])) {
    return false;
  }
  for (var index = 0; index < value.length; index++) {
    if (const <int>{8, 13, 18, 23}.contains(index)) continue;
    final unit = value.codeUnitAt(index);
    final isDigit = unit >= 48 && unit <= 57;
    final isLowerHex = unit >= 97 && unit <= 102;
    if (!isDigit && !isLowerHex) return false;
  }
  return true;
}
