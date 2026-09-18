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
  const AcpSessionOptions({
    super.key,
    required this.session,
    this.online = true,
  });
  final AcpSession session;
  final bool online;
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
            AcpContextRecovery(session: session, online: online),
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
                onPressed: () {
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
                      online: online,
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
                        acpText(context, '会话模型 · ', 'Session model · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.secondaryText,
                        ),
                      ),
                    ),
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
    required this.online,
  });
  final AcpSession initial;
  final Object? epoch;
  final bool wasProjected;
  final bool online;
  @override
  ConsumerState<_AcpModelPicker> createState() => _AcpModelPickerState();
}

class _AcpModelPickerState extends ConsumerState<_AcpModelPicker> {
  String _query = '';
  bool? _automaticPending;
  bool _scheduled = false;
  bool _sawUnavailable = false;
  int? _deferredRevision;
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleRefresh(
    AcpSession session,
    bool available,
    AcpModelScope scope,
    AcpModelRefreshState refresh,
  ) {
    _automaticPending ??= !session.modelCatalogIsFresh(DateTime.now());
    if (!available) _sawUnavailable = true;
    if (_automaticPending != true ||
        !available ||
        !session.modelRefreshSupported ||
        refresh.pending ||
        _scheduled ||
        _retryTimer != null ||
        (_deferredRevision == session.revision && !_sawUnavailable)) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || ref.read(sessionProvider).activeEpoch != widget.epoch) {
        return;
      }
      unawaited(_refresh(session, scope));
    });
  }

  Future<void> _refresh(AcpSession session, AcpModelScope scope) async {
    _automaticPending = false;
    _sawUnavailable = false;
    _deferredRevision = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await ref
        .read(acpModelRefreshControllerProvider(scope).notifier)
        .refresh(session);
    if (!mounted || ref.read(sessionProvider).activeEpoch != widget.epoch) {
      return;
    }
    final result = ref.read(acpModelRefreshControllerProvider(scope));
    if (result.phase == AcpModelRefreshPhase.deferred) {
      _automaticPending = true;
      _deferredRevision = session.revision;
      if (result.retryAfter != null) {
        _retryTimer = Timer(result.retryAfter!, () {
          _retryTimer = null;
          if (mounted) setState(() => _deferredRevision = null);
        });
      }
    }
    setState(() {});
  }

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
    final refresh = ref.watch(acpModelRefreshControllerProvider(scope));
    final inventory = ref.watch(agentsProvider.select((s) => s.agents));
    final agent = inventory
        .where((a) => a.agentDid == session.agentDid)
        .firstOrNull;
    final daemon = inventory
        .where((a) => a.isDaemon && a.agentDid == agent?.daemonAgentDid)
        .firstOrNull;
    final online = daemon == null
        ? widget.online
        : (daemon.daemonEffectiveStatus?.primaryStatus ??
                  daemon.latest.status) !=
              'offline';
    final sameOwner =
        ref.watch(sessionProvider.select((s) => s.activeEpoch)) == widget.epoch;
    final available =
        sameOwner &&
        online &&
        (!widget.wasProjected || projected != null) &&
        session.canSelectModel;
    _scheduleRefresh(
      session,
      available && !operation.blocksSending,
      scope,
      refresh,
    );
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
                    title: acpText(context, '会话模型', 'Session model'),
                    subtitle: acpText(
                      context,
                      '仅用于当前会话',
                      'Applies to this conversation',
                    ),
                    onClose: () => Navigator.of(context).pop(),
                    closeLabel: acpText(context, '关闭', 'Close'),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('acp-current-model'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.subtleSurface,
                      border: Border.all(color: theme.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _modelName(session, context),
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: theme.title,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.data['model_id'] == null
                              ? acpText(
                                  context,
                                  '当前配置未知',
                                  'Current configuration unknown',
                                )
                              : !session.models.any(
                                  (m) => m['id'] == session.data['model_id'],
                                )
                              ? acpText(
                                  context,
                                  '当前配置 · 客户端未列入可选项',
                                  'Current configuration · not listed by the client',
                                )
                              : acpText(
                                  context,
                                  '当前配置',
                                  'Current configuration',
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: theme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    acpText(
                      context,
                      '模型列表由宿主机上的客户端提供。新增模型未出现时，请先检查客户端的模型配置或版本，再刷新。',
                      'Models come from the client on the host device. If a new model is missing, check that client’s model configuration or version, then refresh.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: theme.secondaryText,
                    ),
                  ),
                  if (session.modelRefreshSupported)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        CupertinoButton(
                          key: const Key('acp-model-refresh'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          onPressed:
                              available &&
                                  !refresh.pending &&
                                  !operation.blocksSending
                              ? () => _refresh(session, scope)
                              : null,
                          child: Text(
                            acpText(context, '刷新列表', 'Refresh models'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (refresh.pending)
                          const CupertinoActivityIndicator(radius: 7),
                        if (refresh.phase != AcpModelRefreshPhase.idle)
                          Text(
                            switch (refresh.phase) {
                              AcpModelRefreshPhase.loading => acpText(
                                context,
                                '正在读取最新列表…',
                                'Reading the latest list…',
                              ),
                              AcpModelRefreshPhase.synchronizing => acpText(
                                context,
                                '正在同步列表…',
                                'Syncing the list…',
                              ),
                              AcpModelRefreshPhase.deferred => acpText(
                                context,
                                '稍后刷新，当前列表已保留',
                                'Refresh deferred; the current list is kept',
                              ),
                              AcpModelRefreshPhase.failed => acpText(
                                context,
                                '刷新失败，已保留原列表，请重试',
                                'Refresh failed. The previous list is kept; please retry.',
                              ),
                              AcpModelRefreshPhase.idle => '',
                            },
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: theme.secondaryText,
                            ),
                          ),
                      ],
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
                            : !online
                            ? acpText(
                                context,
                                '设备离线，显示上次获取的列表。',
                                'Device offline. Showing the last available list.',
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
                  session.models.isEmpty
                      ? acpText(
                          context,
                          '客户端未提供可选模型',
                          'The client did not provide selectable models',
                        )
                      : acpText(context, '没有匹配的模型', 'No matching models'),
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
                        available &&
                            id.isNotEmpty &&
                            !selected &&
                            !operation.blocksSending
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
