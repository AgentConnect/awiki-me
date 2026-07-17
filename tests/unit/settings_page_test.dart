import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('设置页导出身份凭证显示暂未实现普通提示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.text('导出身份凭证'), findsOneWidget);

    await tester.tap(find.text('导出身份凭证'));
    await tester.pump();

    expect(gateway.exportCalls, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.danger, isFalse);
    expect(feedback?.message.id, 'featureNotImplemented');
  });

  testWidgets('设置页未登录时禁用凭证导出和删除入口', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const SettingsPage(), gateway: gateway),
    );

    expect(find.text('当前暂无可导出的登录凭证'), findsOneWidget);
    expect(find.text('退出并删除当前登录凭证'), findsOneWidget);

    await tester.tap(find.text('导出身份凭证'));
    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pump();

    expect(gateway.exportCalls, 0);
    expect(gateway.deleteLocalCredentialCalls, 0);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  });

  testWidgets('设置页退出并删除当前凭证会删除本地凭证而不显示未实现错误', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    gateway.localCredentials = const <SessionIdentity>[session];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.text('退出并删除当前凭证'), findsOneWidget);
    expect(find.text('删除本地凭证：default'), findsOneWidget);

    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pumpAndSettle();

    expect(find.textContaining('将退出当前登录，并删除本地凭证 "default"'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );

    await tester.tap(find.text('退出并删除'));
    await tester.pumpAndSettle();

    expect(gateway.deleteLocalCredentialCalls, 1);
    expect(gateway.logoutCalls, 0);
    expect(container.read(uiFeedbackProvider), isNull);
  });

  testWidgets('Mac 嵌入式设置页退出登录后不会关闭根页面', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    gateway.localCredentials = const <SessionIdentity>[session];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(embedded: true),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录').last);
    await tester.pumpAndSettle();

    expect(gateway.logoutCalls, 1);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('Mac 嵌入式设置页退出并删除凭证后不会关闭根页面', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    gateway.localCredentials = const <SessionIdentity>[session];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(embedded: true),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.byType(SettingsPage), findsOneWidget);

    await tester.tap(find.text('退出并删除当前凭证'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出并删除'));
    await tester.pumpAndSettle();

    expect(gateway.deleteLocalCredentialCalls, 1);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('设置页隐藏更新日志下载更新和消息推送入口', (tester) async {
    await tester.pumpWidget(buildLocalizedTestApp(home: const SettingsPage()));

    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('查看更新日志'), findsNothing);
    expect(find.text('下载更新'), findsNothing);
    expect(find.text('立即更新'), findsNothing);
    expect(find.text('消息推送通知'), findsNothing);
  });

  testWidgets('设置页检查更新显示暂未实现普通提示', (tester) async {
    final updateService = FakeUpdateService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        updateService: updateService,
      ),
    );

    await tester.tap(find.text('检查更新'));
    await tester.pump();

    expect(updateService.checkForUpdatesCalls, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.danger, isFalse);
    expect(feedback?.message.id, 'featureNotImplemented');
  });

  testWidgets('设置页展示语言设置并支持切换选项', (tester) async {
    final localePreferenceService = FakeLocalePreferenceService();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        localeMode: AppLocaleMode.system,
        localePreferenceService: localePreferenceService,
      ),
    );

    expect(find.text('语言'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);

    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('取消'), findsNothing);

    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
    expect(localePreferenceService.saveCalls, 1);
    expect(await localePreferenceService.loadMode(), AppLocaleMode.english);
  });

  testWidgets('设置页可进入 Message Agent 独立设置页并从真实入口启用', (tester) async {
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
              'bootstrap_key_id': 'did:agent:daemon#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
      ];
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Message Agent'), findsOneWidget);
    await tester.tap(find.text('Message Agent'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message-agent-settings-page')),
      findsOneWidget,
    );
    expect(find.text('消息处理 Agent'), findsWidgets);
    expect(find.text('运行 Daemon 1'), findsWidgets);
    expect(find.text('已上报公钥'), findsOneWidget);
    expect(find.text('可启用'), findsWidgets);
    expect(find.textContaining('不会自动发送消息'), findsWidgets);
    expect(find.textContaining('不处理 E2EE 明文'), findsWidgets);

    await tester.tap(find.text('启用消息处理 Agent'));
    await tester.pumpAndSettle();

    expect(identities.lastEnsuredDaemonSubkeySelector, 'default');
    expect(control.lastBootstrapDaemonDid, 'did:agent:daemon');
    expect(control.lastBootstrapControllerDid, 'did:human:me');
    expect(
      control.lastBootstrapDaemonPublicKey?.keyId,
      'did:agent:daemon#key-3',
    );
    expect(find.textContaining('自动回复'), findsNothing);
    expect(find.textContaining('代发'), findsNothing);
  });

  testWidgets('Message Agent feature 关闭时设置入口禁用且不触发授权', (tester) async {
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
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Message Agent'), findsNothing);
    expect(find.text('实验功能未开启'), findsOneWidget);
    expect(find.text('消息处理 Agent'), findsNothing);
    expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
    expect(control.lastBootstrapDaemonDid, isNull);
  });

  testWidgets('Message Agent 设置页缺 bootstrap key 时禁用启用并提示刷新', (tester) async {
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

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
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

    await tester.tap(find.text('Message Agent'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('message-agent-settings-page')),
      findsOneWidget,
    );
    expect(find.text('未就绪'), findsOneWidget);
    expect(find.text('等待刷新状态'), findsOneWidget);
    expect(find.textContaining('尚未上报安全 bootstrap 公钥'), findsOneWidget);

    await tester.tap(find.text('启用消息处理 Agent'));
    await tester.pumpAndSettle();

    expect(identities.lastEnsuredDaemonSubkeySelector, isNull);
    expect(control.lastBootstrapDaemonDid, isNull);
  });

  testWidgets('Message Agent 设置页按当前 Daemon 执行撤销授权', (tester) async {
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon:one',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-one',
          displayName: '运行 Daemon 1',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon:one#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
        AgentSummary(
          agentDid: 'did:agent:message:one',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon:one',
          runtime: 'hermes',
          handle: 'hermes-msg-one',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:daemon:two',
          kind: AgentKind.daemon,
          handle: 'awiki-daemon-two',
          displayName: '运行 Daemon 2',
          activeState: 'active',
          latest: AgentLatestStatus(
            status: 'ready',
            platform: 'linux-amd64',
            diagnosticsSummary: <String, Object?>{
              'bootstrap_key_id': 'did:agent:daemon:two#key-3',
              'bootstrap_public_key_b64u':
                  'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
              'bootstrap_key_algorithm': 'x25519',
            },
          ),
        ),
        AgentSummary(
          agentDid: 'did:agent:message:two',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon:two',
          runtime: 'hermes',
          handle: 'hermes-msg-two',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final identities = FakeIdentityCorePort();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const SettingsPage(),
        session: const SessionIdentity(
          did: 'did:human:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
        ),
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          identityCorePortProvider.overrideWithValue(identities),
          agentImEnabledProvider.overrideWithValue(true),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Message Agent'));
    await tester.pumpAndSettle();
    expect(find.text('当前运行 Daemon：运行 Daemon 1'), findsOneWidget);

    await tester.tap(find.text('运行 Daemon 2').first);
    await tester.pumpAndSettle();
    expect(find.text('当前运行 Daemon：运行 Daemon 2'), findsOneWidget);

    await tester.tap(find.text('撤销 Daemon 消息授权'));
    await tester.pumpAndSettle();
    expect(find.textContaining('签名 DID Document 更新'), findsOneWidget);

    await tester.tap(find.text('撤销授权'));
    await tester.pumpAndSettle();

    expect(control.lastRevokedMessageAgentDaemonDid, 'did:agent:daemon:two');
    expect(control.lastRevokedMessageAgentDid, 'did:agent:message:two');
    expect(identities.lastRevokedDaemonSubkeySelector, isNull);
  });
}
