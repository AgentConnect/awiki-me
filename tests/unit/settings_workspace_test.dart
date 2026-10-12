import 'package:awiki_me/src/app/app_appearance.dart';
import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/settings/display_settings_page.dart';
import 'package:awiki_me/src/presentation/settings/language_selection_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_workspace_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'devices/device_test_support.dart';
import 'test_support.dart';

void main() {
  const session = SessionIdentity(
    did: testDid,
    credentialName: 'alice',
    displayName: 'Alice',
    handle: 'alice.awiki.info',
    localIdentityId: 'identity-alice',
  );
  for (final (width, scale) in [(1280.0, 1.0), (960.0, 1.1)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'desktop settings stays split while switching details in $brightness at $width / $scale',
        (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final deviceCore = FakeDeviceManagementCore();
          final theme = AwikiMeTheme.forPlatform(
            TargetPlatform.macOS,
            brightness: brightness,
          );
          await tester.pumpWidget(
            Theme(
              data: theme.materialTheme,
              child: buildLocalizedTestApp(
                session: session,
                applyDisplayScale: true,
                providerOverrides: [
                  initialDisplayScaleProvider.overrideWithValue(scale),
                  deviceManagementCorePortProvider.overrideWithValue(
                    deviceCore,
                  ),
                ],
                home: const SettingsWorkspacePage(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final sidebar = find.byKey(const Key('mac-settings-list-pane'));
          final detail = find.byKey(const Key('settings-detail-pane'));
          final rootNavigator = Navigator.of(
            tester.element(find.byType(SettingsPage)),
          );
          void expectDetail(Finder content, String selectedKey) {
            expect(sidebar.hitTestable(), findsOneWidget);
            expect(content, findsOneWidget);
            expect(
              find.descendant(of: detail, matching: content),
              findsOneWidget,
            );
            expect(
              tester.getRect(content).left,
              greaterThanOrEqualTo(tester.getRect(sidebar).right),
            );
            expect(rootNavigator.canPop(), isFalse);
            final pressable = tester.widget<AppPressable>(
              find.descendant(
                of: find.byKey(Key(selectedKey)),
                matching: find.byType(AppPressable),
              ),
            );
            expect(pressable.selected, isTrue);
            expect(tester.takeException(), isNull);
          }

          expectDetail(
            find.byType(DisplaySettingsPage),
            'settings-display-row',
          );
          expect(
            find.byKey(const Key('display-settings-back-button')),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('settings-language-row')));
          await tester.pumpAndSettle();
          expectDetail(
            find.byType(LanguageSelectionPage),
            'settings-language-row',
          );
          expect(
            find.byKey(const Key('language-selection-back-button')),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('language-option-english')));
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
            tester.element(find.byType(SettingsPage)),
          );
          expect(container.read(appLocaleModeProvider), AppLocaleMode.english);
          await tester.tap(find.byKey(const Key('settings-display-row')));
          await tester.pumpAndSettle();
          expectDetail(
            find.byType(DisplaySettingsPage),
            'settings-display-row',
          );
          await tester.tap(find.byKey(const Key('appearance-dark')));
          await tester.pumpAndSettle();
          expect(container.read(appAppearanceProvider), AppAppearance.dark);
          await tester.tap(find.byKey(const Key('settings-devices-row')));
          await tester.pumpAndSettle();
          expectDetail(find.byType(DevicesPage), 'settings-devices-row');
          expect(find.byKey(const Key('devices-back-button')), findsNothing);
          expect(find.byKey(const Key('devices-refresh')), findsOneWidget);
          await tester.tap(find.byKey(const Key('devices-refresh')));
          await tester.pumpAndSettle();
          expectDetail(find.byType(DevicesPage), 'settings-devices-row');
          // The security flow remains on the right and retains its explicit back
          // action and owner selector, without requesting an OTP just by opening.
          await tester.tap(
            find.byKey(const Key('settings-recover-handle-did-row')),
          );
          await tester.pumpAndSettle();
          expectDetail(
            find.byType(HandleRecoveryPage),
            'settings-recover-handle-did-row',
          );
          final recovery = tester.widget<HandleRecoveryPage>(
            find.byType(HandleRecoveryPage),
          );
          expect(recovery.localIdentityId, session.localIdentityId);
          expect(recovery.autoRequestOtp, isFalse);
          await tester.tap(
            find.byKey(const Key('handle-recovery-back-button')),
          );
          await tester.pumpAndSettle();
          expectDetail(
            find.byType(DisplaySettingsPage),
            'settings-display-row',
          );
          expect(find.byType(HandleRecoveryPage), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}
