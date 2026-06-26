import 'dart:convert';

import 'agent_control_payloads.dart';

const runtimeWorkspaceModeRouteRoot = 'route-root';
const runtimeWorkspaceModeSharedRoot = 'shared-root';
const runtimeWorkspaceModeWorktreePerTask = 'worktree-per-task';

const runtimeSandboxReadOnly = 'read-only';
const runtimeSandboxWorkspaceWrite = 'workspace-write';
const runtimeSandboxDangerFullAccess = 'danger-full-access';

enum RuntimeAgentKind { hermes, codex, claudeCode }

extension RuntimeAgentKindInfo on RuntimeAgentKind {
  String get runtime => switch (this) {
    RuntimeAgentKind.hermes => 'hermes',
    RuntimeAgentKind.codex => 'codex',
    RuntimeAgentKind.claudeCode => 'claude-code',
  };

  String? get driverId => switch (this) {
    RuntimeAgentKind.hermes => null,
    RuntimeAgentKind.codex => 'codex',
    RuntimeAgentKind.claudeCode => 'claude-code',
  };

  String get displayLabel => switch (this) {
    RuntimeAgentKind.hermes => 'Hermes',
    RuntimeAgentKind.codex => 'Codex',
    RuntimeAgentKind.claudeCode => 'Claude Code',
  };

  String get handlePlaceholder => switch (this) {
    RuntimeAgentKind.hermes => 'my-hermes',
    RuntimeAgentKind.codex => 'my-codex',
    RuntimeAgentKind.claudeCode => 'my-claude',
  };

  bool get isGenericCli => driverId != null;

  Map<String, Object?> get defaultDriverConfig => switch (this) {
    RuntimeAgentKind.codex => const <String, Object?>{'ephemeral': false},
    RuntimeAgentKind.hermes ||
    RuntimeAgentKind.claudeCode => const <String, Object?>{},
  };
}

class RuntimeAgentCreateOptions {
  const RuntimeAgentCreateOptions({
    required this.kind,
    required this.handle,
    required this.displayName,
    this.workspaceMode = runtimeWorkspaceModeRouteRoot,
    this.sandbox = runtimeSandboxDangerFullAccess,
    this.model,
  });

  final RuntimeAgentKind kind;
  final String handle;
  final String displayName;
  final String workspaceMode;
  final String sandbox;
  final String? model;

  Map<String, Object?> get driverConfig => kind.defaultDriverConfig;
}

String agentCommandId([String prefix = 'cmd']) =>
    '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}';

Map<String, Object?> runtimeAgentCreatePayload({
  required String controllerDid,
  required String registrationToken,
  required String clientRequestId,
  String runtime = 'hermes',
  String displayName = 'Hermes',
  String? handle,
  String? workspace,
  String? driverId,
  String? workspaceMode,
  String? defaultSandbox,
  String? defaultModel,
  Map<String, Object?>? driverConfig,
  Map<String, Object?>? recipientPolicy,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': agentCommandId(),
    'command': 'runtime.agent.create',
    'target_agent_kind': 'runtime',
    'args': <String, Object?>{
      'runtime': runtime,
      'controller_did': controllerDid,
      'registration_token': registrationToken,
      'display_name': displayName,
      'client_request_id': clientRequestId,
      if (handle != null) 'handle': handle,
      if (workspace != null) 'workspace': workspace,
      if (driverId != null) 'driver_id': driverId,
      if (workspaceMode != null) 'workspace_mode': workspaceMode,
      if (defaultSandbox != null) 'default_sandbox': defaultSandbox,
      if (defaultModel != null) 'default_model': defaultModel,
      if (driverConfig != null && driverConfig.isNotEmpty)
        'driver_config': driverConfig,
      if (recipientPolicy != null && recipientPolicy.isNotEmpty)
        'recipient_policy': recipientPolicy,
    },
    'reply_policy': <String, Object?>{'progress': true, 'final': true},
  };
}

Map<String, Object?> runtimeTaskSubmitPayload({
  required String runtimeAgentDid,
  required String text,
  String? commandId,
  String? taskId,
  String? conversationId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': commandId ?? agentCommandId('cmd_runtime_task'),
    'command': 'runtime.task.submit',
    'target_agent_did': runtimeAgentDid,
    if (taskId != null) 'task_id': taskId,
    if (conversationId != null) 'conversation_id': conversationId,
    'args': <String, Object?>{'text': text},
  };
}

