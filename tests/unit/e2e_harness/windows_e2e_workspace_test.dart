import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/windows_e2e_workspace.dart';

void main() {
  test(
    'restart and recovery phases keep one logical device secret namespace',
    () {
      final specs =
          jsonDecode(
                File('tests/e2e/app_artifact_specs.json').readAsStringSync(),
              )
              as Map;
      final bundles = {
        for (final artifact in specs['artifacts'] as List)
          artifact['name'] as String: artifact['bundleId'] as String,
      };
      for (final names in [
        ['restart-a', 'restart-b', 'restart-c'],
        [
          'recovery-main',
          'recovery-crash-a',
          'recovery-crash-b',
          'recovery-fresh-restart',
          'recovery-registration-resume-a',
          'recovery-registration-resume-b',
        ],
        ['identity-deletion-a', 'identity-deletion-b'],
        ['hosted-gateway-join', 'hosted-gateway-resume'],
      ]) {
        expect(names.map((name) => bundles[name]).toSet(), hasLength(1));
        expect(
          names.map((name) => windowsE2eSecretService(bundles[name]!)).toSet(),
          hasLength(1),
        );
      }
      final admin = windowsE2eSecretService(bundles['admin']!);
      final joiner = windowsE2eSecretService(bundles['joiner']!);
      expect(admin, isNot(joiner));
      expect(admin, isNot('ai.awiki.awikime.dev.scope-secrets'));
      expect(admin, windowsE2eSecretService(bundles['restart-a']!));
    },
  );
  test(
    'snapshot inventory retains shared unit fakes and excludes private fixtures',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki-source-inventory-',
      );
      addTearDown(() => root.delete(recursive: true));
      final git = await Process.run('git', [
        'init',
        '--quiet',
      ], workingDirectory: root.path);
      expect(git.exitCode, 0);
      for (final path in [
        'tests/unit/test_support.dart',
        'tests/unit/support/fakes.dart',
        'tests/e2e/flutter/support/fake_app_bootstrap.dart',
      ]) {
        final file = File('${root.path}/$path');
        await file.parent.create(recursive: true);
        await file.writeAsString('// synthetic shared support');
      }
      await File('${root.path}/.gitignore').writeAsString('*.local.yaml\n');
      await File(
        '${root.path}/tests/e2e/private.local.yaml',
      ).writeAsString('must-not-copy');
      final paths = await windowsE2eSourceInventory(root);
      expect(
        paths,
        containsAll([
          'tests/unit/test_support.dart',
          'tests/unit/support/fakes.dart',
          'tests/e2e/flutter/support/fake_app_bootstrap.dart',
        ]),
      );
      expect(paths, isNot(contains('tests/e2e/private.local.yaml')));
    },
  );
  test(
    'source refresh retains native cache and removes stale copied source',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-native-cache-');
      addTearDown(() => root.delete(recursive: true));
      final snapshot = Directory('${root.path}/.e2e/slot/s');
      final object = File('${snapshot.path}/build/windows/runner.obj');
      await object.parent.create(recursive: true);
      await object.writeAsString('native-cache');
      final stale = File('${snapshot.path}/lib/removed.dart');
      await stale.parent.create(recursive: true);
      await stale.writeAsString('stale source');
      await resetWindowsE2eSnapshot(projectRoot: root, destination: snapshot);
      expect(await object.readAsString(), 'native-cache');
      expect(stale.existsSync(), isFalse);
      expect(snapshot.existsSync(), isTrue);
    },
  );

  test(
    'source refresh refuses a linked native cache before changing source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki-cache-boundary-',
      );
      addTearDown(() => root.delete(recursive: true));
      final outside = await Directory.systemTemp.createTemp(
        'awiki-cache-outside-',
      );
      addTearDown(() => outside.delete(recursive: true));
      final snapshot = await Directory(
        '${root.path}/.e2e/slot/s',
      ).create(recursive: true);
      final source = await File(
        '${snapshot.path}/keep.dart',
      ).writeAsString('keep');
      final sentinel = await File(
        '${outside.path}/sentinel',
      ).writeAsString('outside');
      await Link('${snapshot.path}/build').create(outside.path);
      await expectLater(
        resetWindowsE2eSnapshot(projectRoot: root, destination: snapshot),
        throwsStateError,
      );
      expect(await source.readAsString(), 'keep');
      expect(await sentinel.readAsString(), 'outside');
    },
  );

  test(
    'Windows snapshot relocation retains package versions and archive checksums',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki-win-dependency-contract-',
      );
      addTearDown(() => root.delete(recursive: true));
      final snapshot = await Directory('${root.path}/snapshot').create();
      Map<String, Object> lock(
        String version,
        String checksum,
        String hosted,
      ) => {
        'packages': {
          'fixture': {
            'version': version,
            'source': 'hosted',
            'description': {'sha256': checksum, 'url': hosted},
          },
        },
      };
      await File(
        '${root.path}/pubspec.lock',
      ).writeAsString(jsonEncode(lock('1.2.3', 'archive', 'https://pub.dev')));
      final relocated = File('${snapshot.path}/pubspec.lock');
      await relocated.writeAsString(
        jsonEncode(lock('1.2.3', 'archive', 'https://mirror.example/')),
      );
      verifyWindowsSnapshotDependencies(root, snapshot);
      await relocated.writeAsString(
        jsonEncode(lock('1.2.4', 'archive', 'https://mirror.example/')),
      );
      expect(
        () => verifyWindowsSnapshotDependencies(root, snapshot),
        throwsStateError,
      );
      await relocated.writeAsString(
        jsonEncode(lock('1.2.3', 'changed', 'https://mirror.example/')),
      );
      expect(
        () => verifyWindowsSnapshotDependencies(root, snapshot),
        throwsStateError,
      );
    },
  );

  test(
    'Windows role identities isolate native roots and retain developer source',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki-win-role-contract-',
      );
      addTearDown(() => root.delete(recursive: true));
      const inputs = [
        'windows/CMakeLists.txt',
        'windows/runner/app_constants.h',
        'windows/runner/Runner.rc',
        'windows/runner/desktop_shell.cpp',
        'windows/runner/window_placement.cpp',
        'windows/runner/scope_secret_store.cpp',
        'lib/src/data/storage/platform_scope_secret_repository.dart',
        'lib/src/data/services/app_notification_facade.dart',
      ];
      final originals = {
        for (final path in inputs) path: File(path).readAsStringSync(),
      };
      final headers = <String>[];
      final nativeRoots = <String>[];
      for (final role in ['admin', 'joiner']) {
        final source = Directory('${root.path}/$role');
        for (final entry in originals.entries) {
          final file = File('${source.path}/${entry.key}');
          await file.parent.create(recursive: true);
          await file.writeAsString(entry.value);
        }
        applyWindowsE2eIdentity(
          source,
          bundleId: 'ai.awiki.e2e.$role',
          name: role,
        );
        final header = File(
          '${source.path}/windows/runner/app_constants.h',
        ).readAsStringSync();
        expect(header, contains('ai.awiki.e2e.$role.single-instance'));
        expect(header, isNot(contains('L"AWiki Me"')));
        final cmake = File(
          '${source.path}/windows/CMakeLists.txt',
        ).readAsStringSync();
        expect(
          cmake,
          isNot(contains('if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)')),
        );
        expect(
          cmake,
          contains(
            r'set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "E2E bundle only" FORCE)',
          ),
        );
        headers.add(header);
        final native = File(
          '${source.path}/windows/runner/desktop_shell.cpp',
        ).readAsStringSync();
        expect(native, isNot(contains('L"AWikiMe"')));
        nativeRoots.add(native);
        final dart = File(
          '${source.path}/lib/src/data/storage/platform_scope_secret_repository.dart',
        ).readAsStringSync();
        expect(dart, contains('ai.awiki.awikime.dev.e2e.'));
        final service = windowsE2eSecretService('ai.awiki.e2e.$role');
        expect(dart, contains(service));
        expect(
          File(
            '${source.path}/windows/runner/scope_secret_store.cpp',
          ).readAsStringSync(),
          contains(service),
        );
        expect(dart, isNot(contains('ai.awiki.awikime.dev.scope-secrets')));
      }
      expect(headers[0], isNot(headers[1]));
      expect(nativeRoots[0], isNot(nativeRoots[1]));
      for (final entry in originals.entries) {
        expect(File(entry.key).readAsStringSync(), entry.value);
      }
    },
  );

  test(
    'Windows snapshot refuses directories outside its generated build scope',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki-win-snapshot-boundary-',
      );
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        prepareWindowsE2eWorkspace(
          projectRoot: root,
          destination: Directory('${root.path}/source'),
          bundleId: 'ai.awiki.e2e.admin',
          name: 'admin',
        ),
        throwsStateError,
      );
      await expectLater(
        prepareWindowsE2eWorkspace(
          projectRoot: root,
          destination: Directory('${root.path}/.e2e/job/../../source'),
          bundleId: 'ai.awiki.e2e.admin',
          name: 'admin',
        ),
        throwsStateError,
      );
      expect(Directory('${root.path}/source').existsSync(), isFalse);
    },
  );
}
