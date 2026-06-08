import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('AppListTile 默认使用资源右箭头图标', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: SafeArea(
            child: AppListTile(
              title: 'Settings',
              subtitle: 'Open detail page',
              onTap: _noop,
            ),
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AwikiAssetIcon &&
            widget.assetName == 'assets/icons/icon_right.svg',
      ),
      findsOneWidget,
    );
  });

  testWidgets('AppListTile 点击空白区域也会触发 onTap', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: Center(
              child: SizedBox(
                width: 320,
                child: AppListTile(
                  title: 'Settings',
                  subtitle: 'Open detail page',
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final tileRect = tester.getRect(find.byType(AppListTile));
    await tester.tapAt(Offset(tileRect.right - 48, tileRect.center.dy));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('AppPressable 点击和键盘确认都会触发动作', (tester) async {
    var tapCount = 0;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: Center(
              child: AppPressable(
                autofocus: true,
                onTap: () => tapCount++,
                child: const SizedBox(width: 80, height: 44),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.tap(find.byType(AppPressable));
    await tester.pump();
    expect(tapCount, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tapCount, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tapCount, 3);
  });

  testWidgets('AppPressable 禁用时不会触发动作', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: Center(
              child: AppPressable(
                onTap: () => tapped = true,
                enabled: false,
                child: const SizedBox(width: 80, height: 44),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppPressable));
    await tester.pump();

    expect(tapped, isFalse);
  });

  testWidgets('AppIconButton 加载中不会触发动作', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: Center(
              child: AppIconButton(
                isLoading: true,
                onPressed: () => tapped = true,
                child: const Icon(CupertinoIcons.add),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(AppIconButton));
    await tester.pump();

    expect(tapped, isFalse);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });

  testWidgets('AppDropMenu 点击菜单项会触发动作', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: AppDropMenu(
              title: 'TITLE',
              items: <AppDropMenuItem>[
                AppDropMenuItem(
                  label: 'pick',
                  highlighted: true,
                  onTap: () => tapped = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('TITLE'), findsOneWidget);
    expect(find.text('pick'), findsOneWidget);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
  });
}

void _noop() {}
