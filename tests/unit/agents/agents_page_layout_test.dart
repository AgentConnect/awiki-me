import 'dart:async';

import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
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
import 'package:flutter/material.dart'
    show SelectableText, SelectionArea, SelectionContainer;
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

    await tester.tap(find.text('重置 Session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(control.lastResetDaemonDid, 'did:agent:daemon');
    expect(control.lastResetRuntimeDid, 'did:agent:runtime');

    await tester.tap(find.text('重试 Run'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agent-retry-run-field')),
      'run_123',
    );
    await tester.tap(find.text('重试').last);
    await tester.pumpAndSettle();
    expect(control.lastRetryRunId, 'run_123');
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
            latest: AgentLatestStatus(status: 'ready', platform: 'linux-amd64'),
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
      expect(find.text('当前仅支持 Hermes Runtime Agent'), findsOneWidget);
      final nameFieldFinder = find.byKey(const Key('agent-create-name-field'));
      final handleFieldFinder = find.byKey(
        const Key('agent-create-handle-field'),
      );
      final nameField = tester.widget<CupertinoTextField>(nameFieldFinder);
      expect(nameField.controller?.text, 'Hermes2');

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
      expect(control.lastRuntimeCreateHandle, 'my-agent');
      expect(control.lastRuntimeCreateDisplayName, '写作助手');
      expect(control.lastRuntimeCreateClientRequestId, isNotNull);
      expect(find.text('写作助手'), findsWidgets);
      expect(find.text('hermes · 创建状态暂未返回，可刷新查看'), findsOneWidget);
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
    expect(find.text('hermes · 正常'), findsNWidgets(2));

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
    expect(detailText('代理 1'), findsOneWidget);
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

    expect(find.text('hermes · 正在处理'), findsOneWidget);

    await tester.tap(find.text('Hermes').first);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('正在处理'), findsOneWidget);
    expect(find.text('最近 Run'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
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
    await tester.pumpAndSettle();
    expect(control.lastDeletedDaemonDid, 'did:agent:daemon');
    expect(control.lastUnboundAgentDid, isNull);
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
    expect(
      find.text(
        '有效期至: ${expiresAt.toLocal().hour.toString().padLeft(2, '0')}:${expiresAt.toLocal().minute.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );

    final commandText = tester.widget<SelectableText>(
      find.byKey(const Key('agent-install-command-text')),
    );
    expect(commandText.data, contains('\n'));
    expect(commandText.data, contains('--token'));
    expect(commandText.data, contains('fresh-token'));

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

      expect(find.textContaining('未收到代理响应'), findsWidgets);
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

class _CountingRefreshAgentControlService extends FakeAgentControlService {
  int refreshCount = 0;

  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid) async {
    refreshCount += 1;
    await super.refreshDaemonStatus(daemonAgentDid);
  }
}

class _PendingRefreshAgentControlService extends FakeAgentControlService {
  final Completer<void> _pendingRefresh = Completer<void>();

  @override
  Future<void> refreshDaemonStatus(String daemonAgentDid) {
    lastRefreshedDaemonDid = daemonAgentDid;
    return _pendingRefresh.future;
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

Finder _agentRefreshButton() => find.byIcon(CupertinoIcons.refresh);
