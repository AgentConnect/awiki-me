import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show SelectableText, SelectionArea, SelectionContainer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../shared/identity_flow.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'agent_display_name.dart';
import 'agents_provider.dart';

class AgentsWorkspacePage extends ConsumerStatefulWidget {
  const AgentsWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  ConsumerState<AgentsWorkspacePage> createState() =>
      _AgentsWorkspacePageState();
}

class _AgentsWorkspacePageState extends ConsumerState<AgentsWorkspacePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AgentsState>(agentsProvider, (previous, next) {
      final command = next.installCommand;
      if (command != null && previous?.installCommand != command) {
        _showInstallCommand(context, ref, command);
      }
    });

    final state = ref.watch(agentsProvider);
    final responsive = context.awikiResponsive;
    final list = _AgentListPane(
      state: state,
      footer: widget.listFooter,
      onCreateDaemon: () =>
          ref.read(agentsProvider.notifier).createDaemonInstallCommand(),
      onRefreshDaemon: (agent) {
        ref.read(agentsProvider.notifier).refreshDaemonStatus(agent.agentDid);
      },
      onSelect: (agentDid) =>
          ref.read(agentsProvider.notifier).select(agentDid),
      onRetry: () => ref.read(agentsProvider.notifier).load(),
    );
    final detail = _AgentDetailPane(
      state: state,
      selected: state.selectedAgent,
      onRefresh: (agent) {
        ref.read(agentsProvider.notifier).refreshDaemonStatus(agent.agentDid);
      },
      onCreateRuntime: (agent) =>
          ref.read(agentsProvider.notifier).createHermesRuntime(agent.agentDid),
      onOpenChat: (agent) => _openRuntimeChat(context, ref, agent),
      onRename: (agent) => _showRenameAgentDialog(context, ref, agent),
      onRetryRun: (agent) => _showRetryRunDialog(context, ref, agent),
      onResetRuntime: (agent) =>
          _confirmResetRuntimeSession(context, ref, agent),
      onUpgrade: (agent) => _confirmUpgradeDaemon(context, ref, agent),
      onDelete: (agent) => _confirmDeleteAgent(context, ref, agent),
    );

    if (responsive.supportsTwoPane) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
        child: Row(
          children: <Widget>[
            SizedBox(width: responsive.displayScaled(348), child: list),
            Container(width: 1, color: const Color(0xFFE5EAF2)),
            Expanded(child: detail),
          ],
        ),
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
      child: state.selectedAgentDid == null
          ? list
          : Column(
              children: <Widget>[
                CupertinoNavigationBar(
                  middle: const Text('智能体'),
                  leading: TopBarActionButton(
                    onTap: () =>
                        ref.read(agentsProvider.notifier).clearSelection(),
                    semanticsLabel: '返回',
                    tooltip: '返回',
                    child: const Icon(CupertinoIcons.chevron_left),
                  ),
                ),
                Expanded(child: detail),
              ],
            ),
    );
  }
}

class _AgentListPane extends StatelessWidget {
  const _AgentListPane({
    required this.state,
    required this.footer,
    required this.onCreateDaemon,
    required this.onRefreshDaemon,
    required this.onSelect,
    required this.onRetry,
  });

  final AgentsState state;
  final Widget? footer;
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
                  onPressed: state.isActing ? null : onCreateDaemon,
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
    required this.onSelect,
    required this.onRefreshDaemon,
  });

  final AgentsState state;
  final ValueChanged<String> onSelect;
  final ValueChanged<AgentSummary> onRefreshDaemon;

  @override
  Widget build(BuildContext context) {
    final selectedDid = state.selectedAgent?.agentDid;
    final groups = _AgentTreeGroup.fromAgents(state.agents);
    return Column(
      children: <Widget>[
        for (final group in groups) ...<Widget>[
          _AgentDaemonGroup(
            group: group,
            state: state,
            selectedAgentDid: selectedDid,
            onSelect: onSelect,
            onRefreshDaemon: onRefreshDaemon,
          ),
        ],
      ],
    );
  }
}

class _AgentTreeGroup {
  const _AgentTreeGroup({required this.daemon, required this.runtimes});

