part of '../agents_page.dart';

class _AgentDetailPane extends StatelessWidget {
  const _AgentDetailPane({
    required this.state,
    required this.selected,
    required this.pendingAgentDids,
    required this.onRefresh,
    required this.onCreateRuntime,
    required this.onOpenChat,
    required this.onRename,
    required this.onRetryRun,
    required this.onResetRuntime,
    required this.onUpgrade,
    required this.onCancelUpgrade,
    required this.onDelete,
    required this.onSaveInvocationPolicy,
  });

  final AgentsState state;
  final AgentSummary? selected;
  final Set<String> pendingAgentDids;
  final ValueChanged<AgentSummary> onRefresh;
  final ValueChanged<AgentSummary> onCreateRuntime;
  final ValueChanged<AgentSummary> onOpenChat;
  final ValueChanged<AgentSummary> onRename;
  final ValueChanged<AgentSummary> onRetryRun;
  final ValueChanged<AgentSummary> onResetRuntime;
  final ValueChanged<AgentSummary> onUpgrade;
  final ValueChanged<AgentSummary> onCancelUpgrade;
  final ValueChanged<AgentSummary> onDelete;
  final Future<bool> Function(String agentDid, AgentInvocationPolicy policy)
  onSaveInvocationPolicy;

  @override
  Widget build(BuildContext context) {
    final agent = selected;
    final responsive = context.awikiResponsive;
    if (agent == null) {
      return const Center(child: Text('选择一个代理'));
    }
    final isRefreshing =
        agent.isDaemon && state.isStatusQueryPending(agent.agentDid);
    final isUpgrading =
        agent.isDaemon && state.isDaemonUpgradePending(agent.agentDid);
    final isCancelling =
        agent.isDaemon && state.isDaemonUpgradeCancelling(agent.agentDid);
    final title = AgentDisplayName.title(agent);
    final visualStatus = AgentVisualStatus.fromAgent(
      agent,
      hasPendingTurn: pendingAgentDids.contains(agent.agentDid),
      isPendingUpgrade: isUpgrading,
      hasUpgradeError: state.daemonUpgradeErrors.containsKey(agent.agentDid),
    );
    final statusQueryError = agent.isDaemon
        ? state.statusQueryErrors[agent.agentDid]
        : null;
    final upgradeError = agent.isDaemon
        ? state.daemonUpgradeErrors[agent.agentDid]
        : null;
    final upgradeProgress = agent.isDaemon
        ? state.daemonUpgradeProgress[agent.agentDid]
        : null;
    return SafeArea(
      bottom: false,
      child: SelectionArea(
        child: ListView(
          padding: EdgeInsets.all(responsive.spacing(24)),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.titleXl,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AgentStatusPill(status: visualStatus),
              ],
            ),
            SizedBox(height: responsive.spacing(14)),
            SelectionContainer.disabled(
              child: Wrap(
                spacing: responsive.spacing(8),
                runSpacing: responsive.spacing(8),
                children: <Widget>[
                  if (agent.isDaemon)
                    _DaemonRefreshIconButton(
                      isLoading: isRefreshing,
                      size: responsive.displayScaled(34),
                      onPressed: state.isActing || isRefreshing
                          ? null
                          : () => onRefresh(agent),
                    ),
                  if (agent.isDaemon)
                    _ActionButton(
                      icon: CupertinoIcons.sparkles,
                      label: '创建 Agent',
                      onPressed:
                          state.isActing ||
                              (agent.isDaemon && agent.latest.needsUpgrade)
                          ? null
                          : () => onCreateRuntime(agent),
                    ),
                  if (agent.isRuntime)
                    _ActionButton(
                      icon: CupertinoIcons.chat_bubble_2,
                      label: '打开聊天',
                      onPressed: () => onOpenChat(agent),
                    ),
                  _ActionButton(
                    icon: CupertinoIcons.pencil,
                    label: '改名',
                    onPressed: state.isActing ? null : () => onRename(agent),
                  ),
                  if (agent.isRuntime)
                    _ActionButton(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      label: '重置 Session',
                      onPressed: state.isActing
                          ? null
                          : () => onResetRuntime(agent),
                    ),
                  if (agent.isRuntime)
                    _ActionButton(
                      icon: CupertinoIcons.play_arrow,
                      label: '重试 Run',
                      onPressed: state.isActing
                          ? null
                          : () => onRetryRun(agent),
                    ),
                  if (agent.isDaemon && agent.latest.needsUpgrade)
                    _ActionButton(
                      icon: CupertinoIcons.arrow_up_circle,
                      label: isUpgrading ? '升级中' : '升级',
                      onPressed: state.isActing || isUpgrading
                          ? null
                          : () => onUpgrade(agent),
                    ),
                  if (isUpgrading)
                    _ActionButton(
                      icon: CupertinoIcons.xmark_circle,
                      label: isCancelling ? '取消中' : '取消升级',
                      danger: true,
                      onPressed: state.isActing || isCancelling
                          ? null
                          : () => onCancelUpgrade(agent),
                    ),
                  _ActionButton(
                    icon: CupertinoIcons.trash,
                    label: agent.isDaemon ? '删除代理' : '删除智能体',
                    danger: true,
                    onPressed: state.isActing || !state.canDeleteAgent(agent)
                        ? null
                        : () => onDelete(agent),
                  ),
                ],
              ),
            ),
            if (state.error != null) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              _AgentErrorBanner(message: state.error!),
            ],
            if (statusQueryError != null) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              _AgentErrorBanner(message: statusQueryError),
            ],
            if (upgradeError != null) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              _AgentErrorBanner(message: upgradeError),
            ],
            if (isUpgrading && upgradeProgress != null) ...<Widget>[
              SizedBox(height: responsive.spacing(12)),
              _DaemonUpgradeProgressPanel(
                progress: upgradeProgress,
                isCancelling: isCancelling,
                onCancel: isCancelling ? null : () => onCancelUpgrade(agent),
              ),
            ],
            SizedBox(height: responsive.spacing(18)),
            if (agent.isRuntime && agent.recentRuns.isNotEmpty) ...<Widget>[
              const _SectionTitle('最近 Run'),
              SizedBox(height: responsive.spacing(8)),
              _RunStatusPanel(run: agent.recentRuns.first),
              SizedBox(height: responsive.spacing(18)),
            ],
            if (agent.isRuntime) ...<Widget>[
              _AgentAccessPolicyPanel(
                key: ValueKey<String>('access-policy-${agent.agentDid}'),
                policy:
                    state.invocationPolicies[agent.agentDid] ??
                    const AgentInvocationPolicy(),
                isLoading: state.loadingInvocationPolicies.contains(
                  agent.agentDid,
                ),
                isSaving: state.savingInvocationPolicies.contains(
                  agent.agentDid,
                ),
                errorText: state.invocationPolicyErrors[agent.agentDid],
                onUpdate: (policy) =>
                    onSaveInvocationPolicy(agent.agentDid, policy),
              ),
              SizedBox(height: responsive.spacing(18)),
            ],
            _DiagnosticInfoPanel(
              key: ValueKey<String>('diagnostic-${agent.agentDid}'),
              agent: agent,
            ),
          ],
        ),
      ),
    );
  }
}

