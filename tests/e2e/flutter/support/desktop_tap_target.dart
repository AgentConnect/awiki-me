import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder desktopCliPeerTapTarget(Finder finder, {required String description}) {
  final widget = finder.evaluate().single.widget;
  final pressable = find.descendant(
    of: finder,
    matching: find.byType(AppPressable),
  );
  final count = pressable.evaluate().length;
  final wrapsPressable =
      widget is AppPrimaryButton ||
      widget is AppSecondaryButton ||
      widget is AppIconButton ||
      widget is AppPressableTile;
  if (wrapsPressable && count != 1) {
    fail(
      'Expected exactly one interactive target for $description, found $count.',
    );
  }
  // Selection rows own the gesture while their nested message ignores input.
  return wrapsPressable ? pressable : finder;
}
