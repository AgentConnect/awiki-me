import '../../app/app_locale.dart';
import 'app_key_value_store.dart';

class LocalePreferenceService {
  LocalePreferenceService({AppKeyValueStore? storage})
    : _storage = storage ?? SecureAppKeyValueStore();

  static const String _localeModeKey = 'awiki_me_locale_mode';

  final AppKeyValueStore _storage;

  Future<AppLocaleMode> loadMode() async {
    final raw = await _storage.read(key: _localeModeKey);
    switch (raw) {
      case 'zhHans':
        return AppLocaleMode.zhHans;
      case 'english':
        return AppLocaleMode.english;
      case 'system':
      case null:
      default:
        return AppLocaleMode.system;
    }
  }

  Future<void> saveMode(AppLocaleMode mode) async {
    if (mode == AppLocaleMode.system) {
      await _storage.delete(key: _localeModeKey);
      return;
    }
    await _storage.write(key: _localeModeKey, value: mode.name);
  }
}
