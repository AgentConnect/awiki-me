import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart' as material;

import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/font_size.dart';
import '../shared/responsive_layout.dart';

class FontSizeSettingRow extends ConsumerWidget {
  const FontSizeSettingRow({super.key, this.compact = false, this.height});

  static const double _sliderHorizontalInset = 13;

  final bool compact;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final fontSize = ref.watch(fontSizeProvider);
    final slider = material.Material(
      type: material.MaterialType.transparency,
      child: material.SliderTheme(
        data: material.SliderTheme.of(context).copyWith(
          trackHeight: 2,
          activeTrackColor: theme.primary,
          inactiveTrackColor: theme.border,
          thumbColor: theme.surface,
          activeTickMarkColor: theme.surface,
          inactiveTickMarkColor: theme.secondaryText.withValues(alpha: 0.55),
          thumbShape: const material.RoundSliderThumbShape(
            enabledThumbRadius: 7,
          ),
          overlayShape: const material.RoundSliderOverlayShape(
            overlayRadius: 13,
          ),
          tickMarkShape: const material.RoundSliderTickMarkShape(
            tickMarkRadius: 2.2,
          ),
        ),
        child: material.Slider(
          key: const Key('settings-font-size-slider'),
          min: AwikiFontSize.min,
          max: AwikiFontSize.max,
          divisions: AwikiFontSize.divisions,
          value: fontSize,
          label: '${fontSize.round()} px',
          semanticFormatterCallback: (value) => '${value.round()} px',
          padding: const EdgeInsets.symmetric(
            horizontal: _sliderHorizontalInset,
          ),
          onChanged: ref.read(fontSizeProvider.notifier).setFontSize,
        ),
      ),
    );

    return Container(
      key: const Key('settings-font-size-row'),
      height: compact ? (height ?? 52) : null,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 28)
          : responsive.scaledInsets(
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (compact) ...<Widget>[
            const SizedBox.square(
              dimension: 24,
              child: Icon(
                CupertinoIcons.textformat_size,
                key: Key('settings-font-size-icon'),
                size: 24,
                color: AwikiMePalette.actionBlue,
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.settingsFontSize,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: TextStyle(
                  color: theme.title,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(width: 132, child: slider),
        ],
      ),
    );
  }
}
