import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'AwikiImCore.open desktop native backend smoke',
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
      final vaultDir = Directory('${root.path}/identity-vault');
      final stateDir = Directory('${root.path}/state');
      final cacheDir = Directory('${root.path}/cache');
      final tempDir = Directory('${root.path}/tmp');
      await Future.wait(<Future<Directory>>[
        identityRoot.create(recursive: true),
        vaultDir.create(recursive: true),
        stateDir.create(recursive: true),
        cacheDir.create(recursive: true),
        tempDir.create(recursive: true),
      ]);

      final environment = AwikiImCoreEnvironmentConfig.fromEnvironment();
      final imCore = await core.AwikiImCore.open(
        config: environment.toCoreConfig(),
        paths: core.AwikiImCorePaths(
          identityRootDir: identityRoot.path,
          registryPath: '${identityRoot.path}/registry.json',
          defaultIdentityPath: '${identityRoot.path}/default',
          sqlitePath: '${stateDir.path}/im_core.sqlite',
          cacheDir: cacheDir.path,
          tempDir: tempDir.path,
        ),
        openOptions: core.AwikiImCoreOpenOptions.vaultRequired(
          identitySecretVault: core.ImCoreSecretVaultOptions(
            rootKey: core.DeviceVaultRootKey.fromList(
              List<int>.generate(32, (index) => index + 1),
            ),
            vaultDir: vaultDir.path,
            workspaceId: 'awiki-me-native-smoke',
            deviceId: 'app-device-native-smoke',
          ),
        ),
      );
      addTearDown(imCore.dispose);

      expect(environment.serviceBaseUrl, isNotEmpty);
      expect(environment.didDomain, isNotEmpty);
      expect(await imCore.validatePaths(), isA<List<String>>());
    },
    // Desktop native smoke is intentionally limited to desktop targets. Linux
    // is allowed to execute here once the Flutter Linux runner exists; until
    // awiki_im_core adds Linux native support it should fail loudly instead of
    // being silently treated as a passing E2E gate.
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}
