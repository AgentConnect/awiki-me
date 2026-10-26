import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/desktop_network_preference.dart';
import 'package:awiki_me/src/presentation/settings/network_settings_page.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

class _Preferences implements AppKeyValueStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    if (fail) throw StateError('write failed');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  test(
    'defaults on, persists app-local selection, and restores before applying',
    () async {
      final store = _Preferences();
      final applied = <bool>[];
      final preference = DesktopNetworkPreference(
        preferences: () async => store,
        apply: (value) async => applied.add(value),
      );
      await preference.initialize();
      expect(preference.enabled, isTrue);
      expect(applied, [true]);
      await preference.setEnabled(false);
      final restarted = DesktopNetworkPreference(
        preferences: () async => store,
        apply: (value) async => applied.add(value),
      );
      await restarted.initialize();
      expect(restarted.enabled, isFalse);
      expect(applied, [true, false, false]);
      expect(store.values.keys, [DesktopNetworkPreference.key]);
    },
  );
  test(
    'failed persistence rolls transport back and serialized changes converge',
    () async {
      final store = _Preferences();
      final applied = <bool>[];
      final preference = DesktopNetworkPreference(
        preferences: () async => store,
        apply: (value) async => applied.add(value),
      );
      await preference.initialize();
      store.fail = true;
      await expectLater(preference.setEnabled(false), throwsStateError);
      expect(preference.enabled, isTrue);
      expect(applied, [true, false, true]);
      store.fail = false;
      await Future.wait([
        preference.setEnabled(false),
        preference.setEnabled(true),
      ]);
      expect(preference.enabled, isTrue);
      expect(store.values[DesktopNetworkPreference.key], 'true');
    },
  );
  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    for (final locale in ['zh', 'en']) {
      testWidgets(
        '$platform $locale one proxy switch and status remain usable',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          tester.view
            ..devicePixelRatio = 1
            ..physicalSize = const Size(600, 600);
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final preference = DesktopNetworkPreference(
            preferences: () async => _Preferences(),
            apply: (_) async {},
            readStatus: () async => core.AwikiNetworkStatus.proxyFallback,
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              home: const NetworkSettingsPage(),
              locale: Locale(locale),
              providerOverrides: [
                desktopNetworkPreferenceProvider.overrideWithValue(preference),
              ],
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CupertinoSwitch), findsOneWidget);
          expect(
            tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
            isTrue,
          );
          expect(
            find.text(
              locale == 'zh'
                  ? '代理不可用已回退'
                  : 'Proxy unavailable; using direct connection',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byType(CupertinoSwitch));
          await tester.pumpAndSettle();
          expect(
            tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
            isFalse,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
