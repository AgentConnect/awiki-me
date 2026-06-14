import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Color, SelectableText, SelectionArea, SelectionContainer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/config/awiki_environment_config.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import '../shared/identity_flow.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../chat/chat_provider.dart';
import 'agent_display_name.dart';
import 'agent_status_indicator.dart';
import 'agent_visual_status.dart';
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
    final pendingAgentDids = _pendingAgentDids(ref.watch(chatThreadsProvider));
    final list = _AgentListPane(
      state: state,
      footer: widget.listFooter,
      pendingAgentDids: pendingAgentDids,
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
      pendingAgentDids: pendingAgentDids,
      onRefresh: (agent) {
        ref.read(agentsProvider.notifier).refreshDaemonStatus(agent.agentDid);
      },
      onCreateRuntime: (agent) => _showCreateHermesDialog(
        context,
        ref,
        agent,
        state.runtimesFor(agent.agentDid),
      ),
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
    required this.pendingAgentDids,
    required this.onCreateDaemon,
    required this.onRefreshDaemon,
    required this.onSelect,
    required this.onRetry,
  });

  final AgentsState state;
  final Widget? footer;
  final Set<String> pendingAgentDids;
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
                  pendingAgentDids: pendingAgentDids,
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
    required this.onSelect,
    required this.onRefreshDaemon,
  });

  final AgentsState state;
  final Set<String> pendingAgentDids;
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
            pendingAgentDids: pendingAgentDids,
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
                pendingAgentDids: pendingAgentDids,
                pendingDaemonUpgrades: state.pendingDaemonUpgrades,
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
            pendingDaemonUpgrades: const <String>{},
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
    required this.pendingAgentDids,
    required this.pendingDaemonUpgrades,
    required this.selected,
    required this.onTap,
    this.depth = 0,
    this.runtimeCount,
    this.onRefresh,
    this.isRefreshing = false,
  });

  final AgentSummary agent;
  final Set<String> pendingAgentDids;
  final Set<String> pendingDaemonUpgrades;
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
    final visualStatus = AgentVisualStatus.fromAgent(
      agent,
      hasPendingTurn: pendingAgentDids.contains(agent.agentDid),
      isPendingUpgrade: pendingDaemonUpgrades.contains(agent.agentDid),
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
  AgentVisualStatus visualStatus,
) {
  if (agent.isDaemon) {
    final count = runtimeCount ?? 0;
    return 'Daemon · $count 个 Agent · ${visualStatus.label}';
  }
  final runtime = agent.runtime ?? 'Runtime';
  return '$runtime · ${visualStatus.label}';
}

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
    required this.onDelete,
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
  final ValueChanged<AgentSummary> onDelete;

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
    final title = AgentDisplayName.title(agent);
    final visualStatus = AgentVisualStatus.fromAgent(
      agent,
      hasPendingTurn: pendingAgentDids.contains(agent.agentDid),
      isPendingUpgrade: isUpgrading,
    );
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
                      label: isUpgrading ? '升级中' : '升级',
                      onPressed: state.isActing || isUpgrading
                          ? null
                          : () => onUpgrade(agent),
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
            if (agent.isRuntime && agent.recentRuns.isNotEmpty) ...<Widget>[
              const _SectionTitle('最近 Run'),
              SizedBox(height: responsive.spacing(8)),
              _RunStatusPanel(run: agent.recentRuns.first),
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

class _DiagnosticInfoPanel extends StatefulWidget {
  const _DiagnosticInfoPanel({super.key, required this.agent});

  final AgentSummary agent;

  @override
  State<_DiagnosticInfoPanel> createState() => _DiagnosticInfoPanelState();
}

class _DiagnosticInfoPanelState extends State<_DiagnosticInfoPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final agent = widget.agent;
    final essentialRows = _essentialDiagnosticRows(agent);
    final moreRows = _expandedDiagnosticRows(agent);
    final errorText = _diagnosticErrorText(agent);
    final hasMore = moreRows.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(10)),
        border: Border.all(color: const Color(0xFFE4EAF3)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F0B1220),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
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
                  color: const Color(0xFFF0F5FF),
                  borderRadius: BorderRadius.circular(responsive.radius(9)),
                ),
                child: Icon(
                  CupertinoIcons.info_circle,
                  color: const Color(0xFF0B65F8),
                  size: responsive.iconMd,
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '诊断信息',
                      style: TextStyle(
                        color: const Color(0xFF101B32),
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: responsive.spacing(2)),
                    Text(
                      agent.isDaemon ? '代理运行与身份信息' : '智能体身份信息',
                      style: TextStyle(
                        color: const Color(0xFF66728A),
                        fontSize: responsive.metaSm,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: responsive.spacing(14)),
          _DiagnosticRows(rows: essentialRows),
          if (errorText != null) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            _DiagnosticNotice(text: errorText),
          ],
          if (hasMore) ...<Widget>[
            SizedBox(height: responsive.spacing(12)),
            SelectionContainer.disabled(
              child: _DiagnosticMoreButton(
                expanded: _expanded,
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
            if (_expanded) ...<Widget>[
              SizedBox(height: responsive.spacing(10)),
              _DiagnosticRows(rows: moreRows, compact: true),
            ],
          ],
        ],
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

class _DiagnosticRows extends StatelessWidget {
  const _DiagnosticRows({required this.rows, this.compact = false});

  final List<_DiagnosticRowData> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Column(
      children: <Widget>[
        for (var index = 0; index < rows.length; index++) ...<Widget>[
          if (index > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: responsive.spacing(4)),
              child: Container(height: 1, color: const Color(0xFFEFF3F8)),
            ),
          _DiagnosticInfoRow(row: rows[index], compact: compact),
        ],
      ],
    );
  }
}

