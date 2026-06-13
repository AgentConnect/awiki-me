import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
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

  testWidgets('AwikiMeApp starts authenticated shell and switches tabs', (
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
    expect(find.text('最近会话'), findsOneWidget);
    expect(find.text('还没有会话'), findsOneWidget);
    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();

    expect(find.text('群组'), findsOneWidget);
  });
}
