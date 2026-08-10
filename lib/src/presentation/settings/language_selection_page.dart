import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../l10n/l10n.dart';
import '../shared/app_language_menu.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

class LanguageSelectionPage extends ConsumerWidget {
  const LanguageSelectionPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final selectedMode = ref.watch(appLocaleModeProvider);
    final theme = context.awikiTheme;

    return CupertinoPageScaffold(
      key: const Key('language-selection-page'),
      backgroundColor: theme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              key: const Key('language-selection-header'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AwikiMeTopBar(
                title: l10n.settingsLanguage,
                padding: const EdgeInsets.symmetric(vertical: 6),
                titleFontSize: awikiMeCompactTopBarTitleFontSize,
                titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
                titleHeight: awikiMeCompactTopBarTitleHeight,
                leading: TopBarActionButton(
                  key: const Key('language-selection-back-button'),
                  onTap: onBack ?? () => Navigator.of(context).pop(),
                  semanticsLabel: l10n.commonBack,
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    size: context.awikiResponsive.iconMd,
                    color: AwikiMePalette.actionBlue,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    children: <Widget>[
                      DecoratedBox(
                        key: const Key('language-selection-options'),
                        decoration: BoxDecoration(
                          color: theme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _LanguageOptionRow(
                                key: const Key('language-option-system'),
                                title: l10n.settingsLanguageSystem,
                                subtitle: l10n.settingsLanguageSystemSubtitle,
                                selected: selectedMode == AppLocaleMode.system,
                                height: 78,
                                onTap: () =>
                                    setAppLocaleMode(ref, AppLocaleMode.system),
                              ),
                              const _LanguageDivider(),
                              _LanguageOptionRow(
                                key: const Key('language-option-zh-hans'),
                                title: l10n.settingsLanguageZhHans,
                                selected: selectedMode == AppLocaleMode.zhHans,
                                height: 64,
                                onTap: () =>
                                    setAppLocaleMode(ref, AppLocaleMode.zhHans),
                              ),
                              const _LanguageDivider(),
                              _LanguageOptionRow(
                                key: const Key('language-option-english'),
                                title: l10n.settingsLanguageEnglish,
                                selected: selectedMode == AppLocaleMode.english,
                                height: 64,
                                onTap: () => setAppLocaleMode(
                                  ref,
                                  AppLocaleMode.english,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOptionRow extends StatelessWidget {
  const _LanguageOptionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.height,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final double height;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    final effectiveHeight = height * textScale;
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      onTap: () => onTap(),
      child: ExcludeSemantics(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size(0, effectiveHeight),
          pressedOpacity: 0.72,
          onPressed: onTap,
          child: SizedBox(
            height: effectiveHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: 20, right: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AwikiMePalette.actionBlue
                                : theme.title,
                            fontSize: 17,
                            fontWeight: selected
                                ? FontWeight.w400
                                : FontWeight.w400,
                            height: 24 / 17,
                          ),
                        ),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 14,
                              height: 20 / 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox.square(
                    dimension: 24,
                    child: selected
                        ? const Icon(
                            CupertinoIcons.check_mark,
                            key: Key('language-option-selected-check'),
                            size: 23,
                            color: AwikiMePalette.actionBlue,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageDivider extends StatelessWidget {
  const _LanguageDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 16),
      child: ColoredBox(
        color: context.awikiTheme.border,
        child: const SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}
