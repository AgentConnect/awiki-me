import 'dart:async';

import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/tap_app_pair_control.dart';
import '../test_support.dart';

void main() {
  testWidgets('tap waits for a Cupertino action sheet to enter the viewport', (
    tester,
  ) async {
    var confirmations = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: Center(
              child: CupertinoButton(
                key: const Key('open-sheet'),
                onPressed: () => showCupertinoModalPopup<void>(
                  context: context,
                  builder: (_) => CupertinoActionSheet(
                    actions: [
                      CupertinoActionSheetAction(
                        key: const Key('confirm-sheet'),
                        onPressed: () => confirmations++,
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-sheet')));
    await tester.pump();
    expect(find.byKey(const Key('confirm-sheet')), findsOneWidget);
    expect(find.byKey(const Key('confirm-sheet')).hitTestable(), findsNothing);

    await tapAppPairProductControl(tester, 'confirm-sheet');

    expect(confirmations, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap waits for the production button to become enabled', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    addTearDown(ready.dispose);
    var confirmations = 0;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: ready,
          builder: (_, enabled, _) => Center(
            child: AppPrimaryButton(
              key: const Key('confirm-ready'),
              label: 'Confirm',
              onPressed: enabled ? () => confirmations++ : null,
            ),
          ),
        ),
      ),
    );
    final readiness = Timer(const Duration(milliseconds: 200), () {
      ready.value = true;
    });
    addTearDown(readiness.cancel);

    await tapAppPairProductControl(tester, 'confirm-ready');

    expect(confirmations, 1);
    expect(tester.takeException(), isNull);
  });
}
