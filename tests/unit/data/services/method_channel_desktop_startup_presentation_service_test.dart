import 'package:awiki_me/src/application/desktop_startup_presentation_service.dart';
import 'package:awiki_me/src/data/services/method_channel_desktop_startup_presentation_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.awiki/desktop-startup');

  test('ready content uses the dedicated native startup channel', () async {
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
    const service = MethodChannelDesktopStartupPresentationService(
      channel: channel,
    );

    await service.presentReadyContent();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'presentReadyContent');
    expect(calls.single.arguments, isNull);
  });

  test('factory enables native presentation only on desktop targets', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      expect(
        buildDesktopStartupPresentationService(
          targetPlatform: platform,
          channel: channel,
        ),
        isA<MethodChannelDesktopStartupPresentationService>(),
      );
    }

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.fuchsia,
    ]) {
      expect(
        buildDesktopStartupPresentationService(
          targetPlatform: platform,
          channel: channel,
        ),
        isA<NoopDesktopStartupPresentationService>(),
      );
    }
  });
}
