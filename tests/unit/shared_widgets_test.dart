import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('AppPressableTile 可即时切换选中底色并保留交互动画', (tester) async {
    const normalColor = Color(0xFFF3F4F6);
    const selectedColor = Color(0xFFDCE7FF);
    const hoverColor = Color(0xFFFFFFFF);
    const pressedColor = Color(0xFFE8E7E4);
    const selectedShadow = <BoxShadow>[
      BoxShadow(color: Color(0x12000000), blurRadius: 10),
    ];
    const hoverShadow = <BoxShadow>[
      BoxShadow(color: Color(0x0C000000), blurRadius: 8),
    ];
    final selectedIndex = ValueNotifier<int>(0);
    addTearDown(selectedIndex.dispose);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: SafeArea(
            child: ValueListenableBuilder<int>(
              valueListenable: selectedIndex,
              builder: (context, value, child) {
                return Column(
                  children: List<Widget>.generate(3, (index) {
                    return AppPressableTile(
                      key: Key('selection-tile-$index'),
                      selected: value == index,
                      animateSelection: false,
                      backgroundColor: normalColor,
                      selectedBackgroundColor: selectedColor,
                      hoverColor: value == index
                          ? CupertinoColors.transparent
                          : hoverColor,
                      pressedColor: pressedColor,
                      selectedBoxShadow: selectedShadow,
                      hoverBoxShadow: value == index
                          ? const <BoxShadow>[]
                          : hoverShadow,
                      duration: AwikiMeMotion.instant,
                      interactionExitDuration: Duration.zero,
                      onTap: () => selectedIndex.value = index,
                      child: const SizedBox(width: 160, height: 44),
                    );
                  }),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Color tileBackground(int index) {
      final container = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byKey(Key('selection-tile-$index')),
              matching: find.byType(Container),
            ),
          )
          .singleWhere((widget) {
            final decoration = widget.decoration;
            return decoration is BoxDecoration &&
                (decoration.color == normalColor ||
                    decoration.color == selectedColor);
          });
      return (container.decoration! as BoxDecoration).color!;
    }

    expect(tileBackground(0), selectedColor);
    expect(tileBackground(1), normalColor);
    expect(tileBackground(2), normalColor);
    final selectedContainer = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byKey(const Key('selection-tile-0')),
            matching: find.byType(Container),
          ),
        )
        .singleWhere((widget) {
          final decoration = widget.decoration;
          return decoration is BoxDecoration &&
              decoration.color == selectedColor;
        });
    expect(
      (selectedContainer.decoration! as BoxDecoration).boxShadow,
      selectedShadow,
    );

    Finder interactionLayer(int index) => find.descendant(
      of: find.byKey(Key('selection-tile-$index')),
      matching: find.byType(AnimatedOpacity),
    );

    BoxDecoration interactionDecoration(int index) {
      final decoration = find.descendant(
        of: interactionLayer(index),
        matching: find.byType(DecoratedBox),
      );
      return tester.widget<DecoratedBox>(decoration).decoration
          as BoxDecoration;
    }

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    final secondTile = find.byKey(const Key('selection-tile-1'));
    await mouse.moveTo(tester.getCenter(secondTile));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    final hoverLayer = interactionLayer(1);
    final hoverOpacity = tester.renderObject<RenderAnimatedOpacity>(hoverLayer);
    expect(hoverOpacity.opacity.value, greaterThan(0));
    expect(hoverOpacity.opacity.value, lessThan(1));
    expect(interactionDecoration(1).color, hoverColor);
    expect(interactionDecoration(1).boxShadow, hoverShadow);

    await tester.pumpAndSettle();
    final hoverDecoration = interactionDecoration(1);
    expect(hoverDecoration.color, hoverColor);
    expect(hoverDecoration.boxShadow, hoverShadow);
    expect(tester.getRect(hoverLayer), tester.getRect(secondTile));

    final thirdTile = find.byKey(const Key('selection-tile-2'));
    await mouse.moveTo(tester.getCenter(thirdTile));
    await tester.pump();

    expect(
      tester.widget<AnimatedOpacity>(interactionLayer(1)).duration,
      Duration.zero,
    );
    expect(interactionDecoration(1).color, CupertinoColors.transparent);
    expect(interactionDecoration(1).boxShadow, isNull);
    expect(
      tester.widget<AnimatedOpacity>(interactionLayer(2)).duration,
      AwikiMeMotion.instant,
    );
    expect(interactionDecoration(2).color, hoverColor);
    expect(interactionDecoration(2).boxShadow, hoverShadow);

    await tester.tap(thirdTile);
    await tester.pump();

    expect(selectedIndex.value, 2);
    expect(tileBackground(0), normalColor);
    expect(tileBackground(1), normalColor);
    expect(tileBackground(2), selectedColor);
    expect(
      tester.widget<AnimatedOpacity>(interactionLayer(2)).duration,
      Duration.zero,
    );
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

  testWidgets('AvatarBadge loads only safe HTTPS avatar URIs', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: SafeArea(
            child: Column(
              children: <Widget>[
                AvatarBadge(
                  seed: 'Alice',
                  avatarUri: 'https://cdn.example/alice.png',
                ),
                AvatarBadge(
                  seed: 'Bob',
                  avatarUri: 'http://cdn.example/bob.png',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('AvatarBadge 使用生成文字、确定性颜色及可选身份 ID', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: SafeArea(
            child: Row(
              children: <Widget>[
                AvatarBadge(
                  key: Key('avatar-alice'),
                  seed: 'Alice Chen',
                  userId: 'did:test:alice',
                ),
                AvatarBadge(
                  key: Key('avatar-jin'),
                  seed: 'different-seed',
                  labelOverride: '锦',
                  userId: 'did:test:alice',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Color? generatedColor;
    for (final avatarKey in const <Key>[
      Key('avatar-alice'),
      Key('avatar-jin'),
    ]) {
      final avatar = find.byKey(avatarKey);
      final container = tester.widget<Container>(
        find.descendant(of: avatar, matching: find.byType(Container)),
      );
      final label = tester.widget<Text>(
        find.descendant(of: avatar, matching: find.byType(Text)),
      );

      final color = (container.decoration as BoxDecoration).color;
      generatedColor ??= color;
      expect(color, generatedColor);
      expect(label.style?.color, AwikiMePalette.avatarForeground);
    }
    expect(find.text('AC'), findsOneWidget);
    expect(find.text('锦'), findsOneWidget);
  });

  testWidgets('AvatarBadge 为两字中文头像使用标准字号', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: Center(child: AvatarBadge(seed: '欧阳娜娜', size: 48)),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('娜娜'));
    expect(label.style?.fontSize, closeTo(48 / 3.1, 0.01));
    expect(label.style?.color, AwikiMePalette.avatarForeground);
  });

  testWidgets('AvatarBadge 为智能体后缀保留三字并使用紧凑字号', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: Center(child: AvatarBadge(seed: '通知智能体', size: 48)),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('智能体'));
    expect(label.style?.fontSize, 12);
    expect(label.style?.color, AwikiMePalette.avatarForeground);
  });
}

void _noop() {}
