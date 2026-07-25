import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('expanded 语义尺寸小于 compact', () {
    final compact = AwikiResponsiveInfo.fromSize(const Size(390, 844));
    final expanded = AwikiResponsiveInfo.fromSize(const Size(1280, 800));

    expect(expanded.uiScale, lessThan(compact.uiScale));
    expect(expanded.controlHeight, lessThan(compact.controlHeight));
    expect(
      expanded.compactControlHeight,
      lessThan(compact.compactControlHeight),
    );
    expect(expanded.navBarHeight, lessThan(compact.navBarHeight));
    expect(expanded.avatarSizeMd, lessThan(compact.avatarSizeMd));
    expect(expanded.titleLg, lessThan(compact.titleLg));
    expect(expanded.bodyMd, lessThan(compact.bodyMd));
    expect(expanded.metaSm, lessThan(compact.metaSm));
  });

  test('compact 和 expanded 精确遵守宽高边界', () {
    expect(
      AwikiResponsiveInfo.fromSize(const Size(719, 600)).breakpoint,
      AwikiBreakpoint.compact,
    );
    expect(
      AwikiResponsiveInfo.fromSize(const Size(720, 599)).breakpoint,
      AwikiBreakpoint.compact,
    );
    expect(
      AwikiResponsiveInfo.fromSize(const Size(719, 599)).breakpoint,
      AwikiBreakpoint.compact,
    );
    expect(
      AwikiResponsiveInfo.fromSize(const Size(720, 600)).breakpoint,
      AwikiBreakpoint.expanded,
    );
  });

  test('width-only 兼容入口按足够高度处理', () {
    expect(AwikiResponsiveInfo.fromWidth(719).isCompact, isTrue);
    expect(AwikiResponsiveInfo.fromWidth(720).isExpanded, isTrue);
  });

  test('显示缩放会同步影响语义尺寸', () {
    final normal = AwikiResponsiveInfo.fromSize(const Size(390, 844));
    final larger = AwikiResponsiveInfo.fromSize(
      const Size(390, 844),
      displayScale: 1.12,
    );

    expect(larger.displayScale, 1.12);
    expect(larger.controlHeight, greaterThan(normal.controlHeight));
    expect(larger.avatarSizeMd, greaterThan(normal.avatarSizeMd));
    expect(larger.titleLg, greaterThan(normal.titleLg));
    expect(larger.bodyMd, greaterThan(normal.bodyMd));
    expect(larger.spacing(16), greaterThan(normal.spacing(16)));
    expect(larger.displayScaled(100), closeTo(112, 0.0001));
  });

  test('显示缩放范围会被限制', () {
    final small = AwikiResponsiveInfo.fromSize(
      const Size(390, 844),
      displayScale: 0.1,
    );
    final large = AwikiResponsiveInfo.fromSize(
      const Size(390, 844),
      displayScale: 2,
    );

    expect(small.displayScale, AwikiDisplayScale.min);
    expect(large.displayScale, AwikiDisplayScale.max);
  });

  test('expanded 布局语义在所有平台一致', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final responsive = AwikiResponsiveInfo.fromSize(const Size(1280, 800));

    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(responsive.isExpanded, isTrue, reason: '$platform');
      expect(responsive.supportsTwoPane, isTrue, reason: '$platform');
      expect(responsive.usesDesktopLayout, isTrue, reason: '$platform');
      expect(
        responsive.isMacDesktop,
        platform == TargetPlatform.macOS,
        reason: '$platform',
      );
    }
  });

  testWidgets('BuildContext 同时使用 MediaQuery 宽度和高度', (tester) async {
    AwikiResponsiveInfo? responsive;

    await tester.pumpWidget(
      CupertinoApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(900, 599)),
          child: Builder(
            builder: (context) {
              responsive = context.awikiResponsive;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(responsive?.size, const Size(900, 599));
    expect(responsive?.isCompact, isTrue);
  });

  testWidgets('AwikiPaneLayout 支持拖动调整左栏宽度', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            return CupertinoPageScaffold(
              backgroundColor: context.awikiTheme.background,
              child: const SizedBox.expand(
                child: AwikiPaneLayout(
                  listPane: ColoredBox(
                    key: Key('left-pane'),
                    color: Color(0xFFFFFFFF),
                  ),
                  detailPane: ColoredBox(color: Color(0xFFEEEEEE)),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const Key('left-pane'))).width;
    await tester.drag(
      find.byKey(const Key('awiki-pane-divider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byKey(const Key('left-pane'))).width;

    expect(after, greaterThan(before));
  });

  testWidgets('多个 AwikiPaneLayout 各自保存列表栏宽度', (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) {
            return CupertinoPageScaffold(
              backgroundColor: context.awikiTheme.background,
              child: const Column(
                children: <Widget>[
                  Expanded(
                    child: AwikiPaneLayout(
                      listPane: ColoredBox(
                        key: Key('first-left-pane'),
                        color: Color(0xFFFFFFFF),
                      ),
                      detailPane: ColoredBox(color: Color(0xFFEEEEEE)),
                    ),
                  ),
                  Expanded(
                    child: AwikiPaneLayout(
                      listPane: ColoredBox(
                        key: Key('second-left-pane'),
                        color: Color(0xFFFFFFFF),
                      ),
                      detailPane: ColoredBox(color: Color(0xFFEEEEEE)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstBefore = tester
        .getSize(find.byKey(const Key('first-left-pane')))
        .width;
    final secondBefore = tester
        .getSize(find.byKey(const Key('second-left-pane')))
        .width;
    await tester.drag(
      find.byKey(const Key('awiki-pane-divider')).first,
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('first-left-pane'))).width,
      greaterThan(firstBefore),
    );
    expect(
      tester.getSize(find.byKey(const Key('second-left-pane'))).width,
      secondBefore,
    );
  });
}
