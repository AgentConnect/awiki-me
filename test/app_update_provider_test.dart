import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:awiki_me/src/domain/services/update_service.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_update_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  AppUpdateManifest buildManifest() {
    return AppUpdateManifest(
      version: '0.2.0',
      buildNumber: 2,
      publishedAt: DateTime.utc(2026, 4, 5, 8),
      releaseNotesUrl: 'https://example.com/release-notes',
      githubReleaseUrl: 'https://example.com/releases/tag/v0.2.0',
      platforms: const AppUpdatePlatformsManifest(
        macos: AppUpdatePlatformManifest(
          downloadUrl: 'https://example.com/app.dmg',
          appcastUrl: 'https://example.com/appcast.xml',
        ),
        android: AppUpdatePlatformManifest(
          downloadUrl: 'https://example.com/app.apk',
          sha256: 'abc',
          minSupportedBuildNumber: 1,
        ),
      ),
    );
  }

  group('AppUpdateController', () {
    late FakeUpdateService updateService;
    late ProviderContainer container;

    setUp(() {
      updateService = FakeUpdateService();
      container = ProviderContainer(
        overrides: <Override>[
          updateServiceProvider.overrideWithValue(updateService),
        ],
      );
      addTearDown(container.dispose);
    });

    test('初始化后可拿到当前版本并检测到可更新版本', () async {
      updateService.latestManifest = buildManifest();

      await container.read(appUpdateProvider.notifier).initialize();

      final state = container.read(appUpdateProvider);
      expect(state.currentVersion?.version, '0.1.0');
      expect(state.latestManifest?.version, '0.2.0');
      expect(state.status, AppUpdateStatus.updateAvailable);
    });

    test('手动检查发现已是最新版本时写入提示', () async {
      await container.read(appUpdateProvider.notifier).initialize();
      await container
          .read(appUpdateProvider.notifier)
          .checkForUpdates(force: true);

      expect(
        container.read(appUpdateProvider).status,
        AppUpdateStatus.upToDate,
      );
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'updateAlreadyLatest',
      );
    });

    test('Android 安装权限不足时引导打开设置', () async {
      updateService.latestManifest = buildManifest();
      updateService.installError = const UpdateInstallPermissionRequired();

      await container.read(appUpdateProvider.notifier).initialize();
      await container.read(appUpdateProvider.notifier).installUpdate();

      expect(updateService.installUpdateCalled, isTrue);
      expect(updateService.openInstallPermissionSettingsCalled, isTrue);
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'updatePermissionRequired',
      );
    });
  });
}
