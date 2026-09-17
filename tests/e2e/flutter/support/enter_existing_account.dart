import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// Follow the public existing-account entrance without depending on discovery.
/// Authentication and Join/Recovery assertions remain with the calling case.
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

  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (control('e2e-existing-account').evaluate().isEmpty &&
      DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(control('e2e-existing-account'), findsOneWidget);
  final field = find.descendant(
    of: control('e2e-handle-input'),
    matching: find.byType(CupertinoTextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, handle);
  await tester.pump();
  final action = control('e2e-existing-account');
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pump();
  expect(control('e2e-invite-input'), findsNothing);
}
