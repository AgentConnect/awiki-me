// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/tenant_aware_awiki_me_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('bootstrap error app renders only redacted diagnostics', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTenantBootstrapErrorApp(StateError('native bridge mismatch')),
    );

    expect(find.text('AWikiMe failed to start.'), findsOneWidget);
    expect(find.textContaining('native bridge mismatch'), findsNothing);
    expect(find.text('Diagnostic code: bootstrap_failed'), findsOneWidget);
    expect(find.text('Copy diagnostics'), findsOneWidget);
    expect(find.text('Exit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('bootstrap diagnostic preserves only allowlisted stable codes', () {
    expect(
      tenantBootstrapDiagnosticCode(
        const core.AwikiImCoreException(
          code: 'local_state_upgrade_failed',
          message: '/Users/alice/private/im.sqlite',
        ),
      ),
      'local_state_upgrade_failed',
    );
    expect(
      tenantBootstrapDiagnosticCode(
        const core.AwikiImCoreException(
          code: '/Users/alice/private/im.sqlite',
          message: 'secret',
        ),
      ),
      'bootstrap_failed',
    );
  });

  testWidgets('bootstrap error app exposes retry when provided', (
    tester,
  ) async {
    var retryCount = 0;
    await tester.pumpWidget(
      buildTenantBootstrapErrorApp(
        StateError('upgrade failed'),
        onRetry: () => retryCount += 1,
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retryCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upgrade progress is visible only during upgrade stages', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTenantBootstrapLoadingApp(AppBootstrapProgress.preparing),
    );
    expect(find.text('AWiki'), findsOneWidget);
    expect(find.textContaining('Upgrading local data'), findsNothing);

    await tester.pumpWidget(
      buildTenantBootstrapLoadingApp(AppBootstrapProgress.upgradingLocalState),
    );
    expect(find.text('Upgrading local data securely…'), findsOneWidget);

    await tester.pumpWidget(
      buildTenantBootstrapLoadingApp(
        AppBootstrapProgress.migratingLocalOverlays,
      ),
    );
    expect(find.text('Finishing local data upgrade…'), findsOneWidget);
  });

  test(
    'tenant runtime opens only after previous dispose barrier completes',
    () async {
      final events = <String>[];
      final disposed = Completer<void>();
      final transition = openTenantRuntimeAfterDispose<String>(
        previous: 'old-scope',
        disposePrevious: (previous) async {
          events.add('dispose:$previous:start');
          await disposed.future;
          events.add('dispose:$previous:done');
        },
        openNext: () async {
          events.add('open:new-scope');
          return 'new-scope';
        },
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['dispose:old-scope:start']);
      disposed.complete();

      expect(await transition, 'new-scope');
      expect(events, <String>[
        'dispose:old-scope:start',
        'dispose:old-scope:done',
        'open:new-scope',
      ]);
    },
  );

  test(
    'initial runtime opens directly when there is no previous scope',
    () async {
      var disposeCalled = false;
      final result = await openTenantRuntimeAfterDispose<String>(
        previous: null,
        disposePrevious: (_) async => disposeCalled = true,
        openNext: () async => 'first-scope',
      );

      expect(result, 'first-scope');
      expect(disposeCalled, isFalse);
    },
  );
}
