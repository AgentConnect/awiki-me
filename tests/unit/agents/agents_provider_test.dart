import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/agent/agent_control_status_store.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/personal_agent_binding_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/agent/personal_agent_binding.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/presentation/agents/agent_ui_messages.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

const _daemonSubkeyProposal = <String, Object?>{
  'schema': userSubkeyPackageSchema,
  'user_did': 'did:human:me',
  'verification_method': 'did:human:me#daemon-key-1',
  'key_type': 'Multikey/Ed25519',
  'key_algorithm': 'Ed25519',
  'public_key_multibase': 'zPublic',
};

void main() {
  test(
    'load projects runtime Agent route before publishing inventory',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'codex',
            handle: 'runtime-codex',
            displayName: 'Codex',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final directory = _BlockingDirectoryApplicationService();
      final container = _container(control, directory: directory);
      addTearDown(container.dispose);

      final load = container.read(agentsProvider.notifier).load();
      await directory.resolveStarted.future;

      expect(container.read(agentsProvider).agents, isEmpty);
      directory.complete(
        const DirectoryPeerResolution(
          input: 'did:agent:runtime',
          did: 'did:agent:runtime',
          handle: 'runtime-codex.awiki.info',
          conversationId: 'dm:peer-scope:v1:runtime-codex',
        ),
      );
      await load;

      expect(directory.resolvedPeers, <String>['did:agent:runtime']);
      expect(
        container.read(agentsProvider).agents.single.agentDid,
        'did:agent:runtime',
      );
    },
  );

  test(
    'load restores UserService inventory without explicit selection',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'bootstrap_key_id': 'did:agent:daemon#key-3',
                'bootstrap_public_key_b64u':
                    'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                'bootstrap_key_algorithm': 'x25519',
              },
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();
      final state = container.read(agentsProvider);

      expect(state.agents.map((agent) => agent.agentDid), [
        'did:agent:daemon',
        'did:agent:runtime',
      ]);
      expect(state.selectedAgentDid, isNull);
    },
  );

  test(
    'ensureLoaded loads once and leaves explicit refresh available',
    () async {
      final control = _CountingAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      await Future.wait(<Future<void>>[
        controller.ensureLoaded(),
        controller.ensureLoaded(),
        controller.ensureLoaded(),
      ]);

      expect(control.listAgentsCalls, 1);
      await controller.ensureLoaded();
      expect(control.listAgentsCalls, 1);
      await controller.load();
      expect(control.listAgentsCalls, 2);
    },
  );

  test(
    'account-state snapshot exposes runtime create pending without reloading',
    () async {
      final control = _BlockingRuntimeCreationAgentControlService();
      final container = _container(
        control,
        session: const SessionIdentity(
          did: 'did:human:current',
          credentialName: 'identity-current',
          displayName: 'Current',
          handle: 'current.awiki.info',
          accountBinding: SessionAccountBinding(
            ownerIdentityId: 'owner-1',
            accountId: 'account-1',
            currentDid: 'did:human:current',
            protocolDeviceId: 'device-1',
            identityGeneration: '1',
            deviceAuthGeneration: '1',
          ),
        ),
      );
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      await controller.applyAccountStateSnapshots(
        inventory: ProductAgentInventorySnapshot(
          binding: const ProductAccountBinding(
            ownerIdentityId: 'owner-1',
            accountId: 'account-1',
          ),
          domainVersion: '7',
          refreshedAt: DateTime.utc(2026, 7, 31),
          agents: const <ProductAgentInventoryItem>[
            ProductAgentInventoryItem(
              agentDid: 'did:agent:daemon',
              activeState: 'active',
              payloadJson:
                  '{"agent_kind":"daemon","display_name":"Daemon",'
                  '"status":{"status":"ready"}}',
            ),
          ],
        ),
        isSessionCurrent: () => true,
      );
      final creation = controller.createRuntimeAgent(
        'did:agent:daemon',
        options: const RuntimeAgentCreateOptions(
          kind: RuntimeAgentKind.codex,
          handle: 'current-codex',
          displayName: 'Current Codex',
        ),
      );
      await pumpEventQueue();

      expect(
        container.read(agentsProvider).agents.single.agentDid,
        'did:agent:daemon',
      );
      expect(control.listAgentsCalls, 0);
      expect(control.runtimeCreateStarted, isTrue);
      expect(
        container.read(agentsProvider).pendingRuntimeCreations,
        hasLength(1),
      );

      control.completeRuntimeCreate();
      await creation;
    },
  );

  test(
    'account-state snapshot clears local create only after canonical route projection',
    () async {
      final control = FakeAgentControlService();
      final directory = _EventuallyAvailableDirectoryApplicationService(
        failuresBeforeSuccess: 1,
      );
      final container = _container(
        control,
        directory: directory,
        session: const SessionIdentity(
          did: 'did:human:current',
          credentialName: 'identity-current',
          displayName: 'Current',
          handle: 'current.awiki.info',
          accountBinding: SessionAccountBinding(
            ownerIdentityId: 'owner-1',
            accountId: 'account-1',
            currentDid: 'did:human:current',
            protocolDeviceId: 'device-1',
            identityGeneration: '1',
            deviceAuthGeneration: '1',
          ),
        ),
      );
      addTearDown(container.dispose);
      container
          .read(accountStateSyncRequestBusProvider)
          .attach((_, {force = false, minimumVersion}) async {});
      final controller = container.read(agentsProvider.notifier);

      await controller.applyAccountStateSnapshots(
        inventory: _accountAgentInventorySnapshot(includeRuntime: false),
        isSessionCurrent: () => true,
      );
      await controller.createRuntimeAgent(
        'did:agent:daemon',
        options: const RuntimeAgentCreateOptions(
          kind: RuntimeAgentKind.codex,
          handle: 'current-codex',
          displayName: 'Current Codex',
        ),
      );
      expect(
        container.read(agentsProvider).pendingRuntimeCreations,
        hasLength(1),
      );

      await controller.applyAccountStateSnapshots(
        inventory: _accountAgentInventorySnapshot(includeRuntime: true),
        isSessionCurrent: () => true,
      );

      var state = container.read(agentsProvider);
      final runtime = state.agents.singleWhere(
        (agent) => agent.agentDid == 'did:agent:runtime-current-codex',
      );
      expect(runtime.latest.status, 'ready');
      expect(directory.resolveAttempts, 1);
      expect(
        state.pendingRuntimeCreations,
        hasLength(1),
        reason: 'Inventory presence alone must not bypass route confirmation.',
      );

      await controller.applyAccountStateSnapshots(
        inventory: _accountAgentInventorySnapshot(includeRuntime: true),
        isSessionCurrent: () => true,
      );

      state = container.read(agentsProvider);
      expect(directory.resolveAttempts, 2);
      expect(state.pendingRuntimeCreations, isEmpty);
      expect(
        state.agents
            .singleWhere(
              (agent) => agent.agentDid == 'did:agent:runtime-current-codex',
            )
            .latest
            .status,
        'ready',
      );
    },
  );

  test(
    'next identity does not reuse or accept a stale inventory load',
    () async {
      final control = _BlockingFirstListAgentControlService();
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      final staleLoad = controller.load();
      await control.firstListStarted.future;

      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:human:b',
              credentialName: 'identity-b',
              displayName: 'B',
              handle: 'b.anpclaw.com',
            ),
          );
      controller.clear();
      control.nextAgents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon-b',
          kind: AgentKind.daemon,
          displayName: 'Daemon B',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      await controller.load();

      control.firstListResult.complete(const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon-a',
          kind: AgentKind.daemon,
          displayName: 'Daemon A',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'offline'),
        ),
      ]);
      await staleLoad;

      final state = container.read(agentsProvider);
      expect(control.listAgentsCalls, 2);
      expect(state.agents.map((agent) => agent.agentDid), [
        'did:agent:daemon-b',
      ]);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
    },
  );

  test('auto sync polls empty inventory until a daemon appears', () async {
    final control = _SequencedAgentControlService(<List<AgentSummary>>[
      const <AgentSummary>[],
      const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: 'Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ],
    ]);
    final container = _container(control);
    addTearDown(container.dispose);
    final controller = container.read(agentsProvider.notifier);

    await controller.load();
    expect(container.read(agentsProvider).agents, isEmpty);

    controller.startInventoryAutoSync();
    expect(container.read(agentsProvider).isAutoSyncingInventory, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    final state = container.read(agentsProvider);
    expect(control.listAgentsCalls, 2);
    expect(state.agents.map((agent) => agent.agentDid), ['did:agent:daemon']);
    expect(state.isAutoSyncingInventory, isFalse);
  });

  test(
    'foreground Agent page observation reconciles Inventory and pauses in background',
    () async {
      const daemon = AgentSummary(
        agentDid: 'did:agent:daemon',
        kind: AgentKind.daemon,
        displayName: 'Daemon 1',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      const runtime = AgentSummary(
        agentDid: 'did:agent:runtime',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:agent:daemon',
        runtime: 'claude-code',
        displayName: 'Claude',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      final control = _ControlledInventoryAgentControlService();
      final container = _container(
        control,
        controllerFactory: (ref) => AgentsController(
          ref,
          inventoryObservationInterval: const Duration(milliseconds: 10),
        ),
      );
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      final initialLoad = controller.load();
      await control.waitForListCalls(1);
      control.completeListCall(1, const <AgentSummary>[daemon]);
      await initialLoad;
      controller.startInventoryObservation();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await control.waitForListCalls(2);
      control.completeListCall(2, const <AgentSummary>[daemon, runtime]);
      await pumpEventQueue();
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        contains(runtime.agentDid),
      );

      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      final callsWhenPaused = control.listAgentsCalls;
      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(control.listAgentsCalls, callsWhenPaused);
    },
  );

  test(
    'auto sync keeps empty state clean when a background poll fails',
    () async {
      final control = _SequencedAgentControlService(<List<AgentSummary>>[
        const <AgentSummary>[],
        const <AgentSummary>[],
      ])..errorsByCall[2] = StateError('temporary network failure');
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      await controller.load();
      controller.startInventoryAutoSync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(agentsProvider);
      expect(control.listAgentsCalls, 2);
      expect(state.agents, isEmpty);
      expect(state.error, isNull);
      expect(state.isAutoSyncingInventory, isTrue);
      controller.stopInventoryAutoSync();
    },
  );

  test('load applies stable daemon and runtime ordering', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:runtime-b-2',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon-b',
          runtime: 'hermes',
          displayName: 'Beta Runtime',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:daemon-b',
          kind: AgentKind.daemon,
          displayName: 'B 代理',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'registering'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime-a-2',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon-a',
          runtime: 'hermes',
          displayName: 'Beta Runtime',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime-a-1',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon-a',
          runtime: 'hermes',
          displayName: 'Alpha Runtime',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:daemon-a',
          kind: AgentKind.daemon,
          displayName: 'A 代理',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'registering'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);

    await container.read(agentsProvider.notifier).load();

    expect(
      container.read(agentsProvider).agents.map((agent) => agent.agentDid),
      [
        'did:agent:daemon-a',
        'did:agent:daemon-b',
        'did:agent:runtime-a-1',
        'did:agent:runtime-a-2',
        'did:agent:runtime-b-2',
      ],
    );
  });

  test('load maps authorization failures to a friendly agent error', () async {
    final control = _FailingAgentControlService(
      Exception(
        'AwikiOnboardingUtilityError http 401: '
        '{"jsonrpc":"2.0","error":{"message":"Missing or invalid Authorization header"}}',
      ),
    );
    final container = _container(control);
    addTearDown(container.dispose);

    await container.read(agentsProvider.notifier).load();
    final state = container.read(agentsProvider);

    expect(state.error, AgentUiMessageCodes.sessionExpired);
    expect(state.error, isNot(contains('Authorization header')));
    expect(state.error, isNot(contains('jsonrpc')));
  });

  test('load maps network failures to a friendly agent error', () async {
    final control = _FailingAgentControlService(
      Exception('SocketException: Connection refused'),
    );
    final container = _container(control);
    addTearDown(container.dispose);

    await container.read(agentsProvider.notifier).load();

    expect(
      container.read(agentsProvider).error,
      AgentUiMessageCodes.networkPreserved,
    );
  });

  test(
    'load maps controller handle mismatch to a friendly agent error',
    () async {
      final control = _FailingAgentControlService(
        const AwikiOnboardingUtilityError(
          rpcCode: -32001,
          message: 'controller_handle must match current controller scope',
          data: <String, Object?>{'reason': 'controller_handle_mismatch'},
        ),
      );
      final container = _container(control);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();

      expect(
        container.read(agentsProvider).error,
        AgentUiMessageCodes.controllerHandleMismatch,
      );
    },
  );

  test(
    'load maps missing controller handle to a friendly agent error',
    () async {
      final control = _FailingAgentControlService(
        const AwikiOnboardingUtilityError(
          rpcCode: -32001,
          message:
              'controller_handle is required for daemon registration tokens',
          data: <String, Object?>{'reason': 'controller_handle_required'},
        ),
      );
      final container = _container(control);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();

      expect(
        container.read(agentsProvider).error,
        AgentUiMessageCodes.handleUnavailable,
      );
    },
  );

  test(
    'createDaemonInstallCommand binds command to current session handle',
    () async {
      final control = FakeAgentControlService();
      final container = _container(
        control,
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'Alice.Anpclaw.com',
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .createDaemonInstallCommand();
      final state = container.read(agentsProvider);

      expect(state.installCommand, control.nextInstallCommand);
      expect(control.lastInstallControllerDid, 'did:human:me');
      expect(control.lastInstallControllerHandle, 'alice.anpclaw.com');
    },
  );

  test(
    'createDaemonInstallCommand requires a current session handle',
    () async {
      final control = FakeAgentControlService();
      final container = _container(
        control,
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .createDaemonInstallCommand();
      final state = container.read(agentsProvider);

      expect(control.lastInstallCommand, isNull);
      expect(state.installCommand, isNull);
      expect(state.error, AgentUiMessageCodes.handleUnavailable);
    },
  );

  test(
    'stale agent action cannot restore state after identity switch',
    () async {
      final control = _BlockingInstallCommandAgentControlService();
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      final staleAction = controller.createDaemonInstallCommand();
      await control.installCommandStarted.future;

      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:human:b',
              credentialName: 'identity-b',
              displayName: 'B',
              handle: 'b.anpclaw.com',
            ),
          );
      controller.clear();
      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon-b',
          kind: AgentKind.daemon,
          displayName: 'Daemon B',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      await controller.load();

      control.installCommandResult.complete(control.nextInstallCommand);
      await staleAction;

      final state = container.read(agentsProvider);
      expect(state.agents.map((agent) => agent.agentDid), [
        'did:agent:daemon-b',
      ]);
      expect(state.installCommand, isNull);
      expect(state.pendingActionKeys, isEmpty);
      expect(state.isAutoSyncingInventory, isFalse);
      expect(state.error, isNull);
    },
  );

  test('load ignores local cache read and write failures', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'registering'),
        ),
      ];
    final container = _container(
      control,
      localStore: _FailingAgentStateStore(),
    );
    addTearDown(container.dispose);

    await container.read(agentsProvider.notifier).load();
    final state = container.read(agentsProvider);

    expect(state.error, isNull);
    expect(state.isLoading, isFalse);
    expect(state.agents.map((agent) => agent.agentDid), ['did:agent:daemon']);
  });

  test(
    'same-DID new epoch cache write waits for the raw old write and wins',
    () async {
      const session = SessionIdentity(
        did: 'did:human:me',
        credentialName: 'default',
        displayName: 'Me',
        handle: 'me.anpclaw.com',
      );
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:epoch-1',
            kind: AgentKind.daemon,
            displayName: 'Epoch 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final localStore = _BlockingFirstAgentCacheWriteStore();
      final container = _container(
        control,
        localStore: localStore,
        statusStore: const _StaticAgentControlStatusStore(),
        session: session,
      );
      addTearDown(() {
        localStore.releaseFirstWrite();
        container.dispose();
      });
      final controller = container.read(agentsProvider.notifier);

      final epoch1Load = controller.load();
      await localStore.firstWriteStarted.future;

      container.read(sessionProvider.notifier).activateSession(session);
      controller.clear();
      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:epoch-2',
          kind: AgentKind.daemon,
          displayName: 'Epoch 2',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      final epoch2Load = controller.load();

      await Future.wait(<Future<void>>[
        epoch1Load,
        epoch2Load,
      ]).timeout(const Duration(seconds: 4));
      expect(localStore.saveCalls, 1);
      expect(localStore.savedAgentDids, isEmpty);

      localStore.releaseFirstWrite();
      await localStore.secondWriteCompleted.future.timeout(
        const Duration(seconds: 1),
      );

      expect(localStore.savedAgentDids, <String>[
        'did:agent:epoch-1',
        'did:agent:epoch-2',
      ]);
      expect(
        localStore.agentStates.values.map((item) => item.agentDid),
        <String>['did:agent:epoch-2'],
      );
    },
  );

  test(
    'stale queued control cache write is skipped before the next epoch write',
    () async {
      const session = SessionIdentity(
        did: 'did:human:me',
        credentialName: 'default',
        displayName: 'Me',
        handle: 'me.anpclaw.com',
      );
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:epoch-1',
            kind: AgentKind.daemon,
            displayName: 'Epoch 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final localStore = _BlockingFirstAgentCacheWriteStore();
      final container = _container(
        control,
        localStore: localStore,
        statusStore: const _StaticAgentControlStatusStore(),
        session: session,
      );
      addTearDown(() {
        localStore.releaseFirstWrite();
        container.dispose();
      });
      final controller = container.read(agentsProvider.notifier);

      final epoch1Load = controller.load();
      await localStore.firstWriteStarted.future;
      controller.applyControlPayload(<String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'event_id': 'evt_epoch_1_queued',
        'sent_at': '2026-07-24T08:00:00Z',
        'status_scope': 'snapshot',
        'daemon_agent_did': 'did:agent:epoch-1',
        'daemon': <String, Object?>{
          'agent_did': 'did:agent:epoch-1',
          'status': 'ready',
        },
        'runtimes': <Object?>[
          <String, Object?>{
            'agent_did': 'did:agent:stale-runtime',
            'daemon_agent_did': 'did:agent:epoch-1',
            'runtime': 'hermes',
            'display_name': 'Stale Runtime',
            'status': 'ready',
          },
        ],
      });
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        contains('did:agent:stale-runtime'),
      );

      container.read(sessionProvider.notifier).activateSession(session);
      controller.clear();
      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:epoch-2',
          kind: AgentKind.daemon,
          displayName: 'Epoch 2',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      final epoch2Load = controller.load();
      localStore.releaseFirstWrite();

      await Future.wait(<Future<void>>[
        epoch1Load,
        epoch2Load,
      ]).timeout(const Duration(seconds: 2));

      expect(localStore.savedAgentDids, <String>[
        'did:agent:epoch-1',
        'did:agent:epoch-2',
      ]);
      expect(
        localStore.savedAgentDids,
        isNot(contains('did:agent:stale-runtime')),
      );
      expect(
        localStore.agentStates.values.map((item) => item.agentDid),
        <String>['did:agent:epoch-2'],
      );
    },
  );

  test(
    'load keeps inventory visible when automatic daemon refresh fails',
    () async {
      final control =
          _FailingRefreshAgentControlService(
              Exception('direct E2EE prekey bundle is not available'),
            )
            ..agents = const <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:daemon',
                kind: AgentKind.daemon,
                displayName: '代理 1',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ];
      final container = _container(control);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();
      final state = container.read(agentsProvider);

      expect(state.agents.map((agent) => agent.agentDid), ['did:agent:daemon']);
      expect(state.selectedAgentDid, isNull);
      expect(state.error, isNull);
      expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
    },
  );

  test(
    'status payload creates runtime and preserves daemon/runtime split',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'bootstrap_key_id': 'did:agent:daemon#key-3',
                'bootstrap_public_key_b64u':
                    'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                'bootstrap_key_algorithm': 'x25519',
              },
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();
      await container
          .read(agentsProvider.notifier)
          .refreshDaemonStatus('did:agent:daemon');

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'daemon',
          'command_id': control.lastRefreshedDaemonCommandId,
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
            'version': '0.3.0',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'display_name': 'Hermes',
              'status': 'needs_config',
              'needs_config': true,
            },
          ],
        },
      );

      final state = container.read(agentsProvider);
      expect(state.pendingStatusQueryAtByDaemon, contains('did:agent:daemon'));
      expect(state.agents.map((agent) => agent.agentDid), [
        'did:agent:daemon',
        'did:agent:runtime',
      ]);
      expect(state.agents.first.isDaemon, isTrue);
      final runtime = state.agents.last;
      expect(runtime.isRuntime, isTrue);
      expect(runtime.daemonAgentDid, 'did:agent:daemon');
      expect(runtime.displayName, 'Unnamed agent');
      expect(runtime.latest.status, 'needs_config');
      expect(runtime.latest.needsConfig, isTrue);
      await Future<void>.delayed(agentStatusRefreshMinimumIndicatorDuration);
      expect(
        container.read(agentsProvider).pendingStatusQueryAtByDaemon,
        isEmpty,
      );
    },
  );

  test(
    'status payload preserves generic CLI runtime card diagnostics',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime-codex',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'codex',
              'display_name': 'Codex',
              'status': 'ready',
              'diagnostics_summary': genericCliRuntimeCardDiagnostics(
                lifecycleState: 'needs_setup',
                setupReady: false,
                setupState: 'binary_missing',
                nextAction: 'setup_required',
              ),
            },
          ],
        },
      );

      final runtime = container
          .read(agentsProvider)
          .agents
          .singleWhere((agent) => agent.agentDid == 'did:agent:runtime-codex');
      final runtimeCard = runtime.latest.runtimeCard;
      expect(runtimeCard, isNotNull);
      expect(runtimeCard?.runtimeFamily, 'generic-cli');
      expect(runtimeCard?.driverId, 'codex');
      expect(runtimeCard?.lifecycleState, 'needs_setup');
      expect(runtimeCard?.setupState, 'binary_missing');
      expect(runtimeCard?.nextAction, 'setup_required');
    },
  );

  test('refresh failure records daemon-scoped status error only', () async {
    final control =
        _FailingRefreshAgentControlService(StateError('message send failed'))
          ..agents = const <AgentSummary>[
            AgentSummary(
              agentDid: 'did:agent:daemon',
              kind: AgentKind.daemon,
              displayName: '代理 1',
              activeState: 'active',
              latest: AgentLatestStatus(status: 'ready'),
            ),
          ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    await container
        .read(agentsProvider.notifier)
        .refreshDaemonStatus('did:agent:daemon');

    final state = container.read(agentsProvider);
    expect(state.error, isNull);
    expect(state.pendingStatusQueryAtByDaemon, isEmpty);
    expect(
      state.statusQueryErrors['did:agent:daemon'],
      AgentUiMessageCodes.statusRefreshFailed,
    );
    expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
  });

  test('runtime create result adds runtime agent under daemon', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime',
        'daemon_agent_did': 'did:agent:daemon',
        'state': 'ready',
        'result': <String, Object?>{
          'command': 'runtime.agent.create',
          'runtime_agent_did': 'did:agent:runtime-new',
          'daemon_agent_did': 'did:agent:daemon',
          'runtime': 'hermes',
          'display_name': 'Hermes Runtime',
        },
      },
    );

    final runtime = container
        .read(agentsProvider)
        .agents
        .singleWhere((agent) => agent.agentDid == 'did:agent:runtime-new');
    expect(runtime.kind, AgentKind.runtime);
    expect(runtime.daemonAgentDid, 'did:agent:daemon');
    expect(runtime.displayName, 'Hermes Runtime');
    expect(runtime.latest.status, 'ready');
  });

  test(
    'createHermesRuntime keeps pending until authoritative route projection',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .createHermesRuntime(
            'did:agent:daemon',
            handle: 'alice-hermes',
            displayName: 'Alice Hermes',
          );

      final pending = container
          .read(agentsProvider)
          .pendingRuntimeCreations
          .single;
      expect(pending.daemonAgentDid, 'did:agent:daemon');
      expect(pending.handle, 'alice-hermes');
      expect(pending.displayName, 'Alice Hermes');
      expect(pending.state, PendingRuntimeCreationState.waitingForStatus);
      expect(control.lastRuntimeCreateDaemonDid, 'did:agent:daemon');
      expect(control.lastRuntimeCreateControllerDid, 'did:human:me');
      expect(control.lastRuntimeCreateClientRequestId, pending.requestId);

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime',
          'daemon_agent_did': 'did:agent:daemon',
          'state': 'ready',
          'result': <String, Object?>{
            'command': 'runtime.agent.create',
            'client_request_id': pending.requestId,
            'runtime_agent_did': 'did:agent:runtime-new',
            'daemon_agent_did': 'did:agent:daemon',
            'runtime': 'hermes',
            'handle': 'alice-hermes',
            'display_name': 'Alice Hermes',
          },
        },
      );

      final state = container.read(agentsProvider);
      expect(state.pendingRuntimeCreations, hasLength(1));
      final runtime = state.agents.singleWhere(
        (agent) => agent.agentDid == 'did:agent:runtime-new',
      );
      expect(runtime.displayName, 'Alice Hermes');
      expect(runtime.handle, 'alice-hermes');
      expect(runtime.daemonAgentDid, 'did:agent:daemon');
    },
  );

  test(
    'committed create event survives stale inventory and reconciles without manual refresh',
    () async {
      const daemon = AgentSummary(
        agentDid: 'did:agent:daemon',
        kind: AgentKind.daemon,
        handle: 'awiki-daemon-test',
        displayName: '代理 1',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      const runtime = AgentSummary(
        agentDid: 'did:agent:runtime-new',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:agent:daemon',
        runtime: 'hermes',
        handle: 'alice-hermes',
        displayName: 'Alice Hermes',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      final control = _ControlledInventoryAgentControlService();
      final directory = _EventuallyAvailableDirectoryApplicationService(
        failuresBeforeSuccess: 0,
      );
      final container = _container(control, directory: directory);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      final initialLoad = controller.load();
      await control.waitForListCalls(1);
      control.completeListCall(1, const <AgentSummary>[daemon]);
      await initialLoad;

      await controller.createHermesRuntime(
        daemon.agentDid,
        handle: runtime.handle!,
        displayName: runtime.displayName,
      );
      expect(
        control.listAgentsCalls,
        1,
        reason: 'sending create must not trigger a blind inventory reload',
      );
      final pending = container
          .read(agentsProvider)
          .pendingRuntimeCreations
          .single;

      final staleLoad = controller.load(showLoading: false);
      await control.waitForListCalls(2);
      controller.applyCommittedControlEvent(
        AgentControlEvent(
          messageId: 'msg-create-1',
          daemonAgentDid: daemon.agentDid,
          isReplay: false,
          payload: <String, Object?>{
            'schema': AgentControlPayloads.statusSchema,
            'event_id': 'evt-create-1',
            'status_scope': 'runtime',
            'daemon_agent_did': daemon.agentDid,
            'state': 'ready',
            'result': <String, Object?>{
              'command': 'runtime.agent.create',
              'client_request_id': pending.requestId,
              'runtime_agent_did': runtime.agentDid,
              'daemon_agent_did': daemon.agentDid,
              'runtime': runtime.runtime,
              'handle': runtime.handle,
              'display_name': runtime.displayName,
            },
          },
        ),
      );
      await pumpEventQueue();

      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        contains(runtime.agentDid),
      );
      expect(
        container.read(agentsProvider).pendingRuntimeCreations,
        hasLength(1),
      );

      control.completeListCall(2, const <AgentSummary>[daemon]);
      await staleLoad;
      await control.waitForListCalls(3);
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        contains(runtime.agentDid),
        reason: 'a pre-ACK inventory response must not erase the projection',
      );

      control.completeListCall(3, const <AgentSummary>[daemon, runtime]);
      await pumpEventQueue();
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        containsAll(<String>[daemon.agentDid, runtime.agentDid]),
      );
      expect(container.read(agentsProvider).pendingRuntimeCreations, isEmpty);
    },
  );

  test(
    'accepted local create reconciles authoritative inventory without a control event',
    () async {
      const daemon = AgentSummary(
        agentDid: 'did:agent:daemon',
        kind: AgentKind.daemon,
        handle: 'awiki-daemon-test',
        displayName: '代理 1',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      const runtime = AgentSummary(
        agentDid: 'did:agent:runtime-new',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:agent:daemon',
        runtime: 'codex',
        handle: 'alice-codex',
        displayName: 'Alice Codex',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      final control = _ControlledInventoryAgentControlService();
      final directory = _EventuallyAvailableDirectoryApplicationService();
      final container = _container(control, directory: directory);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      final initialLoad = controller.load();
      await control.waitForListCalls(1);
      control.completeListCall(1, const <AgentSummary>[daemon]);
      await initialLoad;

      await controller.createRuntimeAgent(
        daemon.agentDid,
        options: const RuntimeAgentCreateOptions(
          kind: RuntimeAgentKind.codex,
          handle: 'alice-codex',
          displayName: 'Alice Codex',
        ),
      );
      await control.waitForListCalls(2);
      expect(
        container.read(agentsProvider).pendingRuntimeCreations,
        hasLength(1),
      );

      control.completeListCall(2, const <AgentSummary>[daemon, runtime]);
      await pumpEventQueue();

      expect(directory.resolveAttempts, 1);
      expect(
        container.read(agentsProvider).pendingRuntimeCreations,
        hasLength(1),
        reason:
            'inventory presence alone must not complete creation before the '
            'canonical Direct route is projected',
      );
      await Future<void>.delayed(
        agentRuntimeCreationReconcileInterval +
            const Duration(milliseconds: 100),
      );
      await control.waitForListCalls(3);
      control.completeListCall(3, const <AgentSummary>[daemon, runtime]);
      await pumpEventQueue();

      expect(directory.resolveAttempts, 2);
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        containsAll(<String>[daemon.agentDid, runtime.agentDid]),
      );
      expect(container.read(agentsProvider).pendingRuntimeCreations, isEmpty);
    },
  );

  test(
    'committed create replay cannot complete a different pending intent',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);
      await controller.load();
      await controller.createHermesRuntime(
        'did:agent:daemon',
        handle: 'alice-hermes',
        displayName: 'Alice Hermes',
      );
      final pending = container
          .read(agentsProvider)
          .pendingRuntimeCreations
          .single;

      controller.applyCommittedControlEvent(
        AgentControlEvent(
          messageId: 'msg-stale-create',
          daemonAgentDid: 'did:agent:daemon',
          isReplay: true,
          payload: <String, Object?>{
            'schema': AgentControlPayloads.statusSchema,
            'event_id': 'evt-stale-create',
            'status_scope': 'runtime',
            'daemon_agent_did': 'did:agent:daemon',
            'state': 'ready',
            'result': <String, Object?>{
              'command': 'runtime.agent.create',
              'client_request_id': pending.requestId,
              'runtime_agent_did': 'did:agent:runtime-other',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'handle': 'different-handle',
              'display_name': 'Different Runtime',
            },
          },
        ),
      );
      await pumpEventQueue();

      expect(
        container.read(agentsProvider).pendingRuntimeCreations.single.requestId,
        pending.requestId,
      );
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        isNot(contains('did:agent:runtime-other')),
      );
    },
  );

  test(
    'committed create replay invalidates remote inventory on another device',
    () async {
      const daemon = AgentSummary(
        agentDid: 'did:agent:daemon',
        kind: AgentKind.daemon,
        handle: 'awiki-daemon-test',
        displayName: '代理 1',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      const runtime = AgentSummary(
        agentDid: 'did:agent:runtime-remote',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:agent:daemon',
        runtime: 'claude-code',
        handle: 'remote-claude',
        displayName: 'Remote Claude',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      );
      final control = _ControlledInventoryAgentControlService();
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      final initialLoad = controller.load();
      await control.waitForListCalls(1);
      control.completeListCall(1, const <AgentSummary>[daemon]);
      await initialLoad;

      controller.applyCommittedControlEvent(
        AgentControlEvent(
          messageId: 'msg-remote-create',
          daemonAgentDid: daemon.agentDid,
          isReplay: true,
          payload: const <String, Object?>{
            'schema': AgentControlPayloads.statusSchema,
            'event_id': 'evt-remote-create',
            'status_scope': 'runtime',
            'daemon_agent_did': 'did:agent:daemon',
            'state': 'ready',
            'result': <String, Object?>{
              'command': 'runtime.agent.create',
              'client_request_id': 'request-from-another-device',
              'runtime_agent_did': 'did:agent:runtime-remote',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'claude-code',
              'handle': 'remote-claude',
              'display_name': 'Remote Claude',
            },
          },
        ),
      );

      await control.waitForListCalls(2);
      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        isNot(contains(runtime.agentDid)),
        reason: 'a replay is an invalidation, not an optimistic projection',
      );
      control.completeListCall(2, const <AgentSummary>[daemon, runtime]);
      await pumpEventQueue();

      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        containsAll(<String>[daemon.agentDid, runtime.agentDid]),
      );
      expect(container.read(agentsProvider).pendingRuntimeCreations, isEmpty);
    },
  );

  test(
    'daemon status lookup cannot create an Agent absent from Inventory',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      const statusStore = _StaticAgentControlStatusStore(
        daemonStatusPayload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'daemon',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime-status-only',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'codex',
              'status': 'ready',
            },
          ],
        },
      );
      final container = _container(control, statusStore: statusStore);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);
      await controller.load();

      await controller.refreshDaemonStatus('did:agent:daemon');
      await Future<void>.delayed(
        agentStatusQueryPollInterval + const Duration(milliseconds: 100),
      );

      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        ['did:agent:daemon'],
      );
    },
  );

  test(
    'loads and saves invocation policy through agent control service',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ]
        ..invocationPolicies['did:agent:runtime'] = const AgentInvocationPolicy(
          whitelistHandles: <String>['alice@awiki.info'],
        );
      final container = _container(control);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();
      await container
          .read(agentsProvider.notifier)
          .loadInvocationPolicy('did:agent:runtime');

      expect(
        container
            .read(agentsProvider)
            .invocationPolicies['did:agent:runtime']
            ?.whitelistHandles,
        <String>['alice@awiki.info'],
      );

      const updated = AgentInvocationPolicy(
        activeMode: AgentInvocationPolicyMode.blacklist,
        whitelistHandles: <String>['alice@awiki.info'],
        blacklistHandles: <String>['bob@awiki.info'],
      );
      await container
          .read(agentsProvider.notifier)
          .saveInvocationPolicy('did:agent:runtime', updated);

      expect(control.lastInvocationPolicyAgentDid, 'did:agent:runtime');
      expect(control.lastInvocationPolicy, updated);
      expect(
        container.read(agentsProvider).invocationPolicies['did:agent:runtime'],
        updated,
      );
      expect(container.read(agentsProvider).savingInvocationPolicies, isEmpty);
      expect(container.read(agentsProvider).invocationPolicyErrors, isEmpty);
    },
  );

  test(
    'stale invocation policy result cannot overwrite the next identity',
    () async {
      final control = _BlockingInvocationPolicyAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:runtime-a',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon-a',
            runtime: 'hermes',
            displayName: 'Runtime A',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);

      await controller.load();
      final staleLoad = controller.loadInvocationPolicy('did:agent:runtime-a');
      await control.policyRequestStarted.future;

      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:human:b',
              credentialName: 'identity-b',
              displayName: 'B',
              handle: 'b.anpclaw.com',
            ),
          );
      controller.clear();
      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon-b',
          kind: AgentKind.daemon,
          displayName: 'Daemon B',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
      await controller.load();

      control.policyResult.complete(
        const AgentInvocationPolicy(
          whitelistHandles: <String>['identity-a@awiki.info'],
        ),
      );
      await staleLoad;

      final state = container.read(agentsProvider);
      expect(state.agents.map((agent) => agent.agentDid), [
        'did:agent:daemon-b',
      ]);
      expect(state.invocationPolicies, isEmpty);
      expect(state.loadingInvocationPolicies, isEmpty);
      expect(state.invocationPolicyErrors, isEmpty);
    },
  );

  test('stale status poll payload cannot mutate the next identity', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon-a',
          kind: AgentKind.daemon,
          displayName: 'Daemon A',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final statusStore = _BlockingDaemonStatusLookupStore();
    final container = _container(control, statusStore: statusStore);
    addTearDown(container.dispose);
    final controller = container.read(agentsProvider.notifier);

    await controller.load();
    await controller.refreshDaemonStatus('did:agent:daemon-a');
    await statusStore.lookupStarted.future.timeout(const Duration(seconds: 2));

    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:human:b',
            credentialName: 'identity-b',
            displayName: 'B',
            handle: 'b.anpclaw.com',
          ),
        );
    controller.clear();
    control.agents = const <AgentSummary>[
      AgentSummary(
        agentDid: 'did:agent:daemon-b',
        kind: AgentKind.daemon,
        displayName: 'Daemon B',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      ),
    ];
    await controller.load();

    statusStore.payloadResult.complete(<String, Object?>{
      'schema': AgentControlPayloads.statusSchema,
      'status_scope': 'daemon',
      'daemon_agent_did': 'did:agent:daemon-a',
      'daemon': <String, Object?>{
        'agent_did': 'did:agent:daemon-a',
        'status': 'offline',
      },
    });
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(agentsProvider);
    expect(state.agents.map((agent) => agent.agentDid), ['did:agent:daemon-b']);
    expect(state.statusQueryErrors, isEmpty);
    expect(state.pendingStatusQueryAtByDaemon, isEmpty);
  });

  test(
    'versioned policy mutation awaits account-state reconcile request',
    () async {
      final control = _VersionedAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            displayName: 'Runtime',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();
      final current = container.read(sessionProvider).session!;
      container
          .read(sessionProvider.notifier)
          .setSession(
            SessionIdentity(
              did: current.did,
              credentialName: current.credentialName,
              displayName: current.displayName,
              accountBinding: const SessionAccountBinding(
                ownerIdentityId: 'owner-1',
                accountId: 'account-1',
                currentDid: 'did:human:alice',
                protocolDeviceId: 'device-1',
                identityGeneration: '1',
                deviceAuthGeneration: '1',
              ),
            ),
          );
      final requested = Completer<void>();
      container.read(accountStateSyncRequestBusProvider).attach((
        reason, {
        force = false,
        minimumVersion,
      }) async {
        expect(reason, 'agent_invocation_policy_updated');
        expect(force, isTrue);
        expect(minimumVersion?.domain, ProductAccountDomain.agentInventory);
        expect(minimumVersion?.version, '9');
        requested.complete();
      });

      final saved = await container
          .read(agentsProvider.notifier)
          .saveInvocationPolicy(
            'did:agent:runtime',
            const AgentInvocationPolicy(),
          );

      expect(saved, isTrue);
      await requested.future;
    },
  );

  test('does not load or save invocation policy for daemon agents', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);

    await container.read(agentsProvider.notifier).load();
    await container
        .read(agentsProvider.notifier)
        .loadInvocationPolicy('did:agent:daemon');
    final saved = await container
        .read(agentsProvider.notifier)
        .saveInvocationPolicy(
          'did:agent:daemon',
          const AgentInvocationPolicy(),
        );

    expect(saved, isFalse);
    expect(control.lastInvocationPolicyAgentDid, isNull);
    expect(container.read(agentsProvider).invocationPolicies, isEmpty);
  });

  test('upgradeDaemon rejects stale daemon effective status', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            needsUpgrade: true,
          ),
          daemonEffectiveStatus: DaemonEffectiveStatus(
            controlState: 'stale',
            primaryStatus: 'offline',
            lastReportedStatus: 'needs_upgrade',
            upgradeAvailable: true,
            actionable: false,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    final started = await container
        .read(agentsProvider.notifier)
        .upgradeDaemon('did:agent:daemon');

    final state = container.read(agentsProvider);
    expect(started, isFalse);
    expect(control.lastUpgradeDaemonDid, isNull);
    expect(state.pendingDaemonUpgrades, isEmpty);
    expect(state.daemonUpgradeErrors, isEmpty);
    expect(state.error, AgentUiMessageCodes.daemonUnreachableUpgrade);
  });

  test('createRuntimeAgent rejects stale daemon effective status', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
          daemonEffectiveStatus: DaemonEffectiveStatus(
            controlState: 'stale',
            primaryStatus: 'offline',
            lastReportedStatus: 'ready',
            upgradeAvailable: false,
            actionable: false,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    await container
        .read(agentsProvider.notifier)
        .createRuntimeAgent(
          'did:agent:daemon',
          options: const RuntimeAgentCreateOptions(
            kind: RuntimeAgentKind.hermes,
            handle: 'alice-hermes',
            displayName: 'Alice Hermes',
          ),
        );

    final state = container.read(agentsProvider);
    expect(control.lastRuntimeCreateDaemonDid, isNull);
    expect(state.pendingRuntimeCreations, isEmpty);
    expect(state.error, AgentUiMessageCodes.selectDaemon);
  });

  test(
    'upgradeDaemon waits for version evidence before final success',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      final started = await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');

      expect(started, isTrue);
      expect(control.lastUpgradeDaemonDid, 'did:agent:daemon');
      expect(
        container.read(agentsProvider).pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'ready',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
        },
      );

      var state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(state.agents.single.latest.status, 'upgrading');
      expect(state.agents.single.latest.needsUpgrade, isTrue);

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'ready',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'ready',
            'version': '0.1.34',
          },
        },
      );

      state = container.read(agentsProvider);
      expect(state.pendingDaemonUpgrades, isEmpty);
      expect(state.agents.single.latest.status, 'ready');
      expect(state.agents.single.latest.needsUpgrade, isFalse);
    },
  );

  test('daemon upgrade progress is stored until final success', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            needsUpgrade: true,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    final started = await container
        .read(agentsProvider.notifier)
        .upgradeDaemon('did:agent:daemon');
    expect(started, isTrue);

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'state': 'upgrading',
        'daemon_agent_did': 'did:agent:daemon',
        'result': <String, Object?>{
          'command': 'daemon.upgrade',
          'daemon_agent_did': 'did:agent:daemon',
          'status': 'in_progress',
          'progress': <String, Object?>{
            'stage': 'downloading',
            'message': '正在下载安装包',
            'percent': 42.5,
            'downloaded_bytes': 1024,
            'total_bytes': 4096,
            'source_url': 'https://anpclaw.com/daemon',
            'route': 'direct',
          },
        },
      },
    );

    var state = container.read(agentsProvider);
    expect(
      state.pendingDaemonUpgrades,
      containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
    );
    final progress = state.daemonUpgradeProgress['did:agent:daemon'];
    expect(progress, isNotNull);
    expect(progress!.stage, 'downloading');
    expect(progress.percent, 42.5);
    expect(state.agents.single.latest.status, 'upgrading');

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'state': 'ready',
        'daemon_agent_did': 'did:agent:daemon',
        'result': <String, Object?>{
          'command': 'daemon.upgrade',
          'daemon_agent_did': 'did:agent:daemon',
          'status': 'ready',
          'version': '0.1.41',
        },
      },
    );

    state = container.read(agentsProvider);
    expect(state.pendingDaemonUpgrades, isEmpty);
    expect(state.daemonUpgradeProgress, isEmpty);
  });

  test(
    'slow daemon upgrade progress stays pending without app timeout',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      final started = await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      expect(started, isTrue);

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'upgrading',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'in_progress',
            'progress': <String, Object?>{
              'stage': 'downloading',
              'message': '正在下载安装包',
              'downloaded_bytes': 335872,
              'total_bytes': 7350518,
              'percent': 4.57,
              'speed_bytes_per_sec': 9780,
            },
          },
        },
      );
      await Future<void>.delayed(Duration.zero);

      final state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(state.daemonUpgradeErrors, isEmpty);
      expect(
        state.daemonUpgradeProgress['did:agent:daemon']?.stage,
        'downloading',
      );
      expect(
        state.daemonUpgradeProgress['did:agent:daemon']?.speedBytesPerSecond,
        9780,
      );
    },
  );

  test(
    'daemon upgrade ack timeout keeps request pending for status refresh',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      final commandId = container
          .read(agentsProvider)
          .pendingDaemonUpgrades['did:agent:daemon']!
          .commandId;

      container
          .read(agentsProvider.notifier)
          .handleDaemonUpgradeAckTimeoutForTest('did:agent:daemon', commandId);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(
        state.daemonUpgradeProgress['did:agent:daemon']?.stage,
        'waiting_for_daemon',
      );
      expect(
        state.daemonUpgradeProgress['did:agent:daemon']?.stage,
        'waiting_for_daemon',
      );
      expect(state.daemonUpgradeErrors, isEmpty);
      expect(state.isActing, isFalse);
      expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
    },
  );

  test(
    'load clears pending daemon upgrade when inventory shows latest ready',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              version: '0.1.46',
              latestVersion: '0.1.47',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      final commandId = container
          .read(agentsProvider)
          .pendingDaemonUpgrades['did:agent:daemon']!
          .commandId;
      container
          .read(agentsProvider.notifier)
          .handleDaemonUpgradeAckTimeoutForTest('did:agent:daemon', commandId);

      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            version: '0.1.47',
            latestVersion: '0.1.47',
            needsUpgrade: false,
          ),
        ),
      ];
      await container.read(agentsProvider.notifier).load();

      final state = container.read(agentsProvider);
      expect(state.pendingDaemonUpgrades, isEmpty);
      expect(state.daemonUpgradeProgress, isEmpty);
      expect(state.daemonUpgradeErrors, isEmpty);
      expect(state.agents.single.latest.status, 'ready');
      expect(state.agents.single.latest.needsUpgrade, isFalse);
    },
  );

  test(
    'daemon upgrade ack timeout leaves acknowledged slow download pending',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      final commandId = container
          .read(agentsProvider)
          .pendingDaemonUpgrades['did:agent:daemon']!
          .commandId;
      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'command_id': commandId,
          'state': 'upgrading',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'in_progress',
            'progress': <String, Object?>{
              'stage': 'downloading',
              'message': '正在下载安装包',
              'percent': 12,
            },
          },
        },
      );

      container
          .read(agentsProvider.notifier)
          .handleDaemonUpgradeAckTimeoutForTest('did:agent:daemon', commandId);

      final state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(
        state.pendingDaemonUpgrades['did:agent:daemon']!.acknowledged,
        isTrue,
      );
      expect(
        state.daemonUpgradeProgress['did:agent:daemon']?.stage,
        'downloading',
      );
      expect(state.daemonUpgradeErrors, isEmpty);
    },
  );

  test(
    'cancelDaemonUpgrade tracks cancelling until daemon reports terminal state',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      final upgradeCommandId = container
          .read(agentsProvider)
          .pendingDaemonUpgrades['did:agent:daemon']!
          .commandId;
      final requested = await container
          .read(agentsProvider.notifier)
          .cancelDaemonUpgrade('did:agent:daemon');

      expect(requested, isTrue);
      expect(control.lastCancelledUpgradeDaemonDid, 'did:agent:daemon');
      expect(control.lastCancelledUpgradeTargetCommandId, upgradeCommandId);
      var state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(
        state.cancellingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgradeCancel>()),
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'cancel_requested',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade.cancel',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'cancel_requested',
          },
        },
      );

      state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(
        state.cancellingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgradeCancel>()),
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'cancelled',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'cancelled',
            'error_code': 'upgrade_cancelled',
          },
        },
      );

      state = container.read(agentsProvider);
      expect(state.pendingDaemonUpgrades, isEmpty);
      expect(state.cancellingDaemonUpgrades, isEmpty);
      expect(state.daemonUpgradeProgress, isEmpty);
      expect(state.daemonUpgradeErrors, isEmpty);
      expect(state.agents.single.latest.status, 'needs_upgrade');
    },
  );

  test('daemon upgrade cancel ack timeout clears cancelling only', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            needsUpgrade: true,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    await container
        .read(agentsProvider.notifier)
        .upgradeDaemon('did:agent:daemon');
    final upgradeCommandId = container
        .read(agentsProvider)
        .pendingDaemonUpgrades['did:agent:daemon']!
        .commandId;
    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'command_id': upgradeCommandId,
        'state': 'upgrading',
        'daemon_agent_did': 'did:agent:daemon',
        'result': <String, Object?>{
          'command': 'daemon.upgrade',
          'daemon_agent_did': 'did:agent:daemon',
          'status': 'in_progress',
          'progress': <String, Object?>{
            'stage': 'downloading',
            'message': '正在下载安装包',
          },
        },
      },
    );
    await container
        .read(agentsProvider.notifier)
        .cancelDaemonUpgrade('did:agent:daemon');
    final cancelCommandId = container
        .read(agentsProvider)
        .cancellingDaemonUpgrades['did:agent:daemon']!
        .commandId;

    container
        .read(agentsProvider.notifier)
        .handleDaemonUpgradeCancelAckTimeoutForTest(
          'did:agent:daemon',
          cancelCommandId,
        );

    final state = container.read(agentsProvider);
    expect(
      state.pendingDaemonUpgrades,
      containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
    );
    expect(state.cancellingDaemonUpgrades, isEmpty);
    expect(
      state.daemonUpgradeProgress['did:agent:daemon']?.stage,
      'downloading',
    );
    expect(
      state.daemonUpgradeErrors['did:agent:daemon']?.messageCode,
      AgentUiMessageCodes.upgradeCancelNoResponse,
    );
  });

  test(
    'stale daemon upgrade command payload does not override current pending',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      final commandId = container
          .read(agentsProvider)
          .pendingDaemonUpgrades['did:agent:daemon']!
          .commandId;
      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'command_id': 'cmd_old_upgrade',
          'state': 'failed',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'failed',
            'error_code': 'upgrade_failed',
          },
        },
      );

      final state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades['did:agent:daemon']?.commandId,
        commandId,
      );
      expect(state.daemonUpgradeErrors, isEmpty);
      expect(state.agents.single.latest.status, 'needs_upgrade');
    },
  );

  test(
    'upgradeDaemon does not treat restart scheduled as final success',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              version: '0.1.31',
              latestVersion: '0.1.34',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      final started = await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      expect(started, isTrue);

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'ready',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.upgrade',
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'restart_scheduled',
          },
        },
      );

      var state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(state.agents.single.latest.status, 'upgrading');
      expect(state.agents.single.latest.needsUpgrade, isTrue);

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'ready',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'needs_upgrade',
            'version': '0.1.31',
            'latest_version': '0.1.34',
            'needs_upgrade': true,
          },
          'result': <String, Object?>{
            'daemon_agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
        },
      );

      state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(state.agents.single.latest.status, 'needs_upgrade');
      expect(state.agents.single.latest.needsUpgrade, isTrue);
    },
  );

  test('daemon upgrade failure keeps safe structured diagnostics', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            needsUpgrade: true,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    final started = await container
        .read(agentsProvider.notifier)
        .upgradeDaemon('did:agent:daemon');
    expect(started, isTrue);

    container.read(agentsProvider.notifier).applyControlPayload(<
      String,
      Object?
    >{
      'schema': AgentControlPayloads.statusSchema,
      'state': 'failed',
      'daemon_agent_did': 'did:agent:daemon',
      'result': <String, Object?>{
        'command': 'daemon.upgrade',
        'daemon_agent_did': 'did:agent:daemon',
        'error_code': 'upgrade_download_failed',
        'failed_stage': 'downloading',
        'retryable': true,
        'last_error_summary':
            'daemon package download was interrupted after retries',
        'diagnostic_summary':
            'download daemon package https://anpclaw.com/daemon/releases/0.1.39/awiki-deamon-darwin-arm64.tar.gz: request timed out',
      },
    });

    var state = container.read(agentsProvider);
    expect(state.pendingDaemonUpgrades, isEmpty);
    final failure = state.daemonUpgradeErrors['did:agent:daemon'];
    expect(failure?.messageCode, AgentUiMessageCodes.upgradeDownloadFailed);
    expect(failure?.errorCode, 'upgrade_download_failed');
    expect(failure?.failedStage, 'downloading');
    expect(failure?.retryable, isTrue);
    expect(failure?.diagnosticSummary, contains('request timed out'));
    expect(state.agents.single.latest.status, 'failed');

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'daemon_agent_did': 'did:agent:daemon',
        'daemon': <String, Object?>{
          'agent_did': 'did:agent:daemon',
          'status': 'ready',
          'version': '0.1.39',
          'latest_version': '0.1.39',
          'needs_upgrade': false,
        },
      },
    );

    state = container.read(agentsProvider);
    expect(state.daemonUpgradeErrors, isEmpty);
  });

  test('legacy daemon download failure maps to safe public message', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            needsUpgrade: true,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    container.read(agentsProvider.notifier).applyControlPayload(<
      String,
      Object?
    >{
      'schema': AgentControlPayloads.statusSchema,
      'state': 'failed',
      'daemon_agent_did': 'did:agent:daemon',
      'result': <String, Object?>{
        'command': 'daemon.upgrade',
        'error_code': 'upgrade_failed',
        'last_error_summary':
            'download daemon package https://anpclaw.com/private: request timed out',
      },
    });

    final failure = container
        .read(agentsProvider)
        .daemonUpgradeErrors['did:agent:daemon'];
    expect(
      failure?.messageCode,
      AgentUiMessageCodes.upgradeLegacyDownloadFailed,
    );
    expect(failure?.diagnosticSummary, contains('request timed out'));
  });

  test(
    'status refresh timeout is suppressed while daemon upgrade is pending',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              needsUpgrade: true,
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      final started = await container
          .read(agentsProvider.notifier)
          .upgradeDaemon('did:agent:daemon');
      expect(started, isTrue);

      await container
          .read(agentsProvider.notifier)
          .refreshDaemonStatus('did:agent:daemon');
      container
          .read(agentsProvider.notifier)
          .handleStatusQueryTimeoutForTest('did:agent:daemon');

      final state = container.read(agentsProvider);
      expect(
        state.pendingDaemonUpgrades,
        containsPair('did:agent:daemon', isA<PendingDaemonUpgrade>()),
      );
      expect(state.statusQueryErrors, isEmpty);
    },
  );

  test(
    'status refresh timeout clears pending when local status lookup hangs',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(
        control,
        statusStore: const _HangingAgentControlStatusStore(),
      );
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .refreshDaemonStatus('did:agent:daemon');
      expect(
        container.read(agentsProvider).pendingStatusQueryAtByDaemon,
        contains('did:agent:daemon'),
      );

      await container
          .read(agentsProvider.notifier)
          .handleStatusQueryTimeoutForTest('did:agent:daemon');

      final state = container.read(agentsProvider);
      expect(state.pendingStatusQueryAtByDaemon, isEmpty);
      expect(
        state.statusQueryErrors['did:agent:daemon'],
        AgentUiMessageCodes.statusSyncWaiting,
      );
    },
  );

  test('newer account status snapshot clears an older waiting error', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: 'Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'offline'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    final controller = container.read(agentsProvider.notifier);
    await controller.load();
    await controller.refreshDaemonStatus('did:agent:daemon');
    await controller.handleStatusQueryTimeoutForTest('did:agent:daemon');
    expect(
      container.read(agentsProvider).statusQueryErrors['did:agent:daemon'],
      AgentUiMessageCodes.statusSyncWaiting,
    );

    await controller.applyAccountStateSnapshots(
      inventory: _accountAgentInventorySnapshot(includeRuntime: false),
      status: _accountAgentStatusSnapshot(refreshedAt: DateTime.now().toUtc()),
      isSessionCurrent: () => true,
    );

    final state = container.read(agentsProvider);
    expect(state.statusQueryErrors, isEmpty);
    expect(state.pendingStatusQueryAtByDaemon, isEmpty);
    expect(state.agents.single.latest.status, 'ready');
  });

  test(
    'older account status snapshot cannot clear a newer waiting error',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: 'Daemon',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'offline'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);
      await controller.load();
      final beforeQuery = DateTime.now().toUtc();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await controller.refreshDaemonStatus('did:agent:daemon');
      await controller.handleStatusQueryTimeoutForTest('did:agent:daemon');

      await controller.applyAccountStateSnapshots(
        inventory: _accountAgentInventorySnapshot(includeRuntime: false),
        status: _accountAgentStatusSnapshot(refreshedAt: beforeQuery),
        isSessionCurrent: () => true,
      );

      expect(
        container.read(agentsProvider).statusQueryErrors['did:agent:daemon'],
        AgentUiMessageCodes.statusSyncWaiting,
      );
    },
  );

  test('status refresh send timeout clears pending', () async {
    final control = _HangingRefreshAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    await container
        .read(agentsProvider.notifier)
        .refreshDaemonStatus('did:agent:daemon');

    final state = container.read(agentsProvider);
    expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
    expect(state.pendingStatusQueryAtByDaemon, isEmpty);
    expect(
      state.statusQueryErrors['did:agent:daemon'],
      AgentUiMessageCodes.statusTimeout,
    );
  });

  test('deleteSelected sends runtime delete through owning daemon', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();
    container.read(agentsProvider.notifier).select('did:agent:runtime');

    await container.read(agentsProvider.notifier).deleteSelected();

    expect(control.lastDeletedRuntimeDaemonDid, 'did:agent:daemon');
    expect(control.lastDeletedRuntimeDid, 'did:agent:runtime');
    expect(control.lastDeletedDaemonDid, isNull);
    expect(control.lastUnboundAgentDid, isNull);
    expect(
      container.read(agentsProvider).pendingDeletionAgentDids,
      contains('did:agent:runtime'),
    );
  });

  test('runtime delete pending clears when archive status arrives', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();
    container.read(agentsProvider.notifier).select('did:agent:runtime');

    await container.read(agentsProvider.notifier).deleteSelected();
    expect(
      container.read(agentsProvider).pendingDeletionAgentDids,
      contains('did:agent:runtime'),
    );

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'state': 'archived',
        'daemon_agent_did': 'did:agent:daemon',
        'result': <String, Object?>{
          'command': 'runtime.agent.delete',
          'runtime_agent_did': 'did:agent:runtime',
          'daemon_agent_did': 'did:agent:daemon',
        },
      },
    );

    expect(container.read(agentsProvider).pendingDeletionAgentDids, isEmpty);
    expect(
      container.read(agentsProvider).agents.map((agent) => agent.agentDid),
      ['did:agent:daemon'],
    );
  });

  test(
    'deleteSelected unbinds daemon stuck in registering before first heartbeat',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:stale-daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'registering'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      expect(
        container
            .read(agentsProvider)
            .canDeleteAgent(container.read(agentsProvider).selectedAgent!),
        isTrue,
      );

      await container.read(agentsProvider.notifier).deleteSelected();

      expect(control.lastUnboundAgentDid, 'did:agent:stale-daemon');
      expect(control.lastDeletedDaemonDid, isNull);
      expect(container.read(agentsProvider).agents, isEmpty);
      expect(container.read(agentsProvider).error, isNull);
    },
  );

  test(
    'deleteSelected removes unreachable registering daemon from account',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:registering-seen',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'registering',
              lastSeenAt: DateTime.utc(2026, 6, 21, 10),
            ),
          ),
          const AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:registering-seen',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      expect(
        container
            .read(agentsProvider)
            .canDeleteAgent(container.read(agentsProvider).selectedAgent!),
        isTrue,
      );

      await container.read(agentsProvider.notifier).deleteSelected();

      expect(control.lastUnboundAgentDid, isNull);
      expect(control.lastDeletedDaemonDid, isNull);
      expect(
        control.lastRemovedFromAccountAgentDid,
        'did:agent:registering-seen',
      );
      expect(container.read(agentsProvider).agents, isEmpty);
      expect(container.read(agentsProvider).error, isNull);
    },
  );

  test('deleteSelected removes offline daemon family from account', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:offline-daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'offline'),
        ),
        AgentSummary(
          agentDid: 'did:agent:offline-runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:offline-daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    await container.read(agentsProvider.notifier).deleteSelected();

    expect(control.lastRemovedFromAccountAgentDid, 'did:agent:offline-daemon');
    expect(control.lastDeletedDaemonDid, isNull);
    expect(control.lastDeletedRuntimeDid, isNull);
    expect(container.read(agentsProvider).agents, isEmpty);
    expect(container.read(agentsProvider).pendingDeletionAgentDids, isEmpty);
    expect(container.read(agentsProvider).error, isNull);
  });

  test('deleteSelected removes stale daemon family from account', () async {
    final lastSeenAt = DateTime.now()
        .toUtc()
        .subtract(agentDaemonEffectiveStatusFreshnessWindow)
        .subtract(const Duration(seconds: 1));
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:stale-daemon',
          kind: AgentKind.daemon,
          displayName: 'Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            lastSeenAt: lastSeenAt,
            needsUpgrade: true,
          ),
          daemonEffectiveStatus: DaemonEffectiveStatus(
            controlState: 'online',
            primaryStatus: 'needs_upgrade',
            lastSeenAt: lastSeenAt,
            upgradeAvailable: true,
            actionable: true,
          ),
        ),
        const AgentSummary(
          agentDid: 'did:agent:stale-runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:stale-daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    final daemon = container.read(agentsProvider).selectedAgent!;
    expect(
      container.read(agentsProvider).deleteActionForAgent(daemon),
      AgentDeleteAction.removeFromAccount,
    );

    await container.read(agentsProvider.notifier).deleteSelected();

    expect(control.lastRemovedFromAccountAgentDid, 'did:agent:stale-daemon');
    expect(control.lastDeletedDaemonDid, isNull);
    expect(container.read(agentsProvider).agents, isEmpty);
  });

  test('fresh daemon heartbeat restores controlled deletion', () async {
    final now = DateTime.now().toUtc();
    final staleEffectiveAt = now
        .subtract(agentDaemonEffectiveStatusFreshnessWindow)
        .subtract(const Duration(seconds: 1));
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:recovered-daemon',
          kind: AgentKind.daemon,
          displayName: 'Recovered Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', lastSeenAt: now),
          daemonEffectiveStatus: DaemonEffectiveStatus(
            controlState: 'online',
            primaryStatus: 'ready',
            lastSeenAt: staleEffectiveAt,
            actionable: true,
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    final state = container.read(agentsProvider);
    expect(
      state.deleteActionForAgent(state.selectedAgent!),
      AgentDeleteAction.controlledDelete,
    );
  });

  test(
    'deleteSelected stops waiting and offers account removal after no response',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: 'Daemon 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.now().toUtc(),
            ),
          ),
        ];
      final container = _container(
        control,
        controllerFactory: (ref) => AgentsController(
          ref,
          deletionRefreshAttempts: 1,
          deletionRefreshDelay: Duration.zero,
        ),
      );
      addTearDown(container.dispose);
      final controller = container.read(agentsProvider.notifier);
      await controller.load();

      await controller.deleteSelected();
      expect(
        container.read(agentsProvider).pendingDeletionAgentDids,
        contains('did:agent:daemon'),
      );

      for (var attempt = 0; attempt < 10; attempt += 1) {
        await pumpEventQueue();
        if (container.read(agentsProvider).pendingDeletionAgentDids.isEmpty) {
          break;
        }
      }

      final state = container.read(agentsProvider);
      expect(state.pendingDeletionAgentDids, isEmpty);
      expect(
        state.statusQueryErrors['did:agent:daemon'],
        AgentUiMessageCodes.daemonDeleteNoResponse,
      );
      expect(
        state.deleteActionForAgent(state.selectedAgent!),
        AgentDeleteAction.removeFromAccount,
      );
    },
  );

  test(
    'deleteSelected clears local daemon tracking when removing offline daemon from account',
    () async {
      final control =
          _FailingRefreshAgentControlService(StateError('daemon unreachable'))
            ..agents = const <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:offline-daemon',
                kind: AgentKind.daemon,
                displayName: '代理 1',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'offline'),
              ),
              AgentSummary(
                agentDid: 'did:agent:offline-runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:offline-daemon',
                runtime: 'hermes',
                displayName: 'Hermes',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();
      await container
          .read(agentsProvider.notifier)
          .refreshDaemonStatus('did:agent:offline-daemon');
      expect(
        container.read(agentsProvider).statusQueryErrors,
        contains('did:agent:offline-daemon'),
      );

      await container.read(agentsProvider.notifier).deleteSelected();

      final state = container.read(agentsProvider);
      expect(
        control.lastRemovedFromAccountAgentDid,
        'did:agent:offline-daemon',
      );
      expect(state.agents, isEmpty);
      expect(state.statusQueryErrors, isEmpty);
      expect(state.pendingStatusQueryAtByDaemon, isEmpty);
      expect(state.pendingDaemonUpgrades, isEmpty);
      expect(state.daemonUpgradeErrors, isEmpty);
      expect(state.daemonUpgradeProgress, isEmpty);
      expect(state.pendingDeletionAgentDids, isEmpty);
    },
  );

  test(
    'deleteSelected removes runtime from account when owning daemon is missing',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:orphan-runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:missing-daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container.read(agentsProvider.notifier).deleteSelected();

      expect(
        control.lastRemovedFromAccountAgentDid,
        'did:agent:orphan-runtime',
      );
      expect(control.lastDeletedRuntimeDid, isNull);
      expect(container.read(agentsProvider).agents, isEmpty);
      expect(container.read(agentsProvider).error, isNull);
    },
  );

  test(
    'personal agent lifecycle actions target Hermes message runtime',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:message',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'hermes-msg-app-1',
            displayName: 'Hermes Personal Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control, agentImEnabled: true);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .pausePersonalAgentForDaemon('did:agent:daemon');
      await container
          .read(agentsProvider.notifier)
          .deletePersonalAgentForDaemon('did:agent:daemon');
      await container
          .read(agentsProvider.notifier)
          .revokePersonalAgentAuthorizationForDaemon('did:agent:daemon');

      expect(control.lastPausedPersonalAgentDaemonDid, 'did:agent:daemon');
      expect(control.lastPausedPersonalAgentDid, 'did:agent:message');
      expect(control.lastDeletedPersonalAgentDaemonDid, 'did:agent:daemon');
      expect(control.lastDeletedPersonalAgentDid, 'did:agent:message');
      expect(control.lastDeletedRuntimeDaemonDid, 'did:agent:daemon');
      expect(control.lastDeletedRuntimeDid, 'did:agent:message');
      expect(control.lastRevokedPersonalAgentDaemonDid, 'did:agent:daemon');
      expect(control.lastRevokedPersonalAgentDid, 'did:agent:message');
    },
  );

  test(
    'future provider runtime is not treated as enabled personal agent',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:codex-message',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'codex',
            handle: 'codex-msg-app-1',
            displayName: 'Codex Personal Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control, agentImEnabled: true);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .pausePersonalAgentForDaemon('did:agent:daemon');

      expect(control.lastPausedPersonalAgentDid, isNull);
      expect(
        container.read(agentsProvider).error,
        AgentUiMessageCodes.personalAgentMissing,
      );
    },
  );

  test(
    'archive control payload removes archived agents from current list',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'archived',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'runtime.agent.delete',
            'runtime_agent_did': 'did:agent:runtime',
            'daemon_agent_did': 'did:agent:daemon',
          },
        },
      );

      expect(
        container.read(agentsProvider).agents.map((agent) => agent.agentDid),
        ['did:agent:daemon'],
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'state': 'archived',
          'daemon_agent_did': 'did:agent:daemon',
          'result': <String, Object?>{
            'command': 'daemon.delete',
            'daemon_agent_did': 'did:agent:daemon',
          },
        },
      );

      expect(container.read(agentsProvider).agents, isEmpty);
    },
  );

  test('status snapshot ignores archived runtime payloads', () async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'snapshot',
        'daemon_agent_did': 'did:agent:daemon',
        'daemon': <String, Object?>{
          'agent_did': 'did:agent:daemon',
          'status': 'ready',
        },
        'runtimes': <Object?>[
          <String, Object?>{
            'agent_did': 'did:agent:archived-runtime',
            'daemon_agent_did': 'did:agent:daemon',
            'runtime': 'hermes',
            'status': 'archived',
            'active_state': 'archived',
          },
        ],
      },
    );

    expect(
      container.read(agentsProvider).agents.map((agent) => agent.agentDid),
      ['did:agent:daemon'],
    );
  });

  test(
    'daemon status payload does not replace inventory display names',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '书房代理',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: '写作助手',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'display_name': 'awiki-daemon-random',
            'handle': 'awiki-daemon-random',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'display_name': 'awiki-agent-random',
              'handle': 'awiki-agent-random',
              'runtime': 'hermes',
              'status': 'needs_config',
            },
          ],
        },
      );

      final agents = container.read(agentsProvider).agents;
      final daemon = agents.singleWhere((agent) => agent.isDaemon);
      final runtime = agents.singleWhere((agent) => agent.isRuntime);
      expect(daemon.displayName, '书房代理');
      expect(runtime.displayName, '写作助手');
      expect(runtime.latest.status, 'needs_config');
    },
  );

  test(
    'bootstrapPersonalAgent authorizes daemon proposal and delegates desired state',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'bootstrap_key_id': 'did:agent:daemon#key-3',
                'bootstrap_public_key_b64u':
                    'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                'bootstrap_key_algorithm': 'x25519',
                'config_summary': <String, Object?>{
                  'delegated_subkey_proposal': _daemonSubkeyProposal,
                },
              },
            ),
          ),
        ];
      final identities = FakeIdentityCorePort(
        daemonSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
        ),
      );
      final container = _container(
        control,
        identities: identities,
        agentImEnabled: true,
      );
      addTearDown(container.dispose);
      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastAuthorizedDaemonSubkeySelector, 'default');
      expect(
        identities.lastAuthorizedDaemonSubkeyProposal?.publicKeyMultibase,
        'zPublic',
      );
      expect(control.lastBootstrapDaemonDid, 'did:agent:daemon');
      expect(control.lastBootstrapControllerDid, 'did:human:me');
      expect(control.lastBootstrapAppInstanceId, 'app_1');
      expect(
        control.lastBootstrapUserSubkeyPackage?.verificationMethod,
        'did:human:me#daemon-key-1',
      );
      expect(
        control.lastBootstrapDaemonPublicKey?.keyId,
        'did:agent:daemon#key-3',
      );
      expect(control.lastRuntimeCreateDaemonDid, isNull);
    },
  );

  test(
    'bootstrapPersonalAgent reuses existing Hermes message runtime for binding',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'bootstrap_key_id': 'did:agent:daemon#key-3',
                'bootstrap_public_key_b64u':
                    'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                'bootstrap_key_algorithm': 'x25519',
                'config_summary': <String, Object?>{
                  'delegated_subkey_proposal': _daemonSubkeyProposal,
                },
              },
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:message',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'hermes-msg-app-1',
            displayName: 'Hermes Personal Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final identities = FakeIdentityCorePort(
        daemonSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
        ),
      );
      final bindings = _PersonalAgentBindingsStub();
      final container = _container(
        control,
        identities: identities,
        personalAgentBindings: bindings,
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastAuthorizedDaemonSubkeySelector, 'default');
      expect(control.lastBootstrapDaemonDid, isNull);
      expect(bindings.lastUserDid, 'did:human:me');
      expect(bindings.lastDaemonAgentDid, 'did:agent:daemon');
      expect(bindings.lastPersonalAgentDid, 'did:agent:message');
      expect(
        bindings.lastDelegatedKeyVerificationMethod,
        'did:human:me#daemon-key-1',
      );
    },
  );

  test(
    'bootstrapPersonalAgent keeps raw diagnostic error while showing friendly text',
    () async {
      final control =
          _FailingBootstrapAgentControlService(
              Exception(
                'issue_token failed: invalid_handle hermes-msg-too-long',
              ),
            )
            ..agents = const <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:daemon',
                kind: AgentKind.daemon,
                displayName: '代理 1',
                activeState: 'active',
                latest: AgentLatestStatus(
                  status: 'ready',
                  diagnosticsSummary: <String, Object?>{
                    'bootstrap_key_id': 'did:agent:daemon#key-3',
                    'bootstrap_public_key_b64u':
                        'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                    'bootstrap_key_algorithm': 'x25519',
                    'config_summary': <String, Object?>{
                      'delegated_subkey_proposal': _daemonSubkeyProposal,
                    },
                  },
                ),
              ),
            ];
      final container = _container(control, agentImEnabled: true);
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      final state = container.read(agentsProvider);
      expect(state.error, AgentUiMessageCodes.loadFailed);
      expect(state.error, isNot(contains('invalid_handle')));
      expect(state.debugLastError, contains('invalid_handle'));
    },
  );

  test(
    'bootstrapPersonalAgent is blocked before delegated subkey when feature flag is off',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'bootstrap_key_id': 'did:agent:daemon#key-3',
                'bootstrap_public_key_b64u':
                    'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                'bootstrap_key_algorithm': 'x25519',
              },
            ),
          ),
        ];
      final identities = FakeIdentityCorePort(
        daemonSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
        ),
      );
      final container = _container(
        control,
        identities: identities,
        agentImEnabled: false,
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastAuthorizedDaemonSubkeySelector, isNull);
      expect(control.lastBootstrapDaemonDid, isNull);
      expect(
        container.read(agentsProvider).error,
        AgentUiMessageCodes.tenantUnsupported,
      );
    },
  );

  test(
    'bootstrapPersonalAgent accepts nested bootstrap key diagnostics',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'config_summary': <String, Object?>{
                  'bootstrap_key_status': 'ready',
                  'delegated_subkey_proposal': _daemonSubkeyProposal,
                  'bootstrap_key': <String, Object?>{
                    'key_id': 'did:agent:daemon#key-3',
                    'public_key_b64u':
                        'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                    'algorithm': 'x25519',
                  },
                },
              },
            ),
          ),
        ];
      final identities = FakeIdentityCorePort(
        daemonSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
        ),
      );
      final container = _container(
        control,
        identities: identities,
        agentImEnabled: true,
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastAuthorizedDaemonSubkeySelector, 'default');
      expect(control.lastBootstrapDaemonDid, 'did:agent:daemon');
      expect(
        control.lastBootstrapDaemonPublicKey?.publicKeyB64u,
        'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
    },
  );

  test(
    'bootstrapPersonalAgent accepts flat config summary bootstrap key diagnostics',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              diagnosticsSummary: <String, Object?>{
                'config_summary': <String, Object?>{
                  'bootstrap_key_status': 'ready',
                  'delegated_subkey_proposal': _daemonSubkeyProposal,
                  'bootstrap_key_id': 'did:agent:daemon#key-3',
                  'bootstrap_public_key_b64u':
                      'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                  'bootstrap_key_algorithm': 'x25519',
                },
              },
            ),
          ),
        ];
      final identities = FakeIdentityCorePort(
        daemonSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
        ),
      );
      final container = _container(
        control,
        identities: identities,
        agentImEnabled: true,
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastAuthorizedDaemonSubkeySelector, 'default');
      expect(control.lastBootstrapDaemonDid, 'did:agent:daemon');
      expect(
        control.lastBootstrapDaemonPublicKey?.publicKeyB64u,
        'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      );
    },
  );

  test(
    'bootstrapPersonalAgent requires daemon bootstrap public key before delegated subkey',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final identities = FakeIdentityCorePort(
        daemonSubkeyPackage: const UserSubkeyPackage(
          userDid: 'did:human:me',
          verificationMethod: 'did:human:me#daemon-key-1',
          publicKeyMultibase: 'zPublic',
        ),
      );
      final container = _container(
        control,
        identities: identities,
        agentImEnabled: true,
      );
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapPersonalAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastAuthorizedDaemonSubkeySelector, isNull);
      expect(control.lastBootstrapDaemonDid, isNull);
      expect(
        container.read(agentsProvider).error,
        AgentUiMessageCodes.daemonBootstrapMissing,
      );
    },
  );

  test(
    'createRuntimeAgent delegates codex options from signed-in session',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .createRuntimeAgent(
            'did:agent:daemon',
            options: const RuntimeAgentCreateOptions(
              kind: RuntimeAgentKind.codex,
              handle: 'alice-codex',
              displayName: 'Alice Codex',
              workspaceMode: runtimeWorkspaceModeRouteRoot,
            ),
          );

      expect(control.lastRuntimeCreateDaemonDid, 'did:agent:daemon');
      expect(control.lastRuntimeCreateKind, RuntimeAgentKind.codex);
      expect(control.lastRuntimeCreateHandle, 'alice-codex');
      expect(control.lastRuntimeCreateDisplayName, 'Alice Codex');
      expect(control.lastRuntimeCreateWorkspaceMode, 'route-root');
      expect(control.lastRuntimeCreateSandbox, 'danger-full-access');
    },
  );

  test(
    'control status deduplicates event ids and ignores stale latest',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:05:00Z'),
              version: '0.3.0',
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:05:00Z'),
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'evt_new',
          'sent_at': '2026-06-03T09:06:00Z',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'needs_upgrade',
            'version': '0.4.0',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'needs_config',
              'version': '0.3.0',
              'latest_version': '0.4.0',
              'min_supported_version': '0.4.0',
              'platform': 'linux-amd64',
              'service': 'systemd_user',
              'needs_upgrade': true,
              'needs_config': true,
            },
          ],
        },
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'evt_new',
          'sent_at': '2026-06-03T09:07:00Z',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'failed',
            'version': '0.5.0',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'failed',
            },
          ],
        },
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'evt_old',
          'sent_at': '2026-06-03T09:04:00Z',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'offline',
            'version': '0.2.0',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'ready',
              'needs_config': false,
            },
          ],
        },
      );

      final state = container.read(agentsProvider);
      expect(
        state.seenControlEventIds,
        containsAll(<String>['evt_new', 'evt_old']),
      );
      final daemon = state.agents.singleWhere(
        (agent) => agent.agentDid == 'did:agent:daemon',
      );
      expect(daemon.latest.status, 'needs_upgrade');
      expect(daemon.latest.version, '0.4.0');
      expect(daemon.latest.lastSeenAt, DateTime.parse('2026-06-03T09:06:00Z'));

      final runtime = state.agents.singleWhere(
        (agent) => agent.agentDid == 'did:agent:runtime',
      );
      expect(runtime.latest.status, 'needs_config');
      expect(runtime.latest.needsConfig, isTrue);
      expect(runtime.latest.needsUpgrade, isFalse);
      expect(runtime.latest.version, isNull);
      expect(runtime.latest.latestVersion, isNull);
      expect(runtime.latest.minSupportedVersion, isNull);
      expect(runtime.latest.platform, isNull);
      expect(runtime.latest.service, isNull);
      expect(runtime.latest.lastSeenAt, DateTime.parse('2026-06-03T09:06:00Z'));
    },
  );

  test(
    'timezone-naive inventory timestamp keeps stale v1 dead-letter snapshot from overriding ready',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: 'Daemon',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: parseAgentStatusTimestamp('2026-07-03T07:39:32'),
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime-codex',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'generic-cli',
            displayName: 'Codex',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: parseAgentStatusTimestamp('2026-07-03T07:39:32'),
              diagnosticsSummary: genericCliRuntimeCardDiagnostics(
                lifecycleState: 'created',
                operationalState: 'created',
                setupReady: true,
                setupState: 'ready',
                routeSessionState: 'active',
                nextAction: 'none',
                deadLetterCount: 2,
                attentionState: 'needs_review',
                attentionItemCount: 2,
                attentionNextAction: 'review_dead_letters',
              ),
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();
      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'evt_old_v1_dead_letter',
          'sent_at': '2026-07-03T05:52:49.104682878Z',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime-codex',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'generic-cli',
              'display_name': 'Codex',
              'status': 'ready',
              'last_seen_at': '2026-07-03T05:52:48.659413772Z',
              'needs_config': false,
              'diagnostics_summary': genericCliRuntimeCardDiagnostics(
                statusSchemaVersion: 1,
                lifecycleState: 'dead_letter',
                setupReady: true,
                setupState: 'ready',
                queueState: 'dead_letter',
                routeSessionState: 'active',
                deadLetterCount: 2,
                nextAction: 'manual_review_required',
              ),
            },
          ],
        },
      );

      final runtime = container
          .read(agentsProvider)
          .agents
          .singleWhere((agent) => agent.agentDid == 'did:agent:runtime-codex');
      expect(runtime.latest.status, 'ready');
      expect(runtime.latest.lastSeenAt, DateTime.parse('2026-07-03T07:39:32Z'));
      expect(runtime.latest.runtimeCard?.statusSchemaVersion, 2);
      expect(runtime.latest.runtimeCard?.operationalState, 'created');
    },
  );

  test(
    'snapshot replaces only the same daemon runtime set and cache',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon-a',
            kind: AgentKind.daemon,
            displayName: '代理 A',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime-a-keep',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon-a',
            runtime: 'hermes',
            displayName: 'Hermes A',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime-a-stale',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon-a',
            runtime: 'hermes',
            displayName: 'Hermes Stale',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:daemon-b',
            kind: AgentKind.daemon,
            displayName: '代理 B',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime-b',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon-b',
            runtime: 'hermes',
            displayName: 'Hermes B',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
            ),
          ),
        ];
      final localStore = FakeProductLocalStore();
      final container = _container(control, localStore: localStore);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'evt_snapshot_daemon_a',
          'sent_at': '2026-06-03T09:10:00Z',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon-a',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon-a',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime-a-keep',
              'daemon_agent_did': 'did:agent:daemon-a',
              'runtime': 'hermes',
              'display_name': 'Hermes A',
              'status': 'ready',
            },
          ],
        },
      );

      final state = container.read(agentsProvider);
      expect(
        state.runtimesFor('did:agent:daemon-a').map((agent) => agent.agentDid),
        ['did:agent:runtime-a-keep'],
      );
      expect(
        state.runtimesFor('did:agent:daemon-b').map((agent) => agent.agentDid),
        ['did:agent:runtime-b'],
      );
      expect(
        state.agents.map((agent) => agent.agentDid),
        isNot(contains('did:agent:runtime-a-stale')),
      );

      await pumpEventQueue();
      expect(
        localStore.agentStates.values.map((item) => item.agentDid),
        containsAll(<String>[
          'did:agent:daemon-a',
          'did:agent:runtime-a-keep',
          'did:agent:daemon-b',
          'did:agent:runtime-b',
        ]),
      );
      expect(
        localStore.agentStates.values.map((item) => item.agentDid),
        isNot(contains('did:agent:runtime-a-stale')),
      );
    },
  );

  test('agent cache follows login handle across DID rotation', () async {
    final localStore = FakeProductLocalStore();
    final firstControl = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final firstContainer = _container(
      firstControl,
      localStore: localStore,
      session: const SessionIdentity(
        did: 'did:human:old',
        credentialName: 'default',
        displayName: 'Me',
        handle: 'zhuocheng.anpclaw.com',
      ),
    );
    addTearDown(firstContainer.dispose);
    await firstContainer.read(agentsProvider.notifier).load();

    final secondContainer = _container(
      _FailingAgentControlService(Exception('offline')),
      localStore: localStore,
      session: const SessionIdentity(
        did: 'did:human:new',
        credentialName: 'default',
        displayName: 'Me',
        handle: 'Zhuocheng.Anpclaw.Com',
      ),
    );
    addTearDown(secondContainer.dispose);

    await secondContainer.read(agentsProvider.notifier).load();

    final state = secondContainer.read(agentsProvider);
    expect(state.agents.map((agent) => agent.agentDid), ['did:agent:daemon']);
    expect(localStore.agentStates.values.map((item) => item.ownerDid).toSet(), {
      'controller-handle:zhuocheng.anpclaw.com',
    });
  });

  test(
    'empty daemon snapshot keeps inventory runtime during Personal Agent bootstrap',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:10:00Z'),
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'hermes-msg-controller-001',
            displayName: 'Hermes Personal Agent',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              lastSeenAt: DateTime.parse('2026-06-03T09:10:01Z'),
            ),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'evt_empty_snapshot',
          'sent_at': '2026-06-03T09:10:02Z',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': const <Object?>[],
        },
      );

      final state = container.read(agentsProvider);
      expect(
        state.runtimesFor('did:agent:daemon').map((agent) => agent.agentDid),
        ['did:agent:runtime'],
      );
      expect(
        state.personalAgentRuntimeFor('did:agent:daemon')?.agentDid,
        'did:agent:runtime',
      );
    },
  );

  test('stale snapshot does not prune newer runtime state', () async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            lastSeenAt: DateTime.parse('2026-06-03T09:10:00Z'),
          ),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            lastSeenAt: DateTime.parse('2026-06-03T09:10:00Z'),
          ),
        ),
      ];
    final container = _container(control);
    addTearDown(container.dispose);
    await container.read(agentsProvider.notifier).load();

    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'event_id': 'evt_stale_snapshot',
        'sent_at': '2026-06-03T09:09:00Z',
        'status_scope': 'snapshot',
        'daemon_agent_did': 'did:agent:daemon',
        'daemon': <String, Object?>{
          'agent_did': 'did:agent:daemon',
          'status': 'ready',
        },
        'runtimes': const <Object?>[],
      },
    );

    final state = container.read(agentsProvider);
    expect(
      state.runtimesFor('did:agent:daemon').map((agent) => agent.agentDid),
      ['did:agent:runtime'],
    );
  });

  test(
    'run status payload merges by run id and ignores stale updates',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'run',
          'daemon_agent_did': 'did:agent:daemon',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_1',
              'message_id': 'msg_1',
              'runtime_agent_did': 'did:agent:runtime',
              'conversation_id': 'direct:did:human:me',
              'status': 'running',
              'updated_at': '2026-06-03T09:01:00Z',
            },
          ],
        },
      );

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'run',
          'daemon_agent_did': 'did:agent:daemon',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_1',
              'message_id': 'msg_1',
              'runtime_agent_did': 'did:agent:runtime',
              'conversation_id': 'direct:did:human:me',
              'status': 'queued',
              'updated_at': '2026-06-03T09:00:00Z',
            },
            <String, Object?>{
              'run_id': 'run_2',
              'message_id': 'msg_2',
              'runtime_agent_did': 'did:agent:runtime',
              'conversation_id': 'direct:did:human:me',
              'status': 'failed',
              'updated_at': '2026-06-03T09:02:00Z',
              'last_error_code': 'hermes_error',
              'last_error_summary': 'failed',
            },
          ],
        },
      );

      final runtime = container
          .read(agentsProvider)
          .agents
          .singleWhere((agent) => agent.agentDid == 'did:agent:runtime');
      expect(runtime.latest.status, 'ready');
      expect(runtime.recentRuns.map((run) => run.runId), ['run_2', 'run_1']);
      expect(runtime.recentRuns[0].status, 'failed');
      expect(runtime.recentRuns[0].lastErrorCode, 'hermes_error');
      expect(runtime.recentRuns[1].status, 'running');
    },
  );

  test(
    'local daemon status payload does not promote stale server effective status',
    () async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'needs_upgrade',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
              needsUpgrade: true,
            ),
            daemonEffectiveStatus: DaemonEffectiveStatus(
              controlState: 'stale',
              primaryStatus: 'offline',
              lastReportedStatus: 'needs_upgrade',
              lastSeenAt: DateTime.parse('2026-06-03T09:00:00Z'),
              statusAgeSeconds: 7200,
              upgradeAvailable: true,
              actionable: false,
            ),
          ),
        ];
      final statusStore = _StaticAgentControlStatusStore(
        latestDaemonPayload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'sent_at': DateTime.now().toUtc().toIso8601String(),
          'status_scope': 'daemon',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'needs_upgrade',
            'last_seen_at': DateTime.parse(
              '2026-06-03T09:00:00Z',
            ).toIso8601String(),
            'needs_upgrade': true,
          },
        },
      );
      final container = _container(control, statusStore: statusStore);
      addTearDown(container.dispose);

      await container.read(agentsProvider.notifier).load();

      final daemon = container.read(agentsProvider).agents.single;
      expect(daemon.latest.status, 'needs_upgrade');
      expect(daemon.daemonEffectiveStatus?.controlState, 'stale');
      expect(daemon.daemonEffectiveStatus?.primaryStatus, 'offline');
      expect(daemon.daemonEffectiveStatus?.isUpgradeActionable, isFalse);
    },
  );

  test(
    'runtime activity payload updates controller-visible runtime state',
    () async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'runtime_activity',
          'daemon_agent_did': 'did:agent:daemon',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_external_activity',
              'runtime_agent_did': 'did:agent:runtime',
              'requester_did': 'did:human:bob',
              'trigger_kind': 'external_direct',
              'status': 'running',
              'updated_at': '2026-06-03T09:01:00Z',
            },
          ],
        },
      );

      final runtime = container
          .read(agentsProvider)
          .agents
          .singleWhere((agent) => agent.agentDid == 'did:agent:runtime');
      expect(runtime.latest.status, 'ready');
      expect(runtime.recentRuns, hasLength(1));
      expect(runtime.recentRuns.single.runId, 'run_external_activity');
      expect(runtime.recentRuns.single.status, 'running');
      expect(runtime.recentRuns.single.requesterDid, 'did:human:bob');
      expect(runtime.recentRuns.single.triggerKind, 'external_direct');
    },
  );
}

