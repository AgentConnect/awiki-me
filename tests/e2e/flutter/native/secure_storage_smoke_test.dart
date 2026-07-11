import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'macOS dev scope Keychain persists, creates exclusively, CASes and deletes',
    (tester) async {
      final scope = StorageScopeId.generate();
      final repository = PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.development,
      );
      addTearDown(() async {
        try {
          await repository.delete(scope);
        } on Object {
          // Best-effort cleanup: preserve the primary failure signal.
        }
      });

      final first = ScopeSecretRecord(
        envelope: ScopeSecretEnvelope.create(scopeId: scope),
      );
      await expectLater(
        const MacOsScopeSecretPlatformStore().read(
          service: 'ai.awiki.awikime.scope-secrets',
          account: PlatformScopeSecretRepository.accountFor(scope),
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'scope_secret_bad_request',
          ),
        ),
      );
      final tampered = jsonDecode(first.envelope.encode()) as Map;
      final activeSecrets = tampered['active_secrets'] as Map;
      final rootSecret = activeSecrets['identity_vault_root'] as Map;
      rootSecret['material_b64'] = base64Encode(List<int>.filled(31, 1));
      await expectLater(
        const MacOsScopeSecretPlatformStore().createExclusive(
          service: 'ai.awiki.awikime.dev.scope-secrets',
          account: PlatformScopeSecretRepository.accountFor(scope),
          value: jsonEncode(tampered),
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'scope_secret_corrupt',
          ),
        ),
      );
      await repository.createExclusive(first);
      final restored = await PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.development,
      ).readExisting(scope);
      expect(restored.status, ScopeSecretReadStatus.present);
      expect(restored.record!.envelope.revision, 1);
      expect(
        restored.record!.envelope.identityVaultRoot.copyMaterial(),
        first.envelope.identityVaultRoot.copyMaterial(),
      );
      await expectLater(
        repository.createExclusive(first),
        throwsA(
          isA<ScopeSecretException>().having(
            (error) => error.failure,
            'failure',
            ScopeSecretFailure.alreadyExists,
          ),
        ),
      );

      final next = ScopeSecretRecord(envelope: first.envelope.nextRevision());
      await repository.compareAndReplace(record: next, expectedRevision: 1);
      expect(
        (await repository.readExisting(scope)).record!.envelope.revision,
        2,
      );
      await expectLater(
        repository.compareAndReplace(record: next, expectedRevision: 1),
        throwsA(
          isA<ScopeSecretException>().having(
            (error) => error.failure,
            'failure',
            ScopeSecretFailure.revisionConflict,
          ),
        ),
      );

      await repository.delete(scope);
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.missing,
      );
    },
    skip: !Platform.isMacOS,
  );
}
