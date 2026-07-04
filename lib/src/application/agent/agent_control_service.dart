import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../config/awiki_environment_config.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/agent/agent_command.dart';
import '../../domain/entities/agent/agent_invocation_policy.dart';
import '../../domain/entities/agent/message_agent_runtime_provider.dart';
import '../../domain/entities/agent/message_agent_binding.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/install_command.dart';
import '../models/app_thread_ref.dart';
import '../messaging_service.dart';
import '../ports/agent_inventory_port.dart';
import '../ports/identity_core_port.dart';
import '../ports/message_agent_binding_port.dart';

abstract interface class AgentControlService {
  Future<List<AgentSummary>> listAgents({bool includeInactive = false});
  Future<InstallCommand> createDaemonInstallCommand({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  });
  Future<void> refreshDaemonStatus(String daemonAgentDid, {String? commandId});
  Future<void> createRuntimeAgent({
    required String daemonAgentDid,
    required String controllerDid,
    required RuntimeAgentCreateOptions options,
    String? clientRequestId,
  });
  Future<void> createHermesRuntime({
    required String daemonAgentDid,
    required String controllerDid,
    required String handle,
    required String displayName,
    String? clientRequestId,
  });
  Future<void> ensureMessageAgentBootstrap({
    required String daemonAgentDid,
    required String controllerDid,
    required String appInstanceId,
    required UserSubkeyPackage userSubkeyPackage,
    required DaemonBootstrapPublicKey daemonBootstrapPublicKey,
    String? userHandle,
    String? runtimeRegistrationToken,
    String? runId,
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
  Future<String> upgradeDaemon(String daemonAgentDid, {String? commandId});
  Future<String> cancelDaemonUpgrade(
    String daemonAgentDid, {
    String? commandId,
    String? upgradeCommandId,
  });
  Future<void> deleteDaemon(String daemonAgentDid);
  Future<void> deleteRuntimeAgent({
    required String daemonAgentDid,
    required String runtimeAgentDid,
  });
  Future<MessageAgentBinding> pauseMessageAgent({
    required String daemonAgentDid,
    required String messageAgentDid,
  });
  Future<MessageAgentBinding> deleteMessageAgent({
    required String daemonAgentDid,
    required String messageAgentDid,
  });
  Future<MessageAgentBinding> revokeMessageAgentAuthorization({
    required String daemonAgentDid,
    required String messageAgentDid,
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
    MessageAgentBindingPort? messageAgentBindings,
    IdentityCorePort? identities,
    String? downloadBaseUrl,
    AwikiEnvironmentConfig? environment,
    bool? agentImEnabled,
    String Function()? preferredLanguageProvider,
  }) : this._(
         inventory: inventory,
         messages: messages,
         messageAgentBindings: messageAgentBindings,
         identities: identities,
         environment: environment ?? AwikiEnvironmentConfig.fromEnvironment(),
         downloadBaseUrl: downloadBaseUrl,
         agentImEnabled: agentImEnabled,
         preferredLanguageProvider: preferredLanguageProvider,
       );

  DefaultAgentControlService._({
    required AgentInventoryPort inventory,
    required MessagingService messages,
    MessageAgentBindingPort? messageAgentBindings,
    IdentityCorePort? identities,
    required AwikiEnvironmentConfig environment,
    String? downloadBaseUrl,
    bool? agentImEnabled,
    String Function()? preferredLanguageProvider,
  }) : _inventory = inventory,
       _messages = messages,
       _messageAgentBindings = messageAgentBindings,
       _identities = identities,
       _environment = environment,
       _agentImEnabled = agentImEnabled ?? environment.agentImEnabled,
       _preferredLanguageProvider =
           preferredLanguageProvider ?? (() => 'zh-Hans'),
       downloadBaseUrl =
           _normalizeDownloadBaseUrl(downloadBaseUrl) ??
           environment.daemonDownloadBaseUrl;

  final AgentInventoryPort _inventory;
  final MessagingService _messages;
  final MessageAgentBindingPort? _messageAgentBindings;
  final IdentityCorePort? _identities;
  final AwikiEnvironmentConfig _environment;
  final bool _agentImEnabled;
  final String Function() _preferredLanguageProvider;
  final String downloadBaseUrl;
  static const Duration _messageAgentRuntimeWaitTimeout = Duration(seconds: 90);
  static const Duration _messageAgentRuntimeWaitInterval = Duration(seconds: 2);
  static const Duration _daemonPayloadSendTimeout = Duration(seconds: 12);

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) {
    return _inventory.listAgents(includeInactive: includeInactive);
  }

  @override
  Future<InstallCommand> createDaemonInstallCommand({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    final token = await _inventory.issueDaemonToken(
      controllerDid: controllerDid,
      controllerHandle: controllerHandle,
      clientPlatform: clientPlatform,
    );
    final installerUrl = '$downloadBaseUrl/install.sh';
    final cleanupUrl = '$downloadBaseUrl/cleanup.sh';
    return InstallCommand(
      token: token,
      installerUrl: installerUrl,
      cleanupUrl: cleanupUrl,
      packageUrlTemplate:
          '$downloadBaseUrl/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
      command: _scriptInstallCommand(
        token.token,
        environment: _environment,
        installerUrl: installerUrl,
        downloadBaseUrl: downloadBaseUrl,
      ),
      cleanupCommand: 'curl -fsSL $cleanupUrl | sh',
      fallbackCommand: _fallbackInstallCommand(
        token.token,
        environment: _environment,
        downloadBaseUrl: downloadBaseUrl,
      ),
    );
  }

  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid, {String? commandId}) {
    final effectiveCommandId = commandId ?? agentCommandId('cmd_agent_status');
    return _sendDaemonPayload(
      daemonAgentDid,
      agentStatusQueryPayload(commandId: effectiveCommandId),
      idempotencyKey: 'agent-status:$daemonAgentDid:$effectiveCommandId',
    );
  }

  @override
  Future<void> createHermesRuntime({
    required String daemonAgentDid,
    required String controllerDid,
    required String handle,
    required String displayName,
    String? clientRequestId,
  }) {
    final preferredLanguage = _preferredLanguage();
    return createRuntimeAgent(
      daemonAgentDid: daemonAgentDid,
      controllerDid: controllerDid,
      options: RuntimeAgentCreateOptions(
        kind: RuntimeAgentKind.hermes,
        handle: handle,
        displayName: displayName,
        preferredLanguage: preferredLanguage,
      ),
      clientRequestId: clientRequestId,
    );
  }

  @override
  Future<void> createRuntimeAgent({
    required String daemonAgentDid,
    required String controllerDid,
    required RuntimeAgentCreateOptions options,
    String? clientRequestId,
  }) async {
    final kind = options.kind;
    final driverConfig = options.driverConfig;
    final preferredLanguage =
        _normalizePreferredLanguage(options.preferredLanguage) ??
        _preferredLanguage();
    final token = await _inventory.issueRuntimeToken(
      controllerDid: controllerDid,
      daemonAgentDid: daemonAgentDid,
      runtime: kind.runtime,
      handle: options.handle,
      displayName: options.displayName,
      preferredLanguage: preferredLanguage,
      driverId: kind.driverId,
      workspaceMode: kind.isGenericCli ? options.workspaceMode : null,
      defaultSandbox: kind.isGenericCli ? options.sandbox : null,
      defaultModel: kind.isGenericCli ? options.model : null,
      driverConfig: driverConfig,
    );
    final requestId = clientRequestId ?? agentCommandId('app_req');
    await _sendDaemonPayload(
      daemonAgentDid,
      runtimeAgentCreatePayload(
        controllerDid: controllerDid,
        registrationToken: token.token,
        clientRequestId: requestId,
        runtime: kind.runtime,
        handle: options.handle,
        displayName: options.displayName,
        driverId: kind.driverId,
        workspaceMode: kind.isGenericCli ? options.workspaceMode : null,
        defaultSandbox: kind.isGenericCli ? options.sandbox : null,
        defaultModel: kind.isGenericCli ? options.model : null,
        preferredLanguage: preferredLanguage,
        driverConfig: driverConfig,
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
    required DaemonBootstrapPublicKey daemonBootstrapPublicKey,
    String? userHandle,
    String? runtimeRegistrationToken,
    String? runId,
  }) async {
    if (!_agentImEnabled) {
      throw StateError('Message Agent is disabled.');
    }
    final userDid = userSubkeyPackage.userDid;
    final idempotencyKey = messageAgentBootstrapAttemptIdempotencyKey(
      userDid: userDid,
      appInstanceId: appInstanceId,
      runId: runId,
    );
    final preferredLanguage = _preferredLanguage();
    final runtimeToken =
        runtimeRegistrationToken ??
        (await _inventory.issueRuntimeToken(
          controllerDid: controllerDid,
          daemonAgentDid: daemonAgentDid,
          runtime: defaultMessageAgentRuntimeProvider.runtime,
          handle: _messageAgentRuntimeHandle(
            userDid: userDid,
            appInstanceId: appInstanceId,
          ),
          displayName: defaultMessageAgentRuntimeProvider.runtimeDisplayName,
          preferredLanguage: preferredLanguage,
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
        preferredLanguage: preferredLanguage,
        ensureOnceKey: messageAgentEnsureOnceKey(
          userDid: userDid,
          appInstanceId: appInstanceId,
        ),
        runtimeRegistrationToken: runtimeToken,
      ),
    );
    final secureEnvelope = await DaemonSecureBootstrapEncryptor().encrypt(
      internalEnvelope: envelope,
      recipientDaemonDid: daemonAgentDid,
      recipientKey: daemonBootstrapPublicKey,
    );
    await _sendDaemonPayload(
      daemonAgentDid,
      secureEnvelope,
      idempotencyKey: idempotencyKey,
      secure: false,
    );
    final runtime = await _waitForMessageAgentRuntime(
      daemonAgentDid: daemonAgentDid,
      userDid: userDid,
      appInstanceId: appInstanceId,
    );
    await _requireMessageAgentBindings().ensureBinding(
      userDid: userDid,
      daemonAgentDid: daemonAgentDid,
      messageAgentDid: runtime.agentDid,
      runtimeProvider: appMessageHandlerRuntimeProvider,
      runtimeProfile: const <String, Object?>{
        'profile': appMessageHandlerRuntimeProfile,
      },
      delegatedKeyVerificationMethod: userSubkeyPackage.verificationMethod,
    );
  }

  String _preferredLanguage() {
    return _normalizePreferredLanguage(_preferredLanguageProvider()) ??
        'zh-Hans';
  }

  static String? _normalizePreferredLanguage(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    switch (normalized.toLowerCase()) {
      case 'zh':
      case 'zh-cn':
      case 'zh-hans':
      case 'zh_hans':
        return 'zh-Hans';
      case 'en':
      case 'en-us':
      case 'en-gb':
        return 'en';
      default:
        return null;
    }
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
  Future<String> upgradeDaemon(
    String daemonAgentDid, {
    String? commandId,
  }) async {
    final effectiveCommandId =
        commandId ?? agentCommandId('cmd_daemon_upgrade');
    await _sendDaemonPayload(
      daemonAgentDid,
      daemonUpgradePayload(commandId: effectiveCommandId),
      idempotencyKey: 'daemon-upgrade:$daemonAgentDid:$effectiveCommandId',
    );
    return effectiveCommandId;
  }

  @override
  Future<String> cancelDaemonUpgrade(
    String daemonAgentDid, {
    String? commandId,
    String? upgradeCommandId,
  }) async {
    final effectiveCommandId =
        commandId ?? agentCommandId('cmd_daemon_upgrade_cancel');
    await _sendDaemonPayload(
      daemonAgentDid,
      daemonUpgradeCancelPayload(
        commandId: effectiveCommandId,
        upgradeCommandId: upgradeCommandId,
      ),
      idempotencyKey:
          'daemon-upgrade-cancel:$daemonAgentDid:$effectiveCommandId',
    );
    return effectiveCommandId;
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
  Future<MessageAgentBinding> pauseMessageAgent({
    required String daemonAgentDid,
    required String messageAgentDid,
  }) async {
    final binding = await _requireMessageAgentBindings().disableBinding(
      messageAgentDid: messageAgentDid,
    );
    await _sendDaemonPayload(
      daemonAgentDid,
      messageAgentBindingDisablePayload(
        messageAgentDid: messageAgentDid,
        bindingId: binding.id,
        lifecycleAction: 'pause',
      ),
      idempotencyKey: 'message-agent-disable:$messageAgentDid',
    );
    return binding;
  }

  @override
  Future<MessageAgentBinding> deleteMessageAgent({
    required String daemonAgentDid,
    required String messageAgentDid,
  }) async {
    final binding = await pauseMessageAgent(
      daemonAgentDid: daemonAgentDid,
      messageAgentDid: messageAgentDid,
    );
    await deleteRuntimeAgent(
      daemonAgentDid: daemonAgentDid,
      runtimeAgentDid: messageAgentDid,
    );
    return binding;
  }

  @override
  Future<MessageAgentBinding> revokeMessageAgentAuthorization({
    required String daemonAgentDid,
    required String messageAgentDid,
  }) async {
    final bindings = _requireMessageAgentBindings();
    final activeBinding = await bindings.getActiveBinding();
    if (activeBinding == null) {
      throw StateError('Message Agent binding is not active.');
    }
    if (activeBinding.daemonAgentDid != daemonAgentDid ||
        activeBinding.messageAgentDid != messageAgentDid) {
      throw StateError('Message Agent binding does not match selected daemon.');
    }
    final revokeResult = await _requireIdentities()
        .revokeDaemonSubkeyAuthorization(activeBinding.userDid);
    if (revokeResult.verificationMethod !=
        activeBinding.delegatedKeyVerificationMethod) {
      throw StateError(
        'DID Document update removed a different delegated key.',
      );
    }
    final binding = await bindings.revokeBinding(bindingId: activeBinding.id);
    await _sendDaemonPayload(
      daemonAgentDid,
      messageAgentBindingDisablePayload(
        messageAgentDid: messageAgentDid,
        bindingId: binding.id,
        lifecycleAction: 'revoke',
      ),
      idempotencyKey: 'message-agent-revoke:$messageAgentDid',
    );
    return binding;
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
    bool secure = false,
  }) async {
    await _messages
        .sendPayload(
          thread: AppThreadRef.direct(daemonAgentDid),
          payload: payload,
          secure: secure,
          idempotencyKey: idempotencyKey,
        )
        .timeout(_daemonPayloadSendTimeout);
  }

  MessageAgentBindingPort _requireMessageAgentBindings() {
    final bindings = _messageAgentBindings;
    if (bindings == null) {
      throw StateError('Message Agent binding service is unavailable.');
    }
    return bindings;
  }

  IdentityCorePort _requireIdentities() {
    final identities = _identities;
    if (identities == null) {
      throw StateError('Identity service is unavailable.');
    }
    return identities;
  }

  Future<AgentSummary> _waitForMessageAgentRuntime({
    required String daemonAgentDid,
    required String userDid,
    required String appInstanceId,
  }) async {
    final expectedHandle = _messageAgentRuntimeHandle(
      userDid: userDid,
      appInstanceId: appInstanceId,
    );
    final deadline = DateTime.now().add(_messageAgentRuntimeWaitTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final runtime = await _findMessageAgentRuntime(
          daemonAgentDid: daemonAgentDid,
          expectedHandle: expectedHandle,
        );
        if (runtime != null) {
          return runtime;
        }
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(_messageAgentRuntimeWaitInterval);
    }
    throw StateError(
      'Message Agent runtime was not published by daemon.'
      '${lastError == null ? '' : ' Last error: $lastError'}',
    );
  }

  Future<AgentSummary?> _findMessageAgentRuntime({
    required String daemonAgentDid,
    required String expectedHandle,
  }) async {
    final agents = await _inventory.listAgents(includeInactive: true);
    for (final agent in agents) {
      if (!agent.isRuntime || agent.daemonAgentDid != daemonAgentDid) {
        continue;
      }
      final runtime = agent.runtime?.trim().toLowerCase();
      final handle = agent.handle?.trim().toLowerCase();
      if (runtime == appMessageHandlerRuntime && handle == expectedHandle) {
        return agent;
      }
      if (runtime == appMessageHandlerRuntime &&
          (agent.displayName ==
                  defaultMessageAgentRuntimeProvider.runtimeDisplayName ||
              handle?.startsWith(messageAgentProviderHermesHandlePrefix) ==
                  true)) {
        return agent;
      }
    }
    return null;
  }
}

String _scriptInstallCommand(
  String token, {
  required AwikiEnvironmentConfig environment,
  required String installerUrl,
  required String downloadBaseUrl,
}) {
  final env = <String>[
    'AWIKI_DAEMON_BASE_URL=${_shellQuote(environment.baseUrl)}',
    'AWIKI_DAEMON_DOWNLOAD_BASE_URLS=${_shellQuote(downloadBaseUrl)}',
  ].join(' ');
  return 'curl -fsSL ${_shellQuote(installerUrl)} | '
      '$env sh -s -- --token ${_shellQuote(token)}';
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

String _shellQuote(String value) {
  if (value.isEmpty) {
    return "''";
  }
  return "'${value.replaceAll("'", "'\"'\"'")}'";
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
  const prefix = messageAgentProviderHermesHandlePrefix;
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
