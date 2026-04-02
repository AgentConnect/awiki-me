import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.seed,
    this.size = 48,
  });

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalized = seed.trim();
    final initial =
        normalized.isEmpty ? '?' : normalized.substring(0, 1).toUpperCase();
    final palette = _paletteForSeed(context, normalized);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size / 2.4,
          color: palette.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (Color, Color) _paletteForSeed(BuildContext context, String value) {
    final theme = context.awikiTheme;
    final palettes = <(Color, Color)>[
      (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer
      ),
      (
        theme.colorScheme.tertiaryContainer,
        theme.colorScheme.onTertiaryContainer
      ),
      (theme.warningContainer, theme.primaryDark),
      (theme.subtleSurface, theme.infoAccent),
      (theme.dangerContainer, theme.danger),
      (theme.mutedSurface, theme.title),
    ];
    final hash =
        value.isEmpty ? 0 : value.codeUnits.fold<int>(0, (a, b) => a + b);
    return palettes[hash % palettes.length];
  }
}
