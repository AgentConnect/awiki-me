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
      listPaneWidth: 340,
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
