import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_workspace_page.dart';
import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _StaticFriendsController extends FriendsController {
  _StaticFriendsController(super.ref, FriendsState initialState) {
    state = initialState;
  }
}

void main() {
  testWidgets('桌面宽度下联系人页保持左右分栏布局', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:friend-1',
                    displayName: 'Alice',
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AwikiPaneLayout), findsOneWidget);
    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byType(FriendsWorkspacePage), findsOneWidget);
  });
}
