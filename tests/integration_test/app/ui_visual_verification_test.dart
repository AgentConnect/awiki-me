import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/agents/agent_inbox_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show Key, RepaintBoundary, Size, SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../unit_test/test_support.dart' as test_support;
import '../support/fake_app_bootstrap.dart';

const _captureBoundaryKey = Key('ui-visual-verification-boundary');
const _screenshotsDir = 'docs/ui-optimization-plan/screenshots';
const _session = SessionIdentity(
  did: 'did:test:me',
  credentialName: 'default',
  handle: 'ui-reviewer',
  displayName: 'UI Reviewer',
  jwtToken: 'test-jwt',
);
const _daemonDid = 'did:test:daemon:local';
const _runtimeDid = 'did:test:agent:hermes-ui';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> conversations,
  ) {
    state = ConversationListState(conversations: conversations);
  }

  @override
  Future<void> refresh() async {
    // Screenshots use deterministic seeded conversations.
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('UI optimization visual verification screenshots', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.binding.setSurfaceSize(const Size(1600, 960));
    await _cleanScreenshots();

    final onboardingHarness = createFakeAwikiMeAppHarness();
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureBoundaryKey,
        child: AwikiMeApp(
          bootstrap: onboardingHarness.bootstrap,
          providerOverrides: onboardingHarness.providerOverrides,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录或注册'), findsWidgets);
    await _captureScreenshot(tester, '01-onboarding-login');

    final visualHarness = _createVisualHarness();
    await _resetApp(tester);
    await _pumpVisualApp(tester, visualHarness);
    await tester.tap(find.text('Hermes UI').first);
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('product-brief.pdf'), findsOneWidget);
    await _captureScreenshot(tester, '02-chat-default-info-closed');

    await tester.tap(find.byKey(const Key('chat-conversation-info-button')));
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsOneWidget);
    await _captureScreenshot(tester, '03-chat-info-side-panel');

    await tester.tap(find.text('身份卡').first);
    await tester.pumpAndSettle();
    expect(find.text('智能体信息'), findsOneWidget);
    expect(find.text('Runtime Agent'), findsOneWidget);
    expect(find.byKey(const Key('peer-info-dialog-did-value')), findsOneWidget);
    await _captureScreenshot(tester, '04-agent-info-popup');

    await tester.tap(find.text('Agent 收件箱').last);
    await tester.pump();
    final appContainer = _appContainer(tester);
    appContainer
        .read(agentInboxProvider.notifier)
        .applyControlPayload(_inboxPayload());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('peer-info-agent-inbox')), findsOneWidget);
    expect(find.textContaining('最新：'), findsWidgets);
    await tester.ensureVisible(find.text('bob.anpclaw.com').first);
    await tester.pumpAndSettle();
    await _captureScreenshot(tester, '05-agent-inbox-list');

    await tester.tap(find.text('bob.anpclaw.com').first);
    await tester.pump();
    appContainer
        .read(agentInboxProvider.notifier)
        .applyControlPayload(_threadPayload());
    await tester.pumpAndSettle();
    expect(find.text('加载更早消息'), findsOneWidget);
    await tester.ensureVisible(find.text('加载更早消息'));
    await tester.pumpAndSettle();
    await _captureScreenshot(tester, '06-agent-inbox-thread');

    final agentsHarness = _createVisualHarness();
    await _resetApp(tester);
    await _pumpVisualApp(tester, agentsHarness);
    _appContainer(tester).read(shellTabProvider.notifier).setTab(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建 Hermes').first);
    await tester.pumpAndSettle();
    expect(find.text('Agent 类型'), findsOneWidget);
    expect(find.text('当前仅支持 Hermes Runtime Agent'), findsOneWidget);
    await _captureScreenshot(tester, '07-agent-create-hermes-type');
  });
}

Future<void> _resetApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

FakeAwikiMeAppHarness _createVisualHarness() {
  final conversation = _visualConversation();
  final harness = createFakeAwikiMeAppHarness(session: _session);
  harness.gateway
    ..conversations = <ConversationSummary>[conversation]
    ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
      _runtimeDid: _visualHistory(),
    }
    ..publicProfilesByQuery = <String, UserProfile>{
      _runtimeDid: const UserProfile(
        did: _runtimeDid,
        nickName: 'Hermes UI',
        bio: 'Runtime Agent info popup visual check.',
        tags: <String>['Agent'],
        profileMarkdown:
            '# Hermes UI\n\nRuntime Agent info popup visual check.\n\n- 支持身份卡复制\n- 支持 Agent 收件箱',
        handle: 'hermes-ui',
      ),
    };
  final control =
      harness.bootstrap.agentControlService!
          as test_support.FakeAgentControlService;
  control.agents = <AgentSummary>[
    const AgentSummary(
      agentDid: _daemonDid,
      kind: AgentKind.daemon,
      handle: 'local-daemon',
      displayName: 'Local Daemon',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'ready', platform: 'darwin-arm64'),
    ),
    const AgentSummary(
      agentDid: _runtimeDid,
      kind: AgentKind.runtime,
      daemonAgentDid: _daemonDid,
      runtime: 'hermes',
      handle: 'hermes-ui',
      displayName: 'Hermes UI',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'ready'),
    ),
  ];
  return harness;
}

ConversationSummary _visualConversation() {
  return ConversationSummary(
    threadId: 'dm:$_runtimeDid',
    displayName: 'Hermes UI',
    lastMessagePreview: 'latest runtime reply',
    lastMessageAt: DateTime(2026, 6, 15, 10, 30),
    unreadCount: 0,
    isGroup: false,
    targetDid: _runtimeDid,
  );
}

