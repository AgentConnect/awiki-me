import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../l10n/l10n.dart';
import 'awiki_me_design.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';
import 'widgets/awiki_desktop.dart';
import 'widgets/awiki_glass_controls.dart';

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
      title: l10n.settingsLanguage,
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

/// Opens the language choices as a small menu anchored to [anchorContext]
/// (the reference's popover): a quiet caption, one row per language and a
/// check on the current one. It opens upward when the trigger sits low, as
/// the login footer does, and falls back to the centered sheet otherwise.
Future<void> showAppLanguageMenu(
  BuildContext anchorContext,
  WidgetRef ref,
  AppLocaleMode currentMode,
) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Navigator.of(
            anchorContext,
            rootNavigator: true,
          ).overlay?.context.findRenderObject()
          as RenderBox?;
  if (box == null || overlay == null) {
    return showAppLanguageSheet(anchorContext, ref, currentMode);
  }
  final anchor = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final selected = await showGeneralDialog<AppLocaleMode>(
    context: anchorContext,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: anchorContext.l10n.commonClose,
    barrierColor: const Color(0x00000000),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, __, ___) => _LanguageMenuLayout(
      anchor: anchor,
      child: _LanguageMenu(currentMode: currentMode),
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
  if (selected != null && selected != currentMode) {
    await setAppLocaleMode(ref, selected);
  }
}

class _LanguageMenuLayout extends StatelessWidget {
  const _LanguageMenuLayout({required this.anchor, required this.child});

  final Rect anchor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    const width = 220.0;
    final left = anchor.left.clamp(8.0, screen.width - width - 8);
    final below = screen.height - padding.bottom - anchor.bottom - 12;
    final above = anchor.top - padding.top - 12;
    final openBelow = below >= 200 || below >= above;
    return Stack(
      children: <Widget>[
        Positioned(
          left: left,
          width: width,
          top: openBelow ? anchor.bottom + 4 : null,
          bottom: openBelow ? null : screen.height - anchor.top + 4,
          child: child,
        ),
      ],
    );
  }
}

class _LanguageMenu extends StatelessWidget {
  const _LanguageMenu({required this.currentMode});

  final AppLocaleMode currentMode;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final l10n = context.l10n;
    final phone = context.awikiResponsive.isPhone;
    final rowRadius = BorderRadius.circular(phone ? 14 : 6);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          child: Text(
            l10n.settingsLanguage,
            style: TextStyle(color: theme.secondaryText, fontSize: 12),
          ),
        ),
        for (final mode in AppLocaleMode.values)
          AppPressable(
            key: Key('app-language-option:${mode.name}'),
            onTap: () => Navigator.of(context).pop(mode),
            selected: mode == currentMode,
            semanticLabel: appLocaleModeLabel(context, mode),
            borderRadius: rowRadius,
            builder: (context, state, child) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: state.hovered || state.pressed
                    ? awikiDesktopHoverFill(context)
                    : awikiDesktopHoverFill(context).withValues(alpha: 0),
                borderRadius: rowRadius,
              ),
              child: child,
            ),
            child: SizedBox(
              height: phone ? 44 : 36,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        appLocaleModeLabel(context, mode),
                        style: TextStyle(
                          color: theme.title,
                          fontSize: phone ? 15 : 13,
                        ),
                      ),
                    ),
                    if (mode == currentMode)
                      Icon(
                        CupertinoIcons.checkmark,
                        size: 14,
                        color: theme.title,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    if (phone) {
      return AwikiGlassPanel(
        key: const Key('app-language-menu'),
        radius: 22,
        padding: const EdgeInsets.all(8),
        child: content,
      );
    }
    // Reference desktop popover: a flat surface card with a hairline edge.
    return Container(
      key: const Key('app-language-menu'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.border),
        boxShadow: theme.overlayShadow,
      ),
      child: content,
    );
  }
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
      await setAppLocaleMode(ref, mode);
    },
  );
}

Future<void> setAppLocaleMode(WidgetRef ref, AppLocaleMode mode) async {
  await ref.read(localePreferenceServiceProvider).saveMode(mode);
  ref.read(appLocaleModeProvider.notifier).state = mode;
}
