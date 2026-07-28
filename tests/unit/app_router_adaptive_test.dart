import 'dart:async';

import 'package:awiki_me/src/app/app_router.dart';
import 'package:awiki_me/src/presentation/shared/app_dialog.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show DialogRoute;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact dialogs use a bottom Cupertino popup route', (
    tester,
  ) async {
    await _setViewSize(tester, const Size(390, 844));
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(_TestApp(observer: observer));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(observer.lastRoute, isA<CupertinoModalPopupRoute<void>>());
    final contentRect = tester.getRect(
      find.byKey(const Key('adaptive-dialog-content')),
    );
    expect(contentRect.bottom, greaterThan(790));
    expect(contentRect.center.dy, greaterThan(700));
    expect(
      find.byKey(const Key('compact-bottom-sheet-grab-handle')),
      findsOneWidget,
    );
  });

  testWidgets('compact action sheet dismisses from the modal barrier', (
    tester,
  ) async {
    await _setViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(const _ActionSheetTestApp());
    await tester.tap(find.text('Open actions'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-action-sheet')), findsOneWidget);
    expect(find.text('Command'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-action-sheet')), findsNothing);
  });

  testWidgets('compact bottom sheet moves above the software keyboard', (
    tester,
  ) async {
    await _setViewSize(tester, const Size(390, 844));
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      _TestApp(observer: _RecordingNavigatorObserver(), avoidViewInsets: true),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    final contentRect = tester.getRect(
      find.byKey(const Key('adaptive-dialog-content')),
    );
    expect(contentRect.bottom, lessThanOrEqualTo(844 - 280));
  });

  testWidgets('expanded dialogs use a centered desktop DialogRoute', (
    tester,
  ) async {
    await _setViewSize(tester, const Size(1000, 700));
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(_TestApp(observer: observer));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(observer.lastRoute, isA<DialogRoute<void>>());
    final contentRect = tester.getRect(
      find.byKey(const Key('adaptive-dialog-content')),
    );
    expect(contentRect.center.dx, closeTo(500, 1));
    expect(contentRect.center.dy, closeTo(350, 1));
  });
}

Future<void> _setViewSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.observer, this.avoidViewInsets = false});

  final NavigatorObserver observer;
  final bool avoidViewInsets;

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      navigatorObservers: <NavigatorObserver>[observer],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      home: Builder(
        builder: (context) {
          return CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                onPressed: () {
                  unawaited(
                    AppNavigator.showDialog<void>(
                      context,
                      (_) => AppDialogScaffold(
                        maxWidth: 320,
                        avoidViewInsets: avoidViewInsets,
                        child: const SizedBox(
                          key: Key('adaptive-dialog-content'),
                          width: 280,
                          height: 120,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionSheetTestApp extends StatelessWidget {
  const _ActionSheetTestApp();

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoPageScaffold(
          child: Center(
            child: CupertinoButton(
              onPressed: () {
                unawaited(
                  AppNavigator.showSheet<void>(
                    context,
                    (_) => const AppDropMenu(
                      title: 'Actions',
                      items: <AppDropMenuItem>[
                        AppDropMenuItem(label: 'Command'),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('Open actions'),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastRoute = route;
    super.didPush(route, previousRoute);
  }
}
