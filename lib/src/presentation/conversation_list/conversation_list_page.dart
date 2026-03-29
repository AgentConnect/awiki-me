import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../../core/date_time_formatter.dart';
import '../../domain/entities/conversation_summary.dart';
import '../app_shell/app_controller.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';

class ConversationListPage extends StatelessWidget {
  const ConversationListPage({
    super.key,
    required this.controller,
    required this.onOpenChat,
    required this.onOpenSettings,
    required this.onOpenQuickActions,
  });

  final AppController controller;
  final Future<void> Function(ConversationSummary conversation) onOpenChat;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenQuickActions;

  static final RegExp _didUserPattern = RegExp(r':(?:user:)?([^:]+):k1_');
  static final RegExp _didTailPattern = RegExp(r':([^:]+)$');

  String _compactUserName(ConversationSummary item) {
    final displayName = item.displayName.trim();
    if (displayName.isNotEmpty && !displayName.startsWith('did:')) {
      return displayName;
    }
    final source =
        item.targetDid?.isNotEmpty == true ? item.targetDid! : item.displayName;
    final didMatch = _didUserPattern.firstMatch(source);
    if (didMatch != null) {
      return didMatch.group(1)!;
    }
    final tailMatch = _didTailPattern.firstMatch(source);
    if (tailMatch != null) {
      return tailMatch.group(1)!;
    }
    return source;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          child: AwikiMeTopBar(
            title: '信息',
            padding: EdgeInsets.zero,
            leading: GestureDetector(
              onTap: onOpenSettings,
              child: const Icon(
                Icons.settings_outlined,
                size: 24,
                color: AwikiMeColors.title,
              ),
            ),
            trailing: GestureDetector(
              onTap: onOpenQuickActions,
              child: const Icon(
                Icons.add,
                size: 26,
                color: AwikiMeColors.title,
              ),
            ),
          ),
        ),
        Expanded(
          child: controller.conversations.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  itemCount: controller.conversations.length,
                  itemBuilder: (_, index) {
                    final item = controller.conversations[index];
                    return _ConversationRow(
                      title: _compactUserName(item),
                      preview: item.lastMessagePreview,
                      timeLabel: DateTimeFormatter.conversationTime(
                          item.lastMessageAt),
                      unreadCount: item.unreadCount,
                      onTap: () => onOpenChat(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.unreadCount,
    required this.onTap,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFF3F4F6)),
            ),
          ),
          child: Row(
            children: <Widget>[
              AvatarBadge(seed: title, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AwikiMeTextStyles.cardTitle.copyWith(
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: AwikiMeTextStyles.meta.copyWith(
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            preview.isEmpty ? '暂无消息' : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AwikiMeTextStyles.cardSubtitle.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AwikiMeColors.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unreadCount > 999 ? '999+' : '$unreadCount',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AwikiMeColors.surface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AwikiMeDecorations.card(color: AwikiMeColors.subtleSurface),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('还没有消息', style: AwikiMeTextStyles.sectionTitle),
              SizedBox(height: 8),
              Text(
                '去添加好友、关注联系人，或者先加入一个群聊吧。',
                style: AwikiMeTextStyles.cardSubtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