  final AgentSummary? daemon;
  final List<AgentSummary> runtimes;

  static List<_AgentTreeGroup> fromAgents(List<AgentSummary> agents) {
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
        ),
      if (orphanRuntimes.isNotEmpty)
        _AgentTreeGroup(daemon: null, runtimes: orphanRuntimes),
    ];
  }
}

class _AgentDaemonGroup extends StatelessWidget {
  const _AgentDaemonGroup({
    required this.group,
    required this.state,
    required this.selectedAgentDid,
    required this.onSelect,
    required this.onRefreshDaemon,
  });

  final _AgentTreeGroup group;
  final AgentsState state;
  final String? selectedAgentDid;
  final ValueChanged<String> onSelect;
  final ValueChanged<AgentSummary> onRefreshDaemon;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final daemon = group.daemon;
    final runtimes = group.runtimes;
    if (daemon == null) {
      return Padding(
        padding: EdgeInsets.only(bottom: responsive.spacing(10)),
        child: _OrphanRuntimeGroup(
          runtimes: runtimes,
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
            selected: selectedAgentDid == daemon.agentDid,
            onTap: () => onSelect(daemon.agentDid),
            runtimeCount: runtimes.length,
            onRefresh:
                state.isActing || state.isStatusQueryPending(daemon.agentDid)
                ? null
                : () => onRefreshDaemon(daemon),
            isRefreshing: state.isStatusQueryPending(daemon.agentDid),
          ),
          if (runtimes.isEmpty)
            _EmptyRuntimeHint()
          else
            for (final runtime in runtimes)
              _AgentListTile(
                agent: runtime,
                selected: selectedAgentDid == runtime.agentDid,
                onTap: () => onSelect(runtime.agentDid),
                depth: 1,
              ),
        ],
      ),
    );
  }
}

class _OrphanRuntimeGroup extends StatelessWidget {
  const _OrphanRuntimeGroup({
    required this.runtimes,
    required this.selectedAgentDid,
    required this.onSelect,
  });

  final List<AgentSummary> runtimes;
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

class _AgentListTile extends StatelessWidget {
  const _AgentListTile({
    required this.agent,
    required this.selected,
    required this.onTap,
    this.depth = 0,
    this.runtimeCount,
    this.onRefresh,
    this.isRefreshing = false,
  });

  final AgentSummary agent;
  final bool selected;
  final VoidCallback onTap;
  final int depth;
  final int? runtimeCount;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final isChild = depth > 0;
    final title = AgentDisplayName.title(agent);
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
                            _agentListSubtitle(agent, runtimeCount),
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
                    _StatusDot(status: agent.latest.status),
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

String _agentListSubtitle(AgentSummary agent, int? runtimeCount) {
  if (agent.isDaemon) {
    final count = runtimeCount ?? 0;
    return 'Daemon · $count 个 Agent · ${agent.latest.status}';
  }
  final runtime = agent.runtime ?? 'Runtime';
  return '$runtime · ${agent.latest.status}';
}

class _AgentDetailPane extends StatelessWidget {
  const _AgentDetailPane({
    required this.state,
    required this.selected,
    required this.onRefresh,
    required this.onCreateRuntime,
    required this.onOpenChat,
    required this.onRename,
    required this.onRetryRun,
    required this.onResetRuntime,
    required this.onUpgrade,
    required this.onDelete,
  });

