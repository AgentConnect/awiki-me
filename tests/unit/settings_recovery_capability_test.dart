import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  const session = SessionIdentity(
    did: 'did:wba:fixture.invalid:user:recovery',
    credentialName: 'recovery',
    displayName: 'Recovery fixture',
    localIdentityId: 'recovery-owner',
    handle: 'recovery.fixture.invalid',
  );
  const layouts = [
    (name: 'compact', size: Size(440, 1000), embedded: false),
    (name: 'standalone', size: Size(900, 1000), embedded: false),
    (name: 'desktop', size: Size(1200, 900), embedded: true),
  ];

  for (final layout in layouts) {
    for (final outcome in ['supported', 'unsupported', 'unavailable']) {
      testWidgets(
        'settings recovery is capability-gated on ${layout.name}: $outcome',
        (tester) async {
          tester.view.physicalSize = layout.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final capabilities = Completer<IdentityMethodCapabilities>();
          await tester.pumpWidget(
            buildLocalizedTestApp(
              home: SettingsPage(embedded: layout.embedded),
              session: session,
              providerOverrides: [
                identityMethodCapabilitiesProvider(
                  session.did,
                ).overrideWith((ref) => capabilities.future),
              ],
            ),
          );
          final recovery = find.byKey(
            const Key('settings-recover-handle-did-row'),
          );
          expect(
            recovery,
            findsNothing,
            reason: 'Unknown capability must not expose recovery.',
          );

          if (outcome == 'unavailable') {
            capabilities.completeError(
              StateError('fixture capability unavailable'),
            );
          } else {
            capabilities.complete(
              outcome == 'supported'
                  ? wbaMethodCapabilities
                  : webMethodCapabilities,
            );
          }
          await tester.pumpAndSettle();
          expect(
            recovery,
            outcome == 'supported' ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );
    }
  }
}
