import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  test(
    'load restores UserService inventory and selects daemon first',
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
      expect(state.selectedAgentDid, 'did:agent:daemon');
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

    expect(state.error, '登录状态已失效，请重新登录后再查看智能体。');
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

    expect(container.read(agentsProvider).error, '暂时无法连接后端服务，请检查网络或服务地址后重试。');
  });

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
      expect(state.selectedAgentDid, 'did:agent:daemon');
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
      expect(runtime.displayName, '未命名智能体');
      expect(runtime.latest.status, 'needs_config');
      expect(runtime.latest.needsConfig, isTrue);
      await Future<void>.delayed(agentStatusRefreshMinimumIndicatorDuration);
      expect(
        container.read(agentsProvider).pendingStatusQueryAtByDaemon,
        isEmpty,
      );
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
    expect(state.statusQueryErrors['did:agent:daemon'], '状态刷新请求发送失败，请稍后再试。');
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

  test('upgradeDaemon shows pending until upgrade result arrives', () async {
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
      contains('did:agent:daemon'),
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

    final state = container.read(agentsProvider);
    expect(state.pendingDaemonUpgrades, isEmpty);
    expect(state.agents.single.latest.status, 'ready');
    expect(state.agents.single.latest.needsUpgrade, isFalse);
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
  });

  test(
    'message Agent lifecycle actions target Hermes message runtime',
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
            displayName: 'Hermes Message Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control, agentImEnabled: true);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .pauseMessageAgentForDaemon('did:agent:daemon');
      await container
          .read(agentsProvider.notifier)
          .deleteMessageAgentForDaemon('did:agent:daemon');
      await container
          .read(agentsProvider.notifier)
          .revokeMessageAgentAuthorizationForDaemon('did:agent:daemon');

      expect(control.lastPausedMessageAgentDaemonDid, 'did:agent:daemon');
      expect(control.lastPausedMessageAgentDid, 'did:agent:message');
      expect(control.lastDeletedMessageAgentDaemonDid, 'did:agent:daemon');
      expect(control.lastDeletedMessageAgentDid, 'did:agent:message');
      expect(control.lastDeletedRuntimeDaemonDid, 'did:agent:daemon');
      expect(control.lastDeletedRuntimeDid, 'did:agent:message');
      expect(control.lastRevokedMessageAgentDaemonDid, 'did:agent:daemon');
      expect(control.lastRevokedMessageAgentDid, 'did:agent:message');
    },
  );

  test(
    'future provider runtime is not treated as enabled message Agent',
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
            displayName: 'Codex Message Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = _container(control, agentImEnabled: true);
      addTearDown(container.dispose);
      await container.read(agentsProvider.notifier).load();

      await container
          .read(agentsProvider.notifier)
          .pauseMessageAgentForDaemon('did:agent:daemon');

      expect(control.lastPausedMessageAgentDid, isNull);
      expect(container.read(agentsProvider).error, '当前 Daemon 尚未创建消息处理 Agent。');
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
    'bootstrapMessageAgent ensures daemon subkey and delegates desired state',
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
          privateKeyMultibase: 'zPrivate',
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
          .bootstrapMessageAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastEnsuredDaemonSubkeySelector, 'default');
      expect(identities.lastDaemonSubkeySelector, isNull);
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
    'bootstrapMessageAgent is blocked before delegated subkey when feature flag is off',
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
          privateKeyMultibase: 'zPrivate',
        ),
      );
      final container = _container(control, identities: identities);
      addTearDown(container.dispose);

      await container
          .read(agentsProvider.notifier)
          .bootstrapMessageAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
      expect(control.lastBootstrapDaemonDid, isNull);
      expect(container.read(agentsProvider).error, '消息处理 Agent 功能未开启。');
    },
  );

  test(
    'bootstrapMessageAgent requires daemon bootstrap public key before delegated subkey',
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
          privateKeyMultibase: 'zPrivate',
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
          .bootstrapMessageAgent(
            daemonDid: 'did:agent:daemon',
            appInstanceId: 'app_1',
          );

      expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
      expect(control.lastBootstrapDaemonDid, isNull);
      expect(
        container.read(agentsProvider).error,
        '运行 Daemon 尚未上报安全 bootstrap 公钥，请先刷新状态。',
      );
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
      expect(runtime.latest.lastSeenAt, DateTime.parse('2026-06-03T09:06:00Z'));
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

ProviderContainer _container(
  FakeAgentControlService control, {
  FakeProductLocalStore? localStore,
  FakeIdentityCorePort? identities,
  bool agentImEnabled = false,
  SessionIdentity session = const SessionIdentity(
    did: 'did:human:me',
    credentialName: 'default',
    displayName: 'Me',
  ),
}) {
  return ProviderContainer(
    overrides: <Override>[
      agentControlServiceProvider.overrideWithValue(control),
      identityCorePortProvider.overrideWithValue(
        identities ?? FakeIdentityCorePort(),
      ),
      productLocalStoreProvider.overrideWithValue(
        localStore ?? FakeProductLocalStore(),
      ),
      agentImEnabledProvider.overrideWithValue(agentImEnabled),
      sessionProvider.overrideWith((ref) {
        return SessionController()..setSession(session);
      }),
    ],
  );
}

class _FailingAgentControlService extends FakeAgentControlService {
  _FailingAgentControlService(this.error);

  final Object error;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
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

class _FailingRefreshAgentControlService extends FakeAgentControlService {
  _FailingRefreshAgentControlService(this.error);

  final Object error;

  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid) async {
    lastRefreshedDaemonDid = daemonAgentDid;
    throw error;
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
