import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/l10n.dart';
import '../conversation_list/conversation_provider.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'chat_provider.dart';

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
    this.macStyle = false,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final bool macStyle;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final textController = TextEditingController();
  final scrollController = ScrollController();
  bool _isRefreshingCurrentConversation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final macStyle = widget.macStyle && responsive.isMacDesktop;
    final thread = ref.watch(chatThreadProvider(widget.conversation.threadId));
    final currentConversation = _currentConversationForTitle();
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
        ref.read(chatThreadsProvider.notifier).openConversation(updated),
      );
    });
    final messages = thread.messages;
    final page = SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          _ChatHeader(
            conversation: currentConversation,
            embedded: widget.embedded,
            macStyle: macStyle,
            isRefreshing: _isRefreshingCurrentConversation || thread.isLoading,
            onBack: widget.onBack,
            onDetails: _openDetails,
            onRefresh: () => _refreshCurrentConversation(currentConversation),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: EdgeInsets.fromLTRB(
                macStyle
                    ? 28
                    : (widget.embedded
                          ? responsive.spacing(32)
                          : responsive.tabContentHorizontalPadding),
                macStyle ? 20 : responsive.spacing(24),
                macStyle
                    ? 28
                    : (widget.embedded
                          ? responsive.spacing(32)
                          : responsive.tabContentHorizontalPadding),
                macStyle ? 92 : responsive.spacing(widget.embedded ? 124 : 140),
              ),
              itemCount: messages.length,
              itemBuilder: (_, index) {
                final message = messages[index];
                final previous = index == 0 ? null : messages[index - 1];
                final senderLabel = _displayNameForMessage(context, message);
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: macStyle ? 16 : responsive.spacing(24),
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
                        macStyle: macStyle,
                        onRetry: message.sendState == MessageSendState.failed
                            ? () async {
                                await ref
                                    .read(chatThreadsProvider.notifier)
                                    .retryMessage(
                                      conversation: widget.conversation,
                                      message: message,
                                    );
                              }
                            : null,
                      ),
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
            onSend: () async {
              final value = textController.text;
              textController.clear();
              await ref
                  .read(chatThreadsProvider.notifier)
                  .sendMessage(
                    conversation: widget.conversation,
                    content: value,
                  );
            },
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
          .refreshConversation(conversation);
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
    if (groupName == null || groupName == base.displayName) {
      return base;
    }
    return ConversationSummary(
      threadId: base.threadId,
      displayName: groupName,
      lastMessagePreview: base.lastMessagePreview,
      lastMessageAt: base.lastMessageAt,
      unreadCount: base.unreadCount,
      isGroup: base.isGroup,
      targetDid: base.targetDid,
      groupId: base.groupId,
      avatarSeed: base.avatarSeed,
    );
  }

  String? _currentGroupName(String groupId) {
    final groups = ref.watch(groupProvider).groups;
    for (final group in groups) {
      if (group.groupId == groupId &&
          !GroupDisplayName.isIdLike(group.name, groupId)) {
        return group.name;
      }
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
    return current.createdAt.difference(previous.createdAt).inMinutes >= 30;
  }

  String _timeDividerLabel(DateTime date, {DateTime? previous}) {
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (previous != null &&
        previous.year == date.year &&
        previous.month == date.month &&
        previous.day == date.day) {
      return time;
    }
    return '${_dateLabel(date)} $time';
  }

  String _displayNameForMessage(BuildContext context, ChatMessage message) {
    final senderName = message.senderName?.trim() ?? '';
    if (senderName.isNotEmpty) {
      return senderName;
    }
    final senderDid = message.senderDid.trim();
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
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.embedded,
    required this.macStyle,
    required this.isRefreshing,
    required this.onDetails,
    required this.onRefresh,
    this.onBack,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final bool macStyle;
  final bool isRefreshing;
  final VoidCallback onDetails;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final compactName = DidDisplayFormatter.conversationTitle(
      conversation,
      context.l10n,
    );
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    if (macStyle) {
      return Container(
        height: 64,
        padding: const EdgeInsets.fromLTRB(22, 0, 18, 0),
        decoration: const BoxDecoration(
          color: CupertinoColors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5EAF2))),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final showPills = width >= 500;
            final showSecurityPill = width >= 620;
            final showIdentityLabel = width >= 470;
            final avatarSize = width >= 360 ? 40.0 : 36.0;
            final actionGap = width >= 520 ? 12.0 : 8.0;

            return Row(
              children: <Widget>[
                AvatarBadge(seed: compactName, size: avatarSize),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          compactName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF101B32),
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (showPills && !conversation.isGroup) ...<Widget>[
                        const SizedBox(width: 8),
                        const _MacChatPill(
                          label: '我的智能体',
                          color: Color(0xFFEAF2FF),
                          textColor: Color(0xFF0B65F8),
                        ),
                      ],
                      if (showSecurityPill) ...<Widget>[
                        const SizedBox(width: 6),
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
                _MacChatHeaderButton(
                  key: const Key('chat-refresh-button'),
                  semanticLabel: '刷新当前会话',
                  icon: CupertinoIcons.refresh,
                  isLoading: isRefreshing,
                  onTap: onRefresh,
                ),
                const SizedBox(width: 8),
                _MacChatIdentityButton(
                  showLabel: showIdentityLabel,
                  onTap: onDetails,
                ),
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
          AvatarBadge(seed: compactName, size: responsive.avatarSizeMd),
          SizedBox(width: responsive.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  compactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: responsive.titleLg,
                    fontWeight: FontWeight.w700,
                    color: theme.title,
                  ),
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
                        fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MacChatIdentityButton extends StatelessWidget {
  const _MacChatIdentityButton({required this.showLabel, required this.onTap});

  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        width: showLabel ? null : 34,
        padding: showLabel
            ? const EdgeInsets.symmetric(horizontal: 12)
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDE5F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              CupertinoIcons.person_crop_square,
              color: Color(0xFF34415C),
              size: 17,
            ),
            if (showLabel) ...<Widget>[
              const SizedBox(width: 7),
              const Text(
                '身份卡',
                style: TextStyle(
                  color: Color(0xFF17213A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
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
  });

  final String semanticLabel;
  final IconData icon;
  final Future<void> Function() onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: !isLoading,
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 34,
          width: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDE5F0)),
          ),
          child: isLoading
              ? const CupertinoActivityIndicator(radius: 8)
              : Icon(icon, color: const Color(0xFF34415C), size: 17),
        ),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.senderLabel,
    this.macStyle = false,
    this.onRetry,
  });

  final ChatMessage message;
  final String senderLabel;
  final bool macStyle;
  final Future<void> Function()? onRetry;

  Widget _buildMacBubble(BuildContext context, bool isMine) {
    final bubble = Column(
      crossAxisAlignment: isMine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine ? const Color(0xFFEAF2FF) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isMine ? const Color(0xFFEAF2FF) : const Color(0xFFDDE5F0),
            ),
          ),
          child: Text(
            message.content,
            style: const TextStyle(
              color: Color(0xFF17213A),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
        if (message.sendState == MessageSendState.failed) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '发送失败',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFF3B30),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onRetry,
                behavior: HitTestBehavior.opaque,
                child: const Text(
                  '重试',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0B65F8),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ] else if (message.sendState == MessageSendState.sending) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            '发送中...',
            style: TextStyle(fontSize: 12, color: Color(0xFF8A96AA)),
          ),
        ],
      ],
    );
    return Row(
      mainAxisAlignment: isMine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!isMine) ...<Widget>[
          AvatarBadge(seed: senderLabel, size: 34),
          const SizedBox(width: 10),
        ],
        Flexible(child: bubble),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    if (macStyle) {
      return _buildMacBubble(context, isMine);
    }
    return Row(
      mainAxisAlignment: isMine
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!isMine) ...<Widget>[
          AvatarBadge(seed: senderLabel, size: responsive.scaled(28)),
          SizedBox(width: responsive.spacing(12)),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: responsive.isLarge ? 500 : 640,
            ),
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: <Widget>[
                if (!isMine)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: responsive.spacing(6),
                      left: responsive.spacing(4),
                    ),
                    child: Text(
                      senderLabel,
                      style: TextStyle(
                        fontSize: responsive.metaSm,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryDark,
                      ),
                    ),
                  ),
                Container(
                  padding: responsive.scaledInsets(
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  ),
                  decoration: BoxDecoration(
                    color: isMine
                        ? theme.warningContainer
                        : theme.subtleSurface,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isMine ? 22 : 6),
                      topRight: Radius.circular(isMine ? 6 : 22),
                      bottomLeft: const Radius.circular(22),
                      bottomRight: const Radius.circular(22),
                    ),
                  ),
                  child: Text(
                    message.content,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: responsive.bodyMd,
                      height: responsive.isPhone ? 1.5 : 1.4,
                    ),
                  ),
                ),
                if (message.sendState == MessageSendState.failed) ...<Widget>[
                  SizedBox(height: responsive.spacing(8)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '发送失败',
                        style: TextStyle(
                          fontSize: responsive.metaSm,
                          color: theme.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: responsive.spacing(10)),
                      GestureDetector(
                        onTap: onRetry,
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '重试',
                          style: TextStyle(
                            fontSize: responsive.metaSm,
                            color: theme.primaryDark,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (message.sendState ==
                    MessageSendState.sending) ...<Widget>[
                  SizedBox(height: responsive.spacing(8)),
                  Text(
                    '发送中...',
                    style: TextStyle(
                      fontSize: responsive.metaSm,
                      color: theme.tertiaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.embedded,
    required this.macStyle,
    required this.controller,
    required this.onSend,
  });

  final bool embedded;
  final bool macStyle;
  final TextEditingController controller;
  final Future<void> Function() onSend;

  Future<void> _submitIfNeeded() async {
    if (controller.text.trim().isEmpty) {
      return;
    }
    await onSend();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    if (macStyle) {
      return SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 360;
            final showAttachment = constraints.maxWidth >= 280;
            final horizontal = compact ? 14.0 : 22.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 16),
              child: Container(
                height: 52,
                padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFDDE5F0)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x0F0B1F3A),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    if (showAttachment) ...<Widget>[
                      const Icon(
                        CupertinoIcons.paperclip,
                        color: Color(0xFF34415C),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: CupertinoTextField(
                        controller: controller,
                        placeholder: context.l10n.chatInputPlaceholder,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) async => _submitIfNeeded(),
                        decoration: null,
                        padding: EdgeInsets.zero,
                        style: const TextStyle(
                          color: Color(0xFF17213A),
                          fontSize: 13.5,
                        ),
                        placeholderStyle: const TextStyle(
                          color: Color(0xFF8A96AA),
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _submitIfNeeded,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B65F8),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          CupertinoIcons.paperplane_fill,
                          color: CupertinoColors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    final outerPadding = embedded
        ? const EdgeInsets.fromLTRB(16, 8, 16, 16)
        : responsive.scaledInsets(const EdgeInsets.fromLTRB(16, 8, 16, 16));
    return SafeArea(
      top: false,
      child: Padding(
        padding: outerPadding,
        child: Container(
          constraints: embedded
              ? BoxConstraints.tightFor(height: responsive.navBarHeight)
              : BoxConstraints(minHeight: responsive.controlHeight),
          padding: responsive.scaledInsets(
            EdgeInsets.fromLTRB(14, embedded ? 8 : 10, 14, embedded ? 8 : 10),
          ),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(
              embedded ? 24 : responsive.radius(26),
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              TopBarActionButton(
                onTap: () {},
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
                child: CupertinoTextField(
                  controller: controller,
                  placeholder: context.l10n.chatInputPlaceholder,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) async => _submitIfNeeded(),
                  decoration: null,
                  padding: EdgeInsets.symmetric(
                    vertical: responsive.spacing(10),
                  ),
                  style: TextStyle(
                    fontSize: responsive.bodyMd,
                    color: theme.title,
                  ),
                  placeholderStyle: TextStyle(
                    fontSize: responsive.bodyMd,
                    color: theme.secondaryText,
                  ),
                ),
              ),
              SizedBox(width: responsive.spacing(8)),
              TopBarActionButton(
                onTap: _submitIfNeeded,
                child: Padding(
                  padding: EdgeInsets.all(responsive.spacing(6)),
                  child: AwikiAssetIcon(
                    assetName: 'assets/icons/icon_send.svg',
                    color: theme.primary,
                    size: responsive.iconMd,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
