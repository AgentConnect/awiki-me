import 'dart:async';
import 'dart:io';

import '../../application/tenant/app_tenant.dart';
import 'scope_secret_envelope.dart';
import 'scope_secret_repository.dart';

/// Explicit E2E-only provider. It never discovers a default path and therefore
/// cannot accidentally read or write a production platform secure-store item.
class E2eFileScopeSecretRepository implements ScopeSecretRepository {
  E2eFileScopeSecretRepository({required Directory root}) : _root = root;

  final Directory _root;
  static final Map<String, Future<void>> _processQueues =
      <String, Future<void>>{};

  @override
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId) =>
      _synchronized(scopeId, () => _readUnlocked(scopeId));

  @override
  Future<void> createExclusive(ScopeSecretRecord record) =>
      _synchronized(record.scopeId, () async {
        await _ensurePrivateRoot();
        final file = _file(record.scopeId);
        RandomAccessFile? handle;
        try {
          await file.create(exclusive: true);
          await _chmod(file.path, '600');
          handle = await file.open(mode: FileMode.writeOnly);
          await handle.writeString(record.envelope.encode());
          await handle.flush();
          await handle.close();
          handle = null;
          await _chmod(file.path, '600');
        } on PathExistsException {
          throw const ScopeSecretException(ScopeSecretFailure.alreadyExists);
        } on FileSystemException {
          throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
        } finally {
          await handle?.close();
        }
      });

  @override
  Future<void> compareAndReplace({
    required ScopeSecretRecord record,
    required int expectedRevision,
  }) => _synchronized(record.scopeId, () async {
    if (expectedRevision < 1 ||
        record.envelope.revision != expectedRevision + 1) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    final current = await _readUnlocked(record.scopeId);
    if (current.status == ScopeSecretReadStatus.corrupt) {
      throw const ScopeSecretException(ScopeSecretFailure.corrupt);
    }
    if (current.status != ScopeSecretReadStatus.present ||
        current.record!.envelope.revision != expectedRevision) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    await _ensurePrivateRoot();
    final file = _file(record.scopeId);
    final temp = File('${file.path}.tmp.$pid');
    try {
      await temp.create(exclusive: true);
      await _chmod(temp.path, '600');
      final handle = await temp.open(mode: FileMode.writeOnly);
      try {
        await handle.writeString(record.envelope.encode());
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temp.rename(file.path);
      await _chmod(file.path, '600');
    } on ScopeSecretException {
      rethrow;
    } on FileSystemException {
      throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Do not replace the authoritative CAS result with cleanup noise.
      }
    }
  });

  @override
  Future<void> delete(StorageScopeId scopeId) =>
      _synchronized(scopeId, () async {
        final file = _file(scopeId);
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
        }
      });

  Future<ScopeSecretReadResult> _readUnlocked(StorageScopeId scopeId) async {
    final file = _file(scopeId);
    try {
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return const ScopeSecretReadResult(ScopeSecretReadStatus.missing);
      }
      if (type != FileSystemEntityType.file) {
        return const ScopeSecretReadResult(ScopeSecretReadStatus.corrupt);
      }
      if (!await _isPrivate(file.path, file: true)) {
        return const ScopeSecretReadResult(ScopeSecretReadStatus.accessDenied);
      }
      final encoded = await file.readAsString();
      final envelope = ScopeSecretEnvelope.decodeForScope(
        expectedScopeId: scopeId,
        encoded: encoded,
      );
      return ScopeSecretReadResult(
        ScopeSecretReadStatus.present,
        record: ScopeSecretRecord(envelope: envelope),
      );
    } on FormatException catch (error) {
      return ScopeSecretReadResult(switch (error.message) {
        'scope_secret_scope_mismatch' => ScopeSecretReadStatus.scopeMismatch,
        'scope_secret_envelope_schema_unsupported' =>
          ScopeSecretReadStatus.schemaUnsupported,
        _ => ScopeSecretReadStatus.corrupt,
      });
    } on FileSystemException {
      return const ScopeSecretReadResult(ScopeSecretReadStatus.accessDenied);
    }
  }

  Future<T> _synchronized<T>(
    StorageScopeId scopeId,
    Future<T> Function() action,
  ) {
    final completer = Completer<T>();
    final queueKey = '${_root.absolute.path}\u0000${scopeId.value}';
    final previous = _processQueues[queueKey] ?? Future<void>.value();
    late final Future<void> next;
    next = previous.then((_) async {
      try {
        completer.complete(await _withFileLock(scopeId, action));
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_processQueues[queueKey], next)) {
          _processQueues.remove(queueKey);
        }
      }
    });
    _processQueues[queueKey] = next;
    return completer.future;
  }

  Future<T> _withFileLock<T>(
    StorageScopeId scopeId,
    Future<T> Function() action,
  ) async {
    await _ensurePrivateRoot();
    final lock = File('${_root.path}/.${scopeId.value}.lock');
    final lockType = await FileSystemEntity.type(lock.path, followLinks: false);
    if (lockType == FileSystemEntityType.link ||
        (lockType != FileSystemEntityType.notFound &&
            lockType != FileSystemEntityType.file)) {
      throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
    }
    final handle = await lock.open(mode: FileMode.append);
    try {
      await _chmod(lock.path, '600');
      await handle.lock(FileLock.exclusive);
      return await action();
    } on ScopeSecretException {
      rethrow;
    } on FileSystemException {
      throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
    } finally {
      try {
        await handle.unlock();
      } on FileSystemException {
        // The primary result remains authoritative.
      }
      await handle.close();
    }
  }

  Future<void> _ensurePrivateRoot() async {
    final type = await FileSystemEntity.type(_root.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory)) {
      throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
    }
    if (type == FileSystemEntityType.directory &&
        !await _isPrivate(_root.path, file: false)) {
      throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
    }
    await _root.create(recursive: true);
    await _chmod(_root.path, '700');
  }

  File _file(StorageScopeId scopeId) =>
      File('${_root.path}/${scopeId.value}.json');
}

Future<bool> _isPrivate(String path, {required bool file}) async {
  if (!(Platform.isLinux || Platform.isMacOS)) return true;
  final stat = await FileStat.stat(path);
  final permissions = stat.mode & 0x1ff;
  return file ? permissions == 0x180 : permissions == 0x1c0;
}

Future<void> _chmod(String path, String mode) async {
  if (!(Platform.isLinux || Platform.isMacOS)) return;
  final result = await Process.run('chmod', <String>[mode, path]);
  if (result.exitCode != 0) {
    throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
  }
}
