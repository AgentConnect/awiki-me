part of '../agents_page.dart';

class _AgentListPane extends StatelessWidget {
  const _AgentListPane({
    required this.state,
    required this.footer,
    required this.pendingAgentDids,
    required this.selectedAgentDid,
    required this.onCreateDaemon,
    required this.onRefreshDaemon,
    required this.onSelect,
    required this.onRetry,
  });

  final AgentsState state;
  final Widget? footer;
  final Set<String> pendingAgentDids;
  final String? selectedAgentDid;
  final VoidCallback onCreateDaemon;
  final ValueChanged<AgentSummary> onRefreshDaemon;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.spacing(18),
              responsive.spacing(16),
              responsive.spacing(18),
              responsive.spacing(10),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '智能体',
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.titleXl,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                AppIconButton(
                  onPressed:
                      state.isActionPending(AgentActionKeys.installCommand)
                      ? null
                      : onCreateDaemon,
                  semanticLabel: '创建 Daemon',
                  tooltip: '创建 Daemon',
                  size: responsive.displayScaled(34),
                  child: const Icon(CupertinoIcons.plus_circle_fill),
                ),
              ],
            ),
          ),
          if (state.isLoading) const CupertinoActivityIndicator(),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                responsive.spacing(12),
                responsive.spacing(8),
                responsive.spacing(12),
                responsive.spacing(16),
              ),
              children: <Widget>[
                if (state.error != null) ...<Widget>[
                  _AgentErrorBanner(message: state.error!, onRetry: onRetry),
                  SizedBox(height: responsive.spacing(10)),
                ],
                if (state.agents.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(responsive.spacing(12)),
                    child: Text(
                      '暂无代理',
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.bodySm,
                      ),
                    ),
                  ),
                _AgentHierarchyList(
                  state: state,
                  pendingAgentDids: pendingAgentDids,
                  selectedAgentDid: selectedAgentDid,
                  onSelect: onSelect,
                  onRefreshDaemon: onRefreshDaemon,
                ),
              ],
            ),
          ),
          if (footer != null) footer!,
        ],
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
    required this.pendingRuntimeCreations,
  });

  final AgentSummary? daemon;
  final List<AgentSummary> runtimes;
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
    return <_AgentTreeGroup>[
      for (final daemon in daemons)
        _AgentTreeGroup(
          daemon: daemon,
          runtimes: groupedRuntimes[daemon.agentDid] ?? const <AgentSummary>[],
          pendingRuntimeCreations: state.pendingRuntimeCreationsFor(
            daemon.agentDid,
          ),
        ),
      if (orphanRuntimes.isNotEmpty)
        _AgentTreeGroup(
          daemon: null,
          runtimes: orphanRuntimes,
          pendingRuntimeCreations: const <PendingRuntimeCreation>[],
        ),
    ];
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
        padding: EdgeInsets.only(bottom: responsive.spacing(10)),
        child: _OrphanRuntimeGroup(
          runtimes: runtimes,
          pendingAgentDids: pendingAgentDids,
          selectedAgentDid: selectedAgentDid,
          onSelect: onSelect,
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.spacing(10)),
      child: Column(
        children: <Widget>[
          _AgentListTile(
            agent: daemon,
            pendingAgentDids: pendingAgentDids,
            pendingDaemonUpgrades: state.pendingDaemonUpgrades,
            cancellingDaemonUpgrades: state.cancellingDaemonUpgrades,
            daemonUpgradeErrors: state.daemonUpgradeErrors,
            daemonUpgradeProgress: state.daemonUpgradeProgress,
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
          else ...<Widget>[
            for (final runtime in runtimes)
              _AgentListTile(
                agent: runtime,
                pendingAgentDids: pendingAgentDids,
                pendingDaemonUpgrades: state.pendingDaemonUpgrades,
                cancellingDaemonUpgrades: state.cancellingDaemonUpgrades,
                daemonUpgradeErrors: state.daemonUpgradeErrors,
                daemonUpgradeProgress: state.daemonUpgradeProgress,
                isDeleting: state.isDeletingAgent(runtime.agentDid),
                selected: selectedAgentDid == runtime.agentDid,
                onTap: () => onSelect(runtime.agentDid),
                depth: 1,
              ),
            for (final pending in pendingRuntimeCreations)
              _PendingRuntimeCreationTile(pending: pending),
          ],
        ],
      ),
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
            '未关联代理',
            style: TextStyle(
              color: const Color(0xFF66728A),
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w700,
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
    return Padding(
      padding: EdgeInsets.only(
        left: responsive.spacing(30),
        right: responsive.spacing(4),
        bottom: responsive.spacing(6),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 1,
            height: responsive.displayScaled(28),
            color: const Color(0xFFDDE5F0),
          ),
          SizedBox(width: responsive.spacing(12)),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.spacing(10),
                vertical: responsive.spacing(8),
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FD),
                borderRadius: BorderRadius.circular(responsive.radius(8)),
                border: Border.all(color: const Color(0xFFE8EDF5)),
              ),
              child: Text(
                '尚未创建 Runtime Agent',
                style: TextStyle(
                  color: const Color(0xFF66728A),
                  fontSize: responsive.metaSm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingRuntimeCreationTile extends StatelessWidget {
  const _PendingRuntimeCreationTile({required this.pending});

  final PendingRuntimeCreation pending;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final waiting = pending.isWaitingForStatus;
    final visualStatus = waiting
        ? const AgentVisualStatus(AgentVisualStatusKind.unknown)
        : const AgentVisualStatus(
            AgentVisualStatusKind.processing,
            rawStatus: 'creating',
          );
    return Padding(
      padding: EdgeInsets.only(
        left: responsive.spacing(30),
        bottom: responsive.spacing(6),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: responsive.spacing(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 1,
                height: responsive.displayScaled(50),
                color: const Color(0xFFDDE5F0),
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(responsive.spacing(10)),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBFE),
                borderRadius: BorderRadius.circular(responsive.radius(8)),
                border: Border.all(color: const Color(0xFFE8EDF5)),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: responsive.displayScaled(28),
                    height: responsive.displayScaled(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C4DFF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(responsive.radius(8)),
                    ),
                    child: Center(
                      child: waiting
                          ? Icon(
                              CupertinoIcons.clock,
                              color: const Color(0xFF66728A),
                              size: responsive.iconSm,
                            )
                          : CupertinoActivityIndicator(
                              radius: responsive.displayScaled(7),
                            ),
                    ),
                  ),
                  SizedBox(width: responsive.spacing(10)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          pending.displayName,
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
                          waiting
                              ? '${pending.runtime} · 创建状态暂未返回，可刷新查看'
                              : '${pending.runtime} · 创建中',
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
                  SizedBox(width: responsive.spacing(8)),
                  AgentStatusDot(status: visualStatus),
                ],
              ),
            ),
          ),
        ],
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
    this.depth = 0,
    this.runtimeCount,
    this.onRefresh,
    this.isRefreshing = false,
    this.isDeleting = false,
  });

  final AgentSummary agent;
  final Set<String> pendingAgentDids;
  final Map<String, PendingDaemonUpgrade> pendingDaemonUpgrades;
  final Map<String, PendingDaemonUpgradeCancel> cancellingDaemonUpgrades;
  final Map<String, String> daemonUpgradeErrors;
  final Map<String, DaemonUpgradeProgress> daemonUpgradeProgress;
  final bool selected;
  final VoidCallback onTap;
  final int depth;
  final int? runtimeCount;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final isChild = depth > 0;
    final title = AgentDisplayName.title(agent);
    final daemonUpgradeError = daemonUpgradeErrors[agent.agentDid];
    final daemonUpgradeProgress = this.daemonUpgradeProgress[agent.agentDid];
    final visualStatus = AgentVisualStatus.fromAgent(
      agent,
      hasPendingTurn: isDeleting || pendingAgentDids.contains(agent.agentDid),
      isPendingUpgrade: pendingDaemonUpgrades.containsKey(agent.agentDid),
      hasUpgradeError: pendingDaemonUpgrades.containsKey(agent.agentDid)
          ? false
          : daemonUpgradeError != null,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: isChild ? responsive.spacing(30) : 0,
        bottom: responsive.spacing(6),
      ),
      child: AppPressableTile(
        onTap: onTap,
        selected: selected,
        semanticLabel: title,
        borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
        backgroundColor: CupertinoColors.transparent,
        selectedBackgroundColor: const Color(0xFFE8F0FF),
        child: Row(
          children: <Widget>[
            if (isChild) ...<Widget>[
              SizedBox(
                width: responsive.spacing(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 1,
                    height: responsive.displayScaled(50),
                    color: const Color(0xFFDDE5F0),
                  ),
                ),
              ),
              SizedBox(width: responsive.spacing(8)),
            ],
            Expanded(
              child: Container(
                padding: EdgeInsets.all(
                  isChild ? responsive.spacing(10) : responsive.spacing(12),
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEAF2FF)
                      : isChild
                      ? const Color(0xFFFAFBFE)
                      : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(responsive.radius(8)),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFBBD2FF)
                        : isChild
                        ? const Color(0xFFE8EDF5)
                        : const Color(0xFFE5EAF2),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    _AgentKindIcon(agent: agent, isChild: isChild),
                    SizedBox(width: responsive.spacing(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
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
                            _agentListSubtitle(
                              agent,
                              runtimeCount,
                              visualStatus,
                              isUpgrading: pendingDaemonUpgrades.containsKey(
                                agent.agentDid,
                              ),
                              isCancelling: cancellingDaemonUpgrades
                                  .containsKey(agent.agentDid),
                              upgradeProgress: daemonUpgradeProgress,
                              upgradeError: daemonUpgradeError,
                              isDeleting: isDeleting,
                            ),
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
                    if (agent.isDaemon) ...<Widget>[
                      SizedBox(width: responsive.spacing(8)),
                      _DaemonRefreshIconButton(
                        onPressed: onRefresh,
                        isLoading: isRefreshing,
                        size: responsive.displayScaled(28),
                      ),
                    ],
                    SizedBox(width: responsive.spacing(8)),
                    AgentStatusDot(status: visualStatus),
                  ],
                ),
              ),
            ),
          ],
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
    final color = agent.isDaemon
        ? const Color(0xFF0B65F8)
        : const Color(0xFF7C4DFF);
    return Container(
      width: responsive.displayScaled(isChild ? 28 : 32),
      height: responsive.displayScaled(isChild ? 28 : 32),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isChild ? 0.1 : 0.12),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
      ),
      child: Icon(
        agent.isDaemon
            ? CupertinoIcons.desktopcomputer
            : CupertinoIcons.sparkles,
        color: color,
        size: isChild ? responsive.iconSm : responsive.iconMd,
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
    final enabled = onPressed != null && !isLoading;
    final color = enabled ? const Color(0xFF0B65F8) : const Color(0xFF9AA6B8);
    return AppIconButton(
      onPressed: onPressed,
      semanticLabel: '刷新状态',
      tooltip: '刷新状态',
      size: size,
      isLoading: isLoading,
      backgroundColor: const Color(0xFFF3F7FF),
      borderColor: const Color(0xFFDCE8FF),
      borderRadius: BorderRadius.circular(size / 2),
      child: Icon(CupertinoIcons.refresh, size: size * 0.52, color: color),
    );
  }
}

