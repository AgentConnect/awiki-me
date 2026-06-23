import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/message_agent_binding_port.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/agent/message_agent_binding.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../unit/test_support.dart' as test_support;
import '../support/fake_app_bootstrap.dart';

const String _messageAgentRunConfigPath =
    '.e2e/message-agent/current/run_config.json';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> conversations,
  ) {
    state = ConversationListState(conversations: conversations);
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  runMessageAgentRealBackendE2e();

  testWidgets('Message Agent full UI enables Hermes runtime and lifecycle', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'test-jwt',
    );
    final harness = createFakeAwikiMeAppHarness(session: session);
    final control =
        harness.bootstrap.agentControlService!
            as test_support.FakeAgentControlService;
    final inventory = _UiAgentInventoryPort(() => control.agents);
    final bindings = _UiMessageAgentBindingPort();
    final identities = _UiIdentityCorePort();
    final messages = _UiMessagingService();
    control.agents = const <AgentSummary>[
      AgentSummary(
        agentDid: 'did:test:daemon:message',
        kind: AgentKind.daemon,
        handle: 'daemon-message',
        displayName: 'Message Daemon',
        activeState: 'active',
        latest: AgentLatestStatus(
          status: 'ready',
          version: '0.5.26',
          platform: 'linux-amd64',
          diagnosticsSummary: <String, Object?>{
            'bootstrap_key_id': 'did:test:daemon:message#key-3',
            'bootstrap_public_key_b64u':
                'CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
            'bootstrap_key_algorithm': 'x25519',
          },
        ),
      ),
      AgentSummary(
        agentDid: 'did:test:agent:message',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:test:daemon:message',
        runtime: 'hermes',
        handle: 'hermes-msg-app-default',
        displayName: 'Hermes Message Agent',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      ),
    ];

    try {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: _copyBootstrapForMessageAgentUiTest(
            harness.bootstrap,
            agentInventoryPort: inventory,
            messageAgentBindingPort: bindings,
            identityCorePort: identities,
            messagingService: messages,
            agentControlService: DefaultAgentControlService(
              inventory: inventory,
              messages: messages,
              messageAgentBindings: bindings,
              identities: identities,
              agentImEnabled: false,
            ),
          ),
          providerOverrides: <Override>[
            ...harness.providerOverrides,
            agentImEnabledProvider.overrideWithValue(true),
          ],
        ),
      );
      await _pumpFrame(tester);

      expect(find.byType(AppShell), findsOneWidget);
      await _tapFirstFound(tester, <Finder>[
        find.bySemanticsIdentifier('e2e-agents-tab'),
        find.bySemanticsLabel('智能体'),
        find.bySemanticsLabel('Agents'),
        find.text('智能体'),
        find.text('Agents'),
      ]);
      await _pumpFrame(tester);

      expect(find.text('Message Daemon'), findsWidgets);
      expect(find.text('消息处理 Agent'), findsOneWidget);
      expect(find.text('运行 Daemon'), findsOneWidget);
      expect(find.text('Hermes'), findsOneWidget);
      expect(find.text('所有可处理会话'), findsOneWidget);
      expect(find.text('0.5.26 · linux-amd64'), findsOneWidget);
      expect(find.text('Hermes message runtime'), findsOneWidget);
      expect(find.text('已上报公钥'), findsOneWidget);
      expect(find.text('启用消息处理 Agent'), findsOneWidget);
      expect(find.text('暂停处理消息'), findsOneWidget);
      expect(find.text('删除消息处理 Agent'), findsOneWidget);
      expect(find.text('撤销 Daemon 消息授权'), findsOneWidget);
      expect(find.textContaining('自动回复'), findsNothing);
      expect(find.textContaining('代发'), findsNothing);

      await tester.tap(find.text('启用消息处理 Agent'));
      await _pumpFrame(tester);

      expect(
        messages.lastIdempotencyKey,
        startsWith('message-agent-bootstrap:'),
      );

      await tester.tap(find.text('暂停处理消息'));
      await _pumpFrame(tester);
      expect(
        find.text('暂停后，消息处理 Agent 不再读取和处理新消息；runtime 和授权仍会保留，可以重新启用。'),
        findsOneWidget,
      );
      await tester.tap(find.text('暂停'));
      await _pumpFrame(tester);
      expect(messages.lastPayload?['command'], 'message_agent.binding.disable');

      await tester.tap(find.text('删除消息处理 Agent'));
      await _pumpFrame(tester);
      expect(
        find.text('删除前会先暂停消息处理，然后归档对应 runtime。Daemon 和授权不会被删除。'),
        findsOneWidget,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byType(CupertinoAlertDialog),
              matching: find.text('删除'),
            )
            .last,
      );
      await _pumpFrame(tester);
      expect(
        messages.payloads.map((payload) => payload['command']),
        contains('runtime.agent.delete'),
      );

      bindings.calls.clear();
      identities.calls.clear();
      messages.resetRecordedPayloads();
      await tester.tap(find.text('撤销 Daemon 消息授权'));
      await _pumpFrame(tester);
      expect(find.textContaining('签名 DID Document 更新'), findsOneWidget);
      await tester.tap(find.text('撤销授权'));
      await _pumpFrame(tester);
      expect(identities.calls, <String>['revoke:did:test:me']);
      expect(bindings.calls, <String>['get_active', 'revoke:binding_1']);
      expect(messages.lastPayload?['command'], 'message_agent.binding.disable');
      expect(
        messages.lastIdempotencyKey,
        'message-agent-revoke:did:test:agent:message',
      );
      final revokeArgs = messages.lastPayload?['args'] as Map<String, Object?>;
      expect(revokeArgs['binding_id'], 'binding_1');
      expect(revokeArgs['message_agent_did'], 'did:test:agent:message');
      expect(revokeArgs['lifecycle_action'], 'revoke');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets(
    'Message Agent full UI recovers runtime result and draft action',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      const session = SessionIdentity(
        did: 'did:test:me',
        credentialName: 'default',
        handle: 'me',
        displayName: 'Me',
        jwtToken: 'test-jwt',
      );
      final conversation = ConversationSummary(
        threadId: 'direct:did:human:bob',
        displayName: 'Bob',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 6, 19, 10, 0),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:human:bob',
      );
      final history = <ChatMessage>[
        ChatMessage(
          localId: 'msg_1',
          remoteId: 'msg_1',
          threadId: conversation.threadId,
          senderDid: 'did:human:bob',
          receiverDid: session.did,
          content: 'hello',
          createdAt: DateTime(2026, 6, 19, 10, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ];
      final harness = createFakeAwikiMeAppHarness(session: session);
      harness.gateway
        ..conversations = <ConversationSummary>[conversation]
        ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
          'did:human:bob': history,
        };
      final control =
          harness.bootstrap.agentControlService!
              as test_support.FakeAgentControlService;
      control.agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: 'Message Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes Message Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

      try {
        await tester.pumpWidget(
          AwikiMeApp(
            bootstrap: harness.bootstrap,
            providerOverrides: <Override>[
              ...harness.providerOverrides,
              conversationListProvider.overrideWith(
                (ref) => _StaticConversationListController(
                  ref,
                  <ConversationSummary>[conversation],
                ),
              ),
            ],
          ),
        );
        await _pumpFrame(tester);

        expect(find.byType(AppShell), findsOneWidget);
        expect(find.text('最近会话'), findsOneWidget);
        await tester.tap(find.text('Bob').first);
        await _pumpFrame(tester);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        container
            .read(chatThreadsProvider.notifier)
            .applyMessageAgentControlPayload(const <String, Object?>{
              'schema': 'awiki.message.sync.v1',
              'sync_type': 'runtime_final',
              'runtime_agent_did': 'did:agent:runtime',
              'run_id': 'run_1',
              'source_message_id': 'msg_1',
              'source_conversation_id': 'direct:did:human:bob',
              'state': 'finished',
              'has_text': true,
              'retention_class': 'hash_only',
            });
        container
            .read(chatThreadsProvider.notifier)
            .applyMessageAgentControlPayload(const <String, Object?>{
              'schema': 'awiki.app.action.v1',
              'action_id': 'act_draft',
              'action': 'message.create_draft',
              'state': 'requires_confirmation',
              'runtime_agent_did': 'did:agent:runtime',
              'run_id': 'run_1',
              'source_message_id': 'msg_1',
              'conversation_id': 'direct:did:human:bob',
              'requires_confirmation': true,
              'args': <String, Object?>{'draft_text': '收到，我会处理。'},
            });
        await _pumpFrame(tester);

        expect(find.text('消息 Agent 已完成处理'), findsOneWidget);
        expect(find.text('消息 Agent 生成了草稿'), findsOneWidget);
        await tester.tap(find.text('使用草稿'));
        await _pumpFrame(tester);

        expect(find.text('草稿已放入输入框'), findsOneWidget);
        expect(harness.gateway.lastSentPayloadPeerDid, 'did:agent:daemon');
        expect(harness.gateway.lastSentPayload?['state'], 'succeeded');
      } finally {
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    },
  );
}

