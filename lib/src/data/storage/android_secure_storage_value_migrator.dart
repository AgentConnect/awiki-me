import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Serializes every Android secure-storage migration across App state and
/// Scope secrets. The v9 backends share legacy KeyStore/key-storage material,
/// so their multi-step reads must never overlap during the v10 cutover.
class AndroidSecureStorageMigrationCoordinator {
  AndroidSecureStorageMigrationCoordinator._();

  static Future<void> _pending = Future<void>.value();

  static Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class AndroidSecureStorageValueMigrator {
  AndroidSecureStorageValueMigrator({
    required FlutterSecureStorage storage,
    required AndroidOptions targetOptions,
    required AndroidOptions legacyOptions,
    required Object Function() verificationFailure,
  }) : _storage = storage,
       _targetOptions = targetOptions,
       _legacyOptions = legacyOptions,
       _verificationFailure = verificationFailure;

  final FlutterSecureStorage _storage;
  final AndroidOptions _targetOptions;
  final AndroidOptions _legacyOptions;
  final Object Function() _verificationFailure;

  Future<String?> readAndMigrate({
    required String key,
    void Function(String value)? validateLegacyValue,
  }) => AndroidSecureStorageMigrationCoordinator.run(() async {
    final target = await _storage.read(key: key, aOptions: _targetOptions);
    if (target != null) {
      return target;
    }

    final legacy = await _storage.read(key: key, aOptions: _legacyOptions);
    if (legacy == null) {
      return null;
    }
    validateLegacyValue?.call(legacy);
    await _writeTargetVerified(key: key, value: legacy, targetWasMissing: true);
    return legacy;
  });

  Future<void> writeVerified({required String key, required String value}) =>
      AndroidSecureStorageMigrationCoordinator.run(() async {
        await _writeTargetVerified(
          key: key,
          value: value,
          targetWasMissing: false,
        );
      });

  Future<void> deleteBoth({
    required String key,
  }) => AndroidSecureStorageMigrationCoordinator.run(() async {
    // Delete the source first. If its backend cannot be opened, preserve the
    // verified target and report failure instead of making deletion partial.
    await _storage.delete(key: key, aOptions: _legacyOptions);
    await _storage.delete(key: key, aOptions: _targetOptions);
  });

  Future<void> _writeTargetVerified({
    required String key,
    required String value,
    required bool targetWasMissing,
  }) async {
    try {
      await _storage.write(key: key, value: value, aOptions: _targetOptions);
      final verified = await _storage.read(key: key, aOptions: _targetOptions);
      if (verified != value) {
        throw _verificationFailure();
      }
    } on Object {
      if (targetWasMissing) {
        try {
          await _storage.delete(key: key, aOptions: _targetOptions);
        } on Object {
          // Keep the original failure. The legacy source remains authoritative;
          // a later target read must still fail closed if cleanup did not work.
        }
      }
      rethrow;
    }
  }
}
