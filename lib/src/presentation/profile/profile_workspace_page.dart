import 'package:flutter/cupertino.dart';

import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'profile_page.dart';

class ProfileWorkspacePage extends StatelessWidget {
  const ProfileWorkspacePage({
    super.key,
    this.listFooter,
  });

  final Widget? listFooter;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return const ProfilePage();
    }

    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: ProfilePage(
        embedded: true,
        bottomInset: listFooter == null ? 24 : 16,
      ),
      detailPane: const AwikiWorkspaceEmptyDetail(),
    );
  }
}
