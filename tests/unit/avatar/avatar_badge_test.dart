import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/data/avatar/avatar_image_cache.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';

class Cache implements AvatarImageCache {
  Cache(this.image);
  final ui.Image image;
  int calls = 0;
  @override
  Future<ui.Image?> load(String uri, {int edge = 128}) async =>
      ++calls == 1 ? null : image.clone();
  @override
  void dispose() {}
}

void main() {
  testWidgets(
    'a transient failure retries while visible and clear cancels pending retries',
    (tester) async {
      final image = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const ui.Color(0xff123456), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(8, 8);
        picture.dispose();
        return image;
      });
      final cache = Cache(image!);
      Widget app(String? uri) => ProviderScope(
        overrides: [avatarImageCacheProvider.overrideWithValue(cache)],
        child: CupertinoApp(
          home: AvatarBadge(seed: 'Alice', avatarUri: uri),
        ),
      );
      await tester.pumpWidget(app('https://example.com/a.jpg'));
      await tester.pump();
      expect(cache.calls, 1);
      expect(find.byType(RawImage), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(cache.calls, 2);
      expect(find.byType(RawImage), findsOneWidget);
      await tester.pumpWidget(app(null));
      await tester.pump(const Duration(minutes: 6));
      expect(cache.calls, 2);
      expect(find.byType(RawImage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      image.dispose();
    },
  );
}
