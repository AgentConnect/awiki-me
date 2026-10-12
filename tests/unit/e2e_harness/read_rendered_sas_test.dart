import 'package:awiki_me/src/presentation/shared/widgets/awiki_glass_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/read_rendered_sas.dart';

void main() {
  for (final key in ['device-approval-sas', 'device-join-sas']) {
    testWidgets('reads displayed digits from $key', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: Column(
            children: [
              const Text('Unrelated 999999'),
              KeyedSubtree(
                key: Key(key),
                child: const AwikiSasDigits(code: '482917'),
              ),
            ],
          ),
        ),
      );
      final surface = find.byKey(Key(key));
      // Reproduces the stale E2E cast against the actual product component.
      expect(() => tester.widget<Text>(surface), throwsA(isA<TypeError>()));
      expect(readRenderedSas(tester, surface), '482917');
    });
  }
  for (final code in ['48291', '4829170', '48291x']) {
    testWidgets('rejects malformed rendered digits ($code)', (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          home: KeyedSubtree(
            key: const Key('sas'),
            child: AwikiSasDigits(code: code),
          ),
        ),
      );
      expect(
        () => readRenderedSas(tester, find.byKey(const Key('sas'))),
        throwsA(isA<TestFailure>()),
      );
    });
  }
  testWidgets('rejects missing or ambiguous surfaces', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Column(
          children: [
            AwikiSasDigits(code: '482917'),
            AwikiSasDigits(code: '482917'),
          ],
        ),
      ),
    );
    for (final finder in [
      find.byKey(const Key('missing')),
      find.byType(AwikiSasDigits),
    ]) {
      expect(
        () => readRenderedSas(tester, finder),
        throwsA(isA<TestFailure>()),
      );
    }
  });
}
