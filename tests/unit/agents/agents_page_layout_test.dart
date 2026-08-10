import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/application/agent/agent_control_status_store.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/agent/skill_onboarding_instruction.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/ports/skill_onboarding_port.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/agent_status_indicator.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/agents/skill_onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  for (final scenario
      in <
        ({String label, Size size, Key layoutKey, double dotSize, bool compact})
      >[
        (
          label: '移动端',
          size: const Size(390, 844),
          layoutKey: const Key('agents-compact-layout'),
          dotSize: 8,
          compact: true,
        ),
        (
          label: '桌面端',
          size: const Size(1200, 900),
          layoutKey: const Key('agents-expanded-layout'),
          dotSize: 9 * AwikiDisplayScale.layoutBaseline,
          compact: false,
        ),
      ]) {
    testWidgets('${scenario.label}智能体列表按对应布局展示状态圆点', (tester) async {
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: 'did:agent:daemon:status-layout',
            kind: AgentKind.daemon,
            displayName: 'Layout Daemon',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: 'did:agent:runtime:status-layout',
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon:status-layout',
            runtime: 'hermes',
            displayName: 'Layout Agent',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      tester.view.physicalSize = scenario.size;
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

      expect(find.byKey(scenario.layoutKey), findsOneWidget);
      if (scenario.label == '移动端') {
        final compactSurface = tester.widget<DecoratedBox>(
          find.byKey(const Key('agents-compact-layout')),
        );
        expect(
          (compactSurface.decoration as BoxDecoration).color,
          AwikiMeColors.surface,
        );
      }
      _expectAgentListStatusAnchoredToIcon(
        tester,
        agentDid: 'did:agent:daemon:status-layout',
        title: 'Layout Daemon',
        expectedDotSize: scenario.dotSize,
        compact: scenario.compact,
      );
      _expectAgentListStatusAnchoredToIcon(
        tester,
        agentDid: 'did:agent:runtime:status-layout',
        title: 'Layout Agent',
        expectedDotSize: scenario.dotSize,
        compact: scenario.compact,
      );
      final runtimeAnchor = find.byKey(
        const Key('agent-list-status-anchor-did:agent:runtime:status-layout'),
      );
      expect(
        find.descendant(of: runtimeAnchor, matching: find.byType(AvatarBadge)),
        scenario.compact ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('compact Agent list renders Daemon runtime tree geometry', (
    tester,
  ) async {
    const daemonDid = 'did:agent:daemon:compact-tree';
    const codexDid = 'did:agent:runtime:compact-tree-codex';
    const hermesDid = 'did:agent:runtime:compact-tree-hermes';
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          displayName: 'Local Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: codexDid,
          kind: AgentKind.runtime,
          daemonAgentDid: daemonDid,
          runtime: 'codex',
          displayName: 'Codex UI',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: hermesDid,
          kind: AgentKind.runtime,
          daemonAgentDid: daemonDid,
          runtime: 'hermes',
          displayName: 'Hermes UI',
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

    final vertical = find.byKey(const Key('agent-tree-vertical-$daemonDid'));
    final daemonIcon = find.byKey(const Key('agent-list-kind-icon-$daemonDid'));
    final daemonTile = find.byKey(const Key('agent-list-tile-$daemonDid'));
    final installRow = find.byKey(const Key('agents-install-daemon-row'));
    final header = find.byKey(const Key('agents-compact-list-header'));
    final section = find.byKey(const Key('agents-compact-section-header'));
    final listPane = tester.widget<ColoredBox>(
      find.byKey(const Key('agents-list-pane')),
    );

    expect(vertical, findsOneWidget);
    expect(daemonIcon, findsOneWidget);
    expect(
      find.descendant(of: daemonIcon, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
    expect(tester.getSize(daemonTile).height, closeTo(65, 0.1));
    expect(tester.getSize(installRow).height, closeTo(56, 0.1));
    expect(tester.getRect(header), const Rect.fromLTWH(0, 0, 390, 64));
    final compactTitle = tester.widget<Text>(
      find.descendant(of: header, matching: find.text('智能体')),
    );
    expect(compactTitle.style?.fontSize, 16);
    expect(compactTitle.style?.fontWeight, FontWeight.w600);
    expect(compactTitle.style?.height, 1.25);
    expect(tester.getRect(section), const Rect.fromLTWH(0, 64, 390, 60));
    expect(listPane.color, AwikiMeColors.background);
    final sectionSurface = tester.widget<DecoratedBox>(
      find.descendant(of: section, matching: find.byType(DecoratedBox)),
    );
    final sectionDecoration = sectionSurface.decoration as BoxDecoration;
    expect(sectionDecoration.color, AwikiMeColors.surface);
    expect(
      (sectionDecoration.border! as Border).bottom.color,
      AwikiMeColors.border,
    );
    expect(
      tester.getCenter(find.byKey(const Key('agents-more-actions-button'))).dx,
      closeTo(300, 1.5),
    );
    expect(
      tester
          .getCenter(find.byKey(const Key('agents-install-daemon-button')))
          .dx,
      closeTo(356, 1.5),
    );
    expect(tester.getRect(daemonTile).top, closeTo(124, 0.1));
    expect(tester.getTopLeft(find.text('我的智能体')).dx, closeTo(20, 0.1));
    expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
    expect(
      tester.widget<Container>(vertical).color,
      AwikiMePalette.navigationBorder,
    );

    final verticalRect = tester.getRect(vertical);
    final runtimeCenters = <double>[];
    for (final runtimeDid in <String>[codexDid, hermesDid]) {
      final tile = find.byKey(Key('agent-list-tile-$runtimeDid'));
      final branch = find.byKey(Key('agent-tree-branch-$runtimeDid'));
      final icon = find.byKey(Key('agent-list-kind-icon-$runtimeDid'));
      final branchRect = tester.getRect(branch);
      final iconRect = tester.getRect(icon);

      expect(branch, findsOneWidget);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: branch, matching: find.byType(ColoredBox)),
            )
            .color,
        AwikiMePalette.navigationBorder,
      );
      expect(tester.getSize(tile).height, closeTo(75.5, 0.1));
      expect(branchRect.left, closeTo(verticalRect.center.dx, 0.6));
      expect(branchRect.right, closeTo(iconRect.left, 0.6));
      expect(branchRect.center.dy, closeTo(iconRect.center.dy, 0.6));
      runtimeCenters.add(iconRect.center.dy);
    }
    expect(
      tester.getRect(find.byKey(const Key('agent-list-tile-$codexDid'))).top,
      closeTo(189, 0.1),
    );
    expect(
      tester.getRect(find.byKey(const Key('agent-list-tile-$hermesDid'))).top,
      closeTo(264.5, 0.1),
    );
    expect(tester.getRect(installRow).top, closeTo(340, 0.1));
    final daemonChevron = find.descendant(
      of: daemonTile,
      matching: find.byIcon(CupertinoIcons.chevron_right),
    );
    expect(390 - tester.getRect(daemonChevron).right, closeTo(24.7, 1));
    expect(verticalRect.top, lessThan(runtimeCenters.first));
    expect(verticalRect.bottom, greaterThan(runtimeCenters.last));
  });

  testWidgets('创建中的智能体同样在 metadata 行前展示状态圆点', (tester) async {
    const daemonDid = 'did:agent:daemon:pending-layout';
    const requestId = 'pending-layout-request';
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
          agentsProvider.overrideWith(
            (ref) => _NoopSeededAgentsController(
              ref,
              AgentsState(
                agents: const <AgentSummary>[
                  AgentSummary(
                    agentDid: daemonDid,
                    kind: AgentKind.daemon,
                    displayName: 'Pending Daemon',
                    activeState: 'active',
                    latest: AgentLatestStatus(status: 'ready'),
                  ),
                ],
                pendingRuntimeCreations: <PendingRuntimeCreation>[
                  PendingRuntimeCreation(
                    requestId: requestId,
                    daemonAgentDid: daemonDid,
                    handle: 'pending-agent',
                    displayName: 'Pending Agent',
                    runtime: 'hermes',
                    createdAt: DateTime(2026, 7, 28, 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final anchor = find.byKey(
      const Key('agent-list-status-anchor-pending-$requestId'),
    );
    final dot = anchor;
    expect(anchor, findsOneWidget);
    expect(dot, findsOneWidget);
    expect(tester.widget<AgentStatusDot>(dot).size, 8);
    expect(
      tester.getCenter(dot).dy,
      greaterThan(tester.getRect(find.text('Pending Agent')).bottom),
    );
  });

  testWidgets('正式 Runtime 接管创建投影后列表只显示一个智能体', (tester) async {
    const daemonDid = 'did:agent:daemon:pending-overlap';
    const runtimeDid = 'did:agent:runtime:pending-overlap';
    const requestId = 'pending-overlap-request';
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
          agentsProvider.overrideWith(
            (ref) => _NoopSeededAgentsController(
              ref,
              AgentsState(
                agents: const <AgentSummary>[
                  AgentSummary(
                    agentDid: daemonDid,
                    kind: AgentKind.daemon,
                    displayName: 'Overlap Daemon',
                    activeState: 'active',
                    latest: AgentLatestStatus(status: 'ready'),
                  ),
                  AgentSummary(
                    agentDid: runtimeDid,
                    kind: AgentKind.runtime,
                    daemonAgentDid: daemonDid,
                    runtime: 'hermes',
                    handle: 'overlap-agent',
                    displayName: 'Overlap Agent',
                    activeState: 'active',
                    latest: AgentLatestStatus(status: 'ready'),
                  ),
                ],
                pendingRuntimeCreations: <PendingRuntimeCreation>[
                  PendingRuntimeCreation(
                    requestId: requestId,
                    daemonAgentDid: daemonDid,
                    handle: 'OVERLAP-AGENT',
                    displayName: 'Overlap Agent',
                    runtime: 'hermes',
                    createdAt: DateTime(2026, 7, 30, 12),
                    state: PendingRuntimeCreationState.waitingForStatus,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final listPane = find.byKey(const Key('agents-list-pane'));
    expect(
      find.byKey(const Key('agent-list-tile-$runtimeDid')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: listPane, matching: find.text('Overlap Agent')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-list-status-anchor-pending-$requestId')),
      findsNothing,
    );
    expect(find.textContaining('创建状态暂未返回'), findsOneWidget);
  });

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
    expect(find.byIcon(CupertinoIcons.refresh), findsWidgets);
    expect(find.text('创建 Agent'), findsOneWidget);
    expect(find.text('升级'), findsNothing);
    expect(find.text('安装命令'), findsNothing);
  });

  testWidgets('expanded Agent header keeps refresh outside plus menu', (
    tester,
  ) async {
    final control = _CountingListAgentControlService();
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

    final header = find.byKey(const Key('agents-expanded-list-header'));
    final menuButton = find.byKey(const Key('agents-more-actions-button'));
    final refreshButton = find.byKey(const Key('agents-list-refresh-button'));
    expect(header, findsOneWidget);
    expect(menuButton, findsOneWidget);
    expect(refreshButton, findsOneWidget);
    expect(find.byTooltip('刷新智能体列表'), findsOneWidget);
    expect(
      find.descendant(
        of: menuButton,
        matching: find.byIcon(CupertinoIcons.plus),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('agent-skill-onboarding-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('agents-install-daemon-button')), findsNothing);

    final listCallsBeforeRefresh = control.listAgentsCalls;
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();

    expect(control.listAgentsCalls, listCallsBeforeRefresh + 1);

    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    final skillAction = find.byKey(const Key('agent-skill-onboarding-button'));
    final installAction = find.byKey(const Key('agents-install-daemon-button'));
    expect(skillAction, findsOneWidget);
    expect(refreshButton, findsOneWidget);
    expect(installAction, findsOneWidget);
    expect(find.text('生成 Skill Agent 安装指令'), findsOneWidget);
    expect(find.text('刷新智能体列表'), findsNothing);
    expect(
      find.descendant(of: installAction, matching: find.text('到宿主机安装代理')),
      findsOneWidget,
    );
    expect(
      tester.getRect(skillAction).top,
      greaterThan(tester.getRect(menuButton).bottom),
    );
    expect(tester.getRect(skillAction).width, inInclusiveRange(230, 250));
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

  testWidgets('agents workspace is disabled for non-primary tenants', (
    tester,
  ) async {
    final control = _CountingListAgentControlService();

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

    expect(find.text('当前租户暂不支持智能体'), findsOneWidget);
    expect(find.text('暂无代理'), findsNothing);
    expect(find.byTooltip('刷新智能体列表'), findsNothing);
    expect(control.listAgentsCalls, 0);
  });

  testWidgets('agents workspace defers auto sync stop during dispose', (
    tester,
  ) async {
    late _NoopSeededAgentsController controller;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const _AgentsWorkspaceToggleHost(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentsProvider.overrideWith((ref) {
            controller = _NoopSeededAgentsController(
              ref,
              const AgentsState(
                inventoryAutoSyncReason:
                    AgentInventoryAutoSyncReason.backgroundDiscovery,
              ),
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_AgentsWorkspaceToggleHost)),
    );
    expect(
      identical(container.read(agentsProvider.notifier), controller),
      true,
    );
    expect(container.read(agentsProvider).isAutoSyncingInventory, isTrue);

    await tester.tap(find.byKey(const Key('hide-agents-workspace')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AgentsWorkspacePage), findsNothing);
    expect(container.read(agentsProvider).isAutoSyncingInventory, isFalse);
    expect(tester.takeException(), isNull);
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
    expect(find.textContaining('当前账号还没有可用的 Daemon'), findsOneWidget);
    expect(find.text('正在等待宿主机完成 Daemon 安装，完成后会自动出现。'), findsNothing);
    expect(find.byIcon(CupertinoIcons.desktopcomputer), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.byTooltip('刷新智能体列表'), findsOneWidget);

    await tester.tap(find.byKey(const Key('agents-list-refresh-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(control.listAgentsCalls, greaterThanOrEqualTo(2));
    expect(find.text('Daemon 1'), findsWidgets);
    expect(find.text('暂无代理'), findsNothing);
  });

  testWidgets(
    'empty agents workspace shows install waiting state only for install flow',
    (tester) async {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:human:me',
            credentialName: 'default',
            displayName: 'Me',
          ),
          providerOverrides: <Override>[
            agentsProvider.overrideWith((ref) {
              return _NoopSeededAgentsController(
                ref,
                const AgentsState(
                  inventoryAutoSyncReason:
                      AgentInventoryAutoSyncReason.daemonInstall,
                ),
              );
            }),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('暂无代理'), findsOneWidget);
      expect(find.text('正在等待宿主机完成 Daemon 安装，完成后会自动出现。'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.clock), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    },
  );

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

  testWidgets('stale daemon upgrade snapshot does not show upgrade action', (
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
          daemonEffectiveStatus: DaemonEffectiveStatus(
            controlState: 'stale',
            primaryStatus: 'offline',
            lastReportedStatus: 'needs_upgrade',
            upgradeAvailable: true,
            actionable: false,
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

    expect(find.text('离线'), findsWidgets);
    expect(find.text('升级'), findsNothing);
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
            daemonEffectiveStatus: DaemonEffectiveStatus(
              controlState: 'online',
              primaryStatus: 'ready',
              lastReportedStatus: 'ready',
              actionable: true,
            ),
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

      expect(find.byKey(const Key('agents-compact-layout')), findsOneWidget);
      expect(find.byKey(const Key('agents-compact-list')), findsOneWidget);
      expect(
        find.byKey(const Key('agents-compact-list-header')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('agents-compact-detail')), findsNothing);
      expect(find.byKey(const Key('agents-expanded-layout')), findsNothing);
      expect(find.text('创建 Agent'), findsNothing);
      expect(find.text('Hermes'), findsOneWidget);

      await tester.tap(find.text('代理 1').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agents-compact-list')), findsNothing);
      expect(find.byKey(const Key('agents-compact-detail')), findsOneWidget);
      expect(
        find.byKey(const Key('agents-compact-back-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('agents-persistent-detail-header')),
        findsNothing,
      );
      expect(find.text('创建 Agent'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agents-compact-back-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('agents-compact-list')), findsOneWidget);
      expect(find.byKey(const Key('agents-compact-detail')), findsNothing);
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
      expect(find.byKey(const Key('agents-expanded-layout')), findsOneWidget);
      expect(find.byKey(const Key('agents-compact-layout')), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const Key('agents-expanded-list-pane')))
            .width,
        272,
      );
      expect(
        find.byKey(const Key('agents-expanded-list-header')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('agents-expanded-list-header')))
            .height,
        closeTo(56 * AwikiDisplayScale.layoutBaseline, 0.01),
      );
      expect(
        find.byKey(const Key('agents-persistent-detail-header')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('agents-expanded-detail-pane')),
        findsOneWidget,
      );
      expect(find.text('创建 Agent'), findsOneWidget);

      final widthBeforeDrag = tester
          .getSize(find.byKey(const Key('agents-expanded-list-pane')))
          .width;
      await tester.drag(
        find.byKey(const Key('awiki-pane-divider')),
        const Offset(72, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.byKey(const Key('agents-expanded-list-pane')))
            .width,
        greaterThan(widthBeforeDrag),
      );
    },
  );

  testWidgets('minimum expanded workspace keeps agent actions in bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 600);
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('agents-expanded-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('agents-persistent-detail-header')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

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
            daemonEffectiveStatus: DaemonEffectiveStatus(
              controlState: 'online',
              primaryStatus: 'ready',
              lastReportedStatus: 'ready',
              actionable: true,
            ),
          ),
        ];
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final freshSeenAt = DateTime.now().toUtc().toIso8601String();

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
            agentControlStatusStoreProvider.overrideWithValue(
              _StaticAgentControlStatusStore(
                daemonPayload: <String, Object?>{
                  'schema': AgentControlPayloads.statusSchema,
                  'status_scope': 'daemon',
                  'daemon_agent_did': 'did:agent:daemon',
                  'daemon': <String, Object?>{
                    'agent_did': 'did:agent:daemon',
                    'status': 'ready',
                    'last_seen_at': freshSeenAt,
                  },
                },
              ),
            ),
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
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        'did:agent:runtime': UserProfile(
          did: 'did:agent:runtime',
          displayName: 'Hermes',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'awiki-agent-hermes.awiki.ai',
        ),
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'did:agent:runtime': 'dm:peer-scope:v1:hermes-runtime',
      };
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

    await tester.tap(find.text('Hermes').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开聊天'));
    await tester.pumpAndSettle();
    final opened = tester.widget<ChatView>(find.byType(ChatView)).conversation;
    expect(opened.targetDid, 'did:agent:runtime');
    expect(opened.targetPeer, 'awiki-agent-hermes.awiki.ai');
    expect(opened.conversationId, 'dm:peer-scope:v1:hermes-runtime');

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
            daemonEffectiveStatus: DaemonEffectiveStatus(
              controlState: 'online',
              primaryStatus: 'ready',
              lastReportedStatus: 'ready',
              actionable: true,
            ),
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
      expect(find.text('最终 Handle：@my-agent.awiki.ai'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('agent-access-blacklist-mode')));
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

  testWidgets('personal agent controls are hidden when tenant is unsupported', (
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

    expect(find.text('当前租户暂不支持智能体'), findsOneWidget);
    expect(
      find.byKey(const Key('personal-agent-settings-panel')),
      findsNothing,
    );
    expect(find.text('个人助理'), findsNothing);
    expect(find.text('启用个人助理'), findsNothing);
    expect(find.text('暂停处理消息'), findsNothing);
    expect(find.text('删除个人助理'), findsNothing);
    expect(find.text('撤销 Daemon 消息授权'), findsNothing);
    expect(control.lastBootstrapDaemonDid, isNull);
    expect(find.textContaining('自动回复'), findsNothing);
    expect(find.textContaining('代发'), findsNothing);
  });

  testWidgets(
    'personal agent panel is hidden when daemon lacks bootstrap key',
    (tester) async {
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

      expect(
        find.byKey(const Key('personal-agent-settings-panel')),
        findsNothing,
      );
      expect(find.text('运行 Daemon 内创建 Hermes runtime'), findsNothing);
      expect(find.text('等待刷新状态'), findsOneWidget);
      expect(find.text('启用个人助理'), findsNothing);
      expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
      expect(control.lastBootstrapDaemonDid, isNull);
      expect(find.textContaining('尚未上报安全 bootstrap 公钥'), findsNothing);
    },
  );

  testWidgets(
    'personal agent management panel is hidden with existing runtime',
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
            displayName: 'Hermes Personal Agent',
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
        find.byKey(const Key('personal-agent-settings-panel')),
        findsNothing,
      );
      expect(find.text('个人助理'), findsOneWidget);
      expect(
        find.byKey(const Key('personal-agent-settings-entry-card')),
        findsOneWidget,
      );
      expect(find.text('已创建个人助理'), findsOneWidget);
      expect(find.text('运行 Daemon 1'), findsWidgets);
      expect(find.text('Hermes Personal Agent'), findsWidgets);
      expect(find.text('启用个人助理'), findsNothing);
      expect(find.text('暂停处理消息'), findsNothing);
      expect(find.text('删除个人助理'), findsNothing);
      expect(find.text('撤销 Daemon 消息授权'), findsNothing);
      expect(find.textContaining('自动回复'), findsNothing);
      expect(find.textContaining('代发'), findsNothing);
    },
  );

  testWidgets('create Agent dialog blocks unavailable handle', (tester) async {
    final gateway = FakeAwikiGateway()..handleAlreadyRegistered = true;
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
            "curl -fsSL 'https://awiki.info/daemon/install.sh' | "
            "AWIKI_DAEMON_BASE_URL='https://awiki.info' "
            "AWIKI_DAEMON_DOWNLOAD_BASE_URLS='https://awiki.info/daemon' "
            "sh -s -- --token 'fresh-token'",
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

    await _openExpandedAgentActions(tester);
    await tester.tap(find.byKey(const Key('agents-install-daemon-button')));
    await tester.pumpAndSettle();

    expect(find.text('到宿主机安装代理'), findsWidgets);
    expect(find.textContaining('支持的 Agent 类型：Hermes'), findsWidgets);
    expect(find.byIcon(CupertinoIcons.xmark), findsOneWidget);
    expect(find.byKey(const Key('agent-install-copy-button')), findsOneWidget);
    expect(find.text('重新生成命令'), findsNothing);
    expect(find.text('手动下载'), findsNothing);
    expect(find.text('installer'), findsNothing);
    expect(find.text('package'), findsNothing);
    expect(find.text('手动命令'), findsNothing);
    expect(find.byKey(const Key('agent-cleanup-host-toggle')), findsOneWidget);
    expect(find.text('需要清理当前电脑上的旧 Daemon 残留？'), findsOneWidget);
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
    expect(find.textContaining('不会从 AWiki 账号中移除'), findsOneWidget);
    expect(find.textContaining('从账号移除'), findsOneWidget);
    expect(find.textContaining('此操作不可恢复'), findsOneWidget);
    expect(find.byKey(const Key('agent-cleanup-copy-button')), findsOneWidget);
    expect(find.bySemanticsLabel('复制本机清理命令'), findsOneWidget);
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
    expect(find.byKey(const Key('agent-install-command-text')), findsNothing);
    expect(find.text('到宿主机安装代理'), findsNWidgets(2));
  });

  testWidgets(
    'skill onboarding copies a scoped prompt without managing inventory',
    (tester) async {
      final control = FakeAgentControlService();
      final skillPort = _SkillOnboardingPortStub();
      final gateway = FakeAwikiGateway()
        ..serverInfo = skillOnboardingTestServerInfo();
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = call.arguments as Map<Object?, Object?>;
            clipboardText = data['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AgentsWorkspacePage(),
          session: const SessionIdentity(
            did: 'did:wba:awiki.info:user:alice',
            credentialName: 'alice',
            displayName: 'Alice',
            handle: 'alice.awiki.info',
          ),
          providerOverrides: <Override>[
            agentControlServiceProvider.overrideWithValue(control),
            awikiEnvironmentConfigProvider.overrideWithValue(
              AwikiEnvironmentConfig(
                baseUrl: 'https://awiki.info',
                didDomain: 'awiki.info',
              ),
            ),
            onboardingSupportServiceProvider.overrideWithValue(
              FakeOnboardingSupportService(gateway),
            ),
            skillOnboardingPortProvider.overrideWithValue(skillPort),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await _openExpandedAgentActions(tester);
      await tester.tap(find.byKey(const Key('agent-skill-onboarding-button')));
      await tester.pumpAndSettle();

      expect(find.text('连接 Skill Agent'), findsOneWidget);
      expect(find.text('alice.awiki.info'), findsOneWidget);
      expect(find.text('skill-widget.awiki.info'), findsOneWidget);
      expect(find.byKey(const Key('agent-skill-copy-button')), findsOneWidget);
      final prompt = tester
          .widget<Text>(find.byKey(const Key('agent-skill-instruction-text')))
          .data!;
      expect(prompt, contains('AWIKI_SKILL_ONBOARDING_V1'));
      expect(prompt, contains('awsk1_widget_secret_value'));
      expect(prompt, isNot(contains('did:wba:awiki.info:user:alice')));
      expect(control.lastInstallCommand, isNull);

      final copyButton = find.byKey(const Key('agent-skill-copy-button'));
      await tester.ensureVisible(copyButton);
      await tester.pumpAndSettle();
      await tester.tap(copyButton);
      await tester.pump();
      expect(clipboardText, prompt);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agent-skill-regenerate-button')));
      await tester.pumpAndSettle();
      expect(skillPort.calls, 2);
      expect(control.lastInstallCommand, isNull);
    },
  );

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
      expect(find.text('刷新状态'), findsOneWidget);

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

class _SkillOnboardingPortStub implements SkillOnboardingPort {
  int calls = 0;

  @override
  Future<SkillOnboardingGrant> issueSkillToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    calls += 1;
    return SkillOnboardingGrant(
      token: 'awsk1_widget_secret_value',
      tokenId: 'agtok_widget_$calls',
      controllerHandle: controllerHandle,
      agentHandle: 'skill-widget.awiki.info',
      serviceOrigin: 'https://awiki.info',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }
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

void _expectAgentListStatusAnchoredToIcon(
  WidgetTester tester, {
  required String agentDid,
  required String title,
  required double expectedDotSize,
  required bool compact,
}) {
  final tile = find.byKey(Key('agent-list-tile-$agentDid'));
  final anchor = find.byKey(Key('agent-list-status-anchor-$agentDid'));
  final indicator = compact
      ? anchor
      : find.descendant(of: anchor, matching: find.byType(AgentStatusDot));
  final titleFinder = find.descendant(of: tile, matching: find.text(title));

  expect(tile, findsOneWidget);
  expect(anchor, findsOneWidget);
  expect(indicator, findsOneWidget);
  expect(tester.widget<AgentStatusDot>(indicator).size, expectedDotSize);
  expect(
    find.descendant(of: tile, matching: find.byType(AgentStatusDot)),
    findsOneWidget,
  );
  if (compact) {
    expect(
      tester.getCenter(indicator).dy,
      greaterThan(tester.getRect(titleFinder).bottom),
    );
  } else {
    _expectBottomRightOverlay(tester, anchor: anchor, indicator: indicator);
    expect(
      tester.getCenter(indicator).dx,
      lessThan(tester.getRect(titleFinder).left),
    );
  }
}

void _expectBottomRightOverlay(
  WidgetTester tester, {
  required Finder anchor,
  required Finder indicator,
}) {
  final anchorRect = tester.getRect(anchor);
  final indicatorCenter = tester.getCenter(indicator);
  expect(indicatorCenter.dx, greaterThan(anchorRect.center.dx));
  expect(indicatorCenter.dy, greaterThan(anchorRect.center.dy));
  expect(indicatorCenter.dx, lessThanOrEqualTo(anchorRect.right + 1));
  expect(indicatorCenter.dy, lessThanOrEqualTo(anchorRect.bottom + 1));
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

class _StaticAgentControlStatusStore implements AgentControlStatusStore {
  const _StaticAgentControlStatusStore({this.daemonPayload});

  final Map<String, Object?>? daemonPayload;

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async {
    return daemonPayload;
  }

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) async {
    return daemonPayload;
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

class _NoopSeededAgentsController extends _SeededAgentsController {
  _NoopSeededAgentsController(super.ref, super.initialState);

  @override
  Future<void> ensureLoaded() => Future<void>.value();
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

Future<void> _openExpandedAgentActions(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('agents-more-actions-button')));
  await tester.pumpAndSettle();
}
