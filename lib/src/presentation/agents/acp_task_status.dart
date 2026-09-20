import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/agent/acp_control_service.dart';
import '../../domain/entities/agent/acp_session.dart';
import '../app_shell/providers/session_provider.dart';
import 'acp_session_provider.dart';
import 'acp_model_controller.dart';
import 'acp_model_refresh_controller.dart';
import 'agents_provider.dart';
import 'acp_question_controller.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/app_dialog.dart';

part 'acp_action_button.dart';
part 'acp_question_form.dart';
part 'acp_session_options.dart';
part 'acp_context_recovery.dart';
part 'acp_model_bar.dart';
part 'acp_question_fields.dart';
part 'acp_question_history.dart';

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
  AcpSendBlock.modelChanging => acpText(
    context,
    '模型配置尚未确认，请等待完成或重试。文字和附件已保留。',
    'Model configuration is not confirmed yet. Wait or retry; your text and attachments are kept.',
  ),
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
  final AcpSession? session;
  final Map<String, Object?> task;
  final String viewerDid;
  final bool alignEnd;
  @override
  State<AcpTaskStatus> createState() => _AcpTaskStatusState();
}

class _AcpTaskStatusState extends State<AcpTaskStatus> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final task = widget.task;
    final state = task['state'];
    final active = task['run_id'] == session?.active['run_id'];
    final label = switch (state) {
      'running' =>
        session?.data['restoring'] == true
            ? acpText(context, '正在恢复上下文…', 'Restoring context…')
            : acpText(context, '正在执行', 'Running'),
      'stopping' => acpText(context, '正在停止…', 'Stopping…'),
      'waiting' || 'paused' => acpText(
        context,
        (session?.waitingPaused == true) ? '等待中，需手动执行' : '等待上一任务完成',
        'Waiting${(session?.waitingPaused == true) ? ' — run manually' : ''}',
      ),
      'cancelled' => acpText(context, '已取消', 'Cancelled'),
      'interrupted' => acpText(
        context,
        '任务已中断，未重新执行',
        'Interrupted; task was not rerun',
      ),
      'failed' => acpTaskFailureText(context, task),
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
                  if (session != null &&
                      !session.group &&
                      active &&
                      !session.stopping)
                    AcpActionButton(
                      session: session,
                      action: 'stop',
                      values: {'run_id': task['run_id']},
                      label: acpText(context, '停止', 'Stop'),
                    ),
                  if (session != null &&
                      !session.group &&
                      (state == 'waiting' || state == 'paused')) ...[
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
            ],
          ),
        ),
      ),
    );
  }
}

String acpTaskFailureText(BuildContext context, Map<String, Object?> task) {
  final details = acpMap(task['error_details']);
  final code = details['code'] ?? task['error_code'];
  return switch (code) {
    'model_configuration_failed' => acpText(
      context,
      '客户端未能恢复所选模型，本条指令未执行。请检查模型配置或选择其他模型。',
      'The client could not restore the selected model. This instruction did not run. Check its configuration or choose another model.',
    ),
    'attachment_permission_denied' => acpText(
      context,
      '无法读取附件，请检查文件访问权限',
      'The attachment could not be read. Check its access permissions.',
    ),
    'attachment_not_found' => acpText(
      context,
      '附件已不可用，请重新发送文件',
      'The attachment is unavailable. Send the file again.',
    ),
    'attachment_integrity_failed' ||
    'anp.attachment.digest_mismatch' => acpText(
      context,
      '附件校验失败，未交给智能体；请重新发送文件',
      'Attachment verification failed before the agent ran. Send the file again.',
    ),
    _
        when details['retryable'] == true &&
            code.toString().contains('attachment') =>
      acpText(
        context,
        '附件暂时下载失败，未交给智能体；请稍后重新发送',
        'Attachment download failed before the agent ran. Try sending it again later.',
      ),
    _ when code.toString().startsWith('attachment_') => acpText(
      context,
      '附件准备失败，未交给智能体；请检查文件后重新发送',
      'Attachment preparation failed before the agent ran. Check the file and send it again.',
    ),
    _ => acpText(
      context,
      '执行失败，请检查智能体环境后重试',
      'Task failed. Check the agent environment before retrying.',
    ),
  };
}
