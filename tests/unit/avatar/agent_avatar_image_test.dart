import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:awiki_me/src/domain/entities/agent/agent_avatar.dart';
import 'package:awiki_me/src/presentation/shared/agent_avatar_image.dart';

void main() {
  final png = Uint8List.fromList(
    img.encodePng(img.Image(width: 8, height: 8, numChannels: 4)),
  );
  for (final still in [false, true]) {
    testWidgets(
      'remote sources preserve foreign origin; static policy=$still',
      (tester) async {
        final requested = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              agentAvatarBytesProvider.overrideWith((ref, uri) async {
                requested.add(uri);
                return png;
              }),
            ],
            child: CupertinoApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: still),
                child: const Center(
                  child: AgentAvatarImage(
                    uri: 'https://foreign.example/avatars/presets/new.gif',
                    posterUri:
                        'https://foreign.example/avatars/presets/new.png',
                    size: 48,
                    fallback: Text('fallback'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          requested,
          contains('https://foreign.example/avatars/presets/new.png'),
        );
        expect(
          requested.contains('https://foreign.example/avatars/presets/new.gif'),
          !still,
        );
        expect(
          tester.getSize(find.byType(AgentAvatarImage)),
          const Size(48, 48),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'unsafe and relative URLs use placeholder without local substitution',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            home: AgentAvatarImage(
              uri: '/avatars/presets/legal.gif',
              posterUri: 'http://invalid/a.png',
              size: 56,
              fallback: Text('fallback'),
            ),
          ),
        ),
      );
      expect(find.text('fallback'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('broken animation falls back to remote cover', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentAvatarBytesProvider.overrideWith(
            (ref, uri) async =>
                uri.endsWith('.gif') ? Uint8List.fromList([1, 2, 3]) : png,
          ),
        ],
        child: const CupertinoApp(
          home: AgentAvatarImage(
            uri: 'https://example.com/a.gif',
            posterUri: 'https://example.com/a.png',
            size: 48,
            fallback: Text('fallback'),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    final image = tester.widget<Image>(find.byType(Image).last);
    expect(
      ((image.image as ResizeImage).imageProvider as MemoryImage).bytes,
      png,
    );
    await tester.pumpWidget(const SizedBox());
  });
  test('catalog preserves server names, new IDs and availability', () {
    final preset = AgentAvatarPreset.fromJson({
      'id': 'future-id',
      'display_name': '服务端新增',
      'sort_order': 99,
      'selectable': false,
      'poster_uri': 'https://other.example/new.png',
    });
    expect(preset.id, 'future-id');
    expect(preset.displayName, '服务端新增');
    expect(preset.selectable, isFalse);
    expect(preset.posterUri, startsWith('https://other.example'));
  });
  testWidgets(
    'scrolling offscreen and inactive lifecycle replace animation with cover',
    (tester) async {
      final moving = Uint8List.fromList(
        img.encodePng(img.Image(width: 9, height: 9)),
      );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agentAvatarBytesProvider.overrideWith(
              (ref, uri) async => uri.endsWith('.gif') ? moving : png,
            ),
          ],
          child: CupertinoApp(
            home: ListView(
              controller: scroll,
              children: const [
                Center(
                  child: AgentAvatarImage(
                    uri: 'https://example.com/a.gif',
                    posterUri: 'https://example.com/a.png',
                    size: 48,
                    fallback: Text('fallback'),
                  ),
                ),
                SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      Uint8List visibleBytes() =>
          ((tester.widget<Image>(find.byType(Image).first).image as ResizeImage)
                      .imageProvider
                  as MemoryImage)
              .bytes;
      expect(visibleBytes(), moving);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(visibleBytes(), png);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      scroll.jumpTo(700);
      await tester.pump();
      await tester.pump();
      // Lazy viewports may dispose the offscreen tile altogether, which also stops its codec.
      if (find.byType(Image).evaluate().isNotEmpty) expect(visibleBytes(), png);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
