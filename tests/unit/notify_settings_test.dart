import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/notify_settings.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'test_support.dart';

void main() {
  testWidgets(
    'Android Notify settings save and reopen locally without a server, and report write failure',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('ai.awiki.awikime/remote_push_events');
      final local = <String, Object?>{
        'enabled': true,
        'urgent_enabled': false,
        'mutes_ready': true,
      };
      final writes = <Map<Object?, Object?>>[];
      bool fail = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        switch (call.method) {
          case 'getTextNotifyPreferenceState':
            expect(call.arguments, startsWith('target_'));
            return local;
          case 'configureTextNotify':
            final args = call.arguments as Map;
            expect(args.keys.toSet(), {'target', 'enabled', 'urgent_enabled'});
            writes.add(args);
            if (fail) return false;
            local['enabled'] = args['enabled'];
            local['urgent_enabled'] = args['urgent_enabled'];
            return true;
          default:
            throw StateError(
              'Unexpected external or native call: ${call.method}',
            );
        }
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const SettingsPage(),
          session: const SessionIdentity(
            did: 'did:test:notify-settings',
            credentialName: 'notify-settings',
            displayName: 'Notify',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings-notify-row')));
      await tester.tap(find.byKey(const Key('settings-notify-row')));
      await tester.pumpAndSettle();
      expect(find.byType(NotifySettingsPage), findsOneWidget);
      expect(find.text('会话免打扰尚未同步，任务提醒已暂停。'), findsNothing);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch).last).value,
        false,
      );
      await tester.tap(find.byType(CupertinoSwitch).last);
      await tester.pumpAndSettle();
      expect(local['urgent_enabled'], true);
      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();
      expect(local['enabled'], false);
      expect(
        tester
            .widget<CupertinoSwitch>(find.byType(CupertinoSwitch).last)
            .onChanged,
        null,
      );
      Navigator.of(tester.element(find.byType(NotifySettings))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-notify-row')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CupertinoSwitch>(find.byType(CupertinoSwitch).first)
            .value,
        false,
      );
      fail = true;
      await tester.tap(find.byType(CupertinoSwitch).first);
      await tester.pumpAndSettle();
      expect(find.text('本机通知设置未保存，请重试。'), findsOneWidget);
      expect(local['enabled'], false);
      expect(writes.length, 3);
      local['mutes_ready'] = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('会话免打扰尚未同步，任务提醒已暂停。'), findsOneWidget);
      expect(find.text('同步设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
