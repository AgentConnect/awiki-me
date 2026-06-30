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
    final colors = _colorsForTone(tone);
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

_SemanticPillColors _colorsForTone(SemanticPillTone tone) {
  return switch (tone) {
    SemanticPillTone.identity => const _SemanticPillColors(
      background: Color(0xFFEAF2FF),
      foreground: Color(0xFF0B65F8),
    ),
    SemanticPillTone.runtime => const _SemanticPillColors(
      background: Color(0xFFF2EBFF),
      foreground: Color(0xFF6D35D3),
    ),
    SemanticPillTone.relationship => const _SemanticPillColors(
      background: Color(0xFFE6F8EE),
      foreground: Color(0xFF10A85A),
    ),
    SemanticPillTone.status => const _SemanticPillColors(
      background: Color(0xFFFFF4D6),
      foreground: Color(0xFF825500),
    ),
    SemanticPillTone.metadata => const _SemanticPillColors(
      background: Color(0xFFFFF0E8),
      foreground: Color(0xFFC4552B),
    ),
    SemanticPillTone.muted => const _SemanticPillColors(
      background: Color(0xFFF1F3F7),
      foreground: Color(0xFF66728A),
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
