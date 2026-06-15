import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/application/attachment_preview_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/data/services/file_attachment_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'previewPathFor opens existing local source without remote download',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final localFile = File('${root.path}/local.txt');
      await localFile.writeAsString('local');
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
      );
      var downloadCalls = 0;

      final path = await service.previewPathFor(
        message: _message(localPath: localFile.path),
        download: () {
          downloadCalls += 1;
          return Future<AttachmentDownloadResult>.error(
            StateError('should not download'),
          );
        },
      );

      expect(path, localFile.path);
      expect(downloadCalls, 0);
    },
  );

  test(
    'previewPathFor downloads missing remote object into app cache',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
      );

      final path = await service.previewPathFor(
        message: _message(),
        download: () async => AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'download.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[104, 105]),
        ),
      );

      expect(path, contains(root.path));
      expect(await File(path).readAsString(), 'hi');
    },
  );

  test(
    'previewPathFor reports unavailable when cache and download are empty',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
      );

      await expectLater(
        service.previewPathFor(
          message: _message(),
          download: () async => const AttachmentDownloadResult(
            attachmentId: 'att-1',
            filename: 'download.txt',
            mimeType: 'text/plain',
          ),
        ),
        throwsA(isA<AttachmentUnavailableException>()),
      );
    },
  );
}

ChatMessage _message({String? localPath}) {
  return ChatMessage(
    localId: 'local-msg',
    remoteId: 'msg-1',
    threadId: 'dm:test',
    senderDid: 'did:test:peer',
    content: '',
    createdAt: DateTime(2026, 6, 15, 12, 0),
    isMine: false,
    sendState: MessageSendState.sent,
    originalType: 'application/anp-attachment-manifest+json',
    attachment: ChatAttachment(
      attachmentId: 'att-1',
      filename: 'report.txt',
      mimeType: 'text/plain',
      localPath: localPath,
    ),
  );
}
