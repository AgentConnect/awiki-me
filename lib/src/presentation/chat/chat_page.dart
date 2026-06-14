import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../app/app_router.dart';
import '../../app/e2e_semantics.dart';
import '../../app/app_services.dart';
import '../../application/models/attachment_models.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_identity.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../agents/agent_inbox_panel.dart';
import '../agents/agent_display_name.dart';
import '../agents/agents_provider.dart';
import '../conversation_list/conversation_peer_classifier.dart';
import '../conversation_list/conversation_provider.dart';
import '../friends/friends_page.dart';
import '../friends/friends_provider.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'chat_provider.dart';

const _macChatHeaderActionColor = Color(0xFF44506A);
const _macChatHeaderActionActiveColor = Color(0xFF101B32);
const _macChatHeaderActionActiveBackground = Color(0xFFE4ECF7);
const _macChatHeaderActionIconSize = 16.0;
const _macChatHeaderActionFontWeight = FontWeight.w400;
const _macChatHeaderActionActiveFontWeight = FontWeight.w600;

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: ChatView(
        conversation: conversation,
        embedded: false,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class ChatView extends ConsumerStatefulWidget {
  const ChatView({
    super.key,
    required this.conversation,
    required this.embedded,
    this.onBack,
    this.onMacIdentityPanelTap,
    this.onMacAgentInboxTap,
    this.onMacConversationInfoTap,
    this.macIdentityPanelActive = false,
    this.macAgentInboxPanelActive = false,
    this.macConversationInfoPanelActive = false,
    this.macStyle = false,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final VoidCallback? onMacIdentityPanelTap;
  final VoidCallback? onMacAgentInboxTap;
  final VoidCallback? onMacConversationInfoTap;
  final bool macIdentityPanelActive;
  final bool macAgentInboxPanelActive;
  final bool macConversationInfoPanelActive;
  final bool macStyle;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final textController = TextEditingController();
  final scrollController = ScrollController();
  AttachmentDraft? _pendingAttachment;
  bool _isApplyingComposerDraft = false;
  bool _isRefreshingCurrentConversation = false;
  bool _didRequestAgents = false;
  final Set<String> _downloadingAttachmentMessageIds = <String>{};

  @override
  void initState() {
    super.initState();
    _restoreComposerDraft(widget.conversation);
    textController.addListener(_persistComposerText);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    textController.removeListener(_persistComposerText);
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameConversationTarget(oldWidget.conversation, widget.conversation)) {
      _restoreComposerDraft(widget.conversation, updateState: true);
    }
  }

  void _persistComposerText() {
    if (_isApplyingComposerDraft) {
      return;
    }
    ref
        .read(chatComposerDraftsProvider.notifier)
        .setText(_currentConversationSnapshot(), textController.text);
  }

  void _restoreComposerDraft(
    ConversationSummary conversation, {
    bool updateState = false,
  }) {
    final draft = ref
        .read(chatComposerDraftsProvider.notifier)
        .draftFor(conversation);
    void applyDraft() {
      _pendingAttachment = draft.pendingAttachment;
      _isApplyingComposerDraft = true;
      textController.value = TextEditingValue(
        text: draft.text,
        selection: TextSelection.collapsed(offset: draft.text.length),
      );
      _isApplyingComposerDraft = false;
    }

    if (updateState && mounted) {
      setState(applyDraft);
      return;
    }
    applyDraft();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final macStyle = widget.macStyle && responsive.isMacDesktop;
    final thread = ref.watch(chatThreadProvider(widget.conversation.threadId));
    final currentConversation = _currentConversationForTitle();
    _requestAgentsIfNeeded(currentConversation);
    final agents = ref.watch(agentsProvider).agents;
    final isDeletedAgentConversation =
        currentConversation.isDeletedAgentConversation;
    final runtimeAgent = _runtimeAgentForConversation(
      currentConversation,
      agents,
    );
    final groupSendDisabledReason = _groupSendDisabledReason(
      currentConversation,
    );
    final peerClassification = ref
        .watch(
          conversationPeerClassificationProvider(
            ConversationPeerTarget.fromConversation(currentConversation),
          ),
        )
        .maybeWhen(
          data: (value) => value,
          orElse: () => currentConversation.isGroup
              ? const ConversationPeerClassification.group()
              : runtimeAgent == null
              ? const ConversationPeerClassification.unknown()
              : ConversationPeerClassification.agent(
                  localRuntimeAgent: runtimeAgent,
                ),
        );
    final friendsState = ref.watch(friendsProvider);
    ref.listen<ChatThreadState>(
      chatThreadProvider(widget.conversation.threadId),
      (_, __) => WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottom(),
      ),
    );
    ref.listen<ConversationListState>(conversationListProvider, (_, next) {
      final updated = _matchingConversation(next.conversations);
      if (updated == null) {
        return;
      }
      final currentThread = ref.read(
        chatThreadProvider(widget.conversation.threadId),
      );
      if (!_threadNeedsHistorySync(currentThread, updated)) {
        return;
      }
      unawaited(
        ref
            .read(chatThreadsProvider.notifier)
            .openConversation(
              updated,
              displayThreadId: widget.conversation.threadId,
            ),
      );
    });
    final messages = thread.messages;
    final activePendingTurns = runtimeAgent == null
        ? const <AgentPendingTurn>[]
        : thread.agentPendingTurns
              .where((turn) => turn.isActive)
              .toList(growable: false);
    final messageIdsWithAgentProcessing = <String>{
      for (final message in messages)
        if (thread.pendingAgentTurnForMessage(message) != null) message.localId,
    };
    final unmatchedPendingTurns = activePendingTurns
        .where(
          (turn) => !messages.any((message) => turn.matchesMessage(message)),
        )
        .toList(growable: false);
    final page = SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          _ChatHeader(
            conversation: currentConversation,
            embedded: widget.embedded,
            macStyle: macStyle,
            isRefreshing: _isRefreshingCurrentConversation || thread.isLoading,
            classification: peerClassification,
            isDeletedAgentConversation: isDeletedAgentConversation,
            isFollowing: _isFollowableDirect(currentConversation)
                ? friendsState.isFollowing(currentConversation.targetDid!)
                : false,
            onFollowTap: _isFollowableDirect(currentConversation)
                ? () => _toggleFollow(currentConversation)
                : null,
            onBack: widget.onBack,
            onDetails: _openDetails,
            onMacIdentityPanelTap: widget.onMacIdentityPanelTap,
            onAgentInboxTap: runtimeAgent == null
                ? null
                : widget.onMacAgentInboxTap ?? _openAgentInbox,
            onMacConversationInfoTap: widget.onMacConversationInfoTap,
            macIdentityPanelActive: widget.macIdentityPanelActive,
            macAgentInboxPanelActive: widget.macAgentInboxPanelActive,
            macConversationInfoPanelActive:
                widget.macConversationInfoPanelActive,
            showAgentInbox: runtimeAgent != null,
            onRefresh: () => _refreshCurrentConversation(currentConversation),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                macStyle
                    ? responsive.displayScaled(28)
                    : (widget.embedded
                          ? responsive.spacing(32)
                          : responsive.tabContentHorizontalPadding),
                macStyle
                    ? responsive.displayScaled(20)
                    : responsive.spacing(24),
                macStyle
                    ? responsive.displayScaled(28)
                    : (widget.embedded
                          ? responsive.spacing(32)
                          : responsive.tabContentHorizontalPadding),
                macStyle
                    ? responsive.displayScaled(92)
                    : responsive.spacing(widget.embedded ? 124 : 140),
              ),
              itemCount: messages.length + unmatchedPendingTurns.length,
              itemBuilder: (_, index) {
                if (index >= messages.length) {
                  final turn = unmatchedPendingTurns[index - messages.length];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: macStyle
                          ? responsive.displayScaled(16)
                          : responsive.spacing(24),
                    ),
                    child: _AgentProcessingIndicator(
                      label: _agentProcessingLabel(turn),
                      avatarSeed: _agentProcessingAvatarSeed(
                        runtimeAgent,
                        currentConversation,
                      ),
                      macStyle: macStyle,
                    ),
                  );
                }
                final message = messages[index];
                final pendingTurn = runtimeAgent == null
                    ? null
                    : thread.pendingAgentTurnForMessage(message);
                final previous = index == 0 ? null : messages[index - 1];
                final next = index + 1 < messages.length
                    ? messages[index + 1]
                    : null;
                final senderLabel = _displayNameForMessage(context, message);
                final showSenderLabel = _shouldShowSenderLabel(
                  previous,
                  message,
                );
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: _messageBottomSpacing(
                      responsive: responsive,
                      macStyle: macStyle,
                      current: message,
                      next: next,
                      hasAgentProcessing: pendingTurn != null,
                      nextHasAgentProcessing:
                          next != null &&
                          messageIdsWithAgentProcessing.contains(next.localId),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      if (_shouldShowDivider(previous, message))
                        _DateDivider(
                          label: _timeDividerLabel(
                            message.createdAt,
                            previous: previous?.createdAt,
                          ),
                        ),
                      _MessageBubble(
                        message: message,
                        senderLabel: senderLabel,
                        showSenderLabel: showSenderLabel,
                        macStyle: macStyle,
                        onRetry: message.sendState == MessageSendState.failed
                            ? (_canRetryMessage(message)
                                  ? () async {
                                      await ref
                                          .read(chatThreadsProvider.notifier)
                                          .retryMessage(
                                            conversation: widget.conversation,
                                            message: message,
                                            expectedAgentReplyDid:
                                                runtimeAgent?.agentDid,
                                          );
                                    }
                                  : null)
                            : null,
                        onDownload:
                            message.attachment != null &&
                                message.sendState == MessageSendState.sent
                            ? () => _downloadAttachment(
                                currentConversation,
                                message,
                              )
                            : null,
                        isDownloading: _downloadingAttachmentMessageIds
                            .contains(message.localId),
                      ),
                      if (pendingTurn != null) ...<Widget>[
                        SizedBox(
                          height: macStyle
                              ? responsive.displayScaled(7)
                              : responsive.spacing(7),
                        ),
                        _MessageAgentProcessingStatus(
                          label: _agentProcessingLabel(pendingTurn),
                          overdue: pendingTurn.isOverdue,
                          macStyle: macStyle,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          _Composer(
            embedded: widget.embedded,
            macStyle: macStyle,
            controller: textController,
            pendingAttachment: _pendingAttachment,
            enabled:
                !isDeletedAgentConversation && groupSendDisabledReason == null,
            disabledReason: isDeletedAgentConversation
                ? '智能体已删除，无法继续发送消息'
                : groupSendDisabledReason,
            onSend: () => _submitComposer(currentConversation),
            onAttach: () async {
              await _pickAndStageAttachment();
            },
            onRemoveAttachment: _clearPendingAttachment,
          ),
        ],
      ),
    );
    if (macStyle) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: CupertinoColors.white),
        child: page,
      );
    }
    return AwikiMeWidgets.pageBackground(child: page);
  }

  bool _canRetryMessage(ChatMessage message) {
    if (!message.isAttachmentMessage) {
      return true;
    }
    final localPath = message.attachment?.localPath?.trim();
    return localPath != null && localPath.isNotEmpty;
  }

  Future<void> _openDetails() async {
    if (!widget.conversation.isGroup &&
        widget.conversation.targetDid != null &&
        widget.conversation.targetDid!.isNotEmpty) {
      await AppNavigator.push(
        context,
        (_) => PeerProfilePage(did: widget.conversation.targetDid!),
      );
      return;
    }
    await AppNavigator.push(
      context,
      (_) => GroupDetailPage(initialGroup: _findCurrentGroup()),
    );
  }

  Future<void> _openAgentInbox() async {
    await AppNavigator.push(
      context,
      (_) => AgentInboxPage(conversation: _currentConversationForTitle()),
    );
  }

  Future<void> _pickAndStageAttachment() async {
    final conversation = _currentConversationSnapshot();
    if (conversation.isDeletedAgentConversation ||
        _groupSendDisabledReason(conversation) != null) {
      return;
    }
    try {
      final draft = await ref
          .read(attachmentPickerServiceProvider)
          .pickAttachment();
      if (draft == null) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingAttachment = draft;
      });
      ref
          .read(chatComposerDraftsProvider.notifier)
          .setAttachment(conversation, draft);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  void _clearPendingAttachment() {
    if (_pendingAttachment == null) {
      return;
    }
    final conversation = _currentConversationSnapshot();
    setState(() {
      _pendingAttachment = null;
    });
    ref
        .read(chatComposerDraftsProvider.notifier)
        .setAttachment(conversation, null);
  }

  Future<void> _submitComposer(ConversationSummary conversation) async {
    if (conversation.isDeletedAgentConversation ||
        _groupSendDisabledReason(conversation) != null) {
      return;
    }
    final attachment = _pendingAttachment;
    final content = textController.text.trim();
    if (attachment == null && content.isEmpty) {
      return;
    }
    textController.clear();
    ref.read(chatComposerDraftsProvider.notifier).clearDraft(conversation);
    if (attachment != null) {
      setState(() {
        _pendingAttachment = null;
      });
    }
    final expectedAgentReplyDid = _runtimeAgentForConversation(
      conversation,
      ref.read(agentsProvider).agents,
    )?.agentDid;
    if (attachment != null) {
      await ref
          .read(chatThreadsProvider.notifier)
          .sendAttachment(
            conversation: conversation,
            attachment: attachment,
            caption: content.isEmpty ? null : content,
            expectedAgentReplyDid: expectedAgentReplyDid,
          );
      return;
    }
    await ref
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: content,
          expectedAgentReplyDid: expectedAgentReplyDid,
        );
  }

  Future<void> _downloadAttachment(
    ConversationSummary conversation,
    ChatMessage message,
  ) async {
    if (_downloadingAttachmentMessageIds.contains(message.localId)) {
      return;
    }
    setState(() {
      _downloadingAttachmentMessageIds.add(message.localId);
    });
    try {
      final result = await ref
          .read(chatThreadsProvider.notifier)
          .downloadAttachment(conversation: conversation, message: message);
      final bytes = result.bytes;
      if (bytes == null) {
        throw StateError('附件下载结果为空。');
      }
      final filename =
          result.filename ?? message.attachment?.filename ?? 'attachment';
      final mimeType =
          result.mimeType ??
          message.attachment?.mimeType ??
          'application/octet-stream';
      final savedPath = await ref
          .read(attachmentPickerServiceProvider)
          .saveAttachment(filename: filename, mimeType: mimeType, bytes: bytes);
      if (savedPath != null && savedPath.trim().isNotEmpty) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.exportedTo(savedPath));
      }
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (mounted) {
        setState(() {
          _downloadingAttachmentMessageIds.remove(message.localId);
        });
      }
    }
  }

  Future<void> _refreshCurrentConversation(
    ConversationSummary conversation,
  ) async {
    if (_isRefreshingCurrentConversation) {
      return;
    }
    setState(() {
      _isRefreshingCurrentConversation = true;
    });
    final startedAt = DateTime.now();
    try {
      await ref
          .read(chatThreadsProvider.notifier)
          .refreshConversation(
            conversation,
            displayThreadId: widget.conversation.threadId,
          );
      final elapsed = DateTime.now().difference(startedAt);
      const minimumVisibleTime = Duration(milliseconds: 350);
      if (elapsed < minimumVisibleTime) {
        await Future<void>.delayed(minimumVisibleTime - elapsed);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingCurrentConversation = false;
        });
      }
    }
  }

  bool _isFollowableDirect(ConversationSummary conversation) {
    final targetDid = conversation.targetDid?.trim() ?? '';
    return !conversation.isGroup && targetDid.startsWith('did:');
  }

  void _requestAgentsIfNeeded(ConversationSummary conversation) {
    if (_didRequestAgents ||
        conversation.isGroup ||
        (conversation.targetDid?.trim().isEmpty ?? true) ||
        ref.read(agentsProvider).agents.isNotEmpty) {
      return;
    }
    _didRequestAgents = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(agentsProvider.notifier).load());
    });
  }

  Future<void> _toggleFollow(ConversationSummary conversation) async {
    final targetDid = conversation.targetDid?.trim();
    if (targetDid == null || targetDid.isEmpty) {
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

  void _scrollToBottom() {
    if (!scrollController.hasClients) {
      return;
    }
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
  }

  ConversationSummary? _matchingConversation(
    List<ConversationSummary> conversations,
  ) {
    for (final conversation in conversations) {
      if (conversation.threadId == widget.conversation.threadId) {
        return conversation;
      }
    }
    for (final conversation in conversations) {
      if (sameConversationTarget(conversation, widget.conversation)) {
        return conversation;
      }
    }
    return null;
  }

  ConversationSummary _currentConversationForTitle() {
    final conversations = ref.watch(conversationListProvider).conversations;
    final latest = _matchingConversation(conversations);
    final base = latest ?? widget.conversation;
    if (!base.isGroup || base.groupId == null || base.groupId!.isEmpty) {
      return base;
    }
    final groupName = _currentGroupName(base.groupId!);
    final groupAvatarUri = _currentGroupAvatarUri(base.groupId!);
    if ((groupName == null || groupName == base.displayName) &&
        groupAvatarUri == base.avatarUri) {
      return base;
    }
    return base.copyWith(
      displayName: groupName ?? base.displayName,
      avatarUri: groupAvatarUri ?? base.avatarUri,
    );
  }

  ConversationSummary _currentConversationSnapshot() {
    final conversations = ref.read(conversationListProvider).conversations;
    final latest = _matchingConversation(conversations);
    return latest ?? widget.conversation;
  }

  String? _currentGroupName(String groupId) {
    final groups = ref.watch(groupProvider).groups;
    for (final group in groups) {
      if (group.groupId == groupId &&
          !GroupDisplayName.isIdLike(group.displayName, groupId)) {
        return group.displayName;
      }
    }
    return null;
  }

  String? _currentGroupAvatarUri(String groupId) {
    final groups = ref.watch(groupProvider).groups;
    for (final group in groups) {
      if (group.groupId == groupId) {
        return group.avatarUri;
      }
    }
    return null;
  }

  String? _groupSendDisabledReason(ConversationSummary conversation) {
    if (!conversation.isGroup) {
      return null;
    }
    final groupId = conversation.groupId?.trim();
    if (groupId == null || groupId.isEmpty) {
      return null;
    }
    for (final group in ref.watch(groupProvider).groups) {
      if (group.groupId != groupId) {
        continue;
      }
      final status = group.membershipStatus?.trim();
      if (status == null || status.isEmpty || status == 'active') {
        return null;
      }
      if (status == 'left' || status == 'removed') {
        return '你已不在这个群聊中，不能继续发送消息';
      }
      return '当前群聊暂时不能发送消息';
    }
    return null;
  }

  bool _threadNeedsHistorySync(
    ChatThreadState thread,
    ConversationSummary conversation,
  ) {
    if (thread.isLoading) {
      return false;
    }
    if (thread.messages.isEmpty || conversation.unreadCount > 0) {
      return true;
    }
    final latestLocalAt = thread.messages
        .map((message) => message.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return conversation.lastMessageAt.isAfter(latestLocalAt);
  }

  String _dateLabel(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month-$day';
  }

  bool _shouldShowDivider(ChatMessage? previous, ChatMessage current) {
    if (previous == null) {
      return true;
    }
    return current.createdAt
            .toLocal()
            .difference(previous.createdAt.toLocal())
            .inMinutes >=
        30;
  }

  bool _shouldShowSenderLabel(ChatMessage? previous, ChatMessage current) {
    if (!widget.conversation.isGroup || current.isMine) {
      return false;
    }
    if (previous == null || previous.isMine) {
      return true;
    }
    if (_shouldShowDivider(previous, current)) {
      return true;
    }
    return previous.senderDid.trim() != current.senderDid.trim();
  }

  double _messageBottomSpacing({
    required AwikiResponsiveInfo responsive,
    required bool macStyle,
    required ChatMessage current,
    required ChatMessage? next,
    required bool hasAgentProcessing,
    required bool nextHasAgentProcessing,
  }) {
    final defaultSpacing = macStyle
        ? responsive.displayScaled(16)
        : responsive.spacing(24);
    if (hasAgentProcessing) {
      return macStyle ? responsive.displayScaled(18) : responsive.spacing(24);
    }
    if (nextHasAgentProcessing &&
        next != null &&
        current.isMine == next.isMine &&
        !_shouldShowDivider(current, next)) {
      return macStyle ? responsive.displayScaled(8) : responsive.spacing(10);
    }
    if (_shouldTightenBeforeSenderLabel(current, next)) {
      return macStyle ? responsive.displayScaled(6) : responsive.spacing(8);
    }
    return defaultSpacing;
  }

  bool _shouldTightenBeforeSenderLabel(ChatMessage current, ChatMessage? next) {
    if (next == null || !current.isMine || _shouldShowDivider(current, next)) {
      return false;
    }
    return _shouldShowSenderLabel(current, next);
  }

  String _timeDividerLabel(DateTime date, {DateTime? previous}) {
    final localDate = date.toLocal();
    final time =
        '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    return '${_dateLabel(localDate)} $time';
  }

  String _displayNameForMessage(BuildContext context, ChatMessage message) {
    final senderName = message.senderName?.trim() ?? '';
    final senderDid = message.senderDid.trim();
    if (senderName.isNotEmpty) {
      if (!senderName.startsWith('did:')) {
        return senderName;
      }
      return DidDisplayFormatter.compactDisplayName(
        displayName: senderName,
        fallbackDid: senderDid.isNotEmpty ? senderDid : senderName,
      );
    }
    if (!senderDid.startsWith('did:')) {
      return senderDid.isNotEmpty ? senderDid : context.l10n.chatUnknownUser;
    }
    return DidDisplayFormatter.compactDid(senderDid);
  }

  GroupSummary _findCurrentGroup() {
    final groups = ref.read(groupProvider).groups;
    for (final item in groups) {
      if (item.groupId == widget.conversation.groupId) {
        return item;
      }
    }
    if (groups.isNotEmpty) {
      return groups.first;
    }
    throw StateError('Group not found');
  }

  AgentSummary? _runtimeAgentForConversation(
    ConversationSummary conversation,
    List<AgentSummary> agents,
  ) {
    if (conversation.isGroup) {
      return null;
    }
    final targetDid = conversation.targetDid?.trim();
    if (targetDid == null || targetDid.isEmpty) {
      return null;
    }
    for (final agent in agents) {
      if (agent.isRuntime && agent.agentDid == targetDid) {
        return agent;
      }
    }
    return null;
  }

  String _agentProcessingAvatarSeed(
    AgentSummary? runtimeAgent,
    ConversationSummary conversation,
  ) {
    if (runtimeAgent != null) {
      return AgentDisplayName.title(runtimeAgent);
    }
    return conversation.displayName;
  }

  String _agentProcessingLabel(AgentPendingTurn turn) {
    return turn.isOverdue ? '智能体仍在处理，稍后可刷新查看' : '智能体正在处理...';
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.embedded,
    required this.macStyle,
    required this.isRefreshing,
    required this.classification,
    required this.isDeletedAgentConversation,
    required this.isFollowing,
    required this.onDetails,
    required this.onRefresh,
    required this.showAgentInbox,
    this.onFollowTap,
    this.onMacIdentityPanelTap,
    this.onAgentInboxTap,
    this.onMacConversationInfoTap,
    this.macIdentityPanelActive = false,
    this.macAgentInboxPanelActive = false,
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
  final bool isFollowing;
  final bool showAgentInbox;
  final VoidCallback onDetails;
  final Future<void> Function()? onFollowTap;
  final VoidCallback? onMacIdentityPanelTap;
  final VoidCallback? onAgentInboxTap;
  final VoidCallback? onMacConversationInfoTap;
  final bool macIdentityPanelActive;
  final bool macAgentInboxPanelActive;
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
                AvatarBadge(
                  seed: compactName,
                  size: avatarSize,
                  avatarUri: conversation.avatarUri,
                ),
                SizedBox(width: responsive.displayScaled(10)),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
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
                      if (agentBadgeLabel != null && width >= 500) ...<Widget>[
                        SizedBox(width: responsive.displayScaled(8)),
                        _MacChatPill(
                          label: agentBadgeLabel,
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
                  ),
                ),
                SizedBox(width: actionGap),
                if (onFollowTap != null) ...<Widget>[
                  _ChatFollowButton(
                    isFollowing: isFollowing,
                    compact: width < 560,
                    onTap: onFollowTap!,
                  ),
                  SizedBox(width: responsive.displayScaled(8)),
                ],
                _MacChatHeaderButton(
                  key: const Key('chat-refresh-button'),
                  semanticLabel: '刷新当前会话',
                  icon: CupertinoIcons.refresh,
                  isLoading: isRefreshing,
                  onTap: onRefresh,
                ),
                if (showAgentInbox && onAgentInboxTap != null) ...<Widget>[
                  SizedBox(width: responsive.displayScaled(8)),
                  _MacChatHeaderButton(
                    key: const Key('chat-agent-inbox-button'),
                    semanticLabel: 'Agent 收件箱',
                    icon: CupertinoIcons.tray,
                    isActive: macAgentInboxPanelActive,
                    onTap: () async {
                      onAgentInboxTap!();
                    },
                  ),
                ],
                SizedBox(width: responsive.displayScaled(8)),
                _MacChatIdentityButton(
                  key: const Key('chat-identity-card-button'),
                  label: conversation.isGroup ? '群聊信息' : '身份卡',
                  showLabel: showIdentityLabel,
                  isActive: macIdentityPanelActive,
                  onTap: onMacIdentityPanelTap ?? onDetails,
                ),
                if (onMacConversationInfoTap != null) ...<Widget>[
                  SizedBox(width: responsive.displayScaled(8)),
                  _MacChatHeaderButton(
                    key: const Key('chat-conversation-info-button'),
                    semanticLabel: '折叠会话信息',
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
          AvatarBadge(
            seed: compactName,
            size: responsive.avatarSizeMd,
            avatarUri: conversation.avatarUri,
          ),
          SizedBox(width: responsive.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
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
          if (onFollowTap != null) ...<Widget>[
            SizedBox(width: responsive.spacing(8)),
            _ChatFollowButton(
              isFollowing: isFollowing,
              compact: true,
              onTap: onFollowTap!,
            ),
            SizedBox(width: responsive.spacing(4)),
          ],
          if (showAgentInbox && onAgentInboxTap != null) ...<Widget>[
            TopBarActionButton(
              onTap: onAgentInboxTap,
              semanticsLabel: 'Agent 收件箱',
              child: Padding(
                padding: EdgeInsets.all(responsive.spacing(8)),
                child: Icon(
                  CupertinoIcons.tray,
                  color: theme.title,
                  size: responsive.iconMd,
                ),
              ),
            ),
            SizedBox(width: responsive.spacing(4)),
          ],
          TopBarActionButton(
            onTap: onDetails,
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

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Center(
      child: AppSurface(
        margin: EdgeInsets.only(bottom: responsive.spacing(24)),
        padding: responsive.scaledInsets(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        color: context.awikiTheme.subtleSurface,
        radius: AwikiMeRadii.pill,
        child: Text(label, style: AwikiMeTextStyles.meta),
      ),
    );
  }
}

class _AgentProcessingIndicator extends StatelessWidget {
  const _AgentProcessingIndicator({
    required this.label,
    required this.avatarSeed,
    required this.macStyle,
  });

  final String label;
  final String avatarSeed;
  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final bubbleColor = macStyle
        ? const Color(0xFFF8FAFD)
        : theme.subtleSurface;
    final borderColor = macStyle
        ? const Color(0xFFDDE5F0)
        : theme.border.withValues(alpha: 0.72);
    final textColor = macStyle ? const Color(0xFF66728A) : theme.secondaryText;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AvatarBadge(
            seed: avatarSeed,
            size: macStyle
                ? responsive.displayScaled(34)
                : responsive.scaled(28),
          ),
          SizedBox(
            width: macStyle
                ? responsive.displayScaled(10)
                : responsive.spacing(12),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: macStyle
                    ? responsive.displayScaled(420)
                    : (responsive.isLarge ? 500 : 640),
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: macStyle
                      ? responsive.displayScaled(13)
                      : responsive.spacing(15),
                  vertical: macStyle
                      ? responsive.displayScaled(9)
                      : responsive.spacing(12),
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(8)
                          : responsive.scaled(6),
                    ),
                    topRight: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(10)
                          : responsive.scaled(20),
                    ),
                    bottomLeft: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(10)
                          : responsive.scaled(20),
                    ),
                    bottomRight: Radius.circular(
                      macStyle
                          ? responsive.displayScaled(10)
                          : responsive.scaled(20),
                    ),
                  ),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CupertinoActivityIndicator(
                      radius: macStyle
                          ? responsive.displayScaled(6.5)
                          : responsive.scaled(7),
                      color: textColor,
                    ),
                    SizedBox(
                      width: macStyle
                          ? responsive.displayScaled(8)
                          : responsive.spacing(9),
                    ),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: macStyle
                              ? responsive.displayScaled(13)
                              : responsive.metaSm,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAgentProcessingStatus extends StatelessWidget {
  const _MessageAgentProcessingStatus({
    required this.label,
    required this.overdue,
    required this.macStyle,
  });

  final String label;
  final bool overdue;
  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final foreground = overdue
        ? (macStyle ? const Color(0xFF9A5A00) : const Color(0xFF936300))
        : (macStyle ? const Color(0xFF64718A) : theme.secondaryText);
    final background = overdue
        ? const Color(0xFFFFF5DC)
        : (macStyle ? const Color(0xFFF6F8FC) : theme.subtleSurface);
    final border = overdue
        ? const Color(0xFFE9D49D)
        : (macStyle
              ? const Color(0xFFE0E7F1)
              : theme.border.withValues(alpha: 0.68));
    final iconSize = macStyle
        ? responsive.displayScaled(12.5)
        : responsive.scaled(13);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: macStyle
                ? responsive.displayScaled(420)
                : (responsive.isLarge ? 500 : 640),
          ),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: macStyle
                  ? responsive.displayScaled(10)
                  : responsive.spacing(11),
              vertical: macStyle
                  ? responsive.displayScaled(6)
                  : responsive.spacing(7),
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(
                macStyle ? responsive.displayScaled(8) : 12,
              ),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (overdue)
                  Icon(CupertinoIcons.clock, color: foreground, size: iconSize)
                else
                  CupertinoActivityIndicator(
                    radius: iconSize / 2,
                    color: foreground,
                  ),
                SizedBox(
                  width: macStyle
                      ? responsive.displayScaled(7)
                      : responsive.spacing(7),
                ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: macStyle
                          ? responsive.displayScaled(12)
                          : responsive.metaSm,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.senderLabel,
    required this.showSenderLabel,
    this.macStyle = false,
    this.onRetry,
    this.onDownload,
    this.isDownloading = false,
  });

  final ChatMessage message;
  final String senderLabel;
  final bool showSenderLabel;
  final bool macStyle;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDownload;
  final bool isDownloading;

  Widget _withE2eMessageSemantics({required Widget child}) {
    return e2eSemantics(
      identifier: e2eMessageIdentifier(message.content),
      label: message.content,
      child: child,
    );
  }

  Widget _buildSenderLabel(BuildContext context, {required bool macStyle}) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: macStyle ? responsive.displayScaled(2) : responsive.spacing(4),
        bottom: macStyle ? responsive.displayScaled(5) : responsive.spacing(5),
      ),
      child: Text(
        senderLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: macStyle ? const Color(0xFF66728A) : theme.secondaryText,
          fontSize: macStyle
              ? responsive.displayScaled(11.5)
              : responsive.metaSm,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }

  double _senderLabelOffset(BuildContext context, {required bool macStyle}) {
    final responsive = context.awikiResponsive;
    final fontSize = macStyle
        ? responsive.displayScaled(11.5)
        : responsive.metaSm;
    final bottom = macStyle
        ? responsive.displayScaled(5)
        : responsive.spacing(5);
    return fontSize * 1.2 + bottom;
  }

  double _senderContentTopInset(
    BuildContext context, {
    required bool macStyle,
  }) {
    final responsive = context.awikiResponsive;
    return macStyle ? responsive.displayScaled(10) : responsive.spacing(10);
  }

  Widget _withSendingIndicator(
    BuildContext context, {
    required bool isMine,
    required bool macStyle,
    required Widget child,
  }) {
    if (!isMine || message.sendState != MessageSendState.sending) {
      return child;
    }
    final responsive = context.awikiResponsive;
    final gap = macStyle ? responsive.displayScaled(7) : responsive.spacing(8);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _SendingMessageIndicator(macStyle: macStyle),
        SizedBox(width: gap),
        Flexible(child: child),
      ],
    );
  }

  Widget _buildMacBubble(BuildContext context, bool isMine) {
    final responsive = context.awikiResponsive;
    final textStyle = TextStyle(
      color: const Color(0xFF17213A),
      fontSize: responsive.displayScaled(14),
      height: 1.45,
    );
    final child = message.attachment == null
        ? _MessageTextContent(
            text: message.content,
            style: textStyle,
            renderMarkdown: !isMine,
          )
        : _AttachmentContent(
            message: message,
            macStyle: true,
            onDownload: onDownload,
            isDownloading: isDownloading,
          );
    final bubble = Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        if (showSenderLabel) _buildSenderLabel(context, macStyle: true),
        _withSendingIndicator(
          context,
          isMine: isMine,
          macStyle: true,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: responsive.displayScaled(420),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: responsive.displayScaled(14),
              vertical: responsive.displayScaled(10),
            ),
            decoration: BoxDecoration(
              color: isMine ? const Color(0xFFEAF2FF) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
              border: Border.all(
                color: isMine
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFDDE5F0),
              ),
            ),
            child: SelectionArea(child: child),
          ),
        ),
        if (message.sendState == MessageSendState.failed) ...<Widget>[
          SizedBox(height: responsive.displayScaled(8)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SelectionArea(
                child: Text(
                  '发送失败',
                  style: TextStyle(
                    fontSize: responsive.displayScaled(12),
                    color: const Color(0xFFFF3B30),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onRetry != null) ...<Widget>[
                SizedBox(width: responsive.displayScaled(10)),
                AppPressableText(
                  onTap: onRetry,
                  semanticLabel: '重试发送',
                  child: Text(
                    '重试',
                    style: TextStyle(
                      fontSize: responsive.displayScaled(12),
                      color: const Color(0xFF0B65F8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
    return _withE2eMessageSemantics(
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine) ...<Widget>[
            Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderLabelOffset(context, macStyle: true)
                    : 0,
              ),
              child: AvatarBadge(
                seed: senderLabel,
                size: responsive.displayScaled(34),
              ),
            ),
            SizedBox(width: responsive.displayScaled(10)),
          ],
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderContentTopInset(context, macStyle: true)
                    : 0,
              ),
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final textStyle = TextStyle(
      color: theme.title,
      fontSize: responsive.bodyMd,
      height: responsive.isPhone ? 1.5 : 1.4,
    );
    if (macStyle) {
      return _buildMacBubble(context, isMine);
    }
    return _withE2eMessageSemantics(
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isMine) ...<Widget>[
            Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderLabelOffset(context, macStyle: false)
                    : 0,
              ),
              child: AvatarBadge(
                seed: senderLabel,
                size: responsive.scaled(28),
              ),
            ),
            SizedBox(width: responsive.spacing(12)),
          ],
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(
                top: showSenderLabel
                    ? _senderContentTopInset(context, macStyle: false)
                    : 0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: responsive.isLarge ? 500 : 640,
                ),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: <Widget>[
                    if (showSenderLabel)
                      _buildSenderLabel(context, macStyle: false),
                    _withSendingIndicator(
                      context,
                      isMine: isMine,
                      macStyle: false,
                      child: Container(
                        padding: responsive.scaledInsets(
                          const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? AwikiMePalette.actionBlueSoft
                              : theme.subtleSurface,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(isMine ? 22 : 6),
                            topRight: Radius.circular(isMine ? 6 : 22),
                            bottomLeft: const Radius.circular(22),
                            bottomRight: const Radius.circular(22),
                          ),
                        ),
                        child: SelectionArea(
                          child: message.attachment == null
                              ? _MessageTextContent(
                                  text: message.content,
                                  style: textStyle,
                                  renderMarkdown: !isMine,
                                )
                              : _AttachmentContent(
                                  message: message,
                                  macStyle: false,
                                  onDownload: onDownload,
                                  isDownloading: isDownloading,
                                ),
                        ),
                      ),
                    ),
                    if (message.sendState ==
                        MessageSendState.failed) ...<Widget>[
                      SizedBox(height: responsive.spacing(8)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SelectionArea(
                            child: Text(
                              '发送失败',
                              style: TextStyle(
                                fontSize: responsive.metaSm,
                                color: theme.danger,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (onRetry != null) ...<Widget>[
                            SizedBox(width: responsive.spacing(10)),
                            AppPressableText(
                              onTap: onRetry,
                              semanticLabel: '重试发送',
                              child: Text(
                                '重试',
                                style: TextStyle(
                                  fontSize: responsive.metaSm,
                                  color: theme.primaryDark,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendingMessageIndicator extends StatelessWidget {
  const _SendingMessageIndicator({required this.macStyle});

  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final size = macStyle
        ? responsive.displayScaled(18)
        : responsive.scaled(18);
    final radius = macStyle
        ? responsive.displayScaled(6)
        : responsive.scaled(6);
    return Semantics(
      label: '发送中',
      liveRegion: true,
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: CupertinoActivityIndicator(
            radius: radius,
            color: macStyle ? const Color(0xFF8A96AA) : theme.tertiaryText,
          ),
        ),
      ),
    );
  }
}

class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({
    required this.message,
    required this.macStyle,
    required this.onDownload,
    required this.isDownloading,
  });

  final ChatMessage message;
  final bool macStyle;
  final Future<void> Function()? onDownload;
  final bool isDownloading;

  @override
  Widget build(BuildContext context) {
    final attachment = message.attachment!;
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final caption = attachment.caption?.trim();
    final titleStyle = TextStyle(
      color: macStyle ? const Color(0xFF17213A) : theme.title,
      fontSize: macStyle ? responsive.displayScaled(13.5) : responsive.bodyMd,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    final metaStyle = TextStyle(
      color: macStyle ? const Color(0xFF66728A) : theme.secondaryText,
      fontSize: macStyle ? responsive.displayScaled(12) : responsive.metaSm,
      fontWeight: FontWeight.w500,
      height: 1.25,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: macStyle
            ? responsive.displayScaled(220)
            : responsive.scaled(210),
        maxWidth: macStyle
            ? responsive.displayScaled(360)
            : responsive.scaled(420),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (caption != null && caption.isNotEmpty) ...<Widget>[
            _MessageTextContent(
              text: caption,
              style: TextStyle(
                color: macStyle ? const Color(0xFF17213A) : theme.title,
                fontSize: macStyle
                    ? responsive.displayScaled(14)
                    : responsive.bodyMd,
                height: 1.4,
              ),
              renderMarkdown: !message.isMine,
            ),
            SizedBox(
              height: macStyle
                  ? responsive.displayScaled(9)
                  : responsive.spacing(9),
            ),
            _AttachmentCaptionDivider(macStyle: macStyle),
            SizedBox(
              height: macStyle
                  ? responsive.displayScaled(9)
                  : responsive.spacing(9),
            ),
          ],
          Row(
            children: <Widget>[
              Container(
                width: macStyle
                    ? responsive.displayScaled(38)
                    : responsive.scaled(40),
                height: macStyle
                    ? responsive.displayScaled(38)
                    : responsive.scaled(40),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: macStyle
                      ? const Color(0xFFEAF2FF)
                      : theme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(
                    macStyle ? responsive.displayScaled(8) : 10,
                  ),
                  border: Border.all(
                    color: macStyle ? const Color(0xFFDDE5F0) : theme.border,
                  ),
                ),
                child: Icon(
                  CupertinoIcons.doc_fill,
                  color: macStyle ? const Color(0xFF0B65F8) : theme.primary,
                  size: macStyle
                      ? responsive.displayScaled(20)
                      : responsive.iconSm,
                ),
              ),
              SizedBox(
                width: macStyle
                    ? responsive.displayScaled(10)
                    : responsive.spacing(10),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _MessagePlainText(
                      text: attachment.displayName,
                      maxLines: 2,
                      style: titleStyle,
                    ),
                    SizedBox(
                      height: macStyle
                          ? responsive.displayScaled(4)
                          : responsive.spacing(4),
                    ),
                    Text(
                      _formatAttachmentMeta(
                        attachment.mimeType,
                        attachment.sizeBytes,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
              if (onDownload != null) ...<Widget>[
                SizedBox(
                  width: macStyle
                      ? responsive.displayScaled(10)
                      : responsive.spacing(10),
                ),
                _AttachmentActionButton(
                  macStyle: macStyle,
                  isLoading: isDownloading,
                  onTap: onDownload!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageTextContent extends StatelessWidget {
  const _MessageTextContent({
    required this.text,
    required this.style,
    required this.renderMarkdown,
  });

  final String text;
  final TextStyle style;
  final bool renderMarkdown;

  @override
  Widget build(BuildContext context) {
    if (!renderMarkdown) {
      return _MessagePlainText(text: text, style: style);
    }
    return MarkdownBody(
      data: text,
      selectable: false,
      shrinkWrap: true,
      styleSheet: _chatMarkdownStyleSheet(context, style),
    );
  }
}

MarkdownStyleSheet _chatMarkdownStyleSheet(
  BuildContext context,
  TextStyle bodyStyle,
) {
  final theme = context.awikiTheme;
  final responsive = context.awikiResponsive;
  final fontSize = bodyStyle.fontSize ?? responsive.bodyMd;
  final codeBackground = theme.surface.withValues(alpha: 0.74);
  final quoteBackground = theme.surface.withValues(alpha: 0.58);
  return MarkdownStyleSheet(
    a: bodyStyle.copyWith(
      color: theme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.none,
    ),
    p: bodyStyle,
    pPadding: EdgeInsets.zero,
    strong: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    em: bodyStyle.copyWith(fontStyle: FontStyle.italic),
    del: bodyStyle.copyWith(decoration: TextDecoration.lineThrough),
    code: bodyStyle.copyWith(
      fontFamily: 'monospace',
      fontSize: fontSize * 0.92,
      backgroundColor: codeBackground,
    ),
    h1: bodyStyle.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700),
    h1Padding: EdgeInsets.only(bottom: responsive.spacing(4)),
    h2: bodyStyle.copyWith(fontSize: fontSize + 1, fontWeight: FontWeight.w700),
    h2Padding: EdgeInsets.only(bottom: responsive.spacing(4)),
    h3: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    h3Padding: EdgeInsets.only(bottom: responsive.spacing(3)),
    h4: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    h4Padding: EdgeInsets.only(bottom: responsive.spacing(3)),
    h5: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    h5Padding: EdgeInsets.zero,
    h6: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    h6Padding: EdgeInsets.zero,
    blockSpacing: responsive.spacing(6),
    listIndent: responsive.spacing(18),
    listBullet: bodyStyle,
    listBulletPadding: EdgeInsets.only(right: responsive.spacing(5)),
    blockquote: bodyStyle,
    blockquotePadding: EdgeInsets.symmetric(
      horizontal: responsive.spacing(9),
      vertical: responsive.spacing(6),
    ),
    blockquoteDecoration: BoxDecoration(
      color: quoteBackground,
      border: Border(
        left: BorderSide(color: theme.border, width: responsive.scaled(3)),
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    codeblockPadding: EdgeInsets.all(responsive.spacing(8)),
    codeblockDecoration: BoxDecoration(
      color: codeBackground,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: theme.border.withValues(alpha: 0.8)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: theme.border)),
    ),
  );
}

class _MessagePlainText extends StatelessWidget {
  const _MessagePlainText({
    required this.text,
    required this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      style: style,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textWidthBasis: TextWidthBasis.parent,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }
}

class _AttachmentCaptionDivider extends StatelessWidget {
  const _AttachmentCaptionDivider({required this.macStyle});

  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final horizontalInset = macStyle
        ? responsive.displayScaled(2)
        : responsive.spacing(2);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalInset),
      child: DecoratedBox(
        key: const Key('chat-attachment-caption-divider'),
        decoration: BoxDecoration(
          color: macStyle
              ? const Color(0xFFC3CDDB).withValues(alpha: 0.95)
              : theme.secondaryText.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(1),
        ),
        child: const SizedBox(height: 1, width: double.infinity),
      ),
    );
  }
}

class _AttachmentActionButton extends StatelessWidget {
  const _AttachmentActionButton({
    required this.macStyle,
    required this.isLoading,
    required this.onTap,
  });

  final bool macStyle;
  final bool isLoading;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final size = macStyle
        ? responsive.displayScaled(32)
        : responsive.scaled(34);
    return AppIconButton(
      onPressed: isLoading ? null : () async => onTap(),
      semanticLabel: '下载附件',
      tooltip: '下载附件',
      isLoading: isLoading,
      size: size,
      backgroundColor: macStyle ? CupertinoColors.white : theme.surface,
      borderColor: macStyle ? const Color(0xFFDDE5F0) : theme.border,
      borderRadius: BorderRadius.circular(
        macStyle ? responsive.displayScaled(8) : 10,
      ),
      child: Icon(
        CupertinoIcons.arrow_down_doc_fill,
        color: macStyle ? const Color(0xFF0B65F8) : theme.primary,
        size: macStyle ? responsive.displayScaled(17) : responsive.iconSm,
      ),
    );
  }
}

String _formatAttachmentMeta(String mimeType, int? sizeBytes) {
  final parts = <String>[];
  final type = mimeType.trim();
  if (type.isNotEmpty && type != 'application/octet-stream') {
    parts.add(type);
  }
  if (sizeBytes != null && sizeBytes >= 0) {
    parts.add(_formatFileSize(sizeBytes));
  }
  return parts.isEmpty ? '文件' : parts.join(' · ');
}

String _formatFileSize(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  if (unitIndex == 0) {
    return '$bytes ${units[unitIndex]}';
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}';
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.embedded,
    required this.macStyle,
    required this.controller,
    required this.pendingAttachment,
    this.enabled = true,
    this.disabledReason,
    required this.onSend,
    required this.onAttach,
    required this.onRemoveAttachment,
  });

  final bool embedded;
  final bool macStyle;
  final TextEditingController controller;
  final AttachmentDraft? pendingAttachment;
  final bool enabled;
  final String? disabledReason;
  final Future<void> Function() onSend;
  final Future<void> Function() onAttach;
  final VoidCallback onRemoveAttachment;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final FocusNode _inputFocusNode = FocusNode();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant _Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
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

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) {
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
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
    final nextText = text.replaceRange(start, end, '\n');
    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final canSubmit = _canSubmit;
    final disabledReason = widget.disabledReason ?? '当前会话无法继续发送消息';
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
                responsive.displayScaled(8),
                horizontal,
                responsive.displayScaled(16),
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
                    if (widget.enabled)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          if (showAttachment) ...<Widget>[
                            AppIconButton(
                              key: const Key('chat-attachment-button'),
                              onPressed: _attachIfNeeded,
                              semanticLabel: '添加附件',
                              tooltip: '添加附件',
                              size: responsive.displayScaled(34),
                              borderRadius: BorderRadius.circular(
                                responsive.displayScaled(9),
                              ),
                              child: Icon(
                                CupertinoIcons.paperclip,
                                color: const Color(0xFF34415C),
                                size: responsive.displayScaled(22),
                              ),
                            ),
                            SizedBox(width: responsive.displayScaled(10)),
                          ],
                          Expanded(
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
                                vertical: responsive.displayScaled(7),
                              ),
                              maxLines: 5,
                              onSubmitted: (_) async => _submitIfNeeded(),
                            ),
                          ),
                          SizedBox(width: responsive.displayScaled(10)),
                          AppPressable(
                            key: const Key('chat-send-button'),
                            onTap: _submitIfNeeded,
                            semanticLabel: '发送',
                            semanticsIdentifier: 'e2e-chat-send-button',
                            tooltip: '发送',
                            enabled: true,
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
                              width: responsive.displayScaled(36),
                              height: responsive.displayScaled(36),
                              decoration: BoxDecoration(
                                color: canSubmit
                                    ? const Color(0xFF0B65F8)
                                    : const Color(0xFFE5EAF2),
                                borderRadius: BorderRadius.circular(
                                  responsive.displayScaled(9),
                                ),
                              ),
                              child: _isSending
                                  ? const CupertinoActivityIndicator(
                                      radius: 8,
                                      color: CupertinoColors.white,
                                    )
                                  : Icon(
                                      CupertinoIcons.paperplane_fill,
                                      color: canSubmit
                                          ? CupertinoColors.white
                                          : const Color(0xFF8A96AA),
                                      size: responsive.displayScaled(18),
                                    ),
                            ),
                          ),
                        ],
                      ),
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
                      semanticsLabel: '添加附件',
                      tooltip: '添加附件',
                      child: Padding(
                        padding: EdgeInsets.all(responsive.spacing(6)),
                        child: AwikiAssetIcon(
                          assetName: 'assets/icons/icon_plus.svg',
                          size: responsive.iconMd,
                        ),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(8)),
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
                      label: '发送',
                      button: true,
                      child: TopBarActionButton(
                        key: const Key('chat-send-button'),
                        onTap: _submitIfNeeded,
                        semanticsLabel: '发送',
                        tooltip: '发送',
                        child: Padding(
                          padding: EdgeInsets.all(responsive.spacing(6)),
                          child: _isSending
                              ? CupertinoActivityIndicator(
                                  radius: responsive.displayScaled(8),
                                )
                              : AwikiAssetIcon(
                                  assetName: 'assets/icons/icon_send.svg',
                                  color: canSubmit
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

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({
    required this.attachment,
    required this.macStyle,
    required this.onRemove,
  });

  final AttachmentDraft attachment;
  final bool macStyle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final radius = responsive.radius(macStyle ? 8 : 12);
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
          Container(
            width: responsive.displayScaled(macStyle ? 28 : 32),
            height: responsive.displayScaled(macStyle ? 28 : 32),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(responsive.radius(8)),
            ),
            child: Icon(
              CupertinoIcons.doc,
              color: const Color(0xFF0B65F8),
              size: responsive.displayScaled(macStyle ? 16 : 18),
            ),
          ),
          SizedBox(width: responsive.spacing(9)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  attachment.displayName,
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
            semanticLabel: '移除附件',
            tooltip: '移除附件',
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
}
