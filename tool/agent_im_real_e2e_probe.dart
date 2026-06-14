import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:crypto/crypto.dart' as crypto;
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/data/agent/user_service_agent_inventory_adapter.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';

import '../tests/e2e_test/harness/src/agent_im_config.dart';
import '../tests/e2e_test/harness/src/secret_redactor.dart';

Future<void> main(List<String> args) async {
  try {
    final result = await _run(args);
    stdout.writeln(jsonEncode(const SecretRedactor().redactJson(result)));
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    if (error.showUsage) {
      stderr.writeln(_usage);
    }
    exitCode = error.exitCode;
  } on Object catch (error) {
    stderr.writeln(_redactError(error.toString()));
    exitCode = 1;
  }
}

Future<Map<String, Object?>> _run(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    return <String, Object?>{'usage': _usageLines};
  }
  final command = args.first;
  final options = _parseOptions(args.skip(1).toList(growable: false));
  return switch (command) {
    'issue-daemon-token' => _issueDaemonToken(options),
    'bootstrap' => _bootstrap(options),
    'wait-return' => _waitReturn(options),
    'bootstrap-and-wait' => _bootstrapAndWait(options),
    _ => throw _UsageException('unknown command: $command'),
  };
}

Future<Map<String, Object?>> _issueDaemonToken(
  Map<String, String> options,
) async {
  final context = await _ProbeContext.open(options);
  try {
    final session = await context.ensureAppSession();
    final handle =
        _optional(options, 'daemon-handle') ??
        context.defaultDaemonHandle(session.handle);
    final token = await context.inventory.issueDaemonToken(
      controllerDid: session.did,
      clientPlatform: context.config.app.platform,
    );
    final tokenFile = await context.writeDaemonRegistrationToken(
      token: token.token,
      daemonHandle: handle,
    );
    return <String, Object?>{
      'command': 'issue-daemon-token',
      'runId': context.runId,
      'appHandle': context.config.accounts.appUser.handle,
      'appDid': session.did,
      'daemonHandle': handle,
      'tokenFile': tokenFile.path,
      if (token.tokenId != null) 'tokenId': token.tokenId,
      if (token.expiresAt != null)
        'expiresAt': token.expiresAt!.toUtc().toIso8601String(),
    };
  } finally {
    await context.dispose();
  }
}

Future<Map<String, Object?>> _bootstrap(Map<String, String> options) async {
  final context = await _ProbeContext.open(options);
  try {
    final session = await context.ensureAppSession();
    final daemon = await context.selectDaemon();
    final appInstanceId = context.effectiveAppInstanceId;
    final subkey = await context.ensureDaemonSubkeyPackage(
      handle: context.config.accounts.appUser.handle,
    );
    final runtimeToken = await context.bootstrapRuntimeRegistrationToken(
      controllerDid: session.did,
      daemonDid: daemon.agentDid,
      userDid: subkey.userDid,
      appInstanceId: appInstanceId,
    );
    final inventory = context.inventory;
    final messages = _RecordingRealMessagingService(
      delegate: _CoreMessagingService(
        client: context.currentClient,
        ownerDid: session.did,
      ),
    );
    final service = DefaultAgentControlService(
      inventory: inventory,
      messages: messages,
      environment: context.environment,
      agentImEnabled: true,
    );
    await service.ensureMessageAgentBootstrap(
      daemonAgentDid: daemon.agentDid,
      controllerDid: session.did,
      appInstanceId: appInstanceId,
      userSubkeyPackage: subkey,
      userHandle: session.handle,
      runtimeRegistrationToken: runtimeToken,
      runId: context.runId,
    );
    final sent = messages.lastMessage;
    return <String, Object?>{
      'command': 'bootstrap',
      'runId': context.runId,
      'appHandle': context.config.accounts.appUser.handle,
      'appDid': session.did,
      'daemonDid': daemon.agentDid,
      'daemonDisplayName': daemon.displayName,
      'appInstanceId': appInstanceId,
      'bootstrap': <String, Object?>{
        'sent': sent != null,
        'messageId': sent?.localId,
        'idempotencyKey': messages.lastIdempotencyKey,
        'payloadSchema': messages.lastPayload?['schema'],
        'payloadRunId': messages.lastPayload?['run_id'],
        'hiddenFromChat': sent == null
            ? null
            : sent.isAgentControlPayload && !sent.hasRenderableContent,
      },
    };
  } finally {
    await context.dispose();
  }
}

