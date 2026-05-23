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
      final gateway = FakeAwikiGateway();
      final realtimeGateway = FakeRealtimeGateway();
      bootstrap = AppBootstrap(
        accountGateway: gateway,
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        notificationFacade: FakeNotificationFacade(),
        e2eeFacade: FakeE2eeFacade(),
        localePreferenceService: FakeLocalePreferenceService(),
        updateService: FakeUpdateService(),
        appSessionService: FakeAppSessionService(gateway),
        onboardingService: FakeOnboardingService(gateway),
        onboardingSupportService: FakeOnboardingSupportService(gateway),
        messagingService: FakeMessagingService(gateway),
        conversationService: FakeConversationService(gateway),
        groupApplicationService: FakeGroupApplicationService(gateway),
        profileApplicationService: FakeProfileApplicationService(gateway),
        relationshipApplicationService: FakeRelationshipApplicationService(
          gateway,
        ),
        realtimeApplicationService: FakeRealtimeApplicationService(
          gateway: gateway,
          realtimeGateway: realtimeGateway,
        ),
      );
    });

    testWidgets('uses English when system locale is English', (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('en'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pump();

      expect(find.text('Switch identity'), findsWidgets);
      expect(find.text('Import identity credential'), findsOneWidget);
    });

    testWidgets('falls back to Chinese for unsupported locales', (
      tester,
    ) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('fr'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pump();

      expect(find.text('切换身份'), findsWidgets);
      expect(find.text('导入身份凭证'), findsOneWidget);
    });

    testWidgets('uses explicit locale override from settings provider', (
      tester,
    ) async {
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

      expect(find.text('Switch identity'), findsWidgets);
      expect(find.text('Import identity credential'), findsOneWidget);
    });

    testWidgets('tapping outside an input dismisses keyboard focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => AppLocaleMode.english),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Log in or register'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.pump();

      final focusNode = tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Log in or register'));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('tapping the focused input keeps keyboard focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => AppLocaleMode.english),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Log in or register'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.pump();

      final focusNode = tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });
  });
}
