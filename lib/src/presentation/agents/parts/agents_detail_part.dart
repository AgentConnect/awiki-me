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
    required this.personalAgentEnabled,
    required this.onOpenPersonalAgentSettings,
    required this.onBootstrapPersonalAgent,
    required this.onPausePersonalAgent,
    required this.onDeletePersonalAgent,
    required this.onRevokePersonalAgentAuthorization,
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
  final bool personalAgentEnabled;
  final ValueChanged<AgentSummary> onOpenPersonalAgentSettings;
  final ValueChanged<AgentSummary> onBootstrapPersonalAgent;
  final ValueChanged<AgentSummary> onPausePersonalAgent;
  final ValueChanged<AgentSummary> onDeletePersonalAgent;
  final ValueChanged<AgentSummary> onRevokePersonalAgentAuthorization;
  final Future<bool> Function(String agentDid, AgentInvocationPolicy policy)
  onSaveInvocationPolicy;

  @override
  Widget build(BuildContext context) {
    final agent = selected;
    final responsive = context.awikiResponsive;
    if (agent == null) {
      return Center(child: Text(context.l10n.agentSelectOne));
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
    final isDeleteSending =
        state.isActionPending(AgentActionKeys.delete(agent.agentDid)) ||
        state.isActionPending(
          AgentActionKeys.removeFromAccount(agent.agentDid),
        );
    final deleteAction = state.deleteActionForAgent(agent);
    final isUpgradeSending =
        agent.isDaemon &&
        state.isActionPending(AgentActionKeys.upgradeDaemon(agent.agentDid));
    final title = localizeAgentTitle(context.l10n, agent);
    final visualStatus = AgentVisualStatus.fromAgent(
      agent,
      hasPendingTurn: isDeleting || pendingAgentDids.contains(agent.agentDid),
      isPendingUpgrade: isUpgrading,
      hasUpgradeError: state.daemonUpgradeErrors.containsKey(agent.agentDid),
      hasStatusQueryError:
          agent.isDaemon && state.statusQueryErrors.containsKey(agent.agentDid),
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
    final runtimeDisplay = agent.isRuntime ? agentRuntimeDisplay(agent) : null;
    final daemonCanUpgrade =
        agent.isDaemon &&
        !state.statusQueryErrors.containsKey(agent.agentDid) &&
        (agent.daemonEffectiveStatus?.isUpgradeActionable ??
            agent.latest.needsUpgrade ||
                agent.latest.status.trim().toLowerCase() == 'needs_upgrade');
    final daemonCanCreateRuntime =
        !agent.isDaemon ||
        (!state.statusQueryErrors.containsKey(agent.agentDid) &&
            (agent.daemonEffectiveStatus?.isActionable ?? true));
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
                  SemanticPill(
                    label: agent.isDaemon
                        ? 'Daemon'
                        : context.l10n.identityTypeAgent,
                    tone: SemanticPillTone.identity,
                  ),
                  if (runtimeDisplay != null)
                    SemanticPill(
                      label: runtimeDisplay.label,
                      tone: SemanticPillTone.runtime,
                    ),
                ],
              ),
            ),
            SizedBox(height: responsive.spacing(10)),
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
                      label: context.l10n.agentCreateRuntime,
                      onPressed:
                          isCreatingRuntime ||
                              !daemonCanCreateRuntime ||
                              daemonCanUpgrade
                          ? null
                          : () => onCreateRuntime(agent),
                    ),
                  if (agent.isRuntime)
                    _ActionButton(
                      icon: CupertinoIcons.chat_bubble_2,
                      label: context.l10n.agentOpenChat,
                      onPressed: () => onOpenChat(agent),
                    ),
                  _ActionButton(
                    icon: CupertinoIcons.pencil,
                    label: context.l10n.agentRename,
                    onPressed: isRenaming ? null : () => onRename(agent),
                  ),
                  if (daemonCanUpgrade)
                    _ActionButton(
                      icon: CupertinoIcons.arrow_up_circle,
                      label: isUpgrading
                          ? context.l10n.agentUpgrading
                          : context.l10n.agentUpgrade,
                      onPressed: isUpgradeSending || isUpgrading
                          ? null
                          : () => onUpgrade(agent),
                    ),
                  if (isUpgrading)
                    _ActionButton(
                      icon: CupertinoIcons.xmark_circle,
                      label: isCancelling
                          ? context.l10n.agentCancelling
                          : context.l10n.agentCancelUpgrade,
                      danger: true,
                      onPressed: isCancelling
                          ? null
                          : () => onCancelUpgrade(agent),
                    ),
                  _ActionButton(
                    icon: CupertinoIcons.trash,
                    label: isDeleting
                        ? context.l10n.agentDeleting
                        : _agentDeleteButtonLabel(context, agent, deleteAction),
                    danger: true,
                    onPressed:
                        isDeleteSending ||
                            isDeleting ||
                            deleteAction == AgentDeleteAction.unavailable
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
              _SectionTitle(context.l10n.agentRecentRuns),
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
            if (_shouldShowPersonalAgentSettingsPanel() &&
                agent.isDaemon) ...<Widget>[
              _PersonalAgentSettingsPanel(
                daemon: agent,
                personalAgent: state.personalAgentRuntimeFor(agent.agentDid),
                enabled: personalAgentEnabled,
                isEnablePending: state.isActionPending(
                  AgentActionKeys.bootstrapPersonalAgent(agent.agentDid),
                ),
                isManagementPending:
                    state.isActionPending(
                      AgentActionKeys.pausePersonalAgent(agent.agentDid),
                    ) ||
                    state.isActionPending(
                      AgentActionKeys.deletePersonalAgent(agent.agentDid),
                    ) ||
                    state.isActionPending(
                      AgentActionKeys.revokePersonalAgent(agent.agentDid),
                    ),
                onEnable: () => onBootstrapPersonalAgent(agent),
                onPause: () => onPausePersonalAgent(agent),
                onDelete: () => onDeletePersonalAgent(agent),
                onRevoke: () => onRevokePersonalAgentAuthorization(agent),
              ),
              SizedBox(height: responsive.spacing(18)),
            ] else if (personalAgentEnabled && agent.isDaemon) ...<Widget>[
              _PersonalAgentSettingsEntryCard(
                daemon: agent,
                personalAgent: state.personalAgentRuntimeFor(agent.agentDid),
                onOpen: () => onOpenPersonalAgentSettings(agent),
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

bool _shouldShowPersonalAgentSettingsPanel() {
  // Keep the Personal Agent management implementation available for future
  // rollout, but hide the daemon detail entry from the current product UI.
  return false;
}

String _agentDeleteButtonLabel(
  BuildContext context,
  AgentSummary agent,
  AgentDeleteAction action,
) {
  if (action == AgentDeleteAction.removeFromAccount) {
    return context.l10n.agentRemoveFromAccount;
  }
  return agent.isDaemon
      ? context.l10n.agentDeleteDaemon
      : context.l10n.agentDeleteRuntime;
}

class _PersonalAgentSettingsEntryCard extends StatelessWidget {
  const _PersonalAgentSettingsEntryCard({
    required this.daemon,
    required this.personalAgent,
    required this.onOpen,
  });

  final AgentSummary daemon;
  final AgentSummary? personalAgent;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final responsive = context.awikiResponsive;
    final diagnostics = daemon.latest.diagnosticsSummary;
    final hasBootstrapKey = _daemonHasBootstrapPublicKey(daemon, diagnostics);
    final stateText = personalAgent != null
        ? l10n.personalAgentCreated
        : hasBootstrapKey
        ? l10n.personalAgentReadyToEnable
        : l10n.personalAgentWaitingStatusRefresh;
    final stateActive = personalAgent != null || hasBootstrapKey;
    return AppPressableTile(
      key: const Key('personal-agent-settings-entry-card'),
      onTap: onOpen,
      semanticLabel: l10n.personalAgentConfigure,
      semanticsIdentifier: 'personal-agent-settings-entry',
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
                    l10n.personalAgentTitle,
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.bodyMd,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    l10n.personalAgentSettingsSubtitle,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(7)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _PersonalAgentStatePill(
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
              context.l10n.agentDeletingNotice,
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

class _PersonalAgentSettingsPanel extends StatelessWidget {
  const _PersonalAgentSettingsPanel({
    required this.daemon,
    required this.personalAgent,
    required this.enabled,
    required this.isEnablePending,
    required this.isManagementPending,
    required this.onEnable,
    required this.onPause,
    required this.onDelete,
    required this.onRevoke,
  });

  final AgentSummary daemon;
  final AgentSummary? personalAgent;
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
    const provider = defaultPersonalAgentRuntimeProvider;
    final isBusy = isEnablePending || isManagementPending;
    final canEnable = enabled && daemonReady && hasBootstrapKey && !isBusy;
    final canManage =
        enabled && daemonReady && personalAgent != null && !isBusy;
    return Container(
      key: const Key('personal-agent-settings-panel'),
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
                      context.l10n.personalAgentTitle,
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      enabled
                          ? context.l10n.personalAgentRuntimeSubtitle(
                              provider.displayLabel,
                            )
                          : context.l10n.personalAgentExperimentDisabled,
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.metaSm,
                      ),
                    ),
                  ],
                ),
              ),
              _PersonalAgentStatePill(
                text: enabled && hasBootstrapKey
                    ? context.l10n.personalAgentReadyToEnable
                    : context.l10n.personalAgentNotReady,
                active: enabled && hasBootstrapKey,
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          SelectionContainer.disabled(
            child: _PersonalAgentFactGrid(
              rows: <_PersonalAgentFact>[
                _PersonalAgentFact(
                  context.l10n.personalAgentRunningDaemon,
                  localizeAgentTitle(context.l10n, daemon),
                ),
                _PersonalAgentFact(
                  context.l10n.personalAgentEngine,
                  provider.displayLabel,
                ),
                _PersonalAgentFact(
                  context.l10n.personalAgentScope,
                  context.l10n.personalAgentAllProcessableConversations,
                ),
                _PersonalAgentFact(
                  context.l10n.personalAgentDaemonVersion,
                  _daemonRuntimeSummary(context, daemon),
                ),
                _PersonalAgentFact(
                  context.l10n.personalAgentCapabilities,
                  provider.capabilityLabel,
                ),
                _PersonalAgentFact(
                  context.l10n.personalAgentSecureBootstrap,
                  hasBootstrapKey
                      ? context.l10n.personalAgentPublicKeyReported
                      : context.l10n.personalAgentWaitingStatusRefresh,
                ),
              ],
            ),
          ),
          SizedBox(height: responsive.spacing(12)),
          _PersonalAgentPermissionSummary(enabled: enabled),
          SizedBox(height: responsive.spacing(12)),
          SelectionContainer.disabled(
            child: Wrap(
              spacing: responsive.spacing(8),
              runSpacing: responsive.spacing(8),
              children: <Widget>[
                _ActionButton(
                  icon: CupertinoIcons.check_mark_circled,
                  label: isEnablePending
                      ? context.l10n.personalAgentEnabling
                      : context.l10n.personalAgentEnable,
                  onPressed: canEnable ? onEnable : null,
                ),
                _ActionButton(
                  icon: CupertinoIcons.pause_circle,
                  label: context.l10n.personalAgentPause,
                  onPressed: canManage ? onPause : null,
                ),
                _ActionButton(
                  icon: CupertinoIcons.trash,
                  label: context.l10n.personalAgentDelete,
                  danger: true,
                  onPressed: canManage ? onDelete : null,
                ),
                _ActionButton(
                  icon: CupertinoIcons.lock_slash,
                  label: context.l10n.personalAgentRevokeAuthorization,
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
        _downloadedLabel(context, progress.downloadedBytes!),
      if (progress.speedBytesPerSecond != null)
        '${_formatBytes(progress.speedBytesPerSecond!)}/s',
      if (progress.sourceIndex != null && progress.sourceCount != null)
        _sourceRouteLabel(
          context,
          progress.sourceIndex!,
          progress.sourceCount!,
        ),
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
                  localizeDaemonUpgradeProgress(context.l10n, progress),
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
                  isCancelling
                      ? context.l10n.agentCancelling
                      : context.l10n.commonCancel,
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
              _upgradeSourceLabel(context, progress),
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

class _PersonalAgentStatePill extends StatelessWidget {
  const _PersonalAgentStatePill({required this.text, required this.active});

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

class _PersonalAgentFactGrid extends StatelessWidget {
  const _PersonalAgentFactGrid({required this.rows});

  final List<_PersonalAgentFact> rows;

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

class _PersonalAgentPermissionSummary extends StatelessWidget {
  const _PersonalAgentPermissionSummary({required this.enabled});

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
            ? context.l10n.personalAgentPermissionSummaryEnabled
            : context.l10n.personalAgentPermissionSummaryDisabled,
        style: TextStyle(
          color: const Color(0xFF344056),
          fontSize: responsive.bodySm,
          height: 1.35,
        ),
      ),
    );
  }
}

class _PersonalAgentFact {
  const _PersonalAgentFact(this.label, this.value);

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

String _daemonRuntimeSummary(BuildContext context, AgentSummary daemon) {
  final version = _nonEmpty(daemon.latest.version);
  final platform = _nonEmpty(daemon.latest.platform);
  if (version != null && platform != null) {
    return '$version · $platform';
  }
  return version ?? platform ?? context.l10n.commonUnknown;
}

String _downloadedLabel(BuildContext context, int bytes) {
  return context.l10n.daemonUpgradeDownloaded(_formatBytes(bytes));
}

String _sourceRouteLabel(BuildContext context, int index, int count) {
  return context.l10n.daemonUpgradeRouteIndex(index, count);
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
          if (run.progress case final progress?) ...<Widget>[
            SizedBox(height: responsive.spacing(7)),
            Text(
              _runProgressLabel(context, progress),
              maxLines: 2,
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

String _runProgressLabel(BuildContext context, AgentRunProgress progress) {
  return switch (progress.code) {
    'external_service_delayed' => context.l10n.chatAgentExternalServiceDelayed,
    'external_service_resumed' => context.l10n.chatAgentExternalServiceResumed,
    'external_tool_running' => context.l10n.chatAgentExternalServiceWorking,
    _ => context.l10n.chatAgentProcessing,
  };
}
