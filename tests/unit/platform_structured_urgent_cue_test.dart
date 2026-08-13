import 'package:awiki_me/src/data/services/platform_structured_urgent_cue.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android cue starts for 30 seconds and exposes idempotent stop',
    () async {
      const channel = MethodChannel('test/structured_urgent_cue');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'start' ? true : null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final cue = PlatformStructuredUrgentCue(
        channel: channel,
        isAndroid: () => true,
      );

      await cue.play();
      await cue.stop();
      await cue.stop();

      expect(calls.map((call) => call.method), <String>[
        'start',
        'stop',
        'stop',
      ]);
      expect(calls.first.arguments, <String, Object>{'max_duration_ms': 30000});
    },
  );

  test(
    'Android cue fails closed when native sound and vibration cannot start',
    () async {
      const channel = MethodChannel('test/structured_urgent_cue_unavailable');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final cue = PlatformStructuredUrgentCue(
        channel: channel,
        isAndroid: () => true,
      );

      await expectLater(cue.play(), throwsA(isA<PlatformException>()));
    },
  );
}
