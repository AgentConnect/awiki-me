part of '../chat_page.dart';

class _PeerInfoTarget {
  const _PeerInfoTarget({
    required this.targetDid,
    required this.displayName,
    this.peerPersonaId,
    this.fullHandle,
    this.avatarUri,
    this.inboxConversation,
  });

  factory _PeerInfoTarget.fromConversation(ConversationSummary conversation) {
    return _PeerInfoTarget(
      targetDid: conversation.targetDid?.trim() ?? '',
      displayName: conversation.displayName,
      peerPersonaId: conversation.peerPersonaId,
      fullHandle: conversation.targetPeer,
      avatarUri: conversation.avatarUri,
      inboxConversation: conversation.isGroup ? null : conversation,
    );
  }

  final String targetDid;
  final String displayName;
  final String? peerPersonaId;
  final String? fullHandle;
  final String? avatarUri;
  final ConversationSummary? inboxConversation;
}

class _PeerInfoDialog extends ConsumerStatefulWidget {
  const _PeerInfoDialog({required this.target, this.fullPage = false});

  final _PeerInfoTarget target;
  final bool fullPage;

  @override
  ConsumerState<_PeerInfoDialog> createState() => _PeerInfoDialogState();
}

class _PeerInfoDialogState extends ConsumerState<_PeerInfoDialog> {
  bool _showAgentInbox = false;

  @override
  void initState() {
    super.initState();
    if (widget.target.targetDid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(ref.read(agentsProvider.notifier).ensureLoaded());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final targetDid = widget.target.targetDid;
    final maxDialogHeight = MediaQuery.sizeOf(context).height * 0.86;
    final runtimeAgent = _runtimeAgent();
    final targetLooksLikeAgent =
        runtimeAgent != null || conversationTargetDidLooksLikeAgent(targetDid);
    final title = targetLooksLikeAgent
        ? context.l10n.chatPeerInfoAgentTitle
        : context.l10n.chatPeerInfoUserTitle;
    final state = targetDid.isEmpty
        ? const PeerProfileState(isLoading: false)
        : ref.watch(peerProfileProvider(targetDid));

    final content = Column(
      mainAxisSize: widget.fullPage ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        _PeerInfoHeader(
          title: title,
          fullPage: widget.fullPage,
          showDivider: false,
          compactAgentLayout:
              widget.fullPage &&
              context.awikiResponsive.isCompact &&
              targetLooksLikeAgent,
        ),
        Flexible(
          child: _buildProfileContent(
            state,
            targetDid: targetDid,
            runtimeAgent: runtimeAgent,
            maxDialogHeight: maxDialogHeight,
          ),
        ),
      ],
    );
    if (widget.fullPage) {
      return CupertinoPageScaffold(
        backgroundColor: context.awikiResponsive.isCompact
            ? context.awikiTheme.background
            : context.awikiTheme.surface,
        child: SafeArea(bottom: false, child: content),
      );
    }
    return AppDialogScaffold(
      maxWidth: IdentityProfileLayout.dialogMaxWidth,
      borderRadius: BorderRadius.circular(
        IdentityProfileLayout.dialogRadius(context),
      ),
      child: content,
    );
  }

