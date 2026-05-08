import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large 语义尺寸小于 phone', () {
    final phone = AwikiResponsiveInfo.fromWidth(390);
    final large = AwikiResponsiveInfo.fromWidth(1280);

    expect(large.uiScale, lessThan(phone.uiScale));
    expect(large.controlHeight, lessThan(phone.controlHeight));
    expect(large.compactControlHeight, lessThan(phone.compactControlHeight));
    expect(large.navBarHeight, lessThan(phone.navBarHeight));
    expect(large.avatarSizeMd, lessThan(phone.avatarSizeMd));
    expect(large.titleLg, lessThan(phone.titleLg));
    expect(large.bodyMd, lessThan(phone.bodyMd));
    expect(large.metaSm, lessThan(phone.metaSm));
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
                  detailPane: ColoredBox(
                    color: Color(0xFFEEEEEE),
                  ),
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
        find.byKey(const Key('awiki-pane-divider')), const Offset(80, 0));
    await tester.pumpAndSettle();
    final after = tester.getSize(find.byKey(const Key('left-pane'))).width;

    expect(after, greaterThan(before));
  });
}