class _VersionedAgentControlService extends FakeAgentControlService
    implements VersionedAgentControlService {
  @override
  Future<AgentInventoryMutationResult<AgentSummary>>
  updateDisplayNameVersioned({
    required String agentDid,
    required String displayName,
  }) async {
    return AgentInventoryMutationResult<AgentSummary>(
      value: await updateDisplayName(
        agentDid: agentDid,
        displayName: displayName,
      ),
      inventoryVersion: '9',
    );
  }

  @override
  Future<AgentInventoryMutationReceipt> unbindAgentVersioned(
    String agentDid,
  ) async {
    await unbindAgent(agentDid);
    return const AgentInventoryMutationReceipt(inventoryVersion: '9');
  }

  @override
  Future<AgentInventoryMutationResult<List<AgentSummary>>>
  removeAgentFromAccountVersioned(String agentDid) async {
    return AgentInventoryMutationResult<List<AgentSummary>>(
      value: await removeAgentFromAccount(agentDid),
      inventoryVersion: '9',
    );
  }

  @override
  Future<AgentInventoryMutationResult<AgentInvocationPolicy>>
  updateInvocationPolicyVersioned({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    return AgentInventoryMutationResult<AgentInvocationPolicy>(
      value: await updateInvocationPolicy(agentDid: agentDid, policy: policy),
      inventoryVersion: '9',
    );
  }
}

ProviderContainer _container(
  FakeAgentControlService control, {
  FakeProductLocalStore? localStore,
  FakeIdentityCorePort? identities,
  PersonalAgentBindingPort? personalAgentBindings,
  AgentControlStatusStore? statusStore,
  DirectoryApplicationService? directory,
  AgentsController Function(Ref ref)? controllerFactory,
  bool agentImEnabled = true,
  SessionIdentity session = const SessionIdentity(
    did: 'did:human:me',
    credentialName: 'default',
    displayName: 'Me',
    handle: 'me.anpclaw.com',
  ),
}) {
  return ProviderContainer(
    overrides: <Override>[
      agentControlServiceProvider.overrideWithValue(control),
      if (directory != null)
        directoryApplicationServiceProvider.overrideWithValue(directory),
      identityCorePortProvider.overrideWithValue(
        identities ?? FakeIdentityCorePort(),
      ),
      productLocalStoreProvider.overrideWithValue(
        localStore ?? FakeProductLocalStore(),
      ),
      if (personalAgentBindings != null)
        personalAgentBindingPortProvider.overrideWithValue(
          personalAgentBindings,
        ),
      if (statusStore != null)
        agentControlStatusStoreProvider.overrideWithValue(statusStore),
      if (controllerFactory != null)
        agentsProvider.overrideWith(controllerFactory),
      agentImEnabledProvider.overrideWithValue(agentImEnabled),
      sessionProvider.overrideWith((ref) {
        return SessionController()..setSession(session);
      }),
    ],
  );
}

ProductAgentInventorySnapshot _accountAgentInventorySnapshot({
  required bool includeRuntime,
}) {
  return ProductAgentInventorySnapshot(
    binding: const ProductAccountBinding(
      ownerIdentityId: 'owner-1',
      accountId: 'account-1',
    ),
    domainVersion: includeRuntime ? '8' : '7',
    refreshedAt: DateTime.utc(2026, 8, 5),
    agents: <ProductAgentInventoryItem>[
      const ProductAgentInventoryItem(
        agentDid: 'did:agent:daemon',
        activeState: 'active',
        payloadJson:
            '{"agent_kind":"daemon","handle":"current-daemon",'
            '"display_name":"Daemon","status":{"status":"ready"}}',
      ),
      if (includeRuntime)
        const ProductAgentInventoryItem(
          agentDid: 'did:agent:runtime-current-codex',
          activeState: 'active',
          payloadJson:
              '{"agent_kind":"runtime",'
              '"daemon_agent_did":"did:agent:daemon",'
              '"runtime":"codex","handle":"current-codex",'
              '"display_name":"Current Codex",'
              '"status":{"status":"ready"}}',
        ),
    ],
  );
}

ProductAgentStatusSnapshot _accountAgentStatusSnapshot({
  required DateTime refreshedAt,
}) {
  return ProductAgentStatusSnapshot(
    binding: const ProductAccountBinding(
      ownerIdentityId: 'owner-1',
      accountId: 'account-1',
    ),
    domainVersion: '9',
    refreshedAt: refreshedAt,
    statuses: const <ProductAgentStatusItem>[
      ProductAgentStatusItem(
        agentDid: 'did:agent:daemon',
        payloadJson: '{"status":"ready"}',
      ),
    ],
  );
}

class _BlockingDirectoryApplicationService
    implements DirectoryApplicationService {
  final Completer<void> resolveStarted = Completer<void>();
  final Completer<DirectoryPeerResolution> _resolution =
      Completer<DirectoryPeerResolution>();
  final List<String> resolvedPeers = <String>[];

  void complete(DirectoryPeerResolution resolution) {
    _resolution.complete(resolution);
  }

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async => const <PeerDisplayProfile>[];

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    return resolvePeer(handle);
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) {
    resolvedPeers.add(peer);
    if (!resolveStarted.isCompleted) {
      resolveStarted.complete();
    }
    return _resolution.future;
  }
}

