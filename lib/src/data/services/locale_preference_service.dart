import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../app/app_locale.dart';

class LocalePreferenceService {
  LocalePreferenceService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _localeModeKey = 'awiki_me_locale_mode';

  final FlutterSecureStorage _secureStorage;

  Future<AppLocaleMode> loadMode() async {
    final raw = await _secureStorage.read(key: _localeModeKey);
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
      await _secureStorage.delete(key: _localeModeKey);
      return;
    }
    await _secureStorage.write(key: _localeModeKey, value: mode.name);
  }
}
