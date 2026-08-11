part of '../chat_page.dart';

class _ChatInformationPage extends ConsumerStatefulWidget {
  const _ChatInformationPage({
    required this.conversation,
    required this.target,
    required this.displayName,
    required this.displayThreadId,
    required this.onOpenDirectConversation,
  });

  final ConversationSummary conversation;
  final _PeerInfoTarget target;
  final String displayName;
  final String displayThreadId;
  final PeerProfileDirectConversationOpener onOpenDirectConversation;

  @override
  ConsumerState<_ChatInformationPage> createState() =>
      _ChatInformationPageState();
}

class _ChatInformationPageState extends ConsumerState<_ChatInformationPage> {
  ProductConversationOverlay? _overlay;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isClearing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    try {
      final overlay = await ref
          .read(productLocalStoreProvider)
          .loadConversationOverlayByConversationId(
            ownerDid: epoch.ownerDid,
            conversationId: widget.conversation.conversationId,
          );
      if (!mounted || !epoch.matches(ref.read(sessionProvider))) {
        return;
      }
      setState(() {
        _overlay = overlay;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || !epoch.matches(ref.read(sessionProvider))) {
        return;
      }
      setState(() => _isLoading = false);
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  Future<void> _updateOverlay({bool? muted, bool? pinned}) async {
    if (_isSaving) {
      return;
    }
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) {
      return;
    }
    final previous = _overlay;
    final base =
        previous ??
        ProductConversationOverlay(
          ownerDid: epoch.ownerDid,
          threadId: widget.conversation.threadId,
          conversationId: widget.conversation.conversationId,
          updatedAt: DateTime.now(),
        );
    final next = base.copyWith(
      muted: muted,
      pinned: pinned,
      updatedAt: DateTime.now(),
    );
    setState(() {
      _overlay = next;
      _isSaving = true;
    });
    try {
      await ref
          .read(productLocalStoreProvider)
          .upsertConversationOverlayByConversationId(next);
      if (!epoch.matches(ref.read(sessionProvider))) {
        throw sessionEpochChangedError();
      }
      await ref.read(conversationListProvider.notifier).refreshFastLocal();
    } catch (error) {
      if (!mounted || !epoch.matches(ref.read(sessionProvider))) {
        return;
      }
      setState(() => _overlay = previous);
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (mounted && epoch.matches(ref.read(sessionProvider))) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _openPeerInfo() async {
    final runtimeAgent = localRuntimeAgentForConversationTarget(
      widget.target.targetDid,
      ref.read(agentsProvider).agents,
    );
    final isAgent =
        runtimeAgent != null ||
        conversationTargetDidLooksLikeAgent(widget.target.targetDid);
    if (widget.target.targetDid.isNotEmpty && !isAgent) {
      final result = await AppNavigator.push<PeerProfilePageResult>(
        context,
        (_) => PeerProfilePage(
          did: widget.target.targetDid,
          peerPersonaId: widget.target.peerPersonaId,
          initialDisplayName: widget.target.displayName,
          initialFullHandle: widget.target.fullHandle,
          initialAvatarUri: widget.target.avatarUri,
          onOpenDirectConversation: widget.onOpenDirectConversation,
        ),
      );
      if (result == PeerProfilePageResult.directConversationOpened && mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    await AppNavigator.push<void>(
      context,
      (_) => _PeerInfoDialog(target: widget.target, fullPage: true),
    );
  }

  Future<void> _openSearch() {
    return AppNavigator.push<void>(
      context,
      (_) => _ChatHistorySearchPage(
        displayThreadId: widget.displayThreadId,
        displayName: widget.displayName,
      ),
    );
  }

  Future<void> _confirmRemoveConversation() async {
    if (_isClearing) {
      return;
    }
    var confirmed = false;
    await AppNavigator.showDialog<void>(
      context,
      (dialogContext) => AppConfirmationDialog(
        title: context.l10n.chatRemoveConversationConfirmTitle,
        message: context.l10n.chatRemoveConversationConfirmMessage,
        confirmLabel: context.l10n.chatRemoveConversation,
        destructive: true,
        confirmButtonKey: const Key('chat-information-clear-confirm'),
        onConfirm: () {
          confirmed = true;
          Navigator.of(dialogContext).pop();
        },
      ),
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _isClearing = true);
    try {
      await ref
          .read(chatThreadsProvider.notifier)
          .deleteConversation(widget.conversation);
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.peerProfileThreadDeleted());
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted || isSessionEpochChangedError(error)) {
        return;
      }
      setState(() => _isClearing = false);
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final handle = _chatInformationHandle(
      widget.target.fullHandle,
      fallbackDid: widget.target.targetDid,
      fallbackDisplayName: widget.displayName,
    );
    final primaryDisplayName = _chatInformationPrimaryDisplayName(
      widget.displayName,
      handle,
    );
    final controlsEnabled = !_isLoading && !_isSaving && !_isClearing;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _ChatInformationHeader(title: context.l10n.chatInformationTitle),
            Expanded(
              child: ListView(
                key: const Key('chat-information-page'),
                padding: EdgeInsets.only(
                  bottom:
                      MediaQuery.viewPaddingOf(context).bottom +
                      responsive.spacing(20),
                ),
                children: <Widget>[
                  _ChatInformationIdentityRow(
                    displayName: primaryDisplayName,
                    handle: handle,
                    avatarUri: widget.target.avatarUri,
                    onTap: () => unawaited(_openPeerInfo()),
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  _ChatInformationActionRow(
                    key: const Key('chat-information-search-row'),
                    label: context.l10n.chatSearchHistory,
                    semanticLabel: context.l10n.chatSearchHistory,
                    iconRole: AwikiMeIconRole.search,
                    iconColor: theme.primary,
                    onTap: () => unawaited(_openSearch()),
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  DecoratedBox(
                    decoration: BoxDecoration(color: theme.surface),
                    child: Column(
                      children: <Widget>[
                        _ChatInformationSwitchRow(
                          key: const Key('chat-information-mute-switch'),
                          label: context.l10n.chatMuteNotifications,
                          value: _overlay?.muted ?? false,
                          enabled: controlsEnabled,
                          onChanged: (value) =>
                              unawaited(_updateOverlay(muted: value)),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            left: responsive.spacing(20),
                          ),
                          child: Container(height: 1, color: theme.border),
                        ),
                        _ChatInformationSwitchRow(
                          key: const Key('chat-information-pin-switch'),
                          label: context.l10n.chatPinConversation,
                          value: _overlay?.pinned ?? false,
                          enabled: controlsEnabled,
                          onChanged: (value) =>
                              unawaited(_updateOverlay(pinned: value)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  _ChatInformationActionRow(
                    key: const Key('chat-information-remove-conversation'),
                    label: context.l10n.chatRemoveConversation,
                    semanticLabel: context.l10n.chatRemoveConversation,
                    labelColor: theme.danger,
                    trailingColor: theme.danger,
                    enabled: !_isClearing,
                    onTap: () => unawaited(_confirmRemoveConversation()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInformationHeader extends StatelessWidget {
  const _ChatInformationHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final sideWidth = responsive.displayScaled(52);
    return Container(
      height: responsive.displayScaled(64),
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
              key: const Key('chat-information-back-button'),
              onTap: () => Navigator.of(context).pop(),
              semanticsIdentifier: 'e2e-chat-information-back-button',
              semanticsLabel: context.l10n.commonBack,
              child: AwikiMeSemanticIcon(
                role: AwikiMeIconRole.back,
                color: theme.primaryDark,
                size: responsive.iconMd,
              ),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.title,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(width: sideWidth),
        ],
      ),
    );
  }
}

class _ChatInformationIdentityRow extends StatelessWidget {
  const _ChatInformationIdentityRow({
    required this.displayName,
    required this.handle,
    required this.avatarUri,
    required this.onTap,
  });

  final String displayName;
  final String handle;
  final String? avatarUri;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressable(
      key: const Key('chat-information-peer-row'),
      onTap: onTap,
      semanticLabel: context.l10n.chatOpenPeerInfo(displayName),
      semanticsIdentifier: 'e2e-chat-information-peer-row',
      pressedColor: theme.background,
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.displayScaled(118)),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(20),
          vertical: responsive.spacing(18),
        ),
        color: theme.surface,
        child: Row(
          children: <Widget>[
            AvatarBadge(
              seed: displayName,
              size: responsive.displayScaled(76),
              avatarUri: avatarUri,
            ),
            SizedBox(width: responsive.spacing(16)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (handle.isNotEmpty) ...<Widget>[
                    SizedBox(height: responsive.spacing(5)),
                    Text(
                      handle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: responsive.spacing(12)),
            Icon(
              CupertinoIcons.chevron_forward,
              color: theme.tertiaryText,
              size: responsive.displayScaled(20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInformationActionRow extends StatelessWidget {
  const _ChatInformationActionRow({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.iconRole,
    this.iconColor,
    this.labelColor,
    this.trailingColor,
    this.enabled = true,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final AwikiMeIconRole? iconRole;
  final Color? iconColor;
  final Color? labelColor;
  final Color? trailingColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: semanticLabel,
      pressedColor: theme.background,
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.displayScaled(68)),
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(20)),
        color: theme.surface,
        child: Row(
          children: <Widget>[
            if (iconRole != null) ...<Widget>[
              AwikiMeSemanticIcon(
                role: iconRole!,
                color: iconColor ?? theme.secondaryText,
                size: responsive.displayScaled(24),
              ),
              SizedBox(width: responsive.spacing(14)),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: labelColor ?? theme.title,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: trailingColor ?? theme.tertiaryText,
              size: responsive.displayScaled(20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInformationSwitchRow extends StatelessWidget {
  const _ChatInformationSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Semantics(
      label: label,
      toggled: value,
      enabled: enabled,
      onTap: enabled ? () => onChanged(!value) : null,
      child: AppPressable(
        button: false,
        enabled: enabled,
        onTap: enabled ? () => onChanged(!value) : null,
        pressedColor: theme.background,
        child: Container(
          constraints: BoxConstraints(minHeight: responsive.displayScaled(62)),
          padding: EdgeInsets.symmetric(horizontal: responsive.spacing(20)),
          color: theme.surface,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              IgnorePointer(
                child: CupertinoSwitch(
                  value: value,
                  activeTrackColor: theme.primary,
                  onChanged: enabled ? (_) {} : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHistorySearchPage extends ConsumerStatefulWidget {
  const _ChatHistorySearchPage({
    required this.displayThreadId,
    required this.displayName,
  });

  final String displayThreadId;
  final String displayName;

  @override
  ConsumerState<_ChatHistorySearchPage> createState() =>
      _ChatHistorySearchPageState();
}

class _ChatHistorySearchPageState
    extends ConsumerState<_ChatHistorySearchPage> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final messages = ref.watch(
      chatThreadProvider(
        widget.displayThreadId,
      ).select((state) => state.messages),
    );
    final senderNames = <String, String>{
      for (final message in messages)
        message.localId: message.isMine
            ? context.l10n.profileMeTitle
            : _historyMessageSenderName(
                ref,
                context,
                message,
                fallback: widget.displayName,
              ),
    };
    final normalizedQuery = _query.trim().toLowerCase();
    final results =
        messages
            .where((message) {
              if (normalizedQuery.isEmpty) {
                return true;
              }
              final searchable = <String>[
                localizeMessagePreview(context.l10n, message),
                senderNames[message.localId] ?? '',
                message.senderName ?? '',
                message.attachment?.filename ?? '',
                message.attachment?.caption ?? '',
              ].join('\n').toLowerCase();
              return searchable.contains(normalizedQuery);
            })
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _ChatInformationHeader(title: context.l10n.chatSearchHistory),
            Container(
              color: theme.surface,
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(16),
                responsive.spacing(10),
                responsive.spacing(16),
                responsive.spacing(12),
              ),
              child: CupertinoSearchTextField(
                key: const Key('chat-history-search-field'),
                controller: _controller,
                placeholder: context.l10n.chatSearchHistoryPlaceholder,
                backgroundColor: theme.background,
                itemColor: theme.secondaryText,
                style: TextStyle(color: theme.title, fontSize: 16),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        context.l10n.chatSearchHistoryEmpty,
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 15,
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('chat-history-search-results'),
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.viewPaddingOf(context).bottom +
                            responsive.spacing(16),
                      ),
                      itemCount: results.length,
                      separatorBuilder: (_, __) => Padding(
                        padding: EdgeInsets.only(left: responsive.spacing(20)),
                        child: Container(height: 1, color: theme.border),
                      ),
                      itemBuilder: (context, index) {
                        final message = results[index];
                        final sender =
                            senderNames[message.localId] ?? widget.displayName;
                        return Container(
                          color: theme.surface,
                          padding: EdgeInsets.symmetric(
                            horizontal: responsive.spacing(20),
                            vertical: responsive.spacing(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              AvatarBadge(
                                seed: sender,
                                size: responsive.displayScaled(40),
                              ),
                              SizedBox(width: responsive.spacing(12)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Expanded(
                                          child: Text(
                                            sender,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: theme.title,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: responsive.spacing(8)),
                                        Text(
                                          _chatInformationTimestamp(
                                            message.createdAt,
                                          ),
                                          style: TextStyle(
                                            color: theme.tertiaryText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: responsive.spacing(5)),
                                    Text(
                                      localizeMessagePreview(
                                        context.l10n,
                                        message,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.secondaryText,
                                        fontSize: 15,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _historyMessageSenderName(
  WidgetRef ref,
  BuildContext context,
  ChatMessage message, {
  required String fallback,
}) {
  final runtimeAgent = localRuntimeAgentForConversationTarget(
    message.senderDid.trim(),
    ref.watch(agentsProvider).agents,
  );
  if (runtimeAgent != null) {
    return localizeAgentTitle(context.l10n, runtimeAgent);
  }
  return ref.watch(
    peerDisplayNameProvider(
      PeerDisplayNameRequest(
        peerPersonaId: message.senderPeerPersonaId,
        did: message.senderDid,
        senderNameSnapshot: message.senderName,
        unknownLabel: fallback,
      ),
    ),
  );
}

String _chatInformationHandle(
  String? value, {
  required String fallbackDid,
  required String fallbackDisplayName,
}) {
  final normalized = value?.trim() ?? '';
  if (normalized.isNotEmpty && !normalized.startsWith('did:')) {
    return normalized.startsWith('@') ? normalized : '@$normalized';
  }
  final did = normalized.startsWith('did:') ? normalized : fallbackDid.trim();
  final parts = did.split(':');
  if (parts.length >= 5 && parts[0] == 'did' && parts[1] == 'wba') {
    final domain = parts[2].trim();
    final handle = switch (parts[3]) {
      'user' when parts.length >= 6 => parts[4].trim(),
      'agent' when parts.length >= 7 => parts[5].trim(),
      _ => parts[3].trim(),
    };
    if (handle.isNotEmpty && domain.isNotEmpty) {
      return '@$handle.$domain';
    }
  }
  final displayName = fallbackDisplayName.trim();
  if (displayName.contains('.') && !displayName.contains(' ')) {
    return displayName.startsWith('@') ? displayName : '@$displayName';
  }
  return '';
}

String _chatInformationPrimaryDisplayName(String displayName, String handle) {
  final normalizedName = displayName.trim();
  final normalizedHandle = handle.replaceFirst(RegExp(r'^@'), '').trim();
  if (normalizedHandle.isNotEmpty &&
      (normalizedName.startsWith('did:') ||
          normalizedName.replaceFirst(RegExp(r'^@'), '').toLowerCase() ==
              normalizedHandle.toLowerCase())) {
    final localPart = normalizedHandle.split('.').first.trim();
    if (localPart.isNotEmpty) {
      return localPart;
    }
  }
  return normalizedName;
}

String _chatInformationTimestamp(DateTime value) {
  final local = value.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}/${twoDigits(local.month)}/${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
