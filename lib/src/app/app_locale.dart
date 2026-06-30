import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLocaleMode { system, zhHans, english }

enum EffectiveAppLanguage { zhHans, english }

extension AppLocaleModeX on AppLocaleMode {
  Locale? get locale {
    switch (this) {
      case AppLocaleMode.system:
        return null;
      case AppLocaleMode.zhHans:
        return const Locale('zh');
      case AppLocaleMode.english:
        return const Locale('en');
    }
  }
}

extension EffectiveAppLanguageX on EffectiveAppLanguage {
  String get wireValue {
    switch (this) {
      case EffectiveAppLanguage.zhHans:
        return 'zh-Hans';
      case EffectiveAppLanguage.english:
        return 'en';
    }
  }

  Locale get locale {
    switch (this) {
      case EffectiveAppLanguage.zhHans:
        return const Locale('zh');
      case EffectiveAppLanguage.english:
        return const Locale('en');
    }
  }
}

EffectiveAppLanguage resolveEffectiveAppLanguage(
  AppLocaleMode mode,
  Locale? platformLocale,
) {
  switch (mode) {
    case AppLocaleMode.zhHans:
      return EffectiveAppLanguage.zhHans;
    case AppLocaleMode.english:
      return EffectiveAppLanguage.english;
    case AppLocaleMode.system:
      final languageCode = platformLocale?.languageCode.toLowerCase();
      if (languageCode == 'en') {
        return EffectiveAppLanguage.english;
      }
      return EffectiveAppLanguage.zhHans;
  }
}

final appLocaleModeProvider = StateProvider<AppLocaleMode>(
  (ref) => AppLocaleMode.system,
);
