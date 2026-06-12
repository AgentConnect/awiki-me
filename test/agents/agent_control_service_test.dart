import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
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
        handle: 'alice-hermes',
        displayName: 'Alice Hermes',
      );

      expect(inventory.runtimeTokenDaemonDid, 'did:agent:daemon');
      expect(inventory.runtimeTokenHandle, 'alice-hermes');
      expect(inventory.runtimeTokenDisplayName, 'Alice Hermes');
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(messages.lastSecure, isFalse);
      expect(messages.lastPayload?['schema'], 'awiki.agent.command.v1');
      expect(messages.lastPayload?['command'], 'runtime.agent.create');
      final args = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(args['controller_did'], 'did:human:me');
      expect(args['registration_token'], 'runtime-token');
      expect(args['runtime'], 'hermes');
      expect(args['handle'], 'alice-hermes');
      expect(args['display_name'], 'Alice Hermes');
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
    'ensureMessageAgentBootstrap sends one ordinary bootstrap payload',
    () async {
      final inventory = _InventoryStub();
      final messages = _MessagesStub();
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: messages,
      );

      await service.ensureMessageAgentBootstrap(
        daemonAgentDid: 'did:agent:daemon',
        controllerDid: 'did:human:me',
        appInstanceId: 'app_1',
        userHandle: 'alice.awiki.ai',
        userSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
          privateKeyMultibase: 'zPrivate',
        ),
      );

      expect(inventory.runtimeTokenDaemonDid, 'did:agent:daemon');
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(messages.lastSecure, isFalse);
      expect(
        messages.lastIdempotencyKey,
        'message-agent-bootstrap:did:human:me:app_1',
      );
      expect(messages.lastPayload?['schema'], daemonBootstrapSchema);
      expect(
        messages.lastPayload?['bootstrap_id'],
        matches(RegExp(r'^boot_[0-9a-f]{24}$')),
      );
      expect(messages.lastPayload?['controller_did'], 'did:human:me');
      expect(messages.lastPayload?['app_instance_id'], 'app_1');
      expect(messages.lastPayload?['user_handle'], 'alice.awiki.ai');
      expect(
        messages.lastPayload?.containsKey('private_key_multibase'),
        isFalse,
      );
      final package =
          messages.lastPayload?['user_subkey_package'] as Map<String, Object?>;
      expect(package['schema'], userSubkeyPackageSchema);
      expect(package['verification_method'], 'did:human:me#daemon-key-1');
      expect(package['private_key_encoding'], 'pem');
      expect(package['private_key_pem'], 'zPrivate');
      expect(package.containsKey('private_key_multibase'), isFalse);
      final desired =
          messages.lastPayload?['desired_message_agent']
              as Map<String, Object?>;
      expect(desired['role'], appMessageHandlerRole);
      expect(desired['runtime'], appMessageHandlerRuntime);
      expect(
        desired['ensure_once_key'],
        'app-message-agent:did:human:me:app_1',
      );
      expect(desired['runtime_registration_token'], 'runtime-token');
      expect(desired['allowed_actions'], defaultMessageAgentActions);
    },
  );

  test('bootstrap rejects non daemon-key-1 verification method locally', () {
    expect(
      () => const UserSubkeyPackage(
        userDid: 'did:human:me',
        verificationMethod: 'did:human:me#other-key',
        publicKeyMultibase: 'zPublic',
        privateKeyMultibase: 'zPrivate',
      ).toJson(),
      throwsArgumentError,
    );
  });

  test('bootstrap rejects empty private key material locally', () {
    expect(
      () => const UserSubkeyPackage(
        userDid: 'did:human:me',
        verificationMethod: 'did:human:me#daemon-key-1',
        publicKeyMultibase: 'zPublic',
        privateKeyMultibase: ' ',
      ).toJson(),
      throwsArgumentError,
    );
  });

  test('bootstrap rejects unsupported private key encoding locally', () {
    expect(
      () => const UserSubkeyPackage(
        userDid: 'did:human:me',
        verificationMethod: 'did:human:me#daemon-key-1',
        publicKeyMultibase: 'zPublic',
        privateKeyPem: 'pemPrivate',
        privateKeyEncoding: 'multibase-ed25519-private',
      ).toJson(),
      throwsArgumentError,
    );
  });

  test('bootstrap id is stable and avoids truncation collisions', () {
    final first = messageAgentBootstrapId(
      userDid: 'did:human:${'a' * 160}',
      appInstanceId: 'app_${'x' * 160}',
    );
    final second = messageAgentBootstrapId(
      userDid: 'did:human:${'a' * 159}b',
      appInstanceId: 'app_${'x' * 160}',
    );

    expect(first, matches(RegExp(r'^boot_[0-9a-f]{24}$')));
    expect(second, matches(RegExp(r'^boot_[0-9a-f]{24}$')));
    expect(first, isNot(second));
    expect(
      first,
      messageAgentBootstrapId(
        userDid: 'did:human:${'a' * 160}',
        appInstanceId: 'app_${'x' * 160}',
      ),
    );
  });

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
  String? runtimeTokenHandle;
  String? runtimeTokenDisplayName;

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
    required String handle,
    required String displayName,
  }) async {
    runtimeTokenDaemonDid = daemonAgentDid;
    runtimeTokenHandle = handle;
    runtimeTokenDisplayName = displayName;
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
