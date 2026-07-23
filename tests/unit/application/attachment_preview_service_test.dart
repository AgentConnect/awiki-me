import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/application/attachment_cache_service.dart';
import 'package:awiki_me/src/application/attachment_image_dimensions.dart';
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

  test(
    'previewPathFor shares one in-flight resolution per attachment',
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
      addTearDown(service.dispose);
      final downloadGate = Completer<AttachmentDownloadResult>();
      var downloadCalls = 0;

      Future<AttachmentDownloadResult> download() {
        downloadCalls += 1;
        return downloadGate.future;
      }

      final first = service.previewPathFor(
        message: _message(),
        download: download,
      );
      final handle = service.previewHandleFor(_message());
      final second = service.previewPathFor(
        message: _message(),
        download: download,
      );

      expect(identical(first, second), isTrue);
      expect(handle.snapshot.phase, AttachmentPreviewPhase.loading);
      downloadGate.complete(
        AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'download.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[104, 105]),
        ),
      );

      final paths = await Future.wait(<Future<String>>[first, second]);
      expect(downloadCalls, 1);
      expect(paths[0], paths[1]);
      expect(handle.snapshot.phase, AttachmentPreviewPhase.ready);
      expect(handle.snapshot.path, paths[0]);
    },
  );

  test('failed preview state survives lookup and explicit retry', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
    );
    addTearDown(service.dispose);
    var downloadCalls = 0;

    await expectLater(
      service.previewPathFor(
        message: _message(),
        download: () async {
          downloadCalls += 1;
          throw StateError('temporary download failure');
        },
      ),
      throwsStateError,
    );

    final failedHandle = service.previewHandleFor(_message());
    expect(failedHandle.snapshot.phase, AttachmentPreviewPhase.failed);
    expect(
      identical(failedHandle, service.previewHandleFor(_message())),
      isTrue,
    );

    final path = await service.previewPathFor(
      message: _message(),
      download: () async {
        downloadCalls += 1;
        return AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'download.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[111, 107]),
        );
      },
    );

    expect(downloadCalls, 2);
    expect(failedHandle.snapshot.phase, AttachmentPreviewPhase.ready);
    expect(failedHandle.snapshot.path, path);
    expect(await File(path).readAsString(), 'ok');
  });

  test('rejected authoritative local source stays external-only', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final localFile = File('${root.path}/local.png');
    await localFile.writeAsBytes(<int>[1, 2, 3]);
    final localReference = localFile.uri.toString();
    final message = _message(localPath: localReference);
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
    );
    addTearDown(service.dispose);
    final handle = service.previewHandleFor(message);
    var downloadCalls = 0;

    service.reportPreviewDecodeFailure(message: message, path: localReference);

    expect(handle.snapshot.phase, AttachmentPreviewPhase.failed);
    expect(
      service.previewHandleFor(message).snapshot.phase,
      AttachmentPreviewPhase.failed,
    );

    final path = await service.previewPathFor(
      message: message,
      download: () {
        downloadCalls += 1;
        return Future<AttachmentDownloadResult>.error(
          StateError('local source must not trigger a download'),
        );
      },
    );
    expect(path, localFile.path);
    expect(downloadCalls, 0);
    expect(await localFile.readAsBytes(), <int>[1, 2, 3]);
    expect(handle.snapshot.phase, AttachmentPreviewPhase.failed);
  });

  test(
    'new local source is not overwritten by stale remote completion',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final localFile = File('${root.path}/committed-local.png');
      await localFile.writeAsBytes(<int>[1, 2, 3]);
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
      );
      addTearDown(service.dispose);
      final downloadGate = Completer<AttachmentDownloadResult>();

      final staleResolution = service.previewPathFor(
        message: _message(),
        download: () => downloadGate.future,
      );
      final handle = service.previewHandleFor(_message());
      expect(handle.snapshot.phase, AttachmentPreviewPhase.loading);

      final updatedHandle = service.previewHandleFor(
        _message(localPath: localFile.path),
      );
      expect(identical(handle, updatedHandle), isTrue);
      expect(updatedHandle.snapshot.phase, AttachmentPreviewPhase.ready);
      expect(updatedHandle.snapshot.path, localFile.path);

      final staleError = expectLater(
        staleResolution,
        throwsA(isA<AttachmentPreviewResolutionInvalidatedException>()),
      );
      downloadGate.complete(
        AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'stale.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList(<int>[4, 5, 6]),
        ),
      );
      await staleError;

      expect(updatedHandle.snapshot.phase, AttachmentPreviewPhase.ready);
      expect(updatedHandle.snapshot.path, localFile.path);
    },
  );

  test(
    'object uri added after failure restarts with latest resolver',
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
      addTearDown(service.dispose);
      final original = _message();
      var downloadCalls = 0;

      await expectLater(
        service.previewPathFor(
          message: original,
          download: () async {
            downloadCalls += 1;
            throw StateError('object uri not available yet');
          },
        ),
        throwsStateError,
      );
      final handle = service.previewHandleFor(original);
      expect(handle.snapshot.phase, AttachmentPreviewPhase.failed);

      final updated = _message(objectUri: 'awiki-object://new-source');
      final updatedHandle = service.previewHandleFor(updated);
      expect(identical(handle, updatedHandle), isTrue);
      expect(updatedHandle.snapshot.phase, AttachmentPreviewPhase.idle);

      final path = await service.previewPathFor(
        message: updated,
        download: () async {
          downloadCalls += 1;
          return AttachmentDownloadResult(
            attachmentId: 'att-1',
            filename: 'report.txt',
            mimeType: 'text/plain',
            bytes: Uint8List.fromList(<int>[110, 101, 119]),
          );
        },
      );

      expect(downloadCalls, 2);
      expect(updatedHandle.snapshot.phase, AttachmentPreviewPhase.ready);
      expect(updatedHandle.snapshot.path, path);
      expect(await File(path).readAsString(), 'new');
    },
  );

  test(
    'object uri switch invalidates a running resolver and stale write',
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
      addTearDown(service.dispose);
      final oldDownloadStarted = Completer<void>();
      final oldDownload = Completer<AttachmentDownloadResult>();
      final oldMessage = _message(objectUri: 'awiki-object://old-source');
      final oldResolution = service.previewPathFor(
        message: oldMessage,
        download: () {
          oldDownloadStarted.complete();
          return oldDownload.future;
        },
      );
      await oldDownloadStarted.future;
      final oldError = expectLater(
        oldResolution,
        throwsA(isA<AttachmentPreviewResolutionInvalidatedException>()),
      );

      final newMessage = _message(objectUri: 'awiki-object://new-source');
      final handle = service.previewHandleFor(newMessage);
      expect(handle.snapshot.phase, AttachmentPreviewPhase.idle);
      final newPath = await service.previewPathFor(
        message: newMessage,
        download: () async => AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'report.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[110, 101, 119]),
        ),
      );

      oldDownload.complete(
        AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'report.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[111, 108, 100]),
        ),
      );
      await oldError;

      expect(handle.snapshot.phase, AttachmentPreviewPhase.ready);
      expect(handle.snapshot.path, newPath);
      expect(await File(newPath).readAsString(), 'new');
    },
  );

  test(
    'source switch invalidates a resolver already waiting in cache commit',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final delegate = FileAttachmentCacheService(
        rootDirectory: () async => root,
      );
      final cache = _DelayFirstConditionalAttachmentCache(delegate);
      final service = AttachmentPreviewService(cache: cache);
      addTearDown(service.dispose);
      final oldMessage = _message(objectUri: 'awiki-object://old-source');
      final oldResolution = service.previewPathFor(
        message: oldMessage,
        download: () async => AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'old.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList('old'.codeUnits),
        ),
      );
      await cache.firstConditionalStarted.future;
      final oldError = expectLater(
        oldResolution,
        throwsA(isA<AttachmentPreviewResolutionInvalidatedException>()),
      );

      final newMessage = _message(objectUri: 'awiki-object://new-source');
      final handle = service.previewHandleFor(newMessage);
      final newPath = await service.previewPathFor(
        message: newMessage,
        download: () async => AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'new.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList('new'.codeUnits),
        ),
      );
      cache.releaseFirstConditional.complete();
      await oldError;

      expect(handle.snapshot.phase, AttachmentPreviewPhase.ready);
      expect(handle.snapshot.path, newPath);
      expect(await File(newPath).readAsString(), 'new');
      expect(
        await delegate.lookup(messageId: 'msg-1', attachmentId: 'att-1'),
        newPath,
      );
    },
  );

  test(
    'rejected app cache is bypassed and replaced by a new download',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final message = _message(
        objectUri: 'awiki-object://image',
        filename: 'image.png',
      );
      final cache = FileAttachmentCacheService(rootDirectory: () async => root);
      final service = AttachmentPreviewService(cache: cache);
      addTearDown(service.dispose);
      var downloadCalls = 0;

      final rejectedPath = await service.previewPathFor(
        message: message,
        download: () async {
          downloadCalls += 1;
          return AttachmentDownloadResult(
            attachmentId: 'att-1',
            filename: 'broken.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
          );
        },
      );
      service.reportPreviewDecodeFailure(message: message, path: rejectedPath);

      final refreshedPath = await service.previewPathFor(
        message: message,
        download: () async {
          downloadCalls += 1;
          return AttachmentDownloadResult(
            attachmentId: 'att-1',
            filename: 'fixed.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[4, 5, 6]),
          );
        },
      );

      expect(downloadCalls, 2);
      expect(refreshedPath, isNot(rejectedPath));
      expect(await File(rejectedPath).exists(), isFalse);
      expect(await File(refreshedPath).readAsBytes(), <int>[4, 5, 6]);
      expect(
        service.previewHandleFor(message).snapshot.phase,
        AttachmentPreviewPhase.ready,
      );

      service.dispose();
      final rebuiltService = AttachmentPreviewService(cache: cache);
      addTearDown(rebuiltService.dispose);
      final rebuiltPath = await rebuiltService.previewPathFor(
        message: message,
        download: () {
          downloadCalls += 1;
          return Future<AttachmentDownloadResult>.error(
            StateError('rebuilt service must reuse the fixed cache'),
          );
        },
      );
      expect(rebuiltPath, refreshedPath);
      expect(downloadCalls, 2);
    },
  );

  test(
    'completion trims inactive handles back to the configured limit',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
        maxRetainedEntries: 1,
      );
      addTearDown(service.dispose);
      final firstMessage = _message(
        localId: 'local-1',
        remoteId: 'message-1',
        attachmentId: 'attachment-1',
      );
      final secondMessage = _message(
        localId: 'local-2',
        remoteId: 'message-2',
        attachmentId: 'attachment-2',
      );
      final downloadStarted = Completer<void>();
      final downloadGate = Completer<AttachmentDownloadResult>();
      final firstResolution = service.previewPathFor(
        message: firstMessage,
        download: () {
          downloadStarted.complete();
          return downloadGate.future;
        },
      );
      await downloadStarted.future;
      final firstHandle = service.previewHandleFor(firstMessage);
      service.previewHandleFor(secondMessage);

      downloadGate.complete(
        AttachmentDownloadResult(
          attachmentId: 'attachment-1',
          filename: 'first.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[1]),
        ),
      );
      await firstResolution;
      await Future<void>.delayed(Duration.zero);

      expect(
        identical(firstHandle, service.previewHandleFor(firstMessage)),
        isFalse,
      );
    },
  );

  test('last listener detaching trims handles back to the limit', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      maxRetainedEntries: 1,
    );
    addTearDown(service.dispose);
    final firstMessage = _message(
      localId: 'local-1',
      remoteId: 'message-1',
      attachmentId: 'attachment-1',
    );
    final secondMessage = _message(
      localId: 'local-2',
      remoteId: 'message-2',
      attachmentId: 'attachment-2',
    );
    final firstHandle = service.previewHandleFor(firstMessage);
    final subscription = firstHandle.changes.listen((_) {});
    service.previewHandleFor(secondMessage);

    await subscription.cancel();
    await Future<void>.delayed(Duration.zero);

    expect(
      identical(firstHandle, service.previewHandleFor(firstMessage)),
      isFalse,
    );
  });

  test(
    'dispose during conditional cache commit discards staging and state',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final delegate = FileAttachmentCacheService(
        rootDirectory: () async => root,
      );
      final cache = _DelayFirstConditionalAttachmentCache(delegate);
      final service = AttachmentPreviewService(cache: cache);
      final resolution = service.previewPathFor(
        message: _message(),
        download: () async => AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'report.txt',
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      await cache.firstConditionalStarted.future;
      final invalidated = expectLater(
        resolution,
        throwsA(isA<AttachmentPreviewResolutionInvalidatedException>()),
      );

      service.dispose();
      cache.releaseFirstConditional.complete();
      await invalidated;

      expect(
        await delegate.lookup(messageId: 'msg-1', attachmentId: 'att-1'),
        isNull,
      );
    },
  );

  test('stale decode failure cannot roll back a newer local source', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final oldFile = File('${root.path}/old.png');
    final newFile = File('${root.path}/new.png');
    await oldFile.writeAsBytes(<int>[1]);
    await newFile.writeAsBytes(<int>[2]);
    final oldMessage = _message(localPath: oldFile.path);
    final newMessage = _message(localPath: newFile.path);
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
    );
    addTearDown(service.dispose);

    final handle = service.previewHandleFor(oldMessage);
    service.previewHandleFor(newMessage);
    service.reportPreviewDecodeFailure(message: oldMessage, path: oldFile.path);

    expect(handle.snapshot.phase, AttachmentPreviewPhase.ready);
    expect(handle.snapshot.path, newFile.path);
  });

  test('validated image dimensions reject non-positive pixel sizes', () {
    expect(
      () => AttachmentImageDimensions(pixelWidth: 0, pixelHeight: 10),
      throwsArgumentError,
    );
    expect(
      () => AttachmentImageDimensions(pixelWidth: 10, pixelHeight: -1),
      throwsArgumentError,
    );
  });

  test('local image dimensions are probed once per source path', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final image = File('${root.path}/portrait.png');
    await image.writeAsBytes(<int>[1, 2, 3]);
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);
    final message = _message(
      localPath: image.uri.toString(),
      filename: 'portrait.png',
      mimeType: 'image/png',
    );

    final handle = service.previewHandleFor(message);
    service.previewHandleFor(message);
    expect(probe.calls, <String>[image.path]);
    final update = handle.changes.firstWhere(
      (snapshot) => snapshot.dimensions != null,
    );

    probe.complete(
      image.path,
      AttachmentImageDimensions(pixelWidth: 900, pixelHeight: 1600),
    );
    final snapshot = await update;

    expect(snapshot.phase, AttachmentPreviewPhase.ready);
    expect(snapshot.path, image.uri.toString());
    expect(
      snapshot.dimensions,
      AttachmentImageDimensions(pixelWidth: 900, pixelHeight: 1600),
    );
    service.previewHandleFor(message);
    expect(probe.calls, <String>[image.path]);
  });

  test(
    'downloaded image is probed once after the local path is ready',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final probe = _ControlledImageDimensionProbe();
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
        imageDimensionProbe: probe,
      );
      addTearDown(service.dispose);
      final message = _message(
        objectUri: 'awiki-object://image',
        filename: 'landscape.webp',
        mimeType: 'image/webp',
      );
      final handle = service.previewHandleFor(message);
      final update = handle.changes.firstWhere(
        (snapshot) => snapshot.dimensions != null,
      );

      final path = await service.previewPathFor(
        message: message,
        download: () async => AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'landscape.webp',
          mimeType: 'image/webp',
          bytes: Uint8List.fromList(<int>[1, 2, 3]),
        ),
      );
      expect(probe.calls, <String>[path]);
      probe.complete(
        path,
        AttachmentImageDimensions(pixelWidth: 1600, pixelHeight: 900),
      );
      await update;

      await service.previewPathFor(
        message: message,
        download: () => Future<AttachmentDownloadResult>.error(
          StateError('the ready cache should be reused'),
        ),
      );
      expect(probe.calls, <String>[path]);
    },
  );

  test('stale image dimensions cannot overwrite a newer source', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final oldImage = File('${root.path}/old.png');
    final newImage = File('${root.path}/new.png');
    await oldImage.writeAsBytes(<int>[1]);
    await newImage.writeAsBytes(<int>[2]);
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);
    final oldMessage = _message(
      localPath: oldImage.path,
      filename: 'image.png',
      mimeType: 'image/png',
    );
    final newMessage = _message(
      localPath: newImage.path,
      filename: 'image.png',
      mimeType: 'image/png',
    );

    final handle = service.previewHandleFor(oldMessage);
    service.previewHandleFor(newMessage);
    expect(probe.calls, <String>[oldImage.path, newImage.path]);
    final newUpdate = handle.changes.firstWhere(
      (snapshot) => snapshot.dimensions?.pixelWidth == 1200,
    );
    probe.complete(
      newImage.path,
      AttachmentImageDimensions(pixelWidth: 1200, pixelHeight: 1200),
    );
    await newUpdate;

    probe.complete(
      oldImage.path,
      AttachmentImageDimensions(pixelWidth: 900, pixelHeight: 1600),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handle.snapshot.path, newImage.path);
    expect(
      handle.snapshot.dimensions,
      AttachmentImageDimensions(pixelWidth: 1200, pixelHeight: 1200),
    );
  });

  test('decode failure retains dimensions for the stable fallback', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final image = File('${root.path}/image.png');
    await image.writeAsBytes(<int>[1]);
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);
    final message = _message(
      localPath: image.path,
      filename: 'image.png',
      mimeType: 'image/png',
    );
    final handle = service.previewHandleFor(message);
    final ready = handle.changes.firstWhere(
      (snapshot) => snapshot.dimensions != null,
    );
    final dimensions = AttachmentImageDimensions(
      pixelWidth: 1600,
      pixelHeight: 900,
    );
    probe.complete(image.path, dimensions);
    await ready;
    await Future<void>.delayed(Duration.zero);

    service.reportPreviewDecodeFailure(message: message, path: image.path);

    expect(handle.snapshot.phase, AttachmentPreviewPhase.failed);
    expect(handle.snapshot.path, image.path);
    expect(handle.snapshot.dimensions, dimensions);
  });

  test('same-path replacement invalidates the old dimension probe', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final stablePath = File('${root.path}/download.png');
    await stablePath.writeAsBytes(<int>[1]);
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);
    final message = _message(
      objectUri: 'awiki-object://image',
      filename: 'download.png',
      mimeType: 'image/png',
    );
    final handle = service.previewHandleFor(message);

    final firstPath = await service.previewPathFor(
      message: message,
      download: () async => AttachmentDownloadResult(
        attachmentId: 'att-1',
        filename: 'download.png',
        mimeType: 'image/png',
        localPath: stablePath.path,
      ),
    );
    expect(firstPath, stablePath.path);
    expect(probe.calls, <String>[stablePath.path]);

    service.reportPreviewDecodeFailure(message: message, path: stablePath.path);
    expect(handle.snapshot.phase, AttachmentPreviewPhase.failed);

    final replacementPath = await service.previewPathFor(
      message: message,
      download: () async {
        await stablePath.writeAsBytes(<int>[2]);
        return AttachmentDownloadResult(
          attachmentId: 'att-1',
          filename: 'download.png',
          mimeType: 'image/png',
          localPath: stablePath.path,
        );
      },
    );
    expect(replacementPath, stablePath.path);
    expect(probe.calls, <String>[stablePath.path, stablePath.path]);

    probe.completeCall(
      stablePath.path,
      0,
      AttachmentImageDimensions(pixelWidth: 900, pixelHeight: 1600),
    );
    await Future<void>.delayed(Duration.zero);
    expect(handle.snapshot.dimensions, isNull);

    final corrected = handle.changes.firstWhere(
      (snapshot) => snapshot.dimensions?.pixelWidth == 1600,
    );
    probe.completeCall(
      stablePath.path,
      1,
      AttachmentImageDimensions(pixelWidth: 1600, pixelHeight: 900),
    );
    await corrected;

    expect(handle.snapshot.phase, AttachmentPreviewPhase.ready);
    expect(
      handle.snapshot.dimensions,
      AttachmentImageDimensions(pixelWidth: 1600, pixelHeight: 900),
    );
  });

  test('outgoing source transitions retain provisional dimensions', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final temporaryImage = File('${root.path}/outgoing-temp.png');
    final cachedImage = File('${root.path}/outgoing-cache.png');
    await temporaryImage.writeAsBytes(<int>[1]);
    await cachedImage.writeAsBytes(<int>[1]);
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);
    final originalMessage = _message(
      localPath: temporaryImage.path,
      filename: 'outgoing.png',
      mimeType: 'image/png',
    );
    final handle = service.previewHandleFor(originalMessage);
    final initialDimensions = AttachmentImageDimensions(
      pixelWidth: 900,
      pixelHeight: 1600,
    );
    final initialUpdate = handle.changes.firstWhere(
      (snapshot) => snapshot.dimensions == initialDimensions,
    );
    probe.complete(temporaryImage.path, initialDimensions);
    await initialUpdate;
    await Future<void>.delayed(Duration.zero);

    final objectUriAdded = _message(
      localPath: temporaryImage.path,
      objectUri: 'awiki-object://outgoing',
      filename: 'outgoing.png',
      mimeType: 'image/png',
    );
    final metadataHandle = service.previewHandleFor(objectUriAdded);
    expect(identical(metadataHandle, handle), isTrue);
    expect(metadataHandle.snapshot.dimensions, initialDimensions);
    expect(probe.calls, <String>[temporaryImage.path]);

    final cachedMessage = _message(
      localPath: cachedImage.path,
      objectUri: 'awiki-object://outgoing',
      filename: 'outgoing.png',
      mimeType: 'image/png',
    );
    final cachedHandle = service.previewHandleFor(cachedMessage);
    expect(identical(cachedHandle, handle), isTrue);
    expect(cachedHandle.snapshot.path, cachedImage.path);
    expect(cachedHandle.snapshot.dimensions, initialDimensions);
    expect(probe.calls, <String>[temporaryImage.path, cachedImage.path]);

    final correctedDimensions = AttachmentImageDimensions(
      pixelWidth: 901,
      pixelHeight: 1601,
    );
    final correctedUpdate = handle.changes.firstWhere(
      (snapshot) => snapshot.dimensions == correctedDimensions,
    );
    probe.complete(cachedImage.path, correctedDimensions);
    await correctedUpdate;

    expect(handle.snapshot.dimensions, correctedDimensions);
  });

  test('non-image attachments are never dimension probed', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final file = File('${root.path}/report.txt');
    await file.writeAsString('report');
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);

    service.previewHandleFor(_message(localPath: file.path));

    expect(probe.calls, isEmpty);
  });

  test('failed dimension probes are not repeated for the same path', () async {
    final root = await Directory.systemTemp.createTemp('awiki-preview-');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });
    final nullImage = File('${root.path}/null.png');
    final errorImage = File('${root.path}/error.png');
    await nullImage.writeAsBytes(<int>[1]);
    await errorImage.writeAsBytes(<int>[2]);
    final probe = _ControlledImageDimensionProbe();
    final service = AttachmentPreviewService(
      cache: FileAttachmentCacheService(rootDirectory: () async => root),
      imageDimensionProbe: probe,
    );
    addTearDown(service.dispose);

    final nullMessage = _message(
      localPath: nullImage.path,
      filename: 'image.png',
      mimeType: 'image/png',
    );
    service.previewHandleFor(nullMessage);
    probe.complete(nullImage.path, null);
    await Future<void>.delayed(Duration.zero);
    service.previewHandleFor(nullMessage);

    final errorMessage = _message(
      localPath: errorImage.path,
      filename: 'image.png',
      mimeType: 'image/png',
    );
    final handle = service.previewHandleFor(errorMessage);
    probe.fail(errorImage.path, StateError('invalid image header'));
    await Future<void>.delayed(Duration.zero);
    service.previewHandleFor(errorMessage);

    expect(probe.calls, <String>[nullImage.path, errorImage.path]);
    expect(handle.snapshot.phase, AttachmentPreviewPhase.ready);
    expect(handle.snapshot.dimensions, isNull);
  });

  test(
    'disposing the scope prevents an in-flight probe from publishing',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki-preview-');
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final image = File('${root.path}/image.png');
      await image.writeAsBytes(<int>[1]);
      final probe = _ControlledImageDimensionProbe();
      final service = AttachmentPreviewService(
        cache: FileAttachmentCacheService(rootDirectory: () async => root),
        imageDimensionProbe: probe,
      );
      final message = _message(
        localPath: image.path,
        filename: 'image.png',
        mimeType: 'image/png',
      );
      final handle = service.previewHandleFor(message);

      service.dispose();
      probe.complete(
        image.path,
        AttachmentImageDimensions(pixelWidth: 100, pixelHeight: 200),
      );
      await Future<void>.delayed(Duration.zero);

      expect(handle.snapshot.dimensions, isNull);
    },
  );
}