List<ChatMessage> _visualHistory() {
  return <ChatMessage>[
    ChatMessage(
      localId: 'human-message-1',
      threadId: 'dm:$_runtimeDid',
      senderDid: _session.did,
      senderName: _session.displayName,
      content: '请帮我看一下这份产品概要。',
      createdAt: DateTime(2026, 6, 15, 10, 25),
      isMine: true,
      sendState: MessageSendState.sent,
    ),
    ChatMessage(
      localId: 'agent-message-1',
      threadId: 'dm:$_runtimeDid',
      senderDid: _runtimeDid,
      senderName: 'Hermes UI',
      content: 'latest runtime reply',
      createdAt: DateTime(2026, 6, 15, 10, 30),
      isMine: false,
      sendState: MessageSendState.sent,
    ),
    ChatMessage(
      localId: 'agent-attachment-1',
      threadId: 'dm:$_runtimeDid',
      senderDid: _runtimeDid,
      senderName: 'Hermes UI',
      content: '',
      originalType: 'attachment',
      createdAt: DateTime(2026, 6, 15, 10, 32),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-product-brief',
        filename: 'product-brief.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 248320,
        caption: '这里是可用本机应用查看的附件。',
        objectUri: 'awiki://attachments/product-brief.pdf',
      ),
    ),
  ];
}

Future<void> _pumpVisualApp(
  WidgetTester tester,
  FakeAwikiMeAppHarness harness,
) async {
  final conversation = _visualConversation();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureBoundaryKey,
      child: AwikiMeApp(
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
    ),
  );
  await tester.pumpAndSettle();
}

ProviderContainer _appContainer(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
}

Map<String, Object?> _inboxPayload() {
  return <String, Object?>{
    'schema': AgentControlPayloads.statusSchema,
    'status_scope': 'runtime_inbox',
    'daemon_agent_did': _daemonDid,
    'runtime_agent_did': _runtimeDid,
    'request_id': 'cmd_runtime_inbox_test',
    'state': 'succeeded',
    'result': <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'thread_id': 'dm:peer-scope:v1:bob',
          'kind': 'direct',
          'title': 'bob.anpclaw.com',
          'peer_did': 'did:human:bob',
          'peer_handle': 'bob.anpclaw.com',
          'peer_user_id': 'user-bob',
          'last_message_preview': 'Can you summarize the roadmap?',
          'last_message_at_ms': DateTime(
            2026,
            6,
            15,
            10,
            35,
          ).millisecondsSinceEpoch,
          'unread_count': 2,
          'has_attachments': false,
          'last_content_type': 'text',
        },
        <String, Object?>{
          'thread_id': 'group:did:group:team',
          'kind': 'group',
          'title': '项目群',
          'group_did': 'did:group:team',
          'last_message_preview': 'report.pdf',
          'last_message_at_ms': DateTime(
            2026,
            6,
            15,
            10,
            20,
          ).millisecondsSinceEpoch,
          'unread_count': 0,
          'has_attachments': true,
          'last_content_type': 'attachment',
        },
      ],
      'next_cursor': 'older-inbox-20',
      'fetched_at_ms': DateTime(2026, 6, 15, 10, 36).millisecondsSinceEpoch,
    },
  };
}

Map<String, Object?> _threadPayload() {
  return <String, Object?>{
    'schema': AgentControlPayloads.statusSchema,
    'status_scope': 'runtime_inbox_thread',
    'daemon_agent_did': _daemonDid,
    'runtime_agent_did': _runtimeDid,
    'request_id': 'cmd_runtime_inbox_thread_test',
    'state': 'succeeded',
    'result': <String, Object?>{
      'thread_id': 'dm:peer-scope:v1:bob',
      'kind': 'direct',
      'title': 'bob.anpclaw.com',
      'messages': <Object?>[
        <String, Object?>{
          'message_id': 'msg-bob-1',
          'sender_did': 'did:human:bob',
          'sender_handle': 'bob.anpclaw.com',
          'direction': 'incoming',
          'content_type': 'text',
          'text': 'Can you summarize the roadmap?',
          'sent_at_ms': DateTime(
            2026,
            6,
            15,
            10,
            34,
          ).millisecondsSinceEpoch,
        },
        <String, Object?>{
          'message_id': 'msg-agent-1',
          'sender_did': _runtimeDid,
          'sender_handle': 'hermes-ui',
          'direction': 'outgoing',
          'content_type': 'text',
          'text': 'I will review the roadmap and reply with the top risks.',
          'sent_at_ms': DateTime(
            2026,
            6,
            15,
            10,
            35,
          ).millisecondsSinceEpoch,
        },
      ],
      'next_cursor': 'older-thread-20',
      'fetched_at_ms': DateTime(2026, 6, 15, 10, 36).millisecondsSinceEpoch,
    },
  };
}

Future<void> _cleanScreenshots() async {
  final directory = Directory(_screenshotsDir);
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
    return;
  }
  await for (final entity in directory.list()) {
    final name = entity.uri.pathSegments.last;
    if (entity is File && RegExp(r'^\d\d-.*\.png$').hasMatch(name)) {
      await entity.delete();
    }
  }
}

Future<void> _captureScreenshot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureBoundaryKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  await File('$_screenshotsDir/$name.png')
      .writeAsBytes(bytes, flush: true);
  image.dispose();
}
