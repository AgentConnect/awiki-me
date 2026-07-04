import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../im_core/awiki_im_core_paths.dart';

abstract class AppKeyValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class SecureAppKeyValueStore implements AppKeyValueStore {
  SecureAppKeyValueStore({
    FlutterSecureStorage? secureStorage,
    MacOsKeychainStorage? macOsKeychainStorage,
    MacOsKeychainAccessRepair? macOsKeychainAccessRepair,
  }) : _secureStorage = secureStorage ?? _defaultSecureStorage(),
       _macOsKeychainStorage =
           macOsKeychainStorage ?? const MacOsKeychainStorage(),
       _macOsKeychainAccessRepair =
           macOsKeychainAccessRepair ?? const MacOsKeychainAccessRepair();

  final FlutterSecureStorage _secureStorage;
  final MacOsKeychainStorage _macOsKeychainStorage;
  final MacOsKeychainAccessRepair _macOsKeychainAccessRepair;

  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage();

  static const FlutterSecureStorage _macOsStorage = FlutterSecureStorage(
    // Legacy fallback for values written by flutter_secure_storage before the
    // app added its own macOS Keychain bridge. New macOS writes go through
    // MacOsKeychainStorage so the Keychain ACL can trust the current executable.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  static final Set<String> _macOsAccessRepairAttemptedKeys = <String>{};

  static FlutterSecureStorage _defaultSecureStorage() {
    if (Platform.isMacOS) {
      return _macOsStorage;
    }
    return _defaultStorage;
  }

  @override
  Future<String?> read({required String key}) async {
    if (Platform.isMacOS) {
      final nativeValue = await _readMacOsNativeValue(key);
      if (nativeValue != null) {
        unawaited(_repairMacOsNativeKeychainAccessIfNeeded(key));
        return nativeValue;
      }
      final legacyValue = await _secureStorage.read(key: key);
      if (legacyValue != null) {
        final migrated = await _migrateLegacyMacOsValue(
          key: key,
          value: legacyValue,
        );
        if (migrated) {
          unawaited(_deleteLegacyMacOsValue(key));
        } else {
          unawaited(_repairLegacyMacOsKeychainAccessIfNeeded(key));
        }
      }
      return legacyValue;
    }
    return _secureStorage.read(key: key);
  }

  Future<String?> _readMacOsNativeValue(String key) async {
    try {
      return await _macOsKeychainStorage.read(key: key);
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _migrateLegacyMacOsValue({
    required String key,
    required String value,
  }) async {
    try {
      await _macOsKeychainStorage.write(key: key, value: value);
      return true;
    } on Object {
      // Preserve the successful legacy read path. A later signed/native App
      // launch can retry the migration without losing the existing secret.
      return false;
    }
  }

  Future<void> _deleteLegacyMacOsValue(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } on Object {
      // Best-effort legacy cleanup. The native item already exists, so future
      // reads should not need to touch the legacy Keychain service.
    }
  }

  Future<void> _repairMacOsNativeKeychainAccessIfNeeded(String key) {
    return _repairMacOsKeychainAccessIfNeeded(
      _macOsKeychainAccessRepair.repairNativeSecureStorageKey,
      key,
    );
  }

  Future<void> _repairLegacyMacOsKeychainAccessIfNeeded(String key) {
    return _repairMacOsKeychainAccessIfNeeded(
      _macOsKeychainAccessRepair.repairFlutterSecureStorageKey,
      key,
    );
  }

  Future<void> _repairMacOsKeychainAccessIfNeeded(
    Future<void> Function(String key) repair,
    String key,
  ) async {
    if (!Platform.isMacOS) {
      return;
    }
    if (!_macOsAccessRepairAttemptedKeys.add(key)) {
      return;
    }
    try {
      await repair(key);
    } on Object {
      // Preserve the successful read path. If repair fails, the stored secret is
      // still available; the user may see the macOS authorization prompt again
      // until the item can be repaired or recreated by a signed build.
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    if (Platform.isMacOS) {
      try {
        await _macOsKeychainStorage.write(key: key, value: value);
        return;
      } on MissingPluginException {
        await _secureStorage.write(key: key, value: value);
        unawaited(_repairLegacyMacOsKeychainAccessIfNeeded(key));
        return;
      }
    }
    await _secureStorage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) async {
    if (Platform.isMacOS) {
      try {
        await _macOsKeychainStorage.delete(key: key);
      } on MissingPluginException {
        await _secureStorage.delete(key: key);
        return;
      }
      try {
        await _secureStorage.delete(key: key);
      } on Object {
        // Best-effort legacy cleanup; the native Keychain item is already gone.
      }
      return;
    }
    await _secureStorage.delete(key: key);
  }
}

class MacOsKeychainStorage {
  const MacOsKeychainStorage({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.awiki.awikime/keychain_access';
  static const String _service = 'ai.awiki.awikime.secure_storage';

  final MethodChannel _channel;

  Future<String?> read({required String key}) async {
    if (!Platform.isMacOS) {
      return null;
    }
    return _channel.invokeMethod<String>(
      'readGenericPassword',
      <String, Object?>{'service': _service, 'account': key},
    );
  }

  Future<void> write({required String key, required String value}) async {
    if (!Platform.isMacOS) {
      return;
    }
    await _channel.invokeMethod<void>('writeGenericPassword', <String, Object?>{
      'service': _service,
      'account': key,
      'value': value,
    });
  }

  Future<void> delete({required String key}) async {
    if (!Platform.isMacOS) {
      return;
    }
    await _channel.invokeMethod<void>(
      'deleteGenericPassword',
      <String, Object?>{'service': _service, 'account': key},
    );
  }
}

class MacOsKeychainAccessRepair {
  const MacOsKeychainAccessRepair({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'ai.awiki.awikime/keychain_access';
  static const String _flutterSecureStorageService =
      'flutter_secure_storage_service';

  final MethodChannel _channel;

  Future<void> repairNativeSecureStorageKey(String key) async {
    await _repair(service: MacOsKeychainStorage._service, key: key);
  }

  Future<void> repairFlutterSecureStorageKey(String key) async {
    await _repair(service: _flutterSecureStorageService, key: key);
  }

  Future<void> _repair({required String service, required String key}) async {
    if (!Platform.isMacOS) {
      return;
    }
    await _channel.invokeMethod<void>(
      'repairGenericPasswordAccess',
      <String, Object?>{'service': service, 'account': key},
    );
  }
}

class FileAppKeyValueStore implements AppKeyValueStore {
  FileAppKeyValueStore._(
    this._file, {
    bool strictRead = false,
    bool privateFile = false,
  }) : _strictRead = strictRead,
       _privateFile = privateFile;

  final File _file;
  final bool _strictRead;
  final bool _privateFile;
  Map<String, String>? _cache;

  factory FileAppKeyValueStore.forFile(
    File file, {
    bool strictRead = false,
    bool privateFile = false,
  }) {
    return FileAppKeyValueStore._(
      file,
      strictRead: strictRead,
      privateFile: privateFile,
    );
  }

  static Future<FileAppKeyValueStore> create({
    String fileName = 'awiki_me_state.json',
    String? appStateRoot,
    bool strictRead = false,
    bool privateFile = false,
  }) async {
    final stateRoot = _firstNonEmpty(appStateRoot, awikiE2eAppStateRoot());
    final supportPath = stateRoot == null
        ? (await getApplicationSupportDirectory()).path
        : '$stateRoot/support';
    final file = File('$supportPath/$fileName');
    return FileAppKeyValueStore._(
      file,
      strictRead: strictRead,
      privateFile: privateFile,
    );
  }

  Future<bool> storeExists() {
    return _file.exists();
  }

  bool get strictRead => _strictRead;

  @override
  Future<String?> read({required String key}) async {
    final values = await _loadValues();
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final values = await _loadValues();
    values[key] = value;
    await _persist(values);
  }

  @override
  Future<void> delete({required String key}) async {
    final values = await _loadValues();
    if (values.remove(key) == null) {
      return;
    }
    await _persist(values);
  }

  Future<Map<String, String>> _loadValues() async {
    if (_cache != null) {
      return _cache!;
    }
    if (!await _file.exists()) {
      _cache = <String, String>{};
      return _cache!;
    }
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) {
      _throwIfStrict('key_value_store_file_empty');
      _cache = <String, String>{};
      return _cache!;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      _throwIfStrict('key_value_store_file_invalid_json');
      _cache = <String, String>{};
      return _cache!;
    }
    if (decoded is! Map) {
      _throwIfStrict('key_value_store_file_invalid_shape');
      _cache = <String, String>{};
      return _cache!;
    }
    _cache = decoded.map<String, String>(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
    return _cache!;
  }

  Future<void> _persist(Map<String, String> values) async {
    _cache = Map<String, String>.from(values);
    await _file.parent.create(recursive: true);
    if (!_privateFile) {
      await _file.writeAsString(jsonEncode(_cache), flush: true);
      return;
    }
    await _chmod(_file.parent.path, '700');
    final tempFile = File(
      '${_file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    await tempFile.writeAsString(jsonEncode(_cache), flush: true);
    await _chmod(tempFile.path, '600');
    await tempFile.rename(_file.path);
    await _chmod(_file.path, '600');
  }

  void _throwIfStrict(String code) {
    if (_strictRead) {
      throw StateError(code);
    }
  }
}

String? _firstNonEmpty(String? first, String? second) {
  final firstTrimmed = first?.trim();
  if (firstTrimmed != null && firstTrimmed.isNotEmpty) {
    return firstTrimmed;
  }
  final secondTrimmed = second?.trim();
  if (secondTrimmed != null && secondTrimmed.isNotEmpty) {
    return secondTrimmed;
  }
  return null;
}

Future<void> _chmod(String path, String mode) async {
  if (!(Platform.isLinux || Platform.isMacOS)) {
    return;
  }
  final result = await Process.run('chmod', <String>[mode, path]);
  if (result.exitCode != 0) {
    throw StateError('key_value_store_chmod_failed');
  }
}