void runMessageAgentRealBackendE2e() {
  testWidgets(
    'Message Agent full UI drives real backend daemon and recovery',
    (tester) async {
      final config = _MessageAgentRealBackendConfig.tryLoad();
      if (config == null || !config.realBackend) {
        return;
      }
      if (!File(config.daemonBinary).existsSync()) {
        fail('daemon binary was not found: ${config.daemonBinary}');
      }
      debugDefaultTargetPlatformOverride = config.targetPlatform;
      await tester.binding.setSurfaceSize(const Size(1400, 900));

      final bootstrap = await AppBootstrap.create(
        environment: config.environment,
        appStateRoot: config.appStateRoot,
      );
      Process? daemon;
      try {
        await tester.pumpWidget(
          AwikiMeApp(
            bootstrap: bootstrap,
            providerOverrides: <Override>[
              agentImEnabledProvider.overrideWithValue(true),
            ],
          ),
        );
        await _pumpFrame(tester);
        expect(find.byType(AppShell), findsOneWidget);

        final session = await _prepareRealAppIdentity(
          bootstrap.onboardingService!,
          config,
        );
        await ProviderScope.containerOf(tester.element(find.byType(AppShell)))
            .read(appRuntimeProvider.notifier)
            .activateSession(session.toLegacySessionIdentity());
        await _pumpFrame(tester);

        final appContainer = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        final install = await _installRealDaemon(
          config: config,
          inventory: appContainer.read(agentInventoryPortProvider),
          controllerDid: session.did,
        );
        daemon = await _startRealDaemon(config: config);
        await _waitForFile(config.daemonReadyFile);

        final bindingPort = appContainer.read(messageAgentBindingPortProvider);
        final agents = appContainer.read(agentsProvider.notifier);
        await _waitForAgentInventoryEntry(
          tester: tester,
          agents: agents,
          agentDid: install.daemonDid,
          handle: install.handle,
        );

        await _tapFirstFound(tester, <Finder>[
          find.bySemanticsIdentifier('e2e-agents-tab'),
          find.bySemanticsLabel('智能体'),
          find.bySemanticsLabel('Agents'),
          find.text('智能体'),
          find.text('Agents'),
        ]);
        agents.select(install.daemonDid);
        await _pumpFrame(tester);

        await _waitForDaemonBootstrapKey(
          tester: tester,
          agents: agents,
          daemonDid: install.daemonDid,
        );
        agents.select(install.daemonDid);
        await _pumpFrame(tester);
        expect(find.text('消息处理 Agent'), findsOneWidget);
        expect(find.text('已上报公钥'), findsOneWidget);
        expect(find.text('可启用'), findsWidgets);
        expect(find.text('启用消息处理 Agent'), findsOneWidget);
        await tester.tap(find.text('启用消息处理 Agent'));
        await _pumpUntil(
          tester,
          () => !ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          ).read(agentsProvider).isActing,
          timeout: const Duration(seconds: 25),
          description: 'message agent enable action to finish',
        );
        final stateAfterEnable = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        ).read(agentsProvider);
        if (stateAfterEnable.error != null) {
          fail(
            'Message Agent enable failed: ${stateAfterEnable.error}. '
            'Raw error: ${stateAfterEnable.debugLastError}. '
            'Agents: ${_agentsDebugSummary(stateAfterEnable)}',
          );
        }

        await _waitForUserServiceBindingActive(
          binding: bindingPort,
          daemonDid: install.daemonDid,
        );
        await agents.load();
        await _pumpFrame(tester);
        expect(find.text('Hermes Message Agent'), findsWidgets);

        final sourceText =
            'message agent ui real backend ${config.runId} ${DateTime.now().millisecondsSinceEpoch}';
        final cliSend = await _runCli(config, <String>[
          '--format',
          'json',
          'msg',
          'send',
          '--to',
          config.appHandle,
          '--text',
          sourceText,
        ]);
        if (cliSend.exitCode != 0) {
          fail('CLI peer send failed: ${cliSend.sanitizedSummary(config)}');
        }

        await _waitForAppHistory(
          messaging: bootstrap.messagingService!,
          thread: AppThreadRef.direct(config.cliHandle),
          expectedText: sourceText,
        );
        await _waitForDaemonRuntimeFinalSent(
          daemonStateRoot: config.daemonStateRoot,
          sourceText: sourceText,
        );
        await _openRealCliConversation(
          tester: tester,
          container: appContainer,
          cliHandle: config.cliHandle,
          sourceText: sourceText,
        );
        await _waitForMessageAgentRuntimeFinalInApp(
          tester: tester,
          sourceText: sourceText,
        );

        await _tapFirstFound(tester, <Finder>[
          find.bySemanticsIdentifier('e2e-agents-tab'),
          find.bySemanticsLabel('智能体'),
          find.bySemanticsLabel('Agents'),
          find.text('智能体'),
          find.text('Agents'),
        ]);
        await _pumpFrame(tester);
        await agents.load();
        agents.select(install.daemonDid);
        await _pumpFrame(tester);
        await tester.tap(find.text('撤销 Daemon 消息授权'));
        await _pumpFrame(tester);
        expect(find.textContaining('签名 DID Document 更新'), findsOneWidget);
        await tester.tap(find.text('撤销授权'));
        await _pumpFrame(tester);
        await _pumpUntil(
          tester,
          () => !ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          ).read(agentsProvider).isActing,
          timeout: const Duration(seconds: 25),
        );
        final stateAfterRevoke = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        ).read(agentsProvider);
        if (stateAfterRevoke.error != null) {
          fail(
            'Message Agent revoke failed: ${stateAfterRevoke.error}. '
            'Raw error: ${stateAfterRevoke.debugLastError}. '
            'Agents: ${_agentsDebugSummary(stateAfterRevoke)}',
          );
        }
        await _waitForUserServiceBindingRevoked(binding: bindingPort);
        await _waitForDaemonBindingRevoked(
          daemonStateRoot: config.daemonStateRoot,
          userDid: session.did,
          daemonDid: install.daemonDid,
        );
      } finally {
        if (daemon != null) {
          _terminateProcess(daemon);
        }
        await bootstrap.appSessionService?.logout();
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    },
    skip: !_MessageAgentRealBackendConfig.shouldRun,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