  final AgentsState state;
  final AgentSummary? selected;
  final ValueChanged<AgentSummary> onRefresh;
  final ValueChanged<AgentSummary> onCreateRuntime;
  final ValueChanged<AgentSummary> onOpenChat;
  final ValueChanged<AgentSummary> onRename;
  final ValueChanged<AgentSummary> onRetryRun;
  final ValueChanged<AgentSummary> onResetRuntime;
  final ValueChanged<AgentSummary> onUpgrade;
  final ValueChanged<AgentSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    final agent = selected;
    final responsive = context.awikiResponsive;
    if (agent == null) {
      return const Center(child: Text('选择一个代理'));
    }
    final runtimes = agent.isDaemon
        ? state.runtimesFor(agent.agentDid)
        : const <AgentSummary>[];
    final isRefreshing =
        agent.isDaemon && state.isStatusQueryPending(agent.agentDid);
    final title = AgentDisplayName.title(agent);
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
                _StatusPill(status: agent.latest.status),
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
                      label: '创建 Hermes',
                      onPressed: state.isActing || agent.latest.needsUpgrade
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
                      label: '升级',
                      onPressed: state.isActing ? null : () => onUpgrade(agent),
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
            SizedBox(height: responsive.spacing(18)),
            if (runtimes.isNotEmpty) ...<Widget>[
              const _SectionTitle('Runtime'),
              SizedBox(height: responsive.spacing(8)),
              for (final runtime in runtimes) _RuntimeRow(runtime: runtime),
              SizedBox(height: responsive.spacing(18)),
            ],
            if (agent.isRuntime && agent.recentRuns.isNotEmpty) ...<Widget>[
              const _SectionTitle('最近 Run'),
              SizedBox(height: responsive.spacing(8)),
              _RunStatusPanel(run: agent.recentRuns.first),
              SizedBox(height: responsive.spacing(18)),
            ],
            const _SectionTitle('高级诊断'),
            SizedBox(height: responsive.spacing(8)),
            _InfoGrid(agent: agent),
            if (agent.latest.lastErrorSummary != null ||
                agent.latest.diagnosticsSummary.isNotEmpty) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              _DiagnosticsPanel(agent: agent),
            ],
            SizedBox(height: responsive.spacing(18)),
            const SelectionContainer.disabled(child: _DisabledAdvancedAction()),
          ],
        ),
      ),
    );
  }
}

