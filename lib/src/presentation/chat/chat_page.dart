import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_router.dart';
import '../../app/e2e_semantics.dart';
import '../../app/app_services.dart';
import '../../application/attachment_preview_service.dart';
import '../../application/models/attachment_models.dart';
import '../../core/group_display_name.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/chat_mention.dart';
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
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../conversation_list/conversation_peer_classifier.dart';
import '../conversation_list/conversation_provider.dart';
import '../friends/friends_page.dart';
import '../friends/friends_provider.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'chat_provider.dart';

part 'parts/chat_header_part.dart';
part 'parts/chat_peer_info_part.dart';
part 'parts/chat_message_part.dart';
part 'parts/chat_composer_part.dart';

const _macChatHeaderActionColor = Color(0xFF44506A);
const _macChatHeaderActionActiveColor = Color(0xFF101B32);
const _macChatHeaderActionActiveBackground = Color(0xFFE4ECF7);
const _macChatHeaderActionIconSize = 16.0;
const _macChatHeaderActionFontWeight = FontWeight.w400;
const _macChatHeaderActionActiveFontWeight = FontWeight.w600;
const _chatMessageListBottomInset = 12.0;
const _macChatMessageListBottomInset = 10.0;

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: ChatView(
        key: ValueKey('chat-view:${conversation.threadId}'),
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
    this.onMacConversationInfoTap,
    this.macConversationInfoPanelActive = false,
    this.macStyle = false,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final VoidCallback? onMacIdentityPanelTap;
  final VoidCallback? onMacConversationInfoTap;
  final bool macConversationInfoPanelActive;
  final bool macStyle;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _BottomInitialScrollController extends ScrollController {
  _BottomInitialScrollController()
    : super(keepScrollOffset: false, debugLabel: 'ChatView.messages');

  _BottomInitialScrollPosition? get _bottomInitialPosition {
    if (!hasClients) {
      return null;
    }
    final position = this.position;
    return position is _BottomInitialScrollPosition ? position : null;
  }

  void prepareForInitialBottomPosition() {
    _bottomInitialPosition?.prepareForInitialBottomPosition();
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _BottomInitialScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _BottomInitialScrollPosition extends ScrollPositionWithSingleContext {
  _BottomInitialScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.debugLabel,
  }) : super(initialPixels: 0, keepScrollOffset: false);

  bool _shouldCorrectToBottom = true;

  void prepareForInitialBottomPosition() {
    _shouldCorrectToBottom = true;
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (!_shouldCorrectToBottom || !hasPixels) {
      return accepted;
    }
    if (maxScrollExtent <= minScrollExtent) {
      return accepted;
    }
    if (pixels == maxScrollExtent) {
      _shouldCorrectToBottom = false;
      return accepted;
    }
    correctPixels(maxScrollExtent);
    return false;
  }
}

enum _ChatScrollAnchorPhase { opening, active }

class _ChatViewState extends ConsumerState<ChatView> {
  final textController = TextEditingController();
  late final _BottomInitialScrollController scrollController;
  late final ChatThreadsController _chatThreadsController;
  late String _displayThreadId;
  AttachmentDraft? _pendingAttachment;
  bool _isApplyingComposerDraft = false;
  bool _isRefreshingCurrentConversation = false;
  bool _didRequestAgents = false;
  bool _hasDeferredBottomNotice = false;
  bool _userAwayFromBottom = false;
  bool _isProgrammaticScroll = false;
  bool _scrollToBottomScheduled = false;
  int _scrollRequestToken = 0;
  int _visibleReadAckToken = 0;
  bool _pendingScrollAnimated = false;
  int _pendingScrollSettleFrames = 1;
  _ChatScrollAnchorPhase _scrollAnchorPhase = _ChatScrollAnchorPhase.opening;
  bool _openingAnchorObservedContent = false;
  int _openingAnchorToken = 0;
  final Set<String> _downloadingAttachmentMessageIds = <String>{};
  static const double _nearBottomExtent = 96;

  @override
  void initState() {
    super.initState();
    _displayThreadId = widget.conversation.threadId;
    scrollController = _BottomInitialScrollController();
    _chatThreadsController = ref.read(chatThreadsProvider.notifier);
    _beginOpeningBottomAnchor();
    _markConversationVisible(
      widget.conversation,
      displayThreadId: _displayThreadId,
    );
    _restoreComposerDraft(widget.conversation);
    textController.addListener(_persistComposerText);
    scrollController.addListener(_handleScrollPositionChanged);
  }

  @override
  void dispose() {
    _visibleReadAckToken += 1;
    _cancelPendingScrollRequests();
    _markConversationHidden(
      widget.conversation,
      displayThreadId: _displayThreadId,
    );
    textController.removeListener(_persistComposerText);
    scrollController.removeListener(_handleScrollPositionChanged);
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!sameConversationTarget(oldWidget.conversation, widget.conversation)) {
      _visibleReadAckToken += 1;
      _markConversationHidden(
        oldWidget.conversation,
        displayThreadId: _displayThreadId,
      );
      _displayThreadId = widget.conversation.threadId;
      _markConversationVisible(
        widget.conversation,
        displayThreadId: _displayThreadId,
      );
      _restoreComposerDraft(widget.conversation, updateState: true);
      _hasDeferredBottomNotice = false;
      _userAwayFromBottom = false;
      _cancelPendingScrollRequests();
      _beginOpeningBottomAnchor();
    }
  }

  void _markConversationVisible(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) {
    _chatThreadsController.markConversationVisible(
      conversation,
      displayThreadId: displayThreadId ?? conversation.threadId,
    );
    _scheduleAcknowledgeVisibleConversationRead(
      conversation,
      reason: 'visible',
    );
  }

  void _markConversationHidden(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) {
    _chatThreadsController.markConversationHidden(
      conversation,
      displayThreadId: displayThreadId ?? conversation.threadId,
    );
  }

  void _acknowledgeVisibleConversationRead(
    ConversationSummary conversation, {
    String reason = 'visible',
  }) {
    _chatThreadsController.acknowledgeVisibleConversationRead(
      conversation,
      displayThreadId: _displayThreadId,
      reason: reason,
    );
  }

  void _scheduleAcknowledgeVisibleConversationRead(
    ConversationSummary conversation, {
    String reason = 'visible',
  }) {
    final token = ++_visibleReadAckToken;
    final displayThreadId = _displayThreadId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _visibleReadAckToken ||
          displayThreadId != _displayThreadId ||
          !sameConversationTarget(
            conversation,
            _currentConversationSnapshot(),
          )) {
        return;
      }
      _acknowledgeVisibleConversationRead(conversation, reason: reason);
    });
  }

  void _acknowledgeCurrentVisibleConversationRead({
    String reason = 'visible_interaction',
  }) {
    if (_hasDeferredBottomNotice && !_isNearBottom()) {
      return;
    }
    _acknowledgeVisibleConversationRead(
      _currentConversationSnapshot(),
      reason: reason,
    );
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
    final buildWatch = Stopwatch()..start();
    final responsive = context.awikiResponsive;
    final macStyle = widget.macStyle && responsive.isMacDesktop;
    final messageListBottomInset = macStyle
        ? responsive.displayScaled(_macChatMessageListBottomInset)
        : responsive.spacing(_chatMessageListBottomInset);
    final displayThreadId = _displayThreadId;
    final thread = ref.watch(chatThreadProvider(displayThreadId));
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
    ref.listen<ChatThreadState>(
      chatThreadProvider(displayThreadId),
      (previous, next) =>
          _handleThreadChanged(previous, next, currentConversation),
    );
    ref.listen<ConversationListState>(conversationListProvider, (_, next) {
      final updated = _matchingConversation(next.conversations);
      if (updated == null) {
        return;
      }
      if (!_hasDeferredBottomNotice && !_userAwayFromBottom) {
        _scheduleAcknowledgeVisibleConversationRead(
          updated,
          reason: 'visible_summary_update',
        );
      }
      unawaited(
        ref
            .read(chatThreadsProvider.notifier)
            .syncVisibleConversationAfterSummaryUpdate(
              updated,
              displayThreadId: displayThreadId,
            ),
      );
    });
    final messages = thread.messages;
    _settleOpeningBottomAnchorForCurrentThread(thread);
    final activePendingTurns = thread.agentPendingTurns
        .where((turn) => turn.isActive)
        .toList(growable: false);
    final messageAgentItems = _messageAgentTimelineItems(thread);
    final messageIdsWithAgentProcessing = <String>{
      for (final message in messages)
        if (thread.pendingAgentTurnsForMessage(message).isNotEmpty)
          message.localId,
    };
    final unmatchedPendingTurns = activePendingTurns
        .where(
          (turn) => !messages.any((message) => turn.matchesMessage(message)),
        )
        .toList(growable: false);
    final messageListItemCount =
        messages.length +
        unmatchedPendingTurns.length +
        messageAgentItems.length;
    buildWatch.stop();
    AwikiPerformanceLogger.log(
      'chat_page.build.prepare',
      elapsed: buildWatch.elapsed,
      fields: <String, Object?>{
        ...AwikiPerformanceLogger.threadField(currentConversation.threadId),
        'messages': messages.length,
        'pending': activePendingTurns.length,
        'timeline': messageAgentItems.length,
        'items': messageListItemCount,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
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
            onBack: widget.onBack,
            onDetails: _openDetails,
            onPeerInfoTap: _openDetails,
            onMacIdentityPanelTap: widget.onMacIdentityPanelTap,
            onMacConversationInfoTap: widget.onMacConversationInfoTap,
            macConversationInfoPanelActive:
                widget.macConversationInfoPanelActive,
            onRefresh: () => _refreshCurrentConversation(currentConversation),
          ),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _acknowledgeCurrentVisibleConversationRead(
                reason: 'visible_pointer',
              ),
              child: Stack(
                children: <Widget>[
                  NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ListView.builder(
                      key: ValueKey('chat-messages:$displayThreadId'),
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
                        messageListBottomInset,
                      ),
                      itemCount: messageListItemCount,
                      itemBuilder: (_, index) {
                        final isLastItem = index == messageListItemCount - 1;
                        if (index >= messages.length) {
                          final recoveryIndex =
                              index -
                              messages.length -
                              unmatchedPendingTurns.length;
                          if (recoveryIndex >= 0) {
                            final item = messageAgentItems[recoveryIndex];
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: isLastItem
                                    ? 0
                                    : macStyle
                                    ? responsive.displayScaled(16)
                                    : responsive.spacing(18),
                              ),
                              child: _MessageAgentRecoveryCard(
                                item: item,
                                macStyle: macStyle,
                                onConfirm:
                                    item is _MessageAgentActionTimelineItem
                                    ? () async {
                                        await ref
                                            .read(chatThreadsProvider.notifier)
                                            .confirmAppAction(
                                              conversation: currentConversation,
                                              actionId: item.record.actionId,
                                            );
                                        if (mounted) {
                                          _restoreComposerDraft(
                                            currentConversation,
                                            updateState: true,
                                          );
                                        }
                                      }
                                    : null,
                                onReject:
                                    item is _MessageAgentActionTimelineItem
                                    ? () => ref
                                          .read(chatThreadsProvider.notifier)
                                          .rejectAppAction(
                                            conversation: currentConversation,
                                            actionId: item.record.actionId,
                                          )
                                    : null,
                              ),
                            );
                          }
                          final turn =
                              unmatchedPendingTurns[index - messages.length];
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: isLastItem
                                  ? 0
                                  : macStyle
                                  ? responsive.displayScaled(16)
                                  : responsive.spacing(24),
                            ),
                            child: _AgentProcessingIndicator(
                              label: _agentProcessingLabel(<AgentPendingTurn>[
                                turn,
                              ]),
                              avatarSeed: _agentProcessingAvatarSeed(
                                runtimeAgent,
                                currentConversation,
                              ),
                              macStyle: macStyle,
                            ),
                          );
                        }
                        final message = messages[index];
                        final pendingTurns = thread.pendingAgentTurnsForMessage(
                          message,
                        );
                        final previous = index == 0
                            ? null
                            : messages[index - 1];
                        final next = index + 1 < messages.length
                            ? messages[index + 1]
                            : null;
                        final senderLabel = _displayNameForMessage(
                          context,
                          message,
                        );
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
                              hasAgentProcessing: pendingTurns.isNotEmpty,
                              nextHasAgentProcessing:
                                  next != null &&
                                  messageIdsWithAgentProcessing.contains(
                                    next.localId,
                                  ),
                              isLastItem: isLastItem,
                            ),
                          ),
                          child: KeyedSubtree(
                            key: Key('chat-message-content:${message.localId}'),
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
                                  onRetry:
                                      message.sendState ==
                                          MessageSendState.failed
                                      ? (_canRetryMessage(message)
                                            ? () async {
                                                await ref
                                                    .read(
                                                      chatThreadsProvider
                                                          .notifier,
                                                    )
                                                    .retryMessage(
                                                      conversation:
                                                          currentConversation,
                                                      message: message,
                                                      expectedAgentReplyDid:
                                                          _expectedAgentReplyDidForConversation(
                                                            currentConversation,
                                                            runtimeAgent:
                                                                runtimeAgent,
                                                            classification:
                                                                peerClassification,
                                                          ),
                                                      displayThreadId:
                                                          _displayThreadId,
                                                    );
                                              }
                                            : null)
                                      : null,
                                  onDownload:
                                      message.attachment != null &&
                                          message.sendState ==
                                              MessageSendState.sent
                                      ? () => _openAttachment(
                                          currentConversation,
                                          message,
                                        )
                                      : null,
                                  isDownloading:
                                      _downloadingAttachmentMessageIds.contains(
                                        message.localId,
                                      ),
                                  onPeerInfoTap: _peerInfoTapForMessage(
                                    currentConversation,
                                    message,
                                    senderLabel,
                                  ),
                                ),
                                if (pendingTurns.isNotEmpty) ...<Widget>[
                                  SizedBox(
                                    height: macStyle
                                        ? responsive.displayScaled(7)
                                        : responsive.spacing(7),
                                  ),
                                  _MessageAgentProcessingStatus(
                                    label: _agentProcessingLabel(pendingTurns),
                                    overdue: pendingTurns.any(
                                      (turn) => turn.isOverdue,
                                    ),
                                    macStyle: macStyle,
                                    alignEnd: message.isMine,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_hasDeferredBottomNotice)
                    _NewMessagesButton(
                      macStyle: macStyle,
                      onTap: () => _scheduleScrollToBottom(animated: true),
                    ),
                ],
              ),
            ),
          ),
          _Composer(
            conversation: currentConversation,
            embedded: widget.embedded,
            macStyle: macStyle,
            controller: textController,
            pendingAttachment: _pendingAttachment,
            enabled:
                !isDeletedAgentConversation && groupSendDisabledReason == null,
            disabledReason: isDeletedAgentConversation
                ? '智能体已删除，无法继续发送消息'
                : groupSendDisabledReason,
            onSend: () => _submitComposer(
              currentConversation,
              classification: peerClassification,
            ),
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
    final conversation = _currentConversationForTitle();
    if (!conversation.isGroup &&
        conversation.targetDid != null &&
        conversation.targetDid!.isNotEmpty) {
      await _showPeerInfoDialog(conversation);
      return;
    }
    await AppNavigator.push(
      context,
      (_) => GroupDetailPage(initialGroup: _findCurrentGroup()),
    );
  }

  Future<void> _showPeerInfoDialog(ConversationSummary conversation) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => _PeerInfoDialog(conversation: conversation),
    );
  }

  VoidCallback? _peerInfoTapForMessage(
    ConversationSummary conversation,
    ChatMessage message,
    String senderLabel,
  ) {
    final targetDid = conversation.isGroup
        ? message.senderDid.trim()
        : conversation.targetDid?.trim();
    if (targetDid == null ||
        targetDid.isEmpty ||
        !targetDid.startsWith('did:')) {
      return null;
    }
    final peerConversation = conversation.isGroup
        ? ConversationSummary(
            threadId: 'profile:$targetDid',
            displayName: senderLabel,
            lastMessagePreview: '',
            lastMessageAt: message.createdAt,
            unreadCount: 0,
            isGroup: false,
            targetDid: targetDid,
            avatarSeed: senderLabel,
          )
        : conversation;
    return () => _showPeerInfoDialog(peerConversation);
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

  Future<void> _submitComposer(
    ConversationSummary conversation, {
    required ConversationPeerClassification classification,
  }) async {
    if (conversation.isDeletedAgentConversation ||
        _groupSendDisabledReason(conversation) != null) {
      return;
    }
    final attachment = _pendingAttachment;
    final rawContent = textController.text;
    final content = rawContent.trim();
    if (attachment == null && content.isEmpty) {
      return;
    }
    final draft = ref
        .read(chatComposerDraftsProvider.notifier)
        .draftFor(conversation);
    final validMentionDrafts = conversation.isGroup
        ? draft.validMentions
        : const <ChatMentionDraft>[];
    final messageContent = validMentionDrafts.isEmpty ? content : rawContent;
    textController.clear();
    ref.read(chatComposerDraftsProvider.notifier).clearDraft(conversation);
    if (attachment != null) {
      setState(() {
        _pendingAttachment = null;
      });
    }
    final expectedAgentReplyDid = _expectedAgentReplyDidForConversation(
      conversation,
      runtimeAgent: _runtimeAgentForConversation(
        conversation,
        ref.read(agentsProvider).agents,
      ),
      classification: classification,
    );
    if (attachment != null) {
      await ref
          .read(chatThreadsProvider.notifier)
          .sendAttachment(
            conversation: conversation,
            attachment: attachment,
            caption: messageContent.trim().isEmpty ? null : messageContent,
            mentions: validMentionDrafts,
            expectedAgentReplyDid: expectedAgentReplyDid,
            displayThreadId: _displayThreadId,
          );
      return;
    }
    await ref
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: messageContent,
          mentions: validMentionDrafts,
          expectedAgentReplyDid: expectedAgentReplyDid,
          displayThreadId: _displayThreadId,
        );
  }

  Future<void> _openAttachment(
    ConversationSummary conversation,
    ChatMessage message,
  ) async {
    final attachment = message.attachment;
    if (attachment == null) {
      return;
    }
    if (_downloadingAttachmentMessageIds.contains(message.localId)) {
      return;
    }
    setState(() {
      _downloadingAttachmentMessageIds.add(message.localId);
    });
    try {
      final previewPath = await ref
          .read(attachmentPreviewServiceProvider)
          .previewPathFor(
            message: message,
            download: () => ref
                .read(chatThreadsProvider.notifier)
                .downloadAttachment(
                  conversation: conversation,
                  message: message,
                ),
          );
      await ref.read(attachmentOpenServiceProvider).open(previewPath);
    } catch (error, stackTrace) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(
            _attachmentOpenErrorMessage(error),
            detail: _attachmentOpenErrorDetail(error, stackTrace),
          );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingAttachmentMessageIds.remove(message.localId);
        });
      }
    }
  }

  AppMessage _attachmentOpenErrorMessage(Object error) {
    final raw = error.toString().toLowerCase();
    if (error is AttachmentUnavailableException ||
        raw.contains('attachment object is not committed') ||
        raw.contains('attachment object has expired') ||
        raw.contains('attachment object is not available') ||
        raw.contains('message not found')) {
      return AppMessage.attachmentUnavailable();
    }
    return AppMessage.attachmentOpenFailed();
  }

  String _attachmentOpenErrorDetail(Object error, StackTrace stackTrace) {
    final buffer = StringBuffer()..writeln(error);
    final stack = stackTrace.toString().trim();
    if (stack.isNotEmpty) {
      buffer
        ..writeln()
        ..write(stack);
    }
    return buffer.toString().trim();
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
          .refreshConversation(conversation, displayThreadId: _displayThreadId);
      final elapsed = DateTime.now().difference(startedAt);
      const minimumVisibleTime = Duration(milliseconds: 350);
      if (elapsed < minimumVisibleTime) {
        await Future<void>.delayed(minimumVisibleTime - elapsed);
      }
    } catch (error) {
      if (mounted) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingCurrentConversation = false;
        });
      }
    }
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
      unawaited(ref.read(agentsProvider.notifier).ensureLoaded());
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _endOpeningBottomAnchor();
      _updateUserAwayFromBottom();
      return false;
    }
    if (notification is ScrollEndNotification) {
      _updateUserAwayFromBottom();
    }
    return false;
  }

  void _handleScrollPositionChanged() {
    if (_isProgrammaticScroll || !scrollController.hasClients) {
      return;
    }
    _updateUserAwayFromBottom();
  }

  void _updateUserAwayFromBottom() {
    if (!scrollController.hasClients) {
      return;
    }
    final away = !_isNearBottom();
    if (_userAwayFromBottom == away) {
      return;
    }
    _userAwayFromBottom = away;
    if (!away && _hasDeferredBottomNotice && mounted) {
      setState(() {
        _hasDeferredBottomNotice = false;
      });
      _acknowledgeCurrentVisibleConversationRead(reason: 'scroll_bottom');
    }
  }

  void _handleThreadChanged(
    ChatThreadState? previous,
    ChatThreadState next,
    ConversationSummary conversation,
  ) {
    if (_shouldUseOpeningBottomAnchor(previous, next)) {
      _scheduleOpeningBottomAnchorSettle(settleFrames: 3);
      return;
    }
    if (previous == null) {
      if (next.messages.isNotEmpty) {
        _scheduleScrollToBottom(settleFrames: 2);
      }
      return;
    }
    final previousLast = _lastMessage(previous.messages);
    final nextLast = _lastMessage(next.messages);
    final messageAdded =
        next.messages.length > previous.messages.length &&
        nextLast != null &&
        !_sameMessageIdentity(previousLast, nextLast);
    final pendingAdded =
        _activePendingTurnCount(next) > _activePendingTurnCount(previous);
    final recoveryAdded =
        next.messageAgentTimelineCount > previous.messageAgentTimelineCount;
    final wasNearBottom = !_userAwayFromBottom || _isNearBottom();
    if (messageAdded) {
      if (nextLast.isMine || wasNearBottom) {
        _scheduleScrollToBottom(animated: !nextLast.isMine);
      } else {
        _showDeferredBottomNotice();
      }
      return;
    }
    if (pendingAdded || recoveryAdded) {
      if (wasNearBottom || _latestMessageIsMine(next)) {
        _scheduleScrollToBottom(animated: true);
      } else {
        _showDeferredBottomNotice();
      }
      return;
    }
    final contentGrew =
        next.messages.length > previous.messages.length ||
        next.agentPendingTurns.length > previous.agentPendingTurns.length ||
        next.messageAgentTimelineCount > previous.messageAgentTimelineCount;
    if (contentGrew && wasNearBottom) {
      _scheduleScrollToBottom();
    }
  }

  void _showDeferredBottomNotice() {
    if (_hasDeferredBottomNotice || !mounted) {
      return;
    }
    setState(() {
      _hasDeferredBottomNotice = true;
    });
  }

  void _scheduleScrollToBottom({
    bool animated = false,
    int settleFrames = 1,
    bool forceJump = false,
  }) {
    _pendingScrollAnimated = forceJump
        ? false
        : _pendingScrollAnimated || animated;
    _pendingScrollSettleFrames = _pendingScrollSettleFrames > settleFrames
        ? _pendingScrollSettleFrames
        : settleFrames;
    if (_scrollToBottomScheduled) {
      return;
    }
    _scrollToBottomScheduled = true;
    final token = ++_scrollRequestToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runScheduledScrollToBottom(token);
    });
  }

  void _runScheduledScrollToBottom(int token) {
    if (!mounted || token != _scrollRequestToken) {
      return;
    }
    _scrollToBottom(animated: _pendingScrollAnimated, token: token);
    final remainingFrames = _pendingScrollSettleFrames - 1;
    if (remainingFrames <= 0) {
      _scrollToBottomScheduled = false;
      _pendingScrollAnimated = false;
      _pendingScrollSettleFrames = 1;
      return;
    }
    _pendingScrollAnimated = false;
    _pendingScrollSettleFrames = remainingFrames;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runScheduledScrollToBottom(token);
    });
  }

  void _cancelPendingScrollRequests() {
    _scrollRequestToken += 1;
    _scrollToBottomScheduled = false;
    _pendingScrollAnimated = false;
    _pendingScrollSettleFrames = 1;
    _isProgrammaticScroll = false;
  }

  void _beginOpeningBottomAnchor() {
    _scrollAnchorPhase = _ChatScrollAnchorPhase.opening;
    _openingAnchorObservedContent = false;
    _openingAnchorToken += 1;
    scrollController.prepareForInitialBottomPosition();
  }

  void _endOpeningBottomAnchor() {
    if (_scrollAnchorPhase == _ChatScrollAnchorPhase.active) {
      return;
    }
    _scrollAnchorPhase = _ChatScrollAnchorPhase.active;
    _openingAnchorToken += 1;
  }

  bool _shouldUseOpeningBottomAnchor(
    ChatThreadState? previous,
    ChatThreadState next,
  ) {
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.opening ||
        _userAwayFromBottom ||
        !_threadHasBottomAnchorContent(next)) {
      return false;
    }
    if (previous == null) {
      return true;
    }
    return next.messages.length != previous.messages.length ||
        _activePendingTurnCount(next) != _activePendingTurnCount(previous) ||
        next.messageAgentTimelineCount != previous.messageAgentTimelineCount;
  }

  void _settleOpeningBottomAnchorForCurrentThread(ChatThreadState thread) {
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.opening ||
        _openingAnchorObservedContent ||
        _userAwayFromBottom) {
      return;
    }
    if (_threadHasBottomAnchorContent(thread)) {
      _scheduleOpeningBottomAnchorSettle(settleFrames: 3);
    }
  }

  bool _threadHasBottomAnchorContent(ChatThreadState thread) {
    return thread.messages.isNotEmpty ||
        _activePendingTurnCount(thread) > 0 ||
        thread.messageAgentTimelineCount > 0;
  }

  void _scheduleOpeningBottomAnchorSettle({required int settleFrames}) {
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.opening) {
      return;
    }
    _openingAnchorObservedContent = true;
    scrollController.prepareForInitialBottomPosition();
    _scheduleScrollToBottom(settleFrames: settleFrames, forceJump: true);
    _scheduleOpeningBottomAnchorEnd(afterFrames: settleFrames + 1);
  }

  void _scheduleOpeningBottomAnchorEnd({required int afterFrames}) {
    final token = ++_openingAnchorToken;
    void schedule(int remainingFrames) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            token != _openingAnchorToken ||
            _scrollAnchorPhase != _ChatScrollAnchorPhase.opening) {
          return;
        }
        if (remainingFrames <= 0) {
          _scrollAnchorPhase = _ChatScrollAnchorPhase.active;
          return;
        }
        schedule(remainingFrames - 1);
      });
    }

    schedule(afterFrames);
  }

  void _scrollToBottom({bool animated = false, required int token}) {
    if (!scrollController.hasClients) {
      return;
    }
    final target = scrollController.position.maxScrollExtent;
    _isProgrammaticScroll = true;
    if (animated) {
      scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted || token != _scrollRequestToken) {
              return;
            }
            _isProgrammaticScroll = false;
            _markAtBottomAfterProgrammaticScroll();
          });
      return;
    }
    scrollController.jumpTo(target);
    _isProgrammaticScroll = false;
    _markAtBottomAfterProgrammaticScroll();
  }

  void _markAtBottomAfterProgrammaticScroll() {
    _userAwayFromBottom = false;
    if (_hasDeferredBottomNotice && mounted) {
      setState(() {
        _hasDeferredBottomNotice = false;
      });
    }
    _acknowledgeCurrentVisibleConversationRead(reason: 'programmatic_bottom');
  }

  bool _isNearBottom() {
    if (!scrollController.hasClients) {
      return true;
    }
    final position = scrollController.position;
    return position.maxScrollExtent - position.pixels <= _nearBottomExtent;
  }

  ChatMessage? _lastMessage(List<ChatMessage> messages) {
    return messages.isEmpty ? null : messages.last;
  }

  bool _latestMessageIsMine(ChatThreadState thread) {
    final latest = _lastMessage(thread.messages);
    return latest?.isMine == true;
  }

  bool _sameMessageIdentity(ChatMessage? a, ChatMessage? b) {
    if (a == null || b == null) {
      return a == b;
    }
    final aId = a.remoteId ?? a.localId;
    final bId = b.remoteId ?? b.localId;
    return aId == bId;
  }

  int _activePendingTurnCount(ChatThreadState thread) {
    return thread.agentPendingTurns.where((turn) => turn.isActive).length;
  }

  List<_MessageAgentTimelineItem> _messageAgentTimelineItems(
    ChatThreadState thread,
  ) {
    return <_MessageAgentTimelineItem>[
      for (final sync in thread.messageAgentSyncs)
        _MessageAgentSyncTimelineItem(sync),
      for (final action in thread.appActionRecords.values)
        _MessageAgentActionTimelineItem(action),
    ];
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
    required bool isLastItem,
  }) {
    if (isLastItem) {
      return 0;
    }
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
    return localRuntimeAgentForConversationTarget(targetDid, agents);
  }

  String? _expectedAgentReplyDidForConversation(
    ConversationSummary conversation, {
    required AgentSummary? runtimeAgent,
    required ConversationPeerClassification classification,
  }) {
    if (conversation.isGroup) {
      return null;
    }
    final localRuntimeDid = runtimeAgent?.agentDid.trim();
    if (localRuntimeDid != null && localRuntimeDid.isNotEmpty) {
      return localRuntimeDid;
    }
    final targetDid = conversation.targetDid?.trim();
    if (targetDid == null || targetDid.isEmpty) {
      return null;
    }
    if (!classification.isAgent &&
        !conversationTargetDidLooksLikeAgent(targetDid)) {
      return null;
    }
    return targetDid;
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

  String _agentProcessingLabel(List<AgentPendingTurn> turns) {
    if (turns.isEmpty) {
      return '智能体正在处理...';
    }
    final overdue = turns.any((turn) => turn.isOverdue);
    final subject = _agentProcessingSubject(turns);
    if (subject == '智能体') {
      return overdue ? '智能体仍在处理，稍后可刷新查看' : '智能体正在处理...';
    }
    return overdue ? '$subject 仍在处理，稍后可刷新查看' : '$subject 正在处理...';
  }

  String _agentProcessingSubject(List<AgentPendingTurn> turns) {
    final handles = <String>[];
    final seenHandles = <String>{};
    for (final turn in turns) {
      final handle = turn.agentHandle?.trim();
      if (handle == null || handle.isEmpty || !seenHandles.add(handle)) {
        continue;
      }
      handles.add(handle);
    }
    if (handles.isEmpty) {
      return '智能体';
    }
    if (handles.length <= 2) {
      return handles.map((handle) => '@$handle').join('、');
    }
    return '${handles.length} 个智能体';
  }
}
