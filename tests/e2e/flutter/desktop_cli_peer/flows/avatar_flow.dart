part of '../desktop_cli_peer_e2e.dart';

// Only the OS chooser input is deterministic. The visible crop/editor, Core,
// authentication, server normalization and product image cache remain real.
class _AvatarFixtureChooser extends FileSelectorPlatform {
  XFile? next;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    expect(acceptedTypeGroups?.single.extensions, contains('png'));
    final result = next;
    next = null;
    return result;
  }
}

Future<void> _verifyAvatarEditing(
  _DesktopAppRobot robot,
  WidgetTester tester,
) async {
  robot.failureCaseId = 'AVATAR-E2E-001';
  final originalChooser = FileSelectorPlatform.instance;
  final chooser = _AvatarFixtureChooser();
  final fixtures = await Directory.systemTemp.createTemp('awiki-avatar-e2e-');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  FileSelectorPlatform.instance = chooser;
  Future<void> tap(String key) =>
      robot.tapOne(find.byKey(Key(key)), description: key);
  Future<void> editorReady(String key) => robot.pumpUntil(
    description: 'enabled $key',
    condition: () {
      final target = find.byKey(Key(key));
      return target.evaluate().length == 1 &&
          tester.widget<CupertinoButton>(target).onPressed != null;
    },
  );
  Future<void> verifyPublicImage(String uri) async {
    final response = await (await client.getUrl(Uri.parse(uri))).close();
    expect(response.statusCode, 200);
    final bytes = await response.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    expect(bytes.length, lessThanOrEqualTo(256 * 1024));
    final decoded = img.decodeJpg(Uint8List.fromList(bytes));
    expect(decoded?.width, 512);
    expect(decoded?.height, 512);
    expect(
      response.headers.value(HttpHeaders.cacheControlHeader),
      contains('immutable'),
    );
  }

  try {
    await robot.tapOne(
      find.bySemanticsIdentifier('e2e-profile-dialog-button'),
      description: 'own profile',
    );
    await tap('profile-edit-button');
    String? previous;
    for (final index in [0, 1]) {
      final source = img.Image(width: 1200, height: 800);
      img.fill(source, color: img.ColorRgb8(40 + index * 100, 90, 160));
      img.fillRect(
        source,
        x1: 450,
        y1: 200,
        x2: 800,
        y2: 650,
        color: img.ColorRgb8(230, 200 - index * 80, 70),
      );
      final file = File('${fixtures.path}/source-$index.png');
      await file.writeAsBytes(img.encodePng(source));
      chooser.next = XFile(file.path);
      await tap('profile-edit-change-avatar-button');
      await editorReady('avatar-pick');
      await tap('avatar-pick');
      await editorReady('avatar-save');
      await tester.drag(
        // Crop forwards its key to its internal editor; target the public widget.
        find.byKey(const Key('avatar-crop')).first,
        const Offset(24, 0),
      );
      await tester.pump();
      await tap('avatar-save');
      await robot.pumpUntil(
        description: 'avatar saved and editor dismissed',
        condition: () => find.byType(AvatarEditDialog).evaluate().isEmpty,
      );
      final profile = await robot.container
          .read(profileProvider.notifier)
          .loadAvatarProfile();
      final uri = profile.avatarUri!;
      expect(Uri.parse(uri).scheme, 'https');
      expect(uri, isNot(previous));
      expect(
        profile.avatarThumbnailUri,
        uri.replaceFirst('/512.jpg', '/128.jpg'),
      );
      await verifyPublicImage(uri);
      if (previous != null) await verifyPublicImage(previous);
      previous = uri;
      await robot.pumpUntil(
        description: 'decoded avatar visible in the profile',
        condition: () => find
            .descendant(
              of: find.byType(AvatarBadge),
              matching: find.byWidgetPredicate(
                (widget) => widget is RawImage && widget.image != null,
              ),
            )
            .evaluate()
            .isNotEmpty,
      );
    }
    await tap('profile-edit-change-avatar-button');
    await editorReady('avatar-clear');
    await tap('avatar-clear');
    await tap('avatar-clear-cancel');
    expect(
      (await robot.container.read(profileProvider.notifier).loadAvatarProfile())
          .avatarUri,
      previous,
    );
    await tap('avatar-clear');
    await tap('avatar-clear-confirm');
    await robot.pumpUntil(
      description: 'clear commits and dismisses editor',
      condition: () => find.byType(AvatarEditDialog).evaluate().isEmpty,
    );
    final cleared = await robot.container
        .read(profileProvider.notifier)
        .loadAvatarProfile();
    expect(cleared.avatarUri, isNull);
    expect(cleared.avatarThumbnailUri, isNull);
    await robot.pumpUntil(
      description: 'character fallback replaces decoded avatar',
      condition: () => find
          .descendant(
            of: find.byType(AvatarBadge),
            matching: find.byType(RawImage),
          )
          .evaluate()
          .isEmpty,
    );
    await verifyPublicImage(previous!);
    await _attestPassedCases(<String, List<String>>{
      'AVATAR-E2E-001': const <String>[
        'crop_upload_and_visible_image',
        'replacement_immutable_url_and_clear_fallback',
        'bounded_public_jpeg_and_old_url_retained',
      ],
    });
  } finally {
    FileSelectorPlatform.instance = originalChooser;
    client.close(force: true);
    await fixtures.delete(recursive: true);
  }
}