Future<Map<String, Object?>> _waitReturn(Map<String, String> options) async {
  final context = await _ProbeContext.open(options);
  try {
    final session = await context.ensureAppSession();
    final daemon = await context.selectDaemon();
    final sourceMessageId = _optional(options, 'source-message-id');
    final result = await context.waitForReturnPayload(
      daemonDid: daemon.agentDid,
      ownerDid: session.did,
      sourceMessageId: sourceMessageId,
    );
    return <String, Object?>{
      'command': 'wait-return',
      'runId': context.runId,
      'appHandle': context.config.accounts.appUser.handle,
      'appDid': session.did,
      'daemonDid': daemon.agentDid,
      'sourceMessageId': sourceMessageId,
      'returnEvidence': result.toJson(),
    };
  } finally {
    await context.dispose();
  }
}

Future<Map<String, Object?>> _bootstrapAndWait(
  Map<String, String> options,
) async {
  final bootstrap = await _bootstrap(options);
  final wait = await _waitReturn(options);
  return <String, Object?>{
    'command': 'bootstrap-and-wait',
    'runId': bootstrap['runId'],
    'bootstrap': bootstrap,
    'wait': wait,
  };
}

final class _ProbeContext {
  _ProbeContext({
    required this.config,
    required this.runId,
    required this.workspace,
    required this.coreInstance,
    required this.environment,
    required this.inventory,
    required void Function(String token) captureBearerToken,
  }) : _captureBearerToken = captureBearerToken;

  static Future<_ProbeContext> open(Map<String, String> options) async {
    final configFile = File(_required(options, 'config'));
    final config = AgentImDelegatedConfig.load(configFile);
    final runId = _required(options, 'run-id');
    final workspace = _resolveWorkspace(config.app.workspaceRoot);
    await Directory(workspace).create(recursive: true);
    final paths = _corePathsForWorkspace(workspace);
    await _ensureCorePathDirs(paths);
    final coreInstance = await core.AwikiImCore.open(
      config: core.AwikiImCoreConfig(
        serviceBaseUrl: config.service.baseUrl,
        didDomain: config.service.didDomain,
        userServiceEndpoint: config.service.userServiceUrl,
        messageServiceEndpoint: config.service.messageServiceUrl,
        anpServiceEndpoint: '${config.service.baseUrl}/anp-im/rpc',
        anpServiceDid: 'did:wba:${config.service.didDomain}',
      ),
      paths: paths,
    );
    await coreInstance.validatePaths();
    var bearerToken = '';
    final environment = AwikiEnvironmentConfig(
      baseUrl: config.service.baseUrl,
      userServiceUrl: config.service.userServiceUrl,
      messageServiceUrl: config.service.messageServiceUrl,
      didDomain: config.service.didDomain,
      anpServiceUrl: '${config.service.baseUrl}/anp-im/rpc',
      anpServiceDid: 'did:wba:${config.service.didDomain}',
    );
    final inventory = UserServiceAgentInventoryAdapter(
      userServiceUrl: config.service.userServiceUrl,
      bearerTokenProvider: () => bearerToken,
    );
    final context = _ProbeContext(
      config: config,
      runId: runId,
      workspace: workspace,
      coreInstance: coreInstance,
      environment: environment,
      inventory: inventory,
      captureBearerToken: (token) => bearerToken = token,
    );
    return context;
  }

