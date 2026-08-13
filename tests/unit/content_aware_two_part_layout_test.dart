import 'package:awiki_me/src/presentation/shared/content_aware_two_part_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps real content inline while both groups fit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        width: 320,
        child: AwikiContentAwareTwoPartLayout(
          gap: 16,
          overflowGap: 8,
          minimumPrimaryWidth: 72,
          primary: const SizedBox(key: Key('primary'), width: 180, height: 30),
          secondary: const SizedBox(
            key: Key('secondary'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final secondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(primary.center.dy, closeTo(secondary.center.dy, 0.1));
    expect(primary.width, closeTo(180, 0.1));
    expect(secondary.right, closeTo(320, 0.1));
  });

  testWidgets('shrinks primary before stacking whole groups', (tester) async {
    await tester.pumpWidget(
      _testApp(
        width: 230,
        child: AwikiContentAwareTwoPartLayout(
          gap: 16,
          overflowGap: 8,
          minimumPrimaryWidth: 72,
          primary: const SizedBox(key: Key('primary'), width: 180, height: 30),
          secondary: const SizedBox(
            key: Key('secondary'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final secondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(primary.width, closeTo(94, 0.1));
    expect(primary.center.dy, closeTo(secondary.center.dy, 0.1));
    expect(secondary.right, closeTo(230, 0.1));
  });

  testWidgets('stacks only after minimum inline width no longer fits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        width: 200,
        child: AwikiContentAwareTwoPartLayout(
          gap: 16,
          overflowGap: 8,
          minimumPrimaryWidth: 72,
          overflowSecondaryAlignment: AwikiTwoPartAlignment.end,
          primary: const SizedBox(key: Key('primary'), width: 180, height: 30),
          secondary: const SizedBox(
            key: Key('secondary'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final secondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(secondary.top, closeTo(primary.bottom + 8, 0.1));
    expect(secondary.right, closeTo(200, 0.1));
  });

  testWidgets('respects text direction for inline and overflow alignment', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        width: 200,
        textDirection: TextDirection.rtl,
        child: AwikiContentAwareTwoPartLayout(
          gap: 16,
          overflowGap: 8,
          minimumPrimaryWidth: 72,
          overflowSecondaryAlignment: AwikiTwoPartAlignment.end,
          primary: const SizedBox(key: Key('primary'), width: 180, height: 30),
          secondary: const SizedBox(
            key: Key('secondary'),
            width: 120,
            height: 40,
          ),
        ),
      ),
    );

    final primary = tester.getRect(find.byKey(const Key('primary')));
    final secondary = tester.getRect(find.byKey(const Key('secondary')));
    expect(primary.right, closeTo(200, 0.1));
    expect(secondary.left, closeTo(0, 0.1));
  });
}

Widget _testApp({
  required double width,
  required Widget child,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return CupertinoApp(
    home: Directionality(
      textDirection: textDirection,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}
