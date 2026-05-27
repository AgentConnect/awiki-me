import 'package:flutter/cupertino.dart';

import '../group/group_list_page.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'friends_page.dart';
import 'friends_provider.dart';

class FriendsWorkspacePage extends StatefulWidget {
  const FriendsWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  State<FriendsWorkspacePage> createState() => _FriendsWorkspacePageState();
}

enum _FriendsDetailPane { empty, groups, following, followers }

class _FriendsWorkspacePageState extends State<FriendsWorkspacePage> {
  _FriendsDetailPane _detailPane = _FriendsDetailPane.empty;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return const FriendsPage();
    }

    return AwikiSidebarWorkspace(
      footer: widget.listFooter,
      sidebar: FriendsPage(
        embedded: true,
        bottomInset: widget.listFooter == null ? 24 : 16,
        onGroupTap: responsive.isMacDesktop
            ? () {
                setState(() {
                  _detailPane = _FriendsDetailPane.groups;
                });
              }
            : null,
        onFollowingTap: responsive.isMacDesktop
            ? () {
                setState(() {
                  _detailPane = _FriendsDetailPane.following;
                });
              }
            : null,
        onFollowersTap: responsive.isMacDesktop
            ? () {
                setState(() {
                  _detailPane = _FriendsDetailPane.followers;
                });
              }
            : null,
      ),
      detailPane: switch (_detailPane) {
        _FriendsDetailPane.groups => const GroupListPage(embedded: true),
        _FriendsDetailPane.following => const RelationshipListPage(
          type: FriendsRelationshipListType.following,
          embedded: true,
        ),
        _FriendsDetailPane.followers => const RelationshipListPage(
          type: FriendsRelationshipListType.followers,
          embedded: true,
        ),
        _FriendsDetailPane.empty => const AwikiWorkspaceEmptyDetail(),
      },
    );
  }
}
