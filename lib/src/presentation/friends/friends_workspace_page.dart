import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui_feedback.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/app_message.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../chat/chat_page.dart';
import '../group/group_chat_navigation.dart';
import '../group/group_list_page.dart';
import '../profile/peer_profile_page.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'friends_navigation_provider.dart';
import 'friends_page.dart';
import 'friends_provider.dart';

class FriendsWorkspacePage extends ConsumerStatefulWidget {
  const FriendsWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  ConsumerState<FriendsWorkspacePage> createState() =>
      _FriendsWorkspacePageState();
}

class _FriendsWorkspacePageState extends ConsumerState<FriendsWorkspacePage> {
  final GlobalKey<NavigatorState> _compactNavigatorKey =
      GlobalKey<NavigatorState>();

  Future<void> _showGroupChat(GroupSummary group) async {
    try {
      final conversation = await prepareGroupChat(ref, group);
      if (!mounted) {
        return;
      }
      ref
          .read(friendsWorkspaceNavigationProvider.notifier)
          .showGroupChat(conversation);
    } catch (error) {
      if (mounted) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final navigation = ref.watch(friendsWorkspaceNavigationProvider);
    final controller = ref.read(friendsWorkspaceNavigationProvider.notifier);
    if (!responsive.supportsTwoPane) {
      final handlesSystemBack =
          !AwikiShellNavigationScope.isPresent(context) ||
          ref.watch(shellDestinationProvider) == ShellDestination.contacts;
      return NavigatorPopHandler<void>(
        enabled: handlesSystemBack,
        onPopWithResult: (_) {
          _compactNavigatorKey.currentState?.pop<void>();
        },
        child: Navigator(
          key: _compactNavigatorKey,
          pages: <Page<void>>[
            CupertinoPage<void>(
              key: const ValueKey<String>('friends-directory'),
              child: FriendsPage(
                onGroupTap: controller.showGroups,
                onFollowingTap: () => controller.showRelationships(
                  FriendsRelationshipListType.following,
                ),
                onFollowersTap: () => controller.showRelationships(
                  FriendsRelationshipListType.followers,
                ),
                onContactTap: controller.showProfile,
                onGroupChatTap: _showGroupChat,
              ),
            ),
            if (navigation.keepsRelationshipPageInCompactStack)
              CupertinoPage<void>(
                key: ValueKey<String>(
                  'friends-relationships:${navigation.relationshipType.name}',
                ),
                child: RelationshipListPage(
                  type: navigation.relationshipType,
                  onContactTap: controller.showProfile,
                ),
              ),
            if (navigation.detail == FriendsWorkspaceDetail.groups)
              const CupertinoPage<void>(
                key: ValueKey<String>('friends-groups'),
                child: GroupListPage(),
              ),
            if (navigation.detail == FriendsWorkspaceDetail.groupChat &&
                navigation.selectedGroupConversation != null)
              CupertinoPage<void>(
                key: ValueKey<String>(
                  'friends-group-chat:${navigation.selectedGroupConversation!.conversationId}',
                ),
                child: ChatPage(
                  conversation: navigation.selectedGroupConversation!,
                ),
              ),
            if (navigation.detail == FriendsWorkspaceDetail.profile &&
                navigation.selectedDid != null)
              CupertinoPage<void>(
                key: ValueKey<String>(
                  'friends-profile:${navigation.selectedDid}',
                ),
                child: PeerProfilePage(
                  did: navigation.selectedDid!,
                  keepConversationInCurrentNavigator: true,
                ),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key != const ValueKey<String>('friends-directory')) {
              controller.closeDetail();
            }
          },
        ),
      );
    }

    return AwikiSidebarWorkspace(
      footer: widget.listFooter,
      sidebar: FriendsPage(
        embedded: true,
        bottomInset: widget.listFooter == null ? 24 : 16,
        onGroupTap: controller.showGroups,
        onFollowingTap: () =>
            controller.showRelationships(FriendsRelationshipListType.following),
        onFollowersTap: () =>
            controller.showRelationships(FriendsRelationshipListType.followers),
        onContactTap: controller.showProfile,
        onGroupChatTap: _showGroupChat,
      ),
      detailPane: switch (navigation.detail) {
        FriendsWorkspaceDetail.overview => const AwikiWorkspaceEmptyDetail(),
        FriendsWorkspaceDetail.relationships => RelationshipListPage(
          key: ValueKey<FriendsRelationshipListType>(
            navigation.relationshipType,
          ),
          type: navigation.relationshipType,
          embedded: true,
          onContactTap: controller.showProfile,
        ),
        FriendsWorkspaceDetail.groups => const GroupListPage(embedded: true),
        FriendsWorkspaceDetail.groupChat => ChatView(
          key: ValueKey<String>(
            'friends-group-chat:${navigation.selectedGroupConversation!.conversationId}',
          ),
          conversation: navigation.selectedGroupConversation!,
          embedded: true,
          onBack: controller.closeDetail,
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
