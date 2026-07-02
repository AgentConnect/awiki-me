import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/repositories/awiki_account_gateway.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  testWidgets('agents workspace shows daemon actions', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智能体'), findsWidgets);
    expect(find.text('代理 1'), findsWidgets);
    expect(find.text('刷新状态'), findsNothing);
    expect(find.byIcon(CupertinoIcons.refresh), findsWidgets);
    expect(find.text('创建 Agent'), findsOneWidget);
    expect(find.text('升级'), findsNothing);
    expect(find.text('安装命令'), findsNothing);
  });

  testWidgets('agents workspace re-entry reuses loaded inventory', (
    tester,
  ) async {
    final control = _CountingListAgentControlService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const _AgentsWorkspaceToggleHost(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(control.listAgentsCalls, 1);
    expect(find.byType(AgentsWorkspacePage), findsOneWidget);

    await tester.tap(find.byKey(const Key('hide-agents-workspace')));
    await tester.pumpAndSettle();
    expect(find.byType(AgentsWorkspacePage), findsNothing);

    await tester.tap(find.byKey(const Key('show-agents-workspace')));
    await tester.pumpAndSettle();

    expect(find.byType(AgentsWorkspacePage), findsOneWidget);
    expect(control.listAgentsCalls, 1);
  });

  testWidgets('agents workspace shows empty state and load error banner', (
    tester,
  ) async {
    final control = _FailingListAgentControlService()
      ..agents = const <AgentSummary>[];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('暂无代理'), findsOneWidget);
    expect(find.text('智能体信息暂时无法加载，请稍后重试。'), findsOneWidget);

    control.failList = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('智能体信息暂时无法加载，请稍后重试。'), findsNothing);
    expect(find.text('暂无代理'), findsOneWidget);
  });

  testWidgets('empty agents workspace offers host sync refresh', (
    tester,
  ) async {
    final control = _SequencedListAgentControlService(<List<AgentSummary>>[
      const <AgentSummary>[],
      const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'edgehost-test',
          displayName: 'Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ],
    ]);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('暂无代理'), findsOneWidget);
    expect(find.text('正在同步宿主机上的 Daemon，安装完成后会自动出现。'), findsOneWidget);

    await tester.tap(find.byTooltip('刷新智能体列表').first);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(control.listAgentsCalls, greaterThanOrEqualTo(2));
    expect(find.text('Daemon 1'), findsWidgets);
    expect(find.text('暂无代理'), findsNothing);
  });

  testWidgets('daemon upgrade action appears only when upgrade is needed', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'needs_upgrade',
            platform: 'linux-amd64',
            needsUpgrade: true,
          ),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('升级'), findsOneWidget);
    expect(find.text('安装命令'), findsNothing);
  });

  testWidgets(
    'compact agents workspace returns to list and stays there after status payload',
    (tester) async {
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
          AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'awiki-agent-hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('创建 Agent'), findsNothing);
      expect(find.text('Hermes'), findsOneWidget);

      await tester.tap(find.text('代理 1').first);
      await tester.pumpAndSettle();
      expect(find.text('创建 Agent'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.chevron_left));
      await tester.pumpAndSettle();
      expect(find.text('创建 Agent'), findsNothing);
      expect(find.text('Hermes'), findsOneWidget);

      final context = tester.element(find.byType(AgentsWorkspacePage));
      final container = ProviderScope.containerOf(context);
      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'daemon',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'handle': 'awiki-agent-hermes',
              'display_name': 'Hermes',
              'status': 'ready',
            },
          ],
        },
      );
      await tester.pumpAndSettle();

      expect(container.read(agentsProvider).selectedAgentDid, isNull);
      expect(find.text('创建 Agent'), findsNothing);
      expect(find.text('Hermes'), findsOneWidget);
    },
  );

  testWidgets(
    'wide agents workspace still shows first agent detail by default',
    (tester) async {
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

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(AgentsWorkspacePage));
      final container = ProviderScope.containerOf(context);
      expect(container.read(agentsProvider).selectedAgentDid, isNull);
      expect(find.text('创建 Agent'), findsOneWidget);
    },
  );

  testWidgets(
    'unrelated pending agent action does not disable daemon actions',
    (tester) async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: readyDaemonStatusWithGenericCliCapability,
          ),
        ];
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
            agentsProvider.overrideWith((ref) {
              return _SeededAgentsController(
                ref,
                AgentsState(
                  agents: control.agents,
                  selectedAgentDid: 'did:agent:daemon',
                  pendingActionKeys: <String>{
                    AgentActionKeys.rename('did:agent:other-runtime'),
                  },
                ),
              );
            }),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(_agentRefreshButton().first);
      await tester.pump();
      expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');

      await tester.tap(find.text('改名'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agent-rename-field')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('创建 Agent'));
      await tester.pumpAndSettle();
      expect(find.text('Agent 类型'), findsOneWidget);
    },
  );

  testWidgets('runtime actions open chat and send control commands', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'darwin-arm64'),
        ),
        const AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'awiki-agent-hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hermes').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开聊天'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AgentsWorkspacePage));
    final container = ProviderScope.containerOf(context);
    expect(
      container.read(selectedConversationProvider)?.targetDid,
      'did:agent:runtime',
    );
    expect(
      container.read(selectedConversationProvider)?.targetPeer,
      'awiki-agent-hermes.awiki.info',
    );
    expect(
      container
          .read(conversationListProvider)
          .conversations
          .any((item) => item.targetDid == 'did:agent:runtime'),
      isTrue,
    );
    expect(
      container
          .read(conversationListProvider)
          .conversations
          .singleWhere((item) => item.targetDid == 'did:agent:runtime')
          .targetPeer,
      'awiki-agent-hermes.awiki.info',
    );

    expect(find.text('重置 Session'), findsNothing);
    expect(find.text('重试 Run'), findsNothing);
  });

  testWidgets(
    'create Agent dialog normalizes handle and submits previewed values',
    (tester) async {
      final control = _PendingRefreshAgentControlService()
        ..agents = <AgentSummary>[
          const AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: readyDaemonStatusWithGenericCliCapability,
          ),
          const AgentSummary(
            agentDid: 'did:agent:runtime',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'alice-hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('创建 Agent'));
      await tester.pumpAndSettle();

      expect(find.text('创建 Agent'), findsWidgets);
      expect(find.text('Agent 类型'), findsOneWidget);
      expect(find.text('Hermes'), findsWidgets);
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('需刷新'), findsNothing);
      final nameFieldFinder = find.byKey(const Key('agent-create-name-field'));
      final handleFieldFinder = find.byKey(
        const Key('agent-create-handle-field'),
      );
      final nameField = tester.widget<CupertinoTextField>(nameFieldFinder);
      expect(nameField.controller?.text, 'Hermes2');

      await tester.tap(find.text('Claude Code'));
      await tester.pumpAndSettle();
      final claudeNameField = tester.widget<CupertinoTextField>(
        nameFieldFinder,
      );
      expect(claudeNameField.controller?.text, 'Claude Code1');

      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();
      expect(find.text('工作目录策略'), findsNothing);
      expect(find.text('宿主机全权限'), findsNothing);
      expect(find.text('按会话目录'), findsNothing);
      final codexNameField = tester.widget<CupertinoTextField>(nameFieldFinder);
      expect(codexNameField.controller?.text, 'Codex1');

      await tester.enterText(handleFieldFinder, '@My-Agent');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      final handleField = tester.widget<CupertinoTextField>(handleFieldFinder);
      expect(handleField.controller?.text, 'my-agent');
      expect(find.text('最终 Handle：@my-agent.awiki.info'), findsOneWidget);
      expect(find.text('这个 Handle 可以使用'), findsOneWidget);

      await tester.enterText(nameFieldFinder, '写作助手');
      await tester.tap(find.text('创建').last);
      await tester.pumpAndSettle();

      expect(control.lastRuntimeCreateDaemonDid, 'did:agent:daemon');
      expect(control.lastRuntimeCreateKind, RuntimeAgentKind.codex);
      expect(control.lastRuntimeCreateHandle, 'my-agent');
      expect(control.lastRuntimeCreateDisplayName, '写作助手');
      expect(control.lastRuntimeCreateWorkspaceMode, 'route-root');
      expect(control.lastRuntimeCreateSandbox, 'danger-full-access');
      expect(control.lastRuntimeCreateClientRequestId, isNotNull);
      expect(find.text('写作助手'), findsWidgets);
      expect(find.text('Codex · 创建状态暂未返回，可刷新查看'), findsOneWidget);
    },
  );

  testWidgets(
    'create Agent dialog hides generic CLI advanced options on compact height',
    (tester) async {
      final control = _PendingRefreshAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: readyDaemonStatusWithGenericCliCapability,
          ),
        ];

      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('创建 Agent'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('agent-create-scroll-body')), findsOneWidget);
      expect(find.text('工作目录策略'), findsNothing);
      expect(find.text('宿主机全权限'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('agent-create-handle-field')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agent-create-name-field')), findsOneWidget);
      expect(
        find.byKey(const Key('agent-create-handle-field')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('create Agent dialog submits generic CLI full-access directly', (
    tester,
  ) async {
    final control = _PendingRefreshAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: readyDaemonStatusWithGenericCliCapability,
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建 Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agent-create-handle-field')),
      'full-access-agent',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('agent-create-name-field')),
      '宿主机助手',
    );

    await tester.tap(find.text('创建').last);
    await tester.pumpAndSettle();

    expect(control.lastRuntimeCreateKind, RuntimeAgentKind.codex);
    expect(control.lastRuntimeCreateHandle, 'full-access-agent');
    expect(control.lastRuntimeCreateDisplayName, '宿主机助手');
    expect(control.lastRuntimeCreateSandbox, 'danger-full-access');
  });

  testWidgets(
    'create Agent dialog disables generic CLI when daemon lacks capability',
    (tester) async {
      final control = _PendingRefreshAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready', platform: 'linux-amd64'),
          ),
        ];

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('创建 Agent'));
      await tester.pumpAndSettle();

      expect(find.text('需刷新'), findsNWidgets(2));
      expect(
        find.text('Codex 需要 Daemon 提供 generic-cli capability。'),
        findsOneWidget,
      );
      expect(
        find.text('Claude Code 需要 Daemon 提供 generic-cli capability。'),
        findsOneWidget,
      );

      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();

      expect(find.text('工作目录策略'), findsNothing);
      expect(control.lastRuntimeCreateDaemonDid, isNull);
    },
  );

  testWidgets(
    'create Agent dialog fails closed for incompatible generic CLI schema',
    (tester) async {
      final control = await _pumpCreateAgentDialog(
        tester,
        daemon: _daemonWithGenericCliCapability(
          _genericCliCapability(schemaVersion: 99),
        ),
      );

      expect(find.text('需刷新'), findsWidgets);
      expect(
        find.text('Codex 需要 Daemon 提供 generic-cli capability。'),
        findsOneWidget,
      );

      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();

      expect(find.text('工作目录策略'), findsNothing);
      expect(control.lastRuntimeCreateDaemonDid, isNull);
    },
  );

  testWidgets(
    'create Agent dialog fails closed when route-root is unsupported',
    (tester) async {
      final control = await _pumpCreateAgentDialog(
        tester,
        daemon: _daemonWithGenericCliCapability(
          _genericCliCapability(
            supportedWorkspaceModes: const <String>['shared-root'],
          ),
        ),
      );

      expect(find.text('需要升级'), findsWidgets);
      expect(find.text('Codex 需要按会话目录工作模式。'), findsOneWidget);

      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();

      expect(find.text('工作目录策略'), findsNothing);
      expect(control.lastRuntimeCreateDaemonDid, isNull);
    },
  );

  testWidgets('runtime detail updates access policy immediately', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'awiki-agent-hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ]
      ..invocationPolicies['did:agent:runtime'] = const AgentInvocationPolicy(
        whitelistHandles: <String>['alice.awiki.info'],
      );

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('访问权限'), findsOneWidget);
    expect(find.text('白名单'), findsWidgets);
    expect(find.text('黑名单'), findsWidgets);
    expect(find.byKey(const Key('agent-access-mode-toggle')), findsOneWidget);
    expect(find.text('@alice.awiki.info'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const Key('agent-access-whitelist-field')),
          )
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const Key('agent-access-blacklist-field')),
          )
          .enabled,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('agent-access-blacklist-add')));
    await tester.pumpAndSettle();
    expect(control.lastInvocationPolicyAgentDid, isNull);

    await tester.tap(find.byKey(const Key('agent-access-mode-toggle')));
    await tester.pumpAndSettle();
    expect(control.lastInvocationPolicyAgentDid, 'did:agent:runtime');
    expect(
      control.lastInvocationPolicy?.activeMode,
      AgentInvocationPolicyMode.blacklist,
    );
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const Key('agent-access-whitelist-field')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const Key('agent-access-blacklist-field')),
          )
          .enabled,
      isTrue,
    );

    await tester.enterText(
      find.byKey(const Key('agent-access-blacklist-field')),
      '@bob.awiki.info',
    );
    await tester.tap(find.byKey(const Key('agent-access-blacklist-add')));
    await tester.pumpAndSettle();

    expect(control.lastInvocationPolicyAgentDid, 'did:agent:runtime');
    expect(
      control.lastInvocationPolicy?.activeMode,
      AgentInvocationPolicyMode.blacklist,
    );
    expect(control.lastInvocationPolicy?.whitelistHandles, <String>[
      'alice.awiki.info',
    ]);
    expect(control.lastInvocationPolicy?.blacklistHandles, <String>[
      'bob.awiki.info',
    ]);
    expect(find.text('@bob.awiki.info'), findsOneWidget);

    await tester.tap(find.byTooltip('删除').last);
    await tester.pumpAndSettle();

    expect(control.lastInvocationPolicy?.blacklistHandles, isEmpty);
  });

  testWidgets('daemon detail does not show access policy panel', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'linux-amd64'),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('访问权限'), findsNothing);
    expect(find.byKey(const Key('agent-access-whitelist-field')), findsNothing);
    expect(control.lastInvocationPolicyAgentDid, isNull);
  });

  testWidgets('message Agent panel is hidden when feature flag is off', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentImEnabledProvider.overrideWithValue(false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-agent-settings-panel')), findsNothing);
    expect(find.text('消息处理 Agent'), findsNothing);
    expect(find.text('启用消息处理 Agent'), findsNothing);
    expect(find.text('暂停处理消息'), findsNothing);
    expect(find.text('删除消息处理 Agent'), findsNothing);
    expect(find.text('撤销 Daemon 消息授权'), findsNothing);
    expect(control.lastBootstrapDaemonDid, isNull);
    expect(find.textContaining('自动回复'), findsNothing);
    expect(find.textContaining('代发'), findsNothing);
  });

  testWidgets('message Agent panel is hidden when daemon lacks bootstrap key', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'linux-amd64'),
        ),
      ];
    final identities = FakeIdentityCorePort();

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('message-agent-settings-panel')), findsNothing);
    expect(find.text('运行 Daemon 内创建 Hermes runtime'), findsNothing);
    expect(find.text('等待刷新状态'), findsNothing);
    expect(find.text('启用消息处理 Agent'), findsNothing);
    expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
    expect(control.lastBootstrapDaemonDid, isNull);
    expect(find.textContaining('尚未上报安全 bootstrap 公钥'), findsNothing);
  });

  testWidgets(
    'message Agent management panel is hidden with existing runtime',
    (tester) async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '运行 Daemon 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'ready',
              version: '0.5.26',
              platform: 'linux-amd64',
              diagnosticsSummary: <String, Object?>{
                'config_summary': <String, Object?>{
                  'bootstrap_key_status': 'ready',
                  'bootstrap_key_id': 'did:agent:daemon#key-3',
                  'bootstrap_public_key_b64u':
                      'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
                  'bootstrap_key_algorithm': 'x25519',
                },
              },
            ),
          ),
          AgentSummary(
            agentDid: 'did:agent:message',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'hermes-msg-app-default',
            displayName: 'Hermes Message Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
            handle: 'me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
            agentImEnabledProvider.overrideWithValue(true),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('message-agent-settings-panel')),
        findsNothing,
      );
      expect(find.text('消息处理 Agent'), findsNothing);
      expect(find.text('运行 Daemon 1'), findsWidgets);
      expect(find.text('Hermes Message Agent'), findsWidgets);
      expect(find.text('启用消息处理 Agent'), findsNothing);
      expect(find.text('暂停处理消息'), findsNothing);
      expect(find.text('删除消息处理 Agent'), findsNothing);
      expect(find.text('撤销 Daemon 消息授权'), findsNothing);
      expect(find.textContaining('自动回复'), findsNothing);
      expect(find.textContaining('代发'), findsNothing);
    },
  );

  testWidgets('create Agent dialog blocks unavailable handle', (tester) async {
    final gateway = FakeAwikiGateway()
      ..handleRegistrationStatus = HandleRegistrationStatus.registered;
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'darwin-arm64'),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        gateway: gateway,
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('创建 Agent'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('agent-create-handle-field')),
      'used-agent',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('这个 Handle 已被使用'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('agent-create-name-field')),
      '写作助手',
    );
    await tester.tap(find.text('创建').last);
    await tester.pumpAndSettle();

    expect(control.lastRuntimeCreateDaemonDid, isNull);
  });

  testWidgets('agent list groups runtime agents under their daemon', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:runtime:b',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon:b',
          runtime: 'hermes',
          handle: 'awiki-agent-b',
          displayName: 'Hermes B',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        const AgentSummary(
          agentDid: 'did:agent:daemon:a',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-a',
          displayName: 'MacBook Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'darwin-arm64'),
        ),
        const AgentSummary(
          agentDid: 'did:agent:runtime:a',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon:a',
          runtime: 'hermes',
          handle: 'awiki-agent-a',
          displayName: 'Hermes A',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        const AgentSummary(
          agentDid: 'did:agent:daemon:b',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-b',
          displayName: 'Server Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready', platform: 'linux-arm64'),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daemon · 1 个 Agent · 正常'), findsNWidgets(2));
    expect(find.text('Hermes · 正常'), findsNWidgets(2));

    final listPane = find.byType(ListView).first;
    final daemonATop = tester
        .getTopLeft(
          find.descendant(of: listPane, matching: find.text('MacBook Daemon')),
        )
        .dy;
    final runtimeATop = tester
        .getTopLeft(
          find.descendant(of: listPane, matching: find.text('Hermes A')),
        )
        .dy;
    final daemonBTop = tester
        .getTopLeft(
          find.descendant(of: listPane, matching: find.text('Server Daemon')),
        )
        .dy;
    final runtimeBTop = tester
        .getTopLeft(
          find.descendant(of: listPane, matching: find.text('Hermes B')),
        )
        .dy;
    expect(daemonATop, lessThan(runtimeATop));
    expect(runtimeATop, lessThan(daemonBTop));
    expect(daemonBTop, lessThan(runtimeBTop));

    await tester.tap(
      find.descendant(of: listPane, matching: find.text('Hermes B')),
    );
    await tester.pumpAndSettle();

    expect(find.text('打开聊天'), findsOneWidget);
    expect(find.text('did:agent:runtime:b'), findsWidgets);
    expect(find.text('awiki-agent-b'), findsOneWidget);
    expect(find.text('did:agent:daemon:b'), findsNothing);
  });

  testWidgets('agent detail supports cross-field selection for diagnostics', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'failed',
            version: '1.2.3',
            platform: 'linux-arm64',
            service: 'systemd_user',
            lastErrorCode: 'gateway_error',
            lastErrorSummary: 'gateway timeout',
            diagnosticsSummary: <String, Object?>{'runner': 'queue=3'},
          ),
        ),
        const AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'awiki-agent-hermes',
          displayName: 'Hermes Runtime',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AgentsWorkspacePage));
    ProviderScope.containerOf(
      context,
    ).read(agentsProvider.notifier).select('did:agent:daemon');
    await tester.pumpAndSettle();

    final detailSelectionArea = find.byType(SelectionArea);
    expect(detailSelectionArea, findsOneWidget);
    expect(
      find
          .byWidgetPredicate(
            (widget) => widget is SelectionContainer && widget.delegate == null,
          )
          .evaluate()
          .length,
      greaterThanOrEqualTo(2),
    );
    Finder detailText(String text) =>
        find.descendant(of: detailSelectionArea, matching: find.text(text));
    expect(detailText('代理 1'), findsWidgets);
    expect(detailText('异常'), findsWidgets);
    expect(detailText('Runtime'), findsNothing);
    expect(detailText('Hermes Runtime'), findsNothing);
    expect(detailText('诊断信息'), findsOneWidget);
    expect(detailText('DID'), findsOneWidget);
    expect(detailText('did:agent:daemon'), findsWidgets);
    expect(detailText('平台'), findsOneWidget);
    expect(detailText('linux-arm64'), findsOneWidget);
    expect(detailText('服务'), findsNothing);
    expect(detailText('systemd_user'), findsNothing);
    expect(detailText('错误代码'), findsNothing);
    expect(detailText('gateway_error'), findsNothing);
    expect(detailText('诊断摘要'), findsNothing);
    expect(detailText('gateway timeout'), findsOneWidget);
    expect(detailText('运行器'), findsNothing);
    expect(detailText('queue=3'), findsNothing);

    await tester.tap(find.text('查看更多'));
    await tester.pumpAndSettle();

    expect(detailText('服务'), findsOneWidget);
    expect(detailText('systemd_user'), findsOneWidget);
    expect(detailText('错误代码'), findsOneWidget);
    expect(detailText('gateway_error'), findsOneWidget);
    expect(detailText('运行器'), findsOneWidget);
    expect(detailText('queue=3'), findsOneWidget);
  });

  testWidgets('active runtime run is reflected in shared agent status UI', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        const AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
          recentRuns: <AgentRunStatus>[
            AgentRunStatus(
              runId: 'run_running',
              messageId: 'msg_1',
              runtimeAgentDid: 'did:agent:runtime',
              status: 'running',
            ),
          ],
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hermes · 正在处理'), findsOneWidget);

    await tester.tap(find.text('Hermes').first);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('正在处理'), findsOneWidget);
    expect(find.text('最近 Run'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
  });

  testWidgets('generic CLI runtime card drives shared agent status UI', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime-codex',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'codex',
          handle: 'codex-ui',
          displayName: 'Codex UI',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            diagnosticsSummary: genericCliRuntimeCardDiagnostics(
              lifecycleState: 'needs_setup',
              setupReady: false,
            ),
          ),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime-queued',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'claude-code',
          handle: 'claude-queue',
          displayName: 'Claude Queue',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            lastSeenAt: DateTime.now().toUtc(),
            diagnosticsSummary: genericCliRuntimeCardDiagnostics(
              lifecycleState: 'queued',
              driverId: 'claude-code',
              queueState: 'queued',
              queuedCount: 1,
              nextAction: 'wait_for_run_slot',
            ),
          ),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Codex · 需要配置'), findsOneWidget);
    expect(find.text('Claude Code · 正在处理'), findsOneWidget);

    await tester.tap(find.text('Codex UI').first);
    await tester.pumpAndSettle();

    expect(find.text('需要配置'), findsOneWidget);
    expect(find.textContaining('route_'), findsNothing);
    expect(find.textContaining('native_session'), findsNothing);
    expect(find.textContaining('/Users/'), findsNothing);
  });

  testWidgets('agent detail keeps diagnostics summary visible without data', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'registering'),
        ),
        AgentSummary(
          agentDid: 'did:agent:offline-daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-offline',
          displayName: '离线代理',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'offline'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'awiki-agent-hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final context = tester.element(find.byType(AgentsWorkspacePage));
    final container = ProviderScope.containerOf(context);

    expect(find.text('诊断信息'), findsOneWidget);
    expect(find.text('代理尚未完成状态上报。'), findsNothing);

    container.read(agentsProvider.notifier).select('did:agent:offline-daemon');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('诊断信息'), findsOneWidget);
    expect(find.text('代理离线，暂时无法获取最新诊断。'), findsNothing);

    container.read(agentsProvider.notifier).select('did:agent:runtime');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('诊断信息'), findsOneWidget);
    expect(find.text('暂无异常诊断信息。'), findsNothing);
  });

  testWidgets('runtime detail shows latest run status with redacted error', (
    tester,
  ) async {
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'awiki-agent-hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: const AgentLatestStatus(status: 'ready'),
          recentRuns: <AgentRunStatus>[
            AgentRunStatus(
              runId: 'run_failed_latest',
              messageId: 'msg_1',
              runtimeAgentDid: 'did:agent:runtime',
              status: 'failed',
              updatedAt: DateTime.parse('2026-06-03T09:02:00Z'),
              lastErrorCode: 'hermes_error',
              lastErrorSummary:
                  'failed in /Users/alice/.awiki/logs/full.log token=secret',
            ),
          ],
        ),
      ];

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近 Run'), findsOneWidget);
    expect(find.text('run_failed_latest'), findsOneWidget);
    expect(find.text('failed'), findsWidgets);
    expect(find.textContaining('/Users/alice'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('<path>'), findsOneWidget);
    expect(find.textContaining('<redacted>'), findsOneWidget);
  });

  testWidgets('rename and delete are reachable from detail pane', (
    tester,
  ) async {
    final control = FakeAgentControlService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('改名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('agent-rename-field')), '我的代理');
    await tester.tap(find.text('保存').last);
    await tester.pumpAndSettle();
    expect(control.lastRenamedAgentDid, 'did:agent:daemon');
    expect(control.lastDisplayName, '我的代理');

    await tester.tap(find.text('删除代理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(control.lastDeletedDaemonDid, 'did:agent:daemon');
    expect(control.lastUnboundAgentDid, isNull);
    expect(find.text('删除中'), findsWidgets);
    expect(find.text('删除请求已发送，正在等待代理同步。'), findsOneWidget);
  });

  testWidgets('install command opens a compact host-install dialog', (
    tester,
  ) async {
    final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 2));
    final control = FakeAgentControlService()
      ..nextInstallCommand = InstallCommand(
        token: AgentRegistrationToken(
          token: 'fresh-token',
          expiresAt: expiresAt,
        ),
        command:
            'curl -fsSL https://awiki.info/daemon/install.sh | sh -s -- --token fresh-token --base-url https://awiki.info',
        fallbackCommand:
            'awiki-deamon install --token fresh-token --base-url https://awiki.info',
        installerUrl: 'https://awiki.info/daemon/install.sh',
        cleanupUrl: 'https://awiki.info/daemon/cleanup.sh',
        cleanupCommand: 'curl -fsSL https://awiki.info/daemon/cleanup.sh | sh',
        packageUrlTemplate:
            'https://awiki.info/daemon/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me.anpclaw.com',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(CupertinoIcons.plus_circle_fill));
    await tester.pumpAndSettle();

    expect(find.text('到宿主机安装代理'), findsOneWidget);
    expect(find.textContaining('支持的 Agent 类型：Hermes'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.xmark), findsOneWidget);
    expect(find.byKey(const Key('agent-install-copy-button')), findsOneWidget);
    expect(find.text('重新生成命令'), findsNothing);
    expect(find.text('手动下载'), findsNothing);
    expect(find.text('installer'), findsNothing);
    expect(find.text('package'), findsNothing);
    expect(find.text('手动命令'), findsNothing);
    expect(find.byKey(const Key('agent-cleanup-host-toggle')), findsOneWidget);
    expect(find.byKey(const Key('agent-cleanup-host-warning')), findsNothing);
    expect(find.byKey(const Key('agent-cleanup-command-text')), findsNothing);
    expect(
      find.text(
        '有效期至: ${expiresAt.toLocal().hour.toString().padLeft(2, '0')}:${expiresAt.toLocal().minute.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );

    final commandText = tester.widget<CupertinoTextField>(
      find.byKey(const Key('agent-install-command-text')),
    );
    expect(commandText.controller?.text, isNot(contains('\n')));
    expect(commandText.controller?.text, contains('--token'));
    expect(commandText.controller?.text, contains('fresh-token'));
    expect(commandText.maxLines, 1);
    expect(commandText.readOnly, isTrue);
    expect(commandText.enableInteractiveSelection, isTrue);

    await tester.tap(find.byKey(const Key('agent-cleanup-host-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-cleanup-host-warning')), findsOneWidget);
    expect(find.textContaining('此操作不可恢复'), findsOneWidget);
    expect(find.byKey(const Key('agent-cleanup-copy-button')), findsOneWidget);
    final cleanupText = tester.widget<CupertinoTextField>(
      find.byKey(const Key('agent-cleanup-command-text')),
    );
    expect(cleanupText.controller?.text, contains('cleanup.sh'));
    expect(cleanupText.controller?.text, isNot(contains('--yes')));
    expect(cleanupText.maxLines, 1);
    expect(cleanupText.readOnly, isTrue);

    final commandCenter = tester.getCenter(
      find.byKey(const Key('agent-install-command-text')),
    );
    final copyButtonCenter = tester.getCenter(
      find.byKey(const Key('agent-install-copy-button')),
    );
    expect((commandCenter.dy - copyButtonCenter.dy).abs(), lessThan(1));

    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    await tester.pumpAndSettle();
    expect(find.text('到宿主机安装代理'), findsNothing);
  });

  testWidgets(
    'refresh status shows pending state then no-response after timeout',
    (tester) async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          const AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'registering',
              platform: 'darwin-arm64',
            ),
          ),
        ];

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(_agentRefreshButton().first);
      await tester.pump();

      expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
      expect(find.text('刷新中'), findsNothing);
      expect(find.text('刷新状态'), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.textContaining('状态同步仍在等待'), findsWidgets);
      expect(find.text('刷新中'), findsNothing);
    },
  );

  testWidgets('repeated refresh while loading does not send duplicate query', (
    tester,
  ) async {
    final control = _CountingRefreshAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'registering',
            platform: 'darwin-arm64',
          ),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(_agentRefreshButton().first);
    await tester.pump();

    expect(control.refreshCount, 1);
    expect(find.text('10 秒内只能刷新一次。'), findsNothing);
    expect(find.text('刷新中'), findsNothing);
    expect(_agentRefreshButton(), findsNothing);
  });

  testWidgets('refresh can be triggered again after loading clears', (
    tester,
  ) async {
    final control = _CountingRefreshAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-test',
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'registering',
            platform: 'darwin-arm64',
          ),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AgentsWorkspacePage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final context = tester.element(find.byType(AgentsWorkspacePage));
    final container = ProviderScope.containerOf(context);

    await tester.tap(_agentRefreshButton().first);
    await tester.pump();
    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'daemon',
        'daemon_agent_did': 'did:agent:daemon',
        'daemon': <String, Object?>{
          'agent_did': 'did:agent:daemon',
          'status': 'ready',
        },
      },
    );
    await tester.pump(agentStatusRefreshMinimumIndicatorDuration);
    expect(find.text('刷新中'), findsNothing);

    await tester.tap(_agentRefreshButton().first);
    await tester.pump();

    expect(control.refreshCount, 2);
    expect(find.text('刷新中'), findsNothing);
    expect(find.text('10 秒内只能刷新一次。'), findsNothing);
  });

  testWidgets(
    'status payload clears refresh pending state and diagnostics are redacted',
    (tester) async {
      final control = FakeAgentControlService()
        ..agents = <AgentSummary>[
          const AgentSummary(
            agentDid: 'did:agent:daemon',
            kind: AgentKind.daemon,
            handle: 'awiki-daemon-test',
            displayName: '代理 1',
            activeState: 'active',
            latest: AgentLatestStatus(
              status: 'registering',
              platform: 'darwin-arm64',
            ),
          ),
        ];

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      final context = tester.element(find.byType(AgentsWorkspacePage));
      final container = ProviderScope.containerOf(context);

      await tester.tap(_agentRefreshButton().first);
      await tester.pump();
      expect(find.text('刷新中'), findsNothing);

      container.read(agentsProvider.notifier).applyControlPayload(
        <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'status_scope': 'daemon',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'failed',
            'last_error_summary':
                'failed in /Users/alice/.awiki/logs/full.log token=secret',
            'diagnostics_summary': <String, Object?>{
              'api_key': 'sk-secretvalue',
              'log_path': '/tmp/awiki/log.txt',
              'runner': 'Authorization: Bearer abc.def.ghi',
            },
          },
        },
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('刷新中'), findsNothing);
      expect(find.textContaining('/Users/alice'), findsNothing);
      expect(find.textContaining('/tmp/awiki'), findsNothing);
      expect(find.textContaining('secretvalue'), findsNothing);
      expect(find.textContaining('abc.def.ghi'), findsNothing);
      expect(find.textContaining('<path>'), findsWidgets);
      expect(find.text('<redacted>'), findsNothing);

      await tester.tap(find.text('查看更多'));
      await tester.pumpAndSettle();

      expect(find.textContaining('/tmp/awiki'), findsNothing);
      expect(find.textContaining('secretvalue'), findsNothing);
      expect(find.textContaining('abc.def.ghi'), findsNothing);
      expect(find.textContaining('<path>'), findsWidgets);
      expect(find.text('<redacted>'), findsWidgets);
    },
  );
}

