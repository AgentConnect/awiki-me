import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../domain/entities/identity_type.dart';
import '../../l10n/l10n.dart';
import 'avatar_badge.dart';
import 'awiki_me_design.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

class IdentityProfileLayout {
  const IdentityProfileLayout._();

  static const double dialogMaxWidth = 560;

  static double dialogRadius(BuildContext context) =>
      context.awikiResponsive.displayScaled(AwikiMeRadii.md);

  static double contentInset(BuildContext context) {
    final responsive = context.awikiResponsive;
    return responsive.displayScaled(responsive.isCompact ? 16 : 20);
  }

  static double sectionGap(BuildContext context) =>
      context.awikiResponsive.displayScaled(16);
}

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
    final responsive = context.awikiResponsive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            top: responsive.displayScaled(10),
            bottom: responsive.displayScaled(24),
          ),
          child: header,
        ),
        ...metadata,
        if (footer != null)
          Padding(
            padding: EdgeInsets.only(
              top: responsive.displayScaled(16),
              bottom: responsive.displayScaled(4),
            ),
            child: footer,
          ),
      ],
    );
  }
}

class IdentityProfileHeader extends StatelessWidget {
  const IdentityProfileHeader({
    super.key,
    required this.displayName,
    required this.avatarSeed,
    this.handle,
    this.supportingText,
    this.avatarUri,
    this.avatarUserId,
    this.avatarSize,
    this.badges = const <Widget>[],
    this.titleTrailing,
    this.trailing,
    this.avatarKey,
    this.displayNameKey,
    this.handleKey,
    this.supportingTextKey,
  });

  final String displayName;
  final String avatarSeed;
  final String? handle;
  final String? supportingText;
  final String? avatarUri;
  final String? avatarUserId;
  final double? avatarSize;
  final List<Widget> badges;
  final Widget? titleTrailing;
  final Widget? trailing;
  final Key? avatarKey;
  final Key? displayNameKey;
  final Key? handleKey;
  final Key? supportingTextKey;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final resolvedAvatarSize =
        avatarSize ?? responsive.displayScaled(responsive.isCompact ? 58 : 52);
    final normalizedHandle = handle?.trim() ?? '';
    final normalizedSupportingText = supportingText?.trim() ?? '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackTrailing = trailing != null && constraints.maxWidth < 270;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AvatarBadge(
              key: avatarKey,
              seed: avatarSeed,
              size: resolvedAvatarSize,
              avatarUri: avatarUri,
              userId: avatarUserId,
            ),
            SizedBox(width: responsive.displayScaled(16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          displayName,
                          key: displayNameKey,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.title,
                            fontSize: responsive.titleXl,
                            fontWeight: FontWeight.w400,
                            height: 1.22,
                          ),
                        ),
                      ),
                      if (titleTrailing != null) ...<Widget>[
                        SizedBox(width: responsive.displayScaled(6)),
                        titleTrailing!,
                      ],
                    ],
                  ),
                  if (normalizedHandle.isNotEmpty) ...<Widget>[
                    SizedBox(height: responsive.displayScaled(4)),
                    Text(
                      normalizedHandle,
                      key: handleKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: responsive.bodyMd,
                        height: 1.28,
                      ),
                    ),
                  ],
                  if (normalizedSupportingText.isNotEmpty) ...<Widget>[
                    SizedBox(height: responsive.displayScaled(4)),
                    Text(
                      normalizedSupportingText,
                      key: supportingTextKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.tertiaryText,
                        fontSize: responsive.bodySm,
                        height: 1.28,
                      ),
                    ),
                  ],
                  if (badges.isNotEmpty) ...<Widget>[
                    SizedBox(height: responsive.displayScaled(10)),
                    Wrap(
                      spacing: responsive.displayScaled(8),
                      runSpacing: responsive.displayScaled(8),
                      children: badges,
                    ),
                  ],
                ],
              ),
            ),
            if (!stackTrailing && trailing != null) ...<Widget>[
              SizedBox(width: responsive.displayScaled(12)),
              trailing!,
            ],
          ],
        );

        if (!stackTrailing) {
          return identity;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            identity,
            SizedBox(height: responsive.displayScaled(12)),
            Align(alignment: Alignment.centerRight, child: trailing),
          ],
        );
      },
    );
  }
}

