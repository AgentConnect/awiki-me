// Controlled rendering benchmark: real product list/avatar/cache, synthetic data
// and image transport. This is separate from real-backend product E2E.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:awiki_me/src/data/avatar/avatar_image_cache_io.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import '../../unit/test_support.dart';
import '../../unit/avatar/avatar_image_cache_test.dart' as transport;

class _Dataset extends ConversationListController {
  _Dataset(super.ref, List<ConversationSummary> rows) {
    state = ConversationListState(conversations: rows);
  }
  @override
  Future<void> refresh() async {}
}

class _Profiles extends PeerDisplayProfileController {
  _Profiles(super.ref, bool images) {
    state = PeerDisplayProfileState(
      unresolvedProfilesByDid: {
        for (var i = 0; i < 800; i++)
          'did:benchmark:$i': PeerDisplayProfile(
            did: 'did:benchmark:$i',
            avatarUri: images
                ? 'https://avatar-benchmark.invalid/member-$i.jpg'
                : null,
          ),
      },
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    '1000 conversation avatar scrolling cold/warm profile benchmark',
    (tester) async {
      expect(kProfileMode, isTrue, reason: 'Frame evidence requires --profile');
      final root = await Directory.systemTemp.createTemp(
        'avatar-render-benchmark-',
      );
      final jpeg = img.encodeJpg(img.Image(width: 128, height: 128));
      final reports = <Map<String, Object?>>[];
      try {
        for (var round = 0; round < 3; round++) {
          final directory = await Directory('${root.path}/$round').create();
          for (final mode in ['fallback', 'cold', 'warm']) {
            debugPrint('avatar benchmark round=$round mode=$mode');
            final client = transport.Client(
              (_) async =>
                  transport.Response(jpeg, cache: 'max-age=604800, immutable'),
            );
            final cache = PlatformAvatarImageCache(
              'render-benchmark',
              client: client,
              directory: directory,
            );
            final rows = List.generate(
              1000,
              (i) => ConversationSummary(
                conversationId: 'benchmark:$i',
                threadId: 'benchmark:$i',
                displayName: '会话 $i',
                lastMessagePreview: '同一数据集 · 头像滚动测量',
                lastMessageAt: DateTime.utc(2026, 9, 28),
                unreadCount: i % 4,
                isGroup: i % 5 == 0,
                avatarUri: mode == 'fallback' || i % 5 == 0
                    ? null
                    : 'https://avatar-benchmark.invalid/$i.jpg',
              ),
            );
            await tester.pumpWidget(
              buildLocalizedTestApp(
                // Match the normal App's Material-inside-Cupertino wrapper.
                // Without it Theme.of synthesizes a color scheme per avatar.
                home: Theme(
                  data: AwikiMeTheme.materialTheme,
                  child: const ConversationListPage(macStyle: true),
                ),
                providerOverrides: [
                  conversationListProvider.overrideWith(
                    (ref) => _Dataset(ref, rows),
                  ),
                  avatarImageCacheProvider.overrideWithValue(cache),
                  peerDisplayProfileProvider.overrideWith(
                    (ref) => _Profiles(ref, mode != 'fallback'),
                  ),
                  groupAvatarSummariesProvider.overrideWithValue({
                    for (var i = 0; i < 1000; i += 5)
                      'benchmark:$i': GroupSummary(
                        conversationId: 'benchmark:$i',
                        groupId: 'benchmark:$i',
                        description: '',
                        memberCount: 4,
                        lastMessageAt: null,
                        avatarMembers: List.generate(
                          4,
                          (j) => GroupAvatarMember(
                            memberKey: '$i:$j',
                            did: 'did:benchmark:${i ~/ 5 * 4 + j}',
                          ),
                        ),
                      ),
                  }),
                ],
              ),
            );
            await tester.pumpAndSettle();
            debugPrint('avatar benchmark mounted $round:$mode');
            final positions =
                tester
                    .stateList<ScrollableState>(find.byType(Scrollable))
                    .map((state) => state.position)
                    .toList()
                  ..sort(
                    (a, b) => b.maxScrollExtent.compareTo(a.maxScrollExtent),
                  );
            final position = positions.first;
            expect(position.maxScrollExtent, greaterThan(10000));
            final frames = <ui.FrameTiming>[];
            void record(List<ui.FrameTiming> values) => frames.addAll(values);
            binding.addTimingsCallback(record);
            try {
              // Real animated scrolling emits frames; no synchronous jump loop.
              await tester.runAsync(() async {
                await position
                    .animateTo(
                      position.maxScrollExtent,
                      duration: const Duration(seconds: 6),
                      curve: Curves.linear,
                    )
                    .timeout(const Duration(seconds: 15));
                await position
                    .animateTo(
                      0,
                      duration: const Duration(seconds: 6),
                      curve: Curves.linear,
                    )
                    .timeout(const Duration(seconds: 15));
              });
              await tester.pump(const Duration(milliseconds: 250));
            } finally {
              binding.removeTimingsCallback(record);
            }
            debugPrint('avatar benchmark scrolled $round:$mode');
            await tester.runAsync(
              () => cache.flush().timeout(const Duration(seconds: 30)),
            );
            debugPrint('avatar benchmark flushed $round:$mode');
            expect(frames.length, greaterThan(120));
            final builds =
                frames
                    .map((f) => f.buildDuration.inMicroseconds / 1000)
                    .toList()
                  ..sort();
            final rasters =
                frames
                    .map((f) => f.rasterDuration.inMicroseconds / 1000)
                    .toList()
                  ..sort();
            reports.add({
              'round': round,
              'mode': mode,
              'conversations': rows.length,
              'groupsWithFourTiles': 200,
              'frames': frames.length,
              'buildP95Ms': builds[(builds.length * .95).ceil() - 1],
              'rasterP95Ms': rasters[(rasters.length * .95).ceil() - 1],
              'imageRequests': client.requests.length,
            });
            if (mode == 'warm') expect(client.requests, isEmpty);
            await tester.pumpWidget(const SizedBox());
            cache.dispose();
          }
        }
        const output = String.fromEnvironment('AVATAR_PERFORMANCE_OUTPUT');
        expect(output, isNotEmpty);
        await File(output).writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'buildMode': 'profile',
            'baseline': 'same product list with character fallback',
            'transport': 'bounded synthetic JPEG; real disk/decode cache',
            'runs': reports,
          }),
          flush: true,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