class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow({required this.runtime});

  final AgentSummary runtime;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final title = AgentDisplayName.title(runtime);
    return Container(
      margin: EdgeInsets.only(bottom: responsive.spacing(8)),
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(CupertinoIcons.sparkles, color: Color(0xFF0B65F8)),
          SizedBox(width: responsive.spacing(10)),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              style: const TextStyle(
                color: Color(0xFF101B32),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _StatusPill(status: runtime.latest.status),
        ],
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
              _StatusPill(status: run.status),
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

class _DiagnosticsPanel extends StatelessWidget {
  const _DiagnosticsPanel({required this.agent});

  final AgentSummary agent;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final diagnostics = agent.latest.diagnosticsSummary.entries
        .where((entry) => entry.value != null)
        .toList();
    return Container(
      padding: EdgeInsets.all(responsive.spacing(14)),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF2),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFF3D9A2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '诊断摘要',
            style: TextStyle(
              color: Color(0xFF101B32),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (agent.latest.lastErrorSummary != null) ...<Widget>[
            SizedBox(height: responsive.spacing(8)),
            _CopyableDiagnosticText(
              text: _redactDiagnosticValue(agent.latest.lastErrorSummary),
              color: const Color(0xFF7A4A00),
              fontSize: responsive.bodySm,
            ),
          ],
          if (diagnostics.isNotEmpty) ...<Widget>[
            SizedBox(height: responsive.spacing(8)),
            for (final entry in diagnostics)
              Padding(
                padding: EdgeInsets.only(bottom: responsive.spacing(5)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: responsive.displayScaled(116),
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        style: TextStyle(
                          color: const Color(0xFF66728A),
                          fontSize: responsive.metaSm,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _CopyableDiagnosticText(
                        text: _redactDiagnosticValue(
                          entry.value,
                          key: entry.key,
                        ),
                        color: const Color(0xFF101B32),
                        fontSize: responsive.metaSm,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.agent});

  final AgentSummary agent;

  @override
  Widget build(BuildContext context) {
    final items = <String, String>{
      'DID': agent.agentDid,
      if (agent.handle != null) 'handle': agent.handle!,
      if (agent.daemonAgentDid != null) 'daemon': agent.daemonAgentDid!,
      if (agent.latest.version != null) 'version': agent.latest.version!,
      if (agent.latest.latestVersion != null)
        'latest': agent.latest.latestVersion!,
      if (agent.latest.minSupportedVersion != null)
        'min': agent.latest.minSupportedVersion!,
      if (agent.latest.platform != null) 'platform': agent.latest.platform!,
      if (agent.latest.service != null) 'service': agent.latest.service!,
      if (agent.latest.lastSeenAt != null)
        'last_seen': agent.latest.lastSeenAt!.toLocal().toString(),
      if (agent.latest.lastErrorCode != null)
        'error': agent.latest.lastErrorCode!,
    };
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(14)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFE5EAF2)),
      ),
      child: Column(
        children: items.entries
            .map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: responsive.spacing(7)),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: responsive.displayScaled(96),
                      child: Text(
                        entry.key,
                        style: const TextStyle(color: Color(0xFF66728A)),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _redactDiagnosticValue(entry.value, key: entry.key),
                        maxLines: 2,
                        style: const TextStyle(
                          color: Color(0xFF101B32),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      tooltip: label,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(8),
      builder: (context, state, child) {
        return AnimatedOpacity(
          opacity: state.enabled
              ? state.pressed
                    ? 0.78
                    : state.hovered || state.focused
                    ? 0.90
                    : 1
              : 0.55,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFFEBEB) : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: danger ? AwikiMeColors.danger : const Color(0xFF0B65F8),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: danger ? AwikiMeColors.danger : const Color(0xFF0B65F8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentErrorBanner extends StatelessWidget {
  const _AgentErrorBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final retryButton = onRetry == null
        ? null
        : AppPressable(
            onTap: onRetry,
            semanticLabel: '重试',
            tooltip: '重试',
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.spacing(10),
                vertical: responsive.spacing(5),
              ),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(responsive.radius(8)),
              ),
              child: Text(
                '重试',
                style: TextStyle(
                  color: AwikiMeColors.danger,
                  fontSize: responsive.metaSm,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
    return AwikiMeErrorNotice(
      message: message,
      compact: true,
      trailing: retryButton,
    );
  }
}

class _CopyableDiagnosticText extends StatelessWidget {
  const _CopyableDiagnosticText({
    required this.text,
    required this.color,
    required this.fontSize,
  });

  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            style: TextStyle(color: color, fontSize: fontSize),
          ),
        ),
        SizedBox(width: responsive.spacing(6)),
        _InlineCopyButton(text: text),
      ],
    );
  }
}

class _InlineCopyButton extends StatelessWidget {
  const _InlineCopyButton({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return SelectionContainer.disabled(
      child: AppIconButton(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: text));
          if (context.mounted) {
            AwikiMeToast.show(context, '已复制');
          }
        },
        semanticLabel: '复制',
        tooltip: '复制',
        size: responsive.displayScaled(28),
        padding: EdgeInsets.all(responsive.spacing(5)),
        backgroundColor: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(7)),
        child: Icon(
          CupertinoIcons.doc_on_doc,
          color: const Color(0xFF44506A),
          size: responsive.iconSm,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF101B32),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: _statusColor(status),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DisabledAdvancedAction extends StatelessWidget {
  const _DisabledAdvancedAction();

  @override
  Widget build(BuildContext context) {
    return const Opacity(
      opacity: 0.55,
      child: _ActionButton(
        icon: CupertinoIcons.wrench,
        label: '重建 Runtime',
        onPressed: null,
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'ready':
      return AwikiMeColors.online;
    case 'failed':
    case 'offline':
      return AwikiMeColors.danger;
    case 'needs_config':
    case 'needs_upgrade':
      return AwikiMeColors.alert;
    default:
      return const Color(0xFF66728A);
  }
}

String _redactDiagnosticValue(Object? value, {String? key}) {
  if (_isSensitiveDiagnosticKey(key)) {
    return '<redacted>';
  }
  var text = value?.toString() ?? '';
  text = text.replaceAllMapped(
    RegExp(
      r'\b(authorization)\s*:\s*bearer\s+([^\s,;]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}: Bearer <redacted>',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'\b(token|jwt|private[_-]?key|api[_-]?key|secret|signature)\s*[:=]\s*([^\s,;}]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=<redacted>',
  );
  text = text.replaceAll(
    RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b'),
    '<redacted>',
  );
  text = text.replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{8,}\b'), '<redacted>');
  text = text.replaceAll(
    RegExp(
      r'(/Users/[^\s,;:]+|/home/[^\s,;:]+|/tmp/[^\s,;:]+|/var/[^\s,;:]+|/private/[^\s,;:]+|[A-Za-z]:\\[^\s,;]+)',
    ),
    '<path>',
  );
  return text;
}

bool _isSensitiveDiagnosticKey(String? key) {
  final normalized = key?.toLowerCase().replaceAll('-', '_');
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  return normalized.contains('token') ||
      normalized.contains('jwt') ||
      normalized.contains('private_key') ||
      normalized.contains('api_key') ||
      normalized.contains('secret') ||
      normalized.contains('authorization') ||
      normalized.contains('prompt') ||
      normalized.contains('log') ||
      normalized.endsWith('_path') ||
      normalized == 'path';
}

Future<void> _openRuntimeChat(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) {
  final title = AgentDisplayName.title(agent);
  return openDirectConversationForDid(
    context,
    ref,
    peerDid: agent.agentDid,
    peerName: title,
    avatarSeed: agent.handle ?? agent.agentDid,
  );
}

Future<void> _showRenameAgentDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final controller = TextEditingController(text: AgentDisplayName.title(agent));
  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('改名'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CupertinoTextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          placeholder: '显示名称',
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  controller.dispose();
  final displayName = result?.trim();
  if (displayName == null || displayName.isEmpty || displayName.length > 40) {
    return;
  }
  await ref.read(agentsProvider.notifier).renameSelected(displayName);
}

Future<void> _showRetryRunDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final controller = TextEditingController();
  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('重试 Run'),
      content: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: CupertinoTextField(
          controller: controller,
          autofocus: true,
          placeholder: 'run_id',
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
      ),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('重试'),
        ),
      ],
    ),
  );
  controller.dispose();
  final runId = result?.trim();
  if (runId == null || runId.isEmpty) {
    return;
  }
  await ref.read(agentsProvider.notifier).retryRun(agent, runId);
}

Future<void> _confirmResetRuntimeSession(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final confirmed = await _confirm(
    context,
    title: '重置 Session',
    message: '仅归档本地 session mapping，不删除聊天历史。',
    actionLabel: '重置',
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).resetRuntimeSession(agent);
  }
}

Future<void> _confirmUpgradeDaemon(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final confirmed = await _confirm(
    context,
    title: '升级代理',
    message: '代理会下载 latest 版本并重启服务。',
    actionLabel: '升级',
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).upgradeDaemon(agent.agentDid);
  }
}

