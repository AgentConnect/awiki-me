import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/scheduler.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../app_shell/app_controller.dart';
import '../group/group_list_page.dart';
import '../profile/peer_profile_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.controller,
    required this.conversation,
  });

  final AppController controller;
  final ConversationSummary conversation;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final textController = TextEditingController();
  final scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    textController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.idle &&
        binding.schedulerPhase != SchedulerPhase.transientCallbacks) {
      binding.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
          _scrollToBottom();
        }
      });
    } else {
      setState(() {});
      binding.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!scrollController.hasClients) {
      return;
    }
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final messages =
        widget.controller.messagesForThread(widget.conversation.threadId);
    return CupertinoPageScaffold(
      backgroundColor: AwikiMeColors.background,
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
                    final senderLabel = _displayNameForMessage(message);
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
                  await widget.controller.sendMessage(
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
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => PeerProfilePage(
            controller: widget.controller,
            did: widget.conversation.targetDid!,
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => GroupDetailPage(
          controller: widget.controller,
          initialGroup: _findCurrentGroup(),
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month-$day';
  }

  String _displayNameForMessage(ChatMessage message) {
    final senderName = message.senderName?.trim() ?? '';
    if (senderName.isNotEmpty) {
      return senderName;
    }
    final senderDid = message.senderDid.trim();
    if (!senderDid.startsWith('did:')) {
      return senderDid.isNotEmpty ? senderDid : 'Unknown';
    }
    final parts = senderDid.split(':');
    if (parts.length >= 2) {
      final candidate = parts[parts.length - 2];
      if (candidate.isNotEmpty && candidate != 'user') {
        return candidate;
      }
    }
    return parts.isNotEmpty ? parts.last : 'Unknown';
  }

  GroupSummary _findCurrentGroup() {
    for (final item in widget.controller.groups) {
      if (item.groupId == widget.conversation.groupId) {
        return item;
      }
    }
    return widget.controller.groups.isNotEmpty
        ? widget.controller.groups.first
        : throw StateError('Group not found');
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.onBack,
    required this.onDetails,
  });

  static final RegExp _didUserPattern = RegExp(r':(?:user:)?([^:]+):k1_');
  static final RegExp _didTailPattern = RegExp(r':([^:]+)$');

  final ConversationSummary conversation;
  final VoidCallback onBack;
  final VoidCallback onDetails;

  String _compactConversationName() {
    final displayName = conversation.displayName.trim();
    if (displayName.isNotEmpty && !displayName.startsWith('did:')) {
      return displayName;
    }

    final source = conversation.isGroup
        ? displayName
        : (conversation.targetDid?.trim().isNotEmpty == true
            ? conversation.targetDid!.trim()
            : displayName);

    final didMatch = _didUserPattern.firstMatch(source);
    if (didMatch != null) {
      return didMatch.group(1)!;
    }

    final tailMatch = _didTailPattern.firstMatch(source);
    if (tailMatch != null) {
      return tailMatch.group(1)!;
    }

    return source.isEmpty ? '未命名会话' : source;
  }

  @override
  Widget build(BuildContext context) {
    final compactName = _compactConversationName();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back,
                color: AwikiMeColors.primaryDark,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
          AvatarBadge(seed: compactName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  compactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AwikiMeColors.title,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 8,
                      height: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AwikiMeColors.online,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      conversation.isGroup ? 'GROUP' : 'ONLINE',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AwikiMeColors.primaryDark,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDetails,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.more_vert,
                color: AwikiMeColors.primaryDark,
                size: 20,
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AwikiMeColors.mutedSurface,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AwikiMeColors.primaryDark,
              letterSpacing: 1.1,
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
  });

  final ChatMessage message;
  final String senderLabel;

  @override
  Widget build(BuildContext context) {
    if (message.isMine) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 292),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(20, 15, 20, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF4D6),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.62,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _timeLabel(message.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AwikiMeColors.tertiaryText,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    message.sendState == MessageSendState.sent
                        ? Icons.done_all
                        : Icons.schedule,
                    size: 13,
                    color: AwikiMeColors.tertiaryText,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AvatarBadge(seed: senderLabel, size: 32),
        const SizedBox(width: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 292),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  senderLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AwikiMeColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                decoration: const BoxDecoration(
                  color: AwikiMeColors.mutedSurface,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Text(
                  message.content,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.62,
                    color: Color(0xFF000000),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _timeLabel(message.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AwikiMeColors.tertiaryText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _timeLabel(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          color: const Color(0xCCFFFFFF),
          child: SafeArea(
            top: false,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: AwikiMeColors.mutedSurface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: CupertinoTextField(
                      controller: controller,
                      placeholder: 'Type a message...',
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) async {
                        await onSend();
                      },
                      decoration: null,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onSend,
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.near_me_outlined,
                      color: AwikiMeColors.primary,
                      size: 24,
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
