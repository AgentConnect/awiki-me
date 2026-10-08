import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:awiki_me/src/domain/entities/agent/agent_avatar.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/presentation/shared/agent_avatar_image.dart';
import 'dart:typed_data';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all 32 packaged presets decode as looping multi-frame GIFs', () async {
    for (final id in agentAvatarPresetIds) {
      final uri = '/avatars/presets/$id.gif';
      final path = AgentAvatarImage.packagedAsset(uri);
      expect(path, 'assets/avatars/agents/$id.gif');
      final data = await rootBundle.load(path!);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        targetWidth: 48,
      );
      expect(codec.frameCount, 32, reason: id);
      expect(codec.repetitionCount, -1, reason: id);
      final first = await codec.getNextFrame();
      expect(first.duration, const Duration(milliseconds: 100));
      first.image.dispose();
      codec.dispose();
    }
  });
  testWidgets('failed animated decoding falls back to the poster', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentAvatarBytesProvider.overrideWith(
            (ref, uri) async => Uint8List.fromList([1, 2, 3]),
          ),
        ],
        child: const CupertinoApp(
          home: Center(
            child: AgentAvatarImage(
              uri: 'https://example.com/broken.gif',
              posterUri: '/avatars/presets/legal.png',
              size: 48,
              fallback: Text('fallback'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final poster = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is ResizeImage &&
          (widget.image as ResizeImage).imageProvider is AssetImage &&
          ((widget.image as ResizeImage).imageProvider as AssetImage).assetName
              .endsWith('legal.png'),
    );
    for (var i = 0; i < 20 && poster.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(poster, findsOneWidget);
    expect(tester.getSize(find.byType(AgentAvatarImage)), const Size(48, 48));
    await tester.pumpWidget(const SizedBox());
  });
  test('avatar survives Inventory serialization and editable labels', () {
    final summary = AgentSummary.fromJson({
      'agent_did': 'did:agent',
      'agent_kind': 'runtime',
      'display_name': 'Before',
      'profile_summary': {
        'avatar': {
          'agent_id': 'stable',
          'source': 'preset',
          'preset_id': 'financing',
          'poster_uri': '/avatars/presets/financing.png',
          'version': '4',
          'status': 'ready',
        },
      },
    });
    final renamed = AgentSummary.fromJson({
      ...summary.toJson(),
      'display_name': 'After',
      'handle': 'after.example',
    });
    expect(renamed.avatar?.agentId, 'stable');
    expect(renamed.avatar?.version, '4');
    expect(
      AgentAvatar.defaultPreset('stable'),
      AgentAvatar.defaultPreset('stable'),
    );
    expect(agentAvatarPresetIds.toSet(), hasLength(32));
  });

  for (final reduced in [false, true]) {
    testWidgets('individual avatar motion policy reduced=$reduced', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          child: CupertinoApp(
            home: Center(
              child: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: const AgentAvatarImage(
                  uri: '/avatars/presets/research.gif',
                  posterUri: '/avatars/presets/research.png',
                  size: 48,
                  fallback: Text('fallback'),
                ),
              ),
            ),
          ),
        ),
      );
      final image =
          (tester.widget<Image>(find.byType(Image).first).image as ResizeImage)
                  .imageProvider
              as AssetImage;
      expect(image.assetName, endsWith(reduced ? '.png' : '.gif'));
      expect(tester.getSize(find.byType(AgentAvatarImage)), const Size(48, 48));
      expect(find.byType(ClipRRect), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('mosaic tile always uses the cover', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: Center(
            child: AgentAvatarImage(
              uri: '/avatars/presets/legal.gif',
              posterUri: '/avatars/presets/legal.png',
              size: 34,
              staticOnly: true,
              fallback: Text('fallback'),
            ),
          ),
        ),
      ),
    );
    expect(
      ((tester.widget<Image>(find.byType(Image).first).image as ResizeImage)
                  .imageProvider
              as AssetImage)
          .assetName,
      endsWith('legal.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('invalid remote images retain the fallback and fixed geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: CupertinoApp(
          home: Center(
            child: AgentAvatarImage(
              uri: 'http://invalid/animated.gif',
              posterUri: 'data:image/png;base64,invalid',
              size: 56,
              fallback: Text('fallback'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('fallback'), findsOneWidget);
    expect(tester.getSize(find.byType(AgentAvatarImage)), const Size(56, 56));
    await tester.pumpWidget(const SizedBox());
  });
}
