part of '../agents_page.dart';

class _AgentListPane extends StatelessWidget {
  const _AgentListPane({
    required this.state,
    required this.footer,
    required this.pendingAgentDids,
    required this.selectedAgentDid,
    required this.onCreateDaemon,
    required this.onCreateSkill,
    required this.isCreatingSkill,
    required this.onRefreshDaemon,
    required this.onSelect,
    required this.onSyncInventory,
  });

  final AgentsState state;
  final Widget? footer;
  final Set<String> pendingAgentDids;
  final String? selectedAgentDid;
  final VoidCallback onCreateDaemon;
  final VoidCallback onCreateSkill;
  final bool isCreatingSkill;
  final ValueChanged<AgentSummary> onRefreshDaemon;
  final ValueChanged<String> onSelect;
  final VoidCallback onSyncInventory;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return ColoredBox(
      key: const Key('agents-list-pane'),
      color: responsive.isCompact ? theme.background : theme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _AgentListHeader(
              isLoading: state.isLoading,
              isCreatingSkill: isCreatingSkill,
              isInstalling: state.isActionPending(
                AgentActionKeys.installCommand,
              ),
              onCreateSkill: onCreateSkill,
              onRefresh: onSyncInventory,
              onInstall: onCreateDaemon,
            ),
            Expanded(
              child: ListView(
                key: const Key('agents-hierarchy-scroll'),
                padding: responsive.isCompact
                    ? EdgeInsets.only(bottom: responsive.spacing(16))
                    : EdgeInsets.fromLTRB(
                        responsive.spacing(8),
                        responsive.spacing(8),
                        responsive.spacing(8),
                        responsive.spacing(16),
                      ),
                children: <Widget>[
                  if (responsive.isCompact)
                    _AgentListSectionHeader(
                      count: state.agents
                          .where((agent) => agent.isRuntime)
                          .length,
                    ),
                  if (state.error != null) ...<Widget>[
                    _AgentErrorBanner(
                      message: state.error!,
                      onRetry: onSyncInventory,
                    ),
                    SizedBox(height: responsive.spacing(10)),
                  ],
                  if (state.agents.isEmpty)
                    _AgentEmptyState(
                      isWaitingForDaemonInstall:
                          state.isWaitingForDaemonInstall,
                    ),
                  _AgentHierarchyList(
                    state: state,
                    pendingAgentDids: pendingAgentDids,
                    selectedAgentDid: selectedAgentDid,
                    onSelect: onSelect,
                    onRefreshDaemon: onRefreshDaemon,
                  ),
                  if (responsive.isCompact)
                    _AgentInstallDaemonRow(
                      onTap: onCreateDaemon,
                      disabled: state.isActionPending(
                        AgentActionKeys.installCommand,
                      ),
                    ),
                ],
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

class _AgentListHeader extends StatelessWidget {
  const _AgentListHeader({
    required this.isLoading,
    required this.isCreatingSkill,
    required this.isInstalling,
    required this.onCreateSkill,
    required this.onRefresh,
    required this.onInstall,
  });

  final bool isLoading;
  final bool isCreatingSkill;
  final bool isInstalling;
  final VoidCallback onCreateSkill;
  final VoidCallback onRefresh;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final refreshIcon = isLoading
        ? CupertinoActivityIndicator(radius: responsive.displayScaled(7))
        : Icon(
            CupertinoIcons.refresh,
            size: responsive.iconSm,
            color: theme.secondaryText,
          );
    final installIcon = Icon(
      CupertinoIcons.plus,
      size: responsive.iconMd,
      color: isInstalling ? theme.tertiaryText : theme.secondaryText,
    );

    if (responsive.isCompact) {
      return Container(
        key: const Key('agents-compact-list-header'),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(bottom: BorderSide(color: theme.border)),
        ),
        child: AwikiMeTopBar(
          title: context.l10n.agentPageTitle,
          leadingWidth: 0,
          trailingWidth: 108,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5.5),
          titleFontSize: awikiMeCompactTopBarTitleFontSize,
          titleFontWeight: awikiMeCompactTopBarTitleFontWeight,
          titleHeight: awikiMeCompactTopBarTitleHeight,
          leading: const SizedBox.shrink(),
          trailing: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TopBarActionButton(
                  key: const Key('agents-more-actions-button'),
                  onTap: isCreatingSkill || isLoading
                      ? null
                      : () => _showCompactAgentActions(
                          context,
                          onCreateSkill: onCreateSkill,
                          onRefresh: onRefresh,
                        ),
                  semanticsLabel: context.l10n.commonMoreActions,
                  tooltip: context.l10n.commonMoreActions,
                  child: isCreatingSkill || isLoading
                      ? CupertinoActivityIndicator(
                          radius: responsive.displayScaled(7),
                        )
                      : Icon(
                          CupertinoIcons.ellipsis,
                          color: theme.secondaryText,
                          size: responsive.iconMd,
                        ),
                ),
                const SizedBox(width: 12),
                TopBarActionButton(
                  key: const Key('agents-install-daemon-button'),
                  onTap: isInstalling ? null : onInstall,
                  semanticsLabel: context.l10n.agentInstallTitle,
                  tooltip: context.l10n.agentInstallTitle,
                  child: installIcon,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return AwikiSidebarHeader(
      key: const Key('agents-expanded-list-header'),
      title: context.l10n.agentPageTitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppIconButton(
            key: const Key('agent-skill-onboarding-button'),
            onPressed: isCreatingSkill ? null : onCreateSkill,
            semanticLabel: context.l10n.agentSkillCreateInstruction,
            tooltip: context.l10n.agentSkillCreateInstruction,
            size: responsive.displayScaled(32),
            isLoading: isCreatingSkill,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: const Icon(CupertinoIcons.command),
          ),
          SizedBox(width: responsive.spacing(4)),
          AppIconButton(
            key: const Key('agents-list-refresh-button'),
            onPressed: isLoading ? null : onRefresh,
            semanticLabel: context.l10n.agentRefreshList,
            tooltip: context.l10n.agentRefreshList,
            size: responsive.displayScaled(32),
            isLoading: isLoading,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: refreshIcon,
          ),
          SizedBox(width: responsive.spacing(4)),
          AppIconButton(
            key: const Key('agents-install-daemon-button'),
            onPressed: isInstalling ? null : onInstall,
            semanticLabel: context.l10n.agentInstallTitle,
            tooltip: context.l10n.agentInstallTitle,
            size: responsive.displayScaled(32),
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: installIcon,
          ),
        ],
      ),
    );
  }

  Future<void> _showCompactAgentActions(
    BuildContext context, {
    required VoidCallback onCreateSkill,
    required VoidCallback onRefresh,
  }) async {
    final action = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: <Widget>[
          CupertinoActionSheetAction(
            key: const Key('agent-skill-onboarding-button'),
            onPressed: () => Navigator.of(sheetContext).pop('skill'),
            child: Text(context.l10n.agentSkillCreateInstruction),
          ),
          CupertinoActionSheetAction(
            key: const Key('agents-list-refresh-button'),
            onPressed: () => Navigator.of(sheetContext).pop('refresh'),
            child: Text(context.l10n.agentRefreshList),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(context.l10n.commonCancel),
        ),
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (action == 'skill') {
      onCreateSkill();
    } else if (action == 'refresh') {
      onRefresh();
    }
  }
}

class _AgentListSectionHeader extends StatelessWidget {
  const _AgentListSectionHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return SizedBox(
      key: const Key('agents-compact-section-header'),
      height: 60,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(bottom: BorderSide(color: theme.border)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.l10n.agentMineSection,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: responsive.bodyMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: responsive.bodySm,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentInstallDaemonRow extends StatelessWidget {
  const _AgentInstallDaemonRow({required this.onTap, required this.disabled});

  final VoidCallback onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppPressable(
      key: const Key('agents-install-daemon-row'),
      onTap: disabled ? null : onTap,
      semanticLabel: context.l10n.agentInstallDaemonAction,
      enabled: !disabled,
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        height: 56,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: responsive.spacing(24)),
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(top: BorderSide(color: theme.border)),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                CupertinoIcons.arrow_down_to_line,
                color: theme.primary,
                size: responsive.iconSm,
              ),
              SizedBox(width: responsive.spacing(12)),
              Text(
                context.l10n.agentInstallDaemonAction,
                style: TextStyle(
                  color: theme.primary,
                  fontSize: responsive.bodySm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentEmptyState extends StatelessWidget {
  const _AgentEmptyState({required this.isWaitingForDaemonInstall});

  final bool isWaitingForDaemonInstall;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final type = theme.typographyFor(
      responsive.isCompact
          ? AwikiMeTypographyMode.compact
          : AwikiMeTypographyMode.expanded,
    );
    return SizedBox(
      height: responsive.displayScaled(responsive.isCompact ? 260 : 220),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: responsive.spacing(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isWaitingForDaemonInstall
                    ? CupertinoIcons.clock
                    : CupertinoIcons.desktopcomputer,
                color: theme.tertiaryText,
                size: responsive.displayScaled(28),
              ),
              SizedBox(height: responsive.spacing(10)),
              Text(
                context.l10n.agentEmpty,
                textAlign: TextAlign.center,
                style: type.cardTitle.copyWith(color: theme.title),
              ),
              SizedBox(height: responsive.spacing(5)),
              Text(
                isWaitingForDaemonInstall
                    ? context.l10n.agentEmptyInstallWaitingHost
                    : context.l10n.agentEmptyWaitingHost,
                textAlign: TextAlign.center,
                style: type.cardSubtitle.copyWith(color: theme.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentHierarchyList extends StatelessWidget {
  const _AgentHierarchyList({
    required this.state,
    required this.pendingAgentDids,
    required this.selectedAgentDid,
    required this.onSelect,
    required this.onRefreshDaemon,
  });

  final AgentsState state;
  final Set<String> pendingAgentDids;
  final String? selectedAgentDid;
  final ValueChanged<String> onSelect;
  final ValueChanged<AgentSummary> onRefreshDaemon;

  @override
  Widget build(BuildContext context) {
    final groups = _AgentTreeGroup.fromState(state);
    return Column(
      children: <Widget>[
        for (final group in groups) ...<Widget>[
          _AgentDaemonGroup(
            group: group,
            state: state,
            pendingAgentDids: pendingAgentDids,
            selectedAgentDid: selectedAgentDid,
            onSelect: onSelect,
            onRefreshDaemon: onRefreshDaemon,
          ),
        ],
      ],
    );
  }
}

class _AgentTreeGroup {
  const _AgentTreeGroup({
    required this.daemon,
    required this.runtimes,
    required this.runtimeCreationOverlays,
    required this.pendingRuntimeCreations,
  });

  final AgentSummary? daemon;
  final List<AgentSummary> runtimes;
  final Map<String, PendingRuntimeCreation> runtimeCreationOverlays;
  final List<PendingRuntimeCreation> pendingRuntimeCreations;

  static List<_AgentTreeGroup> fromState(AgentsState state) {
    final agents = state.agents;
    final daemons = agents.where((agent) => agent.isDaemon).toList();
    final groupedRuntimes = <String, List<AgentSummary>>{};
    final orphanRuntimes = <AgentSummary>[];
    final daemonDids = daemons.map((agent) => agent.agentDid).toSet();
    for (final runtime in agents.where((agent) => agent.isRuntime)) {
      final daemonDid = runtime.daemonAgentDid;
      if (daemonDid != null && daemonDids.contains(daemonDid)) {
        groupedRuntimes
            .putIfAbsent(daemonDid, () => <AgentSummary>[])
            .add(runtime);
      } else {
        orphanRuntimes.add(runtime);
      }
    }
    final groups = <_AgentTreeGroup>[];
    for (final daemon in daemons) {
      final runtimes =
          groupedRuntimes[daemon.agentDid] ?? const <AgentSummary>[];
      final runtimeCreationOverlays = <String, PendingRuntimeCreation>{};
      final unrepresentedPendingCreations = <PendingRuntimeCreation>[];
      for (final pending in state.pendingRuntimeCreationsFor(daemon.agentDid)) {
        AgentSummary? representedRuntime;
        for (final runtime in runtimes) {
          if (pending.matchesRuntimeAgent(runtime)) {
            representedRuntime = runtime;
            break;
          }
        }
        if (representedRuntime == null) {
          unrepresentedPendingCreations.add(pending);
        } else {
          runtimeCreationOverlays[representedRuntime.agentDid] = pending;
        }
      }
      groups.add(
        _AgentTreeGroup(
          daemon: daemon,
          runtimes: runtimes,
          runtimeCreationOverlays: runtimeCreationOverlays,
          pendingRuntimeCreations: unrepresentedPendingCreations,
        ),
      );
    }
    if (orphanRuntimes.isNotEmpty) {
      groups.add(
        _AgentTreeGroup(
          daemon: null,
          runtimes: orphanRuntimes,
          runtimeCreationOverlays: const <String, PendingRuntimeCreation>{},
          pendingRuntimeCreations: const <PendingRuntimeCreation>[],
        ),
      );
    }
    return groups;
  }
}

class _AgentDaemonGroup extends StatelessWidget {
  const _AgentDaemonGroup({
    required this.group,
    required this.state,
    required this.pendingAgentDids,
    required this.selectedAgentDid,
    required this.onSelect,
    required this.onRefreshDaemon,
  });

  final _AgentTreeGroup group;
  final AgentsState state;
  final Set<String> pendingAgentDids;
  final String? selectedAgentDid;
  final ValueChanged<String> onSelect;
  final ValueChanged<AgentSummary> onRefreshDaemon;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final daemon = group.daemon;
    final runtimes = group.runtimes;
    final pendingRuntimeCreations = group.pendingRuntimeCreations;
    if (daemon == null) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: responsive.isCompact ? 0 : responsive.spacing(8),
        ),
        child: _OrphanRuntimeGroup(
          runtimes: runtimes,
          pendingAgentDids: pendingAgentDids,
          selectedAgentDid: selectedAgentDid,
          onSelect: onSelect,
        ),
      );
    }
    final runtimeTiles = <Widget>[
      for (final runtime in runtimes)
        _AgentListTile(
          agent: runtime,
          pendingAgentDids: pendingAgentDids,
          pendingDaemonUpgrades: state.pendingDaemonUpgrades,
          cancellingDaemonUpgrades: state.cancellingDaemonUpgrades,
          daemonUpgradeErrors: state.daemonUpgradeErrors,
          daemonUpgradeProgress: state.daemonUpgradeProgress,
          statusQueryErrors: state.statusQueryErrors,
          isDeleting: state.isDeletingAgent(runtime.agentDid),
          pendingRuntimeCreation:
              group.runtimeCreationOverlays[runtime.agentDid],
          selected: selectedAgentDid == runtime.agentDid,
          onTap: () => onSelect(runtime.agentDid),
          depth: 1,
        ),
      for (final pending in pendingRuntimeCreations)
        _PendingRuntimeCreationTile(pending: pending),
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: responsive.isCompact ? 0 : responsive.spacing(8),
      ),
      child: Column(
        children: <Widget>[
          _AgentListTile(
            agent: daemon,
            pendingAgentDids: pendingAgentDids,
            pendingDaemonUpgrades: state.pendingDaemonUpgrades,
            cancellingDaemonUpgrades: state.cancellingDaemonUpgrades,
            daemonUpgradeErrors: state.daemonUpgradeErrors,
            daemonUpgradeProgress: state.daemonUpgradeProgress,
            statusQueryErrors: state.statusQueryErrors,
            isDeleting: state.isDeletingAgent(daemon.agentDid),
            selected: selectedAgentDid == daemon.agentDid,
            onTap: () => onSelect(daemon.agentDid),
            runtimeCount: runtimes.length + pendingRuntimeCreations.length,
            onRefresh: state.isStatusQueryPending(daemon.agentDid)
                ? null
                : () => onRefreshDaemon(daemon),
            isRefreshing: state.isStatusQueryPending(daemon.agentDid),
          ),
          if (runtimes.isEmpty && pendingRuntimeCreations.isEmpty)
            _EmptyRuntimeHint()
          else if (responsive.isCompact)
            _CompactAgentChildrenTree(
              daemonAgentDid: daemon.agentDid,
              children: runtimeTiles,
            )
          else
            ...runtimeTiles,
        ],
      ),
    );
  }
}

class _CompactAgentChildrenTree extends StatelessWidget {
  const _CompactAgentChildrenTree({
    required this.daemonAgentDid,
    required this.children,
  });

  final String daemonAgentDid;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Stack(
      children: <Widget>[
        Column(children: children),
        Positioned(
          left: responsive.displayScaled(41),
          top: responsive.displayScaled(14),
          bottom: responsive.displayScaled(14),
          child: Container(
            key: ValueKey<String>('agent-tree-vertical-$daemonAgentDid'),
            width: responsive.displayScaled(1),
            color: AwikiMePalette.navigationBorder,
          ),
        ),
      ],
    );
  }
}

class _OrphanRuntimeGroup extends StatelessWidget {
  const _OrphanRuntimeGroup({
    required this.runtimes,
    required this.pendingAgentDids,
    required this.selectedAgentDid,
    required this.onSelect,
  });

  final List<AgentSummary> runtimes;
  final Set<String> pendingAgentDids;
  final String? selectedAgentDid;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            responsive.spacing(12),
            responsive.spacing(2),
            responsive.spacing(12),
            responsive.spacing(7),
          ),
          child: Text(
            context.l10n.agentListOrphanGroup,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final runtime in runtimes)
          _AgentListTile(
            agent: runtime,
            pendingAgentDids: pendingAgentDids,
            pendingDaemonUpgrades: const <String, PendingDaemonUpgrade>{},
            cancellingDaemonUpgrades:
                const <String, PendingDaemonUpgradeCancel>{},
            daemonUpgradeProgress: const <String, DaemonUpgradeProgress>{},
            statusQueryErrors: const <String, String>{},
            isDeleting: false,
            selected: selectedAgentDid == runtime.agentDid,
            onTap: () => onSelect(runtime.agentDid),
          ),
      ],
    );
  }
}

class _EmptyRuntimeHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        responsive.isCompact
            ? responsive.displayScaled(64)
            : responsive.spacing(42),
        responsive.spacing(5),
        responsive.spacing(12),
        responsive.spacing(9),
      ),
      decoration: responsive.isCompact
          ? BoxDecoration(
              color: theme.surface,
              border: Border(bottom: BorderSide(color: theme.border)),
            )
          : null,
      child: Text(
        context.l10n.agentListNoRuntime,
        style: TextStyle(
          color: theme.tertiaryText,
          fontSize: responsive.metaSm,
        ),
      ),
    );
  }
}

