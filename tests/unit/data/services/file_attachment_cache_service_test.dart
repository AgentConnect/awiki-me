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
}
