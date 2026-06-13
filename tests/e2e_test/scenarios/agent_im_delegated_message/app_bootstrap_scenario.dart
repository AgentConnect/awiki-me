import 'dart:convert';

import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';

import '../../harness/src/secret_redactor.dart';

const agentImAppBootstrapScenarioName = 'agent-im-app-bootstrap';

final class AgentImAppBootstrapScenario {
  AgentImAppBootstrapScenario({
    AwikiEnvironmentConfig? environment,
    this.redactor = const SecretRedactor(),
  }) : environment = environment ?? AwikiEnvironmentConfig.fromEnvironment();

  final AwikiEnvironmentConfig environment;
  final SecretRedactor redactor;

  Future<AgentImAppBootstrapScenarioResult> run({
    required String runId,
    String daemonDid = 'did:agent:e2e-daemon',
    String controllerDid = 'did:wba:awiki.info:user:app:e1_app',
    String userHandle = 'awiki-e2e-agent-app',
    String appInstanceId = 'macos-e2e-app',
  }) async {
    final messages = _RecordingMessagingService();
    final inventory = _ScenarioAgentInventory();
    final service = DefaultAgentControlService(
      inventory: inventory,
      messages: messages,
      environment: environment,
    );
    final package = UserSubkeyPackage(
      userDid: controllerDid,
      verificationMethod: '$controllerDid#daemon-key-1',
      publicKeyMultibase: 'zE2ePublicDaemonKey',
      privateKeyPem: 'fixture-private-daemon-key-do-not-log',
      keyType: 'Multikey',
    );

    await service.ensureMessageAgentBootstrap(
      daemonAgentDid: daemonDid,
      controllerDid: controllerDid,
      appInstanceId: appInstanceId,
      userSubkeyPackage: package,
      userHandle: userHandle,
    );

    final sentPayload = messages.lastPayload;
    if (sentPayload == null) {
      throw StateError('Agent IM bootstrap scenario did not send a payload.');
    }
    final payloadJson = jsonEncode(sentPayload);
    final chatMessage = ChatMessage(
      localId: 'local-$runId',
      threadId: 'dm:$controllerDid:$daemonDid',
      senderDid: controllerDid,
      receiverDid: daemonDid,
      content: '',
      createdAt: DateTime.utc(2026, 6, 13),
      isMine: true,
      sendState: MessageSendState.sent,
      payloadJson: payloadJson,
    );
    final messageSyncPayload = <String, Object?>{
      'schema': AgentControlPayloads.messageSyncSchema,
      'run_id': runId,
      'message_id': 'msg-$runId',
      'runtime_agent_did': 'did:agent:e2e-hermes',
      'status': 'processed',
      'summary': 'ordinary message processed',
    };
    final actionResultPayload = <String, Object?>{
      'schema': AgentControlPayloads.appActionResultSchema,
      'action_id': 'action-$runId',
      'action': 'message.summarize_plain',
      'state': appActionStateSucceeded,
      'result': <String, Object?>{'summary': 'ordinary message processed'},
    };

    return AgentImAppBootstrapScenarioResult(
      runId: runId,
      daemonDid: daemonDid,
      controllerDid: controllerDid,
      appInstanceId: appInstanceId,
      sentThread: messages.lastThread,
      sentPayload: sentPayload,
      sentIdempotencyKey: messages.lastIdempotencyKey,
      runtimeTokenIssued: inventory.runtimeTokenIssued,
      bootstrapHiddenFromChat:
          chatMessage.isAgentControlPayload &&
          !chatMessage.hasRenderableContent,
      messageSyncDetected:
          AgentControlPayloads.decodeMessageSync(
            jsonEncode(messageSyncPayload),
          ) !=
          null,
      actionResultDetected:
          AgentControlPayloads.decodeAppActionResult(
            jsonEncode(actionResultPayload),
          ) !=
          null,
      report: _buildReport(
        runId: runId,
        daemonDid: daemonDid,
        controllerDid: controllerDid,
        appInstanceId: appInstanceId,
        thread: messages.lastThread,
        payload: sentPayload,
        idempotencyKey: messages.lastIdempotencyKey,
        bootstrapHiddenFromChat:
            chatMessage.isAgentControlPayload &&
            !chatMessage.hasRenderableContent,
        messageSyncDetected:
            AgentControlPayloads.decodeMessageSync(
              jsonEncode(messageSyncPayload),
            ) !=
            null,
        actionResultDetected:
            AgentControlPayloads.decodeAppActionResult(
              jsonEncode(actionResultPayload),
            ) !=
            null,
      ),
      redactor: redactor,
    );
  }

