import 'package:awiki_me/src/application/attachment_open_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android local path opens through platform attachment channel',
    () async {
      const channel = MethodChannel('awiki.test/attachment_viewer');
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
      final service = AttachmentOpenService(
        channel: channel,
        isAndroid: () => true,
        launchUrl: (uri, {mode = LaunchMode.platformDefault}) async {
          throw StateError('launcher should not be used on Android');
        },
      );

      await service.open('/tmp/report.md');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'openAttachment');
      expect(calls.single.arguments, <String, Object?>{
        'path': '/tmp/report.md',
      });
    },
  );

  test(
    'non-Android local path opens with external application launcher',
    () async {
      final launchedUris = <Uri>[];
      final launchModes = <LaunchMode>[];
      final service = AttachmentOpenService(
        isAndroid: () => false,
        launchUrl: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUris.add(uri);
          launchModes.add(mode);
          return true;
        },
      );

      await service.open('/tmp/report.md');

      expect(launchedUris.single, Uri.file('/tmp/report.md'));
      expect(launchModes.single, LaunchMode.externalApplication);
    },
  );

  test('Android platform error reports readable message', () async {
    const channel = MethodChannel('awiki.test/attachment_viewer.error');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'attachment_open_failed',
            message: '没有可用于打开此附件的应用。',
          );
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = AttachmentOpenService(
      channel: channel,
      isAndroid: () => true,
    );

    await expectLater(
      service.open('/tmp/report.unknown'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '没有可用于打开此附件的应用。',
        ),
      ),
    );
  });
}
