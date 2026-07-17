import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Color, SelectionArea, SelectionContainer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

import '../../app/app_router.dart';
import '../../app/e2e_semantics.dart';
import '../../app/app_services.dart';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/install_command.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/message_agent_runtime_provider.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../../app/ui_feedback.dart';
import '../shared/app_dialog.dart';
import '../shared/identity_flow.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/formatters/localized_ui_formatters.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/semantic_pill.dart';
import '../shared/widgets/app_widgets.dart';
import '../chat/chat_provider.dart';
import 'agent_rename_dialog.dart';
import 'agent_runtime_display.dart';
import 'agent_status_indicator.dart';
import 'agent_visual_status.dart';
import 'agents_provider.dart';

part 'parts/agents_list_part.dart';
part 'parts/agents_detail_part.dart';
part 'parts/agents_access_policy_part.dart';
part 'parts/agents_dialogs_part.dart';
part 'message_agent_settings_page.dart';

class AgentsWorkspacePage extends ConsumerStatefulWidget {
  const AgentsWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  ConsumerState<AgentsWorkspacePage> createState() =>
      _AgentsWorkspacePageState();
}

class _AgentsWorkspacePageState extends ConsumerState<AgentsWorkspacePage> {
  late final AgentsController _agentsController;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _agentsController = ref.read(agentsProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_ensureLoadedAndWatchForHostInstall());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _deferAgentsMutation(
      (controller) => controller.stopInventoryAutoSync(),
      requireMounted: false,
    );
    super.dispose();
  }

  Future<void> _ensureLoadedAndWatchForHostInstall() async {
    if (!ref.read(agentImEnabledProvider)) {
      _deferAgentsMutation((controller) => controller.stopInventoryAutoSync());
      return;
    }
    await _agentsController.ensureLoaded();
    if (_disposed || !mounted) {
      return;
    }
    final state = ref.read(agentsProvider);
    if (state.error == null &&
        !state.isLoading &&
        state.agents.isEmpty &&
        !state.isAutoSyncingInventory) {
      _deferAgentsMutation((controller) => controller.startInventoryAutoSync());
    }
  }

  void _deferAgentsMutation(
    void Function(AgentsController controller) mutate, {
    bool requireMounted = true,
  }) {
    scheduleMicrotask(() {
      if (requireMounted && (_disposed || !mounted)) {
        return;
      }
      mutate(_agentsController);
    });
  }

  @override
  Widget build(BuildContext context) {
    final messageAgentEnabled = ref.watch(agentImEnabledProvider);
    if (!messageAgentEnabled) {
      return const _AgentsTenantUnsupportedView();
    }
    ref.listen<AgentsState>(agentsProvider, (previous, next) {
      final command = next.installCommand;
      if (command != null && previous?.installCommand != command) {
        _showInstallCommand(context, ref, command);
      }
    });
    ref.listen<AgentsState>(agentsProvider, (previous, next) {
      if (next.agents.any((agent) => agent.isDaemon)) {
        _deferAgentsMutation(
          (controller) => controller.stopInventoryAutoSync(),
        );
        return;
      }
      if (next.error == null &&
          !next.isLoading &&
          next.agents.isEmpty &&
          previous?.isLoading == true) {
        _deferAgentsMutation(
          (controller) => controller.startInventoryAutoSync(),
        );
      }
    });

    final state = ref.watch(agentsProvider);
    final responsive = context.awikiResponsive;
    final pendingAgentDids = ref.watch(pendingAgentDidsProvider);
    final selected = _agentSelectionForLayout(
      state,
      fallbackToFirst: responsive.supportsTwoPane,
    );
    final selectedAgentDidForList = responsive.supportsTwoPane
        ? selected?.agentDid
        : state.selectedAgentDid;
    final list = _AgentListPane(
      state: state,
      footer: widget.listFooter,
      pendingAgentDids: pendingAgentDids,
      selectedAgentDid: selectedAgentDidForList,
      onCreateDaemon: () =>
          ref.read(agentsProvider.notifier).createDaemonInstallCommand(),
      onRefreshDaemon: (agent) {
        ref.read(agentsProvider.notifier).refreshDaemonStatus(agent.agentDid);
      },
      onSelect: (agentDid) =>
          ref.read(agentsProvider.notifier).select(agentDid),
      onSyncInventory: () =>
          ref.read(agentsProvider.notifier).syncRemoteInventory(),
    );
    final detail = _AgentDetailPane(
      state: state,
      selected: selected,
      pendingAgentDids: pendingAgentDids,
      onRefresh: (agent) {
        ref.read(agentsProvider.notifier).refreshDaemonStatus(agent.agentDid);
      },
      onCreateRuntime: (agent) => _showCreateRuntimeDialog(
        context,
        ref,
        agent,
        state.runtimesFor(agent.agentDid),
      ),
      onOpenChat: (agent) => _openRuntimeChat(context, ref, agent),
      onRename: (agent) => _showRenameAgentDialog(context, ref, agent),
      onUpgrade: (agent) => _confirmUpgradeDaemon(context, ref, agent),
      onCancelUpgrade: (agent) =>
          ref.read(agentsProvider.notifier).cancelDaemonUpgrade(agent.agentDid),
      onDelete: (agent) => _confirmDeleteAgent(context, ref, agent),
      messageAgentEnabled: messageAgentEnabled,
      onOpenMessageAgentSettings: (agent) => AppNavigator.push<void>(
        context,
        (_) => MessageAgentSettingsPage(initialDaemonDid: agent.agentDid),
      ),
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
    final hasCompactDetailSelection =
        state.selectedAgentDid != null && selected != null;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
      child: !hasCompactDetailSelection
          ? list
          : Column(
              children: <Widget>[
                CupertinoNavigationBar(
                  middle: Text(context.l10n.agentPageTitle),
                  leading: TopBarActionButton(
                    onTap: () =>
                        ref.read(agentsProvider.notifier).clearSelection(),
                    semanticsLabel: context.l10n.commonBack,
                    tooltip: context.l10n.commonBack,
                    child: const Icon(CupertinoIcons.chevron_left),
                  ),
                ),
                Expanded(child: detail),
              ],
            ),
    );
  }
}

AgentSummary? _agentSelectionForLayout(
  AgentsState state, {
  required bool fallbackToFirst,
}) {
  final selectedDid = state.selectedAgentDid;
  if (selectedDid != null) {
    for (final agent in state.agents) {
      if (agent.agentDid == selectedDid) {
        return agent;
      }
    }
    return null;
  }
  if (fallbackToFirst && state.agents.isNotEmpty) {
    return state.agents.first;
  }
  return null;
}

class _AgentsTenantUnsupportedView extends StatelessWidget {
  const _AgentsTenantUnsupportedView();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFFBFDFF)),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: responsive.displayScaled(420),
            ),
            child: Padding(
              padding: EdgeInsets.all(responsive.spacing(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: responsive.displayScaled(52),
                    height: responsive.displayScaled(52),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(
                        responsive.radius(14),
                      ),
                      border: Border.all(color: const Color(0xFFD7E5FF)),
                    ),
                    child: Icon(
                      CupertinoIcons.sparkles,
                      color: const Color(0xFF0B65F8),
                      size: responsive.iconLg,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(16)),
                  Text(
                    context.l10n.agentTenantUnsupportedTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.titleXl,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(8)),
                  Text(
                    context.l10n.agentTenantUnsupportedSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFF66728A),
                      fontSize: responsive.bodyMd,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
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
