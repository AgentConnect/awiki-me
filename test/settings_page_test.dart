import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('设置页展示导出身份凭证并触发导出动作', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.text('导出身份凭证'), findsOneWidget);

    await tester.tap(find.text('导出身份凭证'));
    await tester.pump();

    expect(gateway.exportCalls, 1);
  });

  testWidgets('设置页展示语言设置并支持切换选项', (tester) async {
    final localePreferenceService = FakeLocalePreferenceService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        localeMode: AppLocaleMode.system,
        localePreferenceService: localePreferenceService,
      ),
    );

    expect(find.text('语言'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('取消'), findsNothing);

    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
    expect(localePreferenceService.saveCalls, 1);
    expect(
      await localePreferenceService.loadMode(),
      AppLocaleMode.english,
    );
  });
}