Map<String, Object?> agentStatusQueryPayload({
  bool includeRuntimes = true,
  bool includeDiagnostics = true,
  String? commandId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': commandId ?? agentCommandId(),
    'command': 'agent.status.query',
    'target_agent_kind': 'daemon',
    'args': <String, Object?>{
      'include_runtimes': includeRuntimes,
      'include_diagnostics': includeDiagnostics,
    },
  };
}

Map<String, Object?> runtimeSessionResetPayload({
  required String runtimeAgentDid,
  String? conversationId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': agentCommandId(),
    'command': 'runtime.session.reset',
    'target_agent_kind': 'runtime',
    'args': <String, Object?>{
      'runtime_agent_did': runtimeAgentDid,
      if (conversationId != null) 'conversation_id': conversationId,
    },
  };
}

Map<String, Object?> runtimeRunRetryPayload({
  required String runtimeAgentDid,
  required String runId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': agentCommandId(),
    'command': 'runtime.run.retry',
    'target_agent_kind': 'runtime',
    'args': <String, Object?>{
      'runtime_agent_did': runtimeAgentDid,
      'run_id': runId,
    },
  };
}

Map<String, Object?> runtimeInboxQueryPayload({
  required String runtimeAgentDid,
  String scope = 'all',
  int limit = 20,
  String? cursor,
  String? commandId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': commandId ?? agentCommandId('cmd_runtime_inbox'),
    'command': 'runtime.inbox.query',
    'target_agent_kind': 'daemon',
    'args': <String, Object?>{
      'runtime_agent_did': runtimeAgentDid,
      'scope': scope,
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    },
  };
}

Map<String, Object?> runtimeInboxThreadQueryPayload({
  required String runtimeAgentDid,
  required String threadId,
  required String kind,
  String? peerDid,
  String? peerHandle,
  String? groupDid,
  int limit = 20,
  String? cursor,
  String? commandId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': commandId ?? agentCommandId('cmd_runtime_inbox_thread'),
    'command': 'runtime.inbox.thread.query',
    'target_agent_kind': 'daemon',
    'args': <String, Object?>{
      'runtime_agent_did': runtimeAgentDid,
      'thread_id': threadId,
      'kind': kind,
      if (peerDid != null) 'peer_did': peerDid,
      if (peerHandle != null) 'peer_handle': peerHandle,
      if (groupDid != null) 'group_did': groupDid,
      'limit': limit,
      if (cursor != null) 'cursor': cursor,
    },
  };
}

Map<String, Object?> daemonUpgradePayload({
  String targetVersion = 'latest',
  String? commandId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': commandId ?? agentCommandId('cmd_daemon_upgrade'),
    'command': 'daemon.upgrade',
    'target_agent_kind': 'daemon',
    'args': <String, Object?>{'target_version': targetVersion},
  };
}

Map<String, Object?> daemonUpgradeCancelPayload({
  String? upgradeCommandId,
  String? commandId,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': commandId ?? agentCommandId('cmd_daemon_upgrade_cancel'),
    'command': 'daemon.upgrade.cancel',
    'target_agent_kind': 'daemon',
    'args': <String, Object?>{
      if (upgradeCommandId != null) 'upgrade_command_id': upgradeCommandId,
    },
  };
}

Map<String, Object?> daemonDeletePayload({required String daemonAgentDid}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': agentCommandId(),
    'command': 'daemon.delete',
    'target_agent_kind': 'daemon',
    'args': <String, Object?>{'daemon_agent_did': daemonAgentDid},
  };
}

Map<String, Object?> runtimeAgentDeletePayload({
  required String runtimeAgentDid,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': agentCommandId(),
    'command': 'runtime.agent.delete',
    'target_agent_kind': 'runtime',
    'args': <String, Object?>{'runtime_agent_did': runtimeAgentDid},
  };
}

Map<String, Object?> messageAgentBindingDisablePayload({
  required String messageAgentDid,
  String? bindingId,
  String lifecycleAction = 'pause',
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.commandSchema,
    'command_id': agentCommandId('cmd_message_agent_lifecycle'),
    'command': 'message_agent.binding.disable',
    'target_agent_kind': 'runtime',
    'args': <String, Object?>{
      'message_agent_did': messageAgentDid,
      'runtime_agent_did': messageAgentDid,
      'lifecycle_action': lifecycleAction,
      if (bindingId != null && bindingId.trim().isNotEmpty)
        'binding_id': bindingId.trim(),
    },
  };
}

String encodeAgentCommand(Map<String, Object?> payload) => jsonEncode(payload);