AppBootstrap _copyBootstrapForMessageAgentUiTest(
  AppBootstrap source, {
  required AgentInventoryPort agentInventoryPort,
  required MessageAgentBindingPort messageAgentBindingPort,
  required IdentityCorePort identityCorePort,
  required MessagingService messagingService,
  required AgentControlService agentControlService,
}) {
  return AppBootstrap(
    accountGateway: source.accountGateway,
    gateway: source.gateway,
    realtimeGateway: source.realtimeGateway,
    notificationFacade: source.notificationFacade,
    e2eeFacade: source.e2eeFacade,
    localePreferenceService: source.localePreferenceService,
    updateService: source.updateService,
    appSessionService: source.appSessionService,
    identityCorePort: identityCorePort,
    onboardingService: source.onboardingService,
    onboardingSupportService: source.onboardingSupportService,
    messagingService: messagingService,
    conversationService: source.conversationService,
    agentInventoryPort: agentInventoryPort,
    messageAgentBindingPort: messageAgentBindingPort,
    agentControlService: agentControlService,
    agentControlStatusStore: source.agentControlStatusStore,
    groupApplicationService: source.groupApplicationService,
    profileApplicationService: source.profileApplicationService,
    directoryApplicationService: source.directoryApplicationService,
    relationshipApplicationService: source.relationshipApplicationService,
    realtimeApplicationService: source.realtimeApplicationService,
    productLocalStore: source.productLocalStore,
    peerIdentityService: source.peerIdentityService,
  );
}