ChatMessage _message({
  String? localPath,
  String? objectUri,
  String localId = 'local-msg',
  String remoteId = 'msg-1',
  String threadId = 'dm:test',
  String attachmentId = 'att-1',
  String filename = 'report.txt',
  String mimeType = 'text/plain',
}) {
  return ChatMessage(
    localId: localId,
    remoteId: remoteId,
    threadId: threadId,
    senderDid: 'did:test:peer',
    content: '',
    createdAt: DateTime(2026, 6, 15, 12, 0),
    isMine: false,
    sendState: MessageSendState.sent,
    originalType: 'application/anp-attachment-manifest+json',
    attachment: ChatAttachment(
      attachmentId: attachmentId,
      filename: filename,
      mimeType: mimeType,
      localPath: localPath,
      objectUri: objectUri,
    ),
  );
}

class _ControlledImageDimensionProbe implements AttachmentImageDimensionProbe {
  final List<String> calls = <String>[];
  final Map<String, List<Completer<AttachmentImageDimensions?>>> _completers =
      <String, List<Completer<AttachmentImageDimensions?>>>{};

  @override
  Future<AttachmentImageDimensions?> probe(String localPath) {
    calls.add(localPath);
    final completer = Completer<AttachmentImageDimensions?>();
    (_completers[localPath] ??= <Completer<AttachmentImageDimensions?>>[]).add(
      completer,
    );
    return completer.future;
  }

