import 'dart:async';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/desktop_network_preference.dart';
import 'package:awiki_me/src/presentation/server_features/backend_capabilities_provider.dart';
import 'package:awiki_me/src/presentation/server_features/server_features_page.dart';
import 'package:awiki_me/src/presentation/settings/network_settings_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

class _Store implements AppKeyValueStore {
  @override
  Future<String?> read({required String key}) async => null;
  @override
  Future<void> write({required String key, required String value}) async {}
  @override
  Future<void> delete({required String key}) async {}
}

class _RefreshCore extends FakeIdentityCorePort {
  int calls = 0;
  Completer<Map<String, dynamic>> pending = Completer();
  @override
  Future<Map<String, dynamic>> backendCapabilities({bool force = false}) {
    calls++;
    return pending.future;
  }
}

void main() {
  for (final width in [320.0, 560.0, 1100.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final locale in ['zh', 'en']) {
        for (final brightness in Brightness.values) {
          testWidgets('feature grid $width $scale $locale $brightness', (
            tester,
          ) async {
            tester.view
              ..devicePixelRatio = 1
              ..physicalSize = Size(width, 900);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final theme = AwikiMeTheme.forPlatform(
              TargetPlatform.macOS,
              brightness: brightness,
            );
            await tester.pumpWidget(
              buildLocalizedTestApp(
                locale: Locale(locale),
                providerOverrides: [
                  backendFeaturesProvider.overrideWithValue(
                    const AsyncData(BackendFeatures({})),
                  ),
                ],
                home: Theme(
                  data: theme.materialTheme,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 900),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: const ServerFeaturesPage(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final expected =
                (((width.clamp(0, 1040) - 32) + 12) / (240 * scale + 12))
                    .floor()
                    .clamp(1, 3);
            await tester.scrollUntilVisible(
              find.byKey(Key('server-feature-grid-message-$expected')),
              200,
            );
            expect(
              find.byKey(Key('server-feature-grid-message-$expected')),
              findsOneWidget,
            );
            final scroll = find.byType(Scrollable).first;
            await tester.scrollUntilVisible(
              find.byKey(const Key('server-feature-client_updates.policy')),
              300,
              scrollable: scroll,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            final preference = DesktopNetworkPreference(
              preferences: () async => _Store(),
              apply: (_) async {},
              readStatus: () async => core.AwikiNetworkStatus.proxyFallback,
            );
            await tester.pumpWidget(
              buildLocalizedTestApp(
                locale: Locale(locale),
                providerOverrides: [
                  desktopNetworkPreferenceProvider.overrideWithValue(
                    preference,
                  ),
                ],
                home: Theme(
                  data: theme.materialTheme,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 900),
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: const NetworkSettingsPage(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final rect = tester.getRect(find.byType(CupertinoSwitch));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            await tester.scrollUntilVisible(
              find.byKey(const Key('network-status')),
              200,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }
  }
  testWidgets('refresh is single-flight, keeps snapshot and handles failure', (
    tester,
  ) async {
    final port = _RefreshCore();
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ServerFeaturesPage(),
        providerOverrides: [
          identityCorePortProvider.overrideWithValue(port),
          backendFeaturesProvider.overrideWithValue(
            const AsyncData(
              BackendFeatures({
                'message': {
                  'status': 'stale',
                  'capabilities': {
                    'direct': {'support': 'supported'},
                  },
                },
              }),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final refresh = find.byKey(const Key('server-features-refresh'));
    await tester.tap(refresh);
    await tester.pump();
    await tester.tap(refresh);
    await tester.pump();
    expect(port.calls, 1);
    expect(find.byKey(const Key('server-feature-direct')), findsOneWidget);
    port.pending.completeError(StateError('private backend detail'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法更新，请重试。'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    port.pending = Completer();
    await tester.tap(refresh);
    await tester.pump();
    expect(port.calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    port.pending.completeError(StateError('late response'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  test('failed initialization can retry without changing preference', () async {
    var calls = 0;
    final preference = DesktopNetworkPreference(
      preferences: () async => _Store(),
      apply: (_) async {
        if (++calls == 1) throw StateError('temporary');
      },
    );
    await expectLater(preference.initialize(), throwsStateError);
    await preference.initialize();
    expect(calls, 2);
    expect(preference.enabled, isTrue);
  });
  testWidgets(
    'network separates initialization and status failures; coalesces reads',
    (tester) async {
      var attempts = 0;
      var reads = 0;
      final pending = Completer<core.AwikiNetworkStatus>();
      final preference = DesktopNetworkPreference(
        preferences: () async => _Store(),
        apply: (_) async {
          if (++attempts == 1) throw StateError('temporary');
        },
        readStatus: () {
          reads++;
          return pending.future;
        },
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const NetworkSettingsPage(),
          providerOverrides: [
            desktopNetworkPreferenceProvider.overrideWithValue(preference),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('无法读取网络设置，请重试。'), findsOneWidget);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).onChanged,
        isNull,
      );
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(reads, 1);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).onChanged,
        isNotNull,
      );
      expect(find.text('直接连接'), findsNothing);
      pending.completeError(StateError('read failed'));
      await tester.pump();
      await tester.pump();
      expect(find.text('暂时无法读取连接状态。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      'compact settings entries $platform',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          buildLocalizedTestApp(home: const SettingsPage()),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings-server-features-row')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('settings-network-row')),
          platform == TargetPlatform.macOS || platform == TargetPlatform.windows
              ? findsOneWidget
              : findsNothing,
        );
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