Future<AppSession> _prepareRealAppIdentity(
  OnboardingService onboarding,
  _MessageAgentRealBackendConfig config,
) async {
  final recover = await _tryAppIdentityAction(
    () => onboarding.recoverHandle(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
    ),
  );
  if (recover.session != null) {
    return recover.session!;
  }
  if (!_looksRecoverableForRegister(recover.errorText)) {
    throw StateError(
      'App recover failed: ${_sanitizeDiagnostic(recover.errorText, config)}',
    );
  }
  final register = await _tryAppIdentityAction(
    () => onboarding.registerHandleWithPhone(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
      nickName: 'Message Agent E2E ${config.runId}',
    ),
  );
  if (register.session != null) {
    return register.session!;
  }
  throw StateError(
    'App register failed: ${_sanitizeDiagnostic(register.errorText, config)}',
  );
}

Future<_AppIdentityAttempt> _tryAppIdentityAction(
  Future<AppSession> Function() action,
) async {
  try {
    return _AppIdentityAttempt.session(await action());
  } on Object catch (error) {
    return _AppIdentityAttempt.error(error.toString());
  }
}

Future<_DaemonInstallResult> _installRealDaemon({
  required _MessageAgentRealBackendConfig config,
  required AgentInventoryPort inventory,
  required String controllerDid,
}) async {
  final token = await inventory.issueDaemonToken(
    controllerDid: controllerDid,
    clientPlatform: 'linux',
    handle: config.daemonHandle,
  );
  final result = await _runProcess(
    config.daemonBinary,
    <String>[
      'install',
      '--token',
      token.token,
      '--base-url',
      config.environment.baseUrl,
      '--no-service',
      '--print-json',
      '--state-root',
      config.daemonStateRoot,
    ],
    environment: _daemonEnvironment(config),
    timeout: const Duration(minutes: 2),
    secrets: <String>[token.token, ...config.secrets],
  );
  if (result.exitCode != 0) {
    throw StateError(
      'daemon install failed: ${result.sanitizedSummary(config)}',
    );
  }
  final json = jsonDecode(result.stdout);
  if (json is! Map) {
    throw StateError('daemon install did not return a JSON object.');
  }
  return _DaemonInstallResult(
    daemonDid: json['daemon_agent_did']?.toString() ?? '',
    handle: json['handle']?.toString() ?? config.daemonHandle,
  );
}

Future<Process> _startRealDaemon({
  required _MessageAgentRealBackendConfig config,
}) async {
  final readyFile = File(config.daemonReadyFile);
  if (readyFile.existsSync()) {
    readyFile.deleteSync();
  }
  final process = await Process.start(
    config.daemonBinary,
    <String>[
      'foreground',
      '--state-root',
      config.daemonStateRoot,
      '--ready-file',
      config.daemonReadyFile,
      '--max-runtime-ms',
      '180000',
      '--poll-interval-ms',
      '100',
    ],
    environment: _daemonEnvironment(config),
    includeParentEnvironment: true,
    runInShell: false,
  );
  process.stdout.transform(utf8.decoder).listen((_) {}, onError: (_) {});
  process.stderr.transform(utf8.decoder).listen((_) {}, onError: (_) {});
  return process;
}

Map<String, String> _daemonEnvironment(_MessageAgentRealBackendConfig config) {
  return <String, String>{
    'AWIKI_DAEMON_SERVICE_BASE_URL': config.environment.baseUrl,
    'AWIKI_DAEMON_USER_SERVICE_BASE_URL': config.environment.userServiceUrl,
    'AWIKI_DAEMON_MESSAGE_SERVICE_BASE_URL':
        config.environment.messageServiceUrl,
    'AWIKI_DAEMON_DID_DOMAIN': config.environment.didDomain,
    'AWIKI_DAEMON_ALLOW_PLAIN_CONTROL': '1',
    if (config.fakeHermesGatewayCommand != null)
      'AWIKI_HERMES_GATEWAY_CMD': config.fakeHermesGatewayCommand!,
  };
}

Future<void> _waitForUserServiceBindingActive({
  required MessageAgentBindingPort binding,
  required String daemonDid,
}) async {
  await _poll(
    description: 'user-service active binding exists for daemon',
    action: () async {
      final active = await binding.getActiveBinding();
      return active != null && active.daemonAgentDid == daemonDid;
    },
    timeout: const Duration(seconds: 60),
  );
}

Future<void> _waitForAgentInventoryEntry({
  required WidgetTester tester,
  required AgentsController agents,
  required String agentDid,
  required String handle,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    final agent = _agentByDid(state, agentDid);
    if (agent != null && agent.handle == handle) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for agent inventory entry $agentDid/$handle. '
    'Last agents: ${lastState ?? '<none>'}',
  );
}

