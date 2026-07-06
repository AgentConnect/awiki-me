import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/message_agent_binding_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/message_agent_binding.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'createHermesRuntime sends runtime.agent.create control payload',
    () async {
      final inventory = _InventoryStub();
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub();
      inventory.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:message',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'hermes-msg-macos-e2e-app-7fe1fc2b5661',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: messages,
        messageAgentBindings: bindings,
        agentImEnabled: true,
      );

      await service.createHermesRuntime(
        daemonAgentDid: 'did:agent:daemon',
        controllerDid: 'did:human:me',
        handle: 'alice-hermes',
        displayName: 'Alice Hermes',
        clientRequestId: 'app_req_test',
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
      expect(args['client_request_id'], 'app_req_test');
      expect(
        messages.lastIdempotencyKey,
        'runtime-create:did:agent:daemon:app_req_test',
      );
    },
  );

  test('createRuntimeAgent sends codex metadata and command args', () async {
    final inventory = _InventoryStub();
    final messages = _MessagesStub();
    final service = DefaultAgentControlService(
      inventory: inventory,
      messages: messages,
      agentImEnabled: true,
    );

    await service.createRuntimeAgent(
      daemonAgentDid: 'did:agent:daemon',
      controllerDid: 'did:human:me',
      options: const RuntimeAgentCreateOptions(
        kind: RuntimeAgentKind.codex,
        handle: 'alice-codex',
        displayName: 'Alice Codex',
      ),
    );

    expect(inventory.runtimeTokenRuntime, 'codex');
    expect(inventory.runtimeTokenDriverId, 'codex');
    expect(inventory.runtimeTokenWorkspaceMode, 'route-root');
    expect(inventory.runtimeTokenDefaultSandbox, 'danger-full-access');
    expect(inventory.runtimeTokenDriverConfig, <String, Object?>{
      'ephemeral': false,
    });
    expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
    expect(messages.lastSecure, isFalse);
    final args = messages.lastPayload?['args'] as Map<String, Object?>;
    expect(args['runtime'], 'codex');
    expect(args['driver_id'], 'codex');
    expect(args['workspace_mode'], 'route-root');
    expect(args['default_sandbox'], 'danger-full-access');
    expect(args['driver_config'], <String, Object?>{'ephemeral': false});
    expect(args.containsKey('binary_path'), isFalse);
    expect(
      (args['driver_config'] as Map<String, Object?>).containsKey(
        'binary_path',
      ),
      isFalse,
    );
  });

  test(
    'refreshDaemonStatus sends unique query payload for each refresh',
    () async {
      final messages = _MessagesStub();
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
      );

      await service.refreshDaemonStatus('did:agent:daemon');

      expect(messages.lastPayload?['command'], 'agent.status.query');
      expect(messages.lastSecure, isFalse);
      final firstCommandId = messages.lastPayload?['command_id'];
      final firstIdempotencyKey = messages.lastIdempotencyKey;
      expect(firstCommandId, isA<String>());
      expect(
        firstIdempotencyKey,
        'agent-status:did:agent:daemon:$firstCommandId',
      );

      await Future<void>.delayed(const Duration(microseconds: 1));
      await service.refreshDaemonStatus('did:agent:daemon');

      final secondCommandId = messages.lastPayload?['command_id'];
      expect(secondCommandId, isA<String>());
      expect(secondCommandId, isNot(firstCommandId));
      expect(
        messages.lastIdempotencyKey,
        'agent-status:did:agent:daemon:$secondCommandId',
      );
    },
  );

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
    'pauseMessageAgent disables service binding and local daemon binding',
    () async {
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub();
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
        messageAgentBindings: bindings,
      );

      final binding = await service.pauseMessageAgent(
        daemonAgentDid: 'did:agent:daemon',
        messageAgentDid: 'did:agent:message',
      );

      expect(binding.status, 'disabled');
      expect(bindings.lastDisabledMessageAgentDid, 'did:agent:message');
      expect(bindings.lastRevokedMessageAgentDid, isNull);
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(
        messages.lastIdempotencyKey,
        'message-agent-disable:did:agent:message',
      );
      expect(messages.lastPayload?['command'], 'message_agent.binding.disable');
      final args = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(args['message_agent_did'], 'did:agent:message');
      expect(args['runtime_agent_did'], 'did:agent:message');
      expect(args['binding_id'], 'binding_1');
      expect(args['lifecycle_action'], 'pause');
    },
  );

  test('deleteMessageAgent pauses binding before runtime archive', () async {
    final messages = _MessagesStub();
    final bindings = _MessageAgentBindingsStub();
    final service = DefaultAgentControlService(
      inventory: _InventoryStub(),
      messages: messages,
      messageAgentBindings: bindings,
    );

    await service.deleteMessageAgent(
      daemonAgentDid: 'did:agent:daemon',
      messageAgentDid: 'did:agent:message',
    );

    expect(bindings.lastDisabledMessageAgentDid, 'did:agent:message');
    expect(messages.payloads.map((payload) => payload['command']), [
      'message_agent.binding.disable',
      'runtime.agent.delete',
    ]);
    final deleteArgs = messages.payloads.last['args'] as Map<String, Object?>;
    expect(deleteArgs['runtime_agent_did'], 'did:agent:message');
  });

  test(
    'revokeMessageAgentAuthorization updates DID Document before service binding and daemon command',
    () async {
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub();
      final identities = _IdentityCoreStub();
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
        messageAgentBindings: bindings,
        identities: identities,
      );

      final binding = await service.revokeMessageAgentAuthorization(
        daemonAgentDid: 'did:agent:daemon',
        messageAgentDid: 'did:agent:message',
      );

      expect(binding.status, 'revoked');
      expect(bindings.calls, <String>['get_active', 'revoke:binding_1']);
      expect(identities.calls, <String>['revoke:did:human:me']);
      expect(bindings.lastRevokedBindingId, 'binding_1');
      expect(bindings.lastRevokedMessageAgentDid, isNull);
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(
        messages.lastIdempotencyKey,
        'message-agent-revoke:did:agent:message',
      );
      expect(messages.lastPayload?['command'], 'message_agent.binding.disable');
      final args = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(args['message_agent_did'], 'did:agent:message');
      expect(args['runtime_agent_did'], 'did:agent:message');
      expect(args['binding_id'], 'binding_1');
      expect(args['lifecycle_action'], 'revoke');
    },
  );

  test(
    'revokeMessageAgentAuthorization fails before binding revoke when DID update fails',
    () async {
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub();
      final identities = _IdentityCoreStub()
        ..revokeError = StateError('did_document_update_failed');
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
        messageAgentBindings: bindings,
        identities: identities,
      );

      await expectLater(
        service.revokeMessageAgentAuthorization(
          daemonAgentDid: 'did:agent:daemon',
          messageAgentDid: 'did:agent:message',
        ),
        throwsStateError,
      );

      expect(bindings.calls, <String>['get_active']);
      expect(identities.calls, <String>['revoke:did:human:me']);
      expect(bindings.lastRevokedMessageAgentDid, isNull);
      expect(messages.payloads, isEmpty);
    },
  );

  test(
    'revokeMessageAgentAuthorization fails before daemon command when service still sees active delegated key',
    () async {
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub()
        ..revokeError = StateError('delegated_key_still_active');
      final identities = _IdentityCoreStub();
      final service = DefaultAgentControlService(
        inventory: _InventoryStub(),
        messages: messages,
        messageAgentBindings: bindings,
        identities: identities,
      );

      await expectLater(
        service.revokeMessageAgentAuthorization(
          daemonAgentDid: 'did:agent:daemon',
          messageAgentDid: 'did:agent:message',
        ),
        throwsStateError,
      );

      expect(bindings.calls, <String>['get_active', 'revoke:binding_1']);
      expect(identities.calls, <String>['revoke:did:human:me']);
      expect(messages.payloads, isEmpty);
    },
  );

  test(
    'ensureMessageAgentBootstrap sends encrypted bootstrap envelope without private package',
    () async {
      final inventory = _InventoryStub();
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub();
      inventory.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: 'Message Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:message',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'hermes-msg-app-1-334c10a06052',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: messages,
        messageAgentBindings: bindings,
        agentImEnabled: true,
        preferredLanguageProvider: () => 'en-US',
      );

      await service.ensureMessageAgentBootstrap(
        daemonAgentDid: 'did:agent:daemon',
        controllerDid: 'did:human:me',
        appInstanceId: 'app_1',
        userHandle: 'alice.awiki.info',
        daemonBootstrapPublicKey: _bootstrapPublicKey(),
        userSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
          privateKeyMultibase: 'zPrivate',
        ),
      );

      expect(inventory.runtimeTokenDaemonDid, 'did:agent:daemon');
      expect(inventory.runtimeTokenHandle, 'hermes-msg-app-1-334c10a06052');
      expect(inventory.runtimeTokenPreferredLanguage, 'en');
      expect(messages.lastThread?.stableId, 'dm:did:agent:daemon');
      expect(messages.lastSecure, isFalse);
      expect(
        messages.lastIdempotencyKey,
        'message-agent-bootstrap:did:human:me:app_1',
      );
      expect(messages.lastPayload?['schema'], daemonBootstrapSecureSchema);
      expect(messages.lastPayload?['recipient_daemon_did'], 'did:agent:daemon');
      expect(
        messages.lastPayload?['recipient_key_id'],
        'did:agent:daemon#key-3',
      );
      expect(messages.lastPayload?['sender_human_did'], 'did:human:me');
      expect(
        messages.lastPayload?['operation_id'],
        'message-agent-bootstrap:did:human:me:app_1',
      );
      expect(
        messages.lastPayload?['sender_ephemeral_public_key'],
        isA<String>(),
      );
      expect(messages.lastPayload?['nonce'], isA<String>());
      expect(messages.lastPayload?['ciphertext'], isA<String>());
      expect(
        messages.lastPayload?['payload_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      final aad = messages.lastPayload?['aad'] as Map<String, Object?>;
      expect(aad['binding_id'], 'app-message-agent:did:human:me:app_1');
      expect(aad['runtime_provider'], appMessageHandlerRuntimeProvider);
      expect(bindings.lastEnsuredUserDid, 'did:human:me');
      expect(bindings.lastEnsuredDaemonDid, 'did:agent:daemon');
      expect(bindings.lastEnsuredMessageAgentDid, 'did:agent:message');
      expect(
        bindings.lastEnsuredRuntimeProvider,
        appMessageHandlerRuntimeProvider,
      );
      expect(bindings.lastEnsuredRuntimeProfile, const <String, Object?>{
        'profile': appMessageHandlerRuntimeProfile,
      });
      expect(
        bindings.lastEnsuredDelegatedKeyVerificationMethod,
        'did:human:me#daemon-key-1',
      );
      final dump = messages.lastPayload.toString();
      expect(dump, isNot(contains(daemonBootstrapSchema)));
      expect(dump, isNot(contains('private_key_pem')));
      expect(dump, isNot(contains('private_key_multibase')));
      expect(dump, isNot(contains('zPrivate')));
      expect(dump, isNot(contains('runtime-token')));
    },
  );

  test('desired message agent serializes preferred language contract', () {
    final desired = const DesiredMessageAgent(
      preferredLanguage: 'en',
      ensureOnceKey: 'app-message-agent:did:human:me:app_1',
      runtimeRegistrationToken: 'runtime-token',
    ).toJson();

    expect(desired['preferred_language'], 'en');
    expect(desired['runtime_registration_token'], 'runtime-token');
    expect(desired['runtime_provider'], appMessageHandlerRuntimeProvider);
    expect(desired['runtime_profile'], appMessageHandlerRuntimeProfile);
  });

  test(
    'secure bootstrap envelope contract redacts delegated private package',
    () {
      final issuedAt = DateTime.utc(2026, 6, 19, 1);
      final envelope = DaemonSecureBootstrapEnvelope(
        recipientDaemonDid: 'did:agent:daemon',
        recipientKeyId: 'did:agent:daemon#bootstrap-key-1',
        senderHumanDid: 'did:human:me',
        operationId: 'message-agent-bootstrap:did:human:me:app_1',
        issuedAt: issuedAt,
        expiresAt: issuedAt.add(const Duration(minutes: 5)),
        nonce: 'nonce_1',
        senderEphemeralPublicKey: 'sender_key_1',
        ciphertext: 'base64:ciphertext',
        payloadSha256: 'a' * 64,
        aad: const <String, Object?>{
          'human_did': 'did:human:me',
          'daemon_agent_did': 'did:agent:daemon',
          'binding_id': 'app-message-agent:did:human:me:app_1',
        },
      ).toJson();

      expect(envelope['schema'], daemonBootstrapSecureSchema);
      expect(envelope['recipient_daemon_did'], 'did:agent:daemon');
      expect(envelope['sender_human_did'], 'did:human:me');
      expect(envelope['sender_ephemeral_public_key'], 'sender_key_1');
      expect(envelope['ciphertext'], 'base64:ciphertext');
      expect(envelope.toString(), isNot(contains('private_key_pem')));
      expect(envelope.toString(), isNot(contains('zPrivate')));
    },
  );

  test('secure bootstrap envelope rejects private fields in aad', () {
    final issuedAt = DateTime.utc(2026, 6, 19, 1);
    expect(
      () => DaemonSecureBootstrapEnvelope(
        recipientDaemonDid: 'did:agent:daemon',
        recipientKeyId: 'did:agent:daemon#bootstrap-key-1',
        senderHumanDid: 'did:human:me',
        operationId: 'message-agent-bootstrap:did:human:me:app_1',
        issuedAt: issuedAt,
        expiresAt: issuedAt.add(const Duration(minutes: 5)),
        nonce: 'nonce_1',
        senderEphemeralPublicKey: 'sender_key_1',
        ciphertext: 'base64:ciphertext',
        aad: const <String, Object?>{'private_key_pem': 'zPrivate'},
      ).toJson(),
      throwsArgumentError,
    );
  });

  test('secure bootstrap envelope rejects malformed payload hash', () {
    final issuedAt = DateTime.utc(2026, 6, 19, 1);
    expect(
      () => DaemonSecureBootstrapEnvelope(
        recipientDaemonDid: 'did:agent:daemon',
        recipientKeyId: 'did:agent:daemon#bootstrap-key-1',
        senderHumanDid: 'did:human:me',
        operationId: 'message-agent-bootstrap:did:human:me:app_1',
        issuedAt: issuedAt,
        expiresAt: issuedAt.add(const Duration(minutes: 5)),
        nonce: 'nonce_1',
        senderEphemeralPublicKey: 'sender_key_1',
        ciphertext: 'base64:ciphertext',
        payloadSha256: 'not-a-valid-hash',
        aad: const <String, Object?>{
          'binding_id': 'app-message-agent:did:human:me:app_1',
        },
      ).toJson(),
      throwsArgumentError,
    );
  });

  test(
    'ensureMessageAgentBootstrap is disabled unless Agent IM flag is enabled',
    () async {
      final inventory = _InventoryStub();
      final messages = _MessagesStub();
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: messages,
        agentImEnabled: false,
      );

      await expectLater(
        service.ensureMessageAgentBootstrap(
          daemonAgentDid: 'did:agent:daemon',
          controllerDid: 'did:human:me',
          appInstanceId: 'app_1',
          userHandle: 'alice.awiki.info',
          daemonBootstrapPublicKey: _bootstrapPublicKey(),
          userSubkeyPackage: const UserSubkeyPackage(
            userDid: 'did:human:me',
            verificationMethod: 'did:human:me#daemon-key-1',
            publicKeyMultibase: 'zPublic',
            privateKeyMultibase: 'zPrivate',
          ),
        ),
        throwsStateError,
      );

      expect(inventory.runtimeTokenDaemonDid, isNull);
      expect(messages.lastPayload, isNull);
    },
  );

  test(
    'ensureMessageAgentBootstrap keeps app instance stable while run scopes attempt idempotency',
    () async {
      final inventory = _InventoryStub();
      final messages = _MessagesStub();
      final bindings = _MessageAgentBindingsStub();
      inventory.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:message',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'hermes-msg-macos-e2e-app-7fe1fc2b5661',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: messages,
        messageAgentBindings: bindings,
        agentImEnabled: true,
      );

      Future<Map<String, Object?>> send(String runId) async {
        await service.ensureMessageAgentBootstrap(
          daemonAgentDid: 'did:agent:daemon',
          controllerDid: 'did:human:me',
          appInstanceId: 'macos-e2e-app',
          userHandle: 'alice.awiki.info',
          daemonBootstrapPublicKey: _bootstrapPublicKey(),
          userSubkeyPackage: const UserSubkeyPackage(
            userDid: 'did:human:me',
            verificationMethod: 'did:human:me#daemon-key-1',
            publicKeyMultibase: 'zPublic',
            privateKeyMultibase: 'zPrivate',
          ),
          runId: runId,
        );
        return Map<String, Object?>.from(messages.lastPayload!);
      }

      final first = await send('run-001');
      final retry = await send('run-001');
      final secondRun = await send('run-002');

      expect(first['schema'], daemonBootstrapSecureSchema);
      expect(messages.lastIdempotencyKey, endsWith(':attempt:run-002'));
      expect(first['operation_id'], retry['operation_id']);
      expect(first['operation_id'], isNot(secondRun['operation_id']));

      final aad = first['aad'] as Map<String, Object?>;
      expect(aad['binding_id'], 'app-message-agent:did:human:me:macos-e2e-app');
      expect(
        inventory.runtimeTokenHandle,
        'hermes-msg-macos-e2e-app-7fe1fc2b5661',
      );
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
      expect(args['limit'], 20);
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
    expect(args['limit'], 20);
  });

  test(
    'createDaemonInstallCommand returns env-bound command without controller DID',
    () async {
      final inventory = _InventoryStub();
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: _MessagesStub(),
      );

      final command = await service.createDaemonInstallCommand(
        controllerDid: 'did:human:me',
        controllerHandle: 'alice.anpclaw.com',
        clientPlatform: 'macos',
      );

      expect(inventory.lastDaemonTokenControllerHandle, 'alice.anpclaw.com');
      expect(command.command, contains("--token 'daemon-token'"));
      expect(command.command, isNot(contains('did:human:me')));
      expect(
        command.command,
        "curl -fsSL 'https://awiki.info/daemon/install.sh' | "
        "AWIKI_DAEMON_BASE_URL='https://awiki.info' "
        "AWIKI_DAEMON_DOWNLOAD_BASE_URLS='https://awiki.info/daemon' "
        "sh -s -- --token 'daemon-token'",
      );
      expect(
        command.fallbackCommand,
        'awiki-deamon install --token daemon-token --base-url https://awiki.info',
      );
      expect(command.installerUrl, 'https://awiki.info/daemon/install.sh');
      expect(command.cleanupUrl, 'https://awiki.info/daemon/cleanup.sh');
      expect(
        command.cleanupCommand,
        'curl -fsSL https://awiki.info/daemon/cleanup.sh | sh',
      );
      expect(
        command.packageUrlTemplate,
        'https://awiki.info/daemon/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
      );
    },
  );

  test(
    'createDaemonInstallCommand binds installer env to configured domain',
    () async {
      final inventory = _InventoryStub();
      final service = DefaultAgentControlService(
        inventory: inventory,
        messages: _MessagesStub(),
        environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
      );

      final command = await service.createDaemonInstallCommand(
        controllerDid: 'did:human:me',
        controllerHandle: 'alice.awiki.ai',
        clientPlatform: 'macos',
      );

      expect(
        command.command,
        "curl -fsSL 'https://awiki.ai/daemon/install.sh' | "
        "AWIKI_DAEMON_BASE_URL='https://awiki.ai' "
        "AWIKI_DAEMON_DOWNLOAD_BASE_URLS='https://awiki.ai/daemon' "
        "sh -s -- --token 'daemon-token'",
      );
      expect(
        command.fallbackCommand,
        'awiki-deamon install --token daemon-token --base-url https://awiki.ai',
      );
    },
  );

  test('invocation policy calls stay on inventory boundary', () async {
    final inventory = _InventoryStub();
    final service = DefaultAgentControlService(
      inventory: inventory,
      messages: _MessagesStub(),
    );
    const policy = AgentInvocationPolicy(
      activeMode: AgentInvocationPolicyMode.blacklist,
      whitelistHandles: <String>['alice@awiki.info'],
      blacklistHandles: <String>['bob@awiki.info'],
    );

    final saved = await service.updateInvocationPolicy(
      agentDid: 'did:agent:runtime',
      policy: policy,
    );
    final loaded = await service.getInvocationPolicy('did:agent:runtime');

    expect(saved, policy);
    expect(loaded, policy);
    expect(inventory.lastInvocationPolicyAgentDid, 'did:agent:runtime');
    expect(inventory.lastInvocationPolicy, policy);
  });
}

