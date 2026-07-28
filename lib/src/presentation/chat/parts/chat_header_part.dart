part of '../chat_page.dart';

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.nickname,
    required this.embedded,
    required this.macStyle,
    required this.classification,
    required this.isDeletedAgentConversation,
    required this.onPeerInfoTap,
    this.onBack,
    this.onAddGroupMemberTap,
    this.isAddGroupMemberLoading = false,
  });

  final ConversationSummary conversation;
  final String? nickname;
  final bool embedded;
  final VoidCallback? onBack;
  final bool macStyle;
  final ConversationPeerClassification classification;
  final bool isDeletedAgentConversation;
  final VoidCallback onPeerInfoTap;
  final VoidCallback? onAddGroupMemberTap;
  final bool isAddGroupMemberLoading;

  @override
  Widget build(BuildContext context) {
    final profileNickname = nickname?.trim() ?? '';
    final compactName = profileNickname.isNotEmpty
        ? profileNickname
        : DidDisplayFormatter.conversationTitle(conversation, context.l10n);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final agentBadgeLabel = isDeletedAgentConversation
        ? context.l10n.chatAgentDeletedBadge
        : localizeConversationChatBadge(context.l10n, classification);
    final detailTypeLabel = localizeConversationPeerType(
      context.l10n,
      classification,
    );
    final openInfoLabel = context.l10n.chatOpenPeerInfo(detailTypeLabel);
    final showAddGroupMemberButton =
        conversation.isGroup && onAddGroupMemberTap != null;
    if (macStyle) {
      return Container(
        key: const Key('chat-header'),
        height: responsive.displayScaled(52),
        padding: EdgeInsets.fromLTRB(
          responsive.displayScaled(14),
          0,
          responsive.displayScaled(12),
          0,
        ),
        decoration: BoxDecoration(
          color: theme.chatSurface,
          border: Border(
            bottom: BorderSide(color: theme.border.withValues(alpha: 0.55)),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showSecurityPill = width >= 620;
            final avatarSize = responsive.displayScaled(30);

            return Row(
              children: <Widget>[
                _ChatHeaderIdentityTapTarget(
                  key: const Key('chat-peer-info-avatar-button'),
                  semanticLabel: openInfoLabel,
                  semanticsIdentifier: 'chat-peer-info-avatar-button',
                  onTap: onPeerInfoTap,
                  child: AvatarBadge(
                    seed: compactName,
                    size: avatarSize,
                    avatarUri: conversation.avatarUri,
                  ),
                ),
                SizedBox(width: responsive.displayScaled(8)),
                Expanded(
                  child: _MacHeaderIdentityText(
                    compactName: compactName,
                    agentBadgeLabel: agentBadgeLabel,
                    isDeletedAgentConversation: isDeletedAgentConversation,
                    showAgentBadge: width >= 500,
                    showSecurityPill: showSecurityPill,
                    semanticLabel: openInfoLabel,
                    onNameTap: onPeerInfoTap,
                  ),
                ),
                if (showAddGroupMemberButton) ...<Widget>[
                  SizedBox(width: responsive.displayScaled(12)),
                  _ChatHeaderAddGroupMemberButton(
                    onTap: isAddGroupMemberLoading ? null : onAddGroupMemberTap,
                    isLoading: isAddGroupMemberLoading,
                  ),
                ],
              ],
            );
          },
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSourceLabel = constraints.maxWidth >= 350;
        final sideWidth = responsive.displayScaled(showSourceLabel ? 82 : 44);
        return Container(
          key: const Key('chat-header'),
          height: responsive.displayScaled(52),
          padding: EdgeInsets.symmetric(horizontal: responsive.spacing(8)),
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(bottom: BorderSide(color: theme.border)),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: sideWidth,
                child: TopBarActionButton(
                  key: const Key('chat-back-button'),
                  onTap: onBack,
                  semanticsIdentifier: 'e2e-chat-back-button',
                  semanticsLabel: context.l10n.commonBack,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AwikiMeSemanticIcon(
                        role: AwikiMeIconRole.back,
                        color: theme.primaryDark,
                        size: responsive.iconSm,
                      ),
                      if (showSourceLabel) ...<Widget>[
                        SizedBox(width: responsive.spacing(3)),
                        Flexible(
                          child: Text(
                            context.l10n.shellNavMessages,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.primaryDark,
                              fontSize: responsive.bodySm,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _ChatHeaderIdentityTapTarget(
                  key: const Key('chat-peer-info-avatar-button'),
                  semanticLabel: openInfoLabel,
                  semanticsIdentifier: 'chat-peer-info-avatar-button',
                  onTap: onPeerInfoTap,
                  child: Text(
                    compactName,
                    key: const Key('chat-header-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: responsive.displayScaled(16),
                      fontWeight: FontWeight.w600,
                      color: theme.title,
                    ),
                  ),
                ),
              ),
              SizedBox(width: sideWidth),
            ],
          ),
        );
      },
    );
  }
}

class _ChatHeaderAddGroupMemberButton extends StatelessWidget {
  const _ChatHeaderAddGroupMemberButton({
    required this.onTap,
    required this.isLoading,
  });

  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppIconButton(
      key: const Key('chat-header-add-group-member-button'),
      onPressed: onTap,
      semanticLabel: context.l10n.groupAddMembers,
      semanticsIdentifier: 'e2e-chat-header-add-group-member-button',
      isLoading: isLoading,
      size: responsive.compactControlHeight,
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      backgroundColor: theme.primary.withValues(alpha: 0.06),
      borderColor: theme.primary.withValues(alpha: 0.12),
      child: Icon(
        CupertinoIcons.person_add,
        size: responsive.iconSm,
        color: theme.primaryDark,
      ),
    );
  }
}

class _ChatHeaderIdentityTapTarget extends StatelessWidget {
  const _ChatHeaderIdentityTapTarget({
    super.key,
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.semanticsIdentifier,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: semanticLabel,
      builder: (_, __, child) => child,
      child: child,
    );
  }
}

class _MacHeaderIdentityText extends StatelessWidget {
  const _MacHeaderIdentityText({
    required this.compactName,
    required this.agentBadgeLabel,
    required this.isDeletedAgentConversation,
    required this.showAgentBadge,
    required this.showSecurityPill,
    required this.semanticLabel,
    required this.onNameTap,
  });

  final String compactName;
  final String? agentBadgeLabel;
  final bool isDeletedAgentConversation;
  final bool showAgentBadge;
  final bool showSecurityPill;
  final String semanticLabel;
  final VoidCallback onNameTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        Flexible(
          child: _ChatHeaderIdentityTapTarget(
            semanticLabel: semanticLabel,
            onTap: onNameTap,
            child: Text(
              compactName,
              key: const Key('chat-header-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.awikiTheme.title,
                fontSize: responsive.displayScaled(14.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (agentBadgeLabel != null && showAgentBadge) ...<Widget>[
          SizedBox(width: responsive.displayScaled(8)),
          _MacChatPill(
            label: agentBadgeLabel!,
            color: isDeletedAgentConversation
                ? AwikiMePalette.mist
                : AwikiMePalette.brandAccentSoft,
            textColor: isDeletedAgentConversation
                ? AwikiMePalette.mutedNeutral
                : AwikiMePalette.brandAccent,
          ),
        ],
        if (showSecurityPill) ...<Widget>[
          SizedBox(width: responsive.displayScaled(6)),
          _MacChatPill(
            label: context.l10n.chatSafeCollaboration,
            color: const Color(0xFFE6F8EE),
            textColor: AwikiMePalette.successGreen,
          ),
        ],
      ],
    );
  }
}