Future<void> _waitForDaemonBootstrapKey({
  required WidgetTester tester,
  required AgentsController agents,
  required String daemonDid,
}) async {
  Object? lastError;
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    agents.select(daemonDid);
    await _pumpFrame(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final daemon = _agentByDid(container.read(agentsProvider), daemonDid);
    if (daemon == null) {
      lastError = 'daemon not found';
    } else {
      try {
        DaemonBootstrapPublicKey.fromDiagnostics(
          daemonDid: daemonDid,
          diagnostics: daemon.latest.diagnosticsSummary,
        );
        return;
      } on Object catch (error) {
        lastError =
            '$error diagnostics=${jsonEncode(daemon.latest.diagnosticsSummary)}';
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for daemon bootstrap public key for $daemonDid. '
    'Last error: ${lastError ?? '<none>'}',
  );
}

Future<void> _waitForAppHistory({
  required MessagingService messaging,
  required AppThreadRef thread,
  required String expectedText,
}) async {
  await _poll(
    description: 'App history contains "$expectedText"',
    action: () async {
      final messages = await messaging.loadHistory(thread, limit: 20);
      return messages.any((message) => message.content == expectedText);
    },
  );
}

Future<void> _waitForUserServiceBindingRevoked({
  required MessageAgentBindingPort binding,
}) async {
  await _poll(
    description: 'user-service active binding is revoked',
    action: () async => await binding.getActiveBinding() == null,
    timeout: const Duration(seconds: 30),
  );
}

Future<void> _waitForDaemonRuntimeFinalSent({
  required String daemonStateRoot,
  required String sourceText,
}) async {
  final dbPath = '${daemonStateRoot.replaceAll(RegExp(r'/+$'), '')}/daemon.db';
  String lastState = 'daemon.db not found';
  await _poll(
    description: 'daemon queued Message Agent runtime final for CLI message',
    action: () async {
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        lastState = 'daemon.db not found at $dbPath';
        return false;
      }
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows = await db.rawQuery(
          '''
          SELECT t.task_id, t.status AS task_status,
                 r.run_id, r.status AS run_status,
                 f.status AS final_status, f.message_id AS final_message_id,
                 f.sent_at_ms AS final_sent_at_ms
          FROM runtime_task t
          LEFT JOIN runtime_run r ON r.task_id = t.task_id
          LEFT JOIN runtime_final_outbox f ON f.run_id = r.run_id
          WHERE t.task_text LIKE ?
          ORDER BY t.created_at_ms DESC
          LIMIT 1
          ''',
          <Object?>['%$sourceText%'],
        );
        if (rows.isEmpty) {
          lastState = 'no runtime task contains sourceText';
          return false;
        }
        final row = rows.first;
        lastState = jsonEncode(row);
        final finalStatus = row['final_status']?.toString();
        return finalStatus == 'sent' &&
            row['final_message_id'] != null &&
            row['final_sent_at_ms'] != null;
      } finally {
        await db.close();
      }
    },
    timeout: const Duration(seconds: 75),
    interval: const Duration(seconds: 1),
    lastError: () => lastState,
  );
}

Future<void> _waitForDaemonBindingRevoked({
  required String daemonStateRoot,
  required String userDid,
  required String daemonDid,
}) async {
  final dbPath = '${daemonStateRoot.replaceAll(RegExp(r'/+$'), '')}/daemon.db';
  String lastState = 'daemon.db not found';
  await _poll(
    description: 'daemon local Message Agent binding is revoked',
    action: () async {
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        lastState = 'daemon.db not found at $dbPath';
        return false;
      }
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows = await db.rawQuery(
          '''
          SELECT binding_id, user_did, daemon_agent_did, runtime_agent_did,
                 status, revoked_at_ms
          FROM app_message_agent_binding
          WHERE user_did = ? AND daemon_agent_did = ?
          ORDER BY created_at_ms DESC
          LIMIT 1
          ''',
          <Object?>[userDid, daemonDid],
        );
        if (rows.isEmpty) {
          lastState = 'no binding rows for user=$userDid daemon=$daemonDid';
          return false;
        }
        final row = rows.first;
        lastState = jsonEncode(row);
        return row['status'] == 'message_agent_revoked' &&
            row['revoked_at_ms'] != null;
      } finally {
        await db.close();
      }
    },
    timeout: const Duration(seconds: 60),
    interval: const Duration(seconds: 1),
    lastError: () => lastState,
  );
}

Future<void> _openRealCliConversation({
  required WidgetTester tester,
  required ProviderContainer container,
  required String cliHandle,
  required String sourceText,
}) async {
  ConversationSummary? conversation;
  await _pumpUntil(
    tester,
    () {
      conversation = _conversationForCliMessage(
        container.read(conversationListProvider).conversations,
        cliHandle: cliHandle,
        sourceText: sourceText,
      );
      return conversation != null;
    },
    timeout: const Duration(seconds: 30),
    description: 'CLI conversation appears in App recents',
    lastError: () => _conversationDebugSummary(
      container.read(conversationListProvider).conversations,
    ),
  );
  final selected = conversation!;
  await _tapFirstFound(tester, <Finder>[
    find.bySemanticsIdentifier('e2e-messages-tab'),
    find.bySemanticsLabel('消息'),
    find.bySemanticsLabel('Messages'),
    find.text('消息'),
    find.text('Messages'),
  ]);
  await _pumpFrame(tester);
  await container.read(chatThreadsProvider.notifier).openConversation(selected);
  container
      .read(selectedConversationProvider.notifier)
      .selectConversation(selected);
  await _pumpFrame(tester);
}

Future<void> _waitForMessageAgentRuntimeFinalInApp({
  required WidgetTester tester,
  required String sourceText,
}) async {
  Object? lastState;
  await _pumpUntil(
    tester,
    () {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final threads = container.read(chatThreadsProvider);
      lastState = _messageAgentSyncDebugSummary(threads);
      return threads.values.any(
        (thread) =>
            thread.messages.any((message) => message.content == sourceText) &&
            thread.messageAgentSyncs.any((sync) => sync.isRuntimeFinal),
      );
    },
    timeout: const Duration(seconds: 120),
    description: 'App applies Message Agent runtime_final recovery state',
    lastError: () => lastState,
  );
  await _pumpFrame(tester);
  expect(find.text('消息 Agent 已完成处理'), findsOneWidget);
}

ConversationSummary? _conversationForCliMessage(
  List<ConversationSummary> conversations, {
  required String cliHandle,
  required String sourceText,
}) {
  final normalizedHandle = cliHandle.trim().toLowerCase();
  for (final conversation in conversations) {
    if (conversation.lastMessagePreview == sourceText) {
      return conversation;
    }
  }
  for (final conversation in conversations) {
    final targetPeer = conversation.targetPeer?.trim().toLowerCase();
    if (targetPeer == normalizedHandle) {
      return conversation;
    }
    if (conversation.displayName.trim().toLowerCase() == normalizedHandle) {
      return conversation;
    }
    if (conversation.visibilityKeys.any(
      (key) => key.toLowerCase().contains(normalizedHandle),
    )) {
      return conversation;
    }
  }
  return conversations.isEmpty ? null : conversations.first;
}

