import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;
import 'package:flutter/rendering.dart' show RenderBox, ScrollDirection;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_router.dart';
import '../../app/e2e_semantics.dart';
import '../../app/app_services.dart';
import '../../application/attachment_preview_service.dart';
import '../../application/attachment_resource_reference.dart';
import '../../application/models/attachment_models.dart';
import '../../core/group_display_name.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../agents/agent_inbox_panel.dart';
import '../agents/agent_rename_dialog.dart';
import '../agents/agent_runtime_display.dart';
import '../agents/agent_visual_status.dart';
import '../agents/agents_provider.dart';
import '../../domain/entities/agent/agent_control_payloads.dart';
import '../app_shell/providers/session_provider.dart';
import '../conversation_list/conversation_peer_classifier.dart';
import '../conversation_list/conversation_provider.dart';
import '../friends/friends_page.dart';
import '../friends/friends_provider.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_provider.dart';
import '../profile/peer_display_profile_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/app_dialog.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/formatters/localized_ui_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/semantic_pill.dart';
import '../shared/widgets/app_widgets.dart';
import 'chat_provider.dart';

part 'parts/chat_header_part.dart';
part 'parts/chat_peer_info_part.dart';
part 'parts/chat_message_part.dart';
part 'parts/chat_composer_part.dart';

const _chatMessageListBottomInset = 12.0;
const _macChatMessageListBottomInset = 4.0;
const _chatBottomTolerance = 0.5;

typedef ChatImageWidgetBuilder =
    Widget Function({
      String? path,
      Uint8List? bytes,
      double? width,
      double? height,
      required BoxFit fit,
      required Widget errorFallback,
      Widget? framePlaceholder,
    });

final chatImageWidgetBuilderProvider = Provider<ChatImageWidgetBuilder>((ref) {
  return ({
    String? path,
    Uint8List? bytes,
    double? width,
    double? height,
    required BoxFit fit,
    required Widget errorFallback,
    Widget? framePlaceholder,
  }) {
    final cacheWidth = ((width ?? 480) * 3).ceil().clamp(64, 1440);
    Widget buildFrame(
      BuildContext context,
      Widget child,
      int? frame,
      bool wasSynchronouslyLoaded,
    ) {
      if (frame == null &&
          !wasSynchronouslyLoaded &&
          framePlaceholder != null) {
        return framePlaceholder;
      }
      return child;
    }

    if (bytes != null) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        fit: fit,
        frameBuilder: framePlaceholder == null ? null : buildFrame,
        errorBuilder: (_, _, _) => errorFallback,
      );
    }
    final value = path?.trim();
    if (value == null || value.isEmpty) {
      return errorFallback;
    }
    final reference = AttachmentResourceReference.parse(value);
    if (!reference.isLocalFile) {
      return errorFallback;
    }
    return Image.file(
      File(reference.localPath!),
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      fit: fit,
      frameBuilder: framePlaceholder == null ? null : buildFrame,
      errorBuilder: (_, _, _) => errorFallback,
    );
  };
});

