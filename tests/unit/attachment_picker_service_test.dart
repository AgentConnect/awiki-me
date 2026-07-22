import 'dart:async';
import 'dart:io';

import 'package:awiki_me/src/data/services/method_channel_attachment_picker_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows Dart capture watchdog runs after the native timeout', () {
    final service = MethodChannelAttachmentPickerService(windowsPlatform: true);

    expect(service.screenCaptureTimeout, const Duration(seconds: 125));
    expect(
      service.screenCaptureTimeout,
      greaterThan(const Duration(seconds: 120)),
    );
  });

  test(
    'draftFromExternalSource copies local files and infers metadata',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-attachment-source-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final source = File('${tempDir.path}/report.md');
      await source.writeAsString('# Report');

      final service = MethodChannelAttachmentPickerService();
      final draft = await service.draftFromExternalSource(path: source.path);

      expect(draft, isNotNull);
      expect(draft!.filename, 'report.md');
      expect(draft.mimeType, 'text/markdown');
      expect(draft.sizeBytes, source.lengthSync());
      expect(draft.localPath, isNot(source.path));
      expect(draft.bytes, isNull);
      expect(await File(draft.localPath!).readAsString(), '# Report');
    },
  );

  test('draftFromExternalSource preserves pasted image bytes', () async {
    final service = MethodChannelAttachmentPickerService();
    final bytes = Uint8List.fromList(<int>[137, 80, 78, 71]);

    final draft = await service.draftFromExternalSource(
      filename: 'pasted.png',
      mimeType: 'image/png',
      bytes: bytes,
    );

    expect(draft, isNotNull);
    expect(draft!.filename, 'pasted.png');
    expect(draft.mimeType, 'image/png');
    expect(draft.sizeBytes, bytes.length);
    expect(draft.bytes, bytes);
    expect(draft.localPath, isNull);
  });

  test(
    'captureScreenshot stages a successful macOS interactive capture',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-screenshot-test-',
      );
      String? executable;
      List<String>? arguments;
      final service = MethodChannelAttachmentPickerService(
        screenshotSupported: true,
        temporaryDirectoryProvider: () async => tempDir,
        processRunner: (nextExecutable, nextArguments) async {
          executable = nextExecutable;
          arguments = nextArguments;
          await File(nextArguments.last).writeAsBytes(<int>[137, 80, 78, 71]);
          return ProcessResult(1, 0, '', '');
        },
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final draft = await service.captureScreenshot();

      expect(executable, '/usr/sbin/screencapture');
      expect(arguments?.take(2), <String>['-i', '-x']);
      expect(draft, isNotNull);
      expect(draft!.filename, startsWith('screenshot-'));
      expect(draft.mimeType, 'image/png');
      expect(draft.sizeBytes, 4);
      expect(await File(draft.localPath!).exists(), isTrue);
      addTearDown(() async {
        final staged = File(draft.localPath!);
        if (await staged.exists()) {
          await staged.delete();
        }
      });
    },
  );

  test(
    'captureScreenshot never hides the app even when legacy hideApp is true',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-screenshot-visible-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      const channel = MethodChannel('test.awiki/attachment-picker-visible');
      final channelCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            channelCalls.add(call);
            return call.method == 'preflightScreenCapturePermission';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final service = MethodChannelAttachmentPickerService(
        channel: channel,
        screenshotSupported: true,
        temporaryDirectoryProvider: () async => tempDir,
        processRunner: (_, arguments) async {
          await File(arguments.last).writeAsBytes(<int>[137, 80, 78, 71]);
          return ProcessResult(1, 0, '', '');
        },
      );

      final draft = await service.captureScreenshot(hideApp: true);

      expect(draft, isNotNull);
      expect(channelCalls.map((call) => call.method), <String>[
        'preflightScreenCapturePermission',
      ]);
      addTearDown(() async {
        final staged = File(draft!.localPath!);
        if (await staged.exists()) {
          await staged.delete();
        }
      });
    },
  );

  test('captureScreenshot keeps the app visible when capture fails', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'awiki-screenshot-failure-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    const channel = MethodChannel('test.awiki/attachment-picker-failure');
    final channelCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          channelCalls.add(call);
          return call.method == 'preflightScreenCapturePermission';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = MethodChannelAttachmentPickerService(
      channel: channel,
      screenshotSupported: true,
      temporaryDirectoryProvider: () async => tempDir,
      processRunner: (_, _) async =>
          throw const ProcessException('screencapture', <String>[]),
    );

    await expectLater(
      service.captureScreenshot(hideApp: true),
      throwsA(isA<StateError>()),
    );
    expect(channelCalls.map((call) => call.method), <String>[
      'preflightScreenCapturePermission',
    ]);
  });

  test(
    'captureScreenshot requests permission once and never captures desktop when denied',
    () async {
      const channel = MethodChannel('test.awiki/attachment-picker-permission');
      final channelCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            channelCalls.add(call);
            return false;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      var processCalls = 0;
      final service = MethodChannelAttachmentPickerService(
        channel: channel,
        screenshotSupported: true,
        processRunner: (_, _) async {
          processCalls += 1;
          return ProcessResult(1, 0, '', '');
        },
      );

      await expectLater(
        service.captureScreenshot(),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.captureScreenshot(),
        throwsA(isA<StateError>()),
      );

      expect(processCalls, 0);
      expect(channelCalls.map((call) => call.method), <String>[
        'preflightScreenCapturePermission',
        'requestScreenCapturePermission',
        'preflightScreenCapturePermission',
      ]);
    },
  );

  test(
    'macOS clipboard prefers a copied image file over its Finder icon',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-clipboard-file-test-',
      );
      final source = File('${tempDir.path}/actual-picture.png');
      final actualBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 1, 2, 3]);
      final finderIconBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 9]);
      await source.writeAsBytes(actualBytes);
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final service = MethodChannelAttachmentPickerService(
        preferClipboardFiles: true,
        clipboardFilesReader: () async => <String>[source.path],
        clipboardImageReader: () async => finderIconBytes,
      );

      final draft = await service.readClipboardAttachment();

      expect(draft, isNotNull);
      expect(draft!.filename, 'actual-picture.png');
      expect(draft.bytes, isNull);
      expect(await File(draft.localPath!).readAsBytes(), actualBytes);
      addTearDown(() async {
        final staged = File(draft.localPath!);
        if (await staged.exists()) {
          await staged.delete();
        }
      });
    },
  );

  test('macOS clipboard falls back to direct screenshot image bytes', () async {
    final screenshotBytes = Uint8List.fromList(<int>[137, 80, 78, 71, 4]);
    final service = MethodChannelAttachmentPickerService(
      preferClipboardFiles: true,
      clipboardFilesReader: () async => const <String>[],
      clipboardImageReader: () async => screenshotBytes,
    );

    final draft = await service.readClipboardAttachment();

    expect(draft, isNotNull);
    expect(draft!.filename, startsWith('pasted-image-'));
    expect(draft.mimeType, 'image/png');
    expect(draft.bytes, screenshotBytes);
  });

  test('Windows file selection stages through the shared pipeline', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'awiki-windows-file-selector-test-',
    );
    final source = File('${tempDir.path}/报告 with spaces.md');
    await source.writeAsString('# Windows');
    final stagedDir = Directory('${tempDir.path}/staged');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final service = MethodChannelAttachmentPickerService(
      windowsPlatform: true,
      screenshotSupported: false,
      attachmentTemporaryDirectoryProvider: () async => stagedDir,
      windowsFileSelector: () async => AttachmentPlatformFile(
        path: source.path,
        filename: '报告 with spaces.md',
        sizeBytes: await source.length(),
      ),
    );

    final draft = await service.pickAttachment();

    expect(draft, isNotNull);
    expect(draft!.filename, '报告 with spaces.md');
    expect(draft.mimeType, 'text/markdown');
    expect(draft.sizeBytes, await source.length());
    expect(draft.localPath, isNot(source.path));
    expect(await File(draft.localPath!).readAsString(), '# Windows');
  });

  test('Windows file selection cancellation returns null', () async {
    final service = MethodChannelAttachmentPickerService(
      windowsPlatform: true,
      windowsFileSelector: () async => null,
    );

    expect(await service.pickAttachment(), isNull);
  });

  test(
    'Windows save uses the selected destination and sanitized name',
    () async {
      String? receivedFilename;
      String? receivedMimeType;
      Uint8List? receivedBytes;
      final service = MethodChannelAttachmentPickerService(
        windowsPlatform: true,
        windowsFileSaver:
            ({
              required String filename,
              required String mimeType,
              required Uint8List bytes,
            }) async {
              receivedFilename = filename;
              receivedMimeType = mimeType;
              receivedBytes = bytes;
              return r'C:\Users\tester\Downloads\unsafe_name.txt';
            },
      );

      final result = await service.saveAttachment(
        filename: 'unsafe:name.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(result, r'C:\Users\tester\Downloads\unsafe_name.txt');
      expect(receivedFilename, 'unsafe_name.txt');
      expect(receivedMimeType, 'text/plain');
      expect(receivedBytes, <int>[1, 2, 3]);
    },
  );

  test(
    'Windows screenshot uses the native region channel without hiding the app',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-windows-screenshot-test-',
      );
      final stagedDir = Directory('${tempDir.path}/staged');
      const channel = MethodChannel('test.awiki/windows-region-capture');
      final channelCalls = <MethodCall>[];
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            channelCalls.add(call);
            if (call.method == 'captureRegion') {
              final arguments = Map<Object?, Object?>.from(
                call.arguments! as Map<Object?, Object?>,
              );
              await File(
                arguments['outputPath']! as String,
              ).writeAsBytes(<int>[137, 80, 78, 71]);
              return true;
            }
            return false;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final service = MethodChannelAttachmentPickerService(
        channel: channel,
        windowsPlatform: true,
        screenshotSupported: true,
        temporaryDirectoryProvider: () async => tempDir,
        attachmentTemporaryDirectoryProvider: () async => stagedDir,
      );

      final draft = await service.captureScreenshot(hideApp: true);

      expect(draft, isNotNull);
      expect(draft!.mimeType, 'image/png');
      expect(draft.sizeBytes, 4);
      expect(channelCalls, hasLength(1));
      expect(channelCalls.single.method, 'captureRegion');
      expect(
        (channelCalls.single.arguments! as Map<Object?, Object?>)['outputPath'],
        endsWith('.png'),
      );
      expect(await File(draft.localPath!).exists(), isTrue);
    },
  );

  test('Windows native screenshot cancellation returns null', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'awiki-windows-screenshot-cancel-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final service = MethodChannelAttachmentPickerService(
      windowsPlatform: true,
      screenshotSupported: true,
      temporaryDirectoryProvider: () async => tempDir,
      windowsScreenCaptureRunner: (_) async => false,
    );

    expect(await service.captureScreenshot(), isNull);
  });

  for (final code in <String>[
    'capture_invalid_path',
    'capture_busy',
    'capture_failed',
  ]) {
    test('Windows screenshot preserves stable native error $code', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-windows-screenshot-error-test-',
      );
      final channel = MethodChannel('test.awiki/windows-region-$code');
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: code, message: 'native detail');
          });
      final service = MethodChannelAttachmentPickerService(
        channel: channel,
        windowsPlatform: true,
        screenshotSupported: true,
        temporaryDirectoryProvider: () async => tempDir,
      );

      await expectLater(
        service.captureScreenshot(),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', code),
        ),
      );
    });
  }

  test('Windows screenshot timeout cancels the native capture', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'awiki-windows-screenshot-timeout-test-',
    );
    final events = <String>[];
    final captureResult = Completer<bool>();
    const channel = MethodChannel('test.awiki/windows-region-timeout');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          events.add(call.method);
          if (call.method == 'captureRegion') {
            return captureResult.future;
          }
          if (call.method == 'cancelCapture') {
            captureResult.complete(false);
            return true;
          }
          return false;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final service = MethodChannelAttachmentPickerService(
      channel: channel,
      windowsPlatform: true,
      screenshotSupported: true,
      temporaryDirectoryProvider: () async => tempDir,
      screenCaptureTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      service.captureScreenshot(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'screenshot_capture_timeout',
        ),
      ),
    );
    expect(events, <String>['captureRegion', 'cancelCapture']);
  });

  test('shared staging rejects invalid and oversized attachments', () async {
    final service = MethodChannelAttachmentPickerService(
      maxAttachmentSizeBytes: 3,
    );

    await expectLater(
      service.draftFromExternalSource(
        filename: 'empty.bin',
        bytes: Uint8List(0),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'attachment_size_invalid',
        ),
      ),
    );
    await expectLater(
      service.draftFromExternalSource(
        filename: 'large.bin',
        bytes: Uint8List(4),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'attachment_too_large',
        ),
      ),
    );
  });
}
