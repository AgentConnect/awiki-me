import 'dart:async';

import 'package:awiki_me/src/app/app_router.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('macOS pushed navigation bar clears native window buttons', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(const _RouteTestApp());
      expect(tester.getCenter(find.text('Home')).dy, lessThan(52));

      await tester.tap(find.text('Open navigation page'));
      await tester.pumpAndSettle();

      final back = find.byType(CupertinoNavigationBarBackButton);
      expect(back, findsOneWidget);
      expect(
        tester.getTopLeft(back).dy,
        greaterThanOrEqualTo(AppNavigator.macWindowChromeTopInset),
      );
      expect(tester.getCenter(find.text('Child')).dy, greaterThan(52));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('macOS custom-header routes use the same safe area', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(const _RouteTestApp());
      await tester.tap(find.text('Open custom page'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.byKey(const Key('custom-header'))).dy,
        greaterThanOrEqualTo(AppNavigator.macWindowChromeTopInset),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('non-macOS routes keep their existing top layout', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(const _RouteTestApp());
      await tester.tap(find.text('Open custom page'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(const Key('custom-header'))).dy, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _RouteTestApp extends StatelessWidget {
  const _RouteTestApp();

  @override
  Widget build(BuildContext context) => CupertinoApp(
    home: CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Home')),
      child: Builder(
        builder: (context) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CupertinoButton(
                onPressed: () => unawaited(
                  AppNavigator.push<void>(
                    context,
                    (_) => const _NavigationPage(),
                  ),
                ),
                child: const Text('Open navigation page'),
              ),
              CupertinoButton(
                onPressed: () => unawaited(
                  AppNavigator.pushWithoutAnimation<void>(
                    context,
                    (_) => const _CustomHeaderPage(),
                  ),
                ),
                child: const Text('Open custom page'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NavigationPage extends StatelessWidget {
  const _NavigationPage();

  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text('Child')),
    child: SafeArea(child: SizedBox.shrink()),
  );
}

class _CustomHeaderPage extends StatelessWidget {
  const _CustomHeaderPage();

  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    child: SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(key: Key('custom-header'), width: 44, height: 44),
      ),
    ),
  );
}