class _EventuallyAvailableDirectoryApplicationService
    implements DirectoryApplicationService {
  _EventuallyAvailableDirectoryApplicationService({
    this.failuresBeforeSuccess = 1,
  });

  final int failuresBeforeSuccess;
  int resolveAttempts = 0;

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async => const <PeerDisplayProfile>[];

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    return resolvePeer(handle);
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) async {
    resolveAttempts += 1;
    if (resolveAttempts <= failuresBeforeSuccess) {
      throw StateError('route not committed yet');
    }
    return DirectoryPeerResolution(
      input: peer,
      did: peer,
      handle: 'alice-codex.awiki.info',
      conversationId: 'dm:peer-scope:v1:alice-codex',
    );
  }
}

class _StaticAgentControlStatusStore implements AgentControlStatusStore {
  const _StaticAgentControlStatusStore({
    this.latestDaemonPayload,
    this.daemonStatusPayload,
  });

  final Map<String, Object?>? latestDaemonPayload;
  final Map<String, Object?>? daemonStatusPayload;

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async {
    return latestDaemonPayload;
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) async {
    return daemonStatusPayload;
  }

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async {
    return null;
  }
}

class _BlockingDaemonStatusLookupStore implements AgentControlStatusStore {
  final Completer<void> lookupStarted = Completer<void>();
  final Completer<Map<String, Object?>?> payloadResult =
      Completer<Map<String, Object?>?>();

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async {
    return null;
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) {
    if (!lookupStarted.isCompleted) {
      lookupStarted.complete();
    }
    return payloadResult.future;
  }

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async {
    return null;
  }
}