  final AgentImDelegatedConfig config;
  final String runId;
  final String workspace;
  final core.AwikiImCore coreInstance;
  final AwikiEnvironmentConfig environment;
  final UserServiceAgentInventoryAdapter inventory;
  final void Function(String token) _captureBearerToken;
  core.AwikiImClient? _currentClient;

  String get effectiveAppInstanceId {
    final base = config.app.appInstanceId.trim().isEmpty
        ? 'macos-e2e-app'
        : config.app.appInstanceId.trim();
    return base;
  }

  String defaultDaemonHandle(String appHandle) {
    final normalizedHandle = _safeHandleComponent(appHandle);
    final normalizedRunId = _safeHandleComponent(runId);
    final suffix = normalizedRunId.length > 18
        ? normalizedRunId.substring(normalizedRunId.length - 18)
        : normalizedRunId;
    return 'e2e-$normalizedHandle-daemon-$suffix';
  }

  Future<File> writeDaemonRegistrationToken({
    required String token,
    required String daemonHandle,
  }) async {
    final value = token.trim();
    if (value.isEmpty) {
      throw StateError('Daemon registration token was empty.');
    }
    final file = File(
      _joinPath(<String>[
        workspace,
        'secrets',
        'daemon-registration-${_safeFileComponent(daemonHandle)}-$runId.txt',
      ]),
    );
    await file.parent.create(recursive: true);
    file.writeAsStringSync(value);
    return file;
  }

  core.AwikiImClient get currentClient {
    final client = _currentClient;
    if (client == null) {
      throw StateError('IM Core identity is not selected.');
    }
    return client;
  }

  Future<_AppSessionView> ensureAppSession() async {
    final account = config.accounts.appUser;
    final existing = await _tryExistingAppSession(account.handle);
    if (existing != null) {
      return existing;
    }
    final phone = _secretFromEnv(account.phoneEnv, 'app phone');
    final otp = _secretFromEnv(account.otpEnv, 'app OTP');
    try {
      await coreInstance.recoverHandle(
        handle: account.handle,
        phone: phone,
        otp: otp,
      );
    } on Object {
      await coreInstance.registerHandleWithPhone(
        localAlias: account.handle,
        requestedHandle: account.handle,
        phone: phone,
        otp: otp,
        profile: const core.InitialProfile(displayName: 'Agent IM E2E App'),
        makeDefault: true,
      );
    }
    return _openAppSession(account.handle);
  }

  Future<_AppSessionView?> _tryExistingAppSession(String handle) async {
    try {
      return await _openAppSession(handle);
    } on Object {
      await _currentClient?.dispose();
      _currentClient = null;
      return null;
    }
  }

  Future<_AppSessionView> _openAppSession(String handle) async {
    await _currentClient?.dispose();
    final client = await coreInstance.client(
      core.IdentitySelector.localAlias(handle),
    );
    _currentClient = client;
    final session = await client.auth.ensureSession(core.AuthScope.messaging);
    final token = session.bearerToken?.trim();
    if (token != null && token.isNotEmpty) {
      _captureBearerToken(token);
    }
    final current = await client.identity.current();
    return _AppSessionView(
      did: current.did,
      handle: current.handle ?? handle,
      bearerTokenPresent: session.bearerToken?.trim().isNotEmpty == true,
    );
  }

