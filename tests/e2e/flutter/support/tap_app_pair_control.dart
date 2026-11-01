import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits within one deadline, including route motion and an explicitly supplied
/// lazy scrollable. The caller can name the exact rendered control without
/// exposing its text in failure diagnostics.
Future<void> tapAppPairProductControl(
  WidgetTester tester,
  String key, {
  Duration timeout = const Duration(seconds: 60),
  Finder? control,
  Finder? scrollable,
}) async {
  final finder = control ?? find.byKey(Key(key));
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
    } else if (finder.evaluate().isEmpty &&
        scrollable != null &&
        scrollable.evaluate().length == 1) {
      await tester.drag(scrollable, const Offset(0, -300));
    }
    await tester.pump(const Duration(milliseconds: 100));
  } while (DateTime.now().isBefore(deadline));
  fail('App-pair product control unavailable: $key');
}
