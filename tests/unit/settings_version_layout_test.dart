import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_update_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      'embedded settings constrain long test version in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const version = '0.1.108-singapore.20261012.source-0123456789abcdef';
        final updates = FakeUpdateService()
          ..currentVersion = const AppVersion(version: version, buildNumber: 1);
        await tester.pumpWidget(
          buildLocalizedTestApp(
            locale: locale,
            updateService: updates,
            home: const Center(
              child: SizedBox(width: 280, child: SettingsPage(embedded: true)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await ProviderScope.containerOf(
          tester.element(find.byType(SettingsPage)),
        ).read(appUpdateProvider.notifier).initialize();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final row = find.byKey(const Key('settings-current-version-row'));
        final value = find.text(version);
        expect(value, findsOneWidget);
        expect(tester.getSize(value).width, greaterThan(0));
        expect(
          tester.getRect(value).right,
          lessThanOrEqualTo(tester.getRect(row).right),
        );
        expect(tester.widget<Text>(value).overflow, TextOverflow.ellipsis);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  }
}
