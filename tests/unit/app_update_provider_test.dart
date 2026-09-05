import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:awiki_me/src/domain/services/update_service.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_update_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

AppUpdateManifest buildManifest() {
  return AppUpdateManifest(
    policyOrigin: 'https://example.com',
    policyRevision: 1,
    version: '0.2.0',
    buildNumber: 2,
    minimumSupportedVersion: '0.1.0',
    minimumSupportedBuildNumber: 1,
    publishedAt: DateTime.utc(2026, 4, 5, 8),
    releaseNotesUrl: 'https://example.com/release-notes',
    githubReleaseUrl: 'https://example.com/releases/tag/v0.2.0',
    platforms: const AppUpdatePlatformsManifest(
      macos: AppUpdatePlatformManifest(
        downloadUrl: 'https://example.com/app.dmg',
        appcastUrl: 'https://example.com/appcast.xml',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        sizeBytes: 123,
      ),
      android: AppUpdatePlatformManifest(
        downloadUrl: 'https://example.com/app.apk',
        sha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        sizeBytes: 456,
        minSupportedBuildNumber: 1,
      ),
    ),
  );
}

void main() {
  testWidgets('Windows App Shell initializes local and remote version state', (
    tester,
  ) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final updateService = FakeUpdateService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        updateService: updateService,
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final state = container.read(appUpdateProvider);
    expect(updateService.getCurrentVersionCalls, 1);
    expect(updateService.checkForUpdatesCalls, 1);
    expect(state.currentVersion?.displayLabel, '0.1.0+1');
    expect(state.status, AppUpdateStatus.upToDate);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('restricted update page can force-refresh a cached lock', (
    tester,
  ) async {
    final updateService = FakeUpdateService()
      ..latestManifest = buildManifest()
      ..versionUnsupported = true;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        updateService: updateService,
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('restricted-update-refresh')));
    await tester.pump();

    expect(updateService.checkForUpdatesForces, <bool>[false, true]);
  });

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

    test('横幅按语义版本优先于租户独立 build 号判断更新', () {
      final manifest = buildManifest();
      final state = AppUpdateState(
        currentVersion: const AppVersion(version: '0.1.0', buildNumber: 20),
        latestManifest: manifest,
      );

      expect(state.hasUpdate, isTrue);
    });

    test('忽略推荐版本会持久标记并立即隐藏横幅', () async {
      updateService.latestManifest = buildManifest();
      await container.read(appUpdateProvider.notifier).initialize();

      await container.read(appUpdateProvider.notifier).dismissRecommendation();

      expect(container.read(appUpdateProvider).recommendationDismissed, isTrue);
      expect(updateService.ignored, isTrue);
    });

    test('手动官方源检查不会对自定义租户施加最低版本门禁', () async {
      updateService.latestManifest = buildManifest();

      await container
          .read(appUpdateProvider.notifier)
          .checkOfficialSource(AppOfficialUpdateSource.secondary);

      expect(container.read(appUpdateProvider), isA<AppUpdateState>());
      expect(
        container.read(appUpdateProvider).manualOfficialSource,
        AppOfficialUpdateSource.secondary,
      );
      expect(container.read(appUpdateProvider).versionUnsupported, isFalse);
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

    test('后台版本检查在 provider 销毁后不会写入状态', () async {
      final pendingService = _PendingUpdateService();
      final pendingContainer = ProviderContainer(
        overrides: <Override>[
          updateServiceProvider.overrideWithValue(pendingService),
        ],
      );
      final initialize = pendingContainer
          .read(appUpdateProvider.notifier)
          .initialize();
      await pendingService.checkStarted.future;

      pendingContainer.dispose();
      pendingService.complete();

      await expectLater(initialize, completes);
    });
  });
}

class _PendingUpdateService extends FakeUpdateService {
  final Completer<void> checkStarted = Completer<void>();
  final Completer<AppUpdateCheckResult> _result =
      Completer<AppUpdateCheckResult>();

  @override
  Future<AppUpdateCheckResult> checkForUpdates({required bool force}) {
    checkForUpdatesCalls += 1;
    checkStarted.complete();
    return _result.future;
  }

  void complete() {
    _result.complete(AppUpdateCheckResult(currentVersion: currentVersion));
  }
}
