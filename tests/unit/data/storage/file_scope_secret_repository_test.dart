import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/file_scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('awiki_scope_secret_e2e_');
    root = Directory('${sandbox.path}/scope-secrets');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'E2E provider uses private per-scope file and strict lifecycle',
    () async {
      final scope = StorageScopeId.generate();
      final repository = E2eFileScopeSecretRepository(root: root);
      final first = _record(scope);

      await repository.createExclusive(first);
      expect(await _mode(root.path), '700');
      expect(await _mode('${root.path}/${scope.value}.json'), '600');
      expect(
        (await repository.readExisting(scope)).record!.envelope.revision,
        1,
      );
      await expectLater(
        repository.createExclusive(first),
        throwsA(_failure(ScopeSecretFailure.alreadyExists)),
      );

      final next = ScopeSecretRecord(envelope: first.envelope.nextRevision());
      await repository.compareAndReplace(record: next, expectedRevision: 1);
      expect(
        (await repository.readExisting(scope)).record!.envelope.revision,
        2,
      );
      await expectLater(
        repository.compareAndReplace(record: next, expectedRevision: 1),
        throwsA(_failure(ScopeSecretFailure.revisionConflict)),
      );

      await repository.delete(scope);
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.missing,
      );
    },
  );

  test(
    'E2E provider rejects corrupt, symlink and unsafe permissions',
    () async {
      if (!(Platform.isMacOS || Platform.isLinux)) return;
      final scope = StorageScopeId.generate();
      await root.create(recursive: true);
      await Process.run('chmod', <String>['700', root.path]);
      final file = File('${root.path}/${scope.value}.json');
      await file.writeAsString('{broken');
      await Process.run('chmod', <String>['600', file.path]);
      final repository = E2eFileScopeSecretRepository(root: root);
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.corrupt,
      );

      await file.writeAsString(_record(scope).envelope.encode());
      await Process.run('chmod', <String>['644', file.path]);
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.accessDenied,
      );

      await sandbox.delete(recursive: true);
      await sandbox.create();
      final target = await Directory.systemTemp.createTemp(
        'awiki_scope_secret_target_',
      );
      addTearDown(() async {
        if (await target.exists()) await target.delete(recursive: true);
      });
      await Link(root.path).create(target.path);
      await expectLater(
        E2eFileScopeSecretRepository(root: root).readExisting(scope),
        throwsA(_failure(ScopeSecretFailure.accessDenied)),
      );
    },
  );

  test(
    'concurrent exclusive creators produce one winner and never overwrite',
    () async {
      final scope = StorageScopeId.generate();
      final first = E2eFileScopeSecretRepository(root: root);
      final second = E2eFileScopeSecretRepository(root: root);
      final records = <ScopeSecretRecord>[
        _record(scope, byte: 1),
        _record(scope, byte: 2),
      ];
      final outcomes = await Future.wait(
        <Future<void>>[
          first.createExclusive(records[0]),
          second.createExclusive(records[1]),
        ].map((future) async {
          try {
            await future;
            return true;
          } on ScopeSecretException catch (error) {
            expect(error.failure, ScopeSecretFailure.alreadyExists);
            return false;
          }
        }),
      );

      expect(outcomes.where((value) => value), hasLength(1));
      final stored = (await first.readExisting(scope)).record!.envelope;
      expect(<int>{
        1,
        2,
      }, contains(stored.identityVaultRoot.copyMaterial().first));
    },
  );

  test(
    'concurrent CAS writers produce one winner under the scope file lock',
    () async {
      final scope = StorageScopeId.generate();
      final first = E2eFileScopeSecretRepository(root: root);
      final second = E2eFileScopeSecretRepository(root: root);
      await first.createExclusive(_record(scope, byte: 1));
      final replacements = <ScopeSecretRecord>[
        ScopeSecretRecord(
          envelope: _record(scope, byte: 2).envelope.nextRevision(),
        ),
        ScopeSecretRecord(
          envelope: _record(scope, byte: 3).envelope.nextRevision(),
        ),
      ];

      final outcomes = await Future.wait(
        <Future<void>>[
          first.compareAndReplace(record: replacements[0], expectedRevision: 1),
          second.compareAndReplace(
            record: replacements[1],
            expectedRevision: 1,
          ),
        ].map((future) async {
          try {
            await future;
            return true;
          } on ScopeSecretException catch (error) {
            expect(error.failure, ScopeSecretFailure.revisionConflict);
            return false;
          }
        }),
      );

      expect(outcomes.where((value) => value), hasLength(1));
      final stored = (await first.readExisting(scope)).record!.envelope;
      expect(stored.revision, 2);
      expect(<int>{
        2,
        3,
      }, contains(stored.identityVaultRoot.copyMaterial().first));
    },
  );
}

ScopeSecretRecord _record(StorageScopeId scope, {int byte = 8}) =>
    ScopeSecretRecord(
      envelope: ScopeSecretEnvelope.create(
        scopeId: scope,
        randomBytes: (_) => Uint8List.fromList(List<int>.filled(32, byte)),
      ),
    );

Matcher _failure(ScopeSecretFailure failure) => isA<ScopeSecretException>()
    .having((error) => error.failure, 'failure', failure);

Future<String> _mode(String path) async {
  final result = await Process.run('stat', <String>['-f', '%Lp', path]);
  if (result.exitCode == 0) return result.stdout.toString().trim();
  final linux = await Process.run('stat', <String>['-c', '%a', path]);
  return linux.stdout.toString().trim();
}
