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

/// Reference desktop `.col-head`: a divider-free 52-unit row with a 16-unit
/// title and the pane's action on the right.
class AwikiSidebarHeader extends StatelessWidget {
  const AwikiSidebarHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      height: responsive.displayScaled(52),
      padding: EdgeInsets.fromLTRB(
        responsive.spacing(14),
        responsive.displayScaled(6),
        responsive.spacing(12),
        0,
      ),
      color: theme.surface,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.title,
                fontSize: 16,
                height: 1.3,
                fontWeight: FontWeight.w400,
              ),
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
