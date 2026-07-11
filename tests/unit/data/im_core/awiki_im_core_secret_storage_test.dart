import 'dart:typed_data';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('openExisting returns the exact scope root without creating', () async {
    final scope = StorageScopeId.generate();
    final record = ScopeSecretRecord(
      envelope: ScopeSecretEnvelope.create(
        scopeId: scope,
        randomBytes: (_) => Uint8List.fromList(List<int>.filled(32, 7)),
      ),
    );
    final repository = _ReadOnlyRepository(
      ScopeSecretReadResult(ScopeSecretReadStatus.present, record: record),
    );
    final provider = ScopeAwikiImCoreVaultSecretProvider(
      repository: repository,
    );

    final secrets = await provider.openExisting(scope);

    expect(secrets.rootKey.bytes, List<int>.filled(32, 7));
    expect(repository.reads, 1);
    expect(repository.creates, 0);
  });

  test(
    'all non-present states fail closed with stable redacted code',
    () async {
      final cases = <ScopeSecretReadStatus, String>{
        ScopeSecretReadStatus.missing: 'vault_key_missing',
        ScopeSecretReadStatus.accessDenied: 'vault_key_access_denied',
        ScopeSecretReadStatus.corrupt: 'vault_key_bundle_corrupt',
        ScopeSecretReadStatus.scopeMismatch: 'vault_key_scope_mismatch',
        ScopeSecretReadStatus.schemaUnsupported: 'vault_key_schema_unsupported',
        ScopeSecretReadStatus.providerUnavailable:
            'vault_key_provider_unavailable',
        ScopeSecretReadStatus.unsupported: 'vault_key_platform_unsupported',
      };
      final scope = StorageScopeId.generate();
      for (final entry in cases.entries) {
        final provider = ScopeAwikiImCoreVaultSecretProvider(
          repository: _ReadOnlyRepository(ScopeSecretReadResult(entry.key)),
        );
        await expectLater(
          provider.openExisting(scope),
          throwsA(
            isA<AwikiVaultOpenException>()
                .having((error) => error.code, 'code', entry.value)
                .having(
                  (error) => error.toString(),
                  'redacted',
                  isNot(contains('material_b64')),
                ),
          ),
        );
      }
    },
  );
}

class _ReadOnlyRepository implements ScopeSecretRepository {
  _ReadOnlyRepository(this.result);

  final ScopeSecretReadResult result;
  int reads = 0;
  int creates = 0;

  @override
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId) async {
    reads += 1;
    return result;
  }

  @override
  Future<void> createExclusive(ScopeSecretRecord record) async {
    creates += 1;
    throw UnsupportedError('not used');
  }

  @override
  Future<void> compareAndReplace({
    required ScopeSecretRecord record,
    required int expectedRevision,
  }) => throw UnsupportedError('not used');

  @override
  Future<void> delete(StorageScopeId scopeId) =>
      throw UnsupportedError('not used');
}