  Widget _buildProfileContent(
    PeerProfileState state, {
    required String targetDid,
    required AgentSummary? runtimeAgent,
    required double maxDialogHeight,
  }) {
    final responsive = context.awikiResponsive;
    final profile = state.profile;
    final profileDid = _profileDid(profile, fallbackDid: targetDid);
    final displayName = runtimeAgent == null
        ? ref.watch(
            peerDisplayNameProvider(
              PeerDisplayNameRequest(
                peerPersonaId: profileDid == targetDid
                    ? widget.target.peerPersonaId
                    : null,
                did: profileDid,
                nickname: profile?.displayName,
                fullHandle:
                    profile?.fullHandle ??
                    profile?.handle ??
                    widget.target.fullHandle,
                senderNameSnapshot: widget.target.displayName,
                unknownLabel: context.l10n.chatPeerInfoUnknownContact,
              ),
            ),
          )
        : localizeAgentTitle(context.l10n, runtimeAgent);
    final handleLabel = profile == null
        ? (widget.target.fullHandle?.trim() ?? '')
        : DidDisplayFormatter.profileHandleLabel(profile);
    final projectedAvatarUri = peerAvatarUri(
      ref.watch(peerDisplayProfileProvider),
      profileDid,
      peerPersonaId: profileDid == targetDid
          ? widget.target.peerPersonaId
          : null,
    );
    final avatarUri =
        projectedAvatarUri ?? profile?.avatarUri ?? widget.target.avatarUri;
    final rawProfileContent = profile == null
        ? ''
        : (profile.profileMarkdown.trim().isNotEmpty
              ? profile.profileMarkdown.trim()
              : profile.bio.trim());
    final profileContent = profileArticleBody(
      DidDisplayFormatter.withoutRedundantIdentityMetadata(rawProfileContent),
    );
    final primaryIdentity = displayName;
    final secondaryIdentity = _secondaryIdentityLabel(
      primary: primaryIdentity,
      handleLabel: handleLabel,
    );
    final agentAlias = runtimeAgent?.displayName.trim() ?? '';
    final showAgentAlias =
        agentAlias.isNotEmpty &&
        _normalizedIdentityLabel(agentAlias) !=
            _normalizedIdentityLabel(primaryIdentity) &&
        _normalizedIdentityLabel(agentAlias) !=
            _normalizedIdentityLabel(secondaryIdentity);
    final homepageUrl = profile == null
        ? ''
        : ref.watch(profileHomepageResolverProvider).homepageUrl(profile);
    final isFollowing = profileDid.startsWith('did:')
        ? ref.watch(friendsProvider).isFollowing(profileDid)
        : false;
    final relationship = isFollowing ? 'following' : state.relationship;
    final hasPositiveRelationship =
        relationship == 'following' || relationship == 'friend';
    final runtimeDisplay = runtimeAgent == null
        ? null
        : agentRuntimeDisplay(runtimeAgent);
    final runtimeStatus = runtimeAgent == null
        ? null
        : AgentVisualStatus.fromAgent(runtimeAgent);
    final looksLikeAgent =
        runtimeAgent != null || conversationTargetDidLooksLikeAgent(targetDid);
    final profileSubjectType = profile?.subjectType?.trim() ?? '';
    final hasStructuredProfileType =
        profile?.agentKind != null || profileSubjectType.isNotEmpty;
    final fallbackIdentityType = looksLikeAgent
        ? IdentityType.agent(
            agentKind: runtimeAgent != null
                ? IdentityAgentKind.runtime
                : identityAgentKindFromDidHint(targetDid) ??
                      IdentityAgentKind.unknown,
          )
        : const IdentityType.user();
    final identityType = hasStructuredProfileType
        ? profile!.identityType
        : fallbackIdentityType;
    final canFollowProfile = profileDid.startsWith('did:');
    final inboxHeight = (maxDialogHeight * 0.48).clamp(320.0, 440.0).toDouble();
    if (widget.fullPage && responsive.isCompact && looksLikeAgent) {
      final compactHandle = profile?.handle?.trim();
      return _buildCompactAgentProfileContent(
        state,
        profileDid: profileDid,
        displayName: primaryIdentity,
        handleLabel: compactHandle == null || compactHandle.isEmpty
            ? secondaryIdentity
            : compactHandle.startsWith('@')
            ? compactHandle
            : '@$compactHandle',
        avatarUri: avatarUri,
        homepageUrl: homepageUrl,
        profileContent: profileContent,
        isFollowing: isFollowing,
        relationship: relationship,
        hasPositiveRelationship: hasPositiveRelationship,
        canFollowProfile: canFollowProfile,
        identityType: identityType,
      );
    }
    if (widget.fullPage && responsive.isCompact) {
      return _buildCompactUserProfileContent(
        profileDid: profileDid,
        displayName: primaryIdentity,
        bio: profile?.bio ?? '',
        tags: profile?.tags ?? const <String>[],
        avatarUri: avatarUri,
        homepageUrl: homepageUrl,
        isFollowing: isFollowing,
        canFollowProfile: canFollowProfile,
        identityType: identityType,
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        IdentityProfileLayout.contentInset(context),
        0,
        IdentityProfileLayout.contentInset(context),
        responsive.displayScaled(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SelectionArea(
            child: IdentityProfileCard(
              key: const Key('peer-info-identity-card'),
              header: IdentityProfileHeader(
                displayName: primaryIdentity,
                displayNameKey: const Key('peer-info-dialog-handle-value'),
                avatarSeed: displayName,
                avatarUri: avatarUri,
                avatarKey: const Key('peer-info-avatar'),
                handle: secondaryIdentity,
                handleKey: const Key('peer-info-dialog-display-name'),
                supportingText: showAgentAlias ? agentAlias : null,
                supportingTextKey: const Key('peer-info-dialog-agent-alias'),
                titleTrailing: runtimeAgent == null
                    ? null
                    : _AgentRenameIconButton(
                        agent: runtimeAgent,
                        onRename: _renameAgent,
                      ),
                badges: <Widget>[
                  IdentityTypeBadge(type: identityType),
                  if (profile == null && state.isLoading)
                    IdentityProfileBadge(
                      label: context.l10n.chatPeerInfoProfileLoading,
                      tone: IdentityProfileBadgeTone.muted,
                    )
                  else if (profile == null && state.hasError)
                    IdentityProfileBadge(
                      label: context.l10n.chatPeerInfoProfileUnavailable,
                      tone: IdentityProfileBadgeTone.outlined,
                    )
                  else if (!looksLikeAgent && profile != null)
                    IdentityProfileBadge(
                      label: localizeRelationshipLabel(
                        context.l10n,
                        relationship,
                      ),
                      tone: hasPositiveRelationship
                          ? IdentityProfileBadgeTone.success
                          : IdentityProfileBadgeTone.outlined,
                    ),
                  if (runtimeDisplay != null)
                    IdentityProfileBadge(
                      label: runtimeDisplay.label,
                      tone: IdentityProfileBadgeTone.runtime,
                    )
                  else if (looksLikeAgent && profile != null)
                    IdentityProfileBadge(
                      label: localizeRelationshipLabel(
                        context.l10n,
                        relationship,
                      ),
                      tone: hasPositiveRelationship
                          ? IdentityProfileBadgeTone.success
                          : IdentityProfileBadgeTone.outlined,
                    ),
                  if (runtimeStatus != null)
                    IdentityProfileBadge(
                      label: localizeAgentVisualStatus(
                        context.l10n,
                        runtimeStatus,
                      ),
                      tone: IdentityProfileBadgeTone.status,
                    ),
                ],
                trailing: canFollowProfile
                    ? _ChatFollowButton(
                        isFollowing: isFollowing,
                        onTap: () => _toggleFollow(profileDid),
                      )
                    : null,
              ),
              metadata: <Widget>[
                if (profileDid.isNotEmpty)
                  IdentityProfileMetadataRow(
                    label: 'DID',
                    child: CopyableDidLine(
                      value: profileDid,
                      displayValue: DidDisplayFormatter.compactDidPath(
                        profileDid,
                      ),
                      maxLines: 2,
                      copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
                      copiedMessage: context.l10n.chatPeerInfoDidCopied,
                      textKey: const Key('peer-info-dialog-did-value'),
                      buttonKey: const Key('peer-info-dialog-copy-did-button'),
                      textStyle: TextStyle(
                        color: AwikiMePalette.inkNeutral,
                        fontSize: responsive.bodyMd,
                        height: 1.35,
                      ),
                      buttonSize: responsive.displayScaled(30),
                      iconSize: responsive.displayScaled(14),
                      showButtonChrome: false,
                    ),
                  ),
                if (homepageUrl.isNotEmpty)
                  IdentityProfileMetadataRow(
                    label: context.l10n.profileHomepageLabel,
                    child: IdentityProfileLinkValue(
                      value: homepageUrl,
                      actionLabel: context.l10n.profileOpenHomepage,
                      onTap: () => _openHomepage(homepageUrl),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: IdentityProfileLayout.sectionGap(context)),
          SelectionArea(
            child: IdentityDocumentCard(
              key: const Key('peer-info-identity-document'),
              title: context.l10n.chatPeerInfoIdentityCard,
              child: IdentityDocumentContent(
                content: profileContent,
                emptyText: context.l10n.chatPeerInfoNoProfile,
                emptyState: _profilePlaceholder(state),
              ),
            ),
          ),
          if (runtimeAgent != null &&
              widget.target.inboxConversation != null) ...<Widget>[
            const SizedBox(height: 16),
            AppSecondaryButton(
              label: _showAgentInbox
                  ? context.l10n.chatPeerInfoCollapseAgentInbox
                  : context.l10n.chatPeerInfoAgentInbox,
              onPressed: () {
                setState(() {
                  _showAgentInbox = !_showAgentInbox;
                });
              },
            ),
          ],
          if (runtimeAgent != null &&
              widget.target.inboxConversation != null &&
              _showAgentInbox) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              key: const Key('peer-info-agent-inbox'),
              height: inboxHeight,
              child: AgentInboxPanel(
                conversation: widget.target.inboxConversation!,
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

  Widget _buildCompactUserProfileContent({
    required String profileDid,
    required String displayName,
    required String bio,
    required List<String> tags,
    required String? avatarUri,
    required String homepageUrl,
    required bool isFollowing,
    required bool canFollowProfile,
    required IdentityType identityType,
  }) {
    final theme = context.awikiTheme;
    final visibleTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(3)
        .toList(growable: false);
    return SingleChildScrollView(
      key: const Key('peer-info-compact-user-layout'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            key: const Key('peer-info-compact-user-header'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.subtleSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AvatarBadge(
                      key: const Key('peer-info-avatar'),
                      seed: displayName,
                      size: 72,
                      avatarUri: avatarUri,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              displayName,
                              key: const Key('peer-info-dialog-handle-value'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.title,
                                fontSize: 20,
                                fontWeight: FontWeight.w400,
                                height: 1.25,
                              ),
                            ),
                            if (bio.trim().isNotEmpty) ...<Widget>[
                              const SizedBox(height: 6),
                              Text(
                                bio.trim(),
                                key: const Key('peer-info-user-bio'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.secondaryText,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ],
                            if (visibleTags.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 10),
                              Wrap(
                                key: const Key('peer-info-user-tags'),
                                spacing: 8,
                                runSpacing: 8,
                                children: visibleTags
                                    .map(
                                      (tag) => IdentityProfileBadge(
                                        label: tag,
                                        tone: IdentityProfileBadgeTone.outlined,
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ],
                            const SizedBox(height: 10),
                            IdentityTypeBadge(
                              type: identityType,
                              compact: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppPressable(
                        key: const Key('peer-info-return-to-chat-button'),
                        onTap: () => Navigator.of(context).pop(),
                        semanticLabel: context.l10n.peerProfileSendMessage,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            context.l10n.peerProfileSendMessage,
                            style: TextStyle(
                              color: theme.primaryForeground,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (canFollowProfile) ...<Widget>[
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        height: 48,
                        child: _ChatFollowButton(
                          isFollowing: isFollowing,
                          onTap: () => _toggleFollow(profileDid),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            key: const Key('peer-info-compact-user-metadata'),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                if (profileDid.isNotEmpty)
                  _CompactAgentInfoMetadataRow(
                    key: const Key('peer-info-compact-user-did-row'),
                    height: 72,
                    label: 'DID',
                    showDivider: homepageUrl.isNotEmpty,
                    child: CopyableDidLine(
                      value: profileDid,
                      displayValue: DidDisplayFormatter.compactDidPath(
                        profileDid,
                      ),
                      maxLines: 2,
                      copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
                      copiedMessage: context.l10n.chatPeerInfoDidCopied,
                      textKey: const Key('peer-info-dialog-did-value'),
                      buttonKey: const Key('peer-info-dialog-copy-did-button'),
                      textStyle: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 13,
                        height: 1.35,
                      ),
                      buttonSize: 44,
                      iconSize: 20,
                      showButtonChrome: false,
                    ),
                  ),
                if (homepageUrl.isNotEmpty)
                  _CompactAgentHomepageRow(
                    homepageUrl: homepageUrl,
                    onTap: () => _openHomepage(homepageUrl),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactAgentProfileContent(
    PeerProfileState state, {
    required String profileDid,
    required String displayName,
    required String handleLabel,
    required String? avatarUri,
    required String homepageUrl,
    required String profileContent,
    required bool isFollowing,
    required String relationship,
    required bool hasPositiveRelationship,
    required bool canFollowProfile,
    required IdentityType identityType,
  }) {
    final theme = context.awikiTheme;
    final relationshipLabel = localizeRelationshipLabel(
      context.l10n,
      relationship,
    );
    return SingleChildScrollView(
      key: const Key('peer-info-compact-agent-layout'),
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 28),
          Align(
            child: AvatarBadge(
              key: const Key('peer-info-avatar'),
              seed: displayName,
              size: 80,
              avatarUri: avatarUri,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            key: const Key('peer-info-compact-agent-name'),
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Center(
                child: Text(
                  displayName,
                  key: const Key('peer-info-dialog-handle-value'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            key: const Key('peer-info-compact-agent-handle'),
            height: 24,
            child: Center(
              child: Text(
                handleLabel,
                key: const Key('peer-info-dialog-display-name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
          if (canFollowProfile)
            Align(
              child: SizedBox(
                width: 198,
                height: 48,
                child: _ChatFollowButton(
                  isFollowing: isFollowing,
                  compactAgentLayout: true,
                  onTap: () => _toggleFollow(profileDid),
                ),
              ),
            )
          else
            const SizedBox(height: 48),
          const SizedBox(height: 22),
          SizedBox(
            key: const Key('peer-info-compact-agent-badges'),
            height: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IdentityTypeBadge(
                  key: const Key('peer-info-compact-agent-type-badge'),
                  type: identityType,
                  compact: true,
                ),
                const SizedBox(width: 8),
                _CompactAgentInfoBadge(
                  key: const Key('peer-info-compact-agent-follow-badge'),
                  label: relationshipLabel,
                  emphasized: hasPositiveRelationship,
                ),
              ],
            ),
          ),
          const SizedBox(height: 42),
          _CompactAgentInfoMetadataRow(
            key: const Key('peer-info-compact-agent-did-row'),
            height: 58,
            label: 'DID',
            showDivider: true,
            child: CopyableDidLine(
              value: profileDid,
              displayValue: DidDisplayFormatter.compactDidPath(profileDid),
              maxLines: 2,
              copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
              copiedMessage: context.l10n.chatPeerInfoDidCopied,
              textKey: const Key('peer-info-dialog-did-value'),
              buttonKey: const Key('peer-info-dialog-copy-did-button'),
              textStyle: TextStyle(
                color: theme.secondaryText,
                fontSize: 14,
                height: 1.35,
              ),
              buttonSize: 44,
              iconSize: 20,
              showButtonChrome: false,
            ),
          ),
          const SizedBox(height: 12),
          if (homepageUrl.isNotEmpty)
            _CompactAgentHomepageRow(
              homepageUrl: homepageUrl,
              onTap: () => _openHomepage(homepageUrl),
            )
          else
            const SizedBox(height: 60),
          Container(
            key: const Key('peer-info-compact-agent-section-divider'),
            height: 1,
            color: theme.border,
          ),
          const SizedBox(height: 25),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              key: const Key('peer-info-identity-document'),
              height: 104,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    context.l10n.chatPeerInfoIdentityCard,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  IdentityDocumentContent(
                    content: profileContent,
                    emptyText: context.l10n.chatPeerInfoNoProfile,
                    emptyState: _profilePlaceholder(state),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _profileDid(UserProfile? profile, {required String fallbackDid}) {
    final did = profile?.did.trim();
    if (did != null && did.isNotEmpty) {
      return did;
    }
    return fallbackDid.trim();
  }

  String _secondaryIdentityLabel({
    required String primary,
    required String handleLabel,
  }) {
    final normalizedPrimary = _normalizedIdentityLabel(primary);
    final value = handleLabel.trim();
    if (value.isNotEmpty &&
        _normalizedIdentityLabel(value) != normalizedPrimary) {
      return value;
    }
    return '';
  }

  String _normalizedIdentityLabel(String value) =>
      value.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

  Widget _profilePlaceholder(PeerProfileState state) {
    const textStyle = TextStyle(
      color: AwikiMePalette.mutedNeutral,
      fontSize: 13,
      height: 1.35,
    );
    if (state.isLoading) {
      return Row(
        children: <Widget>[
          const CupertinoActivityIndicator(radius: 8),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.chatPeerInfoLoadingProfile,
              style: textStyle,
            ),
          ),
        ],
      );
    }
    if (state.hasError) {
      return AwikiMeErrorText(
        message: context.l10n.peerProfileLoadFailed,
        compact: true,
      );
    }
    return Text(context.l10n.chatPeerInfoNoProfile, style: textStyle);
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
      if (isSessionEpochChangedError(error)) {
        return;
      }
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

  Future<void> _renameAgent(AgentSummary agent) async {
    final displayName = await showAgentRenameDialog(context, agent);
    if (displayName == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(agentsProvider.notifier)
          .renameAgent(agentDid: agent.agentDid, displayName: displayName);
      if (!mounted) {
        return;
      }
      final error = ref.read(agentsProvider).error;
      if (error != null && error.trim().isNotEmpty) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(StateError(error)));
        return;
      }
      ref.read(conversationListProvider.notifier).refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
      return;
    }
  }

  AgentSummary? _runtimeAgent() {
    final targetDid = widget.target.targetDid;
    if (targetDid.isEmpty) {
      return null;
    }
    for (final agent in ref.watch(agentsProvider).agents) {
      if (agent.isRuntime && agent.agentDid == targetDid) {
        return agent;
      }
    }
    return null;
  }
}

class _PeerInfoHeader extends StatelessWidget {
  const _PeerInfoHeader({
    required this.title,
    this.fullPage = false,
    this.showDivider = true,
    this.compactAgentLayout = false,
  });

  final String title;
  final bool fullPage;
  final bool showDivider;
  final bool compactAgentLayout;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    if (fullPage) {
      return DecoratedBox(
        key: compactAgentLayout
            ? const Key('peer-info-compact-agent-header')
            : null,
        decoration: BoxDecoration(
          color: AwikiMePalette.content,
          border: showDivider
              ? const Border(bottom: BorderSide(color: AwikiMePalette.hairline))
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AwikiMeTopBar(
            title: title,
            padding: compactAgentLayout
                ? const EdgeInsets.symmetric(vertical: 6)
                : EdgeInsets.zero,
            titleFontSize: compactAgentLayout
                ? 20
                : awikiMeCompactTopBarTitleFontSize,
            leading: TopBarActionButton(
              key: const Key('peer-info-back-button'),
              onTap: () => Navigator.of(context).pop(),
              semanticsLabel: context.l10n.commonBack,
              child: AwikiMeSemanticIcon(
                role: AwikiMeIconRole.back,
                color: context.awikiTheme.primaryDark,
                size: compactAgentLayout ? 20 : responsive.iconSm,
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: responsive.displayScaled(58),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(bottom: BorderSide(color: AwikiMePalette.hairline))
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            responsive.displayScaled(20),
            0,
            responsive.displayScaled(16),
            0,
          ),
          child: AppDialogHeader(
            closeButtonKey: const Key('peer-info-close-button'),
            title: title,
            closeLabel: context.l10n.chatPeerInfoClose,
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _CompactAgentInfoBadge extends StatelessWidget {
  const _CompactAgentInfoBadge({
    super.key,
    required this.label,
    this.emphasized = false,
  });

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: emphasized ? theme.primarySoft : theme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized ? theme.primarySoft : theme.border,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.secondaryText, fontSize: 14, height: 1),
      ),
    );
  }
}

class _CompactAgentInfoMetadataRow extends StatelessWidget {
  const _CompactAgentInfoMetadataRow({
    super.key,
    required this.height,
    required this.label,
    required this.child,
    this.showDivider = false,
  });

  final double height;
  final String label;
  final Widget child;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return SizedBox(
      height: height,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 56,
                  child: Text(
                    label,
                    style: TextStyle(color: theme.secondaryText, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: child),
              ],
            ),
          ),
          if (showDivider)
            Positioned(
              left: 92,
              right: 24,
              bottom: 0,
              child: SizedBox(
                key: const Key('peer-info-compact-agent-metadata-divider'),
                height: 1,
                child: ColoredBox(color: theme.border),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactAgentHomepageRow extends StatelessWidget {
  const _CompactAgentHomepageRow({
    required this.homepageUrl,
    required this.onTap,
  });

  final String homepageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AppPressable(
      key: const Key('peer-info-compact-agent-homepage-row'),
      onTap: onTap,
      semanticLabel: context.l10n.profileOpenHomepage,
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 56,
                child: Text(
                  context.l10n.profileHomepageLabel,
                  style: TextStyle(color: theme.secondaryText, fontSize: 14),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  homepageUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.primary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 44,
                child: Icon(
                  CupertinoIcons.arrow_up_right,
                  color: theme.secondaryText,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentRenameIconButton extends StatelessWidget {
  const _AgentRenameIconButton({required this.agent, required this.onRename});

  final AgentSummary agent;
  final ValueChanged<AgentSummary> onRename;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return SelectionContainer.disabled(
      child: AppIconButton(
        key: const Key('peer-info-agent-rename-button'),
        onPressed: () => onRename(agent),
        semanticLabel: context.l10n.chatPeerInfoRenameAgent,
        tooltip: context.l10n.chatPeerInfoRenameAgentTooltip,
        size: responsive.displayScaled(30),
        backgroundColor: AwikiMePalette.mist,
        borderColor: AwikiMePalette.hairline,
        borderRadius: BorderRadius.circular(responsive.radius(9)),
        child: Icon(
          CupertinoIcons.pencil,
          color: AwikiMePalette.mutedNeutral,
          size: responsive.iconSm,
        ),
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
        color: AwikiMePalette.mist,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AwikiMePalette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AwikiMePalette.inkNeutral,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _GroupInfoDialog extends ConsumerStatefulWidget {
  const _GroupInfoDialog({
    required this.initialGroup,
    required this.onGroupUpdated,
    this.fullPage = false,
  });

  final GroupSummary initialGroup;
  final ValueChanged<GroupSummary> onGroupUpdated;
  final bool fullPage;

  @override
  ConsumerState<_GroupInfoDialog> createState() => _GroupInfoDialogState();
}

class _GroupInfoDialogState extends ConsumerState<_GroupInfoDialog> {
  late GroupSummary _group;
  bool _didRequestMembers = false;
  bool _didRequestGroup = false;
  bool _isRefreshingMembers = false;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
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

    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final members = ref.watch(groupMembersProvider(groupId));
    final currentDid = ref.watch(sessionProvider).session?.did;
    final canManageMembers = canManageGroupMembers(_group);
    final content = Column(
      mainAxisSize: widget.fullPage ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        _PeerInfoHeader(
          title: context.l10n.chatPeerInfoGroupTitle,
          fullPage: widget.fullPage,
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const Key('group-info-dialog-scroll-view'),
            padding: EdgeInsets.fromLTRB(
              responsive.spacing(18),
              responsive.spacing(16),
              responsive.spacing(18),
              responsive.spacing(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SelectionArea(
                  child: _PeerInfoSection(
                    title: context.l10n.chatPeerInfoGroupSection,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            AvatarBadge(
                              seed: _group.displayName,
                              size: responsive.isPhone ? 56 : 64,
                              avatarUri: _group.avatarUri,
                            ),
                            SizedBox(width: responsive.spacing(14)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    _group.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AwikiMePalette.inkNeutral,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    _group.description.isEmpty
                                        ? context.l10n.groupNoDescription
                                        : _group.description,
                                    style: const TextStyle(
                                      color: AwikiMePalette.mutedNeutral,
                                      fontSize: 13,
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
                            SemanticPill(
                              label: context.l10n.conversationPeerTypeGroup,
                              tone: SemanticPillTone.identity,
                            ),
                            SemanticPill(
                              label: context.l10n.groupMemberCount(
                                _group.memberCount,
                              ),
                              tone: SemanticPillTone.metadata,
                            ),
                            SemanticPill(
                              label: _group.myRole ?? 'member',
                              tone: SemanticPillTone.relationship,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        CopyableDidLine(
                          value: groupId,
                          copySemanticLabel: context.l10n.chatPeerInfoCopyDid,
                          copiedMessage: context.l10n.chatPeerInfoDidCopied,
                          textKey: const Key('group-info-dialog-did-value'),
                          buttonKey: const Key(
                            'group-info-dialog-copy-did-button',
                          ),
                          textStyle: const TextStyle(
                            color: AwikiMePalette.mutedNeutral,
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: responsive.spacing(16)),
                _PeerInfoSection(
                  title: context.l10n.groupMembersTitle,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              members.isEmpty
                                  ? context.l10n.groupMembersEmpty
                                  : context.l10n.chatPeerInfoMemberCount(
                                      members.length,
                                    ),
                              style: AwikiMeTextStyles.cardSubtitle,
                            ),
                          ),
                          _ChatNeutralIconButton(
                            key: const Key(
                              'group-info-dialog-add-member-button',
                            ),
                            semanticLabel: context.l10n.groupAddMembers,
                            icon: CupertinoIcons.person_add,
                            onTap: canManageMembers
                                ? () => _showAddMemberDialog(members)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          _ChatNeutralIconButton(
                            key: const Key(
                              'group-info-dialog-refresh-members-button',
                            ),
                            semanticLabel: context.l10n.groupRefreshMembers,
                            icon: CupertinoIcons.refresh,
                            isLoading: _isRefreshingMembers,
                            onTap: _isRefreshingMembers
                                ? null
                                : _refreshMembers,
                          ),
                        ],
                      ),
                      if (members.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        ...members.map(
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
                        ),
                      ],
                      if (ref.watch(groupProvider).isLoading) ...<Widget>[
                        const SizedBox(height: 12),
                        Center(
                          child: CupertinoActivityIndicator(
                            color: theme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (widget.fullPage) {
      return CupertinoPageScaffold(
        backgroundColor: theme.surface,
        child: SafeArea(bottom: false, child: content),
      );
    }
    return AppDialogScaffold(
      maxWidth: 620,
      borderRadius: BorderRadius.circular(responsive.radius(14)),
      child: content,
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
        // Keep the conversation-derived snapshot visible when background member
        // loading fails.
      }
    });
  }

  void _requestGroup(String groupId) {
    if (_didRequestGroup || hasKnownGroupRole(_group)) {
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
        setState(() => _group = refreshed);
      } catch (_) {
        try {
          await ref.read(groupProvider.notifier).loadGroupMembers(groupId);
        } catch (_) {
          // Initial group enrichment is best effort inside the info dialog.
        }
      }
    });
  }

  Future<void> _refreshMembers() async {
    if (_isRefreshingMembers) {
      return;
    }
    setState(() => _isRefreshingMembers = true);
    try {
      await ref.read(groupProvider.notifier).loadGroupMembers(_group.groupId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (mounted) {
        setState(() => _isRefreshingMembers = false);
      }
    }
  }

  void _showAddMemberDialog(List<GroupMemberSummary> members) {
    AppNavigator.showDialog<void>(
      context,
      (dialogContext) => AddGroupMemberDialog(
        groupId: _group.groupId,
        existingMembers: members,
        onGroupUpdated: (updated) {
          if (!mounted) {
            return;
          }
          setState(() => _group = updated);
          widget.onGroupUpdated(updated);
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
        setState(() => _group = updated);
        widget.onGroupUpdated(updated);
      },
    );
  }
}

class _ChatNeutralIconButton extends StatelessWidget {
  const _ChatNeutralIconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.semanticsIdentifier,
    this.isLoading = false,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final String? semanticsIdentifier;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final enabled = onTap != null && !isLoading;
    return AppIconButton(
      onPressed: isLoading ? null : onTap,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: semanticLabel,
      isLoading: isLoading,
      size: responsive.scaled(34),
      backgroundColor: theme.surface,
      borderColor: AwikiMePalette.hairline,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Icon(
        icon,
        color: enabled ? AwikiMePalette.mutedNeutral : theme.tertiaryText,
        size: responsive.iconSm,
      ),
    );
  }
}

class _MacChatPill extends StatelessWidget {
  const _MacChatPill({
    super.key,
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
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _ChatFollowButton extends StatefulWidget {
  const _ChatFollowButton({
    required this.isFollowing,
    required this.onTap,
    this.compactAgentLayout = false,
  });

  final bool isFollowing;
  final Future<void> Function() onTap;
  final bool compactAgentLayout;

  @override
  State<_ChatFollowButton> createState() => _ChatFollowButtonState();
}

class _ChatFollowButtonState extends State<_ChatFollowButton> {
  bool _isBusy = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.isFollowing
        ? context.l10n.followContactAlreadyFollowing
        : context.l10n.friendsFollow;
    if (widget.compactAgentLayout) {
      final theme = context.awikiTheme;
      return AppPressable(
        key: Key(
          widget.isFollowing ? 'chat-unfollow-button' : 'chat-follow-button',
        ),
        onTap: _isBusy ? null : _handleTap,
        semanticLabel: label,
        tooltip: label,
        enabled: !_isBusy,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 198,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isFollowing ? theme.surface : theme.primary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isFollowing ? theme.border : theme.primary,
            ),
          ),
          child: _isBusy
              ? CupertinoActivityIndicator(
                  key: const Key('chat-relationship-action-progress'),
                  radius: 8,
                  color: widget.isFollowing
                      ? theme.secondaryText
                      : theme.primaryForeground,
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: widget.isFollowing
                        ? theme.secondaryText
                        : theme.primaryForeground,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
        ),
      );
    }
    return IdentityProfileActionButton(
      key: Key(
        widget.isFollowing ? 'chat-unfollow-button' : 'chat-follow-button',
      ),
      label: label,
      emphasized: !widget.isFollowing,
      isLoading: _isBusy,
      progressKey: const Key('chat-relationship-action-progress'),
      onPressed: _isBusy ? null : _handleTap,
    );
  }

  Future<void> _handleTap() async {
    setState(() => _isBusy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }
}