class _HangingAgentControlStatusStore implements AgentControlStatusStore {
  const _HangingAgentControlStatusStore();

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) {
    return Completer<Map<String, Object?>?>().future;
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) {
    return Completer<Map<String, Object?>?>().future;
  }

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) {
    return Completer<Map<String, Object?>?>().future;
  }
}

class _PersonalAgentBindingsStub implements PersonalAgentBindingPort {
  String? lastUserDid;
  String? lastDaemonAgentDid;
  String? lastPersonalAgentDid;
  String? lastRuntimeProvider;
  Map<String, Object?>? lastRuntimeProfile;
  String? lastDelegatedKeyVerificationMethod;

  @override
  Future<PersonalAgentBinding> ensureBinding({
    required String userDid,
    required String daemonAgentDid,
    required String personalAgentDid,
    required String runtimeProvider,
    required Map<String, Object?> runtimeProfile,
    required String delegatedKeyVerificationMethod,
  }) async {
    lastUserDid = userDid;
    lastDaemonAgentDid = daemonAgentDid;
    lastPersonalAgentDid = personalAgentDid;
    lastRuntimeProvider = runtimeProvider;
    lastRuntimeProfile = runtimeProfile;
    lastDelegatedKeyVerificationMethod = delegatedKeyVerificationMethod;
    return PersonalAgentBinding(
      id: 'binding-1',
      userDid: userDid,
      daemonAgentDid: daemonAgentDid,
      personalAgentDid: personalAgentDid,
      runtimeProvider: runtimeProvider,
      runtimeProfile: runtimeProfile,
      delegatedKeyVerificationMethod: delegatedKeyVerificationMethod,
      status: 'active',
    );
  }

