import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../group/group_list_page.dart';
import '../profile/peer_profile_page.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'friends_navigation_provider.dart';
import 'friends_page.dart';
import 'friends_provider.dart';

class FriendsWorkspacePage extends ConsumerWidget {
  const FriendsWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    final navigation = ref.watch(friendsWorkspaceNavigationProvider);
    final controller = ref.read(friendsWorkspaceNavigationProvider.notifier);
    if (!responsive.supportsTwoPane) {
      return Navigator(
        pages: <Page<void>>[
          CupertinoPage<void>(
            key: const ValueKey<String>('friends-directory'),
            child: FriendsPage(
              initialRelationshipType: navigation.relationshipType,
              onRelationshipTypeChanged: controller.showDirectory,
              onGroupTap: controller.showGroups,
              onContactTap: controller.showProfile,
            ),
          ),
          if (navigation.detail == FriendsWorkspaceDetail.groups)
            const CupertinoPage<void>(
              key: ValueKey<String>('friends-groups'),
              child: GroupListPage(),
            ),
          if (navigation.detail == FriendsWorkspaceDetail.profile &&
              navigation.selectedDid != null)
            CupertinoPage<void>(
              key: ValueKey<String>(
                'friends-profile:${navigation.selectedDid}',
              ),
              child: PeerProfilePage(did: navigation.selectedDid!),
            ),
        ],
        onDidRemovePage: (page) {
          if (page.key != const ValueKey<String>('friends-directory')) {
            controller.closeDetail();
          }
        },
      );
    }

    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: FriendsPage(
        embedded: true,
        bottomInset: listFooter == null ? 24 : 16,
        onGroupTap: controller.showGroups,
        onFollowingTap: () =>
            controller.showDirectory(FriendsRelationshipListType.following),
        onFollowersTap: () =>
            controller.showDirectory(FriendsRelationshipListType.followers),
        onContactTap: controller.showProfile,
      ),
      detailPane: switch (navigation.detail) {
        FriendsWorkspaceDetail.groups => const GroupListPage(embedded: true),
        FriendsWorkspaceDetail.directory => RelationshipDirectoryPage(
          initialType: navigation.relationshipType,
          embedded: true,
          onContactTap: controller.showProfile,
          onTypeChanged: controller.showDirectory,
        ),
        FriendsWorkspaceDetail.profile => PeerProfilePage(
          key: ValueKey<String>(navigation.selectedDid ?? ''),
          did: navigation.selectedDid!,
          embedded: true,
          onBack: controller.closeDetail,
        ),
      },
    );
  }
}
