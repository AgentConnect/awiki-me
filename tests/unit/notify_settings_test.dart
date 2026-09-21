import 'package:awiki_me/src/application/ports/notify_preference_port.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/notify_settings.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

class _Preferences implements NotifyPreferencePort {
  NotifyPreference value = const NotifyPreference(
    enabled: true,
    urgentEnabled: false,
    version: 0,
  );
  bool fail = false;
  @override
  Future<NotifyPreference> load() async => value;
  @override
  Future<NotifyPreference> save(
    NotifyPreference previous, {
    required bool enabled,
    required bool urgentEnabled,
    List<String>? mutedPeerDids,
  }) async {
    if (fail) throw StateError('offline');
    expect(previous.version, value.version);
    return value = NotifyPreference(
      enabled: enabled,
      urgentEnabled: urgentEnabled,
      version: value.version + 1,
      mutedPeerDids: mutedPeerDids ?? previous.mutedPeerDids,
    );
  }
}

void main() {
  testWidgets(
    'compact Android settings opens Notify and disables locally before a failed save',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('ai.awiki.awikime/remote_push_events');
      final nativeCalls = <Map<Object?, Object?>>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'configureTextNotify')
          nativeCalls.add(call.arguments as Map);
        if (call.method == 'getTextNotifyPreferenceState')
          return {
            for (final k in ['enabled', 'urgent_enabled', 'version'])
              k: nativeCalls.last[k],
          };
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final preferences = _Preferences();
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const SettingsPage(),
          session: const SessionIdentity(
            did: 'did:test:notify-settings',
            credentialName: 'notify-settings',
            displayName: 'Notify',
          ),
          providerOverrides: [
            notifyPreferencePortProvider.overrideWithValue(preferences),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-notify-row')));
      await tester.tap(find.byKey(const Key('settings-notify-row')));
      await tester.pumpAndSettle();
      expect(find.byType(NotifySettingsPage), findsOneWidget);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).last).value,
        false,
      );
      await tester.tap(find.byType(CupertinoSwitch).last);
      await tester.pumpAndSettle();
      expect(preferences.value.urgentEnabled, true);
      expect(nativeCalls.last['explicit_save'], true);
      preferences.fail = true;
      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();
      expect(nativeCalls.last['enabled'], false);
      expect(nativeCalls.last['local_disable'], true);
      expect(find.text('设置未同步，本机已停止提醒。请重新加载后重试。'), findsOneWidget);
      expect(
        preferences.value.enabled,
        true,
      ); // failed server write is never reported as saved
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
