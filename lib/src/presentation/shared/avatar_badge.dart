import 'package:flutter/cupertino.dart';

import 'default_avatar_generator.dart';

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.seed,
    this.size = 48,
    this.labelOverride,
    this.avatarUri,
    this.userId,
  });

  final String seed;
  final double size;
  final String? labelOverride;
  final String? avatarUri;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final fallback = _FallbackAvatarBadge(
      seed: seed,
      size: size,
      labelOverride: labelOverride,
      userId: userId,
    );
    final uri = _safeAvatarUri(avatarUri);
    if (uri == null) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
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
  });

  final String seed;
  final double size;
  final String? labelOverride;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final generated = generateDefaultAvatar(name: seed, userId: userId);
    final label = labelOverride?.trim().isNotEmpty == true
        ? labelOverride!.trim()
        : generated.text;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            generated.backgroundTopColor,
            generated.backgroundBottomColor,
          ],
        ),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: label.length > 1 ? size / 3.1 : size / 2.4,
          color: CupertinoColors.white,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

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
