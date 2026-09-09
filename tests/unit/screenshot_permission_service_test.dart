import 'dart:async';
import 'dart:io';

import 'package:awiki_me/l10n/app_localizations_en.dart';
import 'package:awiki_me/l10n/app_localizations_zh.dart';
import 'package:awiki_me/src/application/screenshot_failure.dart';
import 'package:awiki_me/src/data/services/method_channel_attachment_picker_service.dart';
import 'package:awiki_me/src/l10n/app_message.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.awiki/screenshot-recovery');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late List<String> calls;
  late bool granted;
  late int captures;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('awiki-screenshot-recovery-');
    calls = [];
    granted = false;
    captures = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'preflightScreenCapturePermission' => granted,
        'requestScreenCapturePermission' => false,
        'screenCaptureDiagnostics' => <String, Object?>{
          'applicationName': 'AWikiMe',
          'bundleIdentifier': 'ai.awiki.awikime.dev',
          'applicationPath': '/test/AWikiMe.app',
          'version': '0.1.28',
          'unknown_secret': 'must-not-be-exported',
        },
        _ => null,
      };
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  MethodChannelAttachmentPickerService service({
    AttachmentProcessRunner? runner,
  }) => MethodChannelAttachmentPickerService(
    channel: channel,
    screenshotSupported: true,
    windowsPlatform: false,
    temporaryDirectoryProvider: () async => temp,
    attachmentTemporaryDirectoryProvider: () async => temp,
    processRunner:
        runner ??
        (_, args) async {
          captures++;
          await File(args.last).writeAsBytes([137, 80, 78, 71]);
          return ProcessResult(1, 0, '', '');
        },
  );

  Matcher failure(ScreenshotFailureKind kind) =>
      throwsA(isA<ScreenshotFailure>().having((e) => e.kind, 'kind', kind));

  test(
    'denied capture supplies current app metadata and never executes capture',
    () async {
      await expectLater(
        service().captureScreenshot(),
        throwsA(
          isA<ScreenshotFailure>()
              .having(
                (e) => e.kind,
                'kind',
                ScreenshotFailureKind.permissionRequired,
              )
              .having(
                (e) => e.diagnostics?.applicationPath,
                'actual path',
                '/test/AWikiMe.app',
              )
              .having(
                (e) => e.diagnostics?.bundleIdentifier,
                'actual bundle',
                'ai.awiki.awikime.dev',
              )
              .having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('must-not-be-exported')),
              ),
        ),
      );
      expect(captures, 0);
    },
  );

  test(
    'denial is not cached: authorization later allows capture without a new request',
    () async {
      final picker = service();
      await expectLater(
        picker.captureScreenshot(),
        failure(ScreenshotFailureKind.permissionRequired),
      );
      await expectLater(
        picker.captureScreenshot(),
        failure(ScreenshotFailureKind.permissionRequired),
      );
      granted = true;
      expect(await picker.captureScreenshot(), isNotNull);
      expect(captures, 1);
      expect(
        calls.where((m) => m == 'requestScreenCapturePermission'),
        hasLength(1),
      );
      expect(
        calls.where((m) => m == 'preflightScreenCapturePermission'),
        hasLength(3),
      );
    },
  );

  for (final outcome in ['missing', 'exception', 'null', 'malformed']) {
    test(
      '$outcome native permission bridge fails closed, not as denial',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          outcome == 'missing'
              ? null
              : (_) async {
                  if (outcome == 'exception') {
                    throw PlatformException(code: 'private-native-detail');
                  }
                  if (outcome == 'malformed') return 'not a boolean';
                  return null;
                },
        );
        await expectLater(
          service().captureScreenshot(),
          failure(ScreenshotFailureKind.permissionCheckFailed),
        );
        expect(captures, 0);
      },
    );
  }

  test(
    'missing optional diagnostics does not replace a real permission denial',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async =>
            call.method == 'screenCaptureDiagnostics' ? null : false,
      );
      await expectLater(
        service().captureScreenshot(),
        failure(ScreenshotFailureKind.permissionRequired),
      );
      expect(captures, 0);
    },
  );

  test(
    'failed request bridge can recover without being cached as a denial',
    () async {
      var requests = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'preflightScreenCapturePermission') return false;
        if (call.method == 'requestScreenCapturePermission') {
          requests++;
          if (requests == 1) throw PlatformException(code: 'unavailable');
          return true;
        }
        return null;
      });
      final picker = service();
      await expectLater(
        picker.captureScreenshot(),
        failure(ScreenshotFailureKind.permissionCheckFailed),
      );
      expect(await picker.captureScreenshot(), isNotNull);
      expect(requests, 2);
      expect(captures, 1);
    },
  );

  test(
    'revoking permission after a successful capture is checked again',
    () async {
      granted = true;
      final picker = service();
      expect(await picker.captureScreenshot(), isNotNull);
      granted = false;
      await expectLater(
        picker.captureScreenshot(),
        failure(ScreenshotFailureKind.permissionRequired),
      );
      expect(captures, 1);
    },
  );

  test('filesystem preparation failure is a capture error', () async {
    granted = true;
    final picker = MethodChannelAttachmentPickerService(
      channel: channel,
      screenshotSupported: true,
      windowsPlatform: false,
      temporaryDirectoryProvider: () async =>
          throw const FileSystemException('private path'),
    );
    await expectLater(
      picker.captureScreenshot(),
      failure(ScreenshotFailureKind.captureFailed),
    );
  });

  test(
    'concurrent clicks execute a single capture and return only one draft',
    () async {
      granted = true;
      final release = Completer<void>();
      final entered = Completer<void>();
      final picker = service(
        runner: (_, args) async {
          captures++;
          entered.complete();
          await release.future;
          await File(args.last).writeAsBytes([137, 80, 78, 71]);
          return ProcessResult(1, 0, '', '');
        },
      );
      final first = picker.captureScreenshot();
      await entered.future;
      expect(await picker.captureScreenshot(), isNull);
      release.complete();
      expect(await first, isNotNull);
      expect(captures, 1);
    },
  );

  for (final exitCode in [0, 1]) {
    test(
      'quiet cancellation ($exitCode) produces no attachment or error',
      () async {
        granted = true;
        expect(
          await service(
            runner: (_, _) async => ProcessResult(1, exitCode, '', ''),
          ).captureScreenshot(),
          isNull,
        );
      },
    );
  }

  test(
    'utility failure is localized, does not leak stderr, and permits retry',
    () async {
      granted = true;
      var fail = true;
      final picker = service(
        runner: (_, args) async {
          if (fail) return ProcessResult(1, 1, '', 'private native failure');
          await File(args.last).writeAsBytes([137, 80, 78, 71]);
          return ProcessResult(1, 0, '', '');
        },
      );
      await expectLater(
        picker.captureScreenshot(),
        failure(ScreenshotFailureKind.captureFailed),
      );
      fail = false;
      expect(await picker.captureScreenshot(), isNotNull);
    },
  );

  test('empty output image is failure, not cancellation', () async {
    granted = true;
    await expectLater(
      service(
        runner: (_, args) async {
          await File(args.last).writeAsBytes([]);
          return ProcessResult(1, 0, '', '');
        },
      ).captureScreenshot(),
      failure(ScreenshotFailureKind.captureFailed),
    );
    expect(await temp.list().toList(), isEmpty);
  });

  test(
    'all screenshot error categories have distinct Chinese and English messages',
    () {
      final zh = AppLocalizationsZh();
      final en = AppLocalizationsEn();
      final messages = ScreenshotFailureKind.values
          .map((kind) => AppMessage.fromError(ScreenshotFailure(kind)))
          .toList();
      expect(messages.map((m) => m.resolve(zh)).toSet(), hasLength(3));
      expect(messages.map((m) => m.resolve(en)).toSet(), hasLength(3));
      for (final message in messages) {
        expect(message.resolve(zh), isNot(contains('screenshot_')));
        expect(message.resolve(en), isNot(contains('screenshot_')));
      }
    },
  );

  test(
    'native request guard is process-owned and diagnostics use the running bundle',
    () {
      final source = File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsStringSync();
      final handler = source.substring(
        source.indexOf('case "requestScreenCapturePermission":'),
        source.indexOf('private func pickAttachment'),
      );
      expect(
        source,
        contains('private static var screenCapturePermissionRequested = false'),
      );
      expect(
        handler.indexOf('CGPreflightScreenCaptureAccess()'),
        lessThan(
          handler.indexOf(
            'else if MainFlutterWindow.screenCapturePermissionRequested',
          ),
        ),
      );
      expect(handler, contains('bundle.bundleURL.path'));
      expect(handler, contains('bundle.bundleIdentifier'));
      expect(handler, isNot(contains('tccutil')));
    },
  );
}