enum IdentityProfileBadgeTone {
  neutral,
  outlined,
  success,
  runtime,
  status,
  muted,
}

class IdentityProfileBadge extends StatelessWidget {
  const IdentityProfileBadge({
    super.key,
    required this.label,
    this.tone = IdentityProfileBadgeTone.neutral,
    this.compact = false,
  });

  final String label;
  final IdentityProfileBadgeTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final colors = switch (tone) {
      IdentityProfileBadgeTone.neutral => (
        theme.subtleSurface,
        theme.secondaryText,
        CupertinoColors.transparent,
      ),
      IdentityProfileBadgeTone.outlined => (
        theme.surface,
        theme.secondaryText,
        theme.border,
      ),
      IdentityProfileBadgeTone.success => (
        const Color(0xFFE6F8EE),
        theme.success,
        CupertinoColors.transparent,
      ),
      IdentityProfileBadgeTone.runtime => (
        const Color(0xFFE4F3FA),
        AwikiMePalette.badgeBlue,
        CupertinoColors.transparent,
      ),
      IdentityProfileBadgeTone.status => (
        const Color(0xFFFFF4D6),
        theme.warning,
        CupertinoColors.transparent,
      ),
      IdentityProfileBadgeTone.muted => (
        theme.mutedSurface,
        theme.secondaryText,
        CupertinoColors.transparent,
      ),
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(compact ? 7 : 10),
        vertical: responsive.displayScaled(compact ? 3 : 5),
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
        border: Border.all(color: colors.$3),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.$2,
          fontSize: compact ? 11 : responsive.bodySm,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

class IdentityTypePresentation {
  const IdentityTypePresentation._();

  static String label(BuildContext context, IdentityType type) {
    final l10n = context.l10n;
    if (!type.isAgent) {
      return switch (type.subjectKind) {
        IdentitySubjectKind.user => l10n.identityTypeUser,
        IdentitySubjectKind.group => l10n.identityTypeGroup,
        IdentitySubjectKind.agent => l10n.identityTypeAgent,
        IdentitySubjectKind.unknown => l10n.identityTypeUnknown,
      };
    }
    return switch (type.agentKind ?? IdentityAgentKind.unknown) {
      IdentityAgentKind.runtime => l10n.identityTypeRuntimeAgent,
      IdentityAgentKind.skill => l10n.identityTypeSkillAgent,
      IdentityAgentKind.daemon => l10n.identityTypeDaemon,
      IdentityAgentKind.unknown => l10n.identityTypeAgent,
    };
  }

  static IdentityProfileBadgeTone tone(IdentityType type) {
    if (!type.isAgent) {
      return type.subjectKind == IdentitySubjectKind.user
          ? IdentityProfileBadgeTone.success
          : IdentityProfileBadgeTone.outlined;
    }
    return switch (type.agentKind ?? IdentityAgentKind.unknown) {
      IdentityAgentKind.runtime ||
      IdentityAgentKind.skill => IdentityProfileBadgeTone.runtime,
      IdentityAgentKind.daemon => IdentityProfileBadgeTone.muted,
      IdentityAgentKind.unknown => IdentityProfileBadgeTone.neutral,
    };
  }
}

class IdentityTypeBadge extends StatelessWidget {
  const IdentityTypeBadge({
    super.key,
    required this.type,
    this.compact = false,
  });

  final IdentityType type;
  final bool compact;

  @override
  Widget build(BuildContext context) => IdentityProfileBadge(
    label: IdentityTypePresentation.label(context, type),
    tone: IdentityTypePresentation.tone(type),
    compact: compact,
  );
}

class IdentityProfileActionButton extends StatelessWidget {
  const IdentityProfileActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.emphasized = false,
    this.isLoading = false,
    this.progressKey,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool isLoading;
  final Key? progressKey;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final enabled = onPressed != null && !isLoading;
    final radius = BorderRadius.circular(
      responsive.displayScaled(AwikiMeRadii.control),
    );
    final foreground = emphasized
        ? theme.primaryForeground
        : theme.secondaryText;
    return AppPressable(
      onTap: enabled ? onPressed : null,
      semanticLabel: label,
      tooltip: label,
      enabled: enabled,
      scaleOnPress: true,
      pressedScale: 0.97,
      borderRadius: radius,
      builder: (context, state, child) => AnimatedOpacity(
        opacity: !state.enabled
            ? 0.58
            : state.pressed
            ? 0.84
            : state.hovered || state.focused
            ? 0.93
            : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: child,
      ),
      child: Container(
        constraints: BoxConstraints(
          minWidth: responsive.displayScaled(64),
          minHeight: responsive.displayScaled(40),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.displayScaled(14),
          vertical: responsive.displayScaled(9),
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: emphasized ? theme.primary : theme.surface,
          borderRadius: radius,
          border: Border.all(color: emphasized ? theme.primary : theme.border),
          boxShadow: emphasized
              ? <BoxShadow>[
                  BoxShadow(
                    color: theme.primary.withValues(alpha: 0.18),
                    blurRadius: responsive.displayScaled(8),
                    offset: Offset(0, responsive.displayScaled(3)),
                  ),
                ]
              : null,
        ),
        child: isLoading
            ? CupertinoActivityIndicator(
                key: progressKey,
                radius: responsive.displayScaled(8),
                color: foreground,
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: responsive.bodyMd,
                  fontWeight: FontWeight.w400,
                  height: 1,
                ),
              ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: responsive.displayScaled(responsive.isCompact ? 58 : 56),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: responsive.displayScaled(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: responsive.displayScaled(
                    responsive.isCompact ? 64 : 88,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: responsive.bodyMd,
                    ),
                  ),
                ),
                SizedBox(width: responsive.displayScaled(12)),
                Expanded(child: child),
              ],
            ),
          ),
        ),
        Container(height: 1, color: theme.border),
      ],
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
    final radius = responsive.displayScaled(AwikiMeRadii.md);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.displayScaled(20)),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(radius),
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
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
          SizedBox(height: responsive.displayScaled(12)),
          child,
        ],
      ),
    );
  }
}

