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
  FileAppKeyValueStore._(this._file);

  final File _file;
  Map<String, String>? _cache;

  factory FileAppKeyValueStore.forFile(File file) {
    return FileAppKeyValueStore._(file);
  }

  static Future<FileAppKeyValueStore> create({
    String fileName = 'awiki_me_state.json',
    String? appStateRoot,
  }) async {
    final stateRoot = _firstNonEmpty(appStateRoot, awikiE2eAppStateRoot());
    final supportPath = stateRoot == null
        ? (await getApplicationSupportDirectory()).path
        : '$stateRoot/support';
    final file = File('$supportPath/$fileName');
    return FileAppKeyValueStore._(file);
  }

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
    try {
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) {
        _cache = <String, String>{};
        return _cache!;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _cache = <String, String>{};
        return _cache!;
      }
      _cache = decoded.map<String, String>(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      return _cache!;
    } catch (_) {
      _cache = <String, String>{};
      return _cache!;
    }
  }

  Future<void> _persist(Map<String, String> values) async {
    _cache = Map<String, String>.from(values);
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(_cache), flush: true);
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
