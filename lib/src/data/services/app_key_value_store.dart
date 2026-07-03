import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../im_core/awiki_im_core_paths.dart';

abstract class AppKeyValueStore {
  Future<String?> read({required String key});

  Future<void> write({required String key, required String value});

  Future<void> delete({required String key});
}

class SecureAppKeyValueStore implements AppKeyValueStore {
  SecureAppKeyValueStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<String?> read({required String key}) {
    return _secureStorage.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _secureStorage.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) {
    return _secureStorage.delete(key: key);
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