class _AgentTreeConnector extends StatelessWidget {
  const _AgentTreeConnector();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return SizedBox(
      width: responsive.spacing(12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 1,
          height: responsive.displayScaled(38),
          color: context.awikiTheme.border,
        ),
      ),
    );
  }
}

class _CompactAgentTreeBranch extends StatelessWidget {
  const _CompactAgentTreeBranch({required this.identifier});

  final String identifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return SizedBox(
      key: ValueKey<String>('agent-tree-branch-$identifier'),
      width: responsive.displayScaled(20),
      height: responsive.displayScaled(1),
      child: const ColoredBox(color: AwikiMePalette.navigationBorder),
    );
  }
}

class _PendingRuntimeCreationTile extends StatelessWidget {
  const _PendingRuntimeCreationTile({required this.pending});

  final PendingRuntimeCreation pending;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final visualStatus = _pendingRuntimeCreationVisualStatus(pending);
    final content = Row(
      children: <Widget>[
        if (!responsive.isCompact) const _AgentTreeConnector(),
        if (!responsive.isCompact) SizedBox(width: responsive.spacing(8)),
        if (responsive.isCompact)
          e2eSemantics(
            identifier: _runtimeAgentRowE2eIdentifier(pending.handle),
            child: Container(
              width: responsive.displayScaled(responsive.isCompact ? 42 : 28),
              height: responsive.displayScaled(responsive.isCompact ? 42 : 28),
              decoration: BoxDecoration(
                color: theme.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: pending.isWaitingForStatus
                    ? Icon(
                        CupertinoIcons.clock,
                        color: theme.secondaryText,
                        size: responsive.iconSm,
                      )
                    : CupertinoActivityIndicator(
                        radius: responsive.displayScaled(7),
                      ),
              ),
            ),
          )
        else
          AgentStatusIndicatorOverlay(
            key: ValueKey<String>(
              'agent-list-status-anchor-pending-${pending.requestId}',
            ),
            status: visualStatus,
            dotSize: responsive.displayScaled(9),
            child: e2eSemantics(
              identifier: _runtimeAgentRowE2eIdentifier(pending.handle),
              child: Container(
                width: responsive.displayScaled(28),
                height: responsive.displayScaled(28),
                decoration: BoxDecoration(
                  color: theme.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: pending.isWaitingForStatus
                      ? Icon(
                          CupertinoIcons.clock,
                          color: theme.secondaryText,
                          size: responsive.iconSm,
                        )
                      : CupertinoActivityIndicator(
                          radius: responsive.displayScaled(7),
                        ),
                ),
              ),
            ),
          ),
        SizedBox(
          width: responsive.isCompact
              ? responsive.displayScaled(16)
              : responsive.spacing(10),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                pending.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.title,
                  fontSize: responsive.bodySm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: responsive.spacing(2)),
              Row(
                children: <Widget>[
                  if (responsive.isCompact) ...<Widget>[
                    AgentStatusDot(
                      key: ValueKey<String>(
                        'agent-list-status-anchor-pending-${pending.requestId}',
                      ),
                      status: visualStatus,
                      size: 8,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      _pendingRuntimeCreationSubtitle(context, pending),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.tertiaryText,
                        fontSize: responsive.metaSm,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(
        left: responsive.isCompact ? 0 : responsive.spacing(26),
        bottom: responsive.isCompact ? 0 : responsive.spacing(2),
      ),
      child: Container(
        constraints: BoxConstraints(
          minHeight: responsive.isCompact ? 75.5 : responsive.displayScaled(48),
        ),
        decoration: BoxDecoration(
          color: theme.surface,
          border: responsive.isCompact
              ? Border(bottom: BorderSide(color: theme.border))
              : null,
        ),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: <Widget>[
            if (responsive.isCompact)
              Positioned(
                left: responsive.displayScaled(41),
                top: 0,
                bottom: 0,
                child: Align(
                  child: _CompactAgentTreeBranch(identifier: pending.requestId),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                responsive.isCompact
                    ? responsive.displayScaled(61)
                    : responsive.spacing(8),
                responsive.spacing(8),
                responsive.isCompact
                    ? responsive.displayScaled(14)
                    : responsive.spacing(8),
                responsive.spacing(8),
              ),
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentListTile extends StatelessWidget {
  const _AgentListTile({
    required this.agent,
    required this.pendingAgentDids,
    required this.pendingDaemonUpgrades,
    required this.cancellingDaemonUpgrades,
    required this.selected,
    required this.onTap,
    this.daemonUpgradeErrors = const <String, String>{},
    this.daemonUpgradeProgress = const <String, DaemonUpgradeProgress>{},
    this.statusQueryErrors = const <String, String>{},
    this.depth = 0,
    this.runtimeCount,
    this.onRefresh,
    this.isRefreshing = false,
    this.isDeleting = false,
    this.pendingRuntimeCreation,
  });

  final AgentSummary agent;
  final Set<String> pendingAgentDids;
  final Map<String, PendingDaemonUpgrade> pendingDaemonUpgrades;
  final Map<String, PendingDaemonUpgradeCancel> cancellingDaemonUpgrades;
  final Map<String, String> daemonUpgradeErrors;
  final Map<String, DaemonUpgradeProgress> daemonUpgradeProgress;
  final Map<String, String> statusQueryErrors;
  final bool selected;
  final VoidCallback onTap;
  final int depth;
  final int? runtimeCount;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final bool isDeleting;
  final PendingRuntimeCreation? pendingRuntimeCreation;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final isChild = depth > 0;
    final title = localizeAgentTitle(context.l10n, agent);
    final daemonUpgradeError = daemonUpgradeErrors[agent.agentDid];
    final daemonUpgradeProgress = this.daemonUpgradeProgress[agent.agentDid];
    final visualStatus = pendingRuntimeCreation == null
        ? AgentVisualStatus.fromAgent(
            agent,
            hasPendingTurn:
                isDeleting || pendingAgentDids.contains(agent.agentDid),
            isPendingUpgrade: pendingDaemonUpgrades.containsKey(agent.agentDid),
            hasUpgradeError: pendingDaemonUpgrades.containsKey(agent.agentDid)
                ? false
                : daemonUpgradeError != null,
            hasStatusQueryError:
                agent.isDaemon && statusQueryErrors.containsKey(agent.agentDid),
          )
        : _pendingRuntimeCreationVisualStatus(pendingRuntimeCreation!);
    return Padding(
      padding: EdgeInsets.only(
        left: responsive.isCompact
            ? 0
            : isChild
            ? responsive.spacing(26)
            : 0,
        bottom: responsive.isCompact ? 0 : responsive.spacing(2),
      ),
      child: AppPressableTile(
        key: ValueKey<String>('agent-list-tile-${agent.agentDid}'),
        onTap: onTap,
        selected: selected,
        semanticLabel: title,
        semanticsIdentifier: agent.isRuntime
            ? _runtimeAgentRowE2eIdentifier(agent.handle)
            : null,
        borderRadius: responsive.isCompact
            ? BorderRadius.zero
            : BorderRadius.circular(responsive.radius(10)),
        backgroundColor: responsive.isCompact
            ? theme.surface
            : CupertinoColors.transparent,
        selectedBackgroundColor: theme.body.withValues(alpha: 0.07),
        border: responsive.isCompact
            ? Border(bottom: BorderSide(color: theme.border))
            : null,
        child: SizedBox(
          height: responsive.isCompact ? (isChild ? 74.5 : 64) : null,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              if (isChild && responsive.isCompact)
                Positioned(
                  left: responsive.displayScaled(41),
                  top: 0,
                  bottom: 0,
                  child: Align(
                    child: _CompactAgentTreeBranch(identifier: agent.agentDid),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  responsive.isCompact
                      ? responsive.displayScaled(isChild ? 61 : 18)
                      : responsive.spacing(8),
                  responsive.spacing(7),
                  responsive.isCompact
                      ? responsive.displayScaled(12)
                      : responsive.spacing(8),
                  responsive.spacing(7),
                ),
                child: Row(
                  children: <Widget>[
                    if (isChild && !responsive.isCompact) ...<Widget>[
                      const _AgentTreeConnector(),
                      SizedBox(width: responsive.spacing(8)),
                    ],
                    if (responsive.isCompact)
                      _AgentKindIcon(agent: agent, isChild: isChild)
                    else
                      AgentStatusIndicatorOverlay(
                        key: ValueKey<String>(
                          'agent-list-status-anchor-${agent.agentDid}',
                        ),
                        status: visualStatus,
                        dotSize: responsive.displayScaled(9),
                        child: _AgentKindIcon(agent: agent, isChild: isChild),
                      ),
                    SizedBox(
                      width: responsive.isCompact && isChild
                          ? responsive.displayScaled(16)
                          : responsive.spacing(10),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.title,
                              fontSize: responsive.bodySm,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: responsive.spacing(2)),
                          Row(
                            children: <Widget>[
                              if (responsive.isCompact) ...<Widget>[
                                AgentStatusDot(
                                  key: ValueKey<String>(
                                    'agent-list-status-anchor-${agent.agentDid}',
                                  ),
                                  status: visualStatus,
                                  size: 8,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Expanded(
                                child: Text(
                                  _agentListSubtitle(
                                    context,
                                    agent,
                                    runtimeCount,
                                    visualStatus,
                                    isUpgrading: pendingDaemonUpgrades
                                        .containsKey(agent.agentDid),
                                    isCancelling: cancellingDaemonUpgrades
                                        .containsKey(agent.agentDid),
                                    upgradeProgress: daemonUpgradeProgress,
                                    upgradeError: daemonUpgradeError,
                                    isDeleting: isDeleting,
                                    pendingRuntimeCreation:
                                        pendingRuntimeCreation,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: theme.tertiaryText,
                                    fontSize: responsive.metaSm,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (agent.isDaemon && !responsive.isCompact) ...<Widget>[
                      SizedBox(width: responsive.spacing(6)),
                      _DaemonRefreshIconButton(
                        onPressed: onRefresh,
                        isLoading: isRefreshing,
                        size: responsive.displayScaled(28),
                      ),
                    ],
                    if (responsive.isCompact) ...<Widget>[
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.chevron_right,
                        color: theme.tertiaryText,
                        size: responsive.iconSm,
                      ),
                      const SizedBox(width: 12),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentKindIcon extends StatelessWidget {
  const _AgentKindIcon({required this.agent, required this.isChild});

  final AgentSummary agent;
  final bool isChild;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final title = localizeAgentTitle(context.l10n, agent).trim();
    final size = responsive.displayScaled(
      responsive.isCompact
          ? agent.isDaemon
                ? 36
                : 42
          : isChild
          ? 28
          : 30,
    );
    if (agent.isRuntime) {
      return AvatarBadge(
        key: ValueKey<String>('agent-list-kind-icon-${agent.agentDid}'),
        seed: title,
        size: size,
      );
    }
    if (responsive.isCompact) {
      return SizedBox.square(
        key: ValueKey<String>('agent-list-kind-icon-${agent.agentDid}'),
        dimension: size,
        child: Icon(
          CupertinoIcons.desktopcomputer,
          color: theme.secondaryText,
          size: responsive.displayScaled(22),
        ),
      );
    }
    return Container(
      key: ValueKey<String>('agent-list-kind-icon-${agent.agentDid}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.subtleSurface,
        borderRadius: BorderRadius.circular(responsive.radius(9)),
      ),
      child: Icon(
        CupertinoIcons.desktopcomputer,
        color: theme.secondaryText,
        size: responsive.iconSm,
      ),
    );
  }
}

class _DaemonRefreshIconButton extends StatelessWidget {
  const _DaemonRefreshIconButton({
    required this.onPressed,
    required this.isLoading,
    required this.size,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final enabled = onPressed != null && !isLoading;
    final color = enabled ? theme.secondaryText : theme.tertiaryText;
    return AppIconButton(
      onPressed: onPressed,
      semanticLabel: context.l10n.agentRefreshStatus,
      tooltip: context.l10n.agentRefreshStatus,
      size: size,
      isLoading: isLoading,
      borderRadius: BorderRadius.circular(size / 2),
      child: Icon(CupertinoIcons.refresh, size: size * 0.52, color: color),
    );
  }
}

String _agentListSubtitle(
  BuildContext context,
  AgentSummary agent,
  int? runtimeCount,
  AgentVisualStatus visualStatus, {
  bool isUpgrading = false,
  bool isCancelling = false,
  DaemonUpgradeProgress? upgradeProgress,
  String? upgradeError,
  bool isDeleting = false,
  PendingRuntimeCreation? pendingRuntimeCreation,
}) {
  final l10n = context.l10n;
  if (agent.isDaemon) {
    return localizeAgentListSubtitle(
      l10n,
      const AgentRuntimeDisplay(label: 'Daemon', isKnown: true),
      visualStatus,
      runtimeCount: runtimeCount ?? 0,
      isUpgrading: isUpgrading,
      isCancelling: isCancelling,
      upgradeProgress: upgradeProgress,
      upgradeError: upgradeError,
      isDeleting: isDeleting,
    );
  }
  if (pendingRuntimeCreation != null) {
    return _pendingRuntimeCreationSubtitle(context, pendingRuntimeCreation);
  }
  return localizeAgentListSubtitle(
    l10n,
    agentRuntimeDisplay(agent),
    visualStatus,
    isRuntime: true,
    isDeleting: isDeleting,
  );
}

AgentVisualStatus _pendingRuntimeCreationVisualStatus(
  PendingRuntimeCreation pending,
) {
  return pending.isWaitingForStatus
      ? const AgentVisualStatus(AgentVisualStatusKind.unknown)
      : const AgentVisualStatus(
          AgentVisualStatusKind.processing,
          rawStatus: 'creating',
        );
}

String _pendingRuntimeCreationSubtitle(
  BuildContext context,
  PendingRuntimeCreation pending,
) {
  final runtimeDisplay = agentRuntimeDisplayFor(runtime: pending.runtime);
  return pending.isWaitingForStatus
      ? context.l10n.agentListRuntimeWaitingStatus(runtimeDisplay.label)
      : context.l10n.agentListRuntimeCreating(runtimeDisplay.label);
}

String? _runtimeAgentRowE2eIdentifier(String? handle) {
  final normalizedHandle = handle?.trim().toLowerCase();
  if (normalizedHandle == null || normalizedHandle.isEmpty) {
    return null;
  }
  return 'e2e-agent-runtime-row-$normalizedHandle';
}

String _formatBytes(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  if (unit == 0) {
    return '${bytes}B';
  }
  return '${value.toStringAsFixed(value >= 10 ? 1 : 2)}${units[unit]}';
}

String _upgradeSourceLabel(
  BuildContext context,
  DaemonUpgradeProgress progress,
) {
  final parts = <String>[
    if (progress.sourceUrl != null) progress.sourceUrl!,
    if (progress.route != null) _upgradeRouteLabel(context, progress.route!),
  ];
  return parts.isEmpty
      ? context.l10n.daemonUpgradePreparingDownload
      : parts.join(' · ');
}

String _upgradeRouteLabel(BuildContext context, String route) {
  if (route == 'direct') {
    return context.l10n.daemonUpgradeRouteDirect;
  }
  if (route == 'environment_proxy') {
    return context.l10n.daemonUpgradeRouteEnvironmentProxy;
  }
  if (route.startsWith('local_proxy:')) {
    return context.l10n.daemonUpgradeRouteLocalProxy(
      route.substring('local_proxy:'.length),
    );
  }
  return route;
}
