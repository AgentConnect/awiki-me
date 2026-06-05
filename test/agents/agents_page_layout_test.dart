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
import 'package:flutter/material.dart' show SelectableText;
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
    expect(find.text('刷新状态'), findsOneWidget);
    expect(find.text('创建 Hermes'), findsOneWidget);
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

  testWidgets('rename and unbind are reachable from detail pane', (
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

    await tester.tap(find.text('解绑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('解绑').last);
    await tester.pumpAndSettle();
    expect(control.lastUnboundAgentDid, 'did:agent:daemon');
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

    await tester.tap(find.text('安装命令'));
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

      await tester.tap(find.text('刷新状态'));
      await tester.pump();

      expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');
      expect(find.text('正在刷新状态'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text('未收到代理响应'), findsWidgets);
      expect(find.text('正在刷新状态'), findsNothing);
    },
  );

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

      await tester.tap(find.text('刷新状态'));
      await tester.pump();
      expect(find.text('正在刷新状态'), findsOneWidget);

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

      expect(find.text('正在刷新状态'), findsNothing);
      expect(find.textContaining('/Users/alice'), findsNothing);
      expect(find.textContaining('/tmp/awiki'), findsNothing);
      expect(find.textContaining('secretvalue'), findsNothing);
      expect(find.textContaining('abc.def.ghi'), findsNothing);
      expect(find.textContaining('<path>'), findsWidgets);
      expect(find.text('<redacted>'), findsWidgets);
    },
  );
}