Map<String, Object?> _genericCliCapability({
  int schemaVersion = 1,
  List<String> supportedDrivers = const <String>[
    'codex',
    'claude-code',
    'command',
  ],
  List<String> supportedWorkspaceModes = const <String>[
    'route-root',
    'shared-root',
    'worktree-per-task',
  ],
  List<String> supportedSandboxModes = const <String>[
    'read-only',
    'workspace-write',
    'danger-full-access',
  ],
  bool routeSessionSupported = true,
  bool nativeResumeSupported = true,
}) {
  final configSummary =
      genericCliCapabilityDiagnostics['config_summary'] as Map<String, Object?>;
  final base = configSummary['generic_cli'] as Map<String, Object?>;
  return <String, Object?>{
    ...base,
    'capability_schema_version': schemaVersion,
    'supported_drivers': supportedDrivers,
    'supported_workspace_modes': supportedWorkspaceModes,
    'supported_sandbox_modes': supportedSandboxModes,
    'route_session_supported': routeSessionSupported,
    'native_resume_supported': nativeResumeSupported,
  };
}

AgentSummary _daemonWithGenericCliCapability(Map<String, Object?> genericCli) {
  return AgentSummary(
    agentDid: 'did:agent:daemon',
    kind: AgentKind.daemon,
    handle: 'awiki-daemon-test',
    displayName: '代理 1',
    activeState: 'active',
    latest: AgentLatestStatus(
      status: 'ready',
      platform: 'linux-amd64',
      diagnosticsSummary: <String, Object?>{
        'config_summary': <String, Object?>{'generic_cli': genericCli},
      },
    ),
  );
}

