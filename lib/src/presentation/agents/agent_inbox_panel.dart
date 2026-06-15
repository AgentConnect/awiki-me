import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/conversation_summary.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'agent_inbox_provider.dart';
import 'agents_provider.dart';

class AgentInboxPage extends StatelessWidget {
  const AgentInboxPage({super.key, required this.conversation});

  final ConversationSummary conversation;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF8FAFD),
      child: AgentInboxPanel(
        conversation: conversation,
        useBackButton: true,
        onClose: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class AgentInboxPanel extends ConsumerStatefulWidget {
  const AgentInboxPanel({
    super.key,
    required this.conversation,
    required this.onClose,
    this.useBackButton = false,
  });

  final ConversationSummary conversation;
  final VoidCallback onClose;
  final bool useBackButton;

  @override
  ConsumerState<AgentInboxPanel> createState() => _AgentInboxPanelState();
}

class _AgentInboxPanelState extends ConsumerState<AgentInboxPanel> {
  bool _didInitialQuery = false;

  @override
  void didUpdateWidget(covariant AgentInboxPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.threadId != widget.conversation.threadId) {
      _didInitialQuery = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtimeAgent();
    final daemonDid = runtime?.daemonAgentDid?.trim();
    final state = ref.watch(agentInboxProvider);
    if (runtime != null && daemonDid != null && daemonDid.isNotEmpty) {
      _requestInitial(runtime, daemonDid);
    }
    final stateMatchesRuntime =
        runtime != null && state.runtimeAgentDid == runtime.agentDid;
    final inThread = stateMatchesRuntime && state.thread.threadId != null;
    return _AgentInboxShell(
      title: inThread ? state.thread.title ?? '收件箱线程' : 'Agent 收件箱',
      onClose: inThread ? _closeThread : widget.onClose,
      closeIcon: inThread || widget.useBackButton
          ? CupertinoIcons.chevron_left
          : CupertinoIcons.xmark,
      closeButtonKey: inThread
          ? const Key('mac-agent-inbox-thread-back-button')
          : const Key('mac-agent-inbox-close-button'),
      closeSemanticLabel: inThread
          ? '返回收件箱'
          : (widget.useBackButton ? '返回会话' : '关闭 Agent 收件箱'),
      closeButtonLeading: inThread || widget.useBackButton,
      child: runtime == null
          ? const Center(
              child: Text(
                '当前会话不是 Runtime Agent 会话',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              ),
            )
          : daemonDid == null || daemonDid.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '这个 Runtime Agent 暂时没有绑定 Daemon',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                ),
              ),
            )
          : !stateMatchesRuntime
          ? const Center(child: CupertinoActivityIndicator())
          : inThread
          ? _AgentInboxThreadView(
              state: state.thread,
              onRefresh: () => _refreshThread(runtime, daemonDid),
              onLoadMore: () {
                ref.read(agentInboxProvider.notifier).loadMoreThread();
              },
            )
          : _AgentInboxListView(
              state: state,
              onScopeChanged: (scope) {
                ref
                    .read(agentInboxProvider.notifier)
                    .queryInbox(
                      daemonAgentDid: daemonDid,
                      runtimeAgentDid: runtime.agentDid,
                      scope: scope,
                      refresh: true,
                    );
              },
              onRefresh: () {
                ref
                    .read(agentInboxProvider.notifier)
                    .queryInbox(
                      daemonAgentDid: daemonDid,
                      runtimeAgentDid: runtime.agentDid,
                      scope: state.scope,
                      refresh: true,
                    );
              },
              onLoadMore: () {
                ref.read(agentInboxProvider.notifier).loadMoreInbox();
              },
              onOpenItem: (item) {
                ref
                    .read(agentInboxProvider.notifier)
                    .queryThread(
                      daemonAgentDid: daemonDid,
                      runtimeAgentDid: runtime.agentDid,
                      item: item,
                    );
              },
            ),
    );
  }

  void _requestInitial(AgentSummary runtime, String daemonDid) {
    if (_didInitialQuery) {
      return;
    }
    _didInitialQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(agentInboxProvider.notifier)
          .queryInbox(
            daemonAgentDid: daemonDid,
            runtimeAgentDid: runtime.agentDid,
          );
    });
  }

  void _refreshThread(AgentSummary runtime, String daemonDid) {
    final state = ref.read(agentInboxProvider);
    final item = state.items.firstWhere(
      (candidate) => candidate.threadId == state.thread.threadId,
      orElse: () => AgentInboxItem(
        threadId: state.thread.threadId ?? '',
        kind: state.thread.kind ?? 'direct',
        title: state.thread.title ?? '收件箱线程',
        lastMessagePreview: '',
        unreadCount: 0,
        hasAttachments: false,
        lastContentType: 'text',
      ),
    );
    ref
        .read(agentInboxProvider.notifier)
        .queryThread(
          daemonAgentDid: daemonDid,
          runtimeAgentDid: runtime.agentDid,
          item: item,
          refresh: true,
        );
  }

  void _closeThread() {
    ref.read(agentInboxProvider.notifier).closeThread();
  }

  AgentSummary? _runtimeAgent() {
    final targetDid = widget.conversation.targetDid?.trim();
    if (targetDid == null || targetDid.isEmpty || widget.conversation.isGroup) {
      return null;
    }
    for (final agent in ref.watch(agentsProvider).agents) {
      if (agent.isRuntime && agent.agentDid == targetDid) {
        return agent;
      }
    }
    return null;
  }
}

