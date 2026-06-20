import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/message_agent_binding_port.dart';
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
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../unit/test_support.dart' as test_support;
import '../support/fake_app_bootstrap.dart';

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
    final realControl = DefaultAgentControlService(
      inventory: inventory,
      messages: messages,
      messageAgentBindings: bindings,
      identities: identities,
      agentImEnabled: true,
    );
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
          bootstrap: harness.bootstrap,
          providerOverrides: <Override>[
            ...harness.providerOverrides,
            agentImEnabledProvider.overrideWithValue(true),
            agentInventoryPortProvider.overrideWithValue(inventory),
            messageAgentBindingPortProvider.overrideWithValue(bindings),
            identityCorePortProvider.overrideWithValue(identities),
            messagingServiceProvider.overrideWithValue(messages),
            agentControlServiceProvider.overrideWithValue(realControl),
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
