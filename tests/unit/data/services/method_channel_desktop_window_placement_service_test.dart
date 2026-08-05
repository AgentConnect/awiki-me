import 'package:awiki_me/src/data/services/method_channel_desktop_window_placement_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.awiki/desktop-window');

  test('reset placement uses the dedicated native window channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const service = MethodChannelDesktopWindowPlacementService(
      channel: channel,
    );

    await service.resetPlacement();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'resetPlacement');
    expect(calls.single.arguments, isNull);
  });
}