class ChatPage extends StatelessWidget {
  const ChatPage({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: ChatView(
        key: ValueKey('chat-view:${conversation.conversationId}'),
        conversation: conversation,
        embedded: false,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _AttachmentDropOverlay extends StatelessWidget {
  const _AttachmentDropOverlay({required this.macStyle});

  final bool macStyle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final radius = macStyle
        ? responsive.displayScaled(18)
        : responsive.radius(24);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x330B65F8),
          border: Border.all(
            color: const Color(0xFF0B65F8),
            width: macStyle ? 1.4 : 1.8,
          ),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Center(
          child: Container(
            key: const Key('chat-attachment-drop-overlay'),
            padding: EdgeInsets.symmetric(
              horizontal: macStyle
                  ? responsive.displayScaled(18)
                  : responsive.spacing(18),
              vertical: macStyle
                  ? responsive.displayScaled(12)
                  : responsive.spacing(12),
            ),
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(
                macStyle ? responsive.displayScaled(14) : responsive.radius(18),
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x240B1F3A),
                  blurRadius: 28,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  CupertinoIcons.paperclip,
                  color: const Color(0xFF0B65F8),
                  size: macStyle
                      ? responsive.displayScaled(20)
                      : responsive.iconMd,
                ),
                SizedBox(
                  width: macStyle
                      ? responsive.displayScaled(8)
                      : responsive.spacing(8),
                ),
                Text(
                  context.l10n.chatAddAttachment,
                  style: TextStyle(
                    color: const Color(0xFF17213A),
                    fontWeight: FontWeight.w700,
                    fontSize: macStyle
                        ? responsive.displayScaled(14)
                        : responsive.bodyMd,
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

String _timelineDisplayThreadId(ConversationSummary conversation) {
  return conversation.conversationId;
}

bool _sameCanonicalConversation(
  ConversationSummary first,
  ConversationSummary second,
) {
  return first.conversationId == second.conversationId;
}

class ChatView extends ConsumerStatefulWidget {
  const ChatView({
    super.key,
    required this.conversation,
    required this.embedded,
    this.onBack,
    this.macStyle = false,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final bool macStyle;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

enum _ChatScrollAnchorPhase {
  opening,
  followingTail,
  readingAnchor,
  programmaticTail,
}

enum _ChatTimelineEntryKind {
  message,
  unmatchedPendingTurn,
  messageAgentRecovery,
  tail,
}

class _ChatTimelineEntry {
  const _ChatTimelineEntry({
    required this.id,
    required this.kind,
    required this.sourceIndex,
  });

  final String id;
  final _ChatTimelineEntryKind kind;
  final int sourceIndex;
}

class _ChatViewportAnchor {
  const _ChatViewportAnchor({
    required this.entryId,
    required this.viewportOffset,
  });

  final String entryId;
  final double viewportOffset;

  _ChatViewportAnchor shiftedBy(double scrollDelta) {
    return _ChatViewportAnchor(
      entryId: entryId,
      viewportOffset: viewportOffset - scrollDelta,
    );
  }
}

class _ChatTimelineGeometry {
  const _ChatTimelineGeometry({
    required this.top,
    required this.bottom,
    required this.viewportExtent,
  });

  final double top;
  final double bottom;
  final double viewportExtent;

  bool get intersectsViewport => bottom > 0 && top < viewportExtent;
}

class _ChatLayoutCorrection {
  const _ChatLayoutCorrection(
    this.delta, {
    this.ownsOutOfRangePosition = false,
  });

  final double delta;
  final bool ownsOutOfRangePosition;
}

typedef _ChatLayoutCorrectionResolver =
    _ChatLayoutCorrection? Function(
      double minScrollExtent,
      double maxScrollExtent,
    );

class _ChatTimelineScrollController extends ScrollController {
  _ChatTimelineScrollController({
    required VoidCallback onUserScrollStart,
    required ValueChanged<double> onScrollDelta,
    required _ChatLayoutCorrectionResolver resolveLayoutCorrection,
  }) : _onUserScrollStart = onUserScrollStart,
       _onScrollDelta = onScrollDelta,
       _resolveLayoutCorrection = resolveLayoutCorrection,
       super(keepScrollOffset: false, debugLabel: 'ChatView.messages');

  final VoidCallback _onUserScrollStart;
  final ValueChanged<double> _onScrollDelta;
  final _ChatLayoutCorrectionResolver _resolveLayoutCorrection;

  void jumpToTimelineTarget(double value) {
    assert(hasClients, 'Chat timeline scroll controller is not attached.');
    for (final position in List<ScrollPosition>.of(positions)) {
      if (position is _ChatTimelineScrollPosition) {
        position.jumpToTimelineTarget(value);
      } else {
        position.jumpTo(value);
      }
    }
  }

  Future<void> animateToTimelineTarget(
    double value, {
    required Duration duration,
    required Curve curve,
  }) async {
    assert(hasClients, 'Chat timeline scroll controller is not attached.');
    await Future.wait<void>(<Future<void>>[
      for (final position in List<ScrollPosition>.of(positions))
        if (position is _ChatTimelineScrollPosition)
          position.animateToTimelineTarget(
            value,
            duration: duration,
            curve: curve,
          )
        else
          position.animateTo(value, duration: duration, curve: curve),
    ]);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ChatTimelineScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      onUserScrollStart: _onUserScrollStart,
      onScrollDelta: _onScrollDelta,
      resolveLayoutCorrection: _resolveLayoutCorrection,
    );
  }
}

class _ChatTimelineScrollPosition extends ScrollPositionWithSingleContext {
  _ChatTimelineScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    super.debugLabel,
    required VoidCallback onUserScrollStart,
    required ValueChanged<double> onScrollDelta,
    required _ChatLayoutCorrectionResolver resolveLayoutCorrection,
  }) : _onUserScrollStart = onUserScrollStart,
       _onScrollDelta = onScrollDelta,
       _resolveLayoutCorrection = resolveLayoutCorrection,
       super(initialPixels: 0, keepScrollOffset: false);

  final VoidCallback _onUserScrollStart;
  final ValueChanged<double> _onScrollDelta;
  final _ChatLayoutCorrectionResolver _resolveLayoutCorrection;
  int _timelineProgrammaticDepth = 0;

  bool get _isTimelineProgrammatic => _timelineProgrammaticDepth > 0;

  T _runTimelineProgrammatic<T>(T Function() action) {
    _timelineProgrammaticDepth += 1;
    try {
      return action();
    } finally {
      _timelineProgrammaticDepth -= 1;
    }
  }

  void jumpToTimelineTarget(double value) {
    _runTimelineProgrammatic<void>(() => jumpTo(value));
  }

  Future<void> animateToTimelineTarget(
    double value, {
    required Duration duration,
    required Curve curve,
  }) {
    return _runTimelineProgrammatic<Future<void>>(
      () => animateTo(value, duration: duration, curve: curve),
    );
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (hasPixels) {
      final correction = _resolveLayoutCorrection(
        minScrollExtent,
        maxScrollExtent,
      );
      if (correction != null &&
          (correction.ownsOutOfRangePosition ||
              !_isOutsideCurrentOrIncomingRange(
                minScrollExtent,
                maxScrollExtent,
              )) &&
          _applyResolvedLayoutCorrection(
            correction,
            minScrollExtent,
            maxScrollExtent,
          )) {
        return false;
      }
    }
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    return accepted;
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    final correction = _resolveLayoutCorrection(
      newPosition.minScrollExtent,
      newPosition.maxScrollExtent,
    );
    if (correction?.ownsOutOfRangePosition != true &&
        (_isOutsideRange(oldPosition) || _isOutsideRange(newPosition))) {
      // Preserve BouncingScrollPhysics overscroll and let the default
      // RangeMaintainingScrollPhysics compose changes to the content bounds.
      return super.correctForNewDimensions(oldPosition, newPosition);
    }
    if (correction != null) {
      final target = (pixels + correction.delta)
          .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent)
          .toDouble();
      if ((target - pixels).abs() > _chatBottomTolerance) {
        correctPixels(target);
        return false;
      }
      // The timeline owns dimension changes while following its tail or a
      // reading anchor. Default pixel-based corrections would move that
      // content anchor when a variable-height entry relayouts.
      return true;
    }
    return super.correctForNewDimensions(oldPosition, newPosition);
  }

  bool _isOutsideCurrentOrIncomingRange(
    double minScrollExtent,
    double maxScrollExtent,
  ) {
    final outsideIncoming =
        pixels < minScrollExtent - _chatBottomTolerance ||
        pixels > maxScrollExtent + _chatBottomTolerance;
    if (outsideIncoming || !haveDimensions) {
      return outsideIncoming;
    }
    return pixels < this.minScrollExtent - _chatBottomTolerance ||
        pixels > this.maxScrollExtent + _chatBottomTolerance;
  }

  bool _isOutsideRange(ScrollMetrics metrics) {
    return metrics.pixels < metrics.minScrollExtent - _chatBottomTolerance ||
        metrics.pixels > metrics.maxScrollExtent + _chatBottomTolerance;
  }

  bool _applyResolvedLayoutCorrection(
    _ChatLayoutCorrection correction,
    double minScrollExtent,
    double maxScrollExtent,
  ) {
    final target = (pixels + correction.delta)
        .clamp(minScrollExtent, maxScrollExtent)
        .toDouble();
    if ((target - pixels).abs() > _chatBottomTolerance) {
      correctPixels(target);
      return true;
    }
    return false;
  }

  void _reportScrollDelta(double before) {
    if (!hasPixels) {
      return;
    }
    final delta = pixels - before;
    if (delta.abs() > _chatBottomTolerance) {
      _onScrollDelta(delta);
    }
  }

  @override
  double setPixels(double newPixels) {
    final before = pixels;
    final overscroll = super.setPixels(newPixels);
    _reportScrollDelta(before);
    return overscroll;
  }

  @override
  void jumpTo(double value) {
    final externalTakeover =
        !_isTimelineProgrammatic &&
        ((value - pixels).abs() > _chatBottomTolerance ||
            isScrollingNotifier.value);
    if (!externalTakeover) {
      super.jumpTo(value);
      return;
    }
    _onUserScrollStart();
    final before = pixels;
    super.jumpTo(value);
    _reportScrollDelta(before);
  }

  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    if (!_isTimelineProgrammatic &&
        ((to - pixels).abs() > _chatBottomTolerance ||
            isScrollingNotifier.value)) {
      _onUserScrollStart();
    }
    return super.animateTo(to, duration: duration, curve: curve);
  }

  @override
  void applyUserOffset(double delta) {
    if (delta != 0) {
      _onUserScrollStart();
    }
    super.applyUserOffset(delta);
  }

  @override
  void pointerScroll(double delta) {
    if (delta == 0) {
      if (!_isTimelineProgrammatic && isScrollingNotifier.value) {
        _onUserScrollStart();
      }
      super.pointerScroll(delta);
      return;
    }
    final canMove =
        (delta < 0 && pixels > minScrollExtent) ||
        (delta > 0 && pixels < maxScrollExtent);
    if (canMove) {
      _onUserScrollStart();
    }
    final before = pixels;
    super.pointerScroll(delta);
    _reportScrollDelta(before);
  }
}

class _ChatViewState extends ConsumerState<ChatView> {
  final textController = TextEditingController();
  final GlobalKey _messageListViewportKey = GlobalKey(
    debugLabel: 'ChatView.messageViewport',
  );
  final Map<String, GlobalKey> _timelineMeasurementKeys = <String, GlobalKey>{};
  late final _ChatTimelineScrollController scrollController;
  late final ChatThreadsController _chatThreadsController;
  ProviderSubscription<ConversationListState>? _conversationListSubscription;
  late String _displayThreadId;
  AttachmentDraft? _pendingAttachment;
  bool _isApplyingComposerDraft = false;
  bool _didRequestAgents = false;
  bool _hasDeferredBottomNotice = false;
  bool _userAwayFromBottom = false;
  bool _isProgrammaticScroll = false;
  bool _programmaticTailCorrectionArmed = false;
  bool _scrollToBottomScheduled = false;
  bool _readingAnchorRefreshScheduled = false;
  int _scrollRequestToken = 0;
  int _scrollEndCheckToken = 0;
  int _visibleReadAckToken = 0;
  int _composerFocusRequestId = 0;
  bool _pendingScrollAnimated = false;
  int _pendingScrollSettleFrames = 1;
  _ChatScrollAnchorPhase _scrollAnchorPhase = _ChatScrollAnchorPhase.opening;
  List<_ChatViewportAnchor> _readingAnchors = const <_ChatViewportAnchor>[];
  List<String> _activeTimelineEntryIds = const <String>[];
  String? _activeTimelineTailId;
  double _activeTimelineBottomInset = 0;
  bool _openingAnchorObservedContent = false;
  int _openingAnchorToken = 0;
  bool _isOpeningGroupInvite = false;
  bool _isDraggingExternalAttachment = false;
  final Set<String> _requestedGroupRoleIds = <String>{};
  final Set<String> _downloadingAttachmentMessageIds = <String>{};
  static const double _nearBottomExtent = 96;

  @override
  void initState() {
    super.initState();
    _displayThreadId = _timelineDisplayThreadId(widget.conversation);
    scrollController = _ChatTimelineScrollController(
      onUserScrollStart: _handleUserScrollStart,
      onScrollDelta: _handleScrollDelta,
      resolveLayoutCorrection: _resolveLayoutCorrection,
    );
    _chatThreadsController = ref.read(chatThreadsProvider.notifier);
    _conversationListSubscription = ref.listenManual<ConversationListState>(
      conversationListProvider,
      (_, next) => _handleConversationListChanged(next),
    );
    _beginOpeningBottomAnchor();
    _scheduleConversationVisible(
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
    _conversationListSubscription?.close();
    textController.removeListener(_persistComposerText);
    scrollController.removeListener(_handleScrollPositionChanged);
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameCanonicalConversation(
      oldWidget.conversation,
      widget.conversation,
    )) {
      _composerFocusRequestId += 1;
      _visibleReadAckToken += 1;
      _markConversationHidden(
        oldWidget.conversation,
        displayThreadId: _displayThreadId,
      );
      _displayThreadId = _timelineDisplayThreadId(widget.conversation);
      _scheduleConversationVisible(
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
      displayThreadId:
          displayThreadId ?? _timelineDisplayThreadId(conversation),
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
      displayThreadId:
          displayThreadId ?? _timelineDisplayThreadId(conversation),
    );
  }

  void _scheduleConversationVisible(
    ConversationSummary conversation, {
    required String displayThreadId,
  }) {
    final token = _visibleReadAckToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _visibleReadAckToken ||
          displayThreadId != _displayThreadId ||
          !_sameCanonicalConversation(
            conversation,
            _currentConversationSnapshot(),
          )) {
        return;
      }
      _markConversationVisible(conversation, displayThreadId: displayThreadId);
    });
  }

  void _acknowledgeVisibleConversationRead(
    ConversationSummary conversation, {
    String reason = 'visible',
    bool forcePersistentAck = false,
  }) {
    _chatThreadsController.acknowledgeVisibleConversationRead(
      conversation,
      displayThreadId: _displayThreadId,
      reason: reason,
      forcePersistentAck: forcePersistentAck,
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
          !_sameCanonicalConversation(
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
    bool forcePersistentAck = false,
  }) {
    if (_hasDeferredBottomNotice && !_isNearBottom()) {
      return;
    }
    _acknowledgeVisibleConversationRead(
      _currentConversationSnapshot(),
      reason: reason,
      forcePersistentAck: forcePersistentAck,
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
    final macStyle = widget.macStyle && responsive.usesDesktopLayout;
    final messageListBottomInset = macStyle
        ? responsive.displayScaled(_macChatMessageListBottomInset)
        : responsive.spacing(_chatMessageListBottomInset);
    final displayThreadId = _displayThreadId;
    final thread = ref.watch(chatThreadProvider(displayThreadId));
    final currentConversation = _currentConversationForTitle();
    final headerNickname = _headerNickname(currentConversation);
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
    final canAcceptExternalAttachment =
        !isDeletedAgentConversation && groupSendDisabledReason == null;
    final inviteTarget = _groupInviteTarget(
      currentConversation,
      ref.watch(groupProvider).groups,
    );
    final canInviteGroupMembers =
        inviteTarget != null && canManageGroupMembers(inviteTarget);
    _requestGroupRoleIfNeeded(currentConversation);
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
    final messages = thread.messages;
    final deferRealtimeTailFirstPaint =
        thread.isHydratingLocalHistory && messages.length <= 1;
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
    final timelineEntries = <_ChatTimelineEntry>[
      for (var index = 0; index < messages.length; index += 1)
        _ChatTimelineEntry(
          id: _messageTimelineEntryId(messages[index]),
          kind: _ChatTimelineEntryKind.message,
          sourceIndex: index,
        ),
      for (var index = 0; index < unmatchedPendingTurns.length; index += 1)
        _ChatTimelineEntry(
          id: _pendingTurnTimelineEntryId(unmatchedPendingTurns[index]),
          kind: _ChatTimelineEntryKind.unmatchedPendingTurn,
          sourceIndex: index,
        ),
      for (var index = 0; index < messageAgentItems.length; index += 1)
        _ChatTimelineEntry(
          id: _messageAgentTimelineEntryId(messageAgentItems[index]),
          kind: _ChatTimelineEntryKind.messageAgentRecovery,
          sourceIndex: index,
        ),
      _ChatTimelineEntry(
        id: _scopedTimelineEntryId('tail'),
        kind: _ChatTimelineEntryKind.tail,
        sourceIndex: -1,
      ),
    ];
    final messageListItemCount = timelineEntries.length - 1;
    _updateActiveTimeline(timelineEntries, bottomInset: messageListBottomInset);
    final timelineChildIndices = <Key, int>{
      for (var index = 0; index < timelineEntries.length; index += 1)
        _timelineChildKey(timelineEntries[index].id): index,
    };
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
            nickname: headerNickname,
            embedded: widget.embedded,
            macStyle: macStyle,
            classification: peerClassification,
            isDeletedAgentConversation: isDeletedAgentConversation,
            onBack: widget.onBack,
            onPeerInfoTap: _openDetails,
            onAddGroupMemberTap: canInviteGroupMembers
                ? () => _openGroupInviteDialog(currentConversation)
                : null,
            isAddGroupMemberLoading: _isOpeningGroupInvite,
          ),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _acknowledgeCurrentVisibleConversationRead(
                reason: 'visible_pointer',
              ),
              child: Stack(
                children: <Widget>[
                  SizedBox.expand(
                    key: _messageListViewportKey,
                    child: NotificationListener<ScrollNotification>(
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
                        itemCount: timelineEntries.length,
                        findChildIndexCallback: (key) =>
                            timelineChildIndices[key],
                        itemBuilder: (_, index) {
                          final entry = timelineEntries[index];
                          if (entry.kind == _ChatTimelineEntryKind.tail) {
                            return _buildTimelineChild(
                              entry.id,
                              const SizedBox(
                                key: Key('chat-timeline-tail'),
                                width: double.infinity,
                              ),
                            );
                          }
                          final isLastItem = index == messageListItemCount - 1;
                          if (entry.kind ==
                              _ChatTimelineEntryKind.messageAgentRecovery) {
                            final item = messageAgentItems[entry.sourceIndex];
                            return _buildTimelineChild(
                              entry.id,
                              Padding(
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
                                              .read(
                                                chatThreadsProvider.notifier,
                                              )
                                              .confirmAppAction(
                                                conversation:
                                                    currentConversation,
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
                              ),
                            );
                          }
                          if (entry.kind ==
                              _ChatTimelineEntryKind.unmatchedPendingTurn) {
                            final turn =
                                unmatchedPendingTurns[entry.sourceIndex];
                            return _buildTimelineChild(
                              entry.id,
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: isLastItem
                                      ? 0
                                      : macStyle
                                      ? responsive.displayScaled(16)
                                      : responsive.spacing(24),
                                ),
                                child: _AgentProcessingIndicator(
                                  label: _agentProcessingLabel(
                                    context,
                                    <AgentPendingTurn>[turn],
                                  ),
                                  avatarSeed: _agentProcessingAvatarSeed(
                                    context,
                                    runtimeAgent,
                                    currentConversation,
                                  ),
                                  macStyle: macStyle,
                                ),
                              ),
                            );
                          }
                          final messageIndex = entry.sourceIndex;
                          final message = messages[messageIndex];
                          final pendingTurns = thread
                              .pendingAgentTurnsForMessage(message);
                          final previous = messageIndex == 0
                              ? null
                              : messages[messageIndex - 1];
                          final next = messageIndex + 1 < messages.length
                              ? messages[messageIndex + 1]
                              : null;
                          final senderLabel = _displayNameForMessage(
                            context,
                            message,
                          );
                          final senderAvatarUri = message.isMine
                              ? null
                              : peerAvatarUri(
                                  ref.watch(peerDisplayProfileProvider),
                                  message.senderDid,
                                  peerPersonaId: message.senderPeerPersonaId,
                                );
                          final showSenderLabel = _shouldShowSenderLabel(
                            previous,
                            message,
                          );
                          return _buildTimelineChild(
                            entry.id,
                            Padding(
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
                                key: Key(
                                  'chat-message-content:${message.localId}',
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
                                    if (message.isGroupSystemEvent)
                                      _GroupSystemEventNotice(
                                        message: message,
                                        macStyle: macStyle,
                                      )
                                    else
                                      _MessageBubble(
                                        message: message,
                                        senderLabel: senderLabel,
                                        senderAvatarUri: senderAvatarUri,
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
                                        onResolveImagePreview:
                                            message.attachment != null &&
                                                message.sendState ==
                                                    MessageSendState.sent
                                            ? () => _resolveAttachmentPreview(
                                                currentConversation,
                                                message,
                                              )
                                            : null,
                                        isDownloading:
                                            _downloadingAttachmentMessageIds
                                                .contains(message.localId),
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
                                        label: _agentProcessingLabel(
                                          context,
                                          pendingTurns,
                                        ),
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
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_hasDeferredBottomNotice)
                    _NewMessagesButton(
                      macStyle: macStyle,
                      onTap: () => _scheduleScrollToBottom(animated: true),
                    ),
                  if (deferRealtimeTailFirstPaint)
                    const Positioned.fill(
                      child: ColoredBox(
                        key: Key('chat-local-history-hydrating-mask'),
                        color: CupertinoColors.white,
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
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
            focusRequestId: _composerFocusRequestId,
            enabled:
                !isDeletedAgentConversation && groupSendDisabledReason == null,
            disabledReason: isDeletedAgentConversation
                ? context.l10n.chatDeletedAgentDisabled
                : groupSendDisabledReason,
            onSend: () => _submitComposer(
              currentConversation,
              classification: peerClassification,
            ),
            onAttach: () async {
              await _pickAndStageAttachment();
            },
            onScreenshot: _captureAndStageScreenshot,
            onPasteAttachment: _pasteClipboardAttachment,
            onRemoveAttachment: _clearPendingAttachment,
          ),
        ],
      ),
    );
    final pageWithDropTarget = _buildAttachmentDropTarget(
      page,
      enabled: canAcceptExternalAttachment,
      macStyle: macStyle,
    );
    if (macStyle) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: CupertinoColors.white),
        child: pageWithDropTarget,
      );
    }
    return AwikiMeWidgets.pageBackground(child: pageWithDropTarget);
  }

  Widget _buildAttachmentDropTarget(
    Widget child, {
    required bool enabled,
    required bool macStyle,
  }) {
    return DropTarget(
      key: Key('chat-attachment-drop-target:$_displayThreadId'),
      enable: enabled,
      onDragEntered: (_) {
        if (!mounted || !enabled || _isDraggingExternalAttachment) {
          return;
        }
        setState(() => _isDraggingExternalAttachment = true);
      },
      onDragExited: (_) {
        if (!mounted || !_isDraggingExternalAttachment) {
          return;
        }
        setState(() => _isDraggingExternalAttachment = false);
      },
      onDragDone: (details) => unawaited(_handleDroppedAttachments(details)),
      child: Stack(
        children: <Widget>[
          child,
          if (_isDraggingExternalAttachment && enabled)
            Positioned.fill(child: _AttachmentDropOverlay(macStyle: macStyle)),
        ],
      ),
    );
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
    if (conversation.isGroup) {
      await _showGroupInfoDialog(conversation);
    }
  }

  Future<void> _showPeerInfoDialog(ConversationSummary conversation) async {
    await AppNavigator.showDialog<void>(
      context,
      (dialogContext) => _PeerInfoDialog(
        target: _PeerInfoTarget.fromConversation(conversation),
      ),
    );
  }

  Future<void> _showGroupInfoDialog(ConversationSummary conversation) async {
    final displayThreadId = _displayThreadId;
    await AppNavigator.showDialog<void>(
      context,
      (dialogContext) => _GroupInfoDialog(
        initialGroup: _groupSummaryForConversation(conversation),
        onGroupUpdated: (updated) => _refreshGroupLocalProjection(
          conversation,
          updated,
          displayThreadId: displayThreadId,
        ),
      ),
    );
  }

  void _refreshGroupLocalProjection(
    ConversationSummary conversation,
    GroupSummary updated, {
    required String displayThreadId,
  }) {
    if (!mounted) {
      return;
    }
    final refreshedConversation = conversation.copyWith(
      groupId: updated.groupId,
    );
    unawaited(
      _chatThreadsController.refreshLocalProjectionForConversation(
        refreshedConversation,
        displayThreadId: displayThreadId,
        force: true,
      ),
    );
  }

  Future<void> _openGroupInviteDialog(ConversationSummary conversation) async {
    final displayThreadId = _displayThreadId;
    final group = _groupInviteTarget(
      conversation,
      ref.read(groupProvider).groups,
    );
    if (group == null || !canManageGroupMembers(group)) {
      return;
    }
    if (_isOpeningGroupInvite) {
      return;
    }
    setState(() => _isOpeningGroupInvite = true);
    try {
      final members = ref.read(groupMembersProvider(group.groupId));
      unawaited(_refreshGroupInviteSnapshot(group.groupId));
      await AppNavigator.showDialog<void>(
        context,
        (dialogContext) => AddGroupMemberDialog(
          groupId: group.groupId,
          existingMembers: members,
          onGroupUpdated: (updated) {
            if (!mounted) {
              return;
            }
            ref.read(groupProvider.notifier).upsertGroup(updated);
            _refreshGroupLocalProjection(
              conversation,
              updated,
              displayThreadId: displayThreadId,
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (mounted) {
        setState(() => _isOpeningGroupInvite = false);
      }
    }
  }

  Future<void> _refreshGroupInviteSnapshot(String groupId) async {
    try {
      await ref.read(groupProvider.notifier).refreshGroup(groupId);
    } catch (_) {
      AwikiPerformanceLogger.log(
        'chat.group_invite.background_refresh.error',
        fields: <String, Object?>{
          'group_hash': AwikiPerformanceLogger.safeHash(groupId),
        },
      );
    }
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
    final target = conversation.isGroup
        ? _PeerInfoTarget(
            targetDid: targetDid,
            displayName: senderLabel,
            peerPersonaId: message.senderPeerPersonaId,
          )
        : _PeerInfoTarget.fromConversation(conversation);
    return () => AppNavigator.showDialog<void>(
      context,
      (dialogContext) => _PeerInfoDialog(target: target),
    );
  }

  Future<void> _pickAndStageAttachment() async {
    final conversation = _currentConversationSnapshot();
    if (!_canAcceptExternalAttachment(conversation)) {
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
      _stageAttachmentDraft(conversation, draft);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  Future<void> _captureAndStageScreenshot({required bool hideApp}) async {
    final conversation = _currentConversationSnapshot();
    if (!_canAcceptExternalAttachment(conversation)) {
      return;
    }
    try {
      final draft = await ref
          .read(attachmentPickerServiceProvider)
          .captureScreenshot(hideApp: hideApp);
      if (draft == null || !mounted) {
        return;
      }
      _stageAttachmentDraft(conversation, draft);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  Future<bool> _pasteClipboardAttachment() async {
    final conversation = _currentConversationSnapshot();
    if (!_canAcceptExternalAttachment(conversation)) {
      return false;
    }
    try {
      final draft = await ref
          .read(attachmentPickerServiceProvider)
          .readClipboardAttachment();
      if (draft == null) {
        return false;
      }
      if (!mounted ||
          !_sameCanonicalConversation(
            conversation,
            _currentConversationSnapshot(),
          )) {
        return true;
      }
      _stageAttachmentDraft(conversation, draft);
      return true;
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
      return true;
    }
  }

  Future<void> _handleDroppedAttachments(DropDoneDetails details) async {
    if (mounted && _isDraggingExternalAttachment) {
      setState(() => _isDraggingExternalAttachment = false);
    }
    final conversation = _currentConversationSnapshot();
    if (!_canAcceptExternalAttachment(conversation)) {
      return;
    }
    final item = _firstDroppedFile(details.files);
    if (item == null) {
      return;
    }
    try {
      final draft = await _draftFromDroppedItem(item);
      if (draft == null ||
          !mounted ||
          !_sameCanonicalConversation(
            conversation,
            _currentConversationSnapshot(),
          )) {
        return;
      }
      _stageAttachmentDraft(conversation, draft);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }

  DropItem? _firstDroppedFile(List<DropItem> items) {
    for (final item in items) {
      if (item is DropItemDirectory) {
        continue;
      }
      return item;
    }
    return null;
  }

  Future<AttachmentDraft?> _draftFromDroppedItem(DropItem item) async {
    final bookmark = item.extraAppleBookmark;
    var didAccessSecurityScopedResource = false;
    try {
      if (bookmark != null && bookmark.isNotEmpty) {
        didAccessSecurityScopedResource = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      final path = item.path.trim();
      Uint8List? bytes;
      if (path.isEmpty) {
        bytes = await item.readAsBytes();
      }
      final filename = item.name.trim();
      final sizeBytes = await _dropItemSizeBytes(item, bytes);
      return ref
          .read(attachmentPickerServiceProvider)
          .draftFromExternalSource(
            path: path.isEmpty ? null : path,
            filename: filename.isEmpty ? null : filename,
            mimeType: item.mimeType,
            sizeBytes: sizeBytes,
            bytes: bytes,
          );
    } finally {
      if (didAccessSecurityScopedResource && bookmark != null) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  Future<int?> _dropItemSizeBytes(DropItem item, Uint8List? bytes) async {
    if (bytes != null) {
      return bytes.length;
    }
    try {
      return await item.length();
    } catch (_) {
      return null;
    }
  }

  bool _canAcceptExternalAttachment(ConversationSummary conversation) {
    return !conversation.isDeletedAgentConversation &&
        _groupSendDisabledReason(conversation) == null;
  }

  void _stageAttachmentDraft(
    ConversationSummary conversation,
    AttachmentDraft draft,
  ) {
    if (!mounted ||
        !_canAcceptExternalAttachment(conversation) ||
        !_sameCanonicalConversation(
          conversation,
          _currentConversationSnapshot(),
        )) {
      return;
    }
    setState(() {
      _pendingAttachment = draft;
      _isDraggingExternalAttachment = false;
    });
    ref
        .read(chatComposerDraftsProvider.notifier)
        .setAttachment(conversation, draft);
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

  Future<String> _resolveAttachmentPreview(
    ConversationSummary conversation,
    ChatMessage message,
  ) {
    return ref
        .read(attachmentPreviewServiceProvider)
        .previewPathFor(
          message: message,
          download: () => ref
              .read(chatThreadsProvider.notifier)
              .downloadAttachment(conversation: conversation, message: message),
        );
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

  String _scopedTimelineEntryId(String value) {
    return '$_displayThreadId::$value';
  }

  String _messageTimelineEntryId(ChatMessage message) {
    return _scopedTimelineEntryId('message:${message.localId}');
  }

  String _pendingTurnTimelineEntryId(AgentPendingTurn turn) {
    final mention = turn.mentionId?.trim();
    final discriminator = mention != null && mention.isNotEmpty
        ? mention
        : turn.startedAt.microsecondsSinceEpoch.toString();
    return _scopedTimelineEntryId(
      'pending:${turn.localMessageId}:${turn.agentDid}:$discriminator',
    );
  }

  String _messageAgentTimelineEntryId(_MessageAgentTimelineItem item) {
    return switch (item) {
      _MessageAgentSyncTimelineItem(:final record) => _scopedTimelineEntryId(
        'agent-sync:${record.identityKey}',
      ),
      _MessageAgentActionTimelineItem(:final record) => _scopedTimelineEntryId(
        'agent-action:${record.actionId}',
      ),
    };
  }

  Key _timelineChildKey(String entryId) {
    return ValueKey<String>('chat-timeline-entry:$entryId');
  }

  Widget _buildTimelineChild(String entryId, Widget child) {
    final measurementKey = _timelineMeasurementKeys.putIfAbsent(
      entryId,
      () => GlobalKey(debugLabel: 'ChatView.timeline.$entryId'),
    );
    return KeyedSubtree(
      key: _timelineChildKey(entryId),
      child: KeyedSubtree(key: measurementKey, child: child),
    );
  }

  void _updateActiveTimeline(
    List<_ChatTimelineEntry> entries, {
    required double bottomInset,
  }) {
    _activeTimelineEntryIds = <String>[for (final entry in entries) entry.id];
    _activeTimelineTailId =
        entries.lastOrNull?.kind == _ChatTimelineEntryKind.tail
        ? entries.last.id
        : null;
    _activeTimelineBottomInset = bottomInset;
    final retainedIds = <String>{
      ..._activeTimelineEntryIds,
      for (final anchor in _readingAnchors) anchor.entryId,
    };
    _timelineMeasurementKeys.removeWhere(
      (entryId, _) => !retainedIds.contains(entryId),
    );
  }

  _ChatTimelineGeometry? _timelineGeometry(String entryId) {
    final viewportRenderObject = _activeRenderBox(_messageListViewportKey);
    final measurementKey = _timelineMeasurementKeys[entryId];
    final itemRenderObject = measurementKey == null
        ? null
        : _activeRenderBox(measurementKey);
    if (viewportRenderObject == null ||
        itemRenderObject == null ||
        !viewportRenderObject.attached ||
        !itemRenderObject.attached ||
        !viewportRenderObject.hasSize ||
        !itemRenderObject.hasSize) {
      return null;
    }
    final top = itemRenderObject
        .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
        .dy;
    return _ChatTimelineGeometry(
      top: top,
      bottom: top + itemRenderObject.size.height,
      viewportExtent: viewportRenderObject.size.height,
    );
  }

  double? _timelineViewportTop(String entryId) {
    final viewportRenderObject = _activeRenderBox(_messageListViewportKey);
    final measurementKey = _timelineMeasurementKeys[entryId];
    final itemRenderObject = measurementKey == null
        ? null
        : _activeRenderBox(measurementKey);
    if (viewportRenderObject == null ||
        itemRenderObject == null ||
        !viewportRenderObject.attached ||
        !itemRenderObject.attached) {
      return null;
    }
    return itemRenderObject
        .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
        .dy;
  }

  RenderBox? _activeRenderBox(GlobalKey key) {
    final itemContext = key.currentContext;
    if (itemContext == null) {
      return null;
    }
    try {
      final renderObject = itemContext.findRenderObject();
      return renderObject is RenderBox ? renderObject : null;
    } on FlutterError {
      // A keyed sliver child can be inactive briefly while
      // findChildIndexCallback moves it to a new timeline index.
      return null;
    }
  }

  void _captureReadingAnchors() {
    final tailId = _activeTimelineTailId;
    final entriesStartingInsideViewport = <_ChatViewportAnchor>[];
    final partiallyVisibleEntries = <_ChatViewportAnchor>[];
    for (final entryId in _activeTimelineEntryIds) {
      if (entryId == tailId) {
        continue;
      }
      final geometry = _timelineGeometry(entryId);
      if (geometry == null || !geometry.intersectsViewport) {
        continue;
      }
      final anchor = _ChatViewportAnchor(
        entryId: entryId,
        viewportOffset: geometry.top,
      );
      if (geometry.top >= 0) {
        entriesStartingInsideViewport.add(anchor);
      } else {
        partiallyVisibleEntries.add(anchor);
      }
    }
    // Prefer an item's actual leading edge over an entry whose content has
    // already left the viewport and only contributes trailing list spacing.
    // A tall partially-visible item remains the fallback when it is the only
    // entry intersecting the viewport.
    final next = <_ChatViewportAnchor>[
      ...entriesStartingInsideViewport,
      ...partiallyVisibleEntries,
    ];
    _readingAnchors = next;
    final retainedIds = <String>{
      ..._activeTimelineEntryIds,
      for (final anchor in next) anchor.entryId,
    };
    _timelineMeasurementKeys.removeWhere(
      (entryId, _) => !retainedIds.contains(entryId),
    );
  }

  void _handleScrollDelta(double delta) {
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.readingAnchor ||
        delta.abs() <= _chatBottomTolerance) {
      return;
    }
    _readingAnchors = <_ChatViewportAnchor>[
      for (final anchor in _readingAnchors) anchor.shiftedBy(delta),
    ];
    _scheduleReadingAnchorRefresh();
  }

  void _scheduleReadingAnchorRefresh() {
    if (_readingAnchorRefreshScheduled) {
      return;
    }
    _readingAnchorRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readingAnchorRefreshScheduled = false;
      if (!mounted ||
          _scrollAnchorPhase != _ChatScrollAnchorPhase.readingAnchor) {
        return;
      }
      _captureReadingAnchors();
    });
  }

  _ChatLayoutCorrection? _resolveLayoutCorrection(
    double minScrollExtent,
    double maxScrollExtent,
  ) {
    switch (_scrollAnchorPhase) {
      case _ChatScrollAnchorPhase.programmaticTail:
        if (_isProgrammaticScroll || !_programmaticTailCorrectionArmed) {
          return null;
        }
        if (maxScrollExtent <= minScrollExtent) {
          return const _ChatLayoutCorrection(0, ownsOutOfRangePosition: true);
        }
        final tailCorrection = _tailViewportCorrection();
        return _ChatLayoutCorrection(
          tailCorrection ?? maxScrollExtent - scrollController.position.pixels,
          ownsOutOfRangePosition: true,
        );
      case _ChatScrollAnchorPhase.readingAnchor:
        for (final anchor in _readingAnchors) {
          final top = _timelineViewportTop(anchor.entryId);
          if (top != null) {
            return _ChatLayoutCorrection(top - anchor.viewportOffset);
          }
        }
        return const _ChatLayoutCorrection(0);
      case _ChatScrollAnchorPhase.opening:
      case _ChatScrollAnchorPhase.followingTail:
        if (maxScrollExtent <= minScrollExtent) {
          return const _ChatLayoutCorrection(0, ownsOutOfRangePosition: true);
        }
        final tailCorrection = _tailViewportCorrection();
        return _ChatLayoutCorrection(
          tailCorrection ?? maxScrollExtent - scrollController.position.pixels,
          ownsOutOfRangePosition: true,
        );
    }
  }

  double? _tailViewportCorrection() {
    final tailId = _activeTimelineTailId;
    if (tailId == null) {
      return null;
    }
    final top = _timelineViewportTop(tailId);
    if (top == null ||
        !scrollController.hasClients ||
        !scrollController.position.hasViewportDimension) {
      return null;
    }
    final desiredTop =
        scrollController.position.viewportDimension -
        _activeTimelineBottomInset;
    return top - desiredTop;
  }

  double _tailScrollTarget() {
    final position = scrollController.position;
    final tailCorrection = _tailViewportCorrection();
    if (tailCorrection == null) {
      return position.maxScrollExtent;
    }
    return (position.pixels + tailCorrection)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  bool _isTailVisible() {
    final tailId = _activeTimelineTailId;
    if (tailId == null) {
      return false;
    }
    final top = _timelineViewportTop(tailId);
    if (top == null ||
        !scrollController.hasClients ||
        !scrollController.position.hasViewportDimension) {
      return false;
    }
    final viewportExtent = scrollController.position.viewportDimension;
    return top >= -_chatBottomTolerance &&
        top <= viewportExtent + _chatBottomTolerance;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (_isProgrammaticScroll) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _enterReadingAnchor();
      _updateUserAwayFromBottom(notification.metrics);
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _enterReadingAnchor();
      } else {
        _scheduleTailOwnershipCheck();
      }
      _updateUserAwayFromBottom(notification.metrics);
      return false;
    }
    if (notification is ScrollEndNotification) {
      _scheduleTailOwnershipCheck();
      _updateUserAwayFromBottom(notification.metrics);
    }
    return false;
  }

  void _handleUserScrollStart() {
    _enterReadingAnchor();
  }

  void _enterReadingAnchor() {
    if (_scrollAnchorPhase == _ChatScrollAnchorPhase.readingAnchor) {
      return;
    }
    _captureReadingAnchors();
    _scrollAnchorPhase = _ChatScrollAnchorPhase.readingAnchor;
    _openingAnchorToken += 1;
    _scrollEndCheckToken += 1;
    _cancelPendingScrollRequests();
  }

  void _scheduleTailOwnershipCheck() {
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.readingAnchor) {
      return;
    }
    final token = ++_scrollEndCheckToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _scrollEndCheckToken ||
          _scrollAnchorPhase != _ChatScrollAnchorPhase.readingAnchor) {
        return;
      }
      if (_isTailVisible()) {
        _scrollAnchorPhase = _ChatScrollAnchorPhase.followingTail;
        _readingAnchors = const <_ChatViewportAnchor>[];
      } else {
        _captureReadingAnchors();
      }
    });
  }

  void _handleScrollPositionChanged() {
    if (_isProgrammaticScroll || !scrollController.hasClients) {
      return;
    }
    _updateUserAwayFromBottom();
  }

  void _updateUserAwayFromBottom([ScrollMetrics? metrics]) {
    if (metrics == null && !scrollController.hasClients) {
      return;
    }
    final away = !_isNearBottom(metrics);
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
    if (_scrollAnchorPhase == _ChatScrollAnchorPhase.readingAnchor) {
      _captureReadingAnchors();
    }
    if (_shouldUseOpeningBottomAnchor(previous, next)) {
      _scheduleOpeningBottomAnchorSettle(settleFrames: 3);
      return;
    }
    if (previous == null) {
      if (next.messages.isNotEmpty) {
        _scheduleScrollToBottom(settleFrames: 2);
        _scheduleAcknowledgeVisibleConversationRead(
          conversation,
          reason: 'visible_thread_initial',
        );
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
    final shouldFollowBottom =
        _scrollAnchorPhase != _ChatScrollAnchorPhase.readingAnchor;
    if (messageAdded) {
      if (nextLast.isMine || shouldFollowBottom) {
        _scheduleScrollToBottom(animated: !nextLast.isMine);
        if (!nextLast.isMine) {
          _acknowledgeVisibleConversationRead(
            conversation,
            reason: 'visible_message_added',
            forcePersistentAck: true,
          );
        }
      } else {
        _showDeferredBottomNotice();
      }
      return;
    }
    if (pendingAdded || recoveryAdded) {
      if (shouldFollowBottom || _latestMessageIsMine(next)) {
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
    if (contentGrew && shouldFollowBottom) {
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
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.opening) {
      _scrollAnchorPhase = _ChatScrollAnchorPhase.programmaticTail;
      _programmaticTailCorrectionArmed = false;
    }
    _readingAnchors = const <_ChatViewportAnchor>[];
    _scrollEndCheckToken += 1;
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
    _programmaticTailCorrectionArmed = false;
  }

  void _beginOpeningBottomAnchor() {
    _scrollAnchorPhase = _ChatScrollAnchorPhase.opening;
    _readingAnchors = const <_ChatViewportAnchor>[];
    _scrollEndCheckToken += 1;
    _openingAnchorObservedContent = false;
    _openingAnchorToken += 1;
  }

  bool _shouldUseOpeningBottomAnchor(
    ChatThreadState? previous,
    ChatThreadState next,
  ) {
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.opening ||
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
        _openingAnchorObservedContent) {
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
          _scrollAnchorPhase = _ChatScrollAnchorPhase.followingTail;
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
    final target = _tailScrollTarget();
    _isProgrammaticScroll = true;
    if (animated) {
      scrollController
          .animateToTimelineTarget(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (!mounted || token != _scrollRequestToken) {
              return;
            }
            _isProgrammaticScroll = false;
            _programmaticTailCorrectionArmed = true;
            if (!_isTailVisible()) {
              _jumpToLatestBottom();
            }
            _markAtBottomAfterProgrammaticScroll();
            _scheduleProgrammaticTailFinalize(token);
          });
      return;
    }
    scrollController.jumpToTimelineTarget(target);
    _isProgrammaticScroll = false;
    _programmaticTailCorrectionArmed = true;
    _markAtBottomAfterProgrammaticScroll();
    _scheduleProgrammaticTailFinalize(token);
  }

  void _scheduleProgrammaticTailFinalize(int token, {int attempts = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _scrollRequestToken ||
          attempts <= 0 ||
          _scrollAnchorPhase == _ChatScrollAnchorPhase.readingAnchor) {
        return;
      }
      if (!_isTailVisible()) {
        _jumpToLatestBottom();
      }
      _markAtBottomAfterProgrammaticScroll();
      if (_scrollAnchorPhase == _ChatScrollAnchorPhase.programmaticTail) {
        _scheduleProgrammaticTailFinalize(token, attempts: attempts - 1);
      }
    });
  }

  void _jumpToLatestBottom() {
    if (!scrollController.hasClients) {
      return;
    }
    _isProgrammaticScroll = true;
    scrollController.jumpToTimelineTarget(_tailScrollTarget());
    _isProgrammaticScroll = false;
    _programmaticTailCorrectionArmed = true;
  }

  void _markAtBottomAfterProgrammaticScroll({bool forcePersistentAck = true}) {
    if (!_isTailVisible()) {
      return;
    }
    _userAwayFromBottom = false;
    if (_scrollAnchorPhase != _ChatScrollAnchorPhase.opening) {
      _scrollAnchorPhase = _ChatScrollAnchorPhase.followingTail;
      _programmaticTailCorrectionArmed = false;
    }
    if (_hasDeferredBottomNotice && mounted) {
      setState(() {
        _hasDeferredBottomNotice = false;
      });
    }
    _acknowledgeCurrentVisibleConversationRead(
      reason: 'programmatic_bottom',
      forcePersistentAck: forcePersistentAck,
    );
  }

  bool _isNearBottom([ScrollMetrics? metrics]) {
    if (metrics == null && !scrollController.hasClients) {
      return true;
    }
    final current = metrics ?? scrollController.position;
    return current.maxScrollExtent - current.pixels <= _nearBottomExtent;
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

  ConversationSummary? _matchingConversationByThread(
    List<ConversationSummary> conversations,
  ) {
    final displayThreadId = _displayThreadId.trim();
    for (final conversation in conversations) {
      if (displayThreadId.isNotEmpty &&
          _timelineDisplayThreadId(conversation) == displayThreadId) {
        return conversation;
      }
    }
    return null;
  }

  void _handleConversationListChanged(ConversationListState next) {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final updated = _matchingConversationByThread(next.conversations);
      if (updated == null) {
        return;
      }
      unawaited(
        _chatThreadsController.syncVisibleConversationAfterSummaryUpdate(
          updated,
          displayThreadId: _displayThreadId,
        ),
      );
    });
  }

  ConversationSummary? _matchingConversationForDisplay(
    List<ConversationSummary> conversations,
  ) {
    return _matchingConversationByThread(conversations);
  }

  ConversationSummary _currentConversationForTitle() {
    final conversations = ref.watch(conversationListProvider).conversations;
    final latest = _matchingConversationForDisplay(conversations);
    final base = latest ?? widget.conversation;
    if (!base.isGroup) {
      final avatarUri = peerAvatarUri(
        ref.watch(peerDisplayProfileProvider),
        base.targetDid,
        peerPersonaId: base.peerPersonaId,
      );
      if (avatarUri == null || avatarUri == base.avatarUri) {
        return base;
      }
      return base.copyWith(avatarUri: avatarUri);
    }
    final groupName = _currentGroupName(base);
    final groupAvatarUri = _currentGroupAvatarUri(base);
    if ((groupName == null || groupName == base.displayName) &&
        groupAvatarUri == base.avatarUri) {
      return base;
    }
    return base.copyWith(
      displayName: groupName ?? base.displayName,
      avatarUri: groupAvatarUri ?? base.avatarUri,
    );
  }

  String? _headerNickname(ConversationSummary conversation) {
    if (conversation.isGroup) {
      return null;
    }
    final targetDid = conversation.targetDid?.trim();
    final peerPersonaId = conversation.peerPersonaId?.trim();
    if ((targetDid == null || targetDid.isEmpty) &&
        (peerPersonaId == null || peerPersonaId.isEmpty)) {
      return null;
    }
    final nickname = ref.watch(
      peerDisplayNameProvider(
        PeerDisplayNameRequest(
          peerPersonaId: peerPersonaId,
          did: targetDid,
          nickname: conversation.displayName,
          fullHandle: conversation.targetPeer,
        ),
      ),
    );
    return nickname.isEmpty ? null : nickname;
  }

  ConversationSummary _currentConversationSnapshot() {
    final conversations = ref.read(conversationListProvider).conversations;
    final latest = _matchingConversationByThread(conversations);
    return latest ?? widget.conversation;
  }

  String? _currentGroupName(ConversationSummary conversation) {
    final groups = ref.watch(groupProvider).groups;
    for (final group in groups) {
      if (group.conversationId == conversation.conversationId &&
          !GroupDisplayName.isIdLike(group.displayName, group.groupId)) {
        return group.displayName;
      }
    }
    return null;
  }

  String? _currentGroupAvatarUri(ConversationSummary conversation) {
    final groups = ref.watch(groupProvider).groups;
    for (final group in groups) {
      if (group.conversationId == conversation.conversationId) {
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
        return context.l10n.chatGroupLeftDisabled;
      }
      return context.l10n.chatGroupSendDisabled;
    }
    return null;
  }

  GroupSummary? _groupInviteTarget(
    ConversationSummary conversation,
    List<GroupSummary> groups,
  ) {
    if (!conversation.isGroup) {
      return null;
    }
    final groupId = conversation.groupId?.trim().isNotEmpty == true
        ? conversation.groupId!.trim()
        : conversation.threadId.trim();
    if (groupId.isEmpty) {
      return null;
    }
    for (final group in groups) {
      if (group.groupId == groupId && hasKnownGroupRole(group)) {
        return group;
      }
    }
    return null;
  }

  void _requestGroupRoleIfNeeded(ConversationSummary conversation) {
    if (!conversation.isGroup) {
      return;
    }
    final groupId = conversation.groupId?.trim().isNotEmpty == true
        ? conversation.groupId!.trim()
        : conversation.threadId.trim();
    if (groupId.isEmpty || _requestedGroupRoleIds.contains(groupId)) {
      return;
    }
    final groups = ref.read(groupProvider).groups;
    for (final group in groups) {
      if (group.groupId == groupId && hasKnownGroupRole(group)) {
        return;
      }
    }
    _requestedGroupRoleIds.add(groupId);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      try {
        await ref
            .read(groupProvider.notifier)
            .refreshGroup(groupId, refreshMembers: false);
      } catch (_) {
        _requestedGroupRoleIds.remove(groupId);
      }
    });
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
    if (current.isGroupSystemEvent) {
      return false;
    }
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
    if (next == null ||
        current.isGroupSystemEvent ||
        next.isGroupSystemEvent ||
        !current.isMine ||
        _shouldShowDivider(current, next)) {
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
    final senderDid = message.senderDid.trim();
    return ref.watch(
      peerDisplayNameProvider(
        PeerDisplayNameRequest(
          peerPersonaId: message.senderPeerPersonaId,
          did: senderDid,
          senderNameSnapshot: message.senderName,
          unknownLabel: context.l10n.chatUnknownUser,
        ),
      ),
    );
  }

  GroupSummary _groupSummaryForConversation(ConversationSummary conversation) {
    final groupId = conversation.groupId?.trim().isNotEmpty == true
        ? conversation.groupId!.trim()
        : conversation.canonicalGroupDid?.trim().isNotEmpty == true
        ? conversation.canonicalGroupDid!.trim()
        : conversation.threadId;
    final groups = ref.read(groupProvider).groups;
    for (final item in groups) {
      if (item.conversationId == conversation.conversationId) {
        return item;
      }
    }
    final name = conversation.displayName.trim().isNotEmpty
        ? conversation.displayName.trim()
        : groupId;
    return GroupSummary(
      conversationId: conversation.conversationId,
      groupId: groupId,
      displayName: name,
      description: '',
      memberCount: 0,
      lastMessageAt: conversation.lastMessageAt,
      avatarUri: conversation.avatarUri,
      membershipStatus: null,
    );
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
    BuildContext context,
    AgentSummary? runtimeAgent,
    ConversationSummary conversation,
  ) {
    if (runtimeAgent != null) {
      return localizeAgentTitle(context.l10n, runtimeAgent);
    }
    return conversation.displayName;
  }

  String _agentProcessingLabel(
    BuildContext context,
    List<AgentPendingTurn> turns,
  ) {
    if (turns.isEmpty) {
      return context.l10n.chatAgentProcessing;
    }
    final overdue = turns.any((turn) => turn.isOverdue);
    final subject = _agentProcessingSubject(context, turns);
    final progressCodes = turns
        .map((turn) => turn.progress?.code)
        .whereType<String>()
        .toSet();
    if (progressCodes.contains('external_service_delayed')) {
      return subject == context.l10n.chatAgentSubject
          ? context.l10n.chatAgentExternalServiceDelayed
          : context.l10n.chatSubjectExternalServiceDelayed(subject);
    }
    if (progressCodes.contains('external_service_resumed')) {
      return subject == context.l10n.chatAgentSubject
          ? context.l10n.chatAgentExternalServiceResumed
          : context.l10n.chatSubjectExternalServiceResumed(subject);
    }
    if (progressCodes.contains('external_tool_running')) {
      return subject == context.l10n.chatAgentSubject
          ? context.l10n.chatAgentExternalServiceWorking
          : context.l10n.chatSubjectExternalServiceWorking(subject);
    }
    if (subject == context.l10n.chatAgentSubject) {
      return overdue
          ? context.l10n.chatAgentStillProcessing
          : context.l10n.chatAgentProcessing;
    }
    return overdue
        ? context.l10n.chatSubjectStillProcessing(subject)
        : context.l10n.chatSubjectProcessing(subject);
  }

  String _agentProcessingSubject(
    BuildContext context,
    List<AgentPendingTurn> turns,
  ) {
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
      return context.l10n.chatAgentSubject;
    }
    if (handles.length <= 2) {
      final separator = appLocalizationsUseChinese(context.l10n) ? '、' : ', ';
      return handles.map((handle) => '@$handle').join(separator);
    }
    return context.l10n.chatAgentCountSubject(handles.length);
  }
}
