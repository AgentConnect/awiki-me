part of '../chat_page.dart';

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.embedded,
    required this.macStyle,
    required this.isRefreshing,
    required this.classification,
    required this.isDeletedAgentConversation,
    required this.onDetails,
    required this.onPeerInfoTap,
    required this.onRefresh,
    this.onMacIdentityPanelTap,
    this.onMacConversationInfoTap,
    this.macConversationInfoPanelActive = false,
    this.onBack,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final bool macStyle;
  final bool isRefreshing;
  final ConversationPeerClassification classification;
  final bool isDeletedAgentConversation;
  final VoidCallback onDetails;
  final VoidCallback onPeerInfoTap;
  final VoidCallback? onMacIdentityPanelTap;
  final VoidCallback? onMacConversationInfoTap;
  final bool macConversationInfoPanelActive;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final compactName = DidDisplayFormatter.conversationTitle(
      conversation,
      context.l10n,
    );
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final agentBadgeLabel = isDeletedAgentConversation
        ? '智能体已删除'
        : classification.chatBadgeLabel;
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
            final showIdentityLabel = width >= 470;
            final avatarSize = responsive.displayScaled(
              width >= 360 ? 40.0 : 36.0,
            );
            final actionGap = responsive.displayScaled(width >= 520 ? 12 : 8);

            return Row(
              children: <Widget>[
                _ChatHeaderIdentityTapTarget(
                  semanticLabel: '打开${classification.detailTypeLabel}信息',
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
                    semanticLabel: '打开${classification.detailTypeLabel}信息',
                    onNameTap: onPeerInfoTap,
                  ),
                ),
                SizedBox(width: actionGap),
                _MacChatHeaderButton(
                  key: const Key('chat-refresh-button'),
                  semanticLabel: '刷新当前会话',
                  icon: CupertinoIcons.refresh,
                  isLoading: isRefreshing,
                  onTap: onRefresh,
                ),
                SizedBox(width: responsive.displayScaled(8)),
                _MacChatIdentityButton(
                  key: const Key('chat-identity-card-button'),
                  label: conversation.isGroup ? '群聊信息' : '身份卡',
                  showLabel: showIdentityLabel,
                  isActive: false,
                  onTap: conversation.isGroup
                      ? (onMacIdentityPanelTap ?? onDetails)
                      : onDetails,
                ),
                if (onMacConversationInfoTap != null) ...<Widget>[
                  SizedBox(width: responsive.displayScaled(8)),
                  _MacChatHeaderButton(
                    key: const Key('chat-conversation-info-button'),
                    semanticLabel: '打开或关闭会话信息',
                    icon: CupertinoIcons.sidebar_right,
                    isActive: macConversationInfoPanelActive,
                    onTap: () async {
                      onMacConversationInfoTap!();
                    },
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
              semanticsLabel: '返回',
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
            semanticLabel: '打开${classification.detailTypeLabel}信息',
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
                        semanticLabel: '打开${classification.detailTypeLabel}信息',
                        onTap: onPeerInfoTap,
                        child: Text(
                          compactName,
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
          TopBarActionButton(
            onTap: onDetails,
            semanticsLabel: '打开${classification.detailTypeLabel}信息',
            child: Padding(
              padding: EdgeInsets.all(responsive.spacing(8)),
              child: AwikiAssetIcon(
                assetName: 'assets/icons/dot_vertical.svg',
                color: theme.title,
                size: responsive.iconMd,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeaderIdentityTapTarget extends StatelessWidget {
  const _ChatHeaderIdentityTapTarget({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
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
          const _MacChatPill(
            label: '安全协作中',
            color: Color(0xFFE6F8EE),
            textColor: Color(0xFF10A85A),
          ),
        ],
      ],
    );
  }
}
