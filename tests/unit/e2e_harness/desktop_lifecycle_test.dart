import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/desktop_lifecycle.dart';

void main() {
  test(
    'background work runs while hidden and resumes before UI pumping',
    () async {
      var state = AppLifecycleState.resumed;
      final transitions = <AppLifecycleState>[];
      final value = await runInHiddenDesktopLifecycle(
        transition: (next) {
          state = next;
          transitions.add(next);
        },
        action: () async {
          expect(state, AppLifecycleState.hidden);
          return 'background message delivered';
        },
      );
      expect(value, 'background message delivered');
      expect(state, AppLifecycleState.resumed);
      expect(transitions, [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
    },
  );

  test(
    'background failure restores the legal lifecycle and retains the error',
    () async {
      final transitions = <AppLifecycleState>[];
      final failure = StateError('background send failed');
      await expectLater(
        runInHiddenDesktopLifecycle<void>(
          transition: transitions.add,
          action: () async => throw failure,
        ),
        throwsA(same(failure)),
      );
      expect(transitions.sublist(2), [
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
    },
  );
}
