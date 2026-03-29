import 'package:flutter/cupertino.dart';

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
    final palette = _paletteForSeed(normalized);
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

  (Color, Color) _paletteForSeed(String value) {
    const palettes = <(Color, Color)>[
      (Color(0xFFDCEBFF), Color(0xFF2563EB)),
      (Color(0xFFD8F8E8), Color(0xFF059669)),
      (Color(0xFFF3E8FF), Color(0xFF9333EA)),
      (Color(0xFFFFEDD5), Color(0xFFEA580C)),
      (Color(0xFFFFE4E6), Color(0xFFE11D48)),
      (Color(0xFFE0F2FE), Color(0xFF0284C7)),
    ];
    final hash =
        value.isEmpty ? 0 : value.codeUnits.fold<int>(0, (a, b) => a + b);
    return palettes[hash % palettes.length];
  }
}
