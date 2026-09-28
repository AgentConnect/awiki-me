import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/key_value_active_session_store.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

final badDecrypt = PlatformException(
  code: 'Exception encountered',
  message: 'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
  details: 'javax.crypto.BadPaddingException: test-only',
);
const scope = '55555555-5555-4555-8555-555555555555';
const activeKey = 'awiki_me_active_identity.scope.$scope';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'damaged legacy selection returns to chooser; explicit selection persists across store instances',
    () async {
      final storage = _BrokenLegacyStorage();
      KeyValueActiveSessionStore selection() => KeyValueActiveSessionStore(
        storage: SecureAppKeyValueStore(
          secureStorage: storage,
          isAndroid: true,
        ),
        scopeId: StorageScopeId.parse(scope),
      );
      expect(await selection().readActiveIdentityId(), isNull);
      expect(storage.writes, isEmpty);
      expect(storage.deletes, isEmpty);
      await selection().writeActiveIdentityId('existing-identity');
      final readsBeforeRestart = storage.legacyReads;
      expect(await selection().readActiveIdentityId(), 'existing-identity');
      expect(storage.legacyReads, readsBeforeRestart);
      expect(storage.writes, [activeKey]);
      expect(storage.deletes, isEmpty);
    },
  );

  final hash = 'a' * 64;
  for (final key in [
    'awiki_me_locale_mode',
    'awiki_me_display_scale_v1',
    'awiki_me_update_${hash}_${hash}_awiki-me_stable_policy_v1',
    'awiki_me_update_${hash}_preferred_official_source',
    'sms_otp_cooldown_retry_at_v1.dGVzdA',
    'sms_otp_cooldown_retry_at_v1.handle_recovery.dGVzdA',
  ]) {
    test('replaceable legacy state can be rebuilt: $key', () async {
      final storage = _BrokenLegacyStorage();
      final store = SecureAppKeyValueStore(
        secureStorage: storage,
        isAndroid: true,
      );
      expect(await store.read(key: key), isNull);
      expect(storage.writes, isEmpty);
      expect(storage.deletes, isEmpty);
    });
  }

  for (final key in [
    'session_token',
    'scope/$scope',
    'root_key_b64',
    'awiki_me_active_identity.scope.invalid',
    'awiki_me_update_unknown_secret',
  ]) {
    test('unknown or secret state still fails closed: $key', () async {
      final storage = _BrokenLegacyStorage();
      final store = SecureAppKeyValueStore(
        secureStorage: storage,
        isAndroid: true,
      );
      await expectLater(store.read(key: key), throwsA(same(badDecrypt)));
      expect(storage.writes, isEmpty);
      expect(storage.deletes, isEmpty);
    });
  }

  test(
    'corruption in the current namespace is never treated as absent',
    () async {
      final storage = _BrokenLegacyStorage()..targetError = badDecrypt;
      final store = SecureAppKeyValueStore(
        secureStorage: storage,
        isAndroid: true,
      );
      await expectLater(store.read(key: activeKey), throwsA(same(badDecrypt)));
      expect(storage.legacyReads, 0);
    },
  );

  for (final error in [
    PlatformException(code: 'access_denied', message: 'BAD_DECRYPT'),
    PlatformException(
      code: 'Exception encountered',
      message: 'storage unavailable',
    ),
    StateError('BAD_DECRYPT'),
  ]) {
    test(
      'unrelated legacy failure propagates: ${error.runtimeType} $error',
      () async {
        final storage = _BrokenLegacyStorage()..legacyError = error;
        final store = SecureAppKeyValueStore(
          secureStorage: storage,
          isAndroid: true,
        );
        await expectLater(store.read(key: activeKey), throwsA(same(error)));
        expect(storage.deletes, isEmpty);
      },
    );
  }

  test(
    'failed verified replacement does not claim a repaired selection',
    () async {
      final storage = _BrokenLegacyStorage()..writeError = badDecrypt;
      final store = SecureAppKeyValueStore(
        secureStorage: storage,
        isAndroid: true,
      );
      expect(await store.read(key: activeKey), isNull);
      await expectLater(
        store.write(key: activeKey, value: 'existing-identity'),
        throwsA(same(badDecrypt)),
      );
      expect(storage.target, isEmpty);
    },
  );

  test('Scope-secret adapter never applies App-state recovery', () async {
    final storage = _BrokenLegacyStorage();
    final scopes = FlutterSecureScopeSecretPlatformStore(
      storage: storage,
      isAndroid: true,
    );
    await expectLater(
      scopes.read(
        service: 'ai.awiki.awikime.dev.scope-secrets',
        account: 'scope/$scope',
      ),
      throwsA(same(badDecrypt)),
    );
    expect(storage.writes, isEmpty);
    expect(storage.deletes, isEmpty);
  });
}

class _BrokenLegacyStorage extends FlutterSecureStorage {
  final target = <String, String>{};
  final writes = <String>[];
  final deletes = <String>[];
  Object legacyError = badDecrypt;
  Object? targetError;
  Object? writeError;
  int legacyReads = 0;

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
    if (aOptions!.toMap()['storageNamespace']!.isNotEmpty) {
      if (targetError case final error?) throw error;
      return target[key];
    }
    legacyReads++;
    throw legacyError;
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
    if (writeError case final error?) throw error;
    expect(aOptions!.toMap()['storageNamespace'], 'awiki_me_app_state_v1');
    writes.add(key);
    target[key] = value!;
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
    deletes.add(key);
    target.remove(key);
  }
}
