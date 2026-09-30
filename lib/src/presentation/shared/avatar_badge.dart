import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';
import 'default_avatar_generator.dart';

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.seed,
    this.size = 48,
    this.labelOverride,
    this.avatarUri,
    this.userId,
    this.square = false,
  });

  final String seed;
  final double size;
  final String? labelOverride;
  final String? avatarUri;
  final String? userId;

  /// Agents use the reference's rounded square (radius 24% of the size);
  /// people stay round.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final fallback = _FallbackAvatarBadge(
      seed: seed,
      size: size,
      labelOverride: labelOverride,
      userId: userId,
      square: square,
    );
    final uri = _safeAvatarUri(avatarUri);
    if (uri == null) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: avatarBadgeRadius(size, square: square),
      child: Image.network(
        uri.toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return fallback;
        },
      ),
    );
  }
}

class _FallbackAvatarBadge extends StatelessWidget {
  const _FallbackAvatarBadge({
    required this.seed,
    required this.size,
    this.labelOverride,
    this.userId,
    this.square = false,
  });

  final String seed;
  final double size;
  final String? labelOverride;
  final String? userId;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final generated = generateDefaultAvatar(name: seed, userId: userId);
    final label = labelOverride?.trim().isNotEmpty == true
        ? labelOverride!.trim()
        : generated.text;
    final labelLength = label.runes.length;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.avatarBackground,
        borderRadius: avatarBadgeRadius(size, square: square),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: labelLength > 2
              ? size / 4
              : labelLength > 1
              ? size / 3.1
              : size / 2.4,
          color: theme.avatarForeground,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Corner radius for an avatar of [size]: round, or the reference's rounded
/// square for agents.
BorderRadius avatarBadgeRadius(double size, {bool square = false}) =>
    BorderRadius.circular(square ? size * 0.24 : size / 2);

Uri? _safeAvatarUri(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.isAbsolute || uri.scheme != 'https') {
    return null;
  }
  final path = uri.path.toLowerCase();
  if (path.endsWith('.svg') ||
      path.endsWith('.html') ||
      path.endsWith('.htm')) {
    return null;
  }
  return uri;
}
