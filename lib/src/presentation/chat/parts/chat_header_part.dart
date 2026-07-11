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
        height: responsive.displayScaled(64),
        padding: EdgeInsets.fromLTRB(
          responsive.displayScaled(22),
          0,
          responsive.displayScaled(18),
          0,
        ),
        decoration: const BoxDecoration(
          color: CupertinoColors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5EAF2))),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showSecurityPill = width >= 620;
            final avatarSize = responsive.displayScaled(
              width >= 360 ? 40.0 : 36.0,
            );

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
                SizedBox(width: responsive.displayScaled(10)),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        embedded
            ? responsive.spacing(24)
            : responsive.tabContentHorizontalPadding,
        responsive.spacing(embedded ? 18 : 8),
        embedded
            ? responsive.spacing(24)
            : responsive.tabContentHorizontalPadding,
        responsive.spacing(12),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: responsive.scaled(40),
            child: TopBarActionButton(
              onTap: onBack,
              semanticsIdentifier: 'e2e-chat-back-button',
              semanticsLabel: context.l10n.commonBack,
              child: Padding(
                padding: EdgeInsets.all(responsive.spacing(8)),
                child: AwikiAssetIcon(
                  assetName: 'assets/icons/icon_left.svg',
                  color: theme.primaryDark,
                  size: responsive.iconMd,
                ),
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(4)),
          _ChatHeaderIdentityTapTarget(
            key: const Key('chat-peer-info-avatar-button'),
            semanticLabel: openInfoLabel,
            semanticsIdentifier: 'chat-peer-info-avatar-button',
            onTap: onPeerInfoTap,
            child: AvatarBadge(
              seed: compactName,
              size: responsive.avatarSizeMd,
              avatarUri: conversation.avatarUri,
            ),
          ),
          SizedBox(width: responsive.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: _ChatHeaderIdentityTapTarget(
                        semanticLabel: openInfoLabel,
                        onTap: onPeerInfoTap,
                        child: Text(
                          compactName,
                          key: const Key('chat-header-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: responsive.titleLg,
                            fontWeight: FontWeight.w500,
                            color: theme.title,
                          ),
                        ),
                      ),
                    ),
                    if (agentBadgeLabel != null) ...<Widget>[
                      SizedBox(width: responsive.spacing(8)),
                      _ChatAgentPill(
                        label: agentBadgeLabel,
                        muted: isDeletedAgentConversation,
                      ),
                    ],
                  ],
                ),
                SizedBox(height: responsive.spacing(2)),
                Row(
                  children: <Widget>[
                    Container(
                      width: responsive.scaled(8),
                      height: responsive.scaled(8),
                      decoration: BoxDecoration(
                        color: theme.success,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(6)),
                    Text(
                      'ONLINE',
                      style: TextStyle(
                        fontSize: responsive.metaSm,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1,
                        color: theme.primaryDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showAddGroupMemberButton) ...<Widget>[
            SizedBox(width: responsive.spacing(10)),
            _ChatHeaderAddGroupMemberButton(
              onTap: isAddGroupMemberLoading ? null : onAddGroupMemberTap,
              isLoading: isAddGroupMemberLoading,
            ),
          ],
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
                color: const Color(0xFF101B32),
                fontSize: responsive.displayScaled(17),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (agentBadgeLabel != null && showAgentBadge) ...<Widget>[
          SizedBox(width: responsive.displayScaled(8)),
          _MacChatPill(
            label: agentBadgeLabel!,
            color: isDeletedAgentConversation
                ? const Color(0xFFF1F3F7)
                : const Color(0xFFEAF2FF),
            textColor: isDeletedAgentConversation
                ? const Color(0xFF66728A)
                : const Color(0xFF0B65F8),
          ),
        ],
        if (showSecurityPill) ...<Widget>[
          SizedBox(width: responsive.displayScaled(6)),
          _MacChatPill(
            label: context.l10n.chatSafeCollaboration,
            color: const Color(0xFFE6F8EE),
            textColor: const Color(0xFF10A85A),
          ),
        ],
      ],
    );
  }
}
