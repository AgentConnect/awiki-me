import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/awiki_storage_scope_layout.dart';
import 'package:awiki_me/src/data/storage/scope_manifest.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/storage_scope_provisioner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FakeScopeSecretRepository secrets;
  late StorageScopeManifestStore manifests;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('awiki_scope_provision_test_');
    secrets = FakeScopeSecretRepository();
    manifests = const StorageScopeManifestStore();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'fault matrix resumes after secret or rolls back pristine scope',
    () async {
      for (final point in <StorageScopeProvisionPoint>[
        StorageScopeProvisionPoint.rootCreated,
        StorageScopeProvisionPoint.manifestWritten,
        StorageScopeProvisionPoint.secretCreated,
        StorageScopeProvisionPoint.directoriesCreated,
      ]) {
        final profile = _profile();
        final layout = _layout(root, profile.storageScopeId);
        final provisioner = _provisioner(secrets, manifests, failAt: point);
        await expectLater(
          provisioner.provision(layout: layout, owner: profile),
          throwsA(isA<_InjectedCrash>()),
        );
        if (point == StorageScopeProvisionPoint.rootCreated) {
          expect(await File(layout.manifestPath).exists(), isFalse);
          expect(
            await _provisioner(
              secrets,
              manifests,
            ).recoverOrphan(layout: layout),
            isNull,
          );
          expect(await Directory(layout.scopeRoot).exists(), isFalse);
          continue;
        }
        final recovered = await _provisioner(
          secrets,
          manifests,
        ).recover(layout: layout, expectedOwner: profile.tenantProfileId);
        if (point == StorageScopeProvisionPoint.manifestWritten) {
          expect(recovered, isNull);
          expect(await Directory(layout.scopeRoot).exists(), isFalse);
        } else {
          expect(recovered?.lifecycle, StorageScopeLifecycle.ready);
          expect(await Directory(layout.identityVaultRoot).exists(), isTrue);
        }
      }
    },
  );

  test(
    'existing ready scope missing key is blocked and never recreated',
    () async {
      final profile = _profile();
      final layout = _layout(root, profile.storageScopeId);
      await _provisioner(
        secrets,
        manifests,
      ).provision(layout: layout, owner: profile);
      await secrets.delete(profile.storageScopeId);

      final recovered = await _provisioner(
        secrets,
        manifests,
      ).recover(layout: layout, expectedOwner: profile.tenantProfileId);

      expect(recovered?.lifecycle, StorageScopeLifecycle.blocked);
      expect(
        (await secrets.readExisting(profile.storageScopeId)).status,
        ScopeSecretReadStatus.missing,
      );
    },
  );

  test('non-pristine provisioning scope without key is blocked', () async {
    final profile = _profile();
    final layout = _layout(root, profile.storageScopeId);
    await expectLater(
      _provisioner(
        secrets,
        manifests,
        failAt: StorageScopeProvisionPoint.manifestWritten,
      ).provision(layout: layout, owner: profile),
      throwsA(isA<_InjectedCrash>()),
    );
    await File(layout.imCoreSqlitePath).parent.create(recursive: true);
    await File(layout.imCoreSqlitePath).writeAsString('durable-data');

    final recovered = await _provisioner(
      secrets,
      manifests,
    ).recover(layout: layout, expectedOwner: profile.tenantProfileId);

    expect(recovered?.lifecycle, StorageScopeLifecycle.blocked);
    expect(await File(layout.imCoreSqlitePath).readAsString(), 'durable-data');
  });

  test('secret access denied blocks scope without replacing secret', () async {
    final profile = _profile();
    final layout = _layout(root, profile.storageScopeId);
    await _provisioner(
      secrets,
      manifests,
    ).provision(layout: layout, owner: profile);
    secrets.deniedScopes.add(profile.storageScopeId);

    final recovered = await _provisioner(
      secrets,
      manifests,
    ).recover(layout: layout, expectedOwner: profile.tenantProfileId);

    expect(recovered?.lifecycle, StorageScopeLifecycle.blocked);
    expect(
      (await secrets.readExisting(profile.storageScopeId)).status,
      ScopeSecretReadStatus.accessDenied,
    );
  });

  test('manifest owner/scope mismatch fails closed', () async {
    final profile = _profile();
    final layout = _layout(root, profile.storageScopeId);
    await _provisioner(
      secrets,
      manifests,
    ).provision(layout: layout, owner: profile);

    await expectLater(
      _provisioner(
        secrets,
        manifests,
      ).recover(layout: layout, expectedOwner: TenantProfileId.generate()),
      throwsFormatException,
    );
  });

  test('unknown manifest schema fails closed', () async {
    final profile = _profile();
    final layout = _layout(root, profile.storageScopeId);
    await _provisioner(
      secrets,
      manifests,
    ).provision(layout: layout, owner: profile);
    final file = File(layout.manifestPath);
    final json = jsonDecode(await file.readAsString()) as Map;
    json['schema_version'] = 2;
    await file.writeAsString(jsonEncode(json));

    await expectLater(
      _provisioner(secrets, manifests).recoverOrphan(layout: layout),
      throwsFormatException,
    );
  });

  test('layout derives only from scope and rejects symlink root', () async {
    final scope = StorageScopeId.generate();
    final first = _layout(root, scope);
    final second = _layout(root, scope);
    expect(first.scopeRoot, second.scopeRoot);

    final external = await Directory.systemTemp.createTemp('awiki_external_');
    addTearDown(() async {
      if (await external.exists()) await external.delete(recursive: true);
    });
    await Directory(first.scopesRoot).create(recursive: true);
    await Link(first.scopeRoot).create(external.path);
    await expectLater(
      first.assertSafeExistingScope(),
      throwsA(isA<FileSystemException>()),
    );
  });
}

AppTenantProfile _profile() {
  final now = DateTime.utc(2026, 7, 11).toIso8601String();
  return AppTenantProfile(
    tenantProfileId: TenantProfileId.generate(),
    storageScopeId: StorageScopeId.generate(),
    kind: AppTenantKind.custom,
    name: 'Tenant',
    backendBaseUrl: 'https://tenant.example.com',
    didHost: 'tenant.example.com',
    lifecycle: AppTenantLifecycle.active,
    createdAt: now,
    updatedAt: now,
  );
}

AwikiStorageScopeLayout _layout(Directory root, StorageScopeId scope) =>
    AwikiStorageScopeLayout.fromRoots(
      appSupportRoot: '${root.path}/support',
      cacheRoot: '${root.path}/cache',
      tempRoot: '${root.path}/tmp',
      scopeId: scope,
    );

StorageScopeProvisioner _provisioner(
  FakeScopeSecretRepository secrets,
  StorageScopeManifestStore manifests, {
  StorageScopeProvisionPoint? failAt,
}) => StorageScopeProvisioner(
  secrets: secrets,
  manifests: manifests,
  secretFactory: (scope) =>
      ScopeSecretRecord(scopeId: scope, opaqueValue: Object()),
  faultInjector: failAt == null
      ? null
      : (point) async {
          if (point == failAt) throw const _InjectedCrash();
        },
);

class _InjectedCrash implements Exception {
  const _InjectedCrash();
}
