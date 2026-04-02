import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/data/services/locale_preference_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalePreferenceService 默认返回跟随系统', () async {
    final storage = _InMemorySecureStorage();
    final service = LocalePreferenceService(secureStorage: storage);

    expect(await service.loadMode(), AppLocaleMode.system);
  });

  test('LocalePreferenceService 保存并恢复英文设置', () async {
    final storage = _InMemorySecureStorage();
    final service = LocalePreferenceService(secureStorage: storage);

    await service.saveMode(AppLocaleMode.english);

    expect(await storage.read(key: 'awiki_me_locale_mode'), 'english');
    expect(await service.loadMode(), AppLocaleMode.english);
  });

  test('LocalePreferenceService 保存跟随系统时会清除本地记录', () async {
    final storage = _InMemorySecureStorage()
      ..seed('awiki_me_locale_mode', 'zhHans');
    final service = LocalePreferenceService(secureStorage: storage);

    await service.saveMode(AppLocaleMode.system);

    expect(await storage.read(key: 'awiki_me_locale_mode'), isNull);
    expect(await service.loadMode(), AppLocaleMode.system);
  });
}

class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage();

  final Map<String, String> _values = <String, String>{};

  void seed(String key, String value) {
    _values[key] = value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

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
    return _values[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}
