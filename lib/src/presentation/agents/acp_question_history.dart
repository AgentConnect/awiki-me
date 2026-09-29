part of 'acp_task_status.dart';

/// A compact, read-only projection of the answer actually accepted by Daemon.
/// Unsubmitted local text is never included in this shared history.
class AcpQuestionHistory extends StatefulWidget {
  const AcpQuestionHistory({
    super.key,
    required this.question,
    required this.taskState,
  });
  final Map<String, Object?> question;
  final String taskState;
  @override
  State<AcpQuestionHistory> createState() => _AcpQuestionHistoryState();
}

class _AcpQuestionHistoryState extends State<AcpQuestionHistory> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final request = acpMap(question['request']);
    final response = acpMap(question['response']);
    final ended = {
      'cancelled',
      'interrupted',
      'failed',
    }.contains(widget.taskState);
    final label = switch (question['status']) {
      'answered' => acpText(
        context,
        ended ? '回答已接收，任务未完成' : '回答已接收',
        ended ? 'Answer received; task unfinished' : 'Answer received',
      ),
      'skipped' || 'declined' => acpText(context, '已跳过此问题', 'Question skipped'),
      'expired' => acpText(context, '问题已过期', 'Question expired'),
      _ => acpText(context, '问题已结束', 'Question closed'),
    };
    final theme = context.awikiTheme;
    final properties = acpMap(acpMap(request['requestedSchema'])['properties']);
    String display(Object? value, Map<String, Object?> property) {
      if (value is List) {
        return value.map((v) => display(v, property)).join('、');
      }
      for (final option in _questionOptions(property)) {
        if (option['const'] == value) return '${option['title'] ?? value}';
      }
      if (value is bool) {
        return value
            ? acpText(context, '是', 'Yes')
            : acpText(context, '否', 'No');
      }
      return value?.toString() ?? '';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoButton(
          key: ValueKey('acp-question-history:${question['id']}'),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 6),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 12,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 18, bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['message']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: theme.title,
                  ),
                ),
                for (final entry in acpMap(response['content']).entries)
                  SelectableText(
                    '${acpMap(properties[entry.key])['title'] ?? entry.key}：${display(entry.value, acpMap(properties[entry.key]))}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.body,
                    ),
                  ),
                if (response['text'] is String)
                  SelectableText(
                    response['text'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.body,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class AcpPendingQuestion extends StatefulWidget {
  const AcpPendingQuestion({
    super.key,
    required this.question,
    required this.initiallyExpanded,
    required this.child,
  });
  final Map<String, Object?> question;
  final bool initiallyExpanded;
  final Widget child;
  @override
  State<AcpPendingQuestion> createState() => _AcpPendingQuestionState();
}

class _AcpPendingQuestionState extends State<AcpPendingQuestion> {
  late bool _expanded = widget.initiallyExpanded;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CupertinoButton(
        key: ValueKey('acp-question-toggle:${widget.question['id']}'),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(vertical: 6),
        onPressed: () => setState(() => _expanded = !_expanded),
        child: Row(
          children: [
            Icon(
              _expanded
                  ? CupertinoIcons.chevron_down
                  : CupertinoIcons.chevron_right,
              size: 12,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                acpMap(widget.question['request'])['message']?.toString() ??
                    acpText(context, '等待回答', 'Awaiting answer'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
      if (_expanded) widget.child,
    ],
  );
}
