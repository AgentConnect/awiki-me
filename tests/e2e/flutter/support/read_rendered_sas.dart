import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the digits actually rendered inside the unique SAS surface.
/// Failure messages deliberately exclude the verification code.
String readRenderedSas(WidgetTester tester, Finder surface) {
  if (surface.evaluate().length != 1) {
    fail('Expected exactly one rendered SAS surface.');
  }
  final labels = tester.widgetList<Text>(
    find.descendant(of: surface, matching: find.byType(Text)),
  );
  final digits = labels.map((label) => label.data ?? '').join();
  if (!RegExp(r'^[0-9]{6}$').hasMatch(digits)) {
    fail('The rendered SAS must contain exactly six digits.');
  }
  return digits;
}
