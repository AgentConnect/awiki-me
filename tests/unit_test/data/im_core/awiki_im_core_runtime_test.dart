import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('open creates directories before invoking the SDK opener', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_test_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '${root.path}/support',
      cacheRoot: '${root.path}/cache',
      tempRoot: '${root.path}/tmp',
    );
    var openerCalled = false;
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
          }) async {
            openerCalled = true;
            expect(await Directory(paths.identityRootDir).exists(), isTrue);
            expect(await Directory(layout.cacheDir).exists(), isTrue);
            expect(await Directory(layout.tempDir).exists(), isTrue);
            throw UnsupportedError('fake opener stops before native load');
          },
    );

    await expectLater(runtime.open(), throwsA(isA<UnsupportedError>()));
    expect(openerCalled, isTrue);
    expect(runtime.isOpen, isFalse);
  });

  test('currentClient fails clearly before an identity is selected', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_test_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: AwikiImCorePathLayout.fromRoots(
        appSupportRoot: '${root.path}/support',
        cacheRoot: '${root.path}/cache',
        tempRoot: '${root.path}/tmp',
      ),
    );

    await expectLater(runtime.currentClient(), throwsA(isA<StateError>()));
  });
}