class IdentityDocumentContent extends StatelessWidget {
  const IdentityDocumentContent({
    super.key,
    required this.content,
    required this.emptyText,
    this.tags = const <String>[],
    this.emptyState,
  });

  final String content;
  final String emptyText;
  final List<String> tags;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final normalizedContent = content.trim();
    final bodyStyle = TextStyle(
      color: theme.body,
      fontSize: responsive.bodyMd,
      height: 1.55,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (normalizedContent.isEmpty)
          emptyState ??
              Text(
                emptyText,
                style: bodyStyle.copyWith(color: theme.secondaryText),
              )
        else
          MarkdownBody(
            data: normalizedContent,
            selectable: false,
            styleSheet: MarkdownStyleSheet(
              p: bodyStyle,
              strong: bodyStyle.copyWith(fontWeight: FontWeight.w400),
              h1: bodyStyle.copyWith(
                fontSize: responsive.titleXl,
                fontWeight: FontWeight.w400,
              ),
              h2: bodyStyle.copyWith(
                fontSize: responsive.titleLg,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        if (tags.isNotEmpty) ...<Widget>[
          SizedBox(height: responsive.displayScaled(18)),
          Wrap(
            spacing: responsive.displayScaled(8),
            runSpacing: responsive.displayScaled(8),
            children: tags.map((tag) => AppPill(label: tag)).toList(),
          ),
        ],
      ],
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
              fontSize: responsive.bodyMd,
              height: 1.35,
              color: theme.primary,
            ),
          ),
        ),
        SizedBox(width: responsive.displayScaled(8)),
        SelectionContainer.disabled(
          child: AppIconButton(
            onPressed: onTap,
            semanticLabel: actionLabel,
            tooltip: actionLabel,
            size: responsive.displayScaled(32),
            borderRadius: BorderRadius.circular(
              responsive.displayScaled(AwikiMeRadii.control),
            ),
            child: Icon(
              CupertinoIcons.arrow_up_right,
              color: theme.secondaryText,
              size: responsive.iconSm,
            ),
          ),
        ),
      ],
    );
  }
}
