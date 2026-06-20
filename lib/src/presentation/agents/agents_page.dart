import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Color, SelectableText, SelectionArea, SelectionContainer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/config/awiki_environment_config.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/message_agent_runtime_provider.dart';
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

part 'parts/agents_list_part.dart';
part 'parts/agents_detail_part.dart';
part 'parts/agents_access_policy_part.dart';
part 'parts/agents_dialogs_part.dart';

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
    final messageAgentEnabled = ref.watch(agentImEnabledProvider);
    final responsive = context.awikiResponsive;
    final pendingAgentDids = ref.watch(pendingAgentDidsProvider);
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
      messageAgentEnabled: messageAgentEnabled,
      onBootstrapMessageAgent: (agent) => ref
          .read(agentsProvider.notifier)
          .bootstrapMessageAgent(daemonDid: agent.agentDid),
      onPauseMessageAgent: (agent) =>
          _confirmPauseMessageAgent(context, ref, agent),
      onDeleteMessageAgent: (agent) =>
          _confirmDeleteMessageAgent(context, ref, agent),
      onRevokeMessageAgentAuthorization: (agent) =>
          _confirmRevokeMessageAgentAuthorization(context, ref, agent),
      onSaveInvocationPolicy: (agentDid, policy) => ref
          .read(agentsProvider.notifier)
          .saveInvocationPolicy(agentDid, policy),
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