class _AgentInboxListView extends StatelessWidget {
  const _AgentInboxListView({
    required this.state,
    required this.onScopeChanged,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpenItem,
  });

  final AgentInboxState state;
  final ValueChanged<AgentInboxScope> onScopeChanged;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<AgentInboxItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final hasItems = state.items.isNotEmpty;
    final showBlockingLoading = state.isLoading && !hasItems;
    final showBlockingError = state.error != null && !hasItems;
    final showInlineError =
        state.error != null && hasItems && !state.hasListTimeout;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: _AgentInboxScopeControl(
                  scope: state.scope,
                  onChanged: onScopeChanged,
                ),
              ),
              const SizedBox(width: 12),
              _AgentInboxIconButton(
                key: const Key('mac-agent-inbox-refresh-button'),
                semanticLabel: '刷新 Agent 收件箱',
                icon: CupertinoIcons.refresh,
                isLoading: state.isRefreshing,
                onTap: state.isRefreshing ? null : onRefresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: showBlockingLoading
              ? const Center(child: CupertinoActivityIndicator())
              : showBlockingError
              ? _AgentInboxError(message: state.error!, onRetry: onRefresh)
              : !hasItems
              ? const Center(
                  child: Text(
                    '这个 Agent 暂时没有收件箱消息',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                  children: <Widget>[
                    if (showInlineError) ...<Widget>[
                      _AgentInboxInlineError(
                        message: state.error!,
                        onRetry: onRefresh,
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (var index = 0; index < state.items.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == state.items.length - 1 ? 0 : 8,
                        ),
                        child: _AgentInboxRow(
                          item: state.items[index],
                          onTap: () => onOpenItem(state.items[index]),
                        ),
                      ),
                    if (state.nextCursor != null) ...<Widget>[
                      if (state.items.isNotEmpty) const SizedBox(height: 8),
                      _LoadMoreButton(
                        label: '加载更多会话',
                        isLoading: state.isRefreshing,
                        onTap: state.isRefreshing ? null : onLoadMore,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AgentInboxScopeControl extends StatelessWidget {
  const _AgentInboxScopeControl({required this.scope, required this.onChanged});

  final AgentInboxScope scope;
  final ValueChanged<AgentInboxScope> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ScopeButton(
          label: '全部',
          selected: scope == AgentInboxScope.all,
          onTap: () => onChanged(AgentInboxScope.all),
        ),
        const SizedBox(width: 8),
        _ScopeButton(
          label: '私聊',
          selected: scope == AgentInboxScope.direct,
          onTap: () => onChanged(AgentInboxScope.direct),
        ),
        const SizedBox(width: 8),
        _ScopeButton(
          label: '群聊',
          selected: scope == AgentInboxScope.group,
          onTap: () => onChanged(AgentInboxScope.group),
        ),
      ],
    );
  }
}

class _ScopeButton extends StatelessWidget {
  const _ScopeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE4ECF7) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? const Color(0xFFB8C8E4) : const Color(0xFFDDE5F0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF44506A),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentInboxRow extends StatelessWidget {
  const _AgentInboxRow({required this.item, required this.onTap});

  final AgentInboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = item.kind == 'group';
    final timeLabel = _formatInboxTimestamp(item.lastMessageAtMs);
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: item.title,
      borderRadius: BorderRadius.circular(8),
      backgroundColor: CupertinoColors.white,
      border: Border.all(color: const Color(0xFFE5EAF2)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isGroup
                    ? const Color(0xFFEAF8EF)
                    : const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isGroup ? CupertinoIcons.person_2 : CupertinoIcons.person,
                color: isGroup
                    ? const Color(0xFF10A85A)
                    : const Color(0xFF0B65F8),
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF17213A),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (timeLabel != null) ...<Widget>[
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8A94A8),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      if (item.hasAttachments) ...<Widget>[
                        const Icon(
                          CupertinoIcons.paperclip,
                          size: 12,
                          color: Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          item.lastMessagePreview.isEmpty
                              ? (item.hasAttachments ? '最新：附件' : '最新：无预览')
                              : '最新：${item.lastMessagePreview}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (item.unreadCount > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 22),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  item.unreadCount > 99 ? '99+' : item.unreadCount.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 11,
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

class _AgentInboxThreadView extends StatelessWidget {
  const _AgentInboxThreadView({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
  });

  final AgentInboxThreadState state;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final hasMessages = state.messages.isNotEmpty;
    final showBlockingLoading = state.isLoading && !hasMessages;
    final showBlockingError = state.error != null && !hasMessages;
    final showInlineError =
        state.error != null && hasMessages && !state.hasTimeout;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
          child: Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '只读收件箱',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _AgentInboxIconButton(
                key: const Key('mac-agent-inbox-thread-refresh-button'),
                semanticLabel: '刷新收件箱线程',
                icon: CupertinoIcons.refresh,
                isLoading: state.isRefreshing,
                onTap: state.isRefreshing ? null : onRefresh,
              ),
            ],
          ),
        ),
        Expanded(
          child: showBlockingLoading
              ? const Center(child: CupertinoActivityIndicator())
              : showBlockingError
              ? _AgentInboxError(message: state.error!, onRetry: onRefresh)
              : !hasMessages
              ? const Center(
                  child: Text(
                    '这个线程暂时没有消息',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  children: <Widget>[
                    if (showInlineError) ...<Widget>[
                      _AgentInboxInlineError(
                        message: state.error!,
                        onRetry: onRefresh,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (state.nextCursor != null) ...<Widget>[
                      _LoadMoreButton(
                        label: '加载更早消息',
                        isLoading: state.isRefreshing,
                        onTap: state.isRefreshing ? null : onLoadMore,
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (var index = 0; index < state.messages.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == state.messages.length - 1 ? 0 : 8,
                        ),
                        child: _AgentInboxMessageRow(
                          message: state.messages[index],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AgentInboxMessageRow extends StatelessWidget {
  const _AgentInboxMessageRow({required this.message});

  final AgentInboxMessage message;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == 'outgoing';
    final visibleAttachments = message.attachments;
    final timeLabel = _formatInboxTimestamp(message.sentAtMs);
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: outgoing ? const Color(0xFFEAF2FF) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5EAF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    outgoing
                        ? 'Agent'
                        : message.senderHandle ??
                              DidDisplayFormatter.compactDid(message.senderDid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5A6478),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (timeLabel != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Text(
                    timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A94A8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            if (message.text.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                message.text,
                style: const TextStyle(
                  color: Color(0xFF17213A),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            if (message.truncated) ...<Widget>[
              const SizedBox(height: 6),
              const Text(
                '内容较长，已截断',
                style: TextStyle(color: Color(0xFF8A94A8), fontSize: 11),
              ),
            ],
            if (visibleAttachments.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              ...visibleAttachments.map(_AgentInboxAttachmentRow.new),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentInboxAttachmentRow extends StatelessWidget {
  const _AgentInboxAttachmentRow(this.attachment);

  final AgentInboxAttachment attachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            CupertinoIcons.paperclip,
            size: 15,
            color: Color(0xFF44506A),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _attachmentSubtitle(attachment),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreButton extends StatelessWidget {
  const _LoadMoreButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: isLoading ? null : onTap,
      semanticLabel: label,
      tooltip: label,
      enabled: !isLoading && onTap != null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: isLoading
            ? const CupertinoActivityIndicator()
            : Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B65F8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

class _AgentInboxError extends StatelessWidget {
  const _AgentInboxError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: AwikiMeErrorNotice(
          message: message,
          center: true,
          compact: true,
          trailing: AppPressable(
            onTap: onRetry,
            semanticLabel: '重试',
            tooltip: '重试',
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0B65F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '重试',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentInboxInlineError extends StatelessWidget {
  const _AgentInboxInlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AwikiMeErrorNotice(
      message: message,
      compact: true,
      trailing: AppPressable(
        onTap: onRetry,
        semanticLabel: '重试',
        tooltip: '重试',
        borderRadius: BorderRadius.circular(7),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '重试',
            style: TextStyle(
              color: Color(0xFF0B65F8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentInboxShell extends StatelessWidget {
  const _AgentInboxShell({
    required this.title,
    required this.onClose,
    required this.child,
    this.closeIcon,
    this.closeButtonKey,
    this.closeSemanticLabel = '关闭 Agent 收件箱',
    this.closeButtonLeading = false,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final IconData? closeIcon;
  final Key? closeButtonKey;
  final String closeSemanticLabel;
  final bool closeButtonLeading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Container(
              height: 60,
              padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE5EAF2))),
              ),
              child: Row(
                children: <Widget>[
                  if (closeButtonLeading) ...<Widget>[
                    _AgentInboxIconButton(
                      key:
                          closeButtonKey ??
                          const Key('agent-inbox-panel-close-button'),
                      semanticLabel: closeSemanticLabel,
                      icon: closeIcon ?? CupertinoIcons.xmark,
                      onTap: onClose,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF101B32),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!closeButtonLeading)
                    _AgentInboxIconButton(
                      key:
                          closeButtonKey ??
                          const Key('agent-inbox-panel-close-button'),
                      semanticLabel: closeSemanticLabel,
                      icon: closeIcon ?? CupertinoIcons.xmark,
                      onTap: onClose,
                    ),
                ],
              ),
            ),
            Expanded(child: SelectionArea(child: child)),
          ],
        ),
      ),
    );
  }
}

class _AgentInboxIconButton extends StatelessWidget {
  const _AgentInboxIconButton({
    super.key,
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppIconButton(
      onPressed: isLoading ? null : onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      isLoading: isLoading,
      size: responsive.displayScaled(32),
      backgroundColor: CupertinoColors.white,
      borderColor: const Color(0xFFDDE5F0),
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      child: Icon(
        icon,
        color: const Color(0xFF34415C),
        size: responsive.displayScaled(16),
      ),
    );
  }
}

String _attachmentSubtitle(AgentInboxAttachment attachment) {
  final size = attachment.sizeBytes;
  final sizeText = size == null ? null : _formatBytes(size);
  if (sizeText == null) {
    return attachment.mimeType;
  }
  return '${attachment.mimeType} · $sizeText';
}

String? _formatInboxTimestamp(int? epochMs) {
  if (epochMs == null || epochMs <= 0) {
    return null;
  }
  final date = DateTime.fromMillisecondsSinceEpoch(
    epochMs,
    isUtc: true,
  ).toLocal();
  final now = DateTime.now();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '$hour:$minute';
  }
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  if (date.year == now.year) {
    return '$month-$day $hour:$minute';
  }
  return '${date.year}-$month-$day $hour:$minute';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}
