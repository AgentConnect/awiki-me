import 'dart:async';

import 'package:awiki_me/src/app/app_router.dart';
import 'package:awiki_me/src/application/screenshot_failure.dart';
import 'package:awiki_me/src/presentation/chat/screenshot_permission_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _diagnostics = ScreenshotAppDiagnostics(
  applicationName: 'AWikiMe (Development)',
  bundleIdentifier: 'ai.awiki.awikime.dev',
  applicationPath:
      '/Users/test/development/very-long-workspace-name/build/macos/Build/Products/Debug/AWikiMe.app',
  version: '0.1.28',
);

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    Locale locale = const Locale('zh'),
    ScreenshotAppDiagnostics? diagnostics = _diagnostics,
    Future<bool> Function()? openSettings,
    Future<void> Function(String)? copy,
  }) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: locale,
        home: CupertinoPageScaffold(
          child: Builder(
            builder: (context) => CupertinoButton(
              child: const Text('open'),
              onPressed: () {
                AppNavigator.showDialog<void>(
                  context,
                  (_) => ScreenshotPermissionDialog(
                    diagnostics: diagnostics,
                    openSettings: openSettings ?? () async => true,
                    copyDiagnostics: copy ?? (_) async {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
      '${locale.languageCode} narrow dialog keeps title and actions usable with details expanded',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await openDialog(tester, locale: locale);
        final title = find.text(
          locale.languageCode == 'zh'
              ? '截图需要屏幕录制权限'
              : 'Allow screenshots',
        );
        expect(
          tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
          isFalse,
        );
        await tester.tap(find.byKey(const Key('screenshot-recovery-toggle')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('screenshot-diagnostics-toggle')),
        );
        await tester.tap(
          find.byKey(const Key('screenshot-diagnostics-toggle')),
        );
        await tester.pumpAndSettle();
        final settings = find.byKey(const Key('screenshot-open-settings'));
        final position = tester.getRect(settings);
        await tester.ensureVisible(
          find.byKey(const Key('screenshot-copy-diagnostics')),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(settings), position);
        expect(settings.hitTestable(), findsOneWidget);
        expect(
          find.byKey(const Key('screenshot-not-now')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '${locale.languageCode} recovery shows the exact app and explicit-copy diagnostics',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        String? copied;
        var opens = 0;
        await openDialog(
          tester,
          locale: locale,
          copy: (value) async {
            copied = value;
          },
          openSettings: () async {
            opens++;
            return true;
          },
        );
        expect(copied, isNull);
        expect(opens, 0);
        expect(
          find.textContaining(_diagnostics.bundleIdentifier),
          findsNothing,
        );
        expect(find.textContaining(_diagnostics.applicationPath), findsNothing);
        expect(find.textContaining('Debug'), findsNothing);
        expect(
          find.byKey(const Key('screenshot-copy-diagnostics')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('screenshot-open-settings')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('screenshot-not-now')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('screenshot-recovery-toggle')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(_diagnostics.applicationPath),
          findsOneWidget,
        );
        expect(
          find.textContaining(_diagnostics.bundleIdentifier),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const Key('screenshot-diagnostics-toggle')),
        );
        await tester.tap(
          find.byKey(const Key('screenshot-diagnostics-toggle')),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(_diagnostics.bundleIdentifier),
          findsOneWidget,
        );
        expect(
          find.textContaining(_diagnostics.applicationPath),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('screenshot-copy-diagnostics')),
        );
        await tester.tap(find.byKey(const Key('screenshot-copy-diagnostics')));
        await tester.pumpAndSettle();
        expect(copied, contains('build_mode: Debug'));
        expect(
          copied,
          contains('application_path: ${_diagnostics.applicationPath}'),
        );
        expect(copied, isNot(contains('tenant')));
        await tester.tap(find.byKey(const Key('screenshot-open-settings')));
        await tester.pumpAndSettle();
        expect(opens, 1);
        expect(find.byType(ScreenshotPermissionDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(ScreenshotPermissionDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'narrow window scrolls, missing metadata and settings failure keep recovery usable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openDialog(
        tester,
        diagnostics: null,
        openSettings: () async => false,
        copy: (_) async => throw StateError('private clipboard error'),
      );
      expect(find.textContaining('无法读取当前应用信息'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('screenshot-open-settings')),
      );
      await tester.tap(find.byKey(const Key('screenshot-open-settings')));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法自动打开设置'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('screenshot-recovery-toggle')),
      );
      await tester.tap(find.byKey(const Key('screenshot-recovery-toggle')));
      await tester.pumpAndSettle();
      expect(find.textContaining('无法读取当前应用信息'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('screenshot-diagnostics-toggle')),
      );
      await tester.tap(find.byKey(const Key('screenshot-diagnostics-toggle')));
      await tester.pumpAndSettle();
      final settingsRect = tester.getRect(
        find.byKey(const Key('screenshot-open-settings')),
      );
      await tester.ensureVisible(
        find.byKey(const Key('screenshot-copy-diagnostics')),
      );
      await tester.tap(find.byKey(const Key('screenshot-copy-diagnostics')));
      await tester.pumpAndSettle();
      expect(find.text('复制失败，请重试。'), findsOneWidget);
      expect(find.textContaining('private clipboard error'), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('screenshot-open-settings'))),
        settingsRect,
      );
      expect(
        find.byKey(const Key('screenshot-open-settings')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('screenshot-not-now')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Not now closes without opening settings or copying information',
    (tester) async {
      var opens = 0;
      var copies = 0;
      await openDialog(
        tester,
        openSettings: () async {
          opens++;
          return true;
        },
        copy: (_) async {
          copies++;
        },
      );
      await tester.tap(find.byKey(const Key('screenshot-not-now')));
      await tester.pumpAndSettle();
      expect(find.byType(ScreenshotPermissionDialog), findsNothing);
      expect(opens, 0);
      expect(copies, 0);
    },
  );

  testWidgets(
    'recovery disclosure is keyboard operable and collapses technical details',
    (tester) async {
      await openDialog(tester);
      final label = find.text('已开启权限，仍无法截图？');
      Focus.of(tester.element(label)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.textContaining(_diagnostics.applicationPath), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('screenshot-diagnostics-toggle')),
      );
      await tester.tap(find.byKey(const Key('screenshot-diagnostics-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(_diagnostics.bundleIdentifier),
        findsOneWidget,
      );
      await tester.ensureVisible(label);
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(find.textContaining(_diagnostics.bundleIdentifier), findsNothing);
      expect(
        find.byKey(const Key('screenshot-copy-diagnostics')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending settings open is coalesced and completing after close is safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final opened = Completer<bool>();
      var calls = 0;
      await openDialog(
        tester,
        openSettings: () {
          calls++;
          return opened.future;
        },
      );
      final button = find.byKey(const Key('screenshot-open-settings'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      expect(calls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      opened.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
