import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../l10n/l10n.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/widgets/app_widgets.dart';
import 'chat_provider.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.conversation,
  });

  final ConversationSummary conversation;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final textController = TextEditingController();
  final scrollController = ScrollController();

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
    final theme = context.awikiTheme;
    final thread = ref.watch(chatThreadProvider(widget.conversation.threadId));
    ref.listen<ChatThreadState>(
      chatThreadProvider(widget.conversation.threadId),
      (_, __) => WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom()),
    );
    final messages = thread.messages;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiMeWidgets.pageBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _ChatHeader(
                conversation: widget.conversation,
                onBack: () => Navigator.of(context).pop(),
                onDetails: _openDetails,
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
                  itemCount: messages.length + 1,
                  itemBuilder: (_, index) {
                    if (index == 0) {
                      final firstDate = messages.isEmpty
                          ? DateTime.now()
                          : messages.first.createdAt;
                      return _DateDivider(label: _dateLabel(firstDate));
                    }
                    final message = messages[index - 1];
                    final senderLabel =
                        _displayNameForMessage(context, message);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _MessageBubble(
                        message: message,
                        senderLabel: senderLabel,
                      ),
                    );
                  },
                ),
              ),
              _Composer(
                controller: textController,
                onSend: () async {
                  final value = textController.text;
                  textController.clear();
                  await ref.read(chatThreadsProvider.notifier).sendMessage(
                        conversation: widget.conversation,
                        content: value,
                      );
                },
              ),
            ],
          ),
        ),
      ),
    );
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

  void _scrollToBottom() {
    if (!scrollController.hasClients) {
      return;
    }
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
  }

  String _dateLabel(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month-$day';
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
    required this.onBack,
    required this.onDetails,
  });

  final ConversationSummary conversation;
  final VoidCallback onBack;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final compactName =
        DidDisplayFormatter.conversationTitle(conversation, context.l10n);
    final theme = context.awikiTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        children: <Widget>[
          TopBarActionButton(
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back,
                color: theme.primaryDark,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AvatarBadge(seed: compactName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              compactName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AwikiMeTextStyles.sectionTitle,
            ),
          ),
          TopBarActionButton(
            onTap: onDetails,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.info_outline,
                color: theme.title,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppSurface(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: context.awikiTheme.subtleSurface,
        radius: AwikiMeRadii.pill,
        child: Text(
          label,
          style: AwikiMeTextStyles.meta,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.senderLabel,
  });

  final ChatMessage message;
  final String senderLabel;

  @override
  Widget build(BuildContext context) {
    final isMine = message.isMine;
    final theme = context.awikiTheme;
    return Row(
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (!isMine) ...<Widget>[
          AvatarBadge(seed: senderLabel, size: 32),
          const SizedBox(width: 12),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              if (!isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    senderLabel,
                    style: AwikiMeTextStyles.meta,
                  ),
                ),
              AppSurface(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: isMine ? theme.primary : theme.surface,
                radius: 18,
                child: Text(
                  message.content,
                  style: TextStyle(
                    color: isMine ? theme.primaryForeground : theme.title,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: <Widget>[
            Expanded(
              child: AppTextField(
                controller: controller,
                label: context.l10n.commonSend,
                placeholder: context.l10n.chatInputPlaceholder,
              ),
            ),
            const SizedBox(width: 12),
            TopBarActionButton(
              onTap: onSend,
              child: AppSurface(
                padding: const EdgeInsets.all(12),
                color: theme.primary,
                radius: AwikiMeRadii.pill,
                child: Icon(
                  Icons.send,
                  color: theme.primaryForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