String _conversationDebugSummary(List<ConversationSummary> conversations) {
  return jsonEncode(
    conversations
        .map(
          (conversation) => <String, Object?>{
            'threadId': conversation.threadId,
            'displayName': conversation.displayName,
            'targetDid': conversation.targetDid,
            'targetPeer': conversation.targetPeer,
            'preview': conversation.lastMessagePreview,
            'visibilityKeys': conversation.visibilityKeys,
          },
        )
        .toList(),
  );
}

String _messageAgentSyncDebugSummary(Map<String, ChatThreadState> threads) {
  return jsonEncode(
    threads.entries
        .map(
          (entry) => <String, Object?>{
            'threadId': entry.key,
            'messages': entry.value.messages
                .map(
                  (message) => <String, Object?>{
                    'localId': message.localId,
                    'remoteId': message.remoteId,
                    'content': message.content,
                  },
                )
                .toList(),
            'syncs': entry.value.messageAgentSyncs
                .map(
                  (sync) => <String, Object?>{
                    'type': sync.type,
                    'runId': sync.runId,
                    'messageId': sync.messageId,
                    'conversationId': sync.conversationId,
                    'state': sync.state,
                  },
                )
                .toList(),
            'actions': entry.value.appActionRecords.keys.toList(),
          },
        )
        .toList(),
  );
}

Future<_CliResult> _runCli(
  _MessageAgentRealBackendConfig config,
  List<String> args, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final result = await _runProcess(
    config.cliBin,
    args,
    environment: <String, String>{
      for (final name in const <String>[
        'PATH',
        'LANG',
        'LC_ALL',
        'TMPDIR',
        'SSL_CERT_FILE',
        'SSL_CERT_DIR',
      ])
        if ((Platform.environment[name] ?? '').trim().isNotEmpty)
          name: Platform.environment[name]!,
      'HOME': config.cliHome,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
    },
    includeParentEnvironment: false,
    timeout: timeout,
    secrets: config.secrets,
  );
  return _CliResult(
    exitCode: result.exitCode,
    stdout: result.stdout,
    stderr: result.stderr,
  );
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Duration timeout = const Duration(seconds: 45),
  List<String> secrets = const <String>[],
}) async {
  final result = await Process.run(
    executable,
    args,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: false,
  ).timeout(timeout);
  return _ProcessResult(
    exitCode: result.exitCode,
    stdout: ((result.stdout as String?) ?? '').trim(),
    stderr: ((result.stderr as String?) ?? '').trim(),
    secrets: secrets,
  );
}

Future<void> _waitForFile(String path) async {
  await _poll(
    description: 'file exists: $path',
    action: () async => File(path).existsSync(),
    timeout: const Duration(seconds: 30),
    interval: const Duration(milliseconds: 250),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  String description = 'UI condition',
  Object? Function()? lastError,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  final detail = lastError == null ? null : lastError();
  fail(
    'Timed out waiting for $description.'
    '${detail == null ? '' : ' Last error: $detail'}',
  );
}

AgentSummary? _agentByDid(AgentsState state, String agentDid) {
  final normalized = agentDid.trim();
  for (final agent in state.agents) {
    if (agent.agentDid == normalized) {
      return agent;
    }
  }
  return null;
}

String _agentsDebugSummary(AgentsState state) {
  return jsonEncode(
    state.agents.map((agent) {
      final diagnostics = agent.latest.diagnosticsSummary;
      final configSummary = diagnostics['config_summary'];
      return <String, Object?>{
        'did': agent.agentDid,
        'kind': agent.kind.name,
        'daemon': agent.daemonAgentDid,
        'runtime': agent.runtime,
        'handle': agent.handle,
        'displayName': agent.displayName,
        'status': agent.latest.status,
        'activeState': agent.activeState,
        'diagnosticsKeys': diagnostics.keys.toList()..sort(),
        'configSummaryKeys': configSummary is Map
            ? (configSummary.keys.map((key) => key.toString()).toList()..sort())
            : const <String>[],
      };
    }).toList(),
  );
}

Future<void> _poll({
  required String description,
  required Future<bool> Function() action,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 2),
  Object? Function()? lastError,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? caughtError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await action()) {
        return;
      }
    } on Object catch (error) {
      caughtError = error;
    }
    await Future<void>.delayed(interval);
  }
  final detail = lastError == null ? caughtError : lastError() ?? caughtError;
  fail(
    'Timed out waiting for $description.'
    '${detail == null ? '' : ' Last error: $detail'}',
  );
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String _sanitizeDiagnostic(
  String input,
  _MessageAgentRealBackendConfig config,
) {
  var output = input;
  for (final secret in config.secrets) {
    final trimmed = secret.trim();
    if (trimmed.isNotEmpty) {
      output = output.replaceAll(trimmed, '<redacted>');
    }
  }
  return output.replaceAll(
    RegExp(
      r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
      caseSensitive: false,
    ),
    '<redacted-key>=<redacted>',
  );
}

void _terminateProcess(Process process) {
  if (process.kill(ProcessSignal.sigterm)) {
    return;
  }
  process.kill(ProcessSignal.sigkill);
}

class _MessageAgentRealBackendConfig {
  const _MessageAgentRealBackendConfig({
    required this.runId,
    required this.platform,
    required this.environment,
    required this.appHandle,
    required this.cliHandle,
    required this.otpPhone,
    required this.otpCode,
    required this.cliBin,
    required this.cliWorkspace,
    required this.cliHome,
    required this.appStateRoot,
    required this.daemonBinary,
    required this.daemonStateRoot,
    required this.daemonReadyFile,
    required this.daemonHandle,
    required this.realBackend,
    this.fakeHermesGatewayCommand,
  });

