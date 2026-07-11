import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../application/tenant/app_tenant.dart';
import 'scope_secret_envelope.dart';
import 'scope_secret_repository.dart';

enum ScopeSecretChannel { production, development }

extension on ScopeSecretChannel {
  String get service => switch (this) {
    ScopeSecretChannel.production => 'ai.awiki.awikime.scope-secrets',
    ScopeSecretChannel.development => 'ai.awiki.awikime.dev.scope-secrets',
  };
}

abstract interface class ScopeSecretPlatformStore {
  Future<String?> read({required String service, required String account});
  Future<void> createExclusive({
    required String service,
    required String account,
    required String value,
  });
  Future<void> compareAndReplace({
    required String service,
    required String account,
    required int expectedRevision,
    required String value,
  });
  Future<void> delete({required String service, required String account});
}

class PlatformScopeSecretRepository implements ScopeSecretRepository {
  PlatformScopeSecretRepository({
    required ScopeSecretChannel channel,
    ScopeSecretPlatformStore? platformStore,
  }) : _service = channel.service,
       _store = platformStore ?? platformScopeSecretStore();

  factory PlatformScopeSecretRepository.forCurrentBuild({
    ScopeSecretPlatformStore? platformStore,
  }) => PlatformScopeSecretRepository(
    channel: kReleaseMode
        ? ScopeSecretChannel.production
        : ScopeSecretChannel.development,
    platformStore: platformStore,
  );

  final String _service;
  final ScopeSecretPlatformStore _store;

  static String accountFor(StorageScopeId scopeId) => 'scope/${scopeId.value}';

  @override
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId) async {
    final String? encoded;
    try {
      encoded = await _store.read(
        service: _service,
        account: accountFor(scopeId),
      );
    } on Object catch (error) {
      return ScopeSecretReadResult(_readStatusFor(error));
    }
    if (encoded == null) {
      return const ScopeSecretReadResult(ScopeSecretReadStatus.missing);
    }
    try {
      return ScopeSecretReadResult(
        ScopeSecretReadStatus.present,
        record: ScopeSecretRecord(
          envelope: ScopeSecretEnvelope.decodeForScope(
            expectedScopeId: scopeId,
            encoded: encoded,
          ),
        ),
      );
    } on FormatException {
      return const ScopeSecretReadResult(ScopeSecretReadStatus.corrupt);
    }
  }

  @override
  Future<void> createExclusive(ScopeSecretRecord record) async {
    try {
      await _store.createExclusive(
        service: _service,
        account: accountFor(record.scopeId),
        value: record.envelope.encode(),
      );
    } on Object catch (error) {
      throw _operationException(error);
    }
  }

  @override
  Future<void> compareAndReplace({
    required ScopeSecretRecord record,
    required int expectedRevision,
  }) async {
    if (expectedRevision < 1 ||
        record.envelope.revision != expectedRevision + 1) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    try {
      await _store.compareAndReplace(
        service: _service,
        account: accountFor(record.scopeId),
        expectedRevision: expectedRevision,
        value: record.envelope.encode(),
      );
    } on Object catch (error) {
      throw _operationException(error);
    }
  }

  @override
  Future<void> delete(StorageScopeId scopeId) async {
    try {
      await _store.delete(service: _service, account: accountFor(scopeId));
    } on Object catch (error) {
      throw _operationException(error);
    }
  }
}

ScopeSecretPlatformStore platformScopeSecretStore() {
  if (Platform.isMacOS) return const MacOsScopeSecretPlatformStore();
  if (Platform.isIOS || Platform.isAndroid) {
    return FlutterSecureScopeSecretPlatformStore();
  }
  return const UnsupportedScopeSecretPlatformStore();
}

class MacOsScopeSecretPlatformStore implements ScopeSecretPlatformStore {
  const MacOsScopeSecretPlatformStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.awiki.awikime/scope_secret';
  final MethodChannel _channel;

  @override
  Future<String?> read({required String service, required String account}) =>
      _channel.invokeMethod<String>('readScopeSecret', <String, Object?>{
        'service': service,
        'account': account,
      });

  @override
  Future<void> createExclusive({
    required String service,
    required String account,
    required String value,
  }) => _channel.invokeMethod<void>(
    'createScopeSecretExclusive',
    <String, Object?>{'service': service, 'account': account, 'value': value},
  );

  @override
  Future<void> compareAndReplace({
    required String service,
    required String account,
    required int expectedRevision,
    required String value,
  }) => _channel
      .invokeMethod<void>('compareAndReplaceScopeSecret', <String, Object?>{
        'service': service,
        'account': account,
        'expected_revision': expectedRevision,
        'value': value,
      });

  @override
  Future<void> delete({required String service, required String account}) =>
      _channel.invokeMethod<void>('deleteScopeSecret', <String, Object?>{
        'service': service,
        'account': account,
      });
}