  Future<AgentSummary> selectDaemon() async {
    final configured = config.agent.daemonDid;
    final agents = await inventory.listAgents(includeInactive: true);
    if (configured != null && configured.trim().isNotEmpty) {
      return agents.firstWhere(
        (agent) => agent.agentDid == configured,
        orElse: () => AgentSummary(
          agentDid: configured,
          kind: AgentKind.daemon,
          displayName: 'Configured Daemon',
          activeState: 'unknown',
          latest: const AgentLatestStatus(status: 'unknown'),
        ),
      );
    }
    final daemonAgents = agents
        .where((agent) => agent.isDaemon)
        .where((agent) => agent.agentDid.trim().isNotEmpty)
        .toList(growable: false);
    if (daemonAgents.isEmpty) {
      throw StateError(
        'No daemon agent found in App user inventory. Configure agent.daemonDid or install/register a daemon for this App user.',
      );
    }
    daemonAgents.sort((a, b) {
      final active = _rankActive(a).compareTo(_rankActive(b));
      if (active != 0) {
        return active;
      }
      return a.agentDid.compareTo(b.agentDid);
    });
    return daemonAgents.first;
  }

  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage({
    required String handle,
  }) async {
    final package = await coreInstance.ensureDaemonSubkeyPackage(
      core.IdentitySelector.localAlias(handle),
    );
    return UserSubkeyPackage(
      userDid: package.userDid,
      verificationMethod: package.verificationMethod,
      publicKeyMultibase: package.publicKeyMultibase,
      privateKeyPem: package.privateKeyPem,
      keyType: package.keyType,
      keyAlgorithm: package.keyAlgorithm,
      privateKeyEncoding: package.privateKeyEncoding,
    );
  }

  Future<String> bootstrapRuntimeRegistrationToken({
    required String controllerDid,
    required String daemonDid,
    required String userDid,
    required String appInstanceId,
  }) async {
    final idempotencyKey = messageAgentBootstrapIdempotencyKey(
      userDid: userDid,
      appInstanceId: appInstanceId,
    );
    final tokenFile = File(
      _joinPath(<String>[
        workspace,
        'secrets',
        'bootstrap-runtime-token-${_safeFileComponent(idempotencyKey)}.txt',
      ]),
    );
    if (tokenFile.existsSync()) {
      final existing = tokenFile.readAsStringSync().trim();
      if (existing.isNotEmpty) {
        return existing;
      }
    }
    await tokenFile.parent.create(recursive: true);
    final token = await inventory.issueRuntimeToken(
      controllerDid: controllerDid,
      daemonAgentDid: daemonDid,
      runtime: appMessageHandlerRuntime,
      handle: _messageAgentRuntimeHandle(
        userDid: userDid,
        appInstanceId: appInstanceId,
      ),
      displayName: 'Hermes Message Agent',
    );
    final value = token.token.trim();
    if (value.isEmpty) {
      throw StateError('Runtime registration token was empty.');
    }
    tokenFile.writeAsStringSync(value);
    return value;
  }

  Future<_ReturnEvidence> waitForReturnPayload({
    required String daemonDid,
    required String ownerDid,
    String? sourceMessageId,
  }) async {
    final timeout = config.timeouts.messageProcess;
    final deadline = DateTime.now().add(timeout);
    final client = currentClient;
    var attempts = 0;
    var lastInspected = <Map<String, Object?>>[];
    while (DateTime.now().isBefore(deadline)) {
      attempts += 1;
      final page = await client.messages.history(
        core.ThreadRef.direct(daemonDid),
        limit: 80,
      );
      final inspected = <Map<String, Object?>>[];
      for (final message in page.items) {
        final payloadJson = message.body.payloadJson;
        if (payloadJson == null || payloadJson.trim().isEmpty) {
          continue;
        }
        final payload = AgentControlPayloads.decode(payloadJson);
        final schema = payload?['schema']?.toString();
        final appMessage = _chatMessageFromCoreForProbe(
          message,
          AppDirectThreadRef(daemonDid),
          sessionOwnerDid: ownerDid,
        );
        final entry = <String, Object?>{
          'messageId': message.id,
          'direction': message.direction.name,
          'sender': message.sender,
          'schema': schema,
          'isControl': appMessage.isAgentControlPayload,
          'renderable': appMessage.hasRenderableContent,
          'hiddenFromChat':
              appMessage.isAgentControlPayload &&
              !appMessage.hasRenderableContent,
          'uiProjection': appMessage.hasRenderableContent
              ? 'ordinary_chat_bubble'
              : _controlUiProjection(schema),
          'payloadRunId': payload?['run_id'],
          'payloadSourceMessageId': payload?['message_id'],
          'payloadRuntimeSourceMessageId': payload?['source_message_id'],
          'payloadSourceConversationId': payload?['source_conversation_id'],
          'syncType': payload?['sync_type'],
          'state': payload?['state'] ?? payload?['processing_status'],
        };
        inspected.add(entry);
        if (_matchesReturnPayload(
          payload,
          sourceMessageId: sourceMessageId,
          runId: runId,
        )) {
          return _ReturnEvidence(
            detected: true,
            attempts: attempts,
            matched: entry,
            inspected: inspected.take(10).toList(growable: false),
          );
        }
      }
      lastInspected = inspected.take(10).toList(growable: false);
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return _ReturnEvidence(
      detected: false,
      attempts: attempts,
      inspected: lastInspected,
    );
  }

  Future<void> dispose() async {
    try {
      await _currentClient?.dispose();
    } finally {
      _currentClient = null;
      await coreInstance.dispose();
    }
  }
}

final class _AppSessionView {
  const _AppSessionView({
    required this.did,
    required this.handle,
    required this.bearerTokenPresent,
  });