  @override
  Future<PersonalAgentBinding?> getActiveBinding() async => null;

  @override
  Future<PersonalAgentBinding> disableBinding({
    String? bindingId,
    String? personalAgentDid,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<PersonalAgentBinding> revokeBinding({
    String? bindingId,
    String? personalAgentDid,
  }) async {
    throw UnimplementedError();
  }
}

class _FailingAgentControlService extends FakeAgentControlService {
  _FailingAgentControlService(this.error);

  final Object error;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    throw error;
  }
}

class _FailingBootstrapAgentControlService extends FakeAgentControlService {
  _FailingBootstrapAgentControlService(this.error);

  final Object error;

  @override
  Future<void> ensurePersonalAgentBootstrap({
    required String daemonAgentDid,
    required String controllerDid,
    required String appInstanceId,
    required UserSubkeyPackage userSubkeyPackage,
    required DaemonBootstrapPublicKey daemonBootstrapPublicKey,
    String? userHandle,
    String? runtimeRegistrationToken,
    String? runId,
  }) async {
    throw error;
  }
}

class _CountingAgentControlService extends FakeAgentControlService {
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listAgentsCalls += 1;
    return super.listAgents(includeInactive: includeInactive);
  }
}

class _BlockingRuntimeCreationAgentControlService
    extends FakeAgentControlService {
  final Completer<List<AgentSummary>> _unexpectedPreCreateList =
      Completer<List<AgentSummary>>();
  final Completer<void> _runtimeCreateResult = Completer<void>();
  int listAgentsCalls = 0;
  bool runtimeCreateStarted = false;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) {
    listAgentsCalls += 1;
    if (!runtimeCreateStarted) {
      return _unexpectedPreCreateList.future;
    }
    return super.listAgents(includeInactive: includeInactive);
  }

  @override
  Future<void> createRuntimeAgent({
    required String daemonAgentDid,
    required String controllerDid,
    required RuntimeAgentCreateOptions options,
    String? clientRequestId,
  }) {
    runtimeCreateStarted = true;
    return _runtimeCreateResult.future;
  }

  void completeRuntimeCreate() {
    if (!_runtimeCreateResult.isCompleted) {
      _runtimeCreateResult.complete();
    }
  }
}

