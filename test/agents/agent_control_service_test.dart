import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'createHermesRuntime sends runtime.agent.create control payload',
    () async {
      final inventory = _InventoryStub();
      final messages = _MessagesStub();
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: messages,
      );

      await service.createHermesRuntime(
        daemonAgentDid: 'did:agent:daemon',
        controllerDid: 'did:human:me',
      );

      expect(inventory.runtimeTokenDaemonDid, 'did:agent:daemon');
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(messages.lastSecure, isFalse);
      expect(messages.lastPayload?['schema'], 'awiki.agent.command.v1');
      expect(messages.lastPayload?['command'], 'runtime.agent.create');
      final args = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(args['controller_did'], 'did:human:me');
      expect(args['registration_token'], 'runtime-token');
      expect(args['runtime'], 'hermes');
    },
  );

  test('refreshDaemonStatus sends throttled query payload shape', () async {
    final messages = _MessagesStub();
    final service = DefaultAgentControlService(
      inventory: _InventoryStub(),
      messages: messages,
    );

    await service.refreshDaemonStatus('did:agent:daemon');

    expect(messages.lastPayload?['command'], 'agent.status.query');
    expect(messages.lastSecure, isFalse);
    expect(messages.lastIdempotencyKey, 'agent-status:did:agent:daemon');
  });

  test('deleteDaemon sends daemon.delete control payload', () async {
    final messages = _MessagesStub();
    final service = DefaultAgentControlService(
      inventory: _InventoryStub(),
      messages: messages,
    );

    await service.deleteDaemon('did:agent:daemon');

    expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
    expect(messages.lastSecure, isFalse);
    expect(messages.lastPayload?['command'], 'daemon.delete');
    final args = messages.lastPayload?['args'] as Map<String, Object?>;
    expect(args['daemon_agent_did'], 'did:agent:daemon');
  });

  test(
    'deleteRuntimeAgent sends runtime.agent.delete through daemon',
    () async {
      final messages = _MessagesStub();
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
      );

      await service.deleteRuntimeAgent(
        daemonAgentDid: 'did:agent:daemon',
        runtimeAgentDid: 'did:agent:runtime',
      );

      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(messages.lastSecure, isFalse);
      expect(messages.lastPayload?['command'], 'runtime.agent.delete');
      final args = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(args['runtime_agent_did'], 'did:agent:runtime');
    },
  );

  test(
    'runtime inbox query sends daemon control payload and returns request id',
    () async {
      final messages = _MessagesStub();
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
      );

      final requestId = await service.queryRuntimeInbox(
        daemonAgentDid: 'did:agent:daemon',
        runtimeAgentDid: 'did:agent:runtime',
        scope: 'direct',
      );

      expect(requestId, startsWith('cmd_runtime_inbox_'));
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(messages.lastSecure, isFalse);
      expect(messages.lastPayload?['command'], 'runtime.inbox.query');
      final args = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(args['runtime_agent_did'], 'did:agent:runtime');
      expect(args['scope'], 'direct');
      expect(
        messages.lastIdempotencyKey,
        contains('runtime-inbox:did:agent:runtime:'),
      );
    },
  );

  test('runtime inbox thread query includes thread identity', () async {
    final messages = _MessagesStub();
    final service = DefaultAgentControlService(
      inventory: _InventoryStub(),
      messages: messages,
    );

    final requestId = await service.queryRuntimeInboxThread(
      daemonAgentDid: 'did:agent:daemon',
      runtimeAgentDid: 'did:agent:runtime',
      threadId: 'dm:peer-scope:v1:bob',
      kind: 'direct',
      peerDid: 'did:human:bob',
      peerHandle: 'bob.anpclaw.com',
    );

    expect(requestId, startsWith('cmd_runtime_inbox_thread_'));
    expect(messages.lastSecure, isFalse);
    expect(messages.lastPayload?['command'], 'runtime.inbox.thread.query');
    final args = messages.lastPayload?['args'] as Map<String, Object?>;
    expect(args['thread_id'], 'dm:peer-scope:v1:bob');
    expect(args['kind'], 'direct');
    expect(args['peer_did'], 'did:human:bob');
    expect(args['peer_handle'], 'bob.anpclaw.com');
  });

  test('createDaemonInstallCommand returns token-only main command', () async {
    final service = DefaultAgentControlService(
      inventory: _InventoryStub(),
      messages: _MessagesStub(),
    );

    final command = await service.createDaemonInstallCommand(
      controllerDid: 'did:human:me',
      clientPlatform: 'macos',
    );

    expect(command.command, contains('--token daemon-token'));
    expect(command.command, isNot(contains('did:human:me')));
    expect(command.command, isNot(contains('--base-url')));
    expect(
      command.fallbackCommand,
      'awiki-deamon install --token daemon-token --base-url https://awiki.ai',
    );
    expect(command.installerUrl, 'https://awiki.ai/daemon/install.sh');
    expect(
      command.packageUrlTemplate,
      'https://awiki.ai/daemon/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
    );
  });
}

class _InventoryStub implements AgentInventoryPort {
  String? runtimeTokenDaemonDid;

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String clientPlatform,
  }) async {
    return const AgentRegistrationToken(token: 'daemon-token');
  }

  @override
  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
  }) async {
    runtimeTokenDaemonDid = daemonAgentDid;
    return const AgentRegistrationToken(token: 'runtime-token');
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
  }) {
    throw UnimplementedError();
  }
}

class _MessagesStub implements MessagingService {
  AppThreadRef? lastThread;
  Map<String, Object?>? lastPayload;
  String? lastIdempotencyKey;
  bool? lastSecure;

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
    lastSecure = secure;
    return ChatMessage(
      localId: 'msg',
      threadId: thread.stableId,
      senderDid: 'did:human:me',
      content: '',
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sent,
      payloadJson: '{}',
    );
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    throw UnimplementedError();
  }
}
