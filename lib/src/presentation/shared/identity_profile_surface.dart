import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

class IdentityProfileCard extends StatelessWidget {
  const IdentityProfileCard({
    super.key,
    required this.header,
    this.metadata = const <Widget>[],
    this.footer,
  });

  final Widget header;
  final List<Widget> metadata;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final radius = responsive.radius(8);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: theme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(responsive.spacing(16)),
            child: header,
          ),
          ...metadata,
          if (footer != null)
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.border)),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: responsive.spacing(16),
                vertical: responsive.spacing(13),
              ),
              child: footer,
            ),
        ],
      ),
    );
  }
}

class IdentityProfileMetadataRow extends StatelessWidget {
  const IdentityProfileMetadataRow({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      constraints: BoxConstraints(
        minHeight: responsive.displayScaled(responsive.isPhone ? 54 : 48),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(16),
        vertical: responsive.spacing(9),
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: responsive.displayScaled(responsive.isPhone ? 56 : 70),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.bodySm,
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(10)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class IdentityDocumentCard extends StatelessWidget {
  const IdentityDocumentCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              color: theme.title,
              fontSize: responsive.bodyMd,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: responsive.spacing(10)),
          child,
        ],
      ),
    );
  }
}

class IdentityProfileLinkValue extends StatelessWidget {
  const IdentityProfileLinkValue({
    super.key,
    required this.value,
    required this.actionLabel,
    required this.onTap,
  });

  final String value;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: responsive.bodySm,
              height: 1.35,
              color: theme.primaryDark,
            ),
          ),
        ),
        SizedBox(width: responsive.spacing(8)),
        SelectionContainer.disabled(
          child: AppIconButton(
            onPressed: onTap,
            semanticLabel: actionLabel,
            tooltip: actionLabel,
            size: responsive.displayScaled(30),
            backgroundColor: theme.surface,
            borderColor: theme.border,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: Icon(
              CupertinoIcons.arrow_up_right,
              color: theme.primaryDark,
              size: responsive.iconSm,
            ),
          ),
        ),
      ],
    );
  }
}
