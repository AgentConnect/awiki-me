import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/data/services/file_attachment_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cacheLocalSource copies file into app-owned attachment cache',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-attachments-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final source = File('${root.path}/source.md');
      await source.writeAsString('# hello');
      final service = FileAttachmentCacheService(
        rootDirectory: () async => root,
      );

      final cachedPath = await service.cacheLocalSource(
        messageId: 'msg/1',
        attachmentId: 'att:1',
        filename: '报告.md',
        mimeType: 'text/markdown',
        sourcePath: source.path,
      );

      expect(cachedPath, isNotNull);
      expect(cachedPath, isNot(source.path));
      expect(await File(cachedPath!).readAsString(), '# hello');
      expect(
        await service.lookup(messageId: 'msg/1', attachmentId: 'att:1'),
        cachedPath,
      );
    },
  );

  test(
    'cacheDownloadedBytes writes bytes into app-owned attachment cache',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-attachments-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final service = FileAttachmentCacheService(
        rootDirectory: () async => root,
      );

      final cachedPath = await service.cacheDownloadedBytes(
        messageId: 'msg-2',
        attachmentId: 'att-2',
        filename: 'download.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList(<int>[104, 105]),
      );

      expect(await File(cachedPath).readAsString(), 'hi');
      expect(
        await service.lookup(messageId: 'msg-2', attachmentId: 'att-2'),
        cachedPath,
      );
    },
  );

  test('identical attachment ids never cross storage-scope roots', () async {
    final sandbox = await Directory.systemTemp.createTemp('awiki-attachments-');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final first = FileAttachmentCacheService(
      rootDirectory: () async => Directory('${sandbox.path}/scope-a'),
    );
    final second = FileAttachmentCacheService(
      rootDirectory: () async => Directory('${sandbox.path}/scope-b'),
    );

    await first.cacheDownloadedBytes(
      messageId: 'same-message',
      attachmentId: 'same-attachment',
      filename: 'a.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList('scope-a'.codeUnits),
    );

    expect(
      await second.lookup(
        messageId: 'same-message',
        attachmentId: 'same-attachment',
      ),
      isNull,
    );
  });
}
