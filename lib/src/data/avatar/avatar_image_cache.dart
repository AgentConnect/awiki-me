import 'dart:ui' as ui;

import 'avatar_image_cache_stub.dart'
    if (dart.library.io) 'avatar_image_cache_io.dart'
    as platform;

abstract class AvatarImageCache {
  factory AvatarImageCache(String owner) = platform.PlatformAvatarImageCache;
  Future<ui.Image?> load(String uri, {int edge = 128});
  void dispose();
}

Uri? safeAvatarUri(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
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

Future<void> clearAvatarImageCache(String owner) =>
    platform.clearAvatarImageCache(owner);
