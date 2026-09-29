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
  _DesktopCliPeerSmokeConfig config,
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
      await tap('profile-avatar');
      await editorReady('avatar-pick');
      await tap('avatar-pick');
      await editorReady('avatar-save');
      final crop = tester.getRect(find.byType(Crop));
      final preview = find.byKey(const Key('avatar-new-preview'));
      final before =
          (tester.widget<CustomPaint>(preview).painter!
                  as AvatarCropPreviewPainter)
              .area;
      // The landscape fixture fills the crop viewport vertically.
      await tester.dragFrom(
        crop.center + Offset(crop.height / 2 - 1, crop.height / 2 - 1),
        const Offset(-48, -48),
      );
      await tester.pump();
      final resized =
          (tester.widget<CustomPaint>(preview).painter!
                  as AvatarCropPreviewPainter)
              .area;
      expect(resized.width, lessThan(before.width));
      expect(resized.width, closeTo(resized.height, .01));
      await tester.dragFrom(
        crop.center - const Offset(24, 24),
        const Offset(16, 0),
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
    await tap('profile-avatar');
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
    // The independent CLI identity gets its image through the source-matched,
    // test-only Rust probe; no keys or tokens cross into Flutter test code.
    await _uploadPeerAvatarFixture(config);
    await tap('profile-back-button');
    await robot.startDirectConversation(config.cliHandle);
    await robot.openSelectedPeerInfo();
    await robot.pumpUntil(
      description: 'peer profile has a decoded avatar',
      condition: () => find
          .descendant(
            of: find.byType(ProfileAvatar),
            matching: find.byType(RawImage),
          )
          .evaluate()
          .isNotEmpty,
    );
    await robot.tapOne(
      find.byType(ProfileAvatar),
      description: 'peer avatar preview',
    );
    await robot.pumpUntilFinder(
      find.byKey(const Key('avatar-preview-image')),
      description: 'large peer avatar',
    );
    await tap('avatar-preview-close');
    expect(find.byType(AvatarPreviewDialog), findsNothing);
    await _attestPassedCases(<String, List<String>>{
      'AVATAR-E2E-001': const <String>[
        'crop_upload_and_visible_image',
        'replacement_immutable_url_and_clear_fallback',
        'bounded_public_jpeg_and_old_url_retained',
        'peer_profile_main_image_preview',
      ],
    });
  } finally {
    FileSelectorPlatform.instance = originalChooser;
    client.close(force: true);
    await fixtures.delete(recursive: true);
  }
}

Future<void> _uploadPeerAvatarFixture(_DesktopCliPeerSmokeConfig config) async {
  final bytes = List<int>.generate(
    16,
    (_) => math.Random.secure().nextInt(256),
  );
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  final requestId =
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  final source = img.Image(width: 512, height: 512);
  img.fill(source, color: img.ColorRgb8(80, 140, 220));
  final binary = '${File(config.cliBin).parent.path}/awiki-system-test-probe';
  final process = await Process.start(
    binary,
    const [],
    environment: {
      'HOME': config.cliHome,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
      'AWIKI_CLI_UPDATE_CACHE_ONLY': '1',
    },
    includeParentEnvironment: false,
  );
  unawaited(process.stderr.drain<void>());
  try {
    process.stdin.writeln(
      jsonEncode({
        'id': 1,
        'action': 'avatar_fixture_set',
        'params': {
          'request_id': requestId,
          'image_base64': base64Encode(img.encodeJpg(source)),
        },
      }),
    );
    await process.stdin.close();
    final output = await process.stdout
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 60));
    final code = await process.exitCode;
    if (code != 0 || output.length > 8192) {
      throw StateError('Avatar fixture failed');
    }
    final receipt = jsonDecode(output);
    if (receipt is! Map || receipt['ok'] != true || receipt['id'] != 1) {
      throw StateError('Avatar fixture receipt invalid');
    }
  } finally {
    process.kill();
  }
}
