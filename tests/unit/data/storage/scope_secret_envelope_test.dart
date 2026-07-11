import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('envelope round trips strict scope-bound 32-byte root', () {
    final scope = StorageScopeId.generate();
    final envelope = ScopeSecretEnvelope.create(
      scopeId: scope,
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );

    final decoded = ScopeSecretEnvelope.decodeForScope(
      expectedScopeId: scope,
      encoded: envelope.encode(),
    );

    expect(decoded.revision, 1);
    expect(
      decoded.identityVaultRoot.copyMaterial(),
      List<int>.generate(32, (i) => i),
    );
    expect(decoded.toString(), contains('<redacted>'));
    expect(
      decoded.toString(),
      isNot(contains(base64Encode(List<int>.generate(32, (i) => i)))),
    );
    expect(decoded.identityVaultRoot.toString(), contains('<redacted>'));
  });

  test('unknown schema is distinguished before future shape validation', () {
    final scope = StorageScopeId.generate();
    final json = _validJson(scope)
      ..['schema_version'] = 2
      ..['future'] = true;
    expect(
      () => ScopeSecretEnvelope.decodeForScope(
        expectedScopeId: scope,
        encoded: jsonEncode(json),
      ),
      throwsA(_formatCode('scope_secret_envelope_schema_unsupported')),
    );
  });

  test('decode rejects mismatch, shape, key id, algorithm and key length', () {
    final scope = StorageScopeId.generate();
    final cases = <String, Map<String, Object?>>{};

    cases['scope_secret_scope_mismatch'] = _validJson(scope)
      ..['scope_id'] = StorageScopeId.generate().value;
    cases['scope_secret_envelope_invalid_shape'] = _validJson(scope)
      ..['unexpected'] = true;
    final badKeyId = _validJson(scope);
    _root(badKeyId)['key_id'] = 'not-a-key-id';
    cases['scope_secret_key_id_invalid'] = badKeyId;
    final badAlgorithm = _validJson(scope);
    _root(badAlgorithm)['algorithm'] = 'raw-128';
    cases['scope_secret_envelope_invalid_secret'] = badAlgorithm;
    final shortKey = _validJson(scope);
    _root(shortKey)['material_b64'] = base64Encode(List<int>.filled(31, 7));
    cases['scope_secret_key_length_invalid'] = shortKey;

    for (final entry in cases.entries) {
      expect(
        () => ScopeSecretEnvelope.decodeForScope(
          expectedScopeId: scope,
          encoded: jsonEncode(entry.value),
        ),
        throwsA(_formatCode(entry.key)),
        reason: entry.key,
      );
    }
  });

  test(
    'next revision retains identity root without exposing mutable bytes',
    () {
      final scope = StorageScopeId.generate();
      final envelope = ScopeSecretEnvelope.create(
        scopeId: scope,
        randomBytes: (_) => Uint8List.fromList(List<int>.filled(32, 9)),
      );
      final exposed = envelope.identityVaultRoot.copyMaterial()
        ..fillRange(0, 32, 0);
      final next = envelope.nextRevision();

      expect(exposed, List<int>.filled(32, 0));
      expect(next.revision, 2);
      expect(next.identityVaultRoot.copyMaterial(), List<int>.filled(32, 9));
      expect(next.identityVaultRoot.keyId, envelope.identityVaultRoot.keyId);
    },
  );
}

Map<String, Object?> _validJson(StorageScopeId scope) =>
    jsonDecode(
          ScopeSecretEnvelope.create(
            scopeId: scope,
            randomBytes: (_) => Uint8List.fromList(List<int>.filled(32, 5)),
          ).encode(),
        )
        as Map<String, Object?>;

Map<String, Object?> _root(Map<String, Object?> json) =>
    (json['active_secrets']! as Map<String, Object?>)['identity_vault_root']!
        as Map<String, Object?>;

Matcher _formatCode(String code) =>
    isA<FormatException>().having((error) => error.message, 'message', code);
