import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show Key, RepaintBoundary, Size, SizedBox;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../unit/test_support.dart' as test_support;
import '../support/fake_app_bootstrap.dart';

const _captureBoundaryKey = Key('ui-visual-verification-boundary');
const _screenshotsDir = 'docs/ui-optimization-plan/screenshots';
const _visualScreenshotFiles = <String>{
  '01-compact-onboarding.png',
  '02-expanded-onboarding.png',
  '03-compact-messages.png',
  '04-compact-chat.png',
  '05-expanded-messages-chat.png',
  '06-compact-agents-list.png',
  '07-compact-agent-detail.png',
  '08-expanded-agents.png',
  '09-compact-contacts.png',
  '10-compact-profile.png',
  '11-compact-settings.png',
  '12-expanded-contacts.png',
  '13-expanded-profile.png',
  '14-expanded-settings.png',
  '15-compact-quick-actions.png',
};
const _compactSize = Size(393, 852);
const _expandedSize = Size(1440, 900);
const _sessionDid = 'did:test:me';
const _session = SessionIdentity(
  did: _sessionDid,
  credentialName: 'default',
  handle: 'ui-reviewer.awiki.ai',
  displayName: 'UI Reviewer',
  jwtToken: 'test-jwt',
);
const _daemonDid = 'did:test:daemon:local';
const _runtimeDid = 'did:test:agent:hermes-ui';
const _humanDid = 'did:test:person:alice';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> conversations,
  ) {
    state = ConversationListState(conversations: conversations);
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshFastLocal() async {}
}

class _StaticFriendsController extends FriendsController {
  _StaticFriendsController(super.ref, FriendsState initialState) {
    state = initialState;
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_cleanScreenshots);

  testWidgets('capture compact and expanded onboarding', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpOnboarding(tester);
      expect(
        find.byKey(const Key('onboarding-compact-auth-card')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '01-compact-onboarding');

      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      await _pumpOnboarding(tester);
      expect(
        find.byKey(const Key('onboarding-expanded-layout')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '02-expanded-onboarding');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture compact and expanded messages and chat', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      expect(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:hermes-ui')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '03-compact-messages');

      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:hermes-ui')),
      );
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(const Key('chat-peer-info-avatar-button')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '04-compact-chat');

      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:hermes-ui')),
      );
      await _pumpVisualFrames(tester);
      expect(find.text('product-brief.pdf'), findsOneWidget);
      await _captureScreenshot(tester, '05-expanded-messages-chat');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture compact and expanded agents', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(find.bySemanticsLabel('智能体'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('agents-compact-list')), findsOneWidget);
      await _captureScreenshot(tester, '06-compact-agents-list');

      await tester.tap(find.text('Hermes UI').first);
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('agents-compact-detail')), findsOneWidget);
      await _captureScreenshot(tester, '07-compact-agent-detail');

      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(find.bySemanticsLabel('智能体'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('agents-expanded-layout')), findsOneWidget);
      await _captureScreenshot(tester, '08-expanded-agents');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture contacts, profile, and settings', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(find.bySemanticsLabel('联系人'));
      await _pumpVisualFrames(tester);
      expect(find.text('Alice Chen'), findsWidgets);
      await _captureScreenshot(tester, '09-compact-contacts');

      await tester.tap(find.bySemanticsLabel('消息'));
      await _pumpVisualFrames(tester);
      await tester.tap(find.bySemanticsLabel('设置'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('settings-profile-row')), findsOneWidget);
      expect(find.byKey(const Key('compact-bottom-navigation')), findsNothing);
      await tester.tap(find.byKey(const Key('settings-profile-row')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('profile-handle-value')), findsOneWidget);
      expect(find.byKey(const Key('compact-bottom-navigation')), findsNothing);
      await _captureScreenshot(tester, '10-compact-profile');

      await tester.tap(find.byKey(const Key('profile-back-button')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('settings-tenant-row')), findsOneWidget);
      await _captureScreenshot(tester, '11-compact-settings');

      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(find.bySemanticsLabel('联系人'));
      await _pumpVisualFrames(tester);
      await _captureScreenshot(tester, '12-expanded-contacts');

      await tester.tap(find.bySemanticsLabel('我'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('profile-sidebar-summary')), findsOneWidget);
      await _captureScreenshot(tester, '13-expanded-profile');

      await tester.tap(find.bySemanticsLabel('设置'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('mac-settings-list-pane')), findsOneWidget);
      await _captureScreenshot(tester, '14-expanded-settings');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture compact adaptive quick-actions menu', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(find.bySemanticsLabel('更多操作'));
      await _pumpVisualFrames(tester);
      expect(find.text('发起新消息'), findsOneWidget);
      await _captureScreenshot(tester, '15-compact-quick-actions');
    } finally {
      await _resetEnvironment(tester);
    }
  });
}

