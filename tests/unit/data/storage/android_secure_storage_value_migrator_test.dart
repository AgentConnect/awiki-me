import 'package:awiki_me/src/data/storage/android_secure_storage_value_migrator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const target = AndroidOptions(
    resetOnError: false,
    storageNamespace: 'target_v1',
  );
  const legacy = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: false,
    // ignore: deprecated_member_use
    sharedPreferencesName: 'legacy_v9',
  );

  AndroidSecureStorageValueMigrator migrator(_MemorySecureStorage storage) =>
      AndroidSecureStorageValueMigrator(
        storage: storage,
        targetOptions: target,
        legacyOptions: legacy,
        verificationFailure: () => StateError('migration_verify_failed'),
      );

  test('target-first read never opens or deletes the v9 source', () async {
    final storage = _MemorySecureStorage()
      ..put(target, 'key', 'current-value')
      ..put(legacy, 'key', 'legacy-value');

    expect(await migrator(storage).readAndMigrate(key: 'key'), 'current-value');
    expect(storage.operations, <String>['read:target_v1:key']);
    expect(storage.value(legacy, 'key'), 'legacy-value');
  });

  test(
    'verified migration adopts target and preserves encrypted v9 source',
    () async {
      final storage = _MemorySecureStorage()
        ..put(legacy, 'key', 'legacy-value');

      expect(
        await migrator(storage).readAndMigrate(key: 'key'),
        'legacy-value',
      );
      expect(storage.value(target, 'key'), 'legacy-value');
      expect(storage.value(legacy, 'key'), 'legacy-value');
      expect(storage.operations, <String>[
        'read:target_v1:key',
        'read:legacy_v9:key',
        'write:target_v1:key',
        'read:target_v1:key',
      ]);
    },
  );

  test(
    'legacy validation failure preserves source and leaves target empty',
    () async {
      final storage = _MemorySecureStorage()
        ..put(legacy, 'key', 'invalid-value');

      await expectLater(
        migrator(storage).readAndMigrate(
          key: 'key',
          validateLegacyValue: (_) => throw const FormatException('invalid'),
        ),
        throwsFormatException,
      );
      expect(storage.value(legacy, 'key'), 'invalid-value');
      expect(storage.value(target, 'key'), isNull);
      expect(storage.operations, <String>[
        'read:target_v1:key',
        'read:legacy_v9:key',
      ]);
    },
  );

  test('target write failure preserves the v9 source', () async {
    final storage = _MemorySecureStorage()
      ..put(legacy, 'key', 'legacy-value')
      ..writeErrors['target_v1'] = StateError('write-failed');

    await expectLater(
      migrator(storage).readAndMigrate(key: 'key'),
      throwsStateError,
    );
    expect(storage.value(legacy, 'key'), 'legacy-value');
    expect(storage.value(target, 'key'), isNull);
    expect(storage.operations.last, 'delete:target_v1:key');
  });

  test(
    'read-back mismatch removes the new target and preserves source',
    () async {
      final storage = _MemorySecureStorage()
        ..put(legacy, 'key', 'legacy-value')
        ..readOverrides['target_v1'] = <String?>[null, 'wrong-value'];

      await expectLater(
        migrator(storage).readAndMigrate(key: 'key'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'code',
            'migration_verify_failed',
          ),
        ),
      );
      expect(storage.value(legacy, 'key'), 'legacy-value');
      expect(storage.value(target, 'key'), isNull);
      expect(storage.operations.last, 'delete:target_v1:key');
    },
  );

  test(
    'fresh target write never initializes or deletes the v9 source',
    () async {
      final storage = _MemorySecureStorage();

      await migrator(storage).writeVerified(key: 'key', value: 'new-value');

      expect(storage.value(target, 'key'), 'new-value');
      expect(storage.operations, <String>[
        'write:target_v1:key',
        'read:target_v1:key',
      ]);
    },
  );

  test(
    'explicit delete stops before target deletion when source fails',
    () async {
      final storage = _MemorySecureStorage()
        ..put(target, 'key', 'current-value')
        ..put(legacy, 'key', 'legacy-value')
        ..deleteErrors['legacy_v9'] = StateError('source-delete-failed');

      await expectLater(
        migrator(storage).deleteBoth(key: 'key'),
        throwsStateError,
      );
      expect(storage.value(target, 'key'), 'current-value');
      expect(storage.value(legacy, 'key'), 'legacy-value');
      expect(storage.operations, <String>['delete:legacy_v9:key']);
    },
  );

  test(
    'App and Scope migrations share one process-wide critical section',
    () async {
      final storage =
          _MemorySecureStorage(delay: const Duration(milliseconds: 5))
            ..put(legacy, 'app-key', 'app-value')
            ..put(legacy, 'scope-key', 'scope-value');
      final first = migrator(storage);
      final second = migrator(storage);

      await Future.wait(<Future<String?>>[
        first.readAndMigrate(key: 'app-key'),
        second.readAndMigrate(key: 'scope-key'),
      ]);

      expect(storage.maximumConcurrentOperations, 1);
      expect(storage.value(target, 'app-key'), 'app-value');
      expect(storage.value(target, 'scope-key'), 'scope-value');
    },
  );
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage({this.delay = Duration.zero});

  final Duration delay;
  final Map<String, Map<String, String>> _values =
      <String, Map<String, String>>{};
  final Map<String, Object> writeErrors = <String, Object>{};
  final Map<String, Object> deleteErrors = <String, Object>{};
  final Map<String, List<String?>> readOverrides = <String, List<String?>>{};
  final List<String> operations = <String>[];
  int _concurrentOperations = 0;
  int maximumConcurrentOperations = 0;

  void put(AndroidOptions options, String key, String value) {
    (_values[_namespace(options)] ??= <String, String>{})[key] = value;
  }

  String? value(AndroidOptions options, String key) =>
      _values[_namespace(options)]?[key];

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _operation(() {
    final namespace = _namespace(aOptions!);
    operations.add('read:$namespace:$key');
    final overrides = readOverrides[namespace];
    if (overrides != null && overrides.isNotEmpty) {
      return overrides.removeAt(0);
    }
    return _values[namespace]?[key];
  });

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
  }) => _operation(() {
    final namespace = _namespace(aOptions!);
    operations.add('write:$namespace:$key');
    final error = writeErrors[namespace];
    if (error != null) throw error;
    (_values[namespace] ??= <String, String>{})[key] = value!;
  });

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => _operation(() {
    final namespace = _namespace(aOptions!);
    operations.add('delete:$namespace:$key');
    final error = deleteErrors[namespace];
    if (error != null) throw error;
    _values[namespace]?.remove(key);
  });

  Future<T> _operation<T>(T Function() action) async {
    _concurrentOperations += 1;
    maximumConcurrentOperations =
        maximumConcurrentOperations < _concurrentOperations
        ? _concurrentOperations
        : maximumConcurrentOperations;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return action();
    } finally {
      _concurrentOperations -= 1;
    }
  }

  String _namespace(AndroidOptions options) {
    final map = options.toMap();
    final target = map['storageNamespace']!;
    if (target.isNotEmpty) return target;
    return map['sharedPreferencesName']!;
  }
}
