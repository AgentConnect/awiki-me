import 'package:flutter/cupertino.dart';

import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'friends_page.dart';

class FriendsWorkspacePage extends StatelessWidget {
  const FriendsWorkspacePage({
    super.key,
    this.listFooter,
  });

  final Widget? listFooter;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return const FriendsPage();
    }

    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: FriendsPage(
        embedded: true,
        bottomInset: listFooter == null ? 24 : 16,
      ),
      detailPane: const AwikiWorkspaceEmptyDetail(),
    );
  }
}
