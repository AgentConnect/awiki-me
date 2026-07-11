import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/data/services/method_channel_attachment_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      final service = MethodChannelAttachmentPickerService(
        screenshotSupported: true,
        temporaryDirectoryProvider: () async => tempDir,
        processRunner: (_, _) async => ProcessResult(1, 1, '', ''),
      );

      expect(await service.captureScreenshot(), isNull);
    },
  );
}
