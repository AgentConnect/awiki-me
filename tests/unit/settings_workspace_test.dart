import 'package:awiki_me/src/app/app_appearance.dart';
import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/presentation/devices/identity_services_page.dart';
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
import 'package:flutter/material.dart' show Theme, Slider;
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
  testWidgets(
    'embedded identity services stays in the detail pane without window chrome',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final core = FakeDeviceManagementCore()
        ..registry = const DeviceRegistrySnapshot(
          did: testDid,
          methodCapabilities: webMethodCapabilities,
          devices: [
            DeviceSummary(
              protocolDeviceId: 'admin',
              signingKeyId: 'sign',
              e2eeKeyId: 'e2ee',
              status: DeviceStatus.active,
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
          ],
        );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          session: session,
          home: const SettingsWorkspacePage(),
          providerOverrides: [
            deviceManagementCorePortProvider.overrideWithValue(core),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-devices-row')));
      await tester.pumpAndSettle();
      final sidebar = find.byKey(const Key('mac-settings-list-pane'));
      final root = Navigator.of(tester.element(find.byType(SettingsPage)));
      final top = MediaQuery.paddingOf(
        tester.element(find.byType(DevicesPage)),
      ).top;
      await tester.tap(find.byKey(const Key('identity-services-open')));
      await tester.pumpAndSettle();
      final services = find.byType(IdentityServicesPage);
      expect(services, findsOneWidget);
      expect(root.canPop(), isFalse);
      expect(
        tester.getRect(services).left,
        greaterThanOrEqualTo(tester.getRect(sidebar).right),
      );
      expect(MediaQuery.paddingOf(tester.element(services)).top, top);
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(DevicesPage), findsOneWidget);
      expect(sidebar.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
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
          // Desktop controls use compact geometry while retaining real scale
          // selection and the user's text scaling, rather than a transformed UI.
          expect(
            tester
                .getSize(find.byKey(const Key('appearance-segmented-control')))
                .height,
            lessThanOrEqualTo(36),
          );
          expect(
            tester
                .getSize(find.byKey(const Key('display-scale-reset-row')))
                .height,
            lessThanOrEqualTo(44),
          );
          final slider = find.byKey(const Key('display-scale-slider'));
          expect(tester.widget(slider), isA<Slider>());
          final sliderRect = tester.getRect(slider);
          await tester.tapAt(
            Offset(sliderRect.right - 24, sliderRect.center.dy),
          );
          await tester.pumpAndSettle();
          final settingsContainer = ProviderScope.containerOf(
            tester.element(find.byType(SettingsPage)),
          );
          expect(settingsContainer.read(displayScaleProvider), 1.3);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('display-scale-reset-row')));
          await tester.pumpAndSettle();
          expect(settingsContainer.read(displayScaleProvider), 1.0);
          settingsContainer.read(displayScaleProvider.notifier).setScale(scale);
          await tester.pumpAndSettle();
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
          expect(
            tester
                .getSize(find.byKey(const Key('language-option-english')))
                .height,
            lessThanOrEqualTo(50),
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
          // Recovery uses the root navigator so pausing/replacing the session
          // cannot dispose its activation fence. Opening still sends no OTP.
          await tester.tap(
            find.byKey(const Key('settings-recover-handle-did-row')),
          );
          await tester.pumpAndSettle();
          expect(find.byType(HandleRecoveryPage), findsOneWidget);
          expect(rootNavigator.canPop(), isTrue);
          final recovery = tester.widget<HandleRecoveryPage>(
            find.byType(HandleRecoveryPage),
          );
          expect(recovery.localIdentityId, session.localIdentityId);
          expect(recovery.autoRequestOtp, isFalse);
          await tester.tap(
            find.byKey(const Key('handle-recovery-back-button')),
          );
          await tester.pumpAndSettle();
          expectDetail(find.byType(DevicesPage), 'settings-devices-row');
          expect(find.byType(HandleRecoveryPage), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }
  }
}
