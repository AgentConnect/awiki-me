import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLocaleMode { system, zhHans, english }

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

final appLocaleModeProvider = StateProvider<AppLocaleMode>(
  (ref) => AppLocaleMode.system,
);
