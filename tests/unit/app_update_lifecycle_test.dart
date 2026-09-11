import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:awiki_me/src/domain/services/update_service.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_update_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_update_provider_test.dart' show buildManifest;
import 'test_support.dart';

void main() {
  test(
    'a newer tenant check supersedes older tenant and official results',
    () async {
      final service = PendingUpdateService();
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateProvider.notifier);
      final oldTenant = controller.initialize();
      await service.started(1);
      final official = controller.checkOfficialSource(
        AppOfficialUpdateSource.secondary,
      );
      await service.started(2);
      final newTenant = controller.checkForUpdates(force: true);
      await service.started(3);
      service.complete(2, restricted: false);
      await newTenant;
      final state = container.read(appUpdateProvider);
      service.complete(0, restricted: true);
      service.complete(1, restricted: false);
      await Future.wait([oldTenant, official]);
      expect(container.read(appUpdateProvider), same(state));
      expect(state.versionUnsupported, isFalse);
      expect(state.manualOfficialSource, isNull);
    },
  );

  test(
    'a supported tenant result preserves the selected official recommendation',
    () async {
      final service = PendingUpdateService();
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateProvider.notifier);
      final tenant = controller.initialize();
      await service.started(1);
      final official = controller.checkOfficialSource(
        AppOfficialUpdateSource.secondary,
      );
      await service.started(2);
      service.complete(1, restricted: false);
      await official;
      final recommendation = container.read(appUpdateProvider);
      service.complete(0, restricted: false);
      await tenant;
      expect(container.read(appUpdateProvider), same(recommendation));
      expect(
        recommendation.manualOfficialSource,
        AppOfficialUpdateSource.secondary,
      );
    },
  );

  test(
    'official lookup during startup does not suppress the initial tenant check',
    () async {
      final service = PendingUpdateService();
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateProvider.notifier);
      final official = controller.checkOfficialSource(
        AppOfficialUpdateSource.secondary,
      );
      final tenant = controller.initialize();
      await service.started(2);
      // The official lookup enters first while both callers await local state.
      service.complete(0, restricted: false);
      await official;
      service.complete(1, restricted: true);
      await tenant;
      expect(container.read(appUpdateProvider).versionUnsupported, isTrue);
      expect(container.read(appUpdateProvider).manualOfficialSource, isNull);
    },
  );

  for (final officialFirst in [false, true]) {
    test(
      'tenant minimum survives an official lookup (official first: $officialFirst)',
      () async {
        final service = PendingUpdateService();
        final container = ProviderContainer(
          overrides: [updateServiceProvider.overrideWithValue(service)],
        );
        addTearDown(container.dispose);
        final controller = container.read(appUpdateProvider.notifier);
        final tenant = controller.initialize();
        await service.started(1);
        final official = controller.checkOfficialSource(
          AppOfficialUpdateSource.secondary,
        );
        await service.started(2);
        if (officialFirst) {
          service.complete(
            1,
            restricted: false,
            manifest: buildManifest(version: '9.0.0'),
          );
          await official;
        }
        service.complete(0, restricted: true);
        await tenant;
        expect(container.read(appUpdateProvider).versionUnsupported, isTrue);
        if (!officialFirst) {
          service.complete(
            1,
            restricted: false,
            manifest: buildManifest(version: '9.0.0'),
          );
          await official;
        }
        final state = container.read(appUpdateProvider);
        expect(state.versionUnsupported, isTrue);
        expect(state.manualOfficialSource, isNull);
        expect(state.latestManifest, isNotNull);
        expect(state.latestManifest?.version, '0.2.0');
        expect(state.status, AppUpdateStatus.updateAvailable);
      },
    );
  }

  test(
    'confirmed policy removal clears old recommendation and its target',
    () async {
      final service = FakeUpdateService()..latestManifest = buildManifest();
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateProvider.notifier);
      await controller.initialize();
      expect(container.read(appUpdateProvider).hasUpdate, isTrue);
      service
        ..latestManifest = null
        ..policyUnavailable = true;
      await controller.checkForUpdates(force: true);
      final state = container.read(appUpdateProvider);
      expect(state.status, AppUpdateStatus.unavailable);
      expect(state.latestManifest, isNull);
      expect(state.hasUpdate, isFalse);
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'updatePolicyUnavailable',
      );
    },
  );

  test('no manifest is unknown, never proof of being up to date', () async {
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(FakeUpdateService())],
    );
    addTearDown(container.dispose);
    await container
        .read(appUpdateProvider.notifier)
        .checkForUpdates(force: true);
    expect(container.read(appUpdateProvider).status, AppUpdateStatus.idle);
    expect(container.read(uiFeedbackProvider), isNull);
  });

  test(
    'an earlier background response cannot undo a newer forced restriction',
    () async {
      final service = PendingUpdateService();
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateProvider.notifier);
      final background = controller.initialize();
      await service.started(1);
      final forced = controller.checkForUpdates(force: true);
      await service.started(2);
      service.complete(1, restricted: true);
      await forced;
      service.complete(0, restricted: false);
      await background;
      expect(container.read(appUpdateProvider).versionUnsupported, isTrue);
    },
  );

  test('a late error does not replace the successful newer check', () async {
    final service = PendingUpdateService();
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appUpdateProvider.notifier);
    final first = controller.initialize();
    await service.started(1);
    final second = controller.checkForUpdates(force: true);
    await service.started(2);
    service.complete(1, restricted: true);
    await second;
    service.pending[0].completeError(StateError('old request failed'));
    await first;
    expect(
      container.read(appUpdateProvider).status,
      AppUpdateStatus.updateAvailable,
    );
    expect(container.read(appUpdateProvider).versionUnsupported, isTrue);
  });

  test(
    'foreign official lookup cannot unlock an existing tenant restriction',
    () async {
      final service = FakeUpdateService()
        ..latestManifest = buildManifest()
        ..versionUnsupported = true;
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      final controller = container.read(appUpdateProvider.notifier);
      await controller.initialize();
      await controller.checkOfficialSource(AppOfficialUpdateSource.secondary);
      expect(container.read(appUpdateProvider).versionUnsupported, isTrue);
      expect(service.checkForUpdatesCalls, 1);
    },
  );

  test('download page completion restores the update state', () async {
    final service = FakeUpdateService()..latestManifest = buildManifest();
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appUpdateProvider.notifier);
    await controller.initialize();
    await controller.installUpdate();
    expect(service.installUpdateCalled, isTrue);
    expect(
      container.read(appUpdateProvider).status,
      AppUpdateStatus.updateAvailable,
    );
  });

  test('blocked fallback lookup leaves the tenant refresh active', () async {
    final service = PendingUpdateService()
      ..cachedUpdate = AppUpdateCheckResult(
        currentVersion: const AppVersion(version: '0.1.0', buildNumber: 1),
        latestManifest: buildManifest(),
        versionUnsupported: true,
        usedCache: true,
      );
    final container = ProviderContainer(
      overrides: [updateServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appUpdateProvider.notifier);
    final refresh = controller.initialize();
    await service.started(1);
    await controller.checkOfficialSource(AppOfficialUpdateSource.secondary);
    service.complete(0, restricted: false);
    await refresh;
    expect(service.pending, hasLength(1));
    expect(container.read(appUpdateProvider).versionUnsupported, isFalse);
    expect(
      container.read(appUpdateProvider).status,
      AppUpdateStatus.updateAvailable,
    );
  });

  test(
    'disposing a tenant drops a pending result containing an upgrade',
    () async {
      final service = PendingUpdateService();
      final container = ProviderContainer(
        overrides: [updateServiceProvider.overrideWithValue(service)],
      );
      final task = container.read(appUpdateProvider.notifier).initialize();
      await service.started(1);
      container.dispose();
      service.complete(0, restricted: true);
      await expectLater(task, completes);
    },
  );

  for (final releaseNotes in [false, true]) {
    test(
      'late ${releaseNotes ? 'release notes' : 'download'} error is ignored after tenant disposal',
      () async {
        final service = _PendingLinkService();
        final container = ProviderContainer(
          overrides: [updateServiceProvider.overrideWithValue(service)],
        );
        final controller = container.read(appUpdateProvider.notifier);
        final action = releaseNotes
            ? controller.openReleaseNotes()
            : controller.openDownloadPage();
        container.dispose();
        service.result.completeError(StateError('browser unavailable'));
        await expectLater(action, completes);
      },
    );
  }

  testWidgets(
    'cached restriction blocks startup until refresh explicitly lifts it',
    (tester) async {
      final service = PendingUpdateService();
      service.cachedUpdate = AppUpdateCheckResult(
        currentVersion: service.currentVersion,
        latestManifest: buildManifest(),
        versionUnsupported: true,
        usedCache: true,
      );
      var initialized = 0;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          updateService: service,
          providerOverrides: [
            appRuntimeProvider.overrideWith(
              (ref) => CountingRuntime(ref, () => initialized++),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('restricted-update-install')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('restricted-update-switch-tenant')),
        findsOneWidget,
      );
      expect(initialized, 0);
      service.complete(0, restricted: false);
      await tester.pump();
      await tester.pump();
      expect(initialized, 1);
    },
  );

  testWidgets('cache miss does not hold startup for the network', (
    tester,
  ) async {
    final service = PendingUpdateService();
    var initialized = 0;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        updateService: service,
        providerOverrides: [
          appRuntimeProvider.overrideWith(
            (ref) => CountingRuntime(ref, () => initialized++),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(initialized, 1);
    service.complete(0, restricted: false);
    await tester.pump();
  });

  testWidgets('settings distinguish missing policy from latest version', (
    tester,
  ) async {
    final service = FakeUpdateService()..policyUnavailable = true;
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const SettingsPage(), updateService: service),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    await container
        .read(appUpdateProvider.notifier)
        .checkForUpdates(force: true);
    await tester.pump();
    expect(find.text('当前租户暂未提供更新信息'), findsOneWidget);
    expect(find.text('已是最新版本'), findsNothing);
  });
}

class PendingUpdateService extends FakeUpdateService {
  final pending = <Completer<AppUpdateCheckResult>>[];
  final changes = StreamController<int>.broadcast(sync: true);
  Future<void> started(int count) async {
    if (pending.length < count) {
      await changes.stream.firstWhere((value) => value >= count);
    }
  }

  @override
  Future<AppUpdateCheckResult> checkForUpdates({required bool force}) {
    pending.add(Completer<AppUpdateCheckResult>());
    changes.add(pending.length);
    return pending.last.future;
  }

  void complete(
    int index, {
    required bool restricted,
    AppUpdateManifest? manifest,
  }) => pending[index].complete(
    AppUpdateCheckResult(
      currentVersion: currentVersion,
      latestManifest: manifest ?? buildManifest(),
      versionUnsupported: restricted,
    ),
  );
}

class CountingRuntime extends AppRuntimeController {
  CountingRuntime(super.ref, this.onInitialize);
  final void Function() onInitialize;
  @override
  Future<void> initialize() async {
    onInitialize();
  }
}

class _PendingLinkService extends FakeUpdateService {
  final result = Completer<void>();
  @override
  Future<void> openDownloadPage(AppUpdateManifest? manifest) => result.future;
  @override
  Future<void> openReleaseNotes(AppUpdateManifest? manifest) => result.future;
}