Future<void> _confirmDeleteAgent(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final isDaemon = agent.isDaemon;
  final confirmed = await _confirm(
    context,
    title: isDaemon ? '删除代理' : '删除智能体',
    message: isDaemon
        ? '删除后会停止宿主机上的代理服务，并移除它创建的智能体。本地数据会归档保留，不会继续使用。'
        : '删除后该智能体会从列表中移除。本地数据会归档保留，不会继续使用。',
    actionLabel: '删除',
    destructive: true,
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).deleteSelected();
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  bool destructive = false,
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        CupertinoDialogAction(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return result == true;
}

void _showInstallCommand(
  BuildContext context,
  WidgetRef ref,
  InstallCommand command,
) {
  showCupertinoDialog<void>(
    context: context,
    builder: (context) => _InstallCommandDialog(
      command: command,
      onClose: () {
        Navigator.of(context).pop();
        ref.read(agentsProvider.notifier).clearInstallCommand();
      },
    ),
  );
}

class _InstallCommandDialog extends StatelessWidget {
  const _InstallCommandDialog({required this.command, required this.onClose});

  final InstallCommand command;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final expiresAt = command.token.expiresAt?.toLocal();
    final isExpired =
        command.token.expiresAt != null &&
        !command.token.expiresAt!.isAfter(DateTime.now().toUtc());
    final media = MediaQuery.of(context);
    final availableWidth = media.size.width - 32;
    final maxDialogWidth = availableWidth < 520 ? availableWidth : 520.0;
    final maxDialogHeight = media.size.height * 0.82;
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Center(
        child: CupertinoPopupSurface(
          isSurfacePainted: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: Padding(
              padding: EdgeInsets.all(responsive.spacing(20)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: responsive.displayScaled(34),
                        height: responsive.displayScaled(34),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(
                            responsive.radius(8),
                          ),
                        ),
                        child: Icon(
                          CupertinoIcons.desktopcomputer,
                          color: const Color(0xFF0B65F8),
                          size: responsive.iconMd,
                        ),
                      ),
                      SizedBox(width: responsive.spacing(10)),
                      Expanded(
                        child: Text(
                          '到宿主机安装代理',
                          style: TextStyle(
                            color: const Color(0xFF101B32),
                            fontSize: responsive.titleXl,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(width: responsive.spacing(8)),
                      AppIconButton(
                        onPressed: onClose,
                        semanticLabel: '关闭',
                        tooltip: '关闭',
                        size: responsive.displayScaled(30),
                        backgroundColor: const Color(0xFFF4F6FA),
                        borderRadius: BorderRadius.circular(
                          responsive.radius(8),
                        ),
                        child: Icon(
                          CupertinoIcons.xmark,
                          color: const Color(0xFF66728A),
                          size: responsive.iconSm,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.spacing(16)),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _CommandText(
                            command.command,
                            onCopy: () async {
                              await Clipboard.setData(
                                ClipboardData(text: command.command),
                              );
                              if (context.mounted) {
                                AwikiMeToast.show(context, '已复制');
                              }
                            },
                          ),
                          SizedBox(height: responsive.spacing(12)),
                          _TokenExpiryRow(
                            isExpired: isExpired,
                            expiresAt: expiresAt,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TokenExpiryRow extends StatelessWidget {
  const _TokenExpiryRow({required this.isExpired, required this.expiresAt});

  final bool isExpired;
  final DateTime? expiresAt;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      padding: EdgeInsets.all(responsive.spacing(10)),
      decoration: BoxDecoration(
        color: isExpired ? const Color(0xFFFFF3F3) : const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(
          color: isExpired ? const Color(0xFFFFD2D2) : const Color(0xFFE2EAF6),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isExpired
                ? CupertinoIcons.exclamationmark_circle_fill
                : CupertinoIcons.clock_fill,
            color: isExpired ? AwikiMeColors.danger : const Color(0xFF66728A),
            size: responsive.iconSm,
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              '有效期至: ${_formatTokenExpiry(expiresAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isExpired
                    ? AwikiMeColors.danger
                    : const Color(0xFF4B5870),
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatTokenExpiry(DateTime? expiresAt) {
  if (expiresAt == null) {
    return '--:--';
  }
  final hour = expiresAt.hour.toString().padLeft(2, '0');
  final minute = expiresAt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class _CommandText extends StatelessWidget {
  const _CommandText(this.value, {required this.onCopy});

  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.spacing(12)),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Stack(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(right: responsive.displayScaled(46)),
            child: SelectableText(
              key: const Key('agent-install-command-text'),
              _wrapCommand(value),
              style: TextStyle(
                color: const Color(0xFFE5E7EB),
                fontSize: responsive.metaSm,
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: AppIconButton(
              key: const Key('agent-install-copy-button'),
              onPressed: onCopy,
              semanticLabel: '复制安装命令',
              tooltip: '复制安装命令',
              size: responsive.displayScaled(34),
              backgroundColor: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(responsive.radius(8)),
              child: Icon(
                CupertinoIcons.doc_on_doc,
                color: const Color(0xFFCBD5E1),
                size: responsive.iconSm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _wrapCommand(String command) {
  final normalized = command.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) {
    return normalized;
  }
  final parts = normalized.split(' ');
  final lines = <String>[];
  final buffer = StringBuffer();
  for (final part in parts) {
    final nextLength = buffer.isEmpty
        ? part.length
        : buffer.length + 1 + part.length;
    if (buffer.isNotEmpty && nextLength > 52) {
      lines.add(buffer.toString());
      buffer
        ..clear()
        ..write('  ')
        ..write(part);
    } else {
      if (buffer.isNotEmpty) {
        buffer.write(' ');
      }
      buffer.write(part);
    }
  }
  if (buffer.isNotEmpty) {
    lines.add(buffer.toString());
  }
  return lines.join('\n');
}
