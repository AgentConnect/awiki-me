import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../shared/identity_flow.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/responsive_layout.dart';
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
      onSelect: (agentDid) =>
          ref.read(agentsProvider.notifier).select(agentDid),
    );
    final detail = _AgentDetailPane(
      state: state,
      selected: state.selectedAgent,
      onRefresh: (agent) =>
          ref.read(agentsProvider.notifier).refreshDaemonStatus(agent.agentDid),
      onCreateRuntime: (agent) =>
          ref.read(agentsProvider.notifier).createHermesRuntime(agent.agentDid),
      onOpenChat: (agent) => _openRuntimeChat(context, ref, agent),
      onRename: (agent) => _showRenameAgentDialog(context, ref, agent),
      onRetryRun: (agent) => _showRetryRunDialog(context, ref, agent),
      onResetRuntime: (agent) =>
          _confirmResetRuntimeSession(context, ref, agent),
      onUpgrade: (agent) => _confirmUpgradeDaemon(context, ref, agent),
      onCreateInstallCommand: () =>
          ref.read(agentsProvider.notifier).createDaemonInstallCommand(),
      onUnbind: () => _confirmUnbindSelected(context, ref),
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
                  leading: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () =>
                        ref.read(agentsProvider.notifier).clearSelection(),
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
    required this.onSelect,
  });

  final AgentsState state;
  final Widget? footer;
  final VoidCallback onCreateDaemon;
  final ValueChanged<String> onSelect;

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
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(34, 34),
                  onPressed: state.isActing ? null : onCreateDaemon,
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
                for (final agent in state.agents)
                  _AgentListTile(
                    agent: agent,
                    selected: state.selectedAgent?.agentDid == agent.agentDid,
                    onTap: () => onSelect(agent.agentDid),
                  ),
              ],
            ),
          ),
          if (state.error != null)
            Padding(
              padding: EdgeInsets.all(responsive.spacing(12)),
              child: Text(
                state.error!,
                style: TextStyle(
                  color: AwikiMeColors.danger,
                  fontSize: responsive.metaSm,
                ),
              ),
            ),
          if (footer != null) footer!,
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
  });

  final AgentSummary agent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.spacing(6)),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          padding: EdgeInsets.all(responsive.spacing(12)),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF2FF) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(responsive.radius(8)),
            border: Border.all(
              color: selected
                  ? const Color(0xFFBBD2FF)
                  : const Color(0xFFE5EAF2),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                agent.isDaemon
                    ? CupertinoIcons.desktopcomputer
                    : CupertinoIcons.sparkles,
                color: const Color(0xFF0B65F8),
                size: responsive.iconMd,
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      agent.displayName,
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
                      '${agent.isDaemon ? 'Daemon' : agent.runtime ?? 'Runtime'} · ${agent.latest.status}',
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
              _StatusDot(status: agent.latest.status),
            ],
          ),
        ),
      ),
    );
  }
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
    required this.onCreateInstallCommand,
    required this.onUnbind,
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
  final VoidCallback onCreateInstallCommand;
  final VoidCallback onUnbind;

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
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: EdgeInsets.all(responsive.spacing(24)),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  agent.displayName,
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
          Wrap(
            spacing: responsive.spacing(8),
            runSpacing: responsive.spacing(8),
            children: <Widget>[
              if (agent.isDaemon)
                _ActionButton(
                  icon: CupertinoIcons.refresh,
                  label: '刷新状态',
                  onPressed: state.isActing ? null : () => onRefresh(agent),
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
                  onPressed: state.isActing ? null : () => onRetryRun(agent),
                ),
              if (agent.isDaemon)
                _ActionButton(
                  icon: CupertinoIcons.arrow_up_circle,
                  label: '升级',
                  onPressed: state.isActing ? null : () => onUpgrade(agent),
                ),
              if (agent.isDaemon)
                _ActionButton(
                  icon: CupertinoIcons.chevron_left_slash_chevron_right,
                  label: '安装命令',
                  onPressed: state.isActing ? null : onCreateInstallCommand,
                ),
              _ActionButton(
                icon: CupertinoIcons.xmark_circle,
                label: '解绑',
                danger: true,
                onPressed: state.isActing ? null : onUnbind,
              ),
            ],
          ),
          if (isRefreshing) ...<Widget>[
            SizedBox(height: responsive.spacing(10)),
            const _RefreshPendingNotice(),
          ],
          if (state.error != null) ...<Widget>[
            SizedBox(height: responsive.spacing(10)),
            Text(
              state.error!,
              style: TextStyle(
                color: AwikiMeColors.danger,
                fontSize: responsive.metaSm,
              ),
            ),
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
          const _DisabledAdvancedAction(),
        ],
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
          Expanded(child: Text(runtime.displayName)),
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
                  overflow: TextOverflow.ellipsis,
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
              overflow: TextOverflow.ellipsis,
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
            Text(
              _redactDiagnosticValue(agent.latest.lastErrorSummary),
              style: TextStyle(
                color: const Color(0xFF7A4A00),
                fontSize: responsive.bodySm,
              ),
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
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF66728A),
                          fontSize: responsive.metaSm,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _redactDiagnosticValue(entry.value, key: entry.key),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF101B32),
                          fontSize: responsive.metaSm,
                        ),
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
                        overflow: TextOverflow.ellipsis,
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
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: danger ? const Color(0xFFFFEBEB) : const Color(0xFFEAF2FF),
      disabledColor: const Color(0xFFE5EAF2),
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
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