  static bool get shouldRun {
    final config = tryLoad();
    return config != null && config.realBackend;
  }

  static _MessageAgentRealBackendConfig? tryLoad() {
    final file = File(_messageAgentRunConfigPath);
    if (!file.existsSync()) {
      return null;
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map) {
      throw StateError('$_messageAgentRunConfigPath must be a JSON object.');
    }
    final map = _stringKeyMap(raw, path: _messageAgentRunConfigPath);
    final messageAgent = _optionalMapAt(map, 'messageAgent');
    final realBackend =
        messageAgent['realBackend'] == true ||
        messageAgent['realBackend']?.toString().toLowerCase() == 'true';
    if (!realBackend) {
      return null;
    }
    final service = _mapAt(map, 'service');
    final otp = _mapAt(map, 'otp');
    final accounts = _mapAt(map, 'accounts');
    final appUser = _mapAt(accounts, 'appUser');
    final cliPeerAccount = _mapAt(accounts, 'cliPeer');
    final cliPeer = _mapAt(map, 'cliPeer');
    final app = _mapAt(map, 'app');
    final daemon = _mapAt(map, 'daemon');
    final baseUrl = _requiredConfig(service, 'baseUrl', 'service.baseUrl');
    final didDomain = _requiredConfig(
      service,
      'didDomain',
      'service.didDomain',
    );
    return _MessageAgentRealBackendConfig(
      runId: _requiredConfig(map, 'runId', 'runId'),
      platform: _requiredConfig(map, 'platform', 'platform'),
      environment: AwikiEnvironmentConfig(
        baseUrl: baseUrl,
        userServiceUrl: _optionalConfig(service, 'userServiceUrl') ?? baseUrl,
        messageServiceUrl:
            _optionalConfig(service, 'messageServiceUrl') ?? baseUrl,
        mailServiceUrl: _optionalConfig(service, 'mailServiceUrl') ?? baseUrl,
        didDomain: didDomain,
        anpServiceUrl:
            _optionalConfig(service, 'anpServiceUrl') ?? '$baseUrl/anp-im/rpc',
        anpServiceDid:
            _optionalConfig(service, 'anpServiceDid') ?? 'did:wba:$didDomain',
        agentImEnabled: true,
      ),
      appHandle: _requiredConfig(appUser, 'handle', 'accounts.appUser.handle'),
      cliHandle: _requiredConfig(
        cliPeerAccount,
        'handle',
        'accounts.cliPeer.handle',
      ),
      otpPhone: _requiredConfig(otp, 'phone', 'otp.phone'),
      otpCode: _requiredConfig(otp, 'code', 'otp.code'),
      cliBin: _requiredConfig(cliPeer, 'binary', 'cliPeer.binary'),
      cliWorkspace: _requiredConfig(cliPeer, 'workspace', 'cliPeer.workspace'),
      cliHome: _requiredConfig(cliPeer, 'home', 'cliPeer.home'),
      appStateRoot: _requiredConfig(app, 'stateRoot', 'app.stateRoot'),
      daemonBinary: _requiredConfig(daemon, 'binary', 'daemon.binary'),
      daemonStateRoot: _requiredConfig(daemon, 'stateRoot', 'daemon.stateRoot'),
      daemonReadyFile: _requiredConfig(daemon, 'readyFile', 'daemon.readyFile'),
      daemonHandle:
          _optionalConfig(daemon, 'handle') ??
          'message-agent-daemon-${DateTime.now().millisecondsSinceEpoch}',
      fakeHermesGatewayCommand: _optionalConfig(
        daemon,
        'fakeHermesGatewayCommand',
      ),
      realBackend: realBackend,
    );
  }

  final String runId;
  final String platform;
  final AwikiEnvironmentConfig environment;
  final String appHandle;
  final String cliHandle;
  final String otpPhone;
  final String otpCode;
  final String cliBin;
  final String cliWorkspace;
  final String cliHome;
  final String appStateRoot;
  final String daemonBinary;
  final String daemonStateRoot;
  final String daemonReadyFile;
  final String daemonHandle;
  final bool realBackend;
  final String? fakeHermesGatewayCommand;

  TargetPlatform get targetPlatform {
    return platform == 'linux' ? TargetPlatform.linux : TargetPlatform.macOS;
  }

  List<String> get secrets => <String>[
    otpPhone,
    otpCode,
    cliWorkspace,
    cliHome,
    appStateRoot,
    daemonStateRoot,
    daemonReadyFile,
  ].where((value) => value.trim().isNotEmpty).toList(growable: false);
}

class _DaemonInstallResult {
  const _DaemonInstallResult({required this.daemonDid, required this.handle});

  final String daemonDid;
  final String handle;
}

class _AppIdentityAttempt {
  const _AppIdentityAttempt._({this.session, required this.errorText});

  factory _AppIdentityAttempt.session(AppSession session) {
    return _AppIdentityAttempt._(session: session, errorText: '');
  }

  factory _AppIdentityAttempt.error(String errorText) {
    return _AppIdentityAttempt._(errorText: errorText);
  }

  final AppSession? session;
  final String errorText;
}

class _ProcessResult {
  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.secrets = const <String>[],
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> secrets;

  String sanitizedSummary(_MessageAgentRealBackendConfig config) {
    return _sanitizeDiagnostic(
      'exit=$exitCode stdout=$stdout stderr=$stderr',
      config,
    );
  }
}

class _CliResult {
  const _CliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  String sanitizedSummary(_MessageAgentRealBackendConfig config) {
    return _sanitizeDiagnostic(
      'exit=$exitCode stdout=$stdout stderr=$stderr',
      config,
    );
  }
}