/// iOS uses a device-only, non-synchronizable Keychain item. Android uses the
/// Keystore-backed encrypted preferences implementation with reset-on-error
/// disabled so a decryption failure cannot silently erase a vault root key.
/// Calls are serialized in-process because these plugin APIs do not expose CAS.
class FlutterSecureScopeSecretPlatformStore
    implements ScopeSecretPlatformStore {
  FlutterSecureScopeSecretPlatformStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static Future<void> _sharedPending = Future<void>.value();

  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: false,
    sharedPreferencesName: 'awiki_me_scope_secrets',
    preferencesKeyPrefix: 'awiki_scope_',
  );

  IOSOptions _iosOptions(String service) => IOSOptions(
    accountName: service,
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  @override
  Future<String?> read({required String service, required String account}) =>
      _serialized(() {
        _validatedScope(service, account);
        return _storage.read(
          key: account,
          iOptions: _iosOptions(service),
          aOptions: _androidOptions,
        );
      });

  @override
  Future<void> createExclusive({
    required String service,
    required String account,
    required String value,
  }) => _serialized(() async {
    final scope = _validatedScope(service, account);
    final envelope = _decode(scope, value);
    if (envelope.revision != 1) {
      throw const ScopeSecretException(ScopeSecretFailure.corrupt);
    }
    final existing = await _storage.read(
      key: account,
      iOptions: _iosOptions(service),
      aOptions: _androidOptions,
    );
    if (existing != null) {
      throw const ScopeSecretException(ScopeSecretFailure.alreadyExists);
    }
    await _storage.write(
      key: account,
      value: value,
      iOptions: _iosOptions(service),
      aOptions: _androidOptions,
    );
  });

  @override
  Future<void> compareAndReplace({
    required String service,
    required String account,
    required int expectedRevision,
    required String value,
  }) => _serialized(() async {
    final scope = _validatedScope(service, account);
    final replacement = _decode(scope, value);
    if (replacement.revision != expectedRevision + 1) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    final existing = await _storage.read(
      key: account,
      iOptions: _iosOptions(service),
      aOptions: _androidOptions,
    );
    if (existing == null) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    final current = _decode(scope, existing);
    if (current.revision != expectedRevision) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    await _storage.write(
      key: account,
      value: value,
      iOptions: _iosOptions(service),
      aOptions: _androidOptions,
    );
  });

  @override
  Future<void> delete({required String service, required String account}) =>
      _serialized(() {
        _validatedScope(service, account);
        return _storage.delete(
          key: account,
          iOptions: _iosOptions(service),
          aOptions: _androidOptions,
        );
      });

  StorageScopeId _validatedScope(String service, String account) {
    final expectedService = kReleaseMode
        ? ScopeSecretChannel.production.service
        : ScopeSecretChannel.development.service;
    if (service != expectedService || !account.startsWith('scope/')) {
      throw const ScopeSecretException(ScopeSecretFailure.operationFailed);
    }
    try {
      return StorageScopeId.parse(account.substring('scope/'.length));
    } on FormatException {
      throw const ScopeSecretException(ScopeSecretFailure.operationFailed);
    }
  }

  ScopeSecretEnvelope _decode(StorageScopeId scope, String encoded) {
    try {
      return ScopeSecretEnvelope.decodeForScope(
        expectedScopeId: scope,
        encoded: encoded,
      );
    } on FormatException {
      throw const ScopeSecretException(ScopeSecretFailure.corrupt);
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _sharedPending = _sharedPending.then((_) async {
      try {
        completer.complete(await action());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class UnsupportedScopeSecretPlatformStore implements ScopeSecretPlatformStore {
  const UnsupportedScopeSecretPlatformStore();

  @override
  Future<String?> read({required String service, required String account}) =>
      _unsupported<String?>();
  @override
  Future<void> createExclusive({
    required String service,
    required String account,
    required String value,
  }) => _unsupported<void>();
  @override
  Future<void> compareAndReplace({
    required String service,
    required String account,
    required int expectedRevision,
    required String value,
  }) => _unsupported<void>();
  @override
  Future<void> delete({required String service, required String account}) =>
      _unsupported<void>();

  Future<T> _unsupported<T>() => Future<T>.error(
    const ScopeSecretException(ScopeSecretFailure.unsupported),
  );
}

ScopeSecretReadStatus _readStatusFor(Object error) {
  final failure = _failureFor(error);
  return switch (failure) {
    ScopeSecretFailure.accessDenied => ScopeSecretReadStatus.accessDenied,
    ScopeSecretFailure.corrupt => ScopeSecretReadStatus.corrupt,
    ScopeSecretFailure.unsupported => ScopeSecretReadStatus.unsupported,
    ScopeSecretFailure.providerUnavailable =>
      ScopeSecretReadStatus.providerUnavailable,
    _ => ScopeSecretReadStatus.providerUnavailable,
  };
}

ScopeSecretException _operationException(Object error) =>
    ScopeSecretException(_failureFor(error));

ScopeSecretFailure _failureFor(Object error) {
  if (error is ScopeSecretException) return error.failure;
  if (error is MissingPluginException) {
    return ScopeSecretFailure.providerUnavailable;
  }
  if (error is PlatformException) {
    return switch (error.code) {
      'scope_secret_already_exists' => ScopeSecretFailure.alreadyExists,
      'scope_secret_revision_conflict' => ScopeSecretFailure.revisionConflict,
      'scope_secret_access_denied' => ScopeSecretFailure.accessDenied,
      'scope_secret_corrupt' => ScopeSecretFailure.corrupt,
      'scope_secret_provider_unavailable' =>
        ScopeSecretFailure.providerUnavailable,
      'scope_secret_platform_unsupported' => ScopeSecretFailure.unsupported,
      _ => ScopeSecretFailure.operationFailed,
    };
  }
  return ScopeSecretFailure.operationFailed;
}
