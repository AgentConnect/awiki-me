import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../support/fake_app_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AwikiMeApp starts with fake bootstrap and shows onboarding', (
    tester,
  ) async {
    final harness = createFakeAwikiMeAppHarness();

    await tester.pumpWidget(
      AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('切换身份'), findsWidgets);
    expect(find.text('登录或注册'), findsWidgets);
    expect(harness.gateway.listLocalCredentialsCalls, greaterThanOrEqualTo(1));
    expect(harness.realtimeGateway.isConnected, isFalse);
  });

  testWidgets('AwikiMeApp starts authenticated shell', (
    tester,
  ) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'test-jwt',
    );
    final harness = createFakeAwikiMeAppHarness(session: session);

    await tester.pumpWidget(
      AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('AwikiMeApp authenticated smoke opens profile and settings', (
    tester,
  ) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'test-jwt',
    );
    final harness = createFakeAwikiMeAppHarness(session: session);

    await tester.pumpWidget(
      AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    );
    await _pumpSmokeFrame(tester);

    expect(find.byType(AppShell), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('我'));
    await _pumpSmokeFrame(tester);

    expect(find.text('Smoke test profile.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('消息'));
    await _pumpSmokeFrame(tester);
    await tester.tap(find.bySemanticsLabel('设置'));
    await _pumpSmokeFrame(tester);

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('导出身份凭证'), findsOneWidget);
  });
}

Future<void> _pumpSmokeFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
