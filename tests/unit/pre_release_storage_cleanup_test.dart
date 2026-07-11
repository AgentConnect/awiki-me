import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/pre_release_storage_cleanup.dart';

void main() {
  late Directory root;
  late _FakeLegacyKeychain keychain;
  late PreReleaseStorageCleanup cleanup;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('awiki_cleanup_test_');
    keychain = _FakeLegacyKeychain();
    cleanup = PreReleaseStorageCleanup(
      supportRoot: root.path,
      keychain: keychain,
      clock: () => DateTime.utc(2026, 7, 11, 12, 34, 56),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'inventory derives only known legacy accounts and never reads values',
    () async {
      await Directory(
        '${cleanup.legacyEnvironmentsRoot}/customer.example.com',
      ).create(recursive: true);
      final expected = legacyLocatorsForNamespaces(<String>[
        'customer.example.com',
      ]).first;
      keychain.existing.add(_key(expected));

      final plan = await cleanup.inspect();

      expect(
        plan.namespaces,
        containsAll(<String>[
          'awiki.ai',
          'tenant-default',
          'customer.example.com',
        ]),
      );
      expect(plan.existingKeychainItems, hasLength(1));
      expect(plan.existingKeychainItems.single.account, expected.account);
      expect(keychain.valueReads, 0);
      expect(
        jsonEncode(plan.toJson()),
        isNot(anyOf(contains('root-secret'), contains('material_b64'))),
      );
    },
  );

  test('dry run never changes directory or Keychain', () async {
    final directory = Directory('${cleanup.legacyEnvironmentsRoot}/awiki.ai');
    await directory.create(recursive: true);
    final locator = legacyLocatorsForNamespaces(<String>['awiki.ai']).first;
    keychain.existing.add(_key(locator));
    final plan = await cleanup.inspect();

    expect(
      await cleanup.execute(plan, mode: PreReleaseCleanupMode.dryRun),
      isNull,
    );
    expect(await directory.exists(), isTrue);
    expect(keychain.deleted, isEmpty);
  });

  test('archive moves legacy directory but preserves Keychain items', () async {
    await Directory(
      '${cleanup.legacyEnvironmentsRoot}/tenant-default',
    ).create(recursive: true);
    final locator = legacyLocatorsForNamespaces(<String>[
      'tenant-default',
    ]).last;
    keychain.existing.add(_key(locator));
    final plan = await cleanup.inspect();

    final archived = await cleanup.execute(
      plan,
      mode: PreReleaseCleanupMode.archive,
      confirmation: archiveConfirmation,
    );

    expect(archived, isNotNull);
    expect(await Directory(archived!).exists(), isTrue);
    expect(await Directory(cleanup.legacyEnvironmentsRoot).exists(), isFalse);
    expect(keychain.deleted, isEmpty);
    final manifest = await Directory(cleanup.archiveRoot)
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .single;
    final content = await manifest.readAsString();
    expect(content, contains(locator.account));
    expect(content, isNot(contains('root-secret')));
  });

  test(
    'delete requires exact confirmation and removes only inventoried legacy items',
    () async {
      await Directory(
        '${cleanup.legacyEnvironmentsRoot}/awiki.ai',
      ).create(recursive: true);
      final legacy = legacyLocatorsForNamespaces(<String>['awiki.ai']).first;
      keychain.existing.add(_key(legacy));
      final plan = await cleanup.inspect();

      await expectLater(
        cleanup.execute(
          plan,
          mode: PreReleaseCleanupMode.delete,
          confirmation: 'yes',
        ),
        throwsStateError,
      );
      expect(await Directory(cleanup.legacyEnvironmentsRoot).exists(), isTrue);

      await cleanup.execute(
        plan,
        mode: PreReleaseCleanupMode.delete,
        confirmation: deleteConfirmation,
      );

      expect(await Directory(cleanup.legacyEnvironmentsRoot).exists(), isFalse);
      expect(keychain.deleted, <String>[_key(legacy)]);
    },
  );

  test('inventory refuses a symlinked legacy root', () async {
    final target = await Directory.systemTemp.createTemp(
      'awiki_cleanup_target_',
    );
    addTearDown(() async {
      if (await target.exists()) await target.delete(recursive: true);
    });
    await Directory('${root.path}/awiki-me').create(recursive: true);
    await Link(cleanup.legacyEnvironmentsRoot).create(target.path);
    await expectLater(cleanup.inspect(), throwsStateError);
  });
}

class _FakeLegacyKeychain implements LegacyKeychainAccess {
  final Set<String> existing = <String>{};
  final List<String> deleted = <String>[];
  int valueReads = 0;

  @override
  Future<bool> exists(LegacyKeychainLocator locator) async =>
      existing.contains(_key(locator));

  @override
  Future<void> delete(LegacyKeychainLocator locator) async {
    deleted.add(_key(locator));
    existing.remove(_key(locator));
  }
}

String _key(LegacyKeychainLocator locator) =>
    '${locator.service}|${locator.account}';
