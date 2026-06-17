part of '../chat_page.dart';

class _PeerInfoDialog extends ConsumerStatefulWidget {
  const _PeerInfoDialog({required this.conversation});

  final ConversationSummary conversation;

  @override
  ConsumerState<_PeerInfoDialog> createState() => _PeerInfoDialogState();
}

class _PeerInfoDialogState extends ConsumerState<_PeerInfoDialog> {
  bool _showAgentInbox = false;

  @override
  Widget build(BuildContext context) {
    final targetDid = widget.conversation.targetDid?.trim() ?? '';
    final responsive = context.awikiResponsive;
    final media = MediaQuery.of(context);
    final maxDialogWidth = media.size.width < 640
        ? media.size.width - 32
        : 620.0;
    final maxDialogHeight = media.size.height * 0.86;
    final runtimeAgent = _runtimeAgent();
    final title = runtimeAgent == null ? '用户信息' : '智能体信息';
    final state = targetDid.isEmpty
        ? const PeerProfileState(isLoading: false)
        : ref.watch(peerProfileProvider(targetDid));

    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(responsive.radius(14)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _PeerInfoHeader(title: title),
                  Flexible(
                    child: state.isLoading
                        ? const Center(child: CupertinoActivityIndicator())
                        : state.profile == null
                        ? _PeerInfoError(onClose: _close)
                        : _buildProfileContent(
                            state,
                            runtimeAgent: runtimeAgent,
                            maxDialogHeight: maxDialogHeight,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileContent(
    PeerProfileState state, {
    required AgentSummary? runtimeAgent,
    required double maxDialogHeight,
  }) {
    final profile = state.profile!;
    final displayName = DidDisplayFormatter.profileName(profile);
    final profileContent = profile.profileMarkdown.trim().isNotEmpty
        ? profile.profileMarkdown.trim()
        : profile.bio.trim();
    final homepageUrl = ref
        .watch(profileHomepageResolverProvider)
        .homepageUrl(profile);
    final isFollowing = ref.watch(friendsProvider).isFollowing(profile.did);
    final inboxHeight = (maxDialogHeight * 0.48).clamp(320.0, 440.0).toDouble();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AvatarBadge(
                      seed: displayName,
                      size: 64,
                      avatarUri: profile.avatarUri,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF101B32),
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          CopyableDidLine(
                            value: profile.did,
                            copySemanticLabel: '复制 DID',
                            copiedMessage: 'DID 已复制',
                            textKey: const Key('peer-info-dialog-did-value'),
                            buttonKey: const Key(
                              'peer-info-dialog-copy-did-button',
                            ),
                            textStyle: const TextStyle(
                              color: Color(0xFF66728A),
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppPill(
                      label: localizeRelationshipLabel(
                        context.l10n,
                        state.relationship,
                      ),
                    ),
                    if (profile.handle?.isNotEmpty == true)
                      AppPill(label: '@${profile.handle}'),
                    AppPill(
                      label: runtimeAgent == null
                          ? 'AWiki 用户'
                          : 'Runtime Agent',
                    ),
                  ],
                ),
                if (homepageUrl.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  AppInlineLinkRow(
                    label: homepageUrl,
                    onTap: () => _openHomepage(homepageUrl),
                  ),
                ],
                const SizedBox(height: 16),
                _PeerInfoSection(
                  title: '身份卡',
                  child: profileContent.isEmpty
                      ? const Text(
                          '暂未填写资料',
                          style: TextStyle(
                            color: Color(0xFF66728A),
                            fontSize: 13,
                          ),
                        )
                      : MarkdownBody(
                          data: profileContent,
                          selectable: false,
                          styleSheet: _chatMarkdownStyleSheet(
                            context,
                            const TextStyle(
                              color: Color(0xFF17213A),
                              fontSize: 13,
                              height: 1.45,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              if (profile.did.trim().startsWith('did:')) ...<Widget>[
                Expanded(
                  child: _ChatFollowButton(
                    isFollowing: isFollowing,
                    compact: false,
                    onTap: () => _toggleFollow(profile.did),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (runtimeAgent != null)
                Expanded(
                  child: AppSecondaryButton(
                    label: _showAgentInbox ? '收起 Agent 收件箱' : 'Agent 收件箱',
                    onPressed: () {
                      setState(() {
                        _showAgentInbox = !_showAgentInbox;
                      });
                    },
                  ),
                ),
            ],
          ),
          if (runtimeAgent != null && _showAgentInbox) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              key: const Key('peer-info-agent-inbox'),
              height: inboxHeight,
              child: AgentInboxPanel(
                conversation: widget.conversation,
                onClose: () {
                  setState(() {
                    _showAgentInbox = false;
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleFollow(String did) async {
    final targetDid = did.trim();
    if (targetDid.isEmpty) {
      return;
    }
    final isFollowing = ref.read(friendsProvider).isFollowing(targetDid);
    if (isFollowing) {
      await confirmAndUnfollow(context, ref, targetDid);
      return;
    }
    try {
      await ref.read(friendsProvider.notifier).follow(targetDid);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  Future<void> _openHomepage(String homepageUrl) async {
    try {
      await launchUrl(
        Uri.parse(homepageUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.linkOpenFailed('$error'));
    }
  }

  AgentSummary? _runtimeAgent() {
    final targetDid = widget.conversation.targetDid?.trim();
    if (targetDid == null || targetDid.isEmpty || widget.conversation.isGroup) {
      return null;
    }
    for (final agent in ref.watch(agentsProvider).agents) {
      if (agent.isRuntime && agent.agentDid == targetDid) {
        return agent;
      }
    }
    return null;
  }

  void _close() {
    Navigator.of(context).pop();
  }
}

class _PeerInfoHeader extends StatelessWidget {
  const _PeerInfoHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      height: responsive.displayScaled(58),
      padding: EdgeInsets.fromLTRB(
        responsive.spacing(18),
        0,
        responsive.spacing(12),
        0,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5EAF2))),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: const Color(0xFF101B32),
                fontSize: responsive.titleLg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppIconButton(
            onPressed: () => Navigator.of(context).pop(),
            semanticLabel: '关闭信息弹窗',
            tooltip: '关闭',
            size: responsive.displayScaled(32),
            backgroundColor: const Color(0xFFF5F7FB),
            borderColor: const Color(0xFFE4E9F2),
            child: Icon(
              CupertinoIcons.xmark,
              color: const Color(0xFF66728A),
              size: responsive.iconSm,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeerInfoSection extends StatelessWidget {
  const _PeerInfoSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF101B32),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PeerInfoError extends StatelessWidget {
  const _PeerInfoError({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AwikiMeErrorText(
            message: context.l10n.peerProfileLoadFailed,
            textAlign: TextAlign.center,
            compact: true,
          ),
          const SizedBox(height: 16),
          AppSecondaryButton(label: '关闭', onPressed: onClose),
        ],
      ),
    );
  }
}

class _MacChatPill extends StatelessWidget {
  const _MacChatPill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(8),
        vertical: responsive.displayScaled(4),
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: responsive.displayScaled(11.5),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ChatAgentPill extends StatelessWidget {
  const _ChatAgentPill({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(7),
        vertical: responsive.displayScaled(3),
      ),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF1F3F7) : const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: muted ? const Color(0xFF66728A) : const Color(0xFF0B65F8),
          fontSize: responsive.displayScaled(10.5),
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
    );
  }
}

class _ChatFollowButton extends StatefulWidget {
  const _ChatFollowButton({
    required this.isFollowing,
    required this.onTap,
    this.compact = false,
  });

  final bool isFollowing;
  final bool compact;
  final Future<void> Function() onTap;

  @override
  State<_ChatFollowButton> createState() => _ChatFollowButtonState();
}

class _ChatFollowButtonState extends State<_ChatFollowButton> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final label = widget.isFollowing ? '已关注' : '关注';
    final foreground = widget.isFollowing
        ? const Color(0xFF34415C)
        : theme.primaryForeground;
    final background = widget.isFollowing
        ? CupertinoColors.white
        : theme.primary;
    return AppPressable(
      onTap: _isBusy
          ? null
          : () async {
              setState(() => _isBusy = true);
              try {
                await widget.onTap();
              } finally {
                if (mounted) {
                  setState(() => _isBusy = false);
                }
              }
            },
      semanticLabel: label,
      tooltip: label,
      enabled: !_isBusy,
      scaleOnPress: true,
      pressedScale: 0.97,
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      builder: (context, state, child) {
        return AnimatedOpacity(
          opacity: state.pressed
              ? 0.82
              : state.hovered || state.focused
              ? 0.92
              : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        height: responsive.displayScaled(30),
        constraints: BoxConstraints(
          minWidth: responsive.displayScaled(widget.compact ? 54 : 66),
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: responsive.displayScaled(10)),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
          border: Border.all(
            color: widget.isFollowing ? const Color(0xFFDDE5F0) : theme.primary,
          ),
        ),
        child: _isBusy
            ? CupertinoActivityIndicator(
                radius: responsive.displayScaled(7),
                color: widget.isFollowing ? const Color(0xFF34415C) : null,
              )
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: responsive.displayScaled(12),
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}

class _MacChatIdentityButton extends StatelessWidget {
  const _MacChatIdentityButton({
    super.key,
    required this.label,
    required this.showLabel,
    required this.onTap,
    this.isActive = false,
  });

  final String label;
  final bool showLabel;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final foreground = isActive
        ? _macChatHeaderActionActiveColor
        : _macChatHeaderActionColor;
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      selected: isActive,
      scaleOnPress: true,
      pressedScale: 0.97,
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      child: Container(
        height: responsive.displayScaled(34),
        width: showLabel ? null : responsive.displayScaled(34),
        padding: showLabel
            ? EdgeInsets.symmetric(horizontal: responsive.displayScaled(12))
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: isActive
              ? _macChatHeaderActionActiveBackground
              : CupertinoColors.white,
          borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
          border: Border.all(color: const Color(0xFFDDE5F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              CupertinoIcons.person_crop_square,
              color: foreground,
              size: responsive.displayScaled(_macChatHeaderActionIconSize),
              weight: isActive ? 700 : 500,
            ),
            if (showLabel) ...<Widget>[
              SizedBox(width: responsive.displayScaled(7)),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: responsive.displayScaled(12),
                  fontWeight: isActive
                      ? _macChatHeaderActionActiveFontWeight
                      : _macChatHeaderActionFontWeight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MacChatHeaderButton extends StatelessWidget {
  const _MacChatHeaderButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
    this.isActive = false,
  });

  final String semanticLabel;
  final IconData icon;
  final Future<void> Function() onTap;
  final bool isLoading;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final foreground = isActive
        ? _macChatHeaderActionActiveColor
        : _macChatHeaderActionColor;
    return AppIconButton(
      onPressed: isLoading ? null : () async => onTap(),
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      isActive: isActive,
      isLoading: isLoading,
      size: responsive.displayScaled(34),
      backgroundColor: CupertinoColors.white,
      activeBackgroundColor: _macChatHeaderActionActiveBackground,
      borderColor: const Color(0xFFDDE5F0),
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      child: Icon(
        icon,
        color: foreground,
        size: responsive.displayScaled(_macChatHeaderActionIconSize),
        weight: isActive ? 900 : 500,
      ),
    );
  }
}
