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
    required this.onChatInformationTap,
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
  final VoidCallback onChatInformationTap;
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
        height: responsive.displayScaled(48),
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
    // Phone: bare chevron, centered tappable identity, and a single
    // trailing control. The bar carries no divider so the stream reads as
    // continuing underneath it.
    final trailing = showAddGroupMemberButton
        ? SizedBox.square(
            dimension: 44,
            child: AppPressable(
              key: const Key('chat-header-add-group-member-button'),
              onTap: isAddGroupMemberLoading ? null : onAddGroupMemberTap,
              enabled: !isAddGroupMemberLoading,
              semanticLabel: context.l10n.groupAddMembers,
              semanticsIdentifier: 'e2e-chat-header-add-group-member-button',
              tooltip: context.l10n.groupAddMembers,
              button: true,
              scaleOnPress: true,
              pressedScale: 0.9,
              borderRadius: BorderRadius.circular(22),
              child: AwikiGlassSurface(
                borderRadius: BorderRadius.circular(22),
                child: Center(
                  child: isAddGroupMemberLoading
                      ? const CupertinoActivityIndicator(radius: 8)
                      : Icon(
                          CupertinoIcons.person_add,
                          size: 20,
                          color: theme.title,
                        ),
                ),
              ),
            ),
          )
        : TopBarActionButton(
            key: const Key('chat-information-button'),
            onTap: onChatInformationTap,
            semanticsIdentifier: 'e2e-chat-information-button',
            semanticsLabel: context.l10n.chatOpenInformation,
            borderRadius: BorderRadius.circular(22),
            child: AwikiMeSemanticIcon(
              role: AwikiMeIconRole.moreHorizontal,
              color: theme.title,
              size: 22,
            ),
          );
    final phoneBadgeLabel = isDeletedAgentConversation
        ? null
        : localizeConversationCompactBadge(context.l10n, classification);
    return Container(
      key: const Key('chat-header'),
      height: responsive.displayScaled(64),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: theme.chatSurface,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: TopBarActionButton(
              key: const Key('chat-back-button'),
              onTap: onBack,
              semanticsIdentifier: 'e2e-chat-back-button',
              semanticsLabel: context.l10n.commonBack,
              borderRadius: BorderRadius.circular(22),
              child: Icon(
                CupertinoIcons.chevron_left,
                color: theme.title,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Center(
              child: _ChatHeaderIdentityTapTarget(
                key: const Key('chat-header-identity'),
                semanticLabel: conversation.isGroup
                    ? context.l10n.chatOpenInformation
                    : openInfoLabel,
                onTap: conversation.isGroup
                    ? onChatInformationTap
                    : onPeerInfoTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          compactName,
                          key: const Key('chat-header-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            color: theme.title,
                          ),
                        ),
                      ),
                      if (phoneBadgeLabel != null) ...<Widget>[
                        const SizedBox(width: 6),
                        AwikiNameTag(
                          key: const Key('chat-header-agent-badge'),
                          label: phoneBadgeLabel,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 44, child: Center(child: trailing)),
        ],
      ),
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
    return _ChatNeutralIconButton(
      key: const Key('chat-header-add-group-member-button'),
      semanticLabel: context.l10n.groupAddMembers,
      semanticsIdentifier: 'e2e-chat-header-add-group-member-button',
      icon: CupertinoIcons.person_add,
      onTap: onTap,
      isLoading: isLoading,
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
    required this.semanticLabel,
    required this.onNameTap,
  });

  final String compactName;
  final String? agentBadgeLabel;
  final bool isDeletedAgentConversation;
  final bool showAgentBadge;
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
                fontSize: 14.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        if (agentBadgeLabel != null && showAgentBadge) ...<Widget>[
          SizedBox(width: responsive.displayScaled(8)),
          _MacChatPill(
            key: const Key('chat-header-agent-badge'),
            label: agentBadgeLabel!,
            color: isDeletedAgentConversation
                ? context.awikiTheme.subtleSurface
                : context.awikiTheme.primarySoft,
            textColor: isDeletedAgentConversation
                ? context.awikiTheme.secondaryText
                : context.awikiTheme.primary,
          ),
        ],
      ],
    );
  }
}