class _RefreshPendingNotice extends StatelessWidget {
  const _RefreshPendingNotice();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      children: <Widget>[
        const CupertinoActivityIndicator(radius: 8),
        SizedBox(width: responsive.spacing(8)),
        Text(
          '正在刷新状态',
          style: TextStyle(
            color: const Color(0xFF66728A),
            fontSize: responsive.metaSm,
          ),
        ),
      ],
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
  return openDirectConversationForDid(
    context,
    ref,
    peerDid: agent.agentDid,
    peerName: agent.displayName,
    avatarSeed: agent.handle ?? agent.agentDid,
  );
}

Future<void> _showRenameAgentDialog(
  BuildContext context,
  WidgetRef ref,
  AgentSummary agent,
) async {
  final controller = TextEditingController(text: agent.displayName);
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

Future<void> _confirmUnbindSelected(BuildContext context, WidgetRef ref) async {
  final confirmed = await _confirm(
    context,
    title: '解绑',
    message: '解绑不会删除 DID、聊天历史或远端身份记录。',
    actionLabel: '解绑',
    destructive: true,
  );
  if (confirmed) {
    await ref.read(agentsProvider.notifier).unbindSelected();
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
  showCupertinoModalPopup<void>(
    context: context,
    builder: (context) => _InstallCommandSheet(
      command: command,
      onRegenerate: () {
        Navigator.of(context).pop();
        ref.read(agentsProvider.notifier).clearInstallCommand();
        ref.read(agentsProvider.notifier).createDaemonInstallCommand();
      },
      onClose: () {
        Navigator.of(context).pop();
        ref.read(agentsProvider.notifier).clearInstallCommand();
      },
    ),
  );
}

class _InstallCommandSheet extends StatefulWidget {
  const _InstallCommandSheet({
    required this.command,
    required this.onRegenerate,
    required this.onClose,
  });

  final InstallCommand command;
  final VoidCallback onRegenerate;
  final VoidCallback onClose;

  @override
  State<_InstallCommandSheet> createState() => _InstallCommandSheetState();
}

class _InstallCommandSheetState extends State<_InstallCommandSheet> {
  bool _manualExpanded = false;

  @override
  Widget build(BuildContext context) {
    final expiresAt = widget.command.token.expiresAt?.toLocal();
    final isExpired =
        widget.command.token.expiresAt != null &&
        !widget.command.token.expiresAt!.isAfter(DateTime.now().toUtc());
    return CupertinoActionSheet(
      title: const Text('安装代理'),
      message: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _CommandText(widget.command.command),
          const SizedBox(height: 10),
          Text(
            isExpired
                ? 'token 过期'
                : expiresAt == null
                ? 'token 已生成'
                : 'token 有效期至 ${expiresAt.toString()}',
            style: TextStyle(
              color: isExpired ? AwikiMeColors.danger : const Color(0xFF66728A),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.command.command),
              );
              if (context.mounted) {
                AwikiMeToast.show(context, '已复制');
              }
            },
            child: const Text('复制命令'),
          ),
          if (isExpired)
            CupertinoButton(
              onPressed: widget.onRegenerate,
              child: const Text('重新生成命令'),
            ),
          CupertinoButton(
            key: const Key('agent-install-manual-toggle'),
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                _manualExpanded = !_manualExpanded;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Text('手动下载'),
                const SizedBox(width: 4),
                Icon(
                  _manualExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 16,
                ),
              ],
            ),
          ),
          if (_manualExpanded) ...<Widget>[
            const SizedBox(height: 8),
            _ManualDownloadRow(
              label: 'installer',
              value: widget.command.installerUrl,
            ),
            const SizedBox(height: 8),
            _ManualDownloadRow(
              label: 'package',
              value: widget.command.packageUrlTemplate,
            ),
            const SizedBox(height: 8),
            const Text('手动命令', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            _CommandText(widget.command.fallbackCommand),
          ],
        ],
      ),
      actions: <Widget>[
        CupertinoActionSheetAction(
          onPressed: widget.onClose,
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ManualDownloadRow extends StatelessWidget {
  const _ManualDownloadRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        _CommandText(value),
      ],
    );
  }
}

class _CommandText extends StatelessWidget {
  const _CommandText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          value,
          softWrap: false,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
      ),
    );
  }
}
