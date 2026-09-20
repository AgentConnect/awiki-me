part of '../chat_page.dart';

/// A presentation of an execution record, never inserted into Core history.
class _AcpReplyPreview extends StatelessWidget {
  const _AcpReplyPreview({
    required this.task,
    required this.session,
    required this.conversation,
    required this.mentionPresentation,
    required this.senderLabel,
    required this.avatarUri,
    required this.viewerDid,
    required this.macStyle,
    this.sourceUnavailable = false,
  });
  final AcpTask task;
  final AcpSession? session;
  final ConversationSummary conversation;
  final ChatMentionPresentationResolver mentionPresentation;
  final String senderLabel;
  final String? avatarUri;
  final String viewerDid;
  final bool macStyle;
  final bool sourceUnavailable;

  @override
  Widget build(BuildContext context) {
    if (task.text.isEmpty && task.tools.isEmpty && task.questions.isEmpty) {
      return const SizedBox.shrink();
    }
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final incomplete = task.terminal && task.state != 'finished';
    return Padding(
      key: ValueKey('acp-reply:${task.runId}'),
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth * (macStyle ? 0.68 : 0.72)
              : 420.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: conversation.isGroup ? responsive.displayScaled(19) : 0,
                ),
                child: _MessageAvatar(
                  messageId: 'acp:${task.runId}',
                  label: senderLabel,
                  avatarUri: avatarUri,
                  isMine: false,
                  size: responsive.displayScaled(macStyle ? 30 : 32),
                ),
              ),
              SizedBox(
                width: macStyle
                    ? responsive.displayScaled(8)
                    : responsive.spacing(8),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (conversation.isGroup)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            senderLabel,
                            style: TextStyle(
                              fontSize: responsive.metaSm,
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                      if (sourceUnavailable)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            acpText(
                              context,
                              '原指令不在当前消息记录中',
                              'The original request is outside this message history',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                      AcpExecutionRecord(
                        task: task,
                        session: session,
                        viewerDid: viewerDid,
                      ),
                      if (task.text.isNotEmpty)
                        _MessageBubbleSurface(
                          key: ValueKey('acp-reply-bubble:${task.runId}'),
                          maxWidth: maxWidth,
                          isMine: false,
                          hasAttachment: false,
                          macStyle: macStyle,
                          child: _MessageSelectableContent(
                            key: ValueKey('acp-stream-text:${task.runId}'),
                            conversation: conversation,
                            text: task.text,
                            child: _MessageTextContent(
                              text: task.text,
                              mentions: const [],
                              payloadJson: null,
                              mentionPresentation: mentionPresentation,
                              style: TextStyle(
                                color: theme.title,
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                height: 1.45,
                              ),
                              renderMarkdown: true,
                            ),
                          ),
                        ),
                      if (incomplete && task.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            acpText(context, '未完成', 'Incomplete'),
                            key: ValueKey('acp-incomplete:${task.runId}'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                      if (task.state == 'finished' &&
                          task.delivery['state'] == 'failed')
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            acpText(
                              context,
                              '回复投递失败，执行结果已保留',
                              'Reply delivery failed; the execution result is kept',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.secondaryText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