  Map<String, Object?> _buildReport({
    required String runId,
    required String daemonDid,
    required String controllerDid,
    required String appInstanceId,
    required AppThreadRef? thread,
    required Map<String, Object?> payload,
    required String? idempotencyKey,
    required bool bootstrapHiddenFromChat,
    required bool messageSyncDetected,
    required bool actionResultDetected,
  }) {
    return redactor.redactJson(<String, Object?>{
          'scenario': agentImAppBootstrapScenarioName,
          'runId': runId,
          'daemonDid': daemonDid,
          'controllerDid': controllerDid,
          'appInstanceId': appInstanceId,
          'sentThread': thread.toString(),
          'idempotencyKey': idempotencyKey,
          'payloadSchema': payload['schema'],
          'payload': <String, Object?>{
            'schema': payload['schema'],
            'bootstrap_id': payload['bootstrap_id'],
            'idempotency_key': payload['idempotency_key'],
            'app_instance_id': payload['app_instance_id'],
            'controller_did': payload['controller_did'],
            'user_handle': payload['user_handle'],
            'user_subkey_package': '<REDACTED_PRIVATE_PACKAGE>',
            'desired_message_agent': payload['desired_message_agent'],
            'capability_policy': payload['capability_policy'],
            'sync_policy': payload['sync_policy'],
          },
          'bootstrapHiddenFromChat': bootstrapHiddenFromChat,
          'messageSyncDetected': messageSyncDetected,
          'actionResultDetected': actionResultDetected,
        })
        as Map<String, Object?>;
  }
}

final class AgentImAppBootstrapScenarioResult {
  const AgentImAppBootstrapScenarioResult({
    required this.runId,
    required this.daemonDid,
    required this.controllerDid,
    required this.appInstanceId,
    required this.sentThread,
    required this.sentPayload,
    required this.sentIdempotencyKey,
    required this.runtimeTokenIssued,
    required this.bootstrapHiddenFromChat,
    required this.messageSyncDetected,
    required this.actionResultDetected,
    required this.report,
    required this.redactor,
  });

  final String runId;
  final String daemonDid;
  final String controllerDid;
  final String appInstanceId;
  final AppThreadRef? sentThread;
  final Map<String, Object?> sentPayload;
  final String? sentIdempotencyKey;
  final bool runtimeTokenIssued;
  final bool bootstrapHiddenFromChat;
  final bool messageSyncDetected;
  final bool actionResultDetected;
  final Map<String, Object?> report;
  final SecretRedactor redactor;

  bool get sentBootstrapPayload =>
      sentPayload['schema'] == AgentControlPayloads.daemonBootstrapSchema;

  bool get privatePackageExcludedFromReport {
    final encoded = jsonEncode(report);
    return !encoded.contains('fixture-private-daemon-key-do-not-log') &&
        !encoded.contains('private_key_pem') &&
        encoded.contains('<REDACTED_PRIVATE_PACKAGE>');
  }
}

final class _ScenarioAgentInventory implements AgentInventoryPort {
  bool runtimeTokenIssued = false;

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String clientPlatform,
  }) async {
    return const AgentRegistrationToken(token: 'fixture-daemon-token');
  }

  @override
  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
    required String handle,
    required String displayName,
  }) async {
    runtimeTokenIssued = true;
    return const AgentRegistrationToken(token: 'fixture-runtime-token');
  }

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    return const <AgentSummary>[];
  }

  @override
  Future<void> unbindAgent({required String agentDid}) async {}

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) async {
    return AgentSummary(
      agentDid: agentDid,
      kind: AgentKind.daemon,
      displayName: displayName,
      activeState: 'active',
      latest: const AgentLatestStatus(status: 'ready'),
    );
  }
}

final class _RecordingMessagingService implements MessagingService {
  AppThreadRef? lastThread;
  Map<String, Object?>? lastPayload;
  String? lastIdempotencyKey;

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) async {
    throw UnsupportedError('Attachment download is not part of this scenario.');
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) async {
    return const <ChatMessage>[];
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) async {
    throw UnsupportedError('Retry is not part of this scenario.');
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) async {
    throw UnsupportedError('Attachment send is not part of this scenario.');
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    lastThread = thread;
    lastPayload = payload;
    lastIdempotencyKey = idempotencyKey;
    return _message(thread: thread, content: '', payload: payload);
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    return _message(thread: thread, content: content);
  }

  ChatMessage _message({
    required AppThreadRef thread,
    required String content,
    Map<String, Object?>? payload,
  }) {
    return ChatMessage(
      localId: 'local-message',
      threadId: switch (thread) {
        AppDirectThreadRef(:final peerDidOrHandle) =>
          'dm:did:wba:awiki.info:user:app:e1_app:$peerDidOrHandle',
        AppGroupThreadRef(:final groupDid) => 'group:$groupDid',
        AppMessageThreadRef(:final threadId) => threadId,
      },
      senderDid: 'did:wba:awiki.info:user:app:e1_app',
      receiverDid: switch (thread) {
        AppDirectThreadRef(:final peerDidOrHandle) => peerDidOrHandle,
        _ => null,
      },
      content: content,
      createdAt: DateTime.utc(2026, 6, 13),
      isMine: true,
      sendState: MessageSendState.sent,
      payloadJson: payload == null ? null : jsonEncode(payload),
    );
  }
}
