import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent/acp_control_service.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../app_shell/providers/session_provider.dart';
import 'acp_session_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/app_dialog.dart';

part 'acp_action_button.dart';
part 'acp_question_form.dart';
part 'acp_session_options.dart';
part 'acp_question_fields.dart';

String acpText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

String acpRejectionText(
  BuildContext context,
  Object? reason,
) => switch (reason) {
  'group_busy' => acpText(
    context,
    '智能体正在此群执行任务，本条指令未执行。请稍后重新发送。',
    'The agent is busy in this group. This instruction did not run; send it again later.',
  ),
  'waiting_slot_full' => acpText(
    context,
    '等待位已满，本条指令未接受。请处理等待消息后重新发送。',
    'The waiting slot is full. Run or cancel the waiting message, then send this instruction again.',
  ),
  'context_reset_required' => acpText(
    context,
    '需要先重新建立上下文，本条指令未执行。',
    'Start a new context first. This instruction did not run.',
  ),
  'conversation_mismatch' => acpText(
    context,
    '会话状态不一致，本条指令未执行。请重新打开会话后再试。',
    'The conversation state changed. Reopen the conversation and send this instruction again.',
  ),
  _ => acpText(
    context,
    '指令未被接受，未自动重试。请检查智能体状态后重新发送。',
    'This instruction was not accepted or retried. Check the agent and send it again.',
  ),
};

String acpBlockText(
  BuildContext context,
  AcpSendBlock block,
) => switch (block) {
  AcpSendBlock.offline => acpText(
    context,
    '智能体所在设备离线，文字和附件已保留。',
    'The agent device is offline. Your text and attachments are kept.',
  ),
  AcpSendBlock.waitingFull => acpText(
    context,
    '已有一条等待消息，请先执行或取消；当前内容保留为草稿。',
    'One message is already waiting. Run or cancel it first; your draft is kept.',
  ),
  AcpSendBlock.groupBusy => acpText(
    context,
    '被提及的智能体正在此群执行任务，请稍后再试。',
    'The mentioned agent is busy in this group. Try again when it finishes.',
  ),
  AcpSendBlock.contextLost => acpText(
    context,
    '上下文无法恢复，请先确认重新开始。聊天记录会保留。',
    'The context could not be restored. Confirm a new start; chat history is retained.',
  ),
};

class AcpTaskStatus extends StatefulWidget {
  const AcpTaskStatus({
    super.key,
    required this.session,
    required this.task,
    required this.viewerDid,
    required this.alignEnd,
  });
  final AcpSession session;
  final Map<String, Object?> task;
  final String viewerDid;
  final bool alignEnd;
  @override
  State<AcpTaskStatus> createState() => _AcpTaskStatusState();
}

class _AcpTaskStatusState extends State<AcpTaskStatus> {
  bool _toolsExpanded = false;
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final task = widget.task;
    final state = task['state'];
    final active = task['run_id'] == session.active['run_id'];
    final label = switch (state) {
      'running' =>
        session.data['restoring'] == true
            ? acpText(context, '正在恢复上下文…', 'Restoring context…')
            : acpText(context, '正在执行', 'Running'),
      'stopping' => acpText(context, '正在停止…', 'Stopping…'),
      'waiting' => acpText(
        context,
        session.waitingPaused ? '等待中，需手动执行' : '等待上一任务完成',
        'Waiting${session.waitingPaused ? ' — run manually' : ''}',
      ),
      'cancelled' => acpText(context, '已取消', 'Cancelled'),
      'interrupted' => acpText(
        context,
        '任务已中断，未重新执行',
        'Interrupted; task was not rerun',
      ),
      'failed' => acpText(
        context,
        '执行失败，请检查智能体环境后重试',
        'Task failed. Check the agent environment before retrying.',
      ),
      _ => acpText(context, '已完成', 'Completed'),
    };
    return Align(
      alignment: widget.alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: widget.alignEnd
                    ? WrapAlignment.end
                    : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.start,
                spacing: 4,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      label,
                      key: ValueKey('acp-state:${task['run_id']}'),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: context.awikiTheme.secondaryText,
                      ),
                    ),
                  ),
                  if (!session.group && active && !session.stopping)
                    AcpActionButton(
                      session: session,
                      action: 'stop',
                      values: {'run_id': task['run_id']},
                      label: acpText(context, '停止', 'Stop'),
                    ),
                  if (!session.group && state == 'waiting') ...[
                    AcpActionButton(
                      session: session,
                      action: 'execute_waiting',
                      values: {'run_id': task['run_id']},
                      enabled: !session.stopping && !session.contextLost,
                      label: acpText(context, '执行', 'Run'),
                    ),
                    AcpActionButton(
                      session: session,
                      action: 'cancel_waiting',
                      values: {'run_id': task['run_id']},
                      label: acpText(context, '取消', 'Cancel'),
                    ),
                  ],
                ],
              ),
              if (active && session.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    session.text,
                    key: const Key('acp-stream-text'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: context.awikiTheme.body,
                    ),
                  ),
                ),
              if (active && session.tools.isNotEmpty) ...[
                CupertinoButton(
                  alignment: Alignment.centerLeft,
                  minimumSize: Size(
                    44,
                    context.awikiResponsive.isCompact ? 44 : 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      setState(() => _toolsExpanded = !_toolsExpanded),
                  child: Row(
                    children: [
                      Icon(
                        _toolsExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 12,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          acpText(
                            context,
                            '工具记录 (${session.tools.length})',
                            'Tools (${session.tools.length})',
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_toolsExpanded)
                  for (final tool in session.tools)
                    Padding(
                      padding: const EdgeInsets.only(left: 18, bottom: 6),
                      child: Text(
                        '${tool['title'] ?? tool['kind'] ?? ''} · ${tool['status'] ?? ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
              ],
              if (active)
                for (final question in session.questions)
                  AcpQuestionForm(
                    key: ValueKey(question['id']),
                    session: session,
                    question: question,
                    canAnswer:
                        session.active['requester_did'] == widget.viewerDid &&
                        !session.stopping,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
