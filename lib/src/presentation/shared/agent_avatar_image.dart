import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';
import '../../data/avatar/avatar_image_cache.dart';
import '../../domain/entities/agent/agent_avatar.dart';
import 'avatar_badge.dart';

final agentAvatarBytesProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, uri) async {
      final cache = ref.watch(avatarImageCacheProvider);
      return cache is AvatarByteCache
          ? (cache as AvatarByteCache).loadBytes(uri)
          : null;
    });

/// All individual and mosaic agent images share one fallback/motion policy.
class AgentAvatarImage extends ConsumerWidget {
  const AgentAvatarImage({
    super.key,
    required this.uri,
    required this.posterUri,
    required this.size,
    required this.fallback,
    this.staticOnly = false,
  });
  final String? uri;
  final String? posterUri;
  final double size;
  final Widget fallback;
  final bool staticOnly;

  static String? packagedAsset(String? value) {
    final parsed = Uri.tryParse(value ?? '');
    final path = parsed?.path ?? '';
    if (!path.startsWith('/avatars/presets/')) return null;
    final filename = path.split('/').last;
    final id = filename.split('.').first;
    if (!agentAvatarPresetIds.contains(id) ||
        !(filename == '$id.png' || filename == '$id.gif')) {
      return null;
    }
    return 'assets/avatars/agents/$filename';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final still =
        staticOnly ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    Widget image(String? value, Widget onError) {
      final asset = packagedAsset(value);
      if (asset != null) {
        return Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
              .ceil()
              .clamp(1, 512),
          errorBuilder: (_, __, ___) => onError,
        );
      }
      final safe = safeAvatarUri(value);
      if (safe == null) return onError;
      final bytes = ref
          .watch(agentAvatarBytesProvider(safe.toString()))
          .valueOrNull;
      if (bytes == null) return onError;
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 512),
        errorBuilder: (_, __, ___) => onError,
      );
    }

    final poster = image(posterUri, fallback);
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: still || uri == null || uri == posterUri
            ? poster
            : image(uri, poster),
      ),
    );
  }
}
