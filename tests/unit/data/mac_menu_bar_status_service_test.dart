import 'package:awiki_me/src/data/services/mac_menu_bar_status_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setUnreadCount sends normalized count on macOS', () async {
    const channel = MethodChannel('awiki.test/menu_bar_status');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = MacMenuBarStatusService(
      channel: channel,
      isMacOS: () => true,
    );

    await service.setUnreadCount(-7);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setUnreadCount');
    expect(calls.single.arguments, <String, Object?>{'count': 0});
  });

  test('setUnreadCount is a no-op outside macOS', () async {
    const channel = MethodChannel('awiki.test/menu_bar_status.non_macos');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = MacMenuBarStatusService(
      channel: channel,
      isMacOS: () => false,
    );

    await service.setUnreadCount(12);

    expect(calls, isEmpty);
  });
}