  void complete(String localPath, AttachmentImageDimensions? dimensions) {
    _nextPending(localPath).complete(dimensions);
  }

  void fail(String localPath, Object error) {
    _nextPending(localPath).completeError(error);
  }

  void completeCall(
    String localPath,
    int callIndex,
    AttachmentImageDimensions? dimensions,
  ) {
    _completers[localPath]![callIndex].complete(dimensions);
  }

  Completer<AttachmentImageDimensions?> _nextPending(String localPath) {
    return _completers[localPath]!.firstWhere(
      (completer) => !completer.isCompleted,
    );
  }
}

class _DelayFirstConditionalAttachmentCache implements AttachmentCacheService {
  _DelayFirstConditionalAttachmentCache(this.delegate);

  final AttachmentCacheService delegate;
  final Completer<void> firstConditionalStarted = Completer<void>();
  final Completer<void> releaseFirstConditional = Completer<void>();
  int _conditionalCalls = 0;

  @override
  Future<String?> cacheLocalSource({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required String sourcePath,
  }) {
    return delegate.cacheLocalSource(
      messageId: messageId,
      attachmentId: attachmentId,
      filename: filename,
      mimeType: mimeType,
      sourcePath: sourcePath,
    );
  }

  @override
  Future<String> cacheDownloadedBytes({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) {
    return delegate.cacheDownloadedBytes(
      messageId: messageId,
      attachmentId: attachmentId,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
    );
  }

  @override
  Future<String?> cacheDownloadedBytesIfCurrent({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    required bool Function() isCurrent,
  }) async {
    _conditionalCalls += 1;
    if (_conditionalCalls == 1) {
      firstConditionalStarted.complete();
      await releaseFirstConditional.future;
    }
    return delegate.cacheDownloadedBytesIfCurrent(
      messageId: messageId,
      attachmentId: attachmentId,
      filename: filename,
      mimeType: mimeType,
      bytes: bytes,
      isCurrent: isCurrent,
    );
  }

  @override
  Future<String?> lookup({
    required String messageId,
    required String attachmentId,
  }) {
    return delegate.lookup(messageId: messageId, attachmentId: attachmentId);
  }
}