Future<_PendingRefreshAgentControlService> _pumpCreateAgentDialog(
  WidgetTester tester, {
  required AgentSummary daemon,
}) async {
  final control = _PendingRefreshAgentControlService()
    ..agents = <AgentSummary>[daemon];
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: const AgentsWorkspacePage(),
      session: const SessionIdentity(
        did: 'did:human:me',
        credentialName: 'default',
        displayName: 'Me',
      ),
      providerOverrides: <Override>[
        agentControlServiceProvider.overrideWithValue(control),
      ],
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('创建 Agent'));
  await tester.pumpAndSettle();

  return control;
}

class _CountingRefreshAgentControlService extends FakeAgentControlService {
  int refreshCount = 0;

  @override
  Future<void> refreshDaemonStatus(
    String daemonAgentDid, {
    String? commandId,
  }) async {
    refreshCount += 1;
    await super.refreshDaemonStatus(daemonAgentDid, commandId: commandId);
  }
}

class _PendingRefreshAgentControlService extends FakeAgentControlService {
  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid, {String? commandId}) {
    lastRefreshedDaemonDid = daemonAgentDid;
    return Future<void>.value();
  }
}

class _CountingListAgentControlService extends FakeAgentControlService {
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listAgentsCalls += 1;
    return super.listAgents(includeInactive: includeInactive);
  }
}