class _DiagnosticInfoRow extends StatelessWidget {
  const _DiagnosticInfoRow({required this.row, required this.compact});

  final _DiagnosticRowData row;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: responsive.spacing(compact ? 3 : 5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: responsive.displayScaled(compact ? 96 : 112),
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF66728A),
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: responsive.spacing(10)),
          Expanded(
            child: Text(
              row.value,
              maxLines: row.isLong ? 3 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF18243A),
                fontSize: compact ? responsive.metaSm : responsive.bodySm,
                fontWeight: FontWeight.w500,
                height: 1.28,
              ),
            ),
          ),
          if (row.copyable) ...<Widget>[
            SizedBox(width: responsive.spacing(8)),
            _InlineCopyButton(text: row.copyText ?? row.value),
          ],
        ],
      ),
    );
  }
}

class _DiagnosticNotice extends StatelessWidget {
  const _DiagnosticNotice({required this.text});

  final String text;

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
        color: const Color(0xFFFFF6EA),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: const Color(0xFFF6D7A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: responsive.spacing(1)),
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: const Color(0xFFB26900),
              size: responsive.iconSm,
            ),
          ),
          SizedBox(width: responsive.spacing(8)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: const Color(0xFF6F4B16),
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

class _DiagnosticMoreButton extends StatelessWidget {
  const _DiagnosticMoreButton({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: expanded ? '收起诊断详情' : '查看更多诊断',
      tooltip: expanded ? '收起' : '查看更多',
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(8),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FC),
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: const Color(0xFFE5EAF2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              expanded ? '收起' : '查看更多',
              style: TextStyle(
                color: const Color(0xFF40506B),
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(width: responsive.spacing(5)),
            Icon(
              expanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: const Color(0xFF66728A),
              size: responsive.iconSm * 0.78,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticRowData {
  const _DiagnosticRowData({
    required this.label,
    required this.value,
    this.copyable = false,
    this.copyText,
    this.isLong = false,
  });

  final String label;
  final String value;
  final bool copyable;
  final String? copyText;
  final bool isLong;
}

List<_DiagnosticRowData> _essentialDiagnosticRows(AgentSummary agent) {
  return <_DiagnosticRowData>[
    _DiagnosticRowData(
      label: 'DID',
      value: agent.agentDid,
      copyable: true,
      copyText: agent.agentDid,
      isLong: true,
    ),
    if (_nonEmpty(agent.handle) != null)
      _DiagnosticRowData(
        label: 'Handle',
        value: _nonEmpty(agent.handle)!,
        copyable: true,
        copyText: _nonEmpty(agent.handle)!,
      ),
    if (agent.isDaemon && _nonEmpty(agent.latest.version) != null)
      _DiagnosticRowData(
        label: '当前版本',
        value: _nonEmpty(agent.latest.version)!,
      ),
    if (agent.isDaemon && _nonEmpty(agent.latest.platform) != null)
      _DiagnosticRowData(label: '平台', value: _nonEmpty(agent.latest.platform)!),
  ];
}

List<_DiagnosticRowData> _expandedDiagnosticRows(AgentSummary agent) {
  final rows = <_DiagnosticRowData>[];
  final latest = agent.latest;
  void add(String label, Object? value, {String? key, bool isLong = false}) {
    final text = _nonEmpty(value);
    if (text == null) {
      return;
    }
    rows.add(
      _DiagnosticRowData(
        label: label,
        value: _redactDiagnosticValue(text, key: key ?? label),
        isLong: isLong || text.length > 48,
      ),
    );
  }

  if (agent.isDaemon) {
    add('最新版本', latest.latestVersion, key: 'latest_version');
    add('最低可用版本', latest.minSupportedVersion, key: 'min_supported_version');
    add('服务', latest.service, key: 'service');
    add('最近上报', latest.lastSeenAt?.toLocal().toString(), key: 'last_seen');
  }
  add('错误代码', latest.lastErrorCode, key: 'last_error_code');
  for (final entry in latest.diagnosticsSummary.entries) {
    if (!_shouldShowDiagnosticSummaryEntry(agent, entry.key, entry.value)) {
      continue;
    }
    add(_diagnosticLabel(entry.key), entry.value, key: entry.key, isLong: true);
  }
  return rows;
}

String? _diagnosticErrorText(AgentSummary agent) {
  final summary = _nonEmpty(agent.latest.lastErrorSummary);
  if (summary == null) {
    return null;
  }
  return _redactDiagnosticValue(summary, key: 'last_error_summary');
}

bool _shouldShowDiagnosticSummaryEntry(
  AgentSummary agent,
  String key,
  Object? value,
) {
  final text = _nonEmpty(value);
  if (text == null) {
    return false;
  }
  final normalized = key.trim().toLowerCase();
  const daemonOwnedKeys = <String>{
    'version',
    'latest_version',
    'min_supported_version',
    'platform',
    'service',
    'service_installed',
    'installation_status',
    'download_base_url',
    'base_url',
  };
  if (agent.isRuntime && daemonOwnedKeys.contains(normalized)) {
    return false;
  }
  return true;
}

String _diagnosticLabel(String key) {
  switch (key.trim().toLowerCase()) {
    case 'runner':
      return '运行器';
    case 'profile_status':
      return '配置状态';
    case 'installation_status':
      return '安装状态';
    case 'service_installed':
      return '服务安装';
    case 'config_summary':
      return '配置摘要';
    case 'hermes_profile':
      return 'Hermes 配置';
    case 'runner_status':
      return '运行状态';
    case 'active_session_count':
      return '活跃会话';
    default:
      return key;
  }
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
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

class _RunStatusPill extends StatelessWidget {
  const _RunStatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _runStatusColor(status).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _runStatusColor(status),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _runStatusColor(String status) {
  switch (status.trim().toLowerCase()) {
    case 'succeeded':
    case 'finished':
      return AwikiMeColors.online;
    case 'failed':
      return AwikiMeColors.danger;
    case 'queued':
    case 'pending':
    case 'running':
      return AwikiMeColors.alert;
    default:
      return const Color(0xFF66728A);
  }
}

Set<String> _pendingAgentDids(Map<String, ChatThreadState> threads) {
  return <String>{
    for (final thread in threads.values)
      for (final turn in thread.agentPendingTurns)
        if (turn.isActive) turn.agentDid,
  };
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
    peerHandle: _agentFullHandle(agent),
    peerName: title,
    avatarSeed: agent.handle ?? agent.agentDid,
  );
}

String? _agentFullHandle(AgentSummary agent) {
  final handle = _trimLeadingAt(agent.handle);
  if (handle == null || handle.isEmpty) {
    return null;
  }
  if (handle.contains('.')) {
    return handle.toLowerCase();
  }
  final domain = AwikiEnvironmentConfig.fromEnvironment().didDomain.trim();
  if (domain.isEmpty) {
    return handle.toLowerCase();
  }
  return '$handle.$domain'.toLowerCase();
}

String? _trimLeadingAt(String? value) {
  var text = value?.trim();
  if (text == null) {
    return null;
  }
  while (text!.startsWith('@')) {
    text = text.substring(1).trimLeft();
  }
  return text.trim();
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

Future<void> _showCreateHermesDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary daemon,
  List<AgentSummary> existingRuntimes,
) async {
  final result = await showCupertinoDialog<_RuntimeAgentCreationDraft>(
    context: context,
    builder: (dialogContext) => _CreateHermesDialog(
      initialDisplayName: _nextHermesDisplayName(existingRuntimes),
      handleDomain: AwikiEnvironmentConfig.fromEnvironment().didDomain,
      validateHandle: (handle, domain) {
        return ref
            .read(onboardingSupportServiceProvider)
            .validateHandle(handle: handle, domain: domain);
      },
    ),
  );
  if (result == null) {
    return;
  }
  await ref
      .read(agentsProvider.notifier)
      .createHermesRuntime(
        daemon.agentDid,
        handle: result.handle,
        displayName: result.displayName,
      );
}

class _RuntimeAgentCreationDraft {
  const _RuntimeAgentCreationDraft({
    required this.displayName,
    required this.handle,
  });

  final String displayName;
  final String handle;
}

class _CreateHermesDialog extends StatefulWidget {
  const _CreateHermesDialog({
    required this.initialDisplayName,
    required this.handleDomain,
    required this.validateHandle,
  });

  final String initialDisplayName;
  final String handleDomain;
  final Future<HandleAvailability> Function(String handle, String domain)
  validateHandle;

  @override
  State<_CreateHermesDialog> createState() => _CreateHermesDialogState();
}

class _CreateHermesDialogState extends State<_CreateHermesDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  final FocusNode _handleFocusNode = FocusNode();
  Timer? _handleValidationDebounce;
  bool _normalizingHandle = false;
  String? _submittedNameError;
  String? _submittedHandleError;
  String? _remoteHandle;
  bool _remoteHandleChecking = false;
  HandleAvailability? _remoteAvailability;
  String? _remoteValidationError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialDisplayName)
      ..addListener(_onFieldChanged);
    _handleController = TextEditingController()
      ..addListener(_normalizeHandleInput);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onFieldChanged)
      ..dispose();
    _handleController
      ..removeListener(_normalizeHandleInput)
      ..dispose();
    _handleValidationDebounce?.cancel();
    _handleFocusNode.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (_submittedNameError != null || _submittedHandleError != null) {
      setState(() {
        _submittedNameError = null;
        _submittedHandleError = null;
      });
      return;
    }
    setState(() {});
  }

  void _normalizeHandleInput() {
    if (_normalizingHandle) {
      return;
    }
    final normalized = _normalizeAgentHandleInput(_handleController.text);
    if (normalized != _handleController.text) {
      _normalizingHandle = true;
      _handleController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      _normalizingHandle = false;
    }
    _onFieldChanged();
    _scheduleHandleAvailabilityCheck();
  }

  void _scheduleHandleAvailabilityCheck() {
    _handleValidationDebounce?.cancel();
    final handle = _handleController.text.trim();
    if (_validateAgentHandle(handle) != null) {
      setState(() {
        _remoteHandle = null;
        _remoteHandleChecking = false;
        _remoteAvailability = null;
        _remoteValidationError = null;
      });
      return;
    }
    setState(() {
      _remoteHandle = handle;
      _remoteHandleChecking = true;
      _remoteAvailability = null;
      _remoteValidationError = null;
    });
    _handleValidationDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _checkHandleAvailability(handle),
    );
  }

  Future<void> _checkHandleAvailability(String handle) async {
    try {
      final availability = await widget.validateHandle(
        handle,
        widget.handleDomain,
      );
      if (!mounted || _remoteHandle != handle) {
        return;
      }
      setState(() {
        _remoteHandleChecking = false;
        _remoteAvailability = availability;
        _remoteValidationError = null;
        _submittedHandleError = null;
      });
    } catch (_) {
      if (!mounted || _remoteHandle != handle) {
        return;
      }
      setState(() {
        _remoteHandleChecking = false;
        _remoteAvailability = null;
        _remoteValidationError = '暂时无法校验可用性，创建时会再次确认';
        _submittedHandleError = null;
      });
    }
  }

  void _submit() {
    final displayName = _nameController.text.trim();
    final handle = _handleController.text.trim();
    final nameError = _validateAgentDisplayName(displayName);
    final handleError =
        _validateAgentHandle(handle) ??
        (_remoteHandleChecking ? '正在校验 Handle 可用性' : null) ??
        _remoteHandleError(handle);
    if (nameError != null || handleError != null) {
      setState(() {
        _submittedNameError = nameError;
        _submittedHandleError = handleError;
      });
      if (handleError != null) {
        _handleFocusNode.requestFocus();
      }
      return;
    }
    Navigator.of(
      context,
    ).pop(_RuntimeAgentCreationDraft(displayName: displayName, handle: handle));
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final handle = _handleController.text.trim();
    final displayName = _nameController.text.trim();
    final nameError =
        _submittedNameError ?? _softValidateAgentDisplayName(displayName);
    final remoteError = _remoteHandleError(handle);
    final handleError =
        _submittedHandleError ??
        _softValidateAgentHandle(handle) ??
        remoteError;
    final canSubmit =
        _validateAgentDisplayName(displayName) == null &&
        _validateAgentHandle(handle) == null &&
        !_remoteHandleChecking &&
        remoteError == null;
    final maxWidth = responsive.isPhone ? double.infinity : 430.0;
    return CupertinoPopupSurface(
      isSurfacePainted: false,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: responsive.spacing(18),
            vertical: responsive.spacing(22),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(responsive.radius(14)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x260B1220),
                    blurRadius: 34,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(responsive.spacing(18)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '创建 Hermes',
                            style: TextStyle(
                              color: const Color(0xFF101B32),
                              fontSize: responsive.titleLg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        AppIconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          semanticLabel: '关闭',
                          tooltip: '关闭',
                          size: responsive.displayScaled(32),
                          backgroundColor: const Color(0xFFF5F7FB),
                          borderColor: const Color(0xFFE4E9F2),
                          child: Icon(
                            CupertinoIcons.xmark,
                            color: const Color(0xFF66728A),
                            size: responsive.iconSm,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: responsive.spacing(14)),
                    _AgentDialogField(
                      label: '名称',
                      controller: _nameController,
                      placeholder: 'Hermes',
                      errorText: nameError,
                      textInputAction: TextInputAction.next,
                    ),
                    SizedBox(height: responsive.spacing(12)),
                    _AgentDialogField(
                      label: 'Handle',
                      controller: _handleController,
                      placeholder: 'my-hermes',
                      errorText: handleError,
                      focusNode: _handleFocusNode,
                      prefix: const Text('@'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    SizedBox(height: responsive.spacing(8)),
                    _HandlePreview(
                      handle: handle,
                      domain: widget.handleDomain,
                      isValid: _validateAgentHandle(handle) == null,
                      isChecking: _remoteHandleChecking,
                      availability: _previewAvailability(handle),
                      fallbackMessage: _remoteValidationError,
                    ),
                    SizedBox(height: responsive.spacing(18)),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _DialogSecondaryButton(
                            label: '取消',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        SizedBox(width: responsive.spacing(10)),
                        Expanded(
                          child: AppPrimaryButton(
                            label: '创建',
                            onPressed: canSubmit ? _submit : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _remoteHandleError(String handle) {
    if (handle.isEmpty || _validateAgentHandle(handle) != null) {
      return null;
    }
    final availability = _previewAvailability(handle);
    if (availability == null || availability.available) {
      return null;
    }
    if (availability.reason == 'unavailable') {
      return '这个 Handle 已被使用';
    }
    return availability.message?.trim().isNotEmpty == true
        ? availability.message
        : '这个 Handle 不可使用';
  }

  HandleAvailability? _previewAvailability(String handle) {
    if (handle.isEmpty || _remoteHandle != handle) {
      return null;
    }
    return _remoteAvailability;
  }
}

class _AgentDialogField extends StatelessWidget {
  const _AgentDialogField({
    required this.label,
    required this.controller,
    required this.placeholder,
    this.errorText,
    this.focusNode,
    this.prefix,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String placeholder;
  final String? errorText;
  final FocusNode? focusNode;
  final Widget? prefix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF66728A),
            fontSize: responsive.metaSm,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: responsive.spacing(6)),
        CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          prefix: prefix == null
              ? null
              : Padding(
                  padding: EdgeInsets.only(left: responsive.spacing(10)),
                  child: DefaultTextStyle(
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.bodyMd,
                      fontWeight: FontWeight.w600,
                    ),
                    child: prefix!,
                  ),
                ),
          padding: EdgeInsets.symmetric(
            horizontal: responsive.spacing(12),
            vertical: responsive.spacing(11),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFD),
            borderRadius: BorderRadius.circular(responsive.radius(9)),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFE14E4E)
                  : const Color(0xFFDDE5F1),
            ),
          ),
          style: TextStyle(
            color: const Color(0xFF101B32),
            fontSize: responsive.bodyMd,
          ),
          placeholderStyle: TextStyle(
            color: const Color(0xFF98A4B8),
            fontSize: responsive.bodyMd,
          ),
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
        ),
        if (hasError) ...<Widget>[
          SizedBox(height: responsive.spacing(5)),
          Text(
            errorText!,
            style: TextStyle(
              color: const Color(0xFFE14E4E),
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _HandlePreview extends StatelessWidget {
  const _HandlePreview({
    required this.handle,
    required this.domain,
    required this.isValid,
    required this.isChecking,
    this.availability,
    this.fallbackMessage,
  });

  final String handle;
  final String domain;
  final bool isValid;
  final bool isChecking;
  final HandleAvailability? availability;
  final String? fallbackMessage;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final preview = handle.isEmpty ? '@handle.$domain' : '@$handle.$domain';
    final message = _handlePreviewMessage(
      handle: handle,
      isValid: isValid,
      isChecking: isChecking,
      availability: availability,
      fallbackMessage: fallbackMessage,
    );
    final color = _handlePreviewColor(
      isValid: isValid,
      isChecking: isChecking,
      availability: availability,
      fallbackMessage: fallbackMessage,
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.spacing(12),
        vertical: responsive.spacing(9),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(responsive.radius(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '最终 Handle：$preview',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isValid
                  ? const Color(0xFF22304A)
                  : const Color(0xFF66728A),
              fontSize: responsive.metaSm,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (message != null) ...<Widget>[
            SizedBox(height: responsive.spacing(4)),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? _handlePreviewMessage({
  required String handle,
  required bool isValid,
  required bool isChecking,
  required HandleAvailability? availability,
  required String? fallbackMessage,
}) {
  if (handle.isEmpty || !isValid) {
    return null;
  }
  if (isChecking) {
    return '正在校验可用性...';
  }
  if (availability != null) {
    if (availability.available) {
      return '这个 Handle 可以使用';
    }
    return availability.reason == 'unavailable'
        ? '这个 Handle 已被使用'
        : availability.message ?? '这个 Handle 不可使用';
  }
  return fallbackMessage;
}

Color _handlePreviewColor({
  required bool isValid,
  required bool isChecking,
  required HandleAvailability? availability,
  required String? fallbackMessage,
}) {
  if (!isValid || isChecking) {
    return const Color(0xFF66728A);
  }
  if (availability?.available == true) {
    return const Color(0xFF1B7F4B);
  }
  if (availability?.available == false) {
    return const Color(0xFFE14E4E);
  }
  if (fallbackMessage != null) {
    return const Color(0xFF66728A);
  }
  return const Color(0xFF66728A);
}

class _DialogSecondaryButton extends StatelessWidget {
  const _DialogSecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      scaleOnPress: true,
      child: Container(
        constraints: BoxConstraints(minHeight: responsive.controlHeight),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FB),
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(color: const Color(0xFFE1E7F0)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: const Color(0xFF4B5870),
            fontSize: responsive.bodyMd,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _nextHermesDisplayName(List<AgentSummary> runtimes) {
  final count = runtimes
      .where((runtime) => runtime.runtime?.trim().toLowerCase() == 'hermes')
      .length;
  return 'Hermes${count + 1}';
}

String _normalizeAgentHandleInput(String value) {
  return value.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
}

String? _softValidateAgentDisplayName(String value) {
  return value.isEmpty ? null : _validateAgentDisplayName(value);
}

String? _validateAgentDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '请输入智能体名称';
  }
  if (trimmed.length > 40) {
    return '名称最多 40 个字符';
  }
  return null;
}

String? _softValidateAgentHandle(String value) {
  return value.isEmpty ? null : _validateAgentHandle(value);
}

String? _validateAgentHandle(String value) {
  final handle = value.trim();
  if (handle.isEmpty) {
    return '请输入 Handle';
  }
  if (handle.length > 63) {
    return 'Handle 最多 63 个字符';
  }
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(handle)) {
    return '仅支持小写字母、数字和连字符，且首尾必须是字母或数字';
  }
  if (handle.contains('--')) {
    return 'Handle 不能包含连续连字符';
  }
  return null;
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
    final started = await ref
        .read(agentsProvider.notifier)
        .upgradeDaemon(agent.agentDid);
    if (started) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.daemonUpgradeStarted());
    }
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
