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
    required this.onUpgrade,
    required this.onCancelUpgrade,
    required this.onDelete,
    required this.messageAgentEnabled,
    required this.onOpenMessageAgentSettings,
    required this.onBootstrapMessageAgent,
    required this.onPauseMessageAgent,
    required this.onDeleteMessageAgent,
    required this.onRevokeMessageAgentAuthorization,
    required this.onSaveInvocationPolicy,
  });

  final AgentsState state;
  final AgentSummary? selected;
  final Set<String> pendingAgentDids;
  final ValueChanged<AgentSummary> onRefresh;
  final ValueChanged<AgentSummary> onCreateRuntime;
  final ValueChanged<AgentSummary> onOpenChat;
  final ValueChanged<AgentSummary> onRename;
  final ValueChanged<AgentSummary> onUpgrade;
  final ValueChanged<AgentSummary> onCancelUpgrade;
  final ValueChanged<AgentSummary> onDelete;
  final bool messageAgentEnabled;
  final ValueChanged<AgentSummary> onOpenMessageAgentSettings;
  final ValueChanged<AgentSummary> onBootstrapMessageAgent;
  final ValueChanged<AgentSummary> onPauseMessageAgent;
  final ValueChanged<AgentSummary> onDeleteMessageAgent;
  final ValueChanged<AgentSummary> onRevokeMessageAgentAuthorization;
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
    final isDeleting = state.isDeletingAgent(agent.agentDid);
    final isCreatingRuntime =
        agent.isDaemon &&
        state.isActionPending(AgentActionKeys.createRuntime(agent.agentDid));
    final isRenaming = state.isActionPending(
      AgentActionKeys.rename(agent.agentDid),
    );
    final isDeleteSending = state.isActionPending(
      AgentActionKeys.delete(agent.agentDid),
    );
    final isUpgradeSending =
        agent.isDaemon &&
        state.isActionPending(AgentActionKeys.upgradeDaemon(agent.agentDid));
    final title = AgentDisplayName.title(agent);
    final visualStatus = AgentVisualStatus.fromAgent(
      agent,
      hasPendingTurn: isDeleting || pendingAgentDids.contains(agent.agentDid),
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
                      onPressed: isRefreshing ? null : () => onRefresh(agent),
                    ),
                  if (agent.isDaemon)
                    _ActionButton(
                      icon: CupertinoIcons.sparkles,
                      label: '创建 Agent',
                      onPressed:
                          isCreatingRuntime ||
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
                    onPressed: isRenaming ? null : () => onRename(agent),
                  ),
                  if (agent.isDaemon && agent.latest.needsUpgrade)
                    _ActionButton(
                      icon: CupertinoIcons.arrow_up_circle,
                      label: isUpgrading ? '升级中' : '升级',
                      onPressed: isUpgradeSending || isUpgrading
                          ? null
                          : () => onUpgrade(agent),
                    ),
                  if (isUpgrading)
                    _ActionButton(
                      icon: CupertinoIcons.xmark_circle,
                      label: isCancelling ? '取消中' : '取消升级',
                      danger: true,
                      onPressed: isCancelling
                          ? null
                          : () => onCancelUpgrade(agent),
                    ),
                  _ActionButton(
                    icon: CupertinoIcons.trash,
                    label: isDeleting
                        ? '删除中'
                        : agent.isDaemon
                        ? '删除代理'
                        : '删除智能体',
                    danger: true,
                    onPressed:
                        isDeleteSending ||
                            isDeleting ||
                            !state.canDeleteAgent(agent)
                        ? null
                        : () => onDelete(agent),
                  ),
                ],
              ),
            ),
            if (isDeleting) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              const _AgentDeletingNotice(),
            ],
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
            if (_shouldShowMessageAgentSettingsPanel() &&
                agent.isDaemon) ...<Widget>[
              _MessageAgentSettingsPanel(
                daemon: agent,
                messageAgent: state.messageAgentRuntimeFor(agent.agentDid),
                enabled: messageAgentEnabled,
                isEnablePending: state.isActionPending(
                  AgentActionKeys.bootstrapMessageAgent(agent.agentDid),
                ),
                isManagementPending:
                    state.isActionPending(
                      AgentActionKeys.pauseMessageAgent(agent.agentDid),
                    ) ||
                    state.isActionPending(
                      AgentActionKeys.deleteMessageAgent(agent.agentDid),
                    ) ||
                    state.isActionPending(
                      AgentActionKeys.revokeMessageAgent(agent.agentDid),
                    ),
                onEnable: () => onBootstrapMessageAgent(agent),
                onPause: () => onPauseMessageAgent(agent),
                onDelete: () => onDeleteMessageAgent(agent),
                onRevoke: () => onRevokeMessageAgentAuthorization(agent),
              ),
              SizedBox(height: responsive.spacing(18)),
            ] else if (messageAgentEnabled && agent.isDaemon) ...<Widget>[
              _MessageAgentSettingsEntryCard(
                daemon: agent,
                messageAgent: state.messageAgentRuntimeFor(agent.agentDid),
                onOpen: () => onOpenMessageAgentSettings(agent),
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

bool _shouldShowMessageAgentSettingsPanel() {
  // Keep the Message Agent management implementation available for future
  // rollout, but hide the daemon detail entry from the current product UI.
  return false;
}

class _MessageAgentSettingsEntryCard extends StatelessWidget {
  const _MessageAgentSettingsEntryCard({
    required this.daemon,
    required this.messageAgent,
    required this.onOpen,
  });

  final AgentSummary daemon;
  final AgentSummary? messageAgent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final diagnostics = daemon.latest.diagnosticsSummary;
    final hasBootstrapKey = _daemonHasBootstrapPublicKey(daemon, diagnostics);
    final stateText = messageAgent != null
        ? '已创建 Message Agent'
        : hasBootstrapKey
        ? '可启用'
        : '待公钥';
    final stateActive = messageAgent != null || hasBootstrapKey;
    return AppPressableTile(
      key: const Key('message-agent-settings-entry-card'),
      onTap: onOpen,
      semanticLabel: '配置消息处理 Agent',
      semanticsIdentifier: 'message-agent-settings-entry',
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      backgroundColor: CupertinoColors.white,
      border: Border.all(color: const Color(0xFFE4EAF3)),
      child: Padding(
        padding: EdgeInsets.all(responsive.spacing(16)),
        child: Row(
          children: <Widget>[
            Container(
              width: responsive.displayScaled(34),
              height: responsive.displayScaled(34),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7F4),
                borderRadius: BorderRadius.circular(responsive.radius(9)),
              ),
              child: Icon(
                CupertinoIcons.bubble_left_bubble_right,
                color: const Color(0xFF1B7A43),
                size: responsive.iconMd,
              ),
            ),
            SizedBox(width: responsive.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '消息处理 Agent',
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.bodyMd,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    '配置启用、暂停和撤销授权；只生成草稿，需你确认后发送。',
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(7)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _MessageAgentStatePill(
                      text: stateText,
                      active: stateActive,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.spacing(10)),
            Icon(
              CupertinoIcons.chevron_right,
              color: const Color(0xFF8A96AA),
              size: responsive.iconSm,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentDeletingNotice extends StatelessWidget {
  const _AgentDeletingNotice();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(12),
        vertical: responsive.spacing(10),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7FF),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFDCE8FF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          CupertinoActivityIndicator(radius: responsive.displayScaled(7)),
          SizedBox(width: responsive.spacing(9)),
          Expanded(
            child: Text(
              '删除请求已发送，正在等待代理同步。',
              style: TextStyle(
                color: const Color(0xFF31527A),
                fontSize: responsive.bodySm,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageAgentSettingsPanel extends StatelessWidget {
  const _MessageAgentSettingsPanel({
    required this.daemon,
    required this.messageAgent,
    required this.enabled,
    required this.isEnablePending,
    required this.isManagementPending,
    required this.onEnable,
    required this.onPause,
    required this.onDelete,
    required this.onRevoke,
  });

  final AgentSummary daemon;
  final AgentSummary? messageAgent;
  final bool enabled;
  final bool isEnablePending;
  final bool isManagementPending;
  final VoidCallback onEnable;
  final VoidCallback onPause;
  final VoidCallback onDelete;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final diagnostics = daemon.latest.diagnosticsSummary;
    final hasBootstrapKey = _daemonHasBootstrapPublicKey(daemon, diagnostics);
    final daemonReady =
        daemon.latest.status.trim().toLowerCase() == 'ready' ||
        daemon.latest.status.trim().toLowerCase() == 'needs_upgrade';
    const provider = defaultMessageAgentRuntimeProvider;
    final isBusy = isEnablePending || isManagementPending;
    final canEnable = enabled && daemonReady && hasBootstrapKey && !isBusy;
    final canManage = enabled && daemonReady && messageAgent != null && !isBusy;
    return Container(
      key: const Key('message-agent-settings-panel'),
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(10)),
        border: Border.all(color: const Color(0xFFE4EAF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: responsive.displayScaled(34),
                height: responsive.displayScaled(34),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7F4),
                  borderRadius: BorderRadius.circular(responsive.radius(9)),
                ),
                child: Icon(
                  CupertinoIcons.bubble_left_bubble_right,
                  color: const Color(0xFF1B7A43),
                  size: responsive.iconMd,
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '消息处理 Agent',
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      enabled
                          ? '运行 Daemon 内创建 ${provider.displayLabel} runtime'
                          : '实验功能关闭',
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.metaSm,
                      ),
                    ),
                  ],
                ),
              ),
              _MessageAgentStatePill(
                text: enabled && hasBootstrapKey ? '可启用' : '未就绪',
                active: enabled && hasBootstrapKey,
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          SelectionContainer.disabled(
            child: _MessageAgentFactGrid(
              rows: <_MessageAgentFact>[
                _MessageAgentFact('运行 Daemon', AgentDisplayName.title(daemon)),
                _MessageAgentFact('引擎', provider.displayLabel),
                const _MessageAgentFact('处理范围', '所有可处理会话'),
                _MessageAgentFact('Daemon 版本', _daemonRuntimeSummary(daemon)),
                _MessageAgentFact('可用能力', provider.capabilityLabel),
                _MessageAgentFact(
                  '安全 bootstrap',
                  hasBootstrapKey ? '已上报公钥' : '等待刷新状态',
                ),
              ],
            ),
          ),
          SizedBox(height: responsive.spacing(12)),
          _MessageAgentPermissionSummary(enabled: enabled),
          SizedBox(height: responsive.spacing(12)),
          SelectionContainer.disabled(
            child: Wrap(
              spacing: responsive.spacing(8),
              runSpacing: responsive.spacing(8),
              children: <Widget>[
                _ActionButton(
                  icon: CupertinoIcons.check_mark_circled,
                  label: isEnablePending ? '启用中' : '启用消息处理 Agent',
                  onPressed: canEnable ? onEnable : null,
                ),
                _ActionButton(
                  icon: CupertinoIcons.pause_circle,
                  label: '暂停处理消息',
                  onPressed: canManage ? onPause : null,
                ),
                _ActionButton(
                  icon: CupertinoIcons.trash,
                  label: '删除消息处理 Agent',
                  danger: true,
                  onPressed: canManage ? onDelete : null,
                ),
                _ActionButton(
                  icon: CupertinoIcons.lock_slash,
                  label: '撤销 Daemon 消息授权',
                  danger: true,
                  onPressed: canManage ? onRevoke : null,
                ),
              ],
            ),
          ),
        ],
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

class _MessageAgentStatePill extends StatelessWidget {
  const _MessageAgentStatePill({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF1B7A43) : const Color(0xFF66728A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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

class _MessageAgentFactGrid extends StatelessWidget {
  const _MessageAgentFactGrid({required this.rows});

  final List<_MessageAgentFact> rows;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Wrap(
      spacing: responsive.spacing(10),
      runSpacing: responsive.spacing(10),
      children: rows
          .map(
            (row) => SizedBox(
              width: responsive.displayScaled(190),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.label,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    row.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.bodySm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MessageAgentPermissionSummary extends StatelessWidget {
  const _MessageAgentPermissionSummary({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Text(
        enabled
            ? '权限摘要：读取普通 direct text，分析、总结、生成草稿；不会自动发送消息，也不处理 E2EE 明文。'
            : '启用 AWIKI_AGENT_IM_ENABLED 后可配置消息处理 Agent。',
        style: TextStyle(
          color: const Color(0xFF344056),
          fontSize: responsive.bodySm,
          height: 1.35,
        ),
      ),
    );
  }
}

class _MessageAgentFact {
  const _MessageAgentFact(this.label, this.value);

  final String label;
  final String value;
}

bool _daemonHasBootstrapPublicKey(
  AgentSummary daemon,
  Map<String, Object?> diagnostics,
) {
  try {
    DaemonBootstrapPublicKey.fromDiagnostics(
      daemonDid: daemon.agentDid,
      diagnostics: diagnostics,
    );
    return true;
  } catch (_) {
    return false;
  }
}

String _daemonRuntimeSummary(AgentSummary daemon) {
  final version = _nonEmpty(daemon.latest.version);
  final platform = _nonEmpty(daemon.latest.platform);
  if (version != null && platform != null) {
    return '$version · $platform';
  }
  return version ?? platform ?? '未知';
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
