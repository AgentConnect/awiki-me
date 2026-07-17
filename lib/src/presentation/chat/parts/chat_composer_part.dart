part of '../chat_page.dart';

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.conversation,
    required this.embedded,
    required this.macStyle,
    required this.controller,
    required this.pendingAttachment,
    required this.focusRequestId,
    this.enabled = true,
    this.disabledReason,
    required this.onSend,
    required this.onAttach,
    required this.onScreenshot,
    required this.onPasteAttachment,
    required this.onRemoveAttachment,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final bool macStyle;
  final TextEditingController controller;
  final AttachmentDraft? pendingAttachment;
  final int focusRequestId;
  final bool enabled;
  final String? disabledReason;
  final Future<void> Function() onSend;
  final Future<void> Function() onAttach;
  final Future<void> Function({required bool hideApp}) onScreenshot;
  final Future<bool> Function() onPasteAttachment;
  final VoidCallback onRemoveAttachment;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final FocusNode _inputFocusNode = FocusNode();
  final Object _emojiTapRegionGroup = Object();
  bool _isSending = false;
  bool _isPastingFromClipboard = false;
  bool _showEmojiPicker = false;
  ChatMentionTrigger? _activeMentionTrigger;
  List<ChatMentionCandidate> _mentionCandidates =
      const <ChatMentionCandidate>[];
  bool _mentionCandidatesLoading = false;
  int _selectedMentionIndex = 0;
  int _mentionCandidateRequestSerial = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
    _scheduleInputFocusForRequest(widget.focusRequestId);
    unawaited(_preloadMentionMembers());
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
    if (oldWidget.focusRequestId != widget.focusRequestId) {
      _scheduleInputFocusForRequest(widget.focusRequestId);
    }
    if (!_sameCanonicalConversation(
      oldWidget.conversation,
      widget.conversation,
    )) {
      _clearMentionTrigger();
      unawaited(_preloadMentionMembers());
    } else {
      _syncMentionTrigger();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scheduleInputFocusForRequest(int requestId) {
    if (requestId <= 0 || !widget.enabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.focusRequestId != requestId || !widget.enabled) {
        return;
      }
      FocusScope.of(context).requestFocus(_inputFocusNode);
    });
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
    _syncMentionTrigger();
  }

  bool get _mentionEnabled {
    final groupDid = _mentionGroupDid;
    return widget.enabled && widget.conversation.isGroup && groupDid != null;
  }

  String? get _mentionGroupDid {
    final groupId = widget.conversation.groupId?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      return groupId;
    }
    if (widget.conversation.isGroup) {
      final thread = widget.conversation.threadId.trim();
      if (thread.isNotEmpty) {
        return thread.startsWith('group:')
            ? thread.substring('group:'.length)
            : thread;
      }
    }
    return null;
  }

  Future<void> _preloadMentionMembers() async {
    final groupDid = _mentionGroupDid;
    if (groupDid == null) {
      return;
    }
    try {
      await ref
          .read(groupProvider.notifier)
          .ensureGroupMembersLoaded(groupDid);
    } catch (_) {
      // The visible mention trigger owns error/empty-state presentation.
    }
  }

  void _syncMentionTrigger() {
    if (!mounted) {
      return;
    }
    final value = widget.controller.value;
    final trigger = ChatMentionTrigger.detect(
      text: value.text,
      selectionBaseOffset: value.selection.baseOffset,
      selectionExtentOffset: value.selection.extentOffset,
      composingStart: value.composing.start,
      composingEnd: value.composing.end,
      isGroup: _mentionEnabled,
    );
    if (trigger == _activeMentionTrigger) {
      return;
    }
    if (trigger == null) {
      _clearMentionTrigger();
      return;
    }
    setState(() {
      _activeMentionTrigger = trigger;
      _mentionCandidates = const <ChatMentionCandidate>[];
      _mentionCandidatesLoading = true;
      _selectedMentionIndex = 0;
    });
    unawaited(_loadMentionCandidates(trigger));
  }

  void _clearMentionTrigger() {
    _mentionCandidateRequestSerial += 1;
    if (!mounted) {
      return;
    }
    if (_activeMentionTrigger == null &&
        _mentionCandidates.isEmpty &&
        !_mentionCandidatesLoading) {
      return;
    }
    setState(() {
      _activeMentionTrigger = null;
      _mentionCandidates = const <ChatMentionCandidate>[];
      _mentionCandidatesLoading = false;
      _selectedMentionIndex = 0;
    });
  }

  Future<void> _loadMentionCandidates(ChatMentionTrigger trigger) async {
    final groupDid = _mentionGroupDid;
    if (groupDid == null) {
      _clearMentionTrigger();
      return;
    }
    final requestSerial = ++_mentionCandidateRequestSerial;
    try {
      final groupState = ref.read(groupProvider);
      final members = groupState.membersByGroup[groupDid] ??
          await ref
              .read(groupProvider.notifier)
              .ensureGroupMembersLoaded(groupDid);
      if (!mounted ||
          requestSerial != _mentionCandidateRequestSerial ||
          trigger != _activeMentionTrigger) {
        return;
      }
      final profileState = ref.read(peerDisplayProfileProvider);
      final candidates = ChatMentionCandidate.forGroupMembers(
        members.map(
          (member) => _mentionMemberPresentation(member, profileState),
        ),
        query: trigger.query,
        currentUserDid: ref.read(sessionProvider).session?.did,
        currentUserHandle: ref.read(sessionProvider).session?.handle,
      );
      setState(() {
        _mentionCandidates = candidates;
        _mentionCandidatesLoading = false;
        _selectedMentionIndex = candidates.isEmpty
            ? 0
            : _selectedMentionIndex.clamp(0, candidates.length - 1);
      });
    } catch (_) {
      if (!mounted ||
          requestSerial != _mentionCandidateRequestSerial ||
          trigger != _activeMentionTrigger) {
        return;
      }
      setState(() {
        _mentionCandidates = ChatMentionCandidate.forGroupMembers(
          const <Never>[],
          query: trigger.query,
          currentUserDid: ref.read(sessionProvider).session?.did,
          currentUserHandle: ref.read(sessionProvider).session?.handle,
        );
        _mentionCandidatesLoading = false;
        _selectedMentionIndex = 0;
      });
    }
  }

  GroupMemberSummary _mentionMemberPresentation(
    GroupMemberSummary member,
    PeerDisplayProfileState profileState,
  ) {
    final profile = profileState.forPeer(
      peerPersonaId: member.peerPersonaId,
      did: member.did,
    );
    final displayName = resolvePeerDisplayName(
      profileState,
      PeerDisplayNameRequest(
        peerPersonaId: member.peerPersonaId,
        did: member.did,
        nickname: member.displayName,
        fullHandle: member.handle,
      ),
    );
    final projectedHandle = profile?.handle?.trim() ?? '';
    return GroupMemberSummary(
      userId: member.userId,
      did: member.did,
      handle: projectedHandle.isEmpty ? member.handle : projectedHandle,
      role: member.role,
      membershipId: member.membershipId,
      peerPersonaId: member.peerPersonaId,
      credentialDid: member.credentialDid,
      profileUrl: member.profileUrl,
      displayName: displayName,
      avatarUri:
          peerAvatarUri(
            profileState,
            member.did,
            peerPersonaId: member.peerPersonaId,
          ) ??
          member.avatarUri,
      subjectType: member.subjectType,
      membershipStatus: member.membershipStatus,
    );
  }

  bool get _hasMentionPanel =>
      _activeMentionTrigger != null &&
      (_mentionCandidatesLoading || _mentionCandidates.isNotEmpty);

  void _selectMentionCandidate(ChatMentionCandidate candidate) {
    if (!candidate.enabled) {
      return;
    }
    final trigger = _activeMentionTrigger;
    if (trigger == null) {
      return;
    }
    final originalValue = widget.controller.value;
    final insertion = trigger.insert(candidate).applyTo(originalValue.text);
    final nextValue = originalValue.copyWith(
      text: insertion.text,
      selection: TextSelection.collapsed(offset: insertion.selectionOffset),
      composing: TextRange.empty,
    );
    widget.controller.value = nextValue;

    final drafts = ref.read(chatComposerDraftsProvider.notifier);
    final currentDraft = drafts.draftFor(widget.conversation);
    drafts.setDraft(
      widget.conversation,
      currentDraft.copyWith(
        text: insertion.text,
        mentions: ChatMentionDraft.mergeReplacingOverlap(
          currentDraft.mentions,
          insertion.mention,
          insertion.text,
        ),
      ),
    );
    _clearMentionTrigger();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  void _moveMentionSelection(int delta) {
    if (_mentionCandidates.isEmpty) {
      return;
    }
    setState(() {
      _selectedMentionIndex =
          (_selectedMentionIndex + delta) % _mentionCandidates.length;
      if (_selectedMentionIndex < 0) {
        _selectedMentionIndex += _mentionCandidates.length;
      }
    });
  }

  bool get _canSubmit {
    return widget.enabled &&
        (widget.pendingAttachment != null ||
            widget.controller.text.trim().isNotEmpty);
  }

  bool get _isComposingInput {
    final composing = widget.controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  Future<void> _submitIfNeeded() async {
    if (!widget.enabled || !_canSubmit || _isSending || _isComposingInput) {
      return;
    }
    setState(() {
      _isSending = true;
    });
    try {
      await widget.onSend();
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _attachIfNeeded() async {
    if (!widget.enabled) {
      return;
    }
    await widget.onAttach();
    if (!mounted || !widget.enabled) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  Future<void> _captureScreenshotIfNeeded() async {
    if (!widget.enabled) {
      return;
    }
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
    }
    await widget.onScreenshot(hideApp: false);
    if (!mounted || !widget.enabled) {
      return;
    }
    _inputFocusNode.requestFocus();
  }

  void _toggleEmojiPicker() {
    if (!widget.enabled) {
      return;
    }
    setState(() => _showEmojiPicker = !_showEmojiPicker);
  }

  void _dismissEmojiPicker() {
    if (!mounted || !_showEmojiPicker) {
      return;
    }
    setState(() => _showEmojiPicker = false);
  }

  Widget _emojiTapRegion({
    required Widget child,
    bool dismissOnOutside = false,
  }) {
    return TapRegion(
      groupId: _emojiTapRegionGroup,
      onTapOutside: dismissOnOutside ? (_) => _dismissEmojiPicker() : null,
      child: child,
    );
  }

  void _insertEmoji(String emoji) {
    _insertTextAtSelection(emoji);
    _inputFocusNode.requestFocus();
  }

  Future<void> _pasteFromClipboard() async {
    if (!widget.enabled || _isPastingFromClipboard) {
      return;
    }
    _isPastingFromClipboard = true;
    try {
      final stagedAttachment = await widget.onPasteAttachment();
      if (!mounted || !widget.enabled) {
        return;
      }
      if (stagedAttachment) {
        _inputFocusNode.requestFocus();
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty || !mounted || !widget.enabled) {
        return;
      }
      _insertTextAtSelection(text);
      _inputFocusNode.requestFocus();
    } finally {
      _isPastingFromClipboard = false;
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isControlPressed)) {
      unawaited(_pasteFromClipboard());
      return KeyEventResult.handled;
    }
    if (_hasMentionPanel) {
      if (key == LogicalKeyboardKey.arrowDown) {
        _moveMentionSelection(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _moveMentionSelection(-1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _clearMentionTrigger();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        if (_mentionCandidates.isNotEmpty) {
          _selectMentionCandidate(_mentionCandidates[_selectedMentionIndex]);
          return KeyEventResult.handled;
        }
      }
    }
    if (key == LogicalKeyboardKey.escape && _showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (_isComposingInput) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertNewlineAtSelection();
      return KeyEventResult.handled;
    }
    unawaited(_submitIfNeeded());
    return KeyEventResult.handled;
  }

  void _insertNewlineAtSelection() {
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) {
      widget.controller.text = '$text\n';
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
      return;
    }
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    _replaceSelectedText(value, start, end, '\n');
  }

  void _insertTextAtSelection(String insertion) {
    final value = widget.controller.value;
    final text = value.text;
    final selection = value.selection;
    if (!selection.isValid) {
      widget.controller.text = '$text$insertion';
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
      return;
    }
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    _replaceSelectedText(value, start, end, insertion);
  }

  void _replaceSelectedText(
    TextEditingValue value,
    int start,
    int end,
    String insertion,
  ) {
    final nextText = value.text.replaceRange(start, end, insertion);
    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + insertion.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final canSubmit = _canSubmit;
    final canUseSendButton = canSubmit && !_isSending && !_isComposingInput;
    final highlightSendButton = canSubmit && !_isSending;
    final disabledReason =
        widget.disabledReason ?? context.l10n.chatCurrentConversationCannotSend;
    if (widget.macStyle) {
      return SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final showAttachment = constraints.maxWidth >= 280;
            final horizontal = responsive.displayScaled(compact ? 14 : 22);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                responsive.displayScaled(2),
                horizontal,
                responsive.displayScaled(10),
              ),
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  responsive.displayScaled(12),
                  responsive.displayScaled(8),
                  responsive.displayScaled(8),
                  responsive.displayScaled(8),
                ),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(
                    responsive.displayScaled(10),
                  ),
                  border: Border.all(color: const Color(0xFFDDE5F0)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0F0B1F3A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_hasMentionPanel) ...<Widget>[
                      _MentionCandidatePanel(
                        candidates: _mentionCandidates,
                        loading: _mentionCandidatesLoading,
                        selectedIndex: _selectedMentionIndex,
                        macStyle: true,
                        onSelected: _selectMentionCandidate,
                      ),
                      SizedBox(height: responsive.displayScaled(8)),
                    ],
                    if (_showEmojiPicker && widget.enabled) ...<Widget>[
                      _emojiTapRegion(
                        dismissOnOutside: true,
                        child: _EmojiPickerPanel(
                          macStyle: true,
                          onSelected: _insertEmoji,
                        ),
                      ),
                      SizedBox(height: responsive.displayScaled(6)),
                    ],
                    if (!widget.enabled)
                      _DisabledComposerNotice(
                        message: disabledReason,
                        macStyle: true,
                      )
                    else if (widget.pendingAttachment != null) ...<Widget>[
                      _PendingAttachmentPreview(
                        attachment: widget.pendingAttachment!,
                        macStyle: true,
                        onRemove: widget.onRemoveAttachment,
                      ),
                      SizedBox(height: responsive.displayScaled(8)),
                    ],
                    if (widget.enabled) ...<Widget>[
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: responsive.displayScaled(38),
                        ),
                        child: _ComposerTextField(
                          controller: widget.controller,
                          focusNode: _inputFocusNode,
                          onKeyEvent: _handleInputKeyEvent,
                          placeholder: context.l10n.chatInputPlaceholder,
                          textStyle: TextStyle(
                            color: const Color(0xFF17213A),
                            fontSize: responsive.displayScaled(13.5),
                            height: 1.32,
                          ),
                          placeholderStyle: TextStyle(
                            color: const Color(0xFF8A96AA),
                            fontSize: responsive.displayScaled(13.5),
                          ),
                          padding: EdgeInsets.symmetric(
                            vertical: responsive.displayScaled(5),
                          ),
                          maxLines: 5,
                          onSubmitted: (_) async => _submitIfNeeded(),
                        ),
                      ),
                      SizedBox(height: responsive.displayScaled(2)),
                      Row(
                        key: const Key('chat-composer-tool-row'),
                        children: <Widget>[
                          if (showAttachment) ...<Widget>[
                            AppIconButton(
                              key: const Key('chat-attachment-button'),
                              onPressed: _attachIfNeeded,
                              semanticLabel: context.l10n.chatAddAttachment,
                              tooltip: context.l10n.chatAddAttachment,
                              size: responsive.displayScaled(29),
                              borderRadius: BorderRadius.circular(
                                responsive.displayScaled(7),
                              ),
                              child: Icon(
                                CupertinoIcons.paperclip,
                                color: const Color(0xFF34415C),
                                size: responsive.displayScaled(17),
                              ),
                            ),
                            SizedBox(width: responsive.displayScaled(3)),
                            _emojiTapRegion(
                              child: AppIconButton(
                                key: const Key('chat-emoji-button'),
                                onPressed: _toggleEmojiPicker,
                                semanticLabel: context.l10n.chatAddEmoji,
                                tooltip: context.l10n.chatAddEmoji,
                                size: responsive.displayScaled(29),
                                borderRadius: BorderRadius.circular(
                                  responsive.displayScaled(7),
                                ),
                                backgroundColor: _showEmojiPicker
                                    ? const Color(0xFFEAF2FF)
                                    : CupertinoColors.transparent,
                                child: Icon(
                                  CupertinoIcons.smiley,
                                  color: const Color(0xFF34415C),
                                  size: responsive.displayScaled(17),
                                ),
                              ),
                            ),
                            if (constraints.maxWidth >= 420) ...<Widget>[
                              SizedBox(width: responsive.displayScaled(3)),
                              AppIconButton(
                                key: const Key('chat-screenshot-button'),
                                onPressed: _captureScreenshotIfNeeded,
                                semanticLabel:
                                    context.l10n.chatCaptureScreenshot,
                                tooltip: context.l10n.chatCaptureScreenshot,
                                size: responsive.displayScaled(29),
                                borderRadius: BorderRadius.circular(
                                  responsive.displayScaled(7),
                                ),
                                child: Icon(
                                  CupertinoIcons.scissors,
                                  color: const Color(0xFF34415C),
                                  size: responsive.displayScaled(16),
                                ),
                              ),
                            ],
                          ],
                          const Spacer(),
                          AppPressable(
                            key: const Key('chat-send-button'),
                            onTap: canUseSendButton ? _submitIfNeeded : null,
                            semanticLabel: context.l10n.commonSend,
                            semanticsIdentifier: 'e2e-chat-send-button',
                            tooltip: context.l10n.commonSend,
                            enabled: canUseSendButton,
                            scaleOnPress: true,
                            pressedScale: 0.94,
                            borderRadius: BorderRadius.circular(
                              responsive.displayScaled(9),
                            ),
                            builder: (context, state, child) {
                              return AnimatedOpacity(
                                opacity: state.pressed
                                    ? 0.82
                                    : state.hovered || state.focused
                                    ? 0.92
                                    : 1,
                                duration: const Duration(milliseconds: 120),
                                child: child,
                              );
                            },
                            child: Container(
                              width: responsive.displayScaled(31),
                              height: responsive.displayScaled(31),
                              decoration: BoxDecoration(
                                color: highlightSendButton
                                    ? const Color(0xFF0B65F8)
                                    : const Color(0xFFE5EAF2),
                                borderRadius: BorderRadius.circular(
                                  responsive.displayScaled(9),
                                ),
                              ),
                              child: Icon(
                                CupertinoIcons.paperplane_fill,
                                color: highlightSendButton
                                    ? CupertinoColors.white
                                    : const Color(0xFF8A96AA),
                                size: responsive.displayScaled(15),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    final outerPadding = widget.embedded
        ? const EdgeInsets.fromLTRB(16, 8, 16, 16)
        : responsive.scaledInsets(const EdgeInsets.fromLTRB(16, 8, 16, 16));
    return SafeArea(
      top: false,
      child: Padding(
        padding: outerPadding,
        child: Container(
          constraints: BoxConstraints(
            minHeight: widget.embedded
                ? responsive.navBarHeight
                : responsive.controlHeight,
          ),
          padding: responsive.scaledInsets(
            EdgeInsets.fromLTRB(
              14,
              widget.embedded ? 8 : 10,
              14,
              widget.embedded ? 8 : 10,
            ),
          ),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(
              widget.embedded ? 24 : responsive.radius(26),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_hasMentionPanel) ...<Widget>[
                _MentionCandidatePanel(
                  candidates: _mentionCandidates,
                  loading: _mentionCandidatesLoading,
                  selectedIndex: _selectedMentionIndex,
                  macStyle: false,
                  onSelected: _selectMentionCandidate,
                ),
                SizedBox(height: responsive.spacing(8)),
              ],
              if (_showEmojiPicker && widget.enabled) ...<Widget>[
                _emojiTapRegion(
                  dismissOnOutside: true,
                  child: _EmojiPickerPanel(
                    macStyle: false,
                    onSelected: _insertEmoji,
                  ),
                ),
                SizedBox(height: responsive.spacing(8)),
              ],
              if (!widget.enabled)
                _DisabledComposerNotice(
                  message: disabledReason,
                  macStyle: false,
                )
              else if (widget.pendingAttachment != null) ...<Widget>[
                _PendingAttachmentPreview(
                  attachment: widget.pendingAttachment!,
                  macStyle: false,
                  onRemove: widget.onRemoveAttachment,
                ),
                SizedBox(height: responsive.spacing(8)),
              ],
              if (widget.enabled)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    TopBarActionButton(
                      key: const Key('chat-attachment-button'),
                      onTap: _attachIfNeeded,
                      semanticsLabel: context.l10n.chatAddAttachment,
                      tooltip: context.l10n.chatAddAttachment,
                      child: Padding(
                        padding: EdgeInsets.all(responsive.spacing(6)),
                        child: AwikiAssetIcon(
                          assetName: 'assets/icons/icon_plus.svg',
                          size: responsive.iconMd,
                        ),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(4)),
                    _emojiTapRegion(
                      child: TopBarActionButton(
                        key: const Key('chat-emoji-button'),
                        onTap: _toggleEmojiPicker,
                        semanticsLabel: context.l10n.chatAddEmoji,
                        tooltip: context.l10n.chatAddEmoji,
                        child: Padding(
                          padding: EdgeInsets.all(responsive.spacing(6)),
                          child: Icon(
                            CupertinoIcons.smiley,
                            color: _showEmojiPicker
                                ? theme.primary
                                : theme.secondaryText,
                            size: responsive.iconMd,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(4)),
                    Expanded(
                      child: _ComposerTextField(
                        controller: widget.controller,
                        focusNode: _inputFocusNode,
                        onKeyEvent: _handleInputKeyEvent,
                        placeholder: context.l10n.chatInputPlaceholder,
                        textStyle: TextStyle(
                          fontSize: responsive.bodyMd,
                          color: theme.title,
                          height: 1.32,
                        ),
                        placeholderStyle: TextStyle(
                          fontSize: responsive.bodyMd,
                          color: theme.secondaryText,
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: responsive.spacing(10),
                        ),
                        maxLines: 4,
                        onSubmitted: (_) async => _submitIfNeeded(),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(8)),
                    e2eSemantics(
                      identifier: 'e2e-chat-send-button',
                      label: context.l10n.commonSend,
                      button: true,
                      child: TopBarActionButton(
                        key: const Key('chat-send-button'),
                        onTap: canUseSendButton ? _submitIfNeeded : null,
                        semanticsLabel: context.l10n.commonSend,
                        tooltip: context.l10n.commonSend,
                        child: Padding(
                          padding: EdgeInsets.all(responsive.spacing(6)),
                          child: AwikiAssetIcon(
                            assetName: 'assets/icons/icon_send.svg',
                            color: highlightSendButton
                                ? theme.primary
                                : theme.secondaryText,
                            size: responsive.iconMd,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const List<String> _composerEmojis = <String>[
  '😀',
  '😄',
  '😂',
  '😊',
  '😍',
  '🥰',
  '😎',
  '🤔',
  '🥳',
  '😭',
  '😅',
  '😴',
  '👍',
  '👏',
  '🙏',
  '💪',
  '👌',
  '❤️',
  '🔥',
  '🎉',
  '✨',
  '💡',
  '✅',
  '🚀',
  '👀',
  '🤝',
  '🌟',
  '💬',
  '📎',
  '☕',
];

class _EmojiPickerPanel extends StatelessWidget {
  const _EmojiPickerPanel({required this.macStyle, required this.onSelected});

  final bool macStyle;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      key: const Key('chat-emoji-picker'),
      width: double.infinity,
      constraints: BoxConstraints(
        maxHeight: macStyle
            ? responsive.displayScaled(132)
            : responsive.scaled(156),
      ),
      padding: EdgeInsets.all(
        macStyle ? responsive.displayScaled(8) : responsive.spacing(8),
      ),
      decoration: BoxDecoration(
        color: macStyle ? const Color(0xFFF7F9FC) : const Color(0xFFFBFCFF),
        borderRadius: BorderRadius.circular(
          macStyle ? responsive.displayScaled(9) : responsive.radius(12),
        ),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: macStyle
              ? responsive.displayScaled(3)
              : responsive.spacing(4),
          runSpacing: macStyle
              ? responsive.displayScaled(3)
              : responsive.spacing(4),
          children: <Widget>[
            for (var index = 0; index < _composerEmojis.length; index += 1)
              CupertinoButton(
                key: Key('chat-emoji-option:$index'),
                minimumSize: Size.zero,
                padding: EdgeInsets.all(
                  macStyle
                      ? responsive.displayScaled(6)
                      : responsive.spacing(7),
                ),
                onPressed: () => onSelected(_composerEmojis[index]),
                child: Text(
                  _composerEmojis[index],
                  style: TextStyle(
                    fontSize: macStyle
                        ? responsive.displayScaled(20)
                        : responsive.scaled(22),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComposerTextField extends StatelessWidget {
  const _ComposerTextField({
    required this.controller,
    required this.focusNode,
    required this.onKeyEvent,
    required this.placeholder,
    required this.textStyle,
    required this.placeholderStyle,
    required this.padding,
    required this.maxLines,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusOnKeyEventCallback onKeyEvent;
  final String placeholder;
  final TextStyle textStyle;
  final TextStyle placeholderStyle;
  final EdgeInsetsGeometry padding;
  final int maxLines;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: onKeyEvent,
      child: e2eSemantics(
        identifier: 'e2e-chat-input',
        label: placeholder,
        textField: true,
        child: CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.send,
          minLines: 1,
          maxLines: maxLines,
          onSubmitted: onSubmitted,
          decoration: null,
          padding: padding,
          style: textStyle,
          placeholderStyle: placeholderStyle,
        ),
      ),
    );
  }
}

class _MentionCandidatePanel extends StatefulWidget {
  const _MentionCandidatePanel({
    required this.candidates,
    required this.loading,
    required this.selectedIndex,
    required this.macStyle,
    required this.onSelected,
  });

  final List<ChatMentionCandidate> candidates;
  final bool loading;
  final int selectedIndex;
  final bool macStyle;
  final ValueChanged<ChatMentionCandidate> onSelected;

  @override
  State<_MentionCandidatePanel> createState() => _MentionCandidatePanelState();
}

class _MentionCandidatePanelState extends State<_MentionCandidatePanel> {
  final ScrollController _scrollController = ScrollController();
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleSelectedCandidateScroll();
  }

  @override
  void didUpdateWidget(covariant _MentionCandidatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.candidates.length != widget.candidates.length ||
        oldWidget.loading != widget.loading ||
        oldWidget.macStyle != widget.macStyle) {
      _scheduleSelectedCandidateScroll();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleSelectedCandidateScroll() {
    if (_scrollScheduled) {
      return;
    }
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted) {
        return;
      }
      _ensureSelectedCandidateVisible();
    });
  }

  void _ensureSelectedCandidateVisible() {
    if (widget.loading ||
        widget.candidates.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final selectedIndex = widget.selectedIndex;
    if (selectedIndex < 0 || selectedIndex >= widget.candidates.length) {
      return;
    }

    final itemExtent = _mentionCandidateItemExtent(context, widget.macStyle);
    final listPadding = _mentionCandidateListVerticalPadding(
      context,
      widget.macStyle,
    );
    final position = _scrollController.position;
    final itemTop = listPadding + selectedIndex * itemExtent;
    final itemBottom = itemTop + itemExtent;
    final visibleTop = position.pixels;
    final visibleBottom = position.pixels + position.viewportDimension;

    double? targetOffset;
    if (itemTop < visibleTop) {
      targetOffset = itemTop;
    } else if (itemBottom > visibleBottom) {
      targetOffset = itemBottom - position.viewportDimension;
    }
    if (targetOffset == null) {
      return;
    }

    final clamped = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) {
      return;
    }
    _scrollController.jumpTo(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final borderRadius = BorderRadius.circular(
      widget.macStyle ? responsive.displayScaled(10) : responsive.radius(14),
    );
    final itemExtent = _mentionCandidateItemExtent(context, widget.macStyle);
    final listPadding = _mentionCandidateListVerticalPadding(
      context,
      widget.macStyle,
    );
    final panel = Container(
      key: const Key('chat-mention-candidate-panel'),
      constraints: BoxConstraints(
        maxHeight: widget.macStyle
            ? responsive.displayScaled(228)
            : responsive.displayScaled(260),
      ),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: borderRadius,
        border: Border.all(color: const Color(0xFFDDE5F0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140B1F3A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: widget.loading && widget.candidates.isEmpty
          ? Padding(
              padding: EdgeInsets.all(
                widget.macStyle
                    ? responsive.displayScaled(14)
                    : responsive.spacing(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CupertinoActivityIndicator(radius: 8),
                  const SizedBox(width: 10),
                  Text(context.l10n.chatLoadingMentionCandidates),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              itemExtent: itemExtent,
              padding: EdgeInsets.symmetric(vertical: listPadding),
              itemCount: widget.candidates.length,
              itemBuilder: (context, index) {
                final candidate = widget.candidates[index];
                return _MentionCandidateTile(
                  candidate: candidate,
                  selected: index == widget.selectedIndex,
                  macStyle: widget.macStyle,
                  itemExtent: itemExtent,
                  onTap: () => widget.onSelected(candidate),
                );
              },
            ),
    );
    return ClipRRect(borderRadius: borderRadius, child: panel);
  }
}

double _mentionCandidateItemExtent(BuildContext context, bool macStyle) {
  final responsive = context.awikiResponsive;
  return macStyle ? responsive.displayScaled(48) : responsive.displayScaled(54);
}

double _mentionCandidateListVerticalPadding(
  BuildContext context,
  bool macStyle,
) {
  final responsive = context.awikiResponsive;
  return macStyle ? responsive.displayScaled(6) : responsive.spacing(6);
}

class _MentionCandidateTile extends StatelessWidget {
  const _MentionCandidateTile({
    required this.candidate,
    required this.selected,
    required this.macStyle,
    required this.itemExtent,
    required this.onTap,
  });

  final ChatMentionCandidate candidate;
  final bool selected;
  final bool macStyle;
  final double itemExtent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final enabled = candidate.enabled;
    final background = selected
        ? const Color(0xFFEAF2FF)
        : CupertinoColors.transparent;
    final titleColor = enabled
        ? const Color(0xFF17213A)
        : const Color(0xFF8A96AA);
    final presentation = _localizedMentionCandidate(context.l10n, candidate);
    final subtitle = enabled
        ? presentation.subtitle
        : presentation.disabledReason ?? presentation.subtitle;
    return CupertinoButton(
      key: Key('chat-mention-candidate-${candidate.id}'),
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: enabled ? onTap : null,
      child: SizedBox(
        key: selected ? const Key('chat-mention-selected-candidate') : null,
        height: itemExtent,
        child: Container(
          color: background,
          padding: EdgeInsets.symmetric(
            horizontal: macStyle
                ? responsive.displayScaled(12)
                : responsive.spacing(12),
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.62,
            child: Row(
              children: <Widget>[
                AvatarBadge(
                  seed: candidate.title,
                  size: macStyle
                      ? responsive.displayScaled(28)
                      : responsive.displayScaled(32),
                  avatarUri: candidate.avatarUri,
                ),
                SizedBox(
                  width: macStyle
                      ? responsive.displayScaled(10)
                      : responsive.spacing(10),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        presentation.surface,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: macStyle
                              ? responsive.displayScaled(13)
                              : responsive.bodyMd,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: responsive.displayScaled(2)),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF6C7890),
                          fontSize: macStyle
                              ? responsive.displayScaled(11)
                              : responsive.bodySm,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: responsive.displayScaled(8)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: responsive.displayScaled(7),
                    vertical: responsive.displayScaled(3),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F5FA),
                    borderRadius: BorderRadius.circular(
                      responsive.displayScaled(999),
                    ),
                  ),
                  child: Text(
                    presentation.badge,
                    style: TextStyle(
                      color: const Color(0xFF44506A),
                      fontSize: macStyle
                          ? responsive.displayScaled(10)
                          : responsive.displayScaled(11),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DisabledComposerNotice extends StatelessWidget {
  const _DisabledComposerNotice({
    required this.message,
    required this.macStyle,
  });

  final String message;
  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      key: const Key('chat-disabled-composer-notice'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(macStyle ? 10 : 12),
        vertical: responsive.displayScaled(macStyle ? 8 : 10),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(
          responsive.radius(macStyle ? 8 : 14),
        ),
        border: Border.all(color: const Color(0xFFE1E7F0)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: const Color(0xFF66728A),
          fontSize: responsive.displayScaled(macStyle ? 12 : 13),
          height: 1.25,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MentionCandidatePresentation {
  const _MentionCandidatePresentation({
    required this.surface,
    required this.subtitle,
    required this.badge,
    this.disabledReason,
  });

  final String surface;
  final String subtitle;
  final String badge;
  final String? disabledReason;
}

_MentionCandidatePresentation _localizedMentionCandidate(
  AppLocalizations l10n,
  ChatMentionCandidate candidate,
) {
  final selector = candidate.selector;
  if (selector != null) {
    return _MentionCandidatePresentation(
      surface: _localizedMentionSelectorSurface(l10n, selector),
      subtitle: _localizedMentionSelectorSubtitle(l10n, selector),
      badge: _localizedMentionSelectorBadge(l10n, selector),
    );
  }
  return _MentionCandidatePresentation(
    surface: candidate.surface,
    subtitle: candidate.subtitle,
    badge: _localizedMentionSubjectType(l10n, candidate.subjectType),
    disabledReason: _localizedMentionDisabledReason(
      l10n,
      candidate.disabledReasonCode,
    ),
  );
}

String _localizedMentionSubjectType(
  AppLocalizations l10n,
  GroupMemberSubjectType subjectType,
) {
  return switch (subjectType) {
    GroupMemberSubjectType.human => l10n.mentionCandidateBadgeUser,
    GroupMemberSubjectType.agent => l10n.mentionCandidateBadgeAgent,
    GroupMemberSubjectType.unknown => l10n.mentionCandidateBadgeUnknown,
  };
}

String _localizedMentionSelectorSurface(
  AppLocalizations l10n,
  ChatMentionSelector selector,
) {
  return switch (selector) {
    ChatMentionSelector.all => l10n.mentionSelectorAllSurface,
    ChatMentionSelector.humans => l10n.mentionSelectorHumansSurface,
    ChatMentionSelector.agents => l10n.mentionSelectorAgentsSurface,
  };
}

String _localizedMentionSelectorSubtitle(
  AppLocalizations l10n,
  ChatMentionSelector selector,
) {
  return switch (selector) {
    ChatMentionSelector.all => l10n.mentionSelectorAllSubtitle,
    ChatMentionSelector.humans => l10n.mentionSelectorHumansSubtitle,
    ChatMentionSelector.agents => l10n.mentionSelectorAgentsSubtitle,
  };
}

String _localizedMentionSelectorBadge(
  AppLocalizations l10n,
  ChatMentionSelector selector,
) {
  return switch (selector) {
    ChatMentionSelector.all => l10n.mentionSelectorAllBadge,
    ChatMentionSelector.humans => l10n.mentionCandidateBadgeUser,
    ChatMentionSelector.agents => l10n.mentionCandidateBadgeAgent,
  };
}

String? _localizedMentionDisabledReason(
  AppLocalizations l10n,
  ChatMentionDisabledReasonCode? code,
) {
  return switch (code) {
    ChatMentionDisabledReasonCode.unknownMemberType =>
      l10n.mentionDisabledUnknownMemberType,
    ChatMentionDisabledReasonCode.inactiveMember =>
      l10n.mentionDisabledInactiveMember,
    null => null,
  };
}

class _PendingAttachmentPreview extends ConsumerWidget {
  const _PendingAttachmentPreview({
    required this.attachment,
    required this.macStyle,
    required this.onRemove,
  });

  final AttachmentDraft attachment;
  final bool macStyle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    final radius = responsive.radius(macStyle ? 8 : 12);
    final previewSize = responsive.displayScaled(macStyle ? 36 : 42);
    return Container(
      key: const Key('chat-pending-attachment-preview'),
      padding: EdgeInsets.fromLTRB(
        responsive.spacing(macStyle ? 9 : 10),
        responsive.spacing(macStyle ? 7 : 8),
        responsive.spacing(macStyle ? 6 : 7),
        responsive.spacing(macStyle ? 7 : 8),
      ),
      decoration: BoxDecoration(
        color: macStyle ? const Color(0xFFF6F8FC) : const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE1E7F0)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox.square(
            dimension: previewSize,
            child: _pendingAttachmentLeading(context, ref, previewSize),
          ),
          SizedBox(width: responsive.spacing(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  localizeAttachmentDraftName(context.l10n, attachment),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF101B32),
                    fontSize: macStyle
                        ? responsive.displayScaled(12.5)
                        : responsive.bodySm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: responsive.spacing(2)),
                Text(
                  _formatAttachmentMeta(
                    context.l10n,
                    attachment.mimeType,
                    attachment.sizeBytes,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF66728A),
                    fontSize: responsive.metaSm,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            key: const Key('chat-pending-attachment-remove-button'),
            onPressed: onRemove,
            semanticLabel: context.l10n.chatRemoveAttachment,
            tooltip: context.l10n.chatRemoveAttachment,
            size: responsive.displayScaled(28),
            padding: EdgeInsets.all(responsive.spacing(4)),
            borderRadius: BorderRadius.circular(responsive.displayScaled(14)),
            child: Icon(
              CupertinoIcons.xmark_circle_fill,
              color: const Color(0xFF8A96AA),
              size: responsive.displayScaled(18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingAttachmentLeading(
    BuildContext context,
    WidgetRef ref,
    double size,
  ) {
    final radius = BorderRadius.circular(context.awikiResponsive.radius(8));
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: radius,
      ),
      child: Icon(
        CupertinoIcons.doc,
        color: const Color(0xFF0B65F8),
        size: context.awikiResponsive.displayScaled(macStyle ? 16 : 18),
      ),
    );
    if (!_isSupportedInlineImage(
      mimeType: attachment.mimeType,
      filename: attachment.filename,
    )) {
      return fallback;
    }
    final bytes = attachment.bytes;
    final localPath = attachment.localPath?.trim();
    if (bytes == null && (localPath == null || localPath.isEmpty)) {
      return fallback;
    }
    final image = ref.watch(chatImageWidgetBuilderProvider)(
      path: localPath,
      bytes: bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorFallback: fallback,
    );
    return ClipRRect(
      key: const Key('chat-pending-image-preview'),
      borderRadius: radius,
      child: image,
    );
  }
}