Future<void> _prepareEnvironment(
  WidgetTester tester, {
  required Size size,
  required TargetPlatform platform,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpVisualFrames(tester);
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
}

Future<void> _resetEnvironment(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = null;
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpVisualFrames(tester);
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Future<void> _pumpOnboarding(WidgetTester tester) async {
  final harness = createFakeAwikiMeAppHarness();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureBoundaryKey,
      child: AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    ),
  );
  await _pumpVisualFrames(tester);
}

FakeAwikiMeAppHarness _createVisualHarness() {
  final conversations = _visualConversations();
  final history = _visualHistory();
  const profile = UserProfile(
    did: _sessionDid,
    displayName: 'UI Reviewer',
    bio: '连接人、智能体与可信协作网络。',
    tags: <String>['产品', '协作'],
    profileMarkdown: '# UI Reviewer\n\n关注可靠、清晰、可维护的协作体验。',
    handle: 'ui-reviewer.awiki.ai',
    fullHandle: 'ui-reviewer.awiki.ai',
  );
  final harness = createFakeAwikiMeAppHarness(
    session: _session,
    profile: profile,
  );
  const alice = UserProfile(
    did: _humanDid,
    displayName: 'Alice Chen',
    bio: '负责产品设计与用户研究。',
    tags: <String>['设计', '研究'],
    profileMarkdown: '## Alice Chen\n\n产品设计与用户研究。',
    handle: 'alice.awiki.ai',
    fullHandle: 'alice.awiki.ai',
  );
  harness.gateway
    ..conversations = conversations
    ..dmHistoryByPeerDid = <String, List<ChatMessage>>{_runtimeDid: history}
    ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      _runtimeDid: history,
    }
    ..following = const <RelationshipSummary>[
      RelationshipSummary(
        did: _humanDid,
        displayName: 'Alice Chen',
        relationship: 'following',
        handle: 'alice.awiki.ai',
      ),
      RelationshipSummary(
        did: _runtimeDid,
        displayName: 'Hermes UI',
        relationship: 'following',
        handle: 'hermes-ui',
      ),
    ]
    ..followers = const <RelationshipSummary>[
      RelationshipSummary(
        did: 'did:test:person:bob',
        displayName: 'Bob Li',
        relationship: 'follower',
        handle: 'bob.awiki.ai',
      ),
    ]
    ..publicProfilesByQuery = <String, UserProfile>{
      _humanDid: alice,
      'alice.awiki.ai': alice,
      _runtimeDid: const UserProfile(
        did: _runtimeDid,
        displayName: 'Hermes UI',
        bio: 'Runtime Agent for visual verification.',
        tags: <String>['Agent'],
        profileMarkdown:
            '# Hermes UI\n\nRuntime Agent for visual verification.',
        handle: 'hermes-ui',
      ),
    };

  final messaging =
      harness.bootstrap.messagingService as test_support.FakeMessagingService;
  messaging.conversationTimelineById['dm:peer-scope:v1:hermes-ui'] = history;

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
      latest: test_support.readyDaemonStatusWithGenericCliCapability,
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
    AgentSummary(
      agentDid: 'did:test:agent:codex-ui',
      kind: AgentKind.runtime,
      daemonAgentDid: _daemonDid,
      runtime: 'codex',
      handle: 'codex-ui',
      displayName: 'Codex UI',
      activeState: 'active',
      latest: AgentLatestStatus(
        status: 'ready',
        diagnosticsSummary: test_support.genericCliRuntimeCardDiagnostics(
          lifecycleState: 'needs_setup',
          setupReady: false,
        ),
      ),
    ),
  ];
  return FakeAwikiMeAppHarness(
    bootstrap: harness.bootstrap,
    gateway: harness.gateway,
    realtimeGateway: harness.realtimeGateway,
    notificationFacade: harness.notificationFacade,
    providerOverrides: <Override>[
      ...harness.providerOverrides,
      conversationListProvider.overrideWith(
        (ref) => _StaticConversationListController(ref, conversations),
      ),
      friendsProvider.overrideWith(
        (ref) => _StaticFriendsController(
          ref,
          const FriendsState(
            following: <RelationshipSummary>[
              RelationshipSummary(
                did: _humanDid,
                displayName: 'Alice Chen',
                relationship: 'following',
                handle: 'alice.awiki.ai',
              ),
              RelationshipSummary(
                did: _runtimeDid,
                displayName: 'Hermes UI',
                relationship: 'following',
                handle: 'hermes-ui',
              ),
            ],
            followers: <RelationshipSummary>[
              RelationshipSummary(
                did: 'did:test:person:bob',
                displayName: 'Bob Li',
                relationship: 'follower',
                handle: 'bob.awiki.ai',
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

List<ConversationSummary> _visualConversations() {
  return <ConversationSummary>[
    ConversationSummary(
      threadId: 'dm:peer-scope:v1:hermes-ui',
      conversationId: 'dm:peer-scope:v1:hermes-ui',
      displayName: 'Hermes UI',
      lastMessagePreview: '产品概要已经整理完成，可以继续讨论。',
      lastMessageAt: DateTime(2026, 7, 25, 10, 30),
      unreadCount: 7,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'agent-message-1',
      isGroup: false,
      targetDid: _runtimeDid,
      targetPeer: 'hermes-ui',
    ),
    ConversationSummary(
      threadId: 'dm:peer-scope:v1:alice',
      conversationId: 'dm:peer-scope:v1:alice',
      displayName: 'Alice Chen',
      lastMessagePreview: '明天下午一起确认交互稿。',
      lastMessageAt: DateTime(2026, 7, 25, 9, 12),
      unreadCount: 2,
      isGroup: false,
      targetDid: _humanDid,
      targetPeer: 'alice.awiki.ai',
    ),
    ConversationSummary(
      threadId: 'group:did:test:group:product',
      conversationId: 'group:did:test:group:product',
      displayName: '产品协作群',
      lastMessagePreview: 'Bob: 新版本体验问题已汇总。',
      lastMessageAt: DateTime(2026, 7, 24, 19, 45),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:product',
      canonicalGroupDid: 'did:test:group:product',
    ),
  ];
}

List<ChatMessage> _visualHistory() {
  return <ChatMessage>[
    ChatMessage(
      localId: 'human-message-1',
      threadId: 'dm:peer-scope:v1:hermes-ui',
      senderDid: _session.did,
      senderName: _session.displayName,
      content: '请帮我看一下这份产品概要。',
      createdAt: DateTime(2026, 7, 25, 10, 25),
      isMine: true,
      sendState: MessageSendState.sent,
    ),
    ChatMessage(
      localId: 'agent-message-1',
      threadId: 'dm:peer-scope:v1:hermes-ui',
      senderDid: _runtimeDid,
      senderName: 'Hermes UI',
      content: '已经看完。信息层级清楚，建议把关键风险放到第一屏。',
      createdAt: DateTime(2026, 7, 25, 10, 30),
      isMine: false,
      sendState: MessageSendState.sent,
    ),
    ChatMessage(
      localId: 'agent-attachment-1',
      threadId: 'dm:peer-scope:v1:hermes-ui',
      senderDid: _runtimeDid,
      senderName: 'Hermes UI',
      content: '',
      originalType: 'attachment',
      createdAt: DateTime(2026, 7, 25, 10, 32),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-product-brief',
        filename: 'product-brief.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 248320,
        caption: '整理后的产品概要。',
        objectUri: 'awiki://attachments/product-brief.pdf',
      ),
    ),
  ];
}

Future<void> _pumpVisualApp(
  WidgetTester tester,
  FakeAwikiMeAppHarness harness,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureBoundaryKey,
      child: AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: harness.providerOverrides,
      ),
    ),
  );
  await _pumpVisualFrames(tester);
}

Future<void> _cleanScreenshots() async {
  final directory = Directory(_screenshotsDir);
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
    return;
  }
  await for (final entity in directory.list()) {
    final name = entity.uri.pathSegments.last;
    if (entity is File && _visualScreenshotFiles.contains(name)) {
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
  await File(
    '$_screenshotsDir/$name.png',
  ).writeAsBytes(byteData!.buffer.asUint8List(), flush: true);
  image.dispose();
}

Future<void> _pumpVisualFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 360));
}