Map<String, Object?> _stringKeyMap(Object? value, {required String path}) {
  if (value is! Map) {
    throw StateError('$path must be a JSON object.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _mapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

Map<String, Object?> _optionalMapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

String _requiredConfig(Map<String, Object?> map, String key, String name) {
  final value = _optionalConfig(map, key);
  if (value == null) {
    throw StateError('$name is required in $_messageAgentRunConfigPath.');
  }
  return value;
}

String? _optionalConfig(Map<String, Object?> map, String key) {
  final raw = map[key];
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

class _UiAgentInventoryPort implements AgentInventoryPort {
  _UiAgentInventoryPort(this._agents);

  final List<AgentSummary> Function() _agents;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    return _agents();
  }

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String clientPlatform,
    String? handle,
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
    String? driverId,
    String? workspaceMode,
    String? defaultSandbox,
    String? defaultModel,
    Map<String, Object?>? driverConfig,
  }) async {
    return const AgentRegistrationToken(token: 'runtime-token');
  }

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy({
    required String agentDid,
  }) async {
    return const AgentInvocationPolicy();
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    return policy;
  }

  @override
  Future<void> unbindAgent({required String agentDid}) async {}

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) async {
    return AgentSummary(
      agentDid: agentDid,
      kind: AgentKind.daemon,
      displayName: displayName,
      activeState: 'active',
      latest: const AgentLatestStatus(status: 'ready'),
    );
  }
}

class _UiMessageAgentBindingPort implements MessageAgentBindingPort {
  final List<String> calls = <String>[];

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
    return MessageAgentBinding(
      id: 'binding_1',
      userDid: userDid,
      daemonAgentDid: daemonAgentDid,
      messageAgentDid: messageAgentDid,
      runtimeProvider: runtimeProvider,
      runtimeProfile: runtimeProfile,
      delegatedKeyVerificationMethod: delegatedKeyVerificationMethod,
      status: 'active',
    );
  }

  @override
  Future<MessageAgentBinding?> getActiveBinding() async {
    calls.add('get_active');
    return const MessageAgentBinding(
      id: 'binding_1',
      userDid: 'did:test:me',
      daemonAgentDid: 'did:test:daemon:message',
      messageAgentDid: 'did:test:agent:message',
      runtimeProvider: 'hermes',
      runtimeProfile: <String, Object?>{'profile': 'message_agent'},
      delegatedKeyVerificationMethod: 'did:test:me#daemon-key-1',
      status: 'active',
    );
  }

  @override
  Future<MessageAgentBinding> disableBinding({
    String? bindingId,
    String? messageAgentDid,
  }) async {
    calls.add('disable:${bindingId ?? messageAgentDid}');
    return const MessageAgentBinding(
      id: 'binding_1',
      userDid: 'did:test:me',
      daemonAgentDid: 'did:test:daemon:message',
      messageAgentDid: 'did:test:agent:message',
      runtimeProvider: 'hermes',
      runtimeProfile: <String, Object?>{'profile': 'message_agent'},
      delegatedKeyVerificationMethod: 'did:test:me#daemon-key-1',
      status: 'disabled',
    );
  }

  @override
  Future<MessageAgentBinding> revokeBinding({
    String? bindingId,
    String? messageAgentDid,
  }) async {
    calls.add('revoke:${bindingId ?? messageAgentDid}');
    return const MessageAgentBinding(
      id: 'binding_1',
      userDid: 'did:test:me',
      daemonAgentDid: 'did:test:daemon:message',
      messageAgentDid: 'did:test:agent:message',
      runtimeProvider: 'hermes',
      runtimeProfile: <String, Object?>{'profile': 'message_agent'},
      delegatedKeyVerificationMethod: 'did:test:me#daemon-key-1',
      status: 'revoked',
    );
  }
}

class _UiIdentityCorePort implements IdentityCorePort {
  final List<String> calls = <String>[];

  @override
  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  ) async {
    calls.add('revoke:$identityIdOrAlias');
    return const DaemonSubkeyAuthorizationRevokeResult(
      userDid: 'did:test:me',
      verificationMethod: 'did:test:me#daemon-key-1',
      updated: true,
    );
  }

  @override
  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) async {
    return const UserSubkeyPackage(
      userDid: 'did:test:me',
      verificationMethod: 'did:test:me#daemon-key-1',
      publicKeyMultibase: 'zPublic',
      privateKeyMultibase: 'zPrivate',
    );
  }

  @override
  Future<AppSession?> defaultIdentity() async => const AppSession(
    did: 'did:test:me',
    identityId: 'default',
    displayName: 'Me',
    localAlias: 'default',
  );

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    (await defaultIdentity())!,
  ];

  @override
  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(String identityIdOrAlias) {
    return ensureDaemonSubkeyPackage(identityIdOrAlias);
  }

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) {
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
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async {
    return (await defaultIdentity())!;
  }
}

class _UiMessagingService implements MessagingService {
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];
  Map<String, Object?>? lastPayload;
  String? lastIdempotencyKey;

  void resetRecordedPayloads() {
    payloads.clear();
    lastPayload = null;
    lastIdempotencyKey = null;
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    payloads.add(payload);
    lastPayload = payload;
    lastIdempotencyKey = idempotencyKey;
    return ChatMessage(
      localId: 'payload_1',
      threadId: thread.stableId,
      senderDid: 'did:test:me',
      receiverDid: thread is AppDirectThreadRef ? thread.peerDidOrHandle : null,
      content: '',
      createdAt: DateTime(2026, 6, 20),
      isMine: true,
      sendState: MessageSendState.sent,
    );
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
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
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
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
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
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tapFirstFound(
  WidgetTester tester,
  List<Finder> candidates,
) async {
  for (final finder in candidates) {
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.first);
      return;
    }
  }
  fail('No tappable finder matched among ${candidates.length} candidates.');
}
