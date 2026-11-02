import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/flutter/support/desktop_tap_target.dart';
import '../test_support.dart';

void main() {
  testWidgets('message selection taps its row while the bubble ignores input', (
    tester,
  ) async {
    var selections = 0;
    var bubbleTaps = 0;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Center(
          child: GestureDetector(
            key: const Key('selection-row'),
            behavior: HitTestBehavior.opaque,
            onTap: () => selections++,
            child: IgnorePointer(
              child: AppPressable(
                onTap: () => bubbleTaps++,
                child: const SizedBox(
                  width: 200,
                  height: 60,
                  child: Text('Message'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final target = desktopCliPeerTapTarget(
      find.byKey(const Key('selection-row')),
      description: 'select second message',
    );
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(selections, 1);
    expect(bubbleTaps, 0);
  });
  testWidgets('production buttons still target their single AppPressable', (
    tester,
  ) async {
    var confirmations = 0;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Center(
          child: AppPrimaryButton(
            key: const Key('confirm'),
            label: 'Confirm',
            onPressed: () => confirmations++,
          ),
        ),
      ),
    );
    final target = desktopCliPeerTapTarget(
      find.byKey(const Key('confirm')),
      description: 'confirm',
    );
    expect(tester.widget(target), isA<AppPressable>());
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(confirmations, 1);
  });
}
