import 'dart:ui' as ui;
import 'avatar_image_cache.dart';

// The native Core-backed App has no Web avatar editing contract yet.
class PlatformAvatarImageCache implements AvatarImageCache {
  PlatformAvatarImageCache(String owner);
  @override
  Future<ui.Image?> load(
    String uri, {
    int edge = 128,
    bool force = false,
  }) async => null;
  @override
  void dispose() {}
}

Future<void> clearAvatarImageCache(String owner) async {}
