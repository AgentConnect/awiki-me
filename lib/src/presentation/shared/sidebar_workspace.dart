import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'awiki_me_design.dart';
import 'responsive_layout.dart';

class AwikiSidebarWorkspace extends StatelessWidget {
  const AwikiSidebarWorkspace({
    super.key,
    required this.sidebar,
    required this.detailPane,
    this.footer,
  });

  final Widget sidebar;
  final Widget detailPane;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AwikiPaneLayout(
      listPaneWidth: 272,
      minListPaneWidth: 240,
      minDetailPaneWidth: 360,
      listPane: DecoratedBox(
        decoration: BoxDecoration(color: context.awikiTheme.background),
        child: Column(
          children: <Widget>[
            Expanded(child: sidebar),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: footer!,
              ),
          ],
        ),
      ),
      detailPane: detailPane,
    );
  }
}

class AwikiSidebarHeader extends StatelessWidget {
  const AwikiSidebarHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final type = theme.typographyFor(AwikiMeTypographyMode.expanded);
    return Container(
      height: responsive.displayScaled(56),
      padding: EdgeInsets.symmetric(horizontal: responsive.spacing(14)),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.navTitle.copyWith(color: theme.title),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AwikiWorkspaceEmptyDetail extends StatelessWidget {
  const AwikiWorkspaceEmptyDetail({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.background),
      child: Center(
        child: Opacity(
          opacity: 0.22,
          child: SvgPicture.asset(
            'assets/branding/awiki-me-mark.svg',
            width: 248,
            height: 248,
            colorFilter: ColorFilter.mode(theme.tertiaryText, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
