part of 'agents_page.dart';

class PersonalAgentSettingsPage extends ConsumerStatefulWidget {
  const PersonalAgentSettingsPage({super.key, this.initialDaemonDid});

  final String? initialDaemonDid;

  @override
  ConsumerState<PersonalAgentSettingsPage> createState() =>
      _PersonalAgentSettingsPageState();
}

class _PersonalAgentSettingsPageState
    extends ConsumerState<PersonalAgentSettingsPage> {
  String? _selectedDaemonDid;

  @override
  void initState() {
    super.initState();
    _selectedDaemonDid = widget.initialDaemonDid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(agentsProvider.notifier).ensureLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(agentsProvider);
    final enabled = ref.watch(agentImEnabledProvider);
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final daemons = state.daemonAgents;
    final selectedDaemon = _selectedDaemon(state, daemons);
    final selectedDid = selectedDaemon?.agentDid;
    final personalAgent = selectedDid == null
        ? null
        : state.personalAgentRuntimeFor(selectedDid);
    final selectionLabel = selectedDaemon == null
        ? l10n.personalAgentNoDaemonSelected
        : l10n.personalAgentSelectedDaemon(
            localizeAgentTitle(l10n, selectedDaemon),
          );
    final isEnablePending =
        selectedDid != null &&
        state.isActionPending(
          AgentActionKeys.bootstrapPersonalAgent(selectedDid),
        );
    final isManagementPending =
        selectedDid != null &&
        (state.isActionPending(
              AgentActionKeys.pausePersonalAgent(selectedDid),
            ) ||
            state.isActionPending(
              AgentActionKeys.deletePersonalAgent(selectedDid),
            ) ||
            state.isActionPending(
              AgentActionKeys.revokePersonalAgent(selectedDid),
            ));

    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 960,
        includeBottomSafeArea: true,
        child: SafeArea(
          bottom: false,
          child: SelectionArea(
            child: ListView(
              key: const Key('personal-agent-settings-page'),
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(16),
                responsive.spacing(14),
                responsive.spacing(16),
                responsive.spacing(24),
              ),
              children: <Widget>[
                AwikiMeTopBar(
                  title: l10n.personalAgentTitle,
                  padding: EdgeInsets.zero,
                  leading: TopBarActionButton(
                    onTap: () => Navigator.of(context).maybePop(),
                    semanticsLabel: l10n.commonBack,
                    tooltip: l10n.commonBack,
                    child: const AwikiAssetIcon(
                      assetName: 'assets/icons/icon_left.svg',
                      color: AwikiMeColors.primaryDark,
                      size: 22,
                    ),
                  ),
                ),
                SizedBox(height: responsive.spacing(16)),
                if (state.error != null) ...<Widget>[
                  _AgentErrorBanner(message: state.error!),
                  SizedBox(height: responsive.spacing(12)),
                ],
                _PersonalAgentHeroCard(
                  enabled: enabled,
                  daemon: selectedDaemon,
                  personalAgent: personalAgent,
                  isEnablePending: isEnablePending,
                  isManagementPending: isManagementPending,
                  onEnable: selectedDaemon == null
                      ? null
                      : () => ref
                            .read(agentsProvider.notifier)
                            .bootstrapPersonalAgent(
                              daemonDid: selectedDaemon.agentDid,
                            ),
                  onPause: selectedDaemon == null
                      ? null
                      : () => _confirmPausePersonalAgent(
                          context,
                          ref,
                          selectedDaemon,
                        ),
                  onDelete: selectedDaemon == null
                      ? null
                      : () => _confirmDeletePersonalAgent(
                          context,
                          ref,
                          selectedDaemon,
                        ),
                  onRevoke: selectedDaemon == null
                      ? null
                      : () => _confirmRevokePersonalAgentAuthorization(
                          context,
                          ref,
                          selectedDaemon,
                        ),
                  onRefresh: selectedDaemon == null
                      ? null
                      : () => ref
                            .read(agentsProvider.notifier)
                            .refreshDaemonStatus(selectedDaemon.agentDid),
                ),
                SizedBox(height: responsive.spacing(16)),
                E2eMarker(
                  selectedDid == null
                      ? 'personal-agent-selected-daemon:none'
                      : 'personal-agent-selected-daemon:$selectedDid',
                ),
                e2eSemantics(
                  identifier: 'personal-agent-selected-daemon-label',
                  label: selectionLabel,
                  child: Text(
                    selectionLabel,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: responsive.spacing(8)),
                _PersonalAgentDaemonSelector(
                  daemons: daemons,
                  selectedDaemonDid: selectedDaemon?.agentDid,
                  state: state,
                  onSelect: (daemonDid) => setState(() {
                    _selectedDaemonDid = daemonDid;
                  }),
                  onRefresh: (daemon) => ref
                      .read(agentsProvider.notifier)
                      .refreshDaemonStatus(daemon.agentDid),
                ),
                SizedBox(height: responsive.spacing(16)),
                _PersonalAgentLimitsCard(enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    );
  }

  AgentSummary? _selectedDaemon(AgentsState state, List<AgentSummary> daemons) {
    final wanted = _selectedDaemonDid ?? widget.initialDaemonDid;
    if (wanted != null) {
      for (final daemon in daemons) {
        if (daemon.agentDid == wanted) {
          return daemon;
        }
      }
    }
    if (daemons.isNotEmpty) {
      return daemons.first;
    }
    return null;
  }
}

class _PersonalAgentHeroCard extends StatelessWidget {
  const _PersonalAgentHeroCard({
    required this.enabled,
    required this.daemon,
    required this.personalAgent,
    required this.isEnablePending,
    required this.isManagementPending,
    required this.onEnable,
    required this.onPause,
    required this.onDelete,
    required this.onRevoke,
    required this.onRefresh,
  });

  final bool enabled;
  final AgentSummary? daemon;
  final AgentSummary? personalAgent;
  final bool isEnablePending;
  final bool isManagementPending;
  final VoidCallback? onEnable;
  final VoidCallback? onPause;
  final VoidCallback? onDelete;
  final VoidCallback? onRevoke;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final responsive = context.awikiResponsive;
    final daemon = this.daemon;
    final diagnostics =
        daemon?.latest.diagnosticsSummary ?? const <String, Object?>{};
    final hasBootstrapKey =
        daemon != null && _daemonHasBootstrapPublicKey(daemon, diagnostics);
    final daemonReady = daemon != null && _personalAgentDaemonReady(daemon);
    final personalAgent = this.personalAgent;
    final isBusy = isEnablePending || isManagementPending;
    final canEnable = enabled && daemonReady && hasBootstrapKey && !isBusy;
    final canManage =
        enabled && daemonReady && personalAgent != null && !isBusy;
    final stateLabel = _personalAgentStateLabel(
      enabled: enabled,
      daemon: daemon,
      hasBootstrapKey: hasBootstrapKey,
      personalAgent: personalAgent,
      isBusy: isBusy,
      l10n: l10n,
    );
    const provider = defaultPersonalAgentRuntimeProvider;
    return AppCardSection(
      padding: EdgeInsets.all(responsive.spacing(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: responsive.displayScaled(42),
                height: responsive.displayScaled(42),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F7F4),
                  borderRadius: BorderRadius.circular(responsive.radius(12)),
                ),
                child: Icon(
                  CupertinoIcons.bubble_left_bubble_right,
                  color: const Color(0xFF1B7A43),
                  size: responsive.iconLg,
                ),
              ),
              SizedBox(width: responsive.spacing(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.personalAgentTitle,
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.titleLg,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(4)),
                    Text(
                      enabled
                          ? l10n.personalAgentDescription
                          : l10n.personalAgentDisabledDescription,
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.bodySm,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              _PersonalAgentStatePill(
                text: stateLabel,
                active: enabled && (personalAgent != null || hasBootstrapKey),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(16)),
          _PersonalAgentFactGrid(
            rows: <_PersonalAgentFact>[
              _PersonalAgentFact(
                l10n.personalAgentRunningDaemon,
                daemon == null
                    ? l10n.personalAgentNotSelected
                    : localizeAgentTitle(l10n, daemon),
              ),
              _PersonalAgentFact(
                l10n.personalAgentEngine,
                provider.displayLabel,
              ),
              _PersonalAgentFact(
                l10n.personalAgentScope,
                l10n.personalAgentDirectTextScope,
              ),
              _PersonalAgentFact(
                l10n.personalAgentDaemonStatus,
                daemon == null
                    ? l10n.personalAgentNoDaemon
                    : daemon.latest.status,
              ),
              _PersonalAgentFact(
                l10n.personalAgentDaemonVersion,
                daemon == null
                    ? l10n.commonUnknown
                    : _daemonRuntimeSummary(context, daemon),
              ),
              _PersonalAgentFact(
                l10n.personalAgentSecureBootstrap,
                hasBootstrapKey
                    ? l10n.personalAgentPublicKeyReported
                    : l10n.personalAgentWaitingStatusRefresh,
              ),
              _PersonalAgentFact(
                l10n.personalAgentAuthorizationStatus,
                personalAgent == null
                    ? l10n.personalAgentNotBound
                    : l10n.personalAgentBound(personalAgent.displayName),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          _PersonalAgentPermissionSummary(enabled: enabled),
          if (!enabled ||
              daemon == null ||
              !daemonReady ||
              !hasBootstrapKey) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            _PersonalAgentReadinessNotice(
              enabled: enabled,
              daemon: daemon,
              daemonReady: daemonReady,
              hasBootstrapKey: hasBootstrapKey,
            ),
          ],
          SizedBox(height: responsive.spacing(14)),
          Wrap(
            spacing: responsive.spacing(8),
            runSpacing: responsive.spacing(8),
            children: <Widget>[
              _ActionButton(
                icon: CupertinoIcons.check_mark_circled,
                label: isEnablePending
                    ? l10n.personalAgentEnabling
                    : l10n.personalAgentEnable,
                semanticsIdentifier: 'personal-agent-enable-action',
                onPressed: canEnable ? onEnable : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.pause_circle,
                label: l10n.personalAgentPause,
                semanticsIdentifier: 'personal-agent-pause-action',
                onPressed: canManage ? onPause : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.trash,
                label: l10n.personalAgentDelete,
                semanticsIdentifier: 'personal-agent-delete-action',
                danger: true,
                onPressed: canManage ? onDelete : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.lock_slash,
                label: l10n.personalAgentRevokeAuthorization,
                semanticsIdentifier: 'personal-agent-revoke-action',
                danger: true,
                onPressed: canManage ? onRevoke : null,
              ),
              _ActionButton(
                icon: CupertinoIcons.refresh,
                label: l10n.personalAgentRefreshDaemonStatus,
                semanticsIdentifier: 'personal-agent-refresh-action',
                onPressed: daemon == null || isBusy ? null : onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonalAgentDaemonSelector extends StatelessWidget {
  const _PersonalAgentDaemonSelector({
    required this.daemons,
    required this.selectedDaemonDid,
    required this.state,
    required this.onSelect,
    required this.onRefresh,
  });

  final List<AgentSummary> daemons;
  final String? selectedDaemonDid;
  final AgentsState state;
  final ValueChanged<String> onSelect;
  final ValueChanged<AgentSummary> onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final responsive = context.awikiResponsive;
    return AppCardSection(
      padding: EdgeInsets.all(responsive.spacing(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.personalAgentSelectDaemon,
            style: TextStyle(
              color: const Color(0xFF101B32),
              fontSize: responsive.bodyMd,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: responsive.spacing(6)),
          Text(
            l10n.personalAgentRunsOnSelectedDaemon,
            style: TextStyle(
              color: const Color(0xFF66728A),
              fontSize: responsive.bodySm,
            ),
          ),
          SizedBox(height: responsive.spacing(12)),
          if (daemons.isEmpty)
            Text(
              l10n.personalAgentNoDaemons,
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.bodySm,
              ),
            )
          else
            Column(
              children: <Widget>[
                for (final daemon in daemons)
                  Padding(
                    padding: EdgeInsets.only(bottom: responsive.spacing(8)),
                    child: _PersonalAgentDaemonOption(
                      daemon: daemon,
                      selected: daemon.agentDid == selectedDaemonDid,
                      isRefreshing: state.isStatusQueryPending(daemon.agentDid),
                      onTap: () => onSelect(daemon.agentDid),
                      onRefresh: () => onRefresh(daemon),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PersonalAgentDaemonOption extends StatelessWidget {
  const _PersonalAgentDaemonOption({
    required this.daemon,
    required this.selected,
    required this.isRefreshing,
    required this.onTap,
    required this.onRefresh,
  });

  final AgentSummary daemon;
  final bool selected;
  final bool isRefreshing;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final responsive = context.awikiResponsive;
    final hasBootstrapKey = _daemonHasBootstrapPublicKey(
      daemon,
      daemon.latest.diagnosticsSummary,
    );
    final status = _personalAgentDaemonReady(daemon)
        ? hasBootstrapKey
              ? l10n.personalAgentReadyWithPublicKey
              : l10n.personalAgentReadyWaitingPublicKey
        : l10n.personalAgentDaemonNeedsAttention(daemon.latest.status);
    return AppPressableTile(
      onTap: onTap,
      selected: selected,
      semanticLabel: l10n.personalAgentSelectDaemonSemantic(
        localizeAgentTitle(l10n, daemon),
      ),
      semanticsIdentifier: 'personal-agent-daemon-option:${daemon.agentDid}',
      borderRadius: BorderRadius.circular(responsive.radius(10)),
      backgroundColor: const Color(0xFFF8FAFD),
      selectedBackgroundColor: const Color(0xFFEAF2FF),
      border: Border.all(
        color: selected ? const Color(0xFF9DC2FF) : const Color(0xFFE5EAF2),
      ),
      child: Padding(
        padding: EdgeInsets.all(responsive.spacing(12)),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF8A96AA),
              size: responsive.iconMd,
            ),
            SizedBox(width: responsive.spacing(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    localizeAgentTitle(l10n, daemon),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.bodySm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(3)),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.metaSm,
                    ),
                  ),
                ],
              ),
            ),
            _DaemonRefreshIconButton(
              isLoading: isRefreshing,
              size: responsive.displayScaled(30),
              onPressed: isRefreshing ? null : onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonalAgentReadinessNotice extends StatelessWidget {
  const _PersonalAgentReadinessNotice({
    required this.enabled,
    required this.daemon,
    required this.daemonReady,
    required this.hasBootstrapKey,
  });

  final bool enabled;
  final AgentSummary? daemon;
  final bool daemonReady;
  final bool hasBootstrapKey;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final responsive = context.awikiResponsive;
    final text = !enabled
        ? l10n.personalAgentFeatureDisabledNotice
        : daemon == null
        ? l10n.personalAgentNoDaemonNotice
        : !daemonReady
        ? l10n.personalAgentDaemonNotReadyNotice
        : !hasBootstrapKey
        ? l10n.personalAgentBootstrapKeyMissingNotice
        : l10n.personalAgentCanEnableNotice;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFFFE0A6)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF7A4E00),
          fontSize: responsive.bodySm,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PersonalAgentLimitsCard extends StatelessWidget {
  const _PersonalAgentLimitsCard({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final responsive = context.awikiResponsive;
    return AppCardSection(
      padding: EdgeInsets.all(responsive.spacing(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.personalAgentSafetyTitle,
            style: TextStyle(
              color: const Color(0xFF101B32),
              fontSize: responsive.bodyMd,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: responsive.spacing(10)),
          _PersonalAgentLimitRow(
            icon: CupertinoIcons.doc_text,
            text: l10n.personalAgentSafetyPlainText,
          ),
          _PersonalAgentLimitRow(
            icon: CupertinoIcons.pencil_outline,
            text: l10n.personalAgentSafetyDraftOnly,
          ),
          _PersonalAgentLimitRow(
            icon: CupertinoIcons.lock_shield,
            text: l10n.personalAgentSafetyNoPrimaryKey,
          ),
          if (!enabled)
            _PersonalAgentLimitRow(
              icon: CupertinoIcons.slash_circle,
              text: l10n.personalAgentSafetyFeatureDisabled,
            ),
        ],
      ),
    );
  }
}

class _PersonalAgentLimitRow extends StatelessWidget {
  const _PersonalAgentLimitRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.spacing(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: const Color(0xFF1B7A43), size: responsive.iconSm),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: const Color(0xFF344056),
                fontSize: responsive.bodySm,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _personalAgentDaemonReady(AgentSummary daemon) {
  final status = daemon.latest.status.trim().toLowerCase();
  return status == 'ready' || status == 'needs_upgrade';
}

String _personalAgentStateLabel({
  required bool enabled,
  required AgentSummary? daemon,
  required bool hasBootstrapKey,
  required AgentSummary? personalAgent,
  required bool isBusy,
  required AppLocalizations l10n,
}) {
  if (!enabled) {
    return l10n.personalAgentExperimentDisabled;
  }
  if (isBusy) {
    return l10n.personalAgentBusy;
  }
  if (daemon == null) {
    return l10n.personalAgentNoDaemon;
  }
  if (!_personalAgentDaemonReady(daemon)) {
    return l10n.personalAgentDaemonNotReady;
  }
  if (!hasBootstrapKey) {
    return l10n.personalAgentNotReady;
  }
  if (personalAgent != null) {
    return l10n.personalAgentEnabledState;
  }
  return l10n.personalAgentReadyToEnable;
}
