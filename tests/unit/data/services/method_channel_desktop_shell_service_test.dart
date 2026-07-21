import 'package:awiki_me/src/application/desktop_shell_service.dart';
import 'package:awiki_me/src/data/services/method_channel_desktop_shell_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.awiki/desktop-shell');
  late List<MethodCall> nativeCalls;

  setUp(() {
    nativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          if (call.method == 'getStorageRoots') {
            return <String, Object?>{
              'support': r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\support',
              'cache': r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\cache',
              'temp': r'C:\Users\tester\AppData\Local\Temp\AWikiMe',
            };
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialize registers the handler and announces ready once', () async {
    final service = MethodChannelDesktopShellService(channel: channel);
    addTearDown(service.dispose);

    await service.initialize();
    await service.initialize();

    expect(nativeCalls.map((call) => call.method), <String>['ready']);
  });

  test(
    'parses native events strictly and exposes them on the stream',
    () async {
      final service = MethodChannelDesktopShellService(channel: channel);
      addTearDown(service.dispose);
      final events = <DesktopShellEvent>[];
      final subscription = service.events.listen(events.add);
      addTearDown(subscription.cancel);
      await service.initialize();

      await service.handleMethodCall(
        const MethodCall('shellEvent', <String, Object?>{'type': 'activate'}),
      );

      expect(events.single.type, DesktopShellEventType.activate);
      await expectLater(
        service.handleMethodCall(
          const MethodCall('shellEvent', <String, Object?>{
            'type': 'activate',
            'unexpected': true,
          }),
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'desktop_shell_event_invalid',
          ),
        ),
      );
    },
  );

  test(
    'reads Known Folder roots and sends normalized shell commands',
    () async {
      final service = MethodChannelDesktopShellService(channel: channel);
      addTearDown(service.dispose);
      await service.initialize();

      final roots = await service.getStorageRoots();
      await service.showWindow();
      await service.hideWindow();
      await service.setUnreadCount(-4);
      await service.completeExit();

      expect(
        roots.support,
        r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\support',
      );
      expect(roots.cache, endsWith(r'AWiki\AWikiMe\cache'));
      expect(roots.temp, endsWith(r'Temp\AWikiMe'));
      expect(nativeCalls.map((call) => call.method), <String>[
        'ready',
        'getStorageRoots',
        'showWindow',
        'hideWindow',
        'setUnreadCount',
        'completeExit',
      ]);
      expect(nativeCalls[4].arguments, <String, Object?>{'count': 0});
    },
  );

  test('rejects incomplete storage roots', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStorageRoots') {
            return <String, Object?>{'support': r'C:\support'};
          }
          return null;
        });
    final service = MethodChannelDesktopShellService(channel: channel);
    addTearDown(service.dispose);

    await expectLater(
      service.getStorageRoots(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'desktop_storage_roots_invalid',
        ),
      ),
    );
  });
}
