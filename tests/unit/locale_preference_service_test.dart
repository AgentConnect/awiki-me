import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/locale_preference_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LocalePreferenceService 默认返回跟随系统', () async {
    final storage = _InMemoryKeyValueStore();
    final service = LocalePreferenceService(storage: storage);

    expect(await service.loadMode(), AppLocaleMode.system);
  });

  test('LocalePreferenceService 保存并恢复英文设置', () async {
    final storage = _InMemoryKeyValueStore();
    final service = LocalePreferenceService(storage: storage);

    await service.saveMode(AppLocaleMode.english);

    expect(await storage.read(key: 'awiki_me_locale_mode'), 'english');
    expect(await service.loadMode(), AppLocaleMode.english);
  });

  test('LocalePreferenceService 保存跟随系统时会清除本地记录', () async {
    final storage = _InMemoryKeyValueStore()
      ..seed('awiki_me_locale_mode', 'zhHans');
    final service = LocalePreferenceService(storage: storage);

    await service.saveMode(AppLocaleMode.system);

    expect(await storage.read(key: 'awiki_me_locale_mode'), isNull);
    expect(await service.loadMode(), AppLocaleMode.system);
  });
}

class _InMemoryKeyValueStore implements AppKeyValueStore {
  _InMemoryKeyValueStore();

  final Map<String, String> _values = <String, String>{};

  void seed(String key, String value) {
    _values[key] = value;
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
