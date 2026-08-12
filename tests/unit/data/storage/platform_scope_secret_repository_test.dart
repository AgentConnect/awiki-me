import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_envelope.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS and Windows select the shared MethodChannel store', () {
    expect(
      platformScopeSecretStore(targetPlatform: TargetPlatform.macOS),
      isA<MethodChannelScopeSecretPlatformStore>(),
    );
    expect(
      platformScopeSecretStore(targetPlatform: TargetPlatform.windows),
      isA<MethodChannelScopeSecretPlatformStore>(),
    );
    expect(
      platformScopeSecretStore(targetPlatform: TargetPlatform.android),
      isA<FlutterSecureScopeSecretPlatformStore>(),
    );
    expect(
      platformScopeSecretStore(targetPlatform: TargetPlatform.linux),
      isA<UnsupportedScopeSecretPlatformStore>(),
    );
  });

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

  test('MethodChannel error codes map to stable repository failures', () async {
    final scope = StorageScopeId.generate();
    final expected = <String, ScopeSecretFailure>{
      'scope_secret_already_exists': ScopeSecretFailure.alreadyExists,
      'scope_secret_revision_conflict': ScopeSecretFailure.revisionConflict,
      'scope_secret_access_denied': ScopeSecretFailure.accessDenied,
      'scope_secret_corrupt': ScopeSecretFailure.corrupt,
      'scope_secret_provider_unavailable':
          ScopeSecretFailure.providerUnavailable,
      'scope_secret_platform_unsupported': ScopeSecretFailure.unsupported,
      'unexpected_native_error': ScopeSecretFailure.operationFailed,
    };

    for (final entry in expected.entries) {
      final store = _MemoryPlatformStore()
        ..createError = PlatformException(code: entry.key);
      final repository = PlatformScopeSecretRepository(
        channel: ScopeSecretChannel.production,
        platformStore: store,
      );
      await expectLater(
        repository.createExclusive(_record(scope)),
        throwsA(_failure(entry.value)),
        reason: entry.key,
      );
    }
  });

  test(
    'MethodChannel store preserves method names and CAS arguments',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('test.awiki/scope-secret');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'readScopeSecret') {
              return 'encoded';
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      const store = MethodChannelScopeSecretPlatformStore(channel: channel);

      expect(
        await store.read(service: 'service', account: 'scope/id'),
        'encoded',
      );
      await store.compareAndReplace(
        service: 'service',
        account: 'scope/id',
        expectedRevision: 4,
        value: 'replacement',
      );

      expect(calls.map((call) => call.method), <String>[
        'readScopeSecret',
        'compareAndReplaceScopeSecret',
      ]);
      expect(calls.last.arguments, <String, Object?>{
        'service': 'service',
        'account': 'scope/id',
        'expected_revision': 4,
        'value': 'replacement',
      });
    },
  );

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

  test(
    'Android scope secrets migrate valid v9 envelope to isolated v10 storage',
    () async {
      final scope = StorageScopeId.generate();
      final account = 'scope/${scope.value}';
      final encoded = _record(scope).envelope.encode();
      final secureStorage = _CapturingSecureStorage()
        ..seed(
          namespace: 'awiki_me_scope_secrets',
          key: account,
          value: encoded,
        );
      final store = FlutterSecureScopeSecretPlatformStore(
        storage: secureStorage,
        isAndroid: true,
      );

      expect(
        await store.read(
          service: 'ai.awiki.awikime.dev.scope-secrets',
          account: account,
        ),
        encoded,
      );
      expect(
        secureStorage.value('awiki_me_scope_secrets_v1', account),
        encoded,
      );
      expect(secureStorage.value('awiki_me_scope_secrets', account), encoded);
      expect(secureStorage.calls.map((call) => call.$1), <String>[
        'read:awiki_me_scope_secrets_v1',
        'read:awiki_me_scope_secrets',
        'write:awiki_me_scope_secrets_v1',
        'read:awiki_me_scope_secrets_v1',
      ]);

      final targetOptions = secureStorage.calls.first.$2;
      expect(targetOptions['resetOnError'], 'false');
      expect(targetOptions['migrateWithBackup'], 'true');
      expect(targetOptions['storageNamespace'], 'awiki_me_scope_secrets_v1');
      expect(targetOptions['sharedPreferencesName'], isEmpty);
      expect(targetOptions['preferencesKeyPrefix'], 'awiki_scope_');

      final legacyOptions = secureStorage.calls[1].$2;
      expect(legacyOptions['encryptedSharedPreferences'], 'true');
      expect(legacyOptions['resetOnError'], 'false');
      expect(legacyOptions['migrateOnAlgorithmChange'], 'false');
      expect(legacyOptions['migrateWithBackup'], 'false');
      expect(legacyOptions['sharedPreferencesName'], 'awiki_me_scope_secrets');
      expect(legacyOptions['preferencesKeyPrefix'], 'awiki_scope_');
    },
  );

  test(
    'Android scope migration rejects corrupt source without writing target',
    () async {
      final scope = StorageScopeId.generate();
      final account = 'scope/${scope.value}';
      final secureStorage = _CapturingSecureStorage()
        ..seed(
          namespace: 'awiki_me_scope_secrets',
          key: account,
          value: '{broken',
        );
      final store = FlutterSecureScopeSecretPlatformStore(
        storage: secureStorage,
        isAndroid: true,
      );

      await expectLater(
        store.read(
          service: 'ai.awiki.awikime.dev.scope-secrets',
          account: account,
        ),
        throwsA(_failure(ScopeSecretFailure.corrupt)),
      );
      expect(secureStorage.value('awiki_me_scope_secrets', account), '{broken');
      expect(secureStorage.value('awiki_me_scope_secrets_v1', account), isNull);
      expect(secureStorage.calls.map((call) => call.$1), <String>[
        'read:awiki_me_scope_secrets_v1',
        'read:awiki_me_scope_secrets',
      ]);
    },
  );

  test(
    'Android scope read-back mismatch reports corrupt and preserves v9 source',
    () async {
      final scope = StorageScopeId.generate();
      final account = 'scope/${scope.value}';
      final encoded = _record(scope).envelope.encode();
      final secureStorage = _CapturingSecureStorage()
        ..mismatchTargetReadBack = true
        ..seed(
          namespace: 'awiki_me_scope_secrets',
          key: account,
          value: encoded,
        );
      final store = FlutterSecureScopeSecretPlatformStore(
        storage: secureStorage,
        isAndroid: true,
      );

      await expectLater(
        store.read(
          service: 'ai.awiki.awikime.dev.scope-secrets',
          account: account,
        ),
        throwsA(_failure(ScopeSecretFailure.corrupt)),
      );
      expect(secureStorage.value('awiki_me_scope_secrets', account), encoded);
      expect(secureStorage.value('awiki_me_scope_secrets_v1', account), isNull);
    },
  );

  test(
    'Android CAS migrates v9 revision then commits exact next revision',
    () async {
      final scope = StorageScopeId.generate();
      final account = 'scope/${scope.value}';
      final first = _record(scope);
      final second = ScopeSecretRecord(envelope: first.envelope.nextRevision());
      final secureStorage = _CapturingSecureStorage()
        ..seed(
          namespace: 'awiki_me_scope_secrets',
          key: account,
          value: first.envelope.encode(),
        );
      final store = FlutterSecureScopeSecretPlatformStore(
        storage: secureStorage,
        isAndroid: true,
      );

      await store.compareAndReplace(
        service: 'ai.awiki.awikime.dev.scope-secrets',
        account: account,
        expectedRevision: 1,
        value: second.envelope.encode(),
      );

      final stored = secureStorage.value('awiki_me_scope_secrets_v1', account);
      expect(stored, isNotNull);
      expect(
        ScopeSecretEnvelope.decodeForScope(
          expectedScopeId: scope,
          encoded: stored!,
        ).revision,
        2,
      );
      expect(
        secureStorage.value('awiki_me_scope_secrets', account),
        first.envelope.encode(),
      );
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
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
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

class _CapturingSecureStorage extends FlutterSecureStorage {
  final Map<String, Map<String, String>> _values =
      <String, Map<String, String>>{};
  final List<(String, Map<String, String>)> calls =
      <(String, Map<String, String>)>[];
  final Set<String> _writtenTargetKeys = <String>{};
  bool mismatchTargetReadBack = false;

  void seed({
    required String namespace,
    required String key,
    required String value,
  }) {
    (_values[namespace] ??= <String, String>{})[key] = value;
  }

  String? value(String namespace, String key) => _values[namespace]?[key];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final options = aOptions!.toMap();
    final namespace = _namespace(options);
    calls.add(('read:$namespace', options));
    if (mismatchTargetReadBack &&
        namespace == 'awiki_me_scope_secrets_v1' &&
        _writtenTargetKeys.contains(key)) {
      return 'mismatched-target';
    }
    return _values[namespace]?[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final options = aOptions!.toMap();
    final namespace = _namespace(options);
    calls.add(('write:$namespace', options));
    (_values[namespace] ??= <String, String>{})[key] = value!;
    if (namespace == 'awiki_me_scope_secrets_v1') {
      _writtenTargetKeys.add(key);
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final options = aOptions!.toMap();
    final namespace = _namespace(options);
    calls.add(('delete:$namespace', options));
    _values[namespace]?.remove(key);
    if (namespace == 'awiki_me_scope_secrets_v1') {
      _writtenTargetKeys.remove(key);
    }
  }

  String _namespace(Map<String, String> options) {
    final target = options['storageNamespace']!;
    return target.isNotEmpty ? target : options['sharedPreferencesName']!;
  }
}
