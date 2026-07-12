import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'production and development use fixed disjoint services and scope account',
    () async {
      final scope = StorageScopeId.generate();
      final store = _MemoryPlatformStore();
      final production = PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.production,
        platformStore: store,
      );
      final development = PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.development,
        platformStore: store,
      );

      await production.readExisting(scope);
      expect(store.lastService, 'ai.awiki.awikime.scope-secrets');
      expect(store.lastAccount, 'scope/${scope.value}');
      await development.readExisting(scope);
      expect(store.lastService, 'ai.awiki.awikime.dev.scope-secrets');
      expect(store.lastAccount, 'scope/${scope.value}');
    },
  );

  test(
    'read fails closed for missing, denied, plugin missing, corrupt and mismatch',
    () async {
      final scope = StorageScopeId.generate();
      final store = _MemoryPlatformStore();
      final repository = PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.production,
        platformStore: store,
      );

      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.missing,
      );
      store.readError = PlatformException(code: 'scope_secret_access_denied');
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.accessDenied,
      );
      store.readError = MissingPluginException();
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.providerUnavailable,
      );
      store.readError = null;
      store.value = '{broken';
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.corrupt,
      );
      store.value = _record(StorageScopeId.generate()).envelope.encode();
      expect(
        (await repository.readExisting(scope)).status,
        ScopeSecretReadStatus.scopeMismatch,
      );
    },
  );

  test(
    'exclusive create never overwrites and CAS requires exact next revision',
    () async {
      final scope = StorageScopeId.generate();
      final store = _MemoryPlatformStore();
      final repository = PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.production,
        platformStore: store,
      );
      final record = _record(scope);

      await repository.createExclusive(record);
      await expectLater(
        repository.createExclusive(record),
        throwsA(_failure(ScopeSecretFailure.alreadyExists)),
      );
      final next = ScopeSecretRecord(envelope: record.envelope.nextRevision());
      await repository.compareAndReplace(record: next, expectedRevision: 1);
      expect(
        (await repository.readExisting(scope)).record!.envelope.revision,
        2,
      );
      await expectLater(
        repository.compareAndReplace(record: next, expectedRevision: 1),
        throwsA(_failure(ScopeSecretFailure.revisionConflict)),
      );
    },
  );

  test('platform errors expose stable code and never raw envelope', () async {
    final scope = StorageScopeId.generate();
    final store = _MemoryPlatformStore()
      ..createError = PlatformException(
        code: 'scope_secret_access_denied',
        message: 'raw-secret-should-not-escape',
      );
    final repository = PlatformScopeSecretRepository(
      channel: ScopeSecretChannel.production,
      platformStore: store,
    );

    await expectLater(
      repository.createExclusive(_record(scope)),
      throwsA(
        isA<ScopeSecretException>()
            .having(
              (error) => error.failure,
              'failure',
              ScopeSecretFailure.accessDenied,
            )
            .having(
              (error) => error.toString(),
              'redacted error',
              isNot(contains('raw-secret')),
            ),
      ),
    );
  });

  test(
    'flutter secure store serializes operations across repository instances',
    () async {
      final secureStorage = _ContendedSecureStorage();
      final first = FlutterSecureScopeSecretPlatformStore(
        storage: secureStorage,
      );
      final second = FlutterSecureScopeSecretPlatformStore(
        storage: secureStorage,
      );
      final firstScope = StorageScopeId.generate();
      final secondScope = StorageScopeId.generate();

      await Future.wait(<Future<String?>>[
        first.read(
          service: 'ai.awiki.awikime.dev.scope-secrets',
          account: 'scope/${firstScope.value}',
        ),
        second.read(
          service: 'ai.awiki.awikime.dev.scope-secrets',
          account: 'scope/${secondScope.value}',
        ),
      ]);

      expect(secureStorage.maximumConcurrentCalls, 1);
    },
  );
}

ScopeSecretRecord _record(StorageScopeId scope) => ScopeSecretRecord(
  envelope: ScopeSecretEnvelope.create(
    scopeId: scope,
    randomBytes: (_) => Uint8List.fromList(List<int>.filled(32, 7)),
  ),
);

Matcher _failure(ScopeSecretFailure failure) => isA<ScopeSecretException>()
    .having((error) => error.failure, 'failure', failure);

class _MemoryPlatformStore implements ScopeSecretPlatformStore {
  String? value;
  Object? readError;
  Object? createError;
  String? lastService;
  String? lastAccount;

  @override
  Future<String?> read({
    required String service,
    required String account,
  }) async {
    lastService = service;
    lastAccount = account;
    if (readError case final error?) throw error;
    return value;
  }

  @override
  Future<void> createExclusive({
    required String service,
    required String account,
    required String value,
  }) async {
    if (createError case final error?) throw error;
    if (this.value != null) {
      throw const ScopeSecretException(ScopeSecretFailure.alreadyExists);
    }
    this.value = value;
  }

  @override
  Future<void> compareAndReplace({
    required String service,
    required String account,
    required int expectedRevision,
    required String value,
  }) async {
    final scope = StorageScopeId.parse(account.substring('scope/'.length));
    final current = this.value;
    if (current == null ||
        ScopeSecretEnvelope.decodeForScope(
              expectedScopeId: scope,
              encoded: current,
            ).revision !=
            expectedRevision) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
    }
    this.value = value;
  }

  @override
  Future<void> delete({
    required String service,
    required String account,
  }) async {
    value = null;
  }
}

class _ContendedSecureStorage extends FlutterSecureStorage {
  _ContendedSecureStorage();

  int _concurrentCalls = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _concurrentCalls += 1;
    maximumConcurrentCalls = maximumConcurrentCalls < _concurrentCalls
        ? _concurrentCalls
        : maximumConcurrentCalls;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _concurrentCalls -= 1;
    return null;
  }
}
