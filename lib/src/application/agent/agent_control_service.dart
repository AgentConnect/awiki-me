import '../config/awiki_environment_config.dart';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/install_command.dart';
import '../models/app_thread_ref.dart';
import '../messaging_service.dart';
import '../ports/agent_inventory_port.dart';

abstract interface class AgentControlService {
  Future<List<AgentSummary>> listAgents({bool includeInactive = false});
  Future<InstallCommand> createDaemonInstallCommand({
    required String controllerDid,
    required String clientPlatform,
  });
  Future<void> refreshDaemonStatus(String daemonAgentDid);
  Future<void> createHermesRuntime({
    required String daemonAgentDid,
    required String controllerDid,
  });
  Future<void> resetRuntimeSession({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    String? conversationId,
  });
  Future<void> retryRun({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String runId,
  });
  Future<String> queryRuntimeInbox({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    String scope = 'all',
    int limit = 30,
    String? cursor,
  });
  Future<String> queryRuntimeInboxThread({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String threadId,
    required String kind,
    String? peerDid,
    String? groupDid,
    int limit = 50,
    String? cursor,
  });
  Future<void> upgradeDaemon(String daemonAgentDid);
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  });
  Future<void> unbindAgent(String agentDid);
}

class DefaultAgentControlService implements AgentControlService {
  DefaultAgentControlService({
    required AgentInventoryPort inventory,
    required MessagingService messages,
    String? downloadBaseUrl,
    AwikiEnvironmentConfig? environment,
  }) : this._(
         inventory: inventory,
         messages: messages,
         environment: environment ?? AwikiEnvironmentConfig.fromEnvironment(),
         downloadBaseUrl: downloadBaseUrl,
       );

  DefaultAgentControlService._({
    required AgentInventoryPort inventory,
    required MessagingService messages,
    required AwikiEnvironmentConfig environment,
    String? downloadBaseUrl,
  }) : _inventory = inventory,
       _messages = messages,
       _environment = environment,
       downloadBaseUrl =
           _normalizeDownloadBaseUrl(downloadBaseUrl) ??
           environment.daemonDownloadBaseUrl;

  final AgentInventoryPort _inventory;
  final MessagingService _messages;
  final AwikiEnvironmentConfig _environment;
  final String downloadBaseUrl;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) {
    return _inventory.listAgents(includeInactive: includeInactive);
  }

  @override
  Future<InstallCommand> createDaemonInstallCommand({
    required String controllerDid,
    required String clientPlatform,
  }) async {
    final token = await _inventory.issueDaemonToken(
      controllerDid: controllerDid,
      clientPlatform: clientPlatform,
    );
    final installerUrl = '$downloadBaseUrl/install.sh';
    return InstallCommand(
      token: token,
      installerUrl: installerUrl,
      packageUrlTemplate:
          '$downloadBaseUrl/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
      command: 'curl -fsSL $installerUrl | sh -s -- --token ${token.token}',
      fallbackCommand: _fallbackInstallCommand(
        token.token,
        environment: _environment,
        downloadBaseUrl: downloadBaseUrl,
      ),
    );
  }

  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid) {
    return _sendDaemonPayload(
      daemonAgentDid,
      agentStatusQueryPayload(),
      idempotencyKey: 'agent-status:$daemonAgentDid',
    );
  }

  @override
  Future<void> createHermesRuntime({
    required String daemonAgentDid,
    required String controllerDid,
  }) async {
    final token = await _inventory.issueRuntimeToken(
      controllerDid: controllerDid,
      daemonAgentDid: daemonAgentDid,
      runtime: 'hermes',
    );
    final requestId = agentCommandId('app_req');
    await _sendDaemonPayload(
      daemonAgentDid,
      runtimeAgentCreatePayload(
        controllerDid: controllerDid,
        registrationToken: token.token,
        clientRequestId: requestId,
      ),
      idempotencyKey: 'runtime-create:$daemonAgentDid:$requestId',
    );
  }

  @override
  Future<void> resetRuntimeSession({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    String? conversationId,
  }) {
    return _sendDaemonPayload(
      daemonAgentDid,
      runtimeSessionResetPayload(
        runtimeAgentDid: runtimeAgentDid,
        conversationId: conversationId,
      ),
    );
  }

  @override
  Future<void> retryRun({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String runId,
  }) {
    return _sendDaemonPayload(
      daemonAgentDid,
      runtimeRunRetryPayload(runtimeAgentDid: runtimeAgentDid, runId: runId),
    );
  }

  @override
  Future<String> queryRuntimeInbox({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    String scope = 'all',
    int limit = 30,
    String? cursor,
  }) async {
    final commandId = agentCommandId('cmd_runtime_inbox');
    await _sendDaemonPayload(
      daemonAgentDid,
      runtimeInboxQueryPayload(
        runtimeAgentDid: runtimeAgentDid,
        scope: scope,
        limit: limit,
        cursor: cursor,
        commandId: commandId,
      ),
      idempotencyKey: 'runtime-inbox:$runtimeAgentDid:$commandId',
    );
    return commandId;
  }

  @override
  Future<String> queryRuntimeInboxThread({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String threadId,
    required String kind,
    String? peerDid,
    String? groupDid,
    int limit = 50,
    String? cursor,
  }) async {
    final commandId = agentCommandId('cmd_runtime_inbox_thread');
    await _sendDaemonPayload(
      daemonAgentDid,
      runtimeInboxThreadQueryPayload(
        runtimeAgentDid: runtimeAgentDid,
        threadId: threadId,
        kind: kind,
        peerDid: peerDid,
        groupDid: groupDid,
        limit: limit,
        cursor: cursor,
        commandId: commandId,
      ),
      idempotencyKey:
          'runtime-inbox-thread:$runtimeAgentDid:$threadId:$commandId',
    );
    return commandId;
  }

  @override
  Future<void> upgradeDaemon(String daemonAgentDid) {
    return _sendDaemonPayload(daemonAgentDid, daemonUpgradePayload());
  }

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) {
    return _inventory.updateDisplayName(
      agentDid: agentDid,
      displayName: displayName,
    );
  }

  @override
  Future<void> unbindAgent(String agentDid) {
    return _inventory.unbindAgent(agentDid: agentDid);
  }

  Future<void> _sendDaemonPayload(
    String daemonAgentDid,
    Map<String, Object?> payload, {
    String? idempotencyKey,
  }) async {
    await _messages.sendPayload(
      thread: AppThreadRef.direct(daemonAgentDid),
      payload: payload,
      secure: true,
      idempotencyKey: idempotencyKey,
    );
  }
}

String _fallbackInstallCommand(
  String token, {
  required AwikiEnvironmentConfig environment,
  required String downloadBaseUrl,
}) {
  final parts = <String>[
    'awiki-deamon',
    'install',
    '--token',
    token,
    '--base-url',
    environment.baseUrl,
  ];
  if (downloadBaseUrl != environment.daemonDownloadBaseUrl) {
    parts.addAll(<String>['--download-base-url', downloadBaseUrl]);
  }
  return parts.join(' ');
}

String? _normalizeDownloadBaseUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed.replaceAll(RegExp(r'/+$'), '');
}
