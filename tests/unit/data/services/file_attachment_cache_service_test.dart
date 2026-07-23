import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/data/services/file_attachment_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  test(
    'conditional cache rejects stale staging without replacing commit',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-attachments-');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final service = FileAttachmentCacheService(
        rootDirectory: () async => root,
      );
      final originalPath = await service.cacheDownloadedBytes(
        messageId: 'message',
        attachmentId: 'attachment',
        filename: 'original.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList('original'.codeUnits),
      );

      final rejectedPath = await service.cacheDownloadedBytesIfCurrent(
        messageId: 'message',
        attachmentId: 'attachment',
        filename: 'stale.txt',
        mimeType: 'text/plain',
        bytes: Uint8List.fromList('stale'.codeUnits),
        isCurrent: () => false,
      );

      expect(rejectedPath, isNull);
      expect(
        await service.lookup(messageId: 'message', attachmentId: 'attachment'),
        originalPath,
      );
      expect(await File(originalPath).readAsString(), 'original');
      final files = await Directory(
        p.dirname(originalPath),
      ).list(followLinks: false).where((entity) => entity is File).toList();
      expect(files, hasLength(1));
    },
  );

  test('new filename atomically replaces the sole committed file', () async {
    final root = await Directory.systemTemp.createTemp('awiki-attachments-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final service = FileAttachmentCacheService(rootDirectory: () async => root);
    final originalPath = await service.cacheDownloadedBytes(
      messageId: 'message',
      attachmentId: 'attachment',
      filename: 'broken.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );

    final replacementPath = await service.cacheDownloadedBytesIfCurrent(
      messageId: 'message',
      attachmentId: 'attachment',
      filename: 'fixed.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList(<int>[4, 5, 6]),
      isCurrent: () => true,
    );

    expect(replacementPath, isNotNull);
    expect(replacementPath, isNot(originalPath));
    expect(await File(originalPath).exists(), isFalse);
    expect(await File(replacementPath!).readAsBytes(), <int>[4, 5, 6]);
    expect(
      await service.lookup(messageId: 'message', attachmentId: 'attachment'),
      replacementPath,
    );
    final committedFiles = await Directory(
      p.dirname(replacementPath),
    ).list(followLinks: false).where((entity) => entity is File).toList();
    expect(committedFiles, hasLength(1));
  });

  test('lookup ignores orphaned staging and backup files', () async {
    final root = await Directory.systemTemp.createTemp('awiki-attachments-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final directory = Directory(p.join(root.path, 'message', 'attachment'));
    await directory.create(recursive: true);
    await File(
      p.join(directory.path, '._awiki_cache_staging-orphan'),
    ).writeAsString('staging');
    await File(
      p.join(directory.path, '._awiki_cache_backup-orphan'),
    ).writeAsString('backup');
    final service = FileAttachmentCacheService(rootDirectory: () async => root);

    expect(
      await service.lookup(messageId: 'message', attachmentId: 'attachment'),
      isNull,
    );
  });
}
