import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
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
    this.onMacConversationInfoTap,
    this.macStyle = false,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final VoidCallback? onMacIdentityPanelTap;
  final VoidCallback? onMacConversationInfoTap;
  final bool macStyle;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final textController = TextEditingController();
  final scrollController = ScrollController();
  bool _isRefreshingCurrentConversation = false;
  final Set<String> _downloadingAttachmentMessageIds = <String>{};

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
            isFollowing: _isFollowableDirect(currentConversation)
                ? friendsState.isFollowing(currentConversation.targetDid!)
                : false,
            onFollowTap: _isFollowableDirect(currentConversation)
                ? () => _toggleFollow(currentConversation)
                : null,
            onBack: widget.onBack,
            onDetails: _openDetails,
            onMacIdentityPanelTap: widget.onMacIdentityPanelTap,
            onMacConversationInfoTap: widget.onMacConversationInfoTap,
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
                            ? (_canRetryMessage(message)
                                  ? () async {
                                      await ref
                                          .read(chatThreadsProvider.notifier)
                                          .retryMessage(
                                            conversation: widget.conversation,
                                            message: message,
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
            onAttach: () async {
              await _pickAndSendAttachment(currentConversation);
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

  Future<void> _pickAndSendAttachment(ConversationSummary conversation) async {
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
      final caption = textController.text.trim().isEmpty
          ? null
          : textController.text.trim();
      textController.clear();
      await ref
          .read(chatThreadsProvider.notifier)
          .sendAttachment(
            conversation: conversation,
            attachment: draft,
            caption: caption,
          );
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
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

  bool _isFollowableDirect(ConversationSummary conversation) {
    final targetDid = conversation.targetDid?.trim() ?? '';
    return !conversation.isGroup && targetDid.startsWith('did:');
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
    return current.createdAt
            .toLocal()
            .difference(previous.createdAt.toLocal())
            .inMinutes >=
        30;
  }

  String _timeDividerLabel(DateTime date, {DateTime? previous}) {
    final localDate = date.toLocal();
    final time =
        '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    return '${_dateLabel(localDate)} $time';
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
    required this.isFollowing,
    required this.onDetails,
    required this.onRefresh,
    this.onFollowTap,
    this.onMacIdentityPanelTap,
    this.onMacConversationInfoTap,
    this.onBack,
  });

  final ConversationSummary conversation;
  final bool embedded;
  final VoidCallback? onBack;
  final bool macStyle;
  final bool isRefreshing;
  final bool isFollowing;
  final VoidCallback onDetails;
  final Future<void> Function()? onFollowTap;
  final VoidCallback? onMacIdentityPanelTap;
  final VoidCallback? onMacConversationInfoTap;
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
                if (onFollowTap != null) ...<Widget>[
                  _ChatFollowButton(
                    isFollowing: isFollowing,
                    compact: width < 560,
                    onTap: onFollowTap!,
                  ),
                  const SizedBox(width: 8),
                ],
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
                  onTap: conversation.isGroup
                      ? onDetails
                      : (onMacIdentityPanelTap ?? onDetails),
                ),
                if (onMacConversationInfoTap != null) ...<Widget>[
                  const SizedBox(width: 8),
                  _MacChatHeaderButton(
                    key: const Key('chat-conversation-info-button'),
                    semanticLabel: '折叠会话信息',
                    icon: CupertinoIcons.sidebar_right,
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
                    if (onFollowTap != null) ...<Widget>[
                      SizedBox(width: responsive.spacing(10)),
                      _ChatFollowButton(
                        isFollowing: isFollowing,
                        compact: responsive.isPhone,
                        onTap: onFollowTap!,
                      ),
                    ],
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
    final label = widget.isFollowing ? '已关注' : '关注';
    final foreground = widget.isFollowing
        ? const Color(0xFF34415C)
        : theme.primaryForeground;
    final background = widget.isFollowing
        ? CupertinoColors.white
        : theme.primary;
    return Semantics(
      button: true,
      label: label,
      enabled: !_isBusy,
      child: GestureDetector(
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
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 30,
          constraints: BoxConstraints(minWidth: widget.compact ? 54 : 66),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.isFollowing
                  ? const Color(0xFFDDE5F0)
                  : theme.primary,
            ),
          ),
          child: _isBusy
              ? CupertinoActivityIndicator(
                  radius: 7,
                  color: widget.isFollowing ? const Color(0xFF34415C) : null,
                )
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
    this.onDownload,
    this.isDownloading = false,
  });

  final ChatMessage message;
  final String senderLabel;
  final bool macStyle;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onDownload;
  final bool isDownloading;

  Widget _buildMacBubble(BuildContext context, bool isMine) {
    final child = message.attachment == null
        ? Text(
            message.content,
            style: const TextStyle(
              color: Color(0xFF17213A),
              fontSize: 14,
              height: 1.45,
            ),
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
          child: child,
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
              if (onRetry != null) ...<Widget>[
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
                  child: message.attachment == null
                      ? Text(
                          message.content,
                          style: TextStyle(
                            color: theme.title,
                            fontSize: responsive.bodyMd,
                            height: responsive.isPhone ? 1.5 : 1.4,
                          ),
                        )
                      : _AttachmentContent(
                          message: message,
                          macStyle: false,
                          onDownload: onDownload,
                          isDownloading: isDownloading,
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
                      if (onRetry != null) ...<Widget>[
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
      fontSize: macStyle ? 13.5 : responsive.bodyMd,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    final metaStyle = TextStyle(
      color: macStyle ? const Color(0xFF66728A) : theme.secondaryText,
      fontSize: macStyle ? 12 : responsive.metaSm,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: macStyle ? 220 : responsive.scaled(210),
        maxWidth: macStyle ? 360 : responsive.scaled(420),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (caption != null && caption.isNotEmpty) ...<Widget>[
            Text(
              caption,
              style: TextStyle(
                color: macStyle ? const Color(0xFF17213A) : theme.title,
                fontSize: macStyle ? 14 : responsive.bodyMd,
                height: 1.4,
              ),
            ),
            SizedBox(height: macStyle ? 10 : responsive.spacing(10)),
          ],
          Row(
            children: <Widget>[
              Container(
                width: macStyle ? 38 : responsive.scaled(40),
                height: macStyle ? 38 : responsive.scaled(40),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: macStyle
                      ? const Color(0xFFEAF2FF)
                      : theme.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(macStyle ? 8 : 10),
                  border: Border.all(
                    color: macStyle ? const Color(0xFFDDE5F0) : theme.border,
                  ),
                ),
                child: Icon(
                  CupertinoIcons.doc_fill,
                  color: macStyle ? const Color(0xFF0B65F8) : theme.primary,
                  size: macStyle ? 20 : responsive.iconSm,
                ),
              ),
              SizedBox(width: macStyle ? 10 : responsive.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      attachment.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    SizedBox(height: macStyle ? 4 : responsive.spacing(4)),
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
                SizedBox(width: macStyle ? 10 : responsive.spacing(10)),
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
    final size = macStyle ? 32.0 : responsive.scaled(34);
    return Semantics(
      button: true,
      label: '下载附件',
      enabled: !isLoading,
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: macStyle ? CupertinoColors.white : theme.surface,
            borderRadius: BorderRadius.circular(macStyle ? 8 : 10),
            border: Border.all(
              color: macStyle ? const Color(0xFFDDE5F0) : theme.border,
            ),
          ),
          child: isLoading
              ? CupertinoActivityIndicator(radius: macStyle ? 7 : 8)
              : Icon(
                  CupertinoIcons.arrow_down_doc_fill,
                  color: macStyle ? const Color(0xFF0B65F8) : theme.primary,
                  size: macStyle ? 17 : responsive.iconSm,
                ),
        ),
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.embedded,
    required this.macStyle,
    required this.controller,
    required this.onSend,
    required this.onAttach,
  });

  final bool embedded;
  final bool macStyle;
  final TextEditingController controller;
  final Future<void> Function() onSend;
  final Future<void> Function() onAttach;

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
                      GestureDetector(
                        key: const Key('chat-attachment-button'),
                        onTap: onAttach,
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            CupertinoIcons.paperclip,
                            color: Color(0xFF34415C),
                            size: 22,
                          ),
                        ),
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
                key: const Key('chat-attachment-button'),
                onTap: onAttach,
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
