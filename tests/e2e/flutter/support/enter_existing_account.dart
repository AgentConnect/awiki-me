import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fill the fixed authentication form for an existing account. The caller's
/// OTP request performs the authoritative registration-status check.
Future<void> enterExistingAccount(
  WidgetTester tester,
  String handle, {
  Finder? scope,
}) async {
  Finder control(String identifier) {
    final finder = find.bySemanticsIdentifier(identifier);
    return scope == null
        ? finder
        : find.descendant(of: scope, matching: finder);
  }

  final field = find.descendant(
    of: control('e2e-handle-input'),
    matching: find.byType(CupertinoTextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, handle);
  await tester.pump();
  expect(control('e2e-send-otp-button'), findsOneWidget);
  expect(control('e2e-phone-input'), findsOneWidget);
  expect(control('e2e-invite-input'), findsNothing);
}