  final String did;
  final String handle;
  final bool bearerTokenPresent;
}

final class _ReturnEvidence {
  const _ReturnEvidence({
    required this.detected,
    required this.attempts,
    this.matched,
    this.inspected = const <Map<String, Object?>>[],
  });

  final bool detected;
  final int attempts;
  final Map<String, Object?>? matched;
  final List<Map<String, Object?>> inspected;

  Map<String, Object?> toJson() => <String, Object?>{
    'detected': detected,
    'attempts': attempts,
    if (matched != null) 'matched': matched,
    'inspected': inspected,
  };
}

final class _CoreMessagingService implements MessagingService {
  const _CoreMessagingService({required this.client, required this.ownerDid});

  final core.AwikiImClient client;
  final String ownerDid;

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) {
    throw UnsupportedError('App E2E probe does not download attachments.');
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) async {
    final page = await client.messages.history(
      _threadRefToCore(thread),
      limit: limit,
      cursor: cursor,
    );
    return <ChatMessage>[
      for (final message in page.items) _chatMessageFromCore(message, thread),
    ];
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    throw UnsupportedError('App E2E probe does not retry messages.');
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) {
    throw UnsupportedError('App E2E probe does not send attachments.');
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    final result = await client.messages.sendPayload(
      core.SendPayloadRequest(
        target: _messageTargetToCore(thread),
        payloadJson: jsonEncode(payload),
        security: secure
            ? core.MessageSecurityMode.secureDirect
            : core.MessageSecurityMode.defaultPlain,
        clientMessageId: idempotencyKey,
        idempotencyKey: idempotencyKey,
      ),
    );
    return _chatMessageFromCore(result.message, thread);
  }

  @override
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) {
    return sendPayload(
      thread: thread,
      payload: ChatMentionPayload.toP9Json(text: text, draftMentions: mentions),
      secure: false,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    final result = await client.messages.sendText(
      core.SendTextRequest(
        target: _messageTargetToCore(thread),
        text: content,
        security: core.MessageSecurityMode.defaultPlain,
      ),
    );
    return _chatMessageFromCore(result.message, thread);
  }

  ChatMessage _chatMessageFromCore(core.Message message, AppThreadRef thread) {
    return ChatMessage(
      localId: message.id,
      remoteId: message.id,
      threadId: thread.stableId,
      senderDid: message.sender,
      receiverDid: message.receiver,
      groupId: message.group,
      content: message.body.text ?? '',
      originalType: message.body.kind ?? message.metadata.contentType ?? 'text',
      createdAt:
          DateTime.tryParse(message.sentAt ?? message.receivedAt ?? '') ??
          DateTime.now().toUtc(),
      isMine:
          message.direction == core.MessageDirection.outgoing ||
          message.sender == ownerDid,
      sendState: MessageSendState.sent,
      payloadJson: message.body.payloadJson,
    );
  }
}

