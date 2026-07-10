import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../l10n/l10n.dart';
import 'widgets/app_widgets.dart';

String appLocaleModeLabel(BuildContext context, AppLocaleMode mode) {
  final l10n = context.l10n;
  switch (mode) {
    case AppLocaleMode.system:
      return l10n.settingsLanguageSystem;
    case AppLocaleMode.zhHans:
      return l10n.settingsLanguageZhHans;
    case AppLocaleMode.english:
      return l10n.settingsLanguageEnglish;
  }
}

String compactAppLocaleModeLabel(BuildContext context, AppLocaleMode mode) {
  switch (mode) {
    case AppLocaleMode.zhHans:
      return '中';
    case AppLocaleMode.english:
      return 'EN';
    case AppLocaleMode.system:
      final locale = Localizations.localeOf(context);
      return locale.languageCode.toLowerCase() == 'en' ? 'EN' : '中';
  }
}

Future<void> showAppLanguageSheet(
  BuildContext context,
  WidgetRef ref,
  AppLocaleMode currentMode,
) {
  final l10n = context.l10n;
  return AppNavigator.showSheet<void>(
    context,
    (sheetContext) => AppDropMenu(
      title: l10n.settingsLanguage.toUpperCase(),
      items: <AppDropMenuItem>[
        _buildLanguageAction(
          ref: ref,
          mode: AppLocaleMode.system,
          currentMode: currentMode,
          label: l10n.settingsLanguageSystem,
        ),
        _buildLanguageAction(
          ref: ref,
          mode: AppLocaleMode.zhHans,
          currentMode: currentMode,
          label: l10n.settingsLanguageZhHans,
        ),
        _buildLanguageAction(
          ref: ref,
          mode: AppLocaleMode.english,
          currentMode: currentMode,
          label: l10n.settingsLanguageEnglish,
        ),
      ],
    ),
  );
}

AppDropMenuItem _buildLanguageAction({
  required WidgetRef ref,
  required AppLocaleMode mode,
  required AppLocaleMode currentMode,
  required String label,
}) {
  return AppDropMenuItem(
    label: label,
    highlighted: currentMode == mode,
    onTap: () async {
      await ref.read(localePreferenceServiceProvider).saveMode(mode);
      ref.read(appLocaleModeProvider.notifier).state = mode;
    },
  );
}
