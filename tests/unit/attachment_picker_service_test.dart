import 'dart:io';

import 'package:awiki_me/src/data/services/method_channel_attachment_picker_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'captureScreenshot returns null when the system capture is cancelled',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-screenshot-cancel-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      const channel = MethodChannel('test.awiki/attachment-picker');
      final visibility = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isShiftPressed') {
              return true;
            }
            if (call.method == 'setMainWindowVisible') {
              visibility.add(
                (call.arguments as Map<Object?, Object?>)['visible']! as bool,
              );
              return null;
            }
            throw MissingPluginException();
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final service = MethodChannelAttachmentPickerService(
        channel: channel,
        screenshotSupported: true,
        temporaryDirectoryProvider: () async => tempDir,
        processRunner: (_, _) async => ProcessResult(1, 1, '', ''),
      );

      expect(await service.captureScreenshot(hideApp: true), isNull);
      expect(visibility, <bool>[false, true]);
    },
  );

  test('captureScreenshot restores a hidden app when capture fails', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'awiki-screenshot-failure-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    const channel = MethodChannel('test.awiki/attachment-picker-failure');
    final visibility = <bool>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isShiftPressed') {
            return true;
          }
          visibility.add(
            (call.arguments as Map<Object?, Object?>)['visible']! as bool,
          );
          return null;
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
    expect(visibility, <bool>[false, true]);
  });

  test(
    'native modifier state prevents stale Shift from hiding the app',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-screenshot-modifier-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      const channel = MethodChannel('test.awiki/attachment-picker-modifier');
      final visibility = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isShiftPressed') {
              return false;
            }
            if (call.method == 'setMainWindowVisible') {
              visibility.add(
                (call.arguments as Map<Object?, Object?>)['visible']! as bool,
              );
            }
            return null;
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
      expect(visibility, isEmpty);
      addTearDown(() async {
        final staged = File(draft!.localPath!);
        if (await staged.exists()) {
          await staged.delete();
        }
      });
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
}