String _agentListSubtitle(
  AgentSummary agent,
  int? runtimeCount,
  AgentVisualStatus visualStatus, {
  bool isUpgrading = false,
  bool isCancelling = false,
  DaemonUpgradeProgress? upgradeProgress,
  String? upgradeError,
  bool isDeleting = false,
}) {
  if (isDeleting) {
    return '删除中 · 等待同步';
  }
  if (agent.isDaemon) {
    final count = runtimeCount ?? 0;
    final statusLabel = upgradeError != null
        ? '升级失败'
        : isCancelling
        ? '正在取消升级'
        : isUpgrading
        ? upgradeProgress?.compactLabel ?? '正在升级'
        : visualStatus.label;
    return 'Daemon · $count 个 Agent · $statusLabel';
  }
  final runtime = agent.runtime ?? 'Runtime';
  return '$runtime · ${visualStatus.label}';
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

String _upgradeSourceLabel(DaemonUpgradeProgress progress) {
  final parts = <String>[
    if (progress.sourceUrl != null) progress.sourceUrl!,
    if (progress.route != null) _upgradeRouteLabel(progress.route!),
  ];
  return parts.isEmpty ? '正在准备下载' : parts.join(' · ');
}

String _upgradeRouteLabel(String route) {
  if (route == 'direct') {
    return '直连';
  }
  if (route == 'environment_proxy') {
    return '代理';
  }
  if (route.startsWith('local_proxy:')) {
    return '本机代理 ${route.substring('local_proxy:'.length)}';
  }
  return route;
}