ChatMessage _chatMessageFromCoreForProbe(
  core.Message message,
  AppThreadRef thread, {
  required String sessionOwnerDid,
}) {
  return ChatMessage(
    localId: message.id,
    remoteId: message.id,
    threadId: thread.stableId,
    senderDid: message.sender,
    receiverDid: message.receiver,
    groupId: message.group,
    content: message.body.text ?? '',
    originalType: message.body.kind ?? message.metadata.contentType ?? 'text',
    createdAt:
        DateTime.tryParse(message.sentAt ?? message.receivedAt ?? '') ??
        DateTime.now().toUtc(),
    isMine:
        message.direction == core.MessageDirection.outgoing ||
        message.sender == sessionOwnerDid,
    sendState: MessageSendState.sent,
    payloadJson: message.body.payloadJson,
  );
}

core.ThreadRef _threadRefToCore(AppThreadRef thread) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => core.ThreadRef.direct(
      peerDidOrHandle,
    ),
    AppGroupThreadRef(:final groupDid) => core.ThreadRef.group(groupDid),
    AppMessageThreadRef(:final threadId) => core.ThreadRef.thread(threadId),
  };
}

core.MessageTarget _messageTargetToCore(AppThreadRef thread) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => core.MessageTarget.direct(
      peerDidOrHandle,
    ),
    AppGroupThreadRef(:final groupDid) => core.MessageTarget.group(groupDid),
    AppMessageThreadRef(:final threadId) => throw UnsupportedError(
      'Cannot send directly to thread id $threadId',
    ),
  };
}

final class _RecordingRealMessagingService implements MessagingService {
  _RecordingRealMessagingService({required MessagingService delegate})
    : _delegate = delegate;

  final MessagingService _delegate;
  ChatMessage? lastMessage;
  Map<String, Object?>? lastPayload;
  String? lastIdempotencyKey;

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) => _delegate.downloadAttachment(
    thread: thread,
    messageId: messageId,
    attachmentId: attachmentId,
    localPath: localPath,
  );

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) => _delegate.loadHistory(thread, limit: limit, cursor: cursor);

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) =>
      _delegate.retryByResendOriginalContent(failed);

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) => _delegate.sendAttachment(
    thread: thread,
    attachment: attachment,
    caption: caption,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    lastPayload = payload;
    lastIdempotencyKey = idempotencyKey;
    final message = await _delegate.sendPayload(
      thread: thread,
      payload: payload,
      secure: secure,
      idempotencyKey: idempotencyKey,
    );
    lastMessage = message;
    return message;
  }

  @override
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) async {
    lastPayload = ChatMentionPayload.toP9Json(
      text: text,
      draftMentions: mentions,
    );
    lastIdempotencyKey = idempotencyKey;
    final message = await _delegate.sendMentionText(
      thread: thread,
      text: text,
      mentions: mentions,
      idempotencyKey: idempotencyKey,
    );
    lastMessage = message;
    return message;
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) => _delegate.sendText(thread: thread, content: content);
}

String _controlUiProjection(String? schema) {
  return switch (schema) {
    AgentControlPayloads.statusSchema => 'agent_status_state',
    AgentControlPayloads.messageSyncSchema => 'agent_message_sync_state',
    AgentControlPayloads.appActionResultSchema => 'app_action_result_state',
    _ => 'agent_control_state',
  };
}

