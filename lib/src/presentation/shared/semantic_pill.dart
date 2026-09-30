import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';
import 'responsive_layout.dart';

enum SemanticPillTone {
  identity,
  runtime,
  relationship,
  status,
  metadata,
  muted,
}

class SemanticPill extends StatelessWidget {
  const SemanticPill({super.key, required this.label, required this.tone});

  final String label;
  final SemanticPillTone tone;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final colors = _colorsForTone(context, tone);
    return Container(
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
      ),
      child: Text(
        label,
        style: AwikiMeTextStyles.pillLabel.copyWith(
          fontSize: responsive.metaSm,
          color: colors.foreground,
        ),
      ),
    );
  }
}

_SemanticPillColors _colorsForTone(
  BuildContext context,
  SemanticPillTone tone,
) {
  return switch (tone) {
    SemanticPillTone.identity => _SemanticPillColors(
      background: context.awikiTheme.primarySoft,
      foreground: context.awikiTheme.primary,
    ),
    SemanticPillTone.runtime => const _SemanticPillColors(
      background: Color(0xFFE4F3FA),
      foreground: AwikiMePalette.badgeBlue,
    ),
    SemanticPillTone.relationship => const _SemanticPillColors(
      background: Color(0xFFE6F8EE),
      foreground: AwikiMePalette.successGreen,
    ),
    SemanticPillTone.status => const _SemanticPillColors(
      background: Color(0xFFFFF4D6),
      foreground: AwikiMePalette.warningGold,
    ),
    SemanticPillTone.metadata => _SemanticPillColors(
      background: context.awikiTheme.subtleSurface,
      foreground: context.awikiTheme.secondaryText,
    ),
    SemanticPillTone.muted => _SemanticPillColors(
      background: context.awikiTheme.mutedSurface,
      foreground: context.awikiTheme.secondaryText,
    ),
  };
}

class _SemanticPillColors {
  const _SemanticPillColors({
    required this.background,
    required this.foreground,
  });

  final Color background;
  final Color foreground;
}
