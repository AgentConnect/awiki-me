import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../config/awiki_environment_config.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';
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
    required String handle,
    required String displayName,
  });
  Future<void> ensureMessageAgentBootstrap({
    required String daemonAgentDid,
    required String controllerDid,
    required String appInstanceId,
    required UserSubkeyPackage userSubkeyPackage,
    String? userHandle,
    String? runtimeRegistrationToken,
    String? runId,
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
    int limit = 20,
    String? cursor,
  });
  Future<String> queryRuntimeInboxThread({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String threadId,
    required String kind,
    String? peerDid,
    String? peerHandle,
    String? groupDid,
    int limit = 20,
    String? cursor,
  });
  Future<void> upgradeDaemon(String daemonAgentDid);
  Future<void> deleteDaemon(String daemonAgentDid);
  Future<void> deleteRuntimeAgent({
    required String daemonAgentDid,
    required String runtimeAgentDid,
  });
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  });
  Future<void> unbindAgent(String agentDid);
  Future<AgentInvocationPolicy> getInvocationPolicy(String agentDid);
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  });
}

class DefaultAgentControlService implements AgentControlService {
  DefaultAgentControlService({
    required AgentInventoryPort inventory,
    required MessagingService messages,
    String? downloadBaseUrl,
    AwikiEnvironmentConfig? environment,
    bool? agentImEnabled,
  }) : this._(
         inventory: inventory,
         messages: messages,
         environment: environment ?? AwikiEnvironmentConfig.fromEnvironment(),
         downloadBaseUrl: downloadBaseUrl,
         agentImEnabled: agentImEnabled,
       );

  DefaultAgentControlService._({
    required AgentInventoryPort inventory,
    required MessagingService messages,
    required AwikiEnvironmentConfig environment,
    String? downloadBaseUrl,
    bool? agentImEnabled,
  }) : _inventory = inventory,
       _messages = messages,
       _environment = environment,
       _agentImEnabled = agentImEnabled ?? environment.agentImEnabled,
       downloadBaseUrl =
           _normalizeDownloadBaseUrl(downloadBaseUrl) ??
           environment.daemonDownloadBaseUrl;

  final AgentInventoryPort _inventory;
  final MessagingService _messages;
  final AwikiEnvironmentConfig _environment;
  final bool _agentImEnabled;
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
    required String handle,
    required String displayName,
  }) async {
    final token = await _inventory.issueRuntimeToken(
      controllerDid: controllerDid,
      daemonAgentDid: daemonAgentDid,
      runtime: 'hermes',
      handle: handle,
      displayName: displayName,
    );
    final requestId = agentCommandId('app_req');
    await _sendDaemonPayload(
      daemonAgentDid,
      runtimeAgentCreatePayload(
        controllerDid: controllerDid,
        registrationToken: token.token,
        clientRequestId: requestId,
        handle: handle,
        displayName: displayName,
      ),
      idempotencyKey: 'runtime-create:$daemonAgentDid:$requestId',
    );
  }

  @override
  Future<void> ensureMessageAgentBootstrap({
    required String daemonAgentDid,
    required String controllerDid,
    required String appInstanceId,
    required UserSubkeyPackage userSubkeyPackage,
    String? userHandle,
    String? runtimeRegistrationToken,
    String? runId,
  }) async {
    if (!_agentImEnabled) {
      return;
    }
    final userDid = userSubkeyPackage.userDid;
    final idempotencyKey = messageAgentBootstrapAttemptIdempotencyKey(
      userDid: userDid,
      appInstanceId: appInstanceId,
      runId: runId,
    );
    final runtimeToken =
        runtimeRegistrationToken ??
        (await _inventory.issueRuntimeToken(
          controllerDid: controllerDid,
          daemonAgentDid: daemonAgentDid,
          runtime: appMessageHandlerRuntime,
          handle: _messageAgentRuntimeHandle(
            userDid: userDid,
            appInstanceId: appInstanceId,
          ),
          displayName: 'Hermes Message Agent',
        )).token;
    final envelope = DaemonBootstrapEnvelope(
      bootstrapId: messageAgentBootstrapAttemptId(
        userDid: userDid,
        appInstanceId: appInstanceId,
        runId: runId,
      ),
      idempotencyKey: idempotencyKey,
      appInstanceId: appInstanceId,
      controllerDid: controllerDid,
      userHandle: userHandle,
      runId: runId,
      userSubkeyPackage: userSubkeyPackage,
      desiredMessageAgent: DesiredMessageAgent(
        ensureOnceKey: messageAgentEnsureOnceKey(
          userDid: userDid,
          appInstanceId: appInstanceId,
        ),
        runtimeRegistrationToken: runtimeToken,
      ),
    );
    await _sendDaemonPayload(
      daemonAgentDid,
      envelope.toJson(),
      idempotencyKey: idempotencyKey,
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
    int limit = 20,
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
    String? peerHandle,
    String? groupDid,
    int limit = 20,
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
        peerHandle: peerHandle,
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
  Future<void> deleteDaemon(String daemonAgentDid) {
    return _sendDaemonPayload(
      daemonAgentDid,
      daemonDeletePayload(daemonAgentDid: daemonAgentDid),
    );
  }

  @override
  Future<void> deleteRuntimeAgent({
    required String daemonAgentDid,
    required String runtimeAgentDid,
  }) {
    return _sendDaemonPayload(
      daemonAgentDid,
      runtimeAgentDeletePayload(runtimeAgentDid: runtimeAgentDid),
    );
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

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy(String agentDid) {
    return _inventory.getInvocationPolicy(agentDid: agentDid);
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) {
    return _inventory.updateInvocationPolicy(
      agentDid: agentDid,
      policy: policy,
    );
  }

  Future<void> _sendDaemonPayload(
    String daemonAgentDid,
    Map<String, Object?> payload, {
    String? idempotencyKey,
  }) async {
    await _messages.sendPayload(
      thread: AppThreadRef.direct(daemonAgentDid),
      payload: payload,
      secure: false,
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

String _messageAgentRuntimeHandle({
  required String userDid,
  required String appInstanceId,
}) {
  const prefix = 'hermes-msg';
  final seed = '${userDid.trim()}|${appInstanceId.trim()}';
  final hash = crypto.sha256
      .convert(utf8.encode(seed))
      .toString()
      .substring(0, 12);
  final appPart = _safeHandleComponent(appInstanceId);
  const maxHandleLength = 48;
  final maxAppLength = maxHandleLength - prefix.length - hash.length - 2;
  final appTail =
      (appPart.length > maxAppLength
              ? appPart.substring(appPart.length - maxAppLength)
              : appPart)
          .replaceAll(RegExp(r'^-+|-+$'), '');
  final handle = '$prefix-${appTail.isEmpty ? 'agent' : appTail}-$hash';
  return handle.length > maxHandleLength
      ? handle.substring(0, maxHandleLength).replaceAll(RegExp(r'^-+|-+$'), '')
      : handle;
}

String _safeHandleComponent(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? 'agent' : normalized;
}