class _SequencedListAgentControlService extends FakeAgentControlService {
  _SequencedListAgentControlService(this.responses);

  final List<List<AgentSummary>> responses;
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listAgentsCalls += 1;
    final index = (listAgentsCalls - 1).clamp(0, responses.length - 1);
    return responses[index];
  }
}

class _FailingListAgentControlService extends FakeAgentControlService {
  bool failList = true;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    if (failList) {
      throw StateError('agent inventory failed');
    }
    return agents;
  }
}

class _SeededAgentsController extends AgentsController {
  _SeededAgentsController(super.ref, AgentsState initialState) {
    state = initialState;
  }
}

class _AgentsWorkspaceToggleHost extends StatefulWidget {
  const _AgentsWorkspaceToggleHost();

  @override
  State<_AgentsWorkspaceToggleHost> createState() =>
      _AgentsWorkspaceToggleHostState();
}

class _AgentsWorkspaceToggleHostState
    extends State<_AgentsWorkspaceToggleHost> {
  bool _showAgents = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        CupertinoButton(
          key: Key(
            _showAgents ? 'hide-agents-workspace' : 'show-agents-workspace',
          ),
          onPressed: () => setState(() => _showAgents = !_showAgents),
          child: Text(_showAgents ? '隐藏智能体' : '显示智能体'),
        ),
        Expanded(
          child: _showAgents
              ? const AgentsWorkspacePage()
              : const SizedBox(key: Key('agents-workspace-placeholder')),
        ),
      ],
    );
  }
}

Finder _agentRefreshButton() => find.descendant(
  of: find.byTooltip('刷新状态'),
  matching: find.byIcon(CupertinoIcons.refresh),
);
