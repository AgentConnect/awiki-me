import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> until(WidgetTester tester, bool Function() predicate) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 300));
  }
  throw StateError('hosted_app_state_deadline');
}

Future<void> input(WidgetTester tester, String identifier, String value) async {
  final field = find.descendant(
    of: find.bySemanticsIdentifier(identifier),
    matching: find.byType(CupertinoTextField),
  );
  if (field.evaluate().length != 1) {
    throw StateError('hosted_app_field_missing');
  }
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}