class _BlockingFirstListAgentControlService extends FakeAgentControlService {
  final Completer<void> firstListStarted = Completer<void>();
  final Completer<List<AgentSummary>> firstListResult =
      Completer<List<AgentSummary>>();
  List<AgentSummary> nextAgents = const <AgentSummary>[];
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) {
    listAgentsCalls += 1;
    if (listAgentsCalls == 1) {
      firstListStarted.complete();
      return firstListResult.future;
    }
    return Future<List<AgentSummary>>.value(nextAgents);
  }
}

class _BlockingInstallCommandAgentControlService
    extends FakeAgentControlService {
  final Completer<void> installCommandStarted = Completer<void>();
  final Completer<InstallCommand> installCommandResult =
      Completer<InstallCommand>();

  @override
  Future<InstallCommand> createDaemonInstallCommand({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) {
    if (!installCommandStarted.isCompleted) {
      installCommandStarted.complete();
    }
    return installCommandResult.future;
  }
}

class _BlockingInvocationPolicyAgentControlService
    extends FakeAgentControlService {
  final Completer<void> policyRequestStarted = Completer<void>();
  final Completer<AgentInvocationPolicy> policyResult =
      Completer<AgentInvocationPolicy>();

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy(String agentDid) {
    if (!policyRequestStarted.isCompleted) {
      policyRequestStarted.complete();
    }
    return policyResult.future;
  }
}

class _SequencedAgentControlService extends FakeAgentControlService {
  _SequencedAgentControlService(this.responses);

  final List<List<AgentSummary>> responses;
  final Map<int, Object> errorsByCall = <int, Object>{};
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listAgentsCalls += 1;
    final error = errorsByCall[listAgentsCalls];
    if (error != null) {
      throw error;
    }
    final index = (listAgentsCalls - 1).clamp(0, responses.length - 1);
    return responses[index];
  }
}