bool _matchesReturnPayload(
  Map<String, Object?>? payload, {
  required String? sourceMessageId,
  required String runId,
}) {
  if (payload == null) {
    return false;
  }
  final schema = payload['schema']?.toString();
  final encoded = jsonEncode(payload);
  final matchedSource =
      sourceMessageId != null &&
      sourceMessageId.trim().isNotEmpty &&
      encoded.contains(sourceMessageId.trim());
  final matchedRun = encoded.contains(runId);
  if (!matchedSource && !matchedRun) {
    return false;
  }
  if (schema == AgentControlPayloads.messageSyncSchema) {
    return payload['sync_type'] == 'runtime_final';
  }
  if (schema == AgentControlPayloads.appActionResultSchema) {
    return true;
  }
  if (schema == AgentControlPayloads.statusSchema) {
    final state =
        payload['state']?.toString() ??
        payload['processing_status']?.toString();
    return state == 'succeeded' || state == 'finished';
  }
  return false;
}

int _rankActive(AgentSummary agent) {
  final state = '${agent.activeState} ${agent.latest.status}'.toLowerCase();
  if (state.contains('active') || state.contains('ready')) {
    return 0;
  }
  return 1;
}

String _secretFromEnv(String envName, String description) {
  final value = Platform.environment[envName]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Missing $description environment variable: $envName');
  }
  return value;
}

String _resolveWorkspace(String value) {
  final dir = Directory(value);
  if (dir.isAbsolute) {
    return dir.path;
  }
  return Directory('${Directory.current.path}/$value').path;
}

core.AwikiImCorePaths _corePathsForWorkspace(String workspace) {
  final appSupportImCoreRoot = _joinPath(<String>[
    workspace,
    'support',
    'awiki-me',
    'im-core',
  ]);
  final identityRoot = _joinPath(<String>[appSupportImCoreRoot, 'identities']);
  return core.AwikiImCorePaths(
    identityRootDir: identityRoot,
    registryPath: _joinPath(<String>[identityRoot, 'registry.json']),
    defaultIdentityPath: _joinPath(<String>[identityRoot, 'default']),
    sqlitePath: _joinPath(<String>[
      appSupportImCoreRoot,
      'state',
      'im_core.sqlite',
    ]),
    cacheDir: _joinPath(<String>[workspace, 'cache', 'awiki-me', 'im-core']),
    tempDir: _joinPath(<String>[workspace, 'tmp', 'awiki-me', 'im-core']),
  );
}

Future<void> _ensureCorePathDirs(core.AwikiImCorePaths paths) async {
  await Future.wait(<Future<Directory>>[
    Directory(paths.identityRootDir).create(recursive: true),
    Directory(_dirname(paths.sqlitePath)).create(recursive: true),
    Directory(paths.cacheDir).create(recursive: true),
    Directory(paths.tempDir).create(recursive: true),
  ]);
}

String _joinPath(List<String> parts) {
  return parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .join('/');
}

String _safeFileComponent(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
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

String _dirname(String path) {
  final index = path.lastIndexOf('/');
  if (index <= 0) {
    return '.';
  }
  return path.substring(0, index);
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (!arg.startsWith('--')) {
      throw _UsageException('unexpected argument: $arg');
    }
    final equals = arg.indexOf('=');
    if (equals > 2) {
      options[arg.substring(2, equals)] = arg.substring(equals + 1);
      continue;
    }
    final name = arg.substring(2);
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw _UsageException('missing value for --$name');
    }
    options[name] = args[index + 1];
    index += 1;
  }
  return options;
}

String _required(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw _UsageException('missing required option --$name');
  }
  return value;
}

String? _optional(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

String _redactError(String value) => const SecretRedactor().redact(value);

const _usageLines = <String>[
  'agent_im_real_e2e_probe.dart <command> [options]',
  '',
  'Commands:',
  '  issue-daemon-token --config PATH --run-id RUN_ID [--daemon-handle HANDLE]',
  '  bootstrap --config PATH --run-id RUN_ID',
  '  wait-return --config PATH --run-id RUN_ID [--source-message-id ID]',
  '  bootstrap-and-wait --config PATH --run-id RUN_ID [--source-message-id ID]',
];

final _usage = _usageLines.join('\n');

final class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
  bool get showUsage => true;
  int get exitCode => 64;

  @override
  String toString() => message;
}
