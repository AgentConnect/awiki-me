import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conversation_summary.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../chat/chat_page.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import 'conversation_list_page.dart';

class ConversationWorkspacePage extends ConsumerWidget {
  const ConversationWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return const ConversationListPage();
    }

    final selectedConversation = ref.watch(selectedConversationProvider);
    if (responsive.isMacDesktop) {
      return _MacConversationWorkspace(
        selectedConversation: selectedConversation,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
        onClearSelection: () {
          ref.read(selectedConversationProvider.notifier).clearSelection();
        },
      );
    }
    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: ConversationListPage(
        embedded: true,
        selectedThreadId: selectedConversation?.threadId,
        bottomInset: listFooter == null ? 24 : 16,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
      ),
      detailPane: selectedConversation == null
          ? const AwikiWorkspaceEmptyDetail()
          : ChatView(
              conversation: selectedConversation,
              embedded: true,
              onBack: () {
                ref
                    .read(selectedConversationProvider.notifier)
                    .clearSelection();
              },
            ),
    );
  }
}

class _MacConversationWorkspace extends StatelessWidget {
  const _MacConversationWorkspace({
    required this.selectedConversation,
    required this.onConversationSelected,
    required this.onClearSelection,
  });

  final ConversationSummary? selectedConversation;
  final ConversationSelectionHandler onConversationSelected;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: CupertinoColors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 1200.0;
          final listWidth = _listPaneWidth(availableWidth);
          final detailWidth = _detailPaneWidth(availableWidth);
          final canShowIdentityPanel =
              selectedConversation != null &&
              availableWidth - listWidth - detailWidth - 3 >= 360;

          return Row(
            children: <Widget>[
              SizedBox(
                width: listWidth,
                child: ConversationListPage(
                  embedded: true,
                  macStyle: true,
                  selectedThreadId: selectedConversation?.threadId,
                  bottomInset: 18,
                  onConversationSelected: onConversationSelected,
                ),
              ),
              Container(width: 1, color: const Color(0xFFE5EAF2)),
              Expanded(
                child: selectedConversation == null
                    ? const AwikiWorkspaceEmptyDetail()
                    : ChatView(
                        conversation: selectedConversation!,
                        embedded: true,
                        macStyle: true,
                        onBack: onClearSelection,
                      ),
              ),
              if (canShowIdentityPanel) ...<Widget>[
                Container(width: 1, color: const Color(0xFFE5EAF2)),
                SizedBox(
                  width: detailWidth,
                  child: _MacAgentDetailPanel(
                    conversation: selectedConversation!,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  double _listPaneWidth(double availableWidth) {
    if (availableWidth < 560) {
      return 220;
    }
    if (availableWidth < 760) {
      return 260;
    }
    if (availableWidth < 980) {
      return 300;
    }
    return 340;
  }

  double _detailPaneWidth(double availableWidth) {
    if (availableWidth < 1180) {
      return 244;
    }
    return 270;
  }
}

class _MacAgentDetailPanel extends StatelessWidget {
  const _MacAgentDetailPanel({required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    final title = DidDisplayFormatter.conversationTitle(
      conversation,
      context.l10n,
    );
    final address = conversation.targetDid?.trim().isNotEmpty == true
        ? conversation.targetDid!.trim()
        : conversation.groupId ?? conversation.threadId;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: <Widget>[
            const Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Agent 身份卡',
                    style: TextStyle(
                      color: Color(0xFF101B32),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(CupertinoIcons.xmark, size: 18, color: Color(0xFF34415C)),
              ],
            ),
            const SizedBox(height: 26),
            const _MacDetailRow(
              label: '身份状态:',
              child: Row(
                children: <Widget>[
                  Icon(
                    CupertinoIcons.checkmark_shield_fill,
                    color: Color(0xFF17BF63),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    '已验证',
                    style: TextStyle(
                      color: Color(0xFF17BF63),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            _MacDetailRow(
              label: '所属:',
              text: conversation.isGroup ? 'AWiki 群组' : '$title 团队',
            ),
            _MacDetailRow(label: '地址:', text: address),
            _MacDetailRow(
              label: '类型:',
              text: conversation.isGroup ? 'Group Agent' : 'Personal Agent',
            ),
            const SizedBox(height: 20),
            const _MacDetailCard(
              title: '会话能力',
              children: <Widget>[
                _MacAbilityGridItem(
                  icon: CupertinoIcons.chat_bubble_text,
                  label: '发送消息',
                ),
                _MacAbilityGridItem(
                  icon: CupertinoIcons.person_crop_circle,
                  label: '查看资料',
                ),
                _MacAbilityGridItem(icon: CupertinoIcons.shield, label: '安全连接'),
                _MacAbilityGridItem(
                  icon: CupertinoIcons.doc_text,
                  label: '会话记录',
                ),
              ],
            ),
            const SizedBox(height: 18),
            _MacDetailCard(
              title: '会话状态',
              children: <Widget>[
                _MacStatusLine(
                  label: '未读消息:',
                  value: '${conversation.unreadCount} 条',
                  color: const Color(0xFF0B65F8),
                ),
                _MacStatusLine(
                  label: '最近预览:',
                  value: conversation.lastMessagePreview.trim().isEmpty
                      ? context.l10n.conversationsNoMessagePreview
                      : conversation.lastMessagePreview.trim(),
                  color: const Color(0xFF66728A),
                ),
                const _MacStatusLine(
                  label: '连接状态:',
                  value: '已建立',
                  color: Color(0xFF17BF63),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacDetailRow extends StatelessWidget {
  const _MacDetailRow({required this.label, this.text, this.child});

  final String label;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child:
                child ??
                Text(
                  text ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _MacDetailCard extends StatelessWidget {
  const _MacDetailCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF17213A),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
  }
}

class _MacAbilityGridItem extends StatelessWidget {
  const _MacAbilityGridItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: const Color(0xFF34415C)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF34415C),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MacStatusLine extends StatelessWidget {
  const _MacStatusLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF66728A), fontSize: 12),
              ),
            ),
            Icon(CupertinoIcons.circle_fill, color: color, size: 8),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: Color(0xFF17213A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