class _ControlledInventoryAgentControlService extends FakeAgentControlService {
  final List<Completer<List<AgentSummary>>> _listCalls =
      <Completer<List<AgentSummary>>>[];

  int get listAgentsCalls => _listCalls.length;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) {
    final completer = Completer<List<AgentSummary>>();
    _listCalls.add(completer);
    return completer.future;
  }

  void completeListCall(int call, List<AgentSummary> agents) {
    _listCalls[call - 1].complete(agents);
  }

  Future<void> waitForListCalls(int expected) async {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      if (listAgentsCalls >= expected) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail(
      'Timed out waiting for $expected inventory calls; '
      'observed $listAgentsCalls.',
    );
  }
}

class _FailingRefreshAgentControlService extends FakeAgentControlService {
  _FailingRefreshAgentControlService(this.error);

  final Object error;

  @override
  Future<void> refreshDaemonStatus(
    String daemonAgentDid, {
    String? commandId,
  }) async {
    lastRefreshedDaemonDid = daemonAgentDid;
    throw error;
  }
}

class _HangingRefreshAgentControlService extends FakeAgentControlService {
  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid, {String? commandId}) {
    lastRefreshedDaemonDid = daemonAgentDid;
    return Completer<void>().future;
  }
}

class _FailingAgentStateStore extends FakeProductLocalStore {
  @override
  Future<List<LocalAgentState>> loadAgentStates({
    required String ownerDid,
  }) async {
    throw StateError('local cache unavailable');
  }

  @override
  Future<void> saveAgentState(LocalAgentState state) async {
    throw StateError('local cache unavailable');
  }
}

class _BlockingFirstAgentCacheWriteStore extends FakeProductLocalStore {
  final Completer<void> firstWriteStarted = Completer<void>();
  final Completer<void> _releaseFirstWrite = Completer<void>();
  final Completer<void> secondWriteCompleted = Completer<void>();
  final List<String> savedAgentDids = <String>[];
  int saveCalls = 0;

  void releaseFirstWrite() {
    if (!_releaseFirstWrite.isCompleted) {
      _releaseFirstWrite.complete();
    }
  }

  @override
  Future<void> saveAgentState(LocalAgentState state) async {
    saveCalls += 1;
    if (saveCalls == 1) {
      firstWriteStarted.complete();
      await _releaseFirstWrite.future;
    }
    savedAgentDids.add(state.agentDid);
    await super.saveAgentState(state);
    if (saveCalls == 2 && !secondWriteCompleted.isCompleted) {
      secondWriteCompleted.complete();
    }
  }
}
