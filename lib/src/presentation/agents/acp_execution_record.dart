import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/agent/acp_session.dart';
import '../../domain/entities/agent/acp_task.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
import 'acp_task_status.dart';

final _expandedRecordProvider = StateProvider.autoDispose.family<bool, String>((
  ref,
  key,
) {
  ref.watch(sessionProvider.select((s) => s.activeEpoch));
  return false;
});

/// Deterministic summary from protocol metadata; never renders raw arguments,
/// commands, URLs with credentials, or absolute host paths.
({String action, String? target, String status}) acpToolSummary(
  Map<String, Object?> tool, {
  required bool chinese,
  bool taskEnded = false,
}) {
  final kind = tool['kind']?.toString().toLowerCase() ?? '';
  final title = tool['title']?.toString() ?? '';
  final normalized = title.toLowerCase();
  final action = switch (kind) {
    'read' => chinese ? '读取文件' : 'Read file',
    'edit' => chinese ? '修改文件' : 'Edit file',
    'delete' => chinese ? '删除文件' : 'Delete file',
    'search' => chinese ? '搜索' : 'Search',
    'execute' => chinese ? '执行命令' : 'Run command',
    'fetch' => chinese ? '获取网页' : 'Fetch page',
    'think' => chinese ? '分析' : 'Analyze',
    'switch_mode' => chinese ? '切换模式' : 'Change mode',
    _
        when normalized.contains('request_user_input') ||
            normalized == 'question' =>
      chinese ? '向你提问' : 'Ask a question',
    _ when normalized == 'read' => chinese ? '读取文件' : 'Read file',
    _ when normalized.contains('search') => chinese ? '搜索' : 'Search',
    _ when normalized == 'shell' || normalized == 'bash' =>
      chinese ? '执行命令' : 'Run command',
    _ => chinese ? '调用工具' : 'Use tool',
  };
  final rawPath =
      tool['target']?.toString() ??
      ((title.startsWith('/') || title.startsWith('Users/')) ? title : '');
  final filename = rawPath.replaceAll('\\', '/').split('/').last;
  final safe =
      filename.isNotEmpty &&
      filename.length <= 100 &&
      !RegExp(
        r'[\x00-\x1f?=#]|sk-[a-zA-Z0-9]|(?:token|secret|password)\s*[:=]',
        caseSensitive: false,
      ).hasMatch(filename);
  final status = switch (tool['status']) {
    'completed' => chinese ? '已完成' : 'Completed',
    'failed' => chinese ? '失败' : 'Failed',
    'in_progress' || 'pending' when taskEnded => chinese ? '未完成' : 'Incomplete',
    'in_progress' => chinese ? '正在执行' : 'Running',
    'pending' => chinese ? '准备中' : 'Preparing',
    'cancelled' => chinese ? '已取消' : 'Cancelled',
    _ => chinese ? '已记录' : 'Recorded',
  };
  return (action: action, target: safe ? filename : null, status: status);
}

class AcpExecutionRecord extends ConsumerWidget {
  const AcpExecutionRecord({
    super.key,
    required this.task,
    required this.session,
    required this.viewerDid,
  });
  final AcpTask task;
  final AcpSession? session;
  final String viewerDid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(_expandedRecordProvider(task.key));
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final questions = task.questions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (task.tools.isNotEmpty || task.omittedToolCount > 0) ...[
          CupertinoButton(
            key: ValueKey('acp-record-toggle:${task.runId}'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.centerLeft,
            minimumSize: const Size(44, 32),
            onPressed: () =>
                ref.read(_expandedRecordProvider(task.key).notifier).state =
                    !expanded,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  expanded
                      ? CupertinoIcons.chevron_down
                      : CupertinoIcons.chevron_right,
                  size: 12,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    acpText(
                      context,
                      '执行记录（${task.tools.length + task.omittedToolCount}）',
                      'Activity (${task.tools.length + task.omittedToolCount})',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            for (final tool in task.tools)
              Builder(
                builder: (context) {
                  final summary = acpToolSummary(
                    tool,
                    chinese: chinese,
                    taskEnded: task.terminal,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(left: 18, bottom: 6),
                    child: Text(
                      [
                        summary.action,
                        if (summary.target != null) summary.target!,
                        summary.status,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: context.awikiTheme.secondaryText,
                      ),
                    ),
                  );
                },
              ),
            if (task.omittedToolCount > 0)
              Text(
                acpText(
                  context,
                  '另有 ${task.omittedToolCount} 条较早记录未展开保存',
                  '${task.omittedToolCount} earlier details were omitted',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: context.awikiTheme.secondaryText,
                ),
              ),
          ],
        ],
        for (final question in questions)
          if (session != null &&
              task.running &&
              question['response'] == null &&
              (question['status'] == null || question['status'] == 'pending'))
            AcpPendingQuestion(
              key: ValueKey('pending:${question['id']}'),
              question: question,
              initiallyExpanded:
                  question ==
                  questions.firstWhere(
                    (q) =>
                        q['response'] == null &&
                        (q['status'] == null || q['status'] == 'pending'),
                  ),
              child: AcpQuestionForm(
                key: ValueKey(question['id']),
                session: session!,
                question: question,
                canAnswer: task.requesterDid == viewerDid && !session!.stopping,
              ),
            )
          else
            AcpQuestionHistory(
              key: ValueKey('history:${question['id']}'),
              question: question,
              taskState: task.state,
            ),
      ],
    );
  }
}
