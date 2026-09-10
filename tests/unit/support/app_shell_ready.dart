import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_update_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Advance only until the startup gates and the intended surface are ready.
/// Avoid pumpAndSettle: connection/recovery indicators may animate continuously.
Future<void> pumpUntilAppShellReady(
  WidgetTester tester, {
  required bool loggedIn,
}) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    final shell = find.byType(AppShell);
    if (shell.evaluate().length != 1) continue;
    final container = ProviderScope.containerOf(tester.element(shell));
    final surface = loggedIn
        ? find.byKey(const Key('app-shell-page-background'))
        : find.byType(OnboardingPage);
    if (container.read(appUpdateProvider).localStateLoaded &&
        container.read(appRuntimeProvider).isInitialized &&
        container.read(sessionProvider).isLoggedIn == loggedIn &&
        surface.evaluate().length == 1) {
      return;
    }
  }
  fail(
    'App startup did not reach the expected '
    '${loggedIn ? 'authenticated' : 'onboarding'} surface within 500 ms.',
  );
}
