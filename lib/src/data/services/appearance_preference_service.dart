import '../../app/app_appearance.dart';
import 'app_key_value_store.dart';

/// Device-wide presentation preference, shared across tenant runtimes.
class AppearancePreferenceService {
  const AppearancePreferenceService({AppKeyValueStore? storage})
    : _storage = storage;

  static const key = 'awiki_me_appearance';
  final AppKeyValueStore? _storage;

  Future<AppAppearance> load() async {
    String? raw;
    try {
      raw = await _storage?.read(key: key);
    } on Object {
      // A presentation preference must not block identity/bootstrap access.
      return AppAppearance.system;
    }
    return switch (raw) {
      'light' => AppAppearance.light,
      'dark' => AppAppearance.dark,
      _ => AppAppearance.system,
    };
  }

  Future<void> save(AppAppearance appearance) async {
    if (appearance == AppAppearance.system) {
      await _storage?.delete(key: key);
    } else {
      await _storage?.write(key: key, value: appearance.name);
    }
  }
}
