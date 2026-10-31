import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits for the visible control within one deadline, including route motion.
Future<void> tapAppPairProductControl(
  WidgetTester tester,
  String key, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final finder = find.byKey(Key(key));
  final deadline = DateTime.now().add(timeout);
  do {
    if (finder.evaluate().length == 1) {
      final widget = tester.widget(finder);
      final enabled =
          (widget is! AppSecondaryButton || widget.onPressed != null) &&
          (widget is! AppPrimaryButton || widget.onPressed != null);
      if (enabled) {
        await tester.ensureVisible(finder);
        await tester.pump();
        final visible = finder.hitTestable();
        if (visible.evaluate().length == 1) {
          await tester.tap(visible);
          await tester.pump();
          return;
        }
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  } while (DateTime.now().isBefore(deadline));
  fail('App-pair product control unavailable: $key');
}
