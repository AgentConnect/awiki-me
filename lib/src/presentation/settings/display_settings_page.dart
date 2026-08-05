import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/display_scale.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';

class DisplaySettingsPage extends ConsumerWidget {
  const DisplaySettingsPage({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = context.awikiTheme;
    final scale = ref.watch(displayScaleProvider);
    final levelIndex = AwikiDisplayScale.levelIndex(scale);
    final percent = (scale * 100).round();

    return CupertinoPageScaffold(
      key: const Key('display-settings-page'),
      backgroundColor: theme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              key: const Key('display-settings-header'),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: AwikiMeTopBar(
                title: l10n.settingsDisplayAndWindow,
                padding: const EdgeInsets.symmetric(vertical: 6),
                titleFontSize: awikiMeCompactTopBarTitleFontSize,
                titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
                titleHeight: awikiMeCompactTopBarTitleHeight,
                leading: TopBarActionButton(
                  key: const Key('display-settings-back-button'),
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
                        key: const Key('display-scale-control'),
                        decoration: BoxDecoration(
                          color: theme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      l10n.settingsDisplayScale,
                                      style: TextStyle(
                                        color: theme.title,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$percent%',
                                    key: const Key('display-scale-value'),
                                    style: const TextStyle(
                                      color: AwikiMePalette.actionBlue,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              CupertinoSlider(
                                key: const Key('display-scale-slider'),
                                min: 0,
                                max: (AwikiDisplayScale.levels.length - 1)
                                    .toDouble(),
                                divisions: AwikiDisplayScale.levels.length - 1,
                                value: levelIndex.toDouble(),
                                onChanged: (value) => ref
                                    .read(displayScaleProvider.notifier)
                                    .setScale(
                                      AwikiDisplayScale.levels[value.round()],
                                    ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(
                                    '80%',
                                    style: TextStyle(
                                      color: theme.tertiaryText,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '130%',
                                    style: TextStyle(
                                      color: theme.tertiaryText,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _DisplayActionRow(
                        key: const Key('display-scale-reset-row'),
                        icon: CupertinoIcons.arrow_counterclockwise,
                        title: l10n.settingsDisplayScaleReset,
                        onTap: () =>
                            ref.read(displayScaleProvider.notifier).reset(),
                      ),
                      const SizedBox(height: 12),
                      _DisplayActionRow(
                        key: const Key('window-placement-reset-row'),
                        icon: CupertinoIcons.rectangle_expand_vertical,
                        title: l10n.settingsWindowPlacementReset,
                        onTap: () async {
                          try {
                            await ref
                                .read(desktopWindowPlacementServiceProvider)
                                .resetPlacement();
                          } on Object catch (error) {
                            ref
                                .read(uiFeedbackProvider.notifier)
                                .showError(
                                  AppMessage.operationFailedRetry(),
                                  detail: error.toString(),
                                );
                          }
                        },
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

class _DisplayActionRow extends StatelessWidget {
  const _DisplayActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AppPressable(
          onTap: onTap,
          semanticLabel: title,
          borderRadius: BorderRadius.zero,
          child: SizedBox(
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 22, color: AwikiMePalette.actionBlue),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
