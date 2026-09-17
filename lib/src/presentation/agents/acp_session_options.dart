part of 'acp_task_status.dart';

String _modelName(AcpSession session, BuildContext context) {
  final id = session.data['model_id'];
  for (final model in session.models) {
    if (model['id'] == id) return '${model['name'] ?? id}';
  }
  return id?.toString() ??
      acpText(context, '客户端未提供当前模型', 'Client did not report the current model');
}

class AcpSessionOptions extends ConsumerWidget {
  const AcpSessionOptions({super.key, required this.session});
  final AcpSession session;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.awikiTheme;
    if (!session.contextLost && session.group) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.contextLost)
            Container(
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
                    acpBlockText(context, AcpSendBlock.contextLost),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.body,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AcpActionButton(
                    session: session,
                    action: 'reset_context',
                    values: const {'confirmed': true},
                    enabled: !session.busy,
                    label: acpText(context, '重新开始', 'Start again'),
                    confirmation: acpText(
                      context,
                      '确认建立新的上下文？现有聊天记录将保留。',
                      'Start a new context? Existing chat history will be retained.',
                    ),
                  ),
                ],
              ),
            ),
          if (!session.group)
            _AcpModelOperationStatus(
              scope: (
                agentDid: session.agentDid,
                conversationId: session.conversationId,
              ),
            ),
          if (!session.group)
            Align(
              alignment: Alignment.centerLeft,
              child: CupertinoButton(
                key: const Key('acp-model-menu'),
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(vertical: 8),
                onPressed: session.models.isEmpty
                    ? null
                    : () {
                        final epoch = ref.read(sessionProvider).activeEpoch;
                        final projected = ref
                            .read(acpSessionsProvider)
                            .sessions
                            .containsKey(session.key);
                        showCupertinoModalPopup<void>(
                          context: context,
                          builder: (_) => _AcpModelPicker(
                            initial: session,
                            epoch: epoch,
                            wasProjected: projected,
                          ),
                        );
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.slider_horizontal_3,
                      size: 16,
                      color: theme.secondaryText,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _modelName(session, context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      CupertinoIcons.chevron_down,
                      size: 11,
                      color: theme.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AcpModelPicker extends ConsumerStatefulWidget {
  const _AcpModelPicker({
    required this.initial,
    required this.epoch,
    required this.wasProjected,
  });
  final AcpSession initial;
  final Object? epoch;
  final bool wasProjected;
  @override
  ConsumerState<_AcpModelPicker> createState() => _AcpModelPickerState();
}

class _AcpModelPickerState extends ConsumerState<_AcpModelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final projected = ref.watch(
      acpSessionsProvider.select((s) => s.sessions[widget.initial.key]),
    );
    final session = projected ?? widget.initial;
    final scope = (
      agentDid: session.agentDid,
      conversationId: session.conversationId,
    );
    final operation = ref.watch(acpModelControllerProvider(scope));
    final sameOwner =
        ref.watch(sessionProvider.select((s) => s.activeEpoch)) == widget.epoch;
    final available =
        sameOwner &&
        (!widget.wasProjected || projected != null) &&
        session.canSelectModel;
    final models = session.models
        .where(
          (m) => '${m['name'] ?? ''} ${m['id'] ?? ''} ${m['description'] ?? ''}'
              .toLowerCase()
              .contains(_query.toLowerCase()),
        )
        .toList();
    return AppDialogScaffold(
      key: const Key('acp-model-picker'),
      maxWidth: 520,
      avoidViewInsets: true,
      child: CustomScrollView(
        shrinkWrap: true,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDialogHeader(
                    title: acpText(context, '选择模型', 'Choose a model'),
                    subtitle: acpText(
                      context,
                      '仅用于当前会话',
                      'Applies to this conversation',
                    ),
                    onClose: () => Navigator.of(context).pop(),
                    closeLabel: acpText(context, '关闭', 'Close'),
                  ),
                  _AcpModelOperationStatus(scope: scope),
                  if (!available)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        !sameOwner
                            ? acpText(
                                context,
                                '身份已变化，请关闭此窗口。',
                                'Your identity changed. Close this window.',
                              )
                            : session.contextLost
                            ? acpText(
                                context,
                                '先确认重新开始，再切换模型。',
                                'Confirm a new context before changing models.',
                              )
                            : widget.wasProjected && projected == null
                            ? acpText(
                                context,
                                '会话状态已变化，请关闭后重试。',
                                'The conversation state changed. Close this window and try again.',
                              )
                            : acpText(
                                context,
                                '任务和等待消息处理完毕后，即可切换模型。',
                                'Finish the active and waiting tasks before changing models.',
                              ),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
                  if (session.models.length > 6)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: CupertinoSearchTextField(
                        enabled: !operation.blocksSending,
                        key: const Key('acp-model-search'),
                        placeholder: acpText(context, '搜索模型', 'Search models'),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (models.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  acpText(context, '没有匹配的模型', 'No matching models'),
                  style: TextStyle(fontSize: 14, color: theme.secondaryText),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            sliver: SliverList.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                final id = model['id']?.toString() ?? '';
                final selected = id == session.data['model_id'];
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CupertinoButton(
                    key: ValueKey('acp-model:$id'),
                    padding: EdgeInsets.zero,
                    onPressed:
                        available && id.isNotEmpty && !operation.blocksSending
                        ? () async {
                            final done = await ref
                                .read(
                                  acpModelControllerProvider(scope).notifier,
                                )
                                .select(session, id);
                            if (done &&
                                context.mounted &&
                                ref.read(sessionProvider).activeEpoch ==
                                    widget.epoch) {
                              Navigator.of(context).pop();
                            }
                          }
                        : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.primary.withValues(alpha: 0.08)
                            : theme.subtleSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? theme.primary.withValues(alpha: 0.35)
                              : theme.border,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${model['name'] ?? id}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                    color: theme.title,
                                  ),
                                ),
                                if (model['description'] is String &&
                                    (model['description']! as String)
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    model['description']! as String,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.5,
                                      color: theme.secondaryText,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            selected
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.circle,
                            size: 20,
                            color: selected ? theme.primary : theme.border,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
