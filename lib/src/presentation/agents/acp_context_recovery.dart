part of 'acp_task_status.dart';

/// Context recovery is available independently of model selection, including
/// group sessions. Inventory gates the affordance; the Daemon authorizes it.
class AcpContextRecovery extends StatelessWidget {
  const AcpContextRecovery({
    super.key,
    required this.session,
    this.agentName,
    this.canControl = true,
    this.online = true,
  });
  final AcpSession session;
  final String? agentName;
  final bool canControl;
  final bool online;

  @override
  Widget build(BuildContext context) {
    if (!session.contextLost) return const SizedBox.shrink();
    final theme = context.awikiTheme;
    final name = agentName ?? acpText(context, '智能体', 'Agent');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.group
                ? acpText(
                    context,
                    '$name 在本群的上下文无法恢复。聊天记录会保留。',
                    '$name could not restore its context in this group. Chat history is retained.',
                  )
                : acpBlockText(context, AcpSendBlock.contextLost),
            style: TextStyle(fontSize: 13, height: 1.5, color: theme.body),
          ),
          if (!canControl)
            Text(
              acpText(
                context,
                '请联系该智能体的控制者重新开始。',
                'Ask this agent’s controller to start a new context.',
              ),
            )
          else ...[
            const SizedBox(height: 8),
            AcpActionButton(
              key: ValueKey('acp-reset-action:${session.key}'),
              session: session,
              action: 'reset_context',
              values: const {'confirmed': true},
              enabled: online && !session.busy,
              label: acpText(context, '重新开始', 'Start again'),
              confirmation: session.group
                  ? acpText(
                      context,
                      '确认重新开始 $name 在本群的上下文？聊天记录将保留，旧指令不会自动重跑。',
                      'Start a new context for $name in this group? Chat history is retained; previous instructions will not run again.',
                    )
                  : acpText(
                      context,
                      '确认建立新的上下文？现有聊天记录将保留。',
                      'Start a new context? Existing chat history will be retained.',
                    ),
            ),
            if (!online)
              Text(
                acpText(
                  context,
                  '智能体所在设备离线，恢复连接后可重试。',
                  'The agent device is offline. Retry when it reconnects.',
                ),
              ),
          ],
        ],
      ),
    );
  }
}
