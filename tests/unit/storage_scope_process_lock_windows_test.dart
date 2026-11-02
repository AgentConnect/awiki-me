import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/data/storage/storage_scope_provisioner.dart';

void main() {
  test('scope lock closes after a protected action fails', () async {
    final directory = await Directory.systemTemp.createTemp('awiki-scope-lock-action-test-');
    final file = File('${directory.path}/registry.lock');
    try {
      await expectLater(
        StorageScopeProcessLock(file.path).synchronized(() async {
          throw StateError('synthetic action failure');
        }),
        throwsStateError,
      );
      await file.delete();
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test('failed Windows scope lock acquisition releases its file handle', () async {
    final directory = await Directory.systemTemp.createTemp('awiki-scope-lock-test-');
    final file = File('${directory.path}/registry.lock');
    final holder = await file.open(mode: FileMode.append);
    var holderClosed = false;
    try {
      await holder.lock(FileLock.exclusive);
      var actionStarted = false;
      await expectLater(
        StorageScopeProcessLock(file.path).synchronized(() async {
          actionStarted = true;
        }),
        throwsA(isA<FileSystemException>()),
      );
      expect(actionStarted, isFalse);
      await holder.unlock();
      await holder.close();
      holderClosed = true;
      // Windows refuses deletion while even an unlocked leaked handle is open.
      await file.delete();
    } finally {
      if (!holderClosed) {
        await holder.unlock();
        await holder.close();
      }
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isWindows);
}
