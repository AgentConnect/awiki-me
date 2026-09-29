import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/enter_existing_account.dart';

void main() {
  testWidgets(
    'waits for the onboarding Handle field after capability loading',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final handleController = TextEditingController();
      addTearDown(handleController.dispose);
      var ready = false;
      late StateSetter rebuild;

      await tester.pumpWidget(
        CupertinoApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CupertinoPageScaffold(
                child: SingleChildScrollView(
                  child: ready
                      ? Column(
                          children: [
                            Semantics(
                              identifier: 'e2e-phone-input',
                              child: const CupertinoTextField(),
                            ),
                            Semantics(
                              identifier: 'e2e-handle-input',
                              child: CupertinoTextField(
                                controller: handleController,
                              ),
                            ),
                            Semantics(
                              identifier: 'e2e-send-otp-button',
                              child: CupertinoButton(
                                onPressed: () {},
                                child: const Text('Send OTP'),
                              ),
                            ),
                          ],
                        )
                      : const Text('Loading server capabilities'),
                ),
              );
            },
          ),
        ),
      );
      expect(find.bySemanticsIdentifier('e2e-handle-input'), findsNothing);

      Timer(const Duration(milliseconds: 400), () {
        rebuild(() => ready = true);
      });
      await enterExistingAccount(tester, 'existing-handle');

      expect(handleController.text, 'existing-handle');
      expect(find.bySemanticsIdentifier('e2e-send-otp-button'), findsOneWidget);
      semantics.dispose();
    },
  );
}