class _DaemonUpgradeProgressPanel extends StatelessWidget {
  const _DaemonUpgradeProgressPanel({
    required this.progress,
    required this.isCancelling,
    required this.onCancel,
  });

  final DaemonUpgradeProgress progress;
  final bool isCancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final percent = progress.percent?.clamp(0, 100);
    final progressValue = percent == null ? null : percent / 100;
    final details = <String>[
      if (progress.downloadedBytes != null && progress.totalBytes != null)
        '${_formatBytes(progress.downloadedBytes!)} / ${_formatBytes(progress.totalBytes!)}'
      else if (progress.downloadedBytes != null)
        '已下载 ${_formatBytes(progress.downloadedBytes!)}',
      if (progress.speedBytesPerSecond != null)
        '${_formatBytes(progress.speedBytesPerSecond!)}/s',
      if (progress.sourceIndex != null && progress.sourceCount != null)
        '线路 ${progress.sourceIndex}/${progress.sourceCount}',
    ];
    return Container(
      padding: EdgeInsets.all(responsive.spacing(14)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CupertinoActivityIndicator(radius: responsive.displayScaled(7)),
              SizedBox(width: responsive.spacing(9)),
              Expanded(
                child: Text(
                  progress.displayMessage,
                  style: TextStyle(
                    color: const Color(0xFF101B32),
                    fontSize: responsive.bodySm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (percent != null)
                Text(
                  '${percent.round()}%',
                  style: TextStyle(
                    color: const Color(0xFF0B65F8),
                    fontSize: responsive.metaSm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              SizedBox(width: responsive.spacing(10)),
              CupertinoButton(
                minimumSize: Size(
                  responsive.displayScaled(28),
                  responsive.displayScaled(28),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: responsive.spacing(10),
                  vertical: responsive.spacing(5),
                ),
                color: const Color(0xFFFEEEF0),
                disabledColor: const Color(0xFFF2F4F8),
                borderRadius: BorderRadius.circular(responsive.radius(7)),
                onPressed: onCancel,
                child: Text(
                  isCancelling ? '取消中' : '取消',
                  style: TextStyle(
                    color: isCancelling
                        ? const Color(0xFF8A96AA)
                        : AwikiMeColors.danger,
                    fontSize: responsive.metaSm,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(10)),
          _DaemonUpgradeProgressBar(value: progressValue),
          if (details.isNotEmpty) ...<Widget>[
            SizedBox(height: responsive.spacing(8)),
            Text(
              details.join(' · '),
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.metaSm,
              ),
            ),
          ],
          if (progress.sourceUrl != null || progress.route != null) ...<Widget>[
            SizedBox(height: responsive.spacing(6)),
            Text(
              _upgradeSourceLabel(progress),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.metaSm,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DaemonUpgradeProgressBar extends StatelessWidget {
  const _DaemonUpgradeProgressBar({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return ClipRRect(
      borderRadius: BorderRadius.circular(responsive.radius(99)),
      child: Container(
        height: responsive.displayScaled(7),
        color: const Color(0xFFEAF2FF),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value?.clamp(0.06, 1) ?? 0.18,
          heightFactor: 1,
          child: Container(color: const Color(0xFF0B65F8)),
        ),
      ),
    );
  }
}

class _RunStatusPanel extends StatelessWidget {
  const _RunStatusPanel({required this.run});

  final AgentRunStatus run;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final updatedAt = run.updatedAt ?? run.startedAt;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(14)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  run.runId,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF101B32),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _RunStatusPill(status: run.status),
            ],
          ),
          if (updatedAt != null) ...<Widget>[
            SizedBox(height: responsive.spacing(7)),
            Text(
              updatedAt.toLocal().toString(),
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.metaSm,
              ),
            ),
          ],
          if (run.lastErrorCode != null ||
              run.lastErrorSummary != null) ...<Widget>[
            SizedBox(height: responsive.spacing(7)),
            Text(
              [
                if (run.lastErrorCode != null) run.lastErrorCode,
                if (run.lastErrorSummary != null)
                  _redactDiagnosticValue(run.lastErrorSummary),
              ].join(' · '),
              maxLines: 2,
              style: TextStyle(
                color: AwikiMeColors.danger,
                fontSize: responsive.metaSm,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