class _InventoryStub implements AgentInventoryPort {
  List<AgentSummary> agents = const <AgentSummary>[];
  String? lastDaemonTokenControllerDid;
  String? lastDaemonTokenControllerHandle;
  String? lastDaemonTokenClientPlatform;
  String? runtimeTokenDaemonDid;
  String? runtimeTokenHandle;
  String? runtimeTokenDisplayName;
  String? runtimeTokenRuntime;
  String? runtimeTokenPreferredLanguage;
  String? runtimeTokenDriverId;
  String? runtimeTokenWorkspaceMode;
  String? runtimeTokenDefaultSandbox;
  String? runtimeTokenDefaultModel;
  Map<String, Object?>? runtimeTokenDriverConfig;
  final Map<String, AgentInvocationPolicy> invocationPolicies =
      <String, AgentInvocationPolicy>{};
  String? lastInvocationPolicyAgentDid;
  AgentInvocationPolicy? lastInvocationPolicy;

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    lastDaemonTokenControllerDid = controllerDid;
    lastDaemonTokenControllerHandle = controllerHandle;
    lastDaemonTokenClientPlatform = clientPlatform;
    return const AgentRegistrationToken(token: 'daemon-token');
  }

  @override
  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
    required String handle,
    required String displayName,
    required String preferredLanguage,
    String? driverId,
    String? workspaceMode,
    String? defaultSandbox,
    String? defaultModel,
    Map<String, Object?>? driverConfig,
  }) async {
    runtimeTokenDaemonDid = daemonAgentDid;
    runtimeTokenHandle = handle;
    runtimeTokenDisplayName = displayName;
    runtimeTokenRuntime = runtime;
    runtimeTokenPreferredLanguage = preferredLanguage;
    runtimeTokenDriverId = driverId;
    runtimeTokenWorkspaceMode = workspaceMode;
    runtimeTokenDefaultSandbox = defaultSandbox;
    runtimeTokenDefaultModel = defaultModel;
    runtimeTokenDriverConfig = driverConfig;
    return const AgentRegistrationToken(token: 'runtime-token');
  }

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    return agents;
  }

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy({
    required String agentDid,
  }) async {
    return invocationPolicies[agentDid] ?? const AgentInvocationPolicy();
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    lastInvocationPolicyAgentDid = agentDid;
    lastInvocationPolicy = policy;
    invocationPolicies[agentDid] = policy;
    return policy;
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
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
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
    payloads.add(payload);
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
  Future<ChatMessage> sendConversationMentionText({
    required AppConversationReadRef conversation,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? clientMessageId,
    String? idempotencyKey,
  }) {
    return sendConversationPayload(
      conversation: conversation,
      payload: ChatMentionPayload.toP9Json(text: text, draftMentions: mentions),
      clientMessageId: clientMessageId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<ChatMessage> sendConversationPayload({
    required AppConversationReadRef conversation,
    required Map<String, Object?> payload,
    String? clientMessageId,
    String? idempotencyKey,
  }) {
    lastPayload = payload;
    payloads.add(payload);
    lastIdempotencyKey = idempotencyKey;
    return Future<ChatMessage>.value(
      ChatMessage(
        localId: clientMessageId ?? 'msg',
        remoteId: clientMessageId ?? 'msg',
        conversationId: conversation.conversationId,
        threadId: conversation.conversationId,
        senderDid: 'did:human:me',
        content: payload['text']?.toString() ?? '',
        createdAt: DateTime.now(),
        isMine: true,
        sendState: MessageSendState.sent,
        payloadJson: '{}',
      ),
    );
  }

  @override
  Future<ChatMessage> sendConversationText({
    required AppConversationReadRef conversation,
    required String content,
    String? clientMessageId,
    String? idempotencyKey,
  }) {
    throw UnimplementedError();
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
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> sendConversationAttachment({
    required AppConversationReadRef conversation,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? clientMessageId,
    String? idempotencyKey,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
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

class _MessageAgentBindingsStub implements MessageAgentBindingPort {
  final List<String> calls = <String>[];
  String? lastEnsuredUserDid;
  String? lastEnsuredDaemonDid;
  String? lastEnsuredMessageAgentDid;
  String? lastEnsuredRuntimeProvider;
  Map<String, Object?>? lastEnsuredRuntimeProfile;
  String? lastEnsuredDelegatedKeyVerificationMethod;
  String? lastDisabledBindingId;
  String? lastDisabledMessageAgentDid;
  String? lastRevokedBindingId;
  String? lastRevokedMessageAgentDid;
  Object? revokeError;

  @override
  Future<MessageAgentBinding> ensureBinding({
    required String userDid,
    required String daemonAgentDid,
    required String messageAgentDid,
    required String runtimeProvider,
    required Map<String, Object?> runtimeProfile,
    required String delegatedKeyVerificationMethod,
  }) async {
    calls.add('ensure:$messageAgentDid');
    lastEnsuredUserDid = userDid;
    lastEnsuredDaemonDid = daemonAgentDid;
    lastEnsuredMessageAgentDid = messageAgentDid;
    lastEnsuredRuntimeProvider = runtimeProvider;
    lastEnsuredRuntimeProfile = runtimeProfile;
    lastEnsuredDelegatedKeyVerificationMethod = delegatedKeyVerificationMethod;
    return _binding(messageAgentDid: messageAgentDid, status: 'active');
  }

  @override
  Future<MessageAgentBinding?> getActiveBinding() async {
    calls.add('get_active');
    return _binding(status: 'active');
  }

  @override
  Future<MessageAgentBinding> disableBinding({
    String? bindingId,
    String? messageAgentDid,
  }) async {
    calls.add('disable:${bindingId ?? messageAgentDid}');
    lastDisabledBindingId = bindingId;
    lastDisabledMessageAgentDid = messageAgentDid;
    return _binding(
      messageAgentDid: messageAgentDid ?? 'did:agent:message',
      status: 'disabled',
    );
  }

  @override
  Future<MessageAgentBinding> revokeBinding({
    String? bindingId,
    String? messageAgentDid,
  }) async {
    calls.add('revoke:${bindingId ?? messageAgentDid}');
    lastRevokedBindingId = bindingId;
    lastRevokedMessageAgentDid = messageAgentDid;
    final error = revokeError;
    if (error != null) {
      throw error;
    }
    return _binding(
      messageAgentDid: messageAgentDid ?? 'did:agent:message',
      status: 'revoked',
    );
  }

  MessageAgentBinding _binding({
    String messageAgentDid = 'did:agent:message',
    required String status,
  }) {
    return MessageAgentBinding(
      id: 'binding_1',
      userDid: 'did:human:me',
      daemonAgentDid: 'did:agent:daemon',
      messageAgentDid: messageAgentDid,
      runtimeProvider: 'hermes',
      runtimeProfile: const <String, Object?>{'profile': 'message_agent'},
      delegatedKeyVerificationMethod: 'did:human:me#daemon-key-1',
      status: status,
    );
  }
}

class _IdentityCoreStub implements IdentityCorePort {
  final List<String> calls = <String>[];
  Object? revokeError;
  String verificationMethod = 'did:human:me#daemon-key-1';

  @override
  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  ) async {
    calls.add('revoke:$identityIdOrAlias');
    final error = revokeError;
    if (error != null) {
      throw error;
    }
    return DaemonSubkeyAuthorizationRevokeResult(
      userDid: 'did:human:me',
      verificationMethod: verificationMethod,
      updated: true,
    );
  }

  @override
  Future<AppSession?> defaultIdentity() {
    throw UnimplementedError();
  }

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) {
    throw UnimplementedError();
  }

  @override
  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<AppSession>> listLocalIdentities() {
    throw UnimplementedError();
  }

  @override
  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(String identityIdOrAlias) {
    throw UnimplementedError();
  }

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) {
    throw UnimplementedError();
  }
}

DaemonBootstrapPublicKey _bootstrapPublicKey() {
  return const DaemonBootstrapPublicKey(
    keyId: 'did:agent:daemon#key-3',
    publicKeyB64u: 'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    publicKeyMultibase: 'zBootstrapPublic',
  );
}
