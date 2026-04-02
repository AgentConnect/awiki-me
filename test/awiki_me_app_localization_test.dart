import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_locale.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('AwikiMeApp localization', () {
    late AppBootstrap bootstrap;

    setUp(() {
      bootstrap = AppBootstrap(
        gateway: FakeAwikiGateway(),
        realtimeGateway: FakeRealtimeGateway(),
        notificationFacade: FakeNotificationFacade(),
        e2eeFacade: FakeE2eeFacade(),
        localePreferenceService: FakeLocalePreferenceService(),
      );
    });

    testWidgets('uses English when system locale is English', (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('en'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pump();

      expect(find.text('Log in'), findsWidgets);
      expect(find.text('Import identity credential'), findsOneWidget);
    });

    testWidgets('falls back to Chinese for unsupported locales',
        (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('fr'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pump();

      expect(find.text('登录'), findsWidgets);
      expect(find.text('导入身份凭证'), findsOneWidget);
    });

    testWidgets('uses explicit locale override from settings provider',
        (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('zh'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => AppLocaleMode.english),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Log in'), findsWidgets);
      expect(find.text('Import identity credential'), findsOneWidget);
    });
  });
}
