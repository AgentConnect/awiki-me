import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
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
    expect(find.text('创建 Hermes'), findsOneWidget);
    expect(find.text('升级'), findsNothing);
    expect(find.text('安装命令'), findsNothing);
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
      container
          .read(conversationListProvider)
          .conversations
          .any((item) => item.targetDid == 'did:agent:runtime'),
      isTrue,
    );

    await tester.tap(find.text('重置 Session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置').last);
    await tester.pumpAndSettle();
    expect(control.lastResetDaemonDid, 'did:agent:daemon');
    expect(control.lastResetRuntimeDid, 'did:agent:runtime');

    await tester.tap(find.text('重试 Run'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), 'run_123');
    await tester.tap(find.text('重试').last);
    await tester.pumpAndSettle();
    expect(control.lastRetryRunId, 'run_123');
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

    expect(find.text('Daemon · 1 个 Agent · ready'), findsNWidgets(2));
    expect(find.text('hermes · ready'), findsNWidgets(2));

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
    expect(find.text('did:agent:daemon:b'), findsWidgets);
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
    expect(detailText('failed'), findsWidgets);
    expect(detailText('Runtime'), findsOneWidget);
    expect(detailText('Hermes Runtime'), findsOneWidget);
    expect(detailText('ready'), findsWidgets);
    expect(detailText('高级诊断'), findsOneWidget);
    expect(detailText('DID'), findsOneWidget);
    expect(detailText('did:agent:daemon'), findsWidgets);
    expect(detailText('platform'), findsOneWidget);
    expect(detailText('linux-arm64'), findsOneWidget);
    expect(detailText('service'), findsOneWidget);
    expect(detailText('systemd_user'), findsOneWidget);
    expect(detailText('error'), findsOneWidget);
    expect(detailText('gateway_error'), findsOneWidget);
    expect(detailText('诊断摘要'), findsOneWidget);
    expect(detailText('gateway timeout'), findsOneWidget);
    expect(detailText('runner'), findsOneWidget);
    expect(detailText('queue=3'), findsOneWidget);
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
    await tester.enterText(find.byType(CupertinoTextField), '我的代理');
    await tester.tap(find.text('保存'));
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
            'curl -fsSL https://awiki.ai/daemon/install.sh | sh -s -- --token fresh-token --base-url https://awiki.ai',
        fallbackCommand:
            'awiki-deamon install --token fresh-token --base-url https://awiki.ai',
        installerUrl: 'https://awiki.ai/daemon/install.sh',
        packageUrlTemplate:
            'https://awiki.ai/daemon/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
      );

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

    await tester.tap(find.byIcon(CupertinoIcons.plus_circle_fill));
    await tester.pumpAndSettle();

    expect(find.text('到宿主机安装代理'), findsOneWidget);
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

      await tester.tap(_agentRefreshButton().first);
      await tester.pump();

      expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
      expect(find.text('刷新中'), findsNothing);
      expect(find.text('刷新状态'), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text('未收到代理响应'), findsWidgets);
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
    await tester.pumpAndSettle();

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
    await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();

      expect(find.text('刷新中'), findsNothing);
      expect(find.textContaining('/Users/alice'), findsNothing);
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

Finder _agentRefreshButton() => find.byIcon(CupertinoIcons.refresh);
