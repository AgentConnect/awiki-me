import 'dart:ui' as ui;
import 'package:awiki_me/src/data/avatar/avatar_image_cache.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/profile/avatar_edit_dialog.dart';
import 'package:awiki_me/src/presentation/profile/profile_page.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/profile_avatar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_support.dart';

class PreviewCache implements AvatarImageCache {
  PreviewCache(this.image);
  final ui.Image image;
  bool fail = true;
  final calls = <(String, int, bool)>[];
  @override
  Future<ui.Image?> load(
    String uri, {
    int edge = 128,
    bool force = false,
  }) async {
    calls.add((uri, edge, force));
    return edge == 512 && fail ? null : image.clone();
  }

  @override
  void dispose() {}
}

void main() {
  for (final width in [390.0, 1100.0]) {
    testWidgets('own avatar opens separate editor at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const profile = UserProfile(
        did: 'did:test:alice',
        nickName: 'Alice',
        bio: '',
        tags: [],
        profileMarkdown: '',
      );
      final gateway = FakeAwikiGateway()..myProfile = profile;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: ProfilePage(homepageMarkdownLoader: (_) async => null),
          gateway: gateway,
          profile: profile,
        ),
      );
      await tester.pumpAndSettle();
      final avatar = find.byType(ProfileAvatar);
      expect(avatar, findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(avatar));
      await tester.pump();
      expect(find.byIcon(CupertinoIcons.camera), findsOneWidget);
      await tester.tap(avatar);
      await tester.pumpAndSettle();
      expect(find.byType(AvatarEditDialog), findsOneWidget);
      expect(find.byKey(const Key('profile-edit-page')), findsNothing);
      expect(find.byKey(const Key('profile-edit-dialog')), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'peer main image previews, retries and closes with Escape; no image has no entry',
    (tester) async {
      final image = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const ui.Color(0xffabcdef), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        picture.dispose();
        return image;
      });
      final cache = PreviewCache(image!);
      Widget tree(String? uri) => buildLocalizedTestApp(
        home: Center(
          child: ProfileAvatar(seed: 'Bob', avatarUri: uri),
        ),
        providerOverrides: [avatarImageCacheProvider.overrideWithValue(cache)],
      );
      await tester.pumpWidget(tree('https://example.com/main.jpg'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ProfileAvatar));
      await tester.pumpAndSettle();
      expect(find.text('头像加载失败，请重试。'), findsOneWidget);
      cache.fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(
        cache.calls,
        contains(('https://example.com/main.jpg', 512, true)),
      );
      expect(find.byKey(const Key('avatar-preview-image')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AvatarPreviewDialog), findsNothing);
      await tester.pumpWidget(tree(null));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ProfileAvatar));
      await tester.pumpAndSettle();
      expect(find.byType(AvatarPreviewDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      image.dispose();
    },
  );
}
