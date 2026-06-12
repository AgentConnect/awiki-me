import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'AwikiImCore.open macOS native backend smoke',
    (_) async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_me_im_core_smoke_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final identityRoot = Directory('${root.path}/identities');
      final stateDir = Directory('${root.path}/state');
      final cacheDir = Directory('${root.path}/cache');
      final tempDir = Directory('${root.path}/tmp');
      await Future.wait(<Future<Directory>>[
        identityRoot.create(recursive: true),
        stateDir.create(recursive: true),
        cacheDir.create(recursive: true),
        tempDir.create(recursive: true),
      ]);

      final imCore = await core.AwikiImCore.open(
        config: const core.AwikiImCoreConfig(
          serviceBaseUrl: 'https://awiki.ai',
          didDomain: 'awiki.ai',
        ),
        paths: core.AwikiImCorePaths(
          identityRootDir: identityRoot.path,
          registryPath: '${identityRoot.path}/registry.json',
          defaultIdentityPath: '${identityRoot.path}/default',
          sqlitePath: '${stateDir.path}/im_core.sqlite',
          cacheDir: cacheDir.path,
          tempDir: tempDir.path,
        ),
      );
      addTearDown(imCore.dispose);

      expect(await imCore.validatePaths(), isA<List<String>>());
    },
    // awiki_im_core native smoke is currently supported only on macOS in this
    // repository. Linux has no runner and no native plugin declaration yet.
    skip: !Platform.isMacOS,
  );
}
