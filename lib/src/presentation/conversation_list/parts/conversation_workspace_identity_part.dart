part of '../conversation_workspace_page.dart';

class _MacPeerProfilePanel extends ConsumerWidget {
  const _MacPeerProfilePanel({
    super.key,
    required this.conversation,
    required this.onClose,
    this.useBackButton = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onClose;
  final bool useBackButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDid = conversation.targetDid?.trim();
    if (conversation.isGroup) {
      return _MacGroupInfoPanel(
        conversation: conversation,
        onClose: onClose,
        useBackButton: useBackButton,
      );
    }
    if (targetDid == null || targetDid.isEmpty) {
      return _MacPanelShell(
        title: _identityCardTitleForConversation(context, conversation),
        onClose: onClose,
        closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
        closeButtonKey: useBackButton
            ? const Key('mac-compact-panel-back-button')
            : null,
        closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
        closeButtonLeading: useBackButton,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AwikiMeErrorText(
              message: context.l10n.peerProfileLoadFailed,
              textAlign: TextAlign.center,
              compact: true,
            ),
          ),
        ),
      );
    }

    final state = ref.watch(peerProfileProvider(targetDid));
    final profile = state.profile;
    if (state.isLoading) {
      return _MacPanelShell(
        title: _identityCardTitleForConversation(context, conversation),
        onClose: onClose,
        closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
        closeButtonKey: useBackButton
            ? const Key('mac-compact-panel-back-button')
            : null,
        closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
        closeButtonLeading: useBackButton,
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }
    if (profile == null) {
      return _MacPanelShell(
        title: _identityCardTitleForConversation(context, conversation),
        onClose: onClose,
        closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
        closeButtonKey: useBackButton
            ? const Key('mac-compact-panel-back-button')
            : null,
        closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
        closeButtonLeading: useBackButton,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AwikiMeErrorText(
              message: context.l10n.peerProfileLoadFailed,
              textAlign: TextAlign.center,
              compact: true,
            ),
          ),
        ),
      );
    }

    final name = DidDisplayFormatter.profileName(profile);
    final profileContent = profile.profileMarkdown.trim().isNotEmpty
        ? profile.profileMarkdown.trim()
        : profile.bio.trim();
    final homepageUrl = ref
        .watch(profileHomepageResolverProvider)
        .homepageUrl(profile);

    return _MacPanelShell(
      title: _identityCardTitleForProfile(profile),
      onClose: onClose,
      closeIcon: useBackButton ? CupertinoIcons.chevron_left : null,
      closeButtonKey: useBackButton
          ? const Key('mac-compact-panel-back-button')
          : null,
      closeSemanticLabel: useBackButton ? '返回会话' : '关闭身份卡',
      closeButtonLeading: useBackButton,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        children: <Widget>[
          _MacProfileCard(
            title: '身份信息',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AvatarBadge(
                      seed: name,
                      size: 56,
                      avatarUri: profile.avatarUri,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF101B32),
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            profile.did,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF66728A),
                              fontSize: 11.5,
                              height: 1.35,
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
                    _MacProfilePill(
                      label: localizeRelationshipLabel(
                        context.l10n,
                        state.relationship,
                      ),
                    ),
                    if (profile.handle?.trim().isNotEmpty == true)
                      _MacProfilePill(label: '@${profile.handle!.trim()}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _MacProfileCard(
            title: '主页',
            child: AppPressableTile(
              onTap: () async {
                await launchUrl(
                  Uri.parse(homepageUrl),
                  mode: LaunchMode.externalApplication,
                );
              },
              semanticLabel: '打开主页',
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFDFF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE5EAF2)),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      CupertinoIcons.link,
                      color: Color(0xFF34415C),
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        homepageUrl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0B65F8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _MacProfileCard(
            title: '资料',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (profileContent.isEmpty)
                  Text(
                    context.l10n.profileEmpty,
                    style: const TextStyle(
                      color: Color(0xFF66728A),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  )
                else
                  MarkdownBody(
                    data: profileContent,
                    shrinkWrap: true,
                    styleSheet:
                        MarkdownStyleSheet.fromCupertinoTheme(
                          CupertinoTheme.of(context),
                        ).copyWith(
                          p: const TextStyle(
                            color: Color(0xFF17213A),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                          h1: const TextStyle(
                            color: Color(0xFF101B32),
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                          ),
                          h2: const TextStyle(
                            color: Color(0xFF101B32),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                  ),
                if (profile.tags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: profile.tags
                        .map((tag) => _MacProfilePill(label: tag))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _identityCardTitleForProfile(UserProfile profile) {
    final userName = profile.displayName.trim();
    final handle = profile.handle?.trim() ?? '';
    final titleName = userName.isNotEmpty
        ? userName
        : (handle.isNotEmpty
              ? handle
              : DidDisplayFormatter.compactDid(profile.did));
    return '$titleName 的身份卡';
  }

  String _identityCardTitleForConversation(
    BuildContext context,
    ConversationSummary conversation,
  ) {
    final title = DidDisplayFormatter.conversationTitle(
      conversation,
      context.l10n,
    );
    return '$title 的身份卡';
  }
}

class _MacGroupInfoPanel extends ConsumerStatefulWidget {
  const _MacGroupInfoPanel({
    required this.conversation,
    required this.onClose,
    this.useBackButton = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onClose;
  final bool useBackButton;

  @override
  ConsumerState<_MacGroupInfoPanel> createState() => _MacGroupInfoPanelState();
}

class _MacGroupInfoPanelState extends ConsumerState<_MacGroupInfoPanel> {
  late GroupSummary _group;
  bool _didRequestMembers = false;
  bool _didRequestGroup = false;
  bool _isRefreshingMembers = false;

  @override
  void initState() {
    super.initState();
    _group = _groupFromConversation(widget.conversation);
  }

  @override
  void didUpdateWidget(covariant _MacGroupInfoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.groupId != widget.conversation.groupId ||
        oldWidget.conversation.threadId != widget.conversation.threadId) {
      _group = _groupFromConversation(widget.conversation);
      _didRequestMembers = false;
      _didRequestGroup = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupId = _group.groupId;
    final knownGroup = _knownGroup(groupId);
    if (knownGroup != null && knownGroup != _group) {
      _group = knownGroup;
    }
    _requestGroup(groupId);
    _requestMembers(groupId);
    final members = ref.watch(groupMembersProvider(groupId));
    final currentDid = ref.watch(sessionProvider).session?.did;
    final canManageMembers = canManageGroupMembers(_group);
    final theme = context.awikiTheme;
    return _MacPanelShell(
      title: '${_group.displayName} 的群聊信息',
      onClose: widget.onClose,
      closeIcon: widget.useBackButton ? CupertinoIcons.chevron_left : null,
      closeButtonKey: widget.useBackButton
          ? const Key('mac-compact-panel-back-button')
          : null,
      closeSemanticLabel: widget.useBackButton ? '返回会话' : '关闭群聊信息',
      closeButtonLeading: widget.useBackButton,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        children: <Widget>[
          _MacProfileCard(
            title: '群聊信息',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AvatarBadge(
                      seed: _group.displayName,
                      size: 56,
                      avatarUri: _group.avatarUri,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _group.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AwikiMeTextStyles.cardTitle,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _group.description.isEmpty
                                ? context.l10n.groupNoDescription
                                : _group.description,
                            style: AwikiMeTextStyles.cardSubtitle,
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
                      label: context.l10n.groupMemberCount(_group.memberCount),
                    ),
                    AppPill(label: _group.myRole ?? 'member'),
                  ],
                ),
                const SizedBox(height: 14),
                CopyableDidLine(
                  value: groupId,
                  copySemanticLabel: '复制 Group DID',
                  copiedMessage: 'DID 已复制',
                  textKey: const Key('mac-group-info-did-value'),
                  buttonKey: const Key('mac-group-info-copy-did-button'),
                  textStyle: AwikiMeTextStyles.cardSubtitle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _MacProfileCard(
            title: '成员',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MacPanelIconButton(
                  key: const Key('mac-group-info-add-member-button'),
                  semanticLabel: '添加成员',
                  icon: CupertinoIcons.person_add,
                  onTap: canManageMembers
                      ? () => _openAddMemberDialog(members)
                      : null,
                ),
                const SizedBox(width: 8),
                _MacPanelIconButton(
                  key: const Key('mac-group-info-refresh-button'),
                  semanticLabel: '刷新成员',
                  icon: CupertinoIcons.refresh,
                  isLoading: _isRefreshingMembers,
                  onTap: _isRefreshingMembers ? null : _refreshMembers,
                ),
              ],
            ),
            child: members.isEmpty
                ? Text(
                    context.l10n.groupMembersEmpty,
                    style: AwikiMeTextStyles.cardSubtitle,
                  )
                : Column(
                    children: members
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GroupMemberRow(
                              item: item,
                              onRemove:
                                  canRemoveGroupMember(
                                    group: _group,
                                    member: item,
                                    currentDid: currentDid,
                                  )
                                  ? () => _confirmRemoveMember(item)
                                  : null,
                              showRemoveButton: true,
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          if (ref.watch(groupProvider).isLoading) ...<Widget>[
            const SizedBox(height: 12),
            Center(child: CupertinoActivityIndicator(color: theme.primary)),
          ],
        ],
      ),
    );
  }

  GroupSummary? _knownGroup(String groupId) {
    for (final group in ref.watch(groupProvider).groups) {
      if (group.groupId == groupId) {
        return group;
      }
    }
    return null;
  }

  void _requestMembers(String groupId) {
    if (_didRequestMembers) {
      return;
    }
    _didRequestMembers = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      try {
        await ref.read(groupProvider.notifier).loadGroupMembers(groupId);
      } catch (_) {
        // Background loading should not replace the conversation-derived group
        // panel with an async Flutter error.
      }
    });
  }

  void _requestGroup(String groupId) {
    if (_didRequestGroup || _hasCompleteGroupData(_group)) {
      return;
    }
    _didRequestGroup = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      try {
        final refreshed = await ref
            .read(groupProvider.notifier)
            .refreshGroup(groupId);
        if (!mounted) {
          return;
        }
        setState(() {
          _group = refreshed;
        });
      } catch (_) {
        // Keep the conversation-derived summary visible if the full snapshot
        // cannot be refreshed.
        try {
          await ref.read(groupProvider.notifier).loadGroupMembers(groupId);
        } catch (_) {
          // Member loading is best-effort during the initial side-panel render.
        }
      }
    });
  }

  bool _hasCompleteGroupData(GroupSummary group) {
    return hasKnownGroupRole(group);
  }

  Future<void> _refreshMembers() async {
    if (_isRefreshingMembers) {
      return;
    }
    setState(() {
      _isRefreshingMembers = true;
    });
    try {
      await ref.read(groupProvider.notifier).loadGroupMembers(_group.groupId);
      if (!mounted) {
        return;
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingMembers = false;
        });
      }
    }
  }

  void _openAddMemberDialog(List<GroupMemberSummary> members) {
    AppNavigator.showDialog<void>(
      context,
      (dialogContext) => AddGroupMemberDialog(
        groupId: _group.groupId,
        existingMembers: members,
        onGroupUpdated: (updated) {
          if (!mounted) {
            return;
          }
          setState(() {
            _group = updated;
          });
        },
      ),
    );
  }

  Future<void> _confirmRemoveMember(GroupMemberSummary member) async {
    await showRemoveGroupMemberDialog(
      context: context,
      ref: ref,
      groupId: _group.groupId,
      member: member,
      onGroupUpdated: (updated) {
        if (!mounted) {
          return;
        }
        setState(() {
          _group = updated;
        });
      },
    );
  }

  GroupSummary _groupFromConversation(ConversationSummary conversation) {
    final groupId = conversation.groupId?.trim().isNotEmpty == true
        ? conversation.groupId!.trim()
        : conversation.threadId;
    final name = conversation.displayName.trim().isNotEmpty
        ? conversation.displayName.trim()
        : groupId;
    return GroupSummary(
      groupId: groupId,
      displayName: name,
      description: '',
      memberCount: 0,
      lastMessageAt: conversation.lastMessageAt,
      avatarUri: conversation.avatarUri,
      membershipStatus: null,
    );
  }
}
