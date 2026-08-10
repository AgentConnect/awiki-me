import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/agents/agent_status_indicator.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoPageScaffold;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart'
    show
        ColoredBox,
        DecoratedBox,
        FontWeight,
        Icon,
        Key,
        RepaintBoundary,
        Size,
        SizedBox,
        Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../unit/test_support.dart' as test_support;
import '../support/fake_app_bootstrap.dart';

const _captureBoundaryKey = Key('ui-visual-verification-boundary');
const _screenshotsDir = 'docs/ui-optimization-plan/screenshots';
const _goldenFontFamily = 'AwikiGoldenCjk';
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
const _agentInfoDid =
    'did:wba:agent-connect.cn:agent:skill:skill-cc44721e0153c892';

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

class _StaticGroupController extends GroupController {
  _StaticGroupController(super.ref, GroupState initialState) {
    state = initialState;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadGoldenFont);

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
      expect(
        find.byKey(const Key('onboarding-desktop-dot-pattern')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '02-expanded-onboarding');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('android compact onboarding clears the system navigation edge', (
    tester,
  ) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.android,
      );
      await _pumpOnboarding(tester);

      final footerRect = tester.getRect(
        find.byKey(const Key('onboarding-compact-footer')),
      );
      expect(_compactSize.height - footerRect.bottom, greaterThan(10));
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
      _expectCompactShellHeader(tester, title: '消息');
      await _captureScreenshot(tester, '03-compact-messages');

      final swipeConversation = find.byKey(
        const Key('conversation-row:dm:peer-scope:v1:hermes-ui'),
      );
      await tester.drag(swipeConversation, const Offset(-120, 0));
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(
          const Key('conversation-row-delete:dm:peer-scope:v1:hermes-ui'),
        ),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '23-compact-conversation-swipe-delete');

      await tester.tap(
        find.byKey(
          const Key('conversation-row-delete:dm:peer-scope:v1:hermes-ui'),
        ),
      );
      await _pumpVisualFrames(tester);
      expect(find.text('删除会话'), findsOneWidget);
      expect(find.text('从最近列表移除该会话'), findsOneWidget);
      await _captureScreenshot(
        tester,
        '24-compact-conversation-delete-confirmation',
      );
      await tester.tap(find.text('取消'));
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(
          const Key('conversation-row-delete:dm:peer-scope:v1:hermes-ui'),
        ),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:hermes-ui')),
      );
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('chat-information-button')), findsOneWidget);
      expect(
        find.byKey(const Key('chat-message-bubble:human-image-1')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '04-compact-chat');

      await tester.tap(find.byKey(const Key('chat-information-button')));
      await _pumpVisualFrames(tester);
      expect(find.text('聊天信息'), findsOneWidget);
      expect(
        find.byKey(const Key('chat-information-peer-row')),
        findsOneWidget,
      );
      expect(find.text('查找聊天记录'), findsOneWidget);
      expect(find.text('消息免打扰'), findsOneWidget);
      expect(find.text('置顶聊天'), findsOneWidget);
      expect(find.text('移出消息列表'), findsOneWidget);
      await _captureScreenshot(tester, '21-compact-chat-information');
      await tester.tap(find.byKey(const Key('chat-information-back-button')));
      await _pumpVisualFrames(tester);

      final compactImage = find.byKey(
        const Key('chat-image-interaction:human-image-1'),
      );
      await tester.longPress(compactImage);
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('compact-action-sheet')), findsOneWidget);
      await _captureScreenshot(tester, '18-compact-image-actions');
      await tester.tapAt(const Offset(20, 20));
      await _pumpVisualFrames(tester);

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

      final expandedImage = find.byKey(
        const Key('chat-image-interaction:human-image-1'),
      );
      await tester.tap(expandedImage, buttons: kSecondaryMouseButton);
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(const Key('chat-image-copy-action:human-image-1')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '19-expanded-image-actions');
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
      _expectAgentListStatusOverlay(tester, _daemonDid);
      _expectAgentListStatusOverlay(tester, _runtimeDid);
      _expectCompactAgentTree(
        tester,
        daemonDid: _daemonDid,
        runtimeDids: const <String>['did:test:agent:codex-ui', _runtimeDid],
      );
      _expectCompactAgentGeometry(tester, daemonDid: _daemonDid);
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
      _expectAgentListStatusOverlay(tester, _daemonDid);
      _expectAgentListStatusOverlay(tester, _runtimeDid);
      await _captureScreenshot(tester, '08-expanded-agents');
      await tester.tap(find.byKey(const Key('agents-more-actions-button')));
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(const Key('agent-skill-onboarding-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('agents-list-refresh-button')),
        findsOneWidget,
      );
      expect(find.text('刷新智能体列表'), findsNothing);
      expect(
        find.byKey(const Key('agents-install-daemon-button')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '08b-expanded-agent-actions');
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
      _expectCompactShellHeader(tester, title: '联系人');
      expect(find.byKey(const Key('friends-category-tabs')), findsOneWidget);
      await _captureScreenshot(tester, '09-compact-contacts');

      await tester.tap(find.byKey(const Key('friends-category-tab-following')));
      await _pumpVisualFrames(tester);
      expect(find.text('Bob Li'), findsNothing);
      await _captureScreenshot(tester, '09b-compact-contacts-following');

      await tester.tap(find.byKey(const Key('friends-category-tab-followers')));
      await _pumpVisualFrames(tester);
      expect(find.text('Bob Li'), findsOneWidget);
      await _captureScreenshot(tester, '09c-compact-contacts-followers');

      await tester.tap(find.byKey(const Key('friends-category-tab-groups')));
      await _pumpVisualFrames(tester);
      expect(find.text('Design Lab'), findsOneWidget);
      await _captureScreenshot(tester, '09d-compact-contacts-groups');

      await tester.tap(find.byKey(const Key('friends-category-tab-all')));
      await _pumpVisualFrames(tester);
      await tester.tap(
        find.byKey(const Key('friends-all-contact:did:test:person:alice')),
      );
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(const Key('peer-profile-identity-hero')),
        findsOneWidget,
      );
      expect(
        tester.getSize(
          find.byKey(const Key('peer-profile-send-message-visual')),
        ),
        const Size(84, 40),
      );
      expect(find.byKey(const Key('peer-profile-follow')), findsNothing);
      expect(find.byKey(const Key('peer-profile-unfollow')), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('peer-profile-delete-thread-visual')),
                matching: find.text('删除本地聊天记录'),
              ),
            )
            .style
            ?.fontSize,
        16,
      );
      await _captureScreenshot(tester, '09e-compact-contact-profile');

      await tester.tap(find.bySemanticsLabel('返回'));
      await _pumpVisualFrames(tester);

      await tester.tap(find.bySemanticsLabel('我'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('profile-handle-value')), findsOneWidget);
      expect(find.byKey(const Key('profile-back-button')), findsNothing);
      expect(
        find.byKey(const Key('compact-bottom-navigation')),
        findsOneWidget,
      );
      _expectCompactProfileGeometry(tester);
      await _captureScreenshot(tester, '10-compact-profile');

      await tester.tap(find.byKey(const Key('profile-did-row')));
      await _pumpVisualFrames(tester);
      expect(
        tester.getRect(find.byKey(const Key('profile-navigation-group'))),
        Rect.fromLTWH(0, 354, _compactSize.width, 296),
      );
      expect(
        tester.getRect(find.byKey(const Key('profile-did-details'))),
        Rect.fromLTWH(0, 407, _compactSize.width, 84),
      );
      expect(find.byKey(const Key('profile-did-value')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('profile-copy-did-button'))),
        const Size.square(44),
      );
      expect(find.byKey(const Key('profile-homepage-details')), findsNothing);
      await _captureScreenshot(tester, '10a-compact-profile-did-expanded');

      await tester.tap(find.byKey(const Key('profile-homepage-row')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('profile-did-details')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('profile-homepage-details'))),
        Rect.fromLTWH(0, 460, _compactSize.width, 64),
      );
      expect(find.byKey(const Key('profile-homepage-value')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('profile-homepage-action-target'))),
        const Size.square(44),
      );
      await _captureScreenshot(tester, '10c-compact-profile-homepage-expanded');

      await tester.tap(find.byKey(const Key('profile-identity-document-row')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('profile-homepage-details')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('profile-navigation-group'))),
        Rect.fromLTWH(0, 354, _compactSize.width, 240),
      );
      expect(
        tester.getRect(find.byKey(const Key('profile-identity-empty-state'))),
        Rect.fromLTWH(0, 513, _compactSize.width, 28),
      );
      expect(find.text('暂无资料'), findsOneWidget);
      expect(
        find.byKey(const Key('profile-expanded-identity-summary')),
        findsNothing,
      );
      expect(find.byKey(const Key('profile-expanded-did-row')), findsNothing);
      expect(
        find.byKey(const Key('profile-expanded-homepage-row')),
        findsNothing,
      );
      expect(find.byKey(const Key('profile-identity-document')), findsNothing);
      expect(
        tester.getRect(find.byKey(const Key('profile-settings-row'))),
        Rect.fromLTWH(0, 542, _compactSize.width, 52),
      );
      expect(
        tester
            .widget<Icon>(
              find.byKey(const Key('profile-identity-document-arrow')),
            )
            .icon,
        CupertinoIcons.chevron_down,
      );
      expect(
        find.byKey(const Key('profile-identity-empty-state-text')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '10b-compact-profile-identity-expanded');

      await tester.tap(find.byKey(const Key('profile-identity-document-row')));
      await _pumpVisualFrames(tester);

      await tester.tap(find.byKey(const Key('profile-settings-row')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('settings-tenant-row')), findsNothing);
      expect(
        find.byKey(const Key('settings-current-version-row')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('compact-bottom-navigation')), findsNothing);
      _expectCompactSettingsGeometry(tester);
      await _captureScreenshot(tester, '11-compact-settings');

      final securityGroup = find.byKey(const Key('settings-security-group'));
      expect(tester.getSize(securityGroup).width, _compactSize.width);
      expect(tester.getSize(securityGroup).height, 223);
      expect(
        tester.getSize(
          find.byKey(const Key('settings-delete-credential-icon')),
        ),
        const Size.square(24),
      );
      await _captureScreenshot(tester, '11b-compact-settings-danger');

      await tester.tap(find.byKey(const Key('settings-delete-credential-row')));
      await _pumpVisualFrames(tester);
      expect(find.text('退出并删除当前凭证'), findsWidgets);
      expect(find.text('不会注销身份或影响其他设备'), findsOneWidget);
      await _captureScreenshot(
        tester,
        '22-compact-settings-delete-credential-confirmation',
      );
      await tester.tap(find.text('取消'));
      await _pumpVisualFrames(tester);

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
      expect(
        find.byKey(const Key('desktop-current-identity-dialog')),
        findsOneWidget,
      );
      await _captureScreenshot(tester, '13-expanded-profile');

      await tester.tap(find.byKey(const Key('desktop-current-identity-close')));
      await _pumpVisualFrames(tester);

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

      await tester.tapAt(const Offset(8, 400));
      await _pumpVisualFrames(tester);
      await tester.tap(find.bySemanticsLabel('联系人'));
      await _pumpVisualFrames(tester);
      final contactsMoreActions = find.descendant(
        of: find.byKey(const Key('friends-page-surface')),
        matching: find.bySemanticsLabel('更多操作'),
      );
      await tester.tap(contactsMoreActions);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('compact-quick-actions-menu')),
        findsOneWidget,
      );
      expect(find.text('发起新消息'), findsOneWidget);
      await _captureScreenshot(tester, '15b-compact-contacts-quick-actions');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture compact and expanded peer profile', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:alice')),
      );
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-information-button')));
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-information-peer-row')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('peer-info-identity-card')), findsOneWidget);
      await _captureScreenshot(tester, '16-compact-peer-profile');

      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:alice')),
      );
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('peer-info-identity-card')), findsOneWidget);
      await _captureScreenshot(tester, '17-expanded-peer-profile');
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture compact Agent peer info', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpVisualApp(tester, _createAgentPeerInfoVisualHarness());
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:agent-lab')),
      );
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-information-button')));
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-information-peer-row')));
      await _pumpVisualFrames(tester);

      expect(
        find.byKey(const Key('peer-info-compact-agent-layout')),
        findsOneWidget,
      );
      expect(find.text('智能体信息'), findsOneWidget);
      expect(find.text('Agent Lab'), findsOneWidget);
      expect(find.text('@skill-agent'), findsOneWidget);
      expect(find.text('未关注'), findsOneWidget);
      expect(
        find.byKey(const Key('peer-info-agent-rename-button')),
        findsNothing,
      );
      _expectCompactAgentPeerInfoGeometry(tester);
      await _captureScreenshot(tester, '20-compact-agent-peer-info');
    } finally {
      await _resetEnvironment(tester);
    }
  });
}

Future<void> _loadGoldenFont() async {
  await Future.wait(<Future<void>>[
    _loadFont(
      family: _goldenFontFamily,
      asset: 'assets/fonts/awiki_golden_cjk.ttf',
    ),
    _loadFont(
      family: 'MaterialIcons',
      asset: 'fonts/MaterialIcons-Regular.otf',
    ),
    _loadFont(
      family: 'packages/cupertino_icons/CupertinoIcons',
      asset: 'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    ),
  ]);
}

Future<void> _loadFont({required String family, required String asset}) async {
  final data = await rootBundle.load(asset);
  await (FontLoader(family)..addFont(Future.value(data))).load();
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
        testFontFamily: _goldenFontFamily,
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
    bio: '',
    tags: <String>[],
    profileMarkdown:
        '''
我的短号(handle)：ui-reviewer.awiki.ai
DID: $_sessionDid
''',
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
    messageSyncService: harness.messageSyncService,
    agentControlService: harness.agentControlService,
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
      groupProvider.overrideWith(
        (ref) => _StaticGroupController(
          ref,
          GroupState(
            groups: <GroupSummary>[
              GroupSummary(
                groupId: 'did:test:group:design-lab',
                conversationId: 'group:did:test:group:design-lab',
                name: 'Design Lab',
                description: '产品设计与评审',
                memberCount: 8,
                lastMessageAt: DateTime(2026, 8, 2),
              ),
              GroupSummary(
                groupId: 'did:test:group:awiki-beta',
                conversationId: 'group:did:test:group:awiki-beta',
                name: 'AWiki Beta',
                description: '内测反馈与协作',
                memberCount: 16,
                lastMessageAt: DateTime(2026, 8, 1),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

FakeAwikiMeAppHarness _createAgentPeerInfoVisualHarness() {
  const profile = UserProfile(
    did: _sessionDid,
    displayName: 'UI Reviewer',
    bio: '',
    tags: <String>[],
    profileMarkdown: '',
    handle: 'ui-reviewer.awiki.ai',
    fullHandle: 'ui-reviewer.awiki.ai',
  );
  const agentProfile = UserProfile(
    did: _agentInfoDid,
    displayName: 'Agent Lab',
    bio: '',
    tags: <String>[],
    profileMarkdown: '',
    handle: 'skill-agent',
    fullHandle: 'skill-cc44721e0153c892.agent-connect.cn',
  );
  final conversation = ConversationSummary(
    threadId: 'dm:peer-scope:v1:agent-lab',
    conversationId: 'dm:peer-scope:v1:agent-lab',
    displayName: 'Agent Lab',
    lastMessagePreview: '技能智能体已准备好。',
    lastMessageAt: DateTime(2026, 8, 1, 11, 30),
    unreadCount: 0,
    isGroup: false,
    targetDid: _agentInfoDid,
    targetPeer: 'skill-agent',
  );
  final harness = createFakeAwikiMeAppHarness(
    session: _session,
    profile: profile,
  );
  harness.gateway
    ..conversations = <ConversationSummary>[conversation]
    ..publicProfilesByQuery = const <String, UserProfile>{
      _agentInfoDid: agentProfile,
      'skill-agent': agentProfile,
    }
    ..following = <RelationshipSummary>[];
  final control =
      harness.bootstrap.agentControlService!
          as test_support.FakeAgentControlService;
  control.agents = <AgentSummary>[];
  return FakeAwikiMeAppHarness(
    bootstrap: harness.bootstrap,
    gateway: harness.gateway,
    realtimeGateway: harness.realtimeGateway,
    messageSyncService: harness.messageSyncService,
    agentControlService: harness.agentControlService,
    notificationFacade: harness.notificationFacade,
    providerOverrides: <Override>[
      ...harness.providerOverrides,
      conversationListProvider.overrideWith(
        (ref) => _StaticConversationListController(ref, <ConversationSummary>[
          conversation,
        ]),
      ),
      friendsProvider.overrideWith(
        (ref) => _StaticFriendsController(ref, const FriendsState()),
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
  final visualImagePath = File(
    'assets/branding/awiki-me-logo.png',
  ).absolute.path;
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
      localId: 'human-image-1',
      threadId: 'dm:peer-scope:v1:hermes-ui',
      senderDid: _session.did,
      senderName: _session.displayName,
      content: '',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime(2026, 7, 25, 10, 31),
      isMine: true,
      sendState: MessageSendState.sent,
      attachment: ChatAttachment(
        attachmentId: 'att-visual-image',
        filename: 'awiki-me-logo.png',
        mimeType: 'image/png',
        sizeBytes: 194410,
        localPath: visualImagePath,
        hasLocalSource: true,
      ),
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
        testFontFamily: _goldenFontFamily,
      ),
    ),
  );
  await _pumpVisualFrames(tester);
}

void _expectAgentListStatusOverlay(WidgetTester tester, String agentDid) {
  final anchor = find.byKey(Key('agent-list-status-anchor-$agentDid'));
  expect(anchor, findsOneWidget);
  final anchorWidget = tester.widget(anchor);
  if (anchorWidget is AgentStatusDot) {
    final icon = find.byKey(Key('agent-list-kind-icon-$agentDid'));
    expect(anchorWidget.size, 8);
    expect(tester.getCenter(anchor).dy, greaterThan(tester.getCenter(icon).dy));
    return;
  }

  final indicator = find.descendant(
    of: anchor,
    matching: find.byType(AgentStatusDot),
  );
  expect(indicator, findsOneWidget);
  final anchorRect = tester.getRect(anchor);
  final indicatorCenter = tester.getCenter(indicator);
  expect(indicatorCenter.dx, greaterThan(anchorRect.center.dx));
  expect(indicatorCenter.dy, greaterThan(anchorRect.center.dy));
}

void _expectCompactAgentTree(
  WidgetTester tester, {
  required String daemonDid,
  required List<String> runtimeDids,
}) {
  final vertical = find.byKey(Key('agent-tree-vertical-$daemonDid'));
  final verticalRect = tester.getRect(vertical);
  final runtimeCenters = <double>[];

  expect(vertical, findsOneWidget);
  for (final runtimeDid in runtimeDids) {
    final branch = find.byKey(Key('agent-tree-branch-$runtimeDid'));
    final icon = find.byKey(Key('agent-list-kind-icon-$runtimeDid'));
    final branchRect = tester.getRect(branch);
    final iconRect = tester.getRect(icon);

    expect(branch, findsOneWidget);
    expect(branchRect.left, closeTo(verticalRect.center.dx, 0.6));
    expect(branchRect.right, closeTo(iconRect.left, 0.6));
    expect(branchRect.center.dy, closeTo(iconRect.center.dy, 0.6));
    runtimeCenters.add(iconRect.center.dy);
  }
  expect(verticalRect.top, lessThan(runtimeCenters.first));
  expect(verticalRect.bottom, greaterThan(runtimeCenters.last));
}

void _expectCompactAgentGeometry(
  WidgetTester tester, {
  required String daemonDid,
}) {
  final header = tester.getRect(
    find.byKey(const Key('agents-compact-list-header')),
  );
  final section = tester.getRect(
    find.byKey(const Key('agents-compact-section-header')),
  );
  final daemon = tester.getRect(find.byKey(Key('agent-list-tile-$daemonDid')));
  final install = tester.getRect(
    find.byKey(const Key('agents-install-daemon-row')),
  );

  expect(header.height, closeTo(64, 0.1));
  final title = tester.widget<Text>(
    find.descendant(
      of: find.byKey(const Key('agents-compact-list-header')),
      matching: find.text('智能体'),
    ),
  );
  expect(title.style?.fontSize, 16);
  expect(title.style?.fontWeight, FontWeight.w400);
  expect(title.style?.height, 1.25);
  expect(
    tester.widget<ColoredBox>(find.byKey(const Key('agents-list-pane'))).color,
    AwikiMeColors.background,
  );
  expect(section.top, closeTo(64, 0.1));
  expect(section.height, closeTo(60, 0.1));
  final sectionSurface = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byKey(const Key('agents-compact-section-header')),
      matching: find.byType(DecoratedBox),
    ),
  );
  final sectionDecoration = sectionSurface.decoration as BoxDecoration;
  expect(sectionDecoration.color, AwikiMeColors.surface);
  expect(
    (sectionDecoration.border! as Border).bottom.color,
    AwikiMeColors.border,
  );
  expect(
    tester.getCenter(find.byKey(const Key('agents-more-actions-button'))).dx,
    closeTo(300 + (_compactSize.width - 390), 1.5),
  );
  expect(
    tester.getCenter(find.byKey(const Key('agents-install-daemon-button'))).dx,
    closeTo(356 + (_compactSize.width - 390), 1.5),
  );
  expect(daemon.top, closeTo(124, 0.1));
  expect(daemon.height, closeTo(65, 0.1));
  expect(install.top, closeTo(340, 0.1));
  expect(install.height, closeTo(56, 0.1));
}

void _expectCompactProfileGeometry(WidgetTester tester) {
  final header = tester.getRect(
    find.byKey(const Key('profile-compact-header')),
  );
  final avatar = tester.getRect(find.byKey(const Key('profile-avatar')));
  final statistics = tester.getRect(
    find.byKey(const Key('profile-statistics')),
  );
  final navigationGroup = find.byKey(const Key('profile-navigation-group'));
  final navigation = tester.getRect(navigationGroup);
  final did = tester.getRect(find.byKey(const Key('profile-did-row')));
  final homepage = tester.getRect(
    find.byKey(const Key('profile-homepage-row')),
  );
  final identity = tester.getRect(
    find.byKey(const Key('profile-identity-document-row')),
  );
  final settings = tester.getRect(
    find.byKey(const Key('profile-settings-row')),
  );

  expect(header, Rect.fromLTWH(0, 0, _compactSize.width, 64));
  final title = tester.widget<Text>(
    find.descendant(
      of: find.byKey(const Key('profile-compact-header')),
      matching: find.text('我'),
    ),
  );
  expect(title.style?.fontSize, 16);
  expect(title.style?.fontWeight, FontWeight.w400);
  expect(title.style?.height, 1.25);
  expect(
    tester
        .widget<ColoredBox>(find.byKey(const Key('shell-tab-page-surface')))
        .color,
    AwikiMeColors.background,
  );
  final headerDecoration =
      tester
              .widget<DecoratedBox>(
                find.byKey(const Key('profile-compact-header')),
              )
              .decoration
          as BoxDecoration;
  expect(headerDecoration.color, AwikiMeColors.surface);
  expect(headerDecoration.border, isNull);
  expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
  expect(avatar, Rect.fromLTWH((_compactSize.width - 104) / 2, 104, 104, 104));
  final handle = tester.widget<Text>(
    find.byKey(const Key('profile-handle-value')),
  );
  expect(handle.maxLines, 1);
  expect(handle.softWrap, isFalse);
  expect(
    tester.getSize(find.byKey(const Key('profile-edit-button'))),
    const Size.square(44),
  );
  expect(statistics, Rect.fromLTWH(16, 292, _compactSize.width - 32, 30));
  expect(
    tester.getRect(find.byKey(const Key('profile-statistics-divider'))),
    Rect.fromLTWH((_compactSize.width / 2) - 0.5, 292, 1, 30),
  );
  expect(find.byKey(const Key('profile-metadata-card')), findsNothing);
  expect(
    tester.getRect(find.byKey(const Key('profile-navigation-top-divider'))),
    Rect.fromLTWH(0, 354, _compactSize.width, 1),
  );
  expect(navigation, Rect.fromLTWH(0, 354, _compactSize.width, 212));
  expect(did, Rect.fromLTWH(0, 355, _compactSize.width, 52));
  expect(
    tester.getRect(find.byKey(const Key('profile-did-icon-target'))),
    const Rect.fromLTWH(16, 359, 44, 44),
  );
  expect(
    tester.getRect(find.byKey(const Key('profile-did-divider'))),
    Rect.fromLTWH(0, 407, _compactSize.width, 1),
  );
  expect(homepage, Rect.fromLTWH(0, 408, _compactSize.width, 52));
  expect(
    tester.getRect(find.byKey(const Key('profile-homepage-divider'))),
    Rect.fromLTWH(0, 460, _compactSize.width, 1),
  );
  expect(identity, Rect.fromLTWH(0, 461, _compactSize.width, 52));
  expect(
    tester.getSize(find.byKey(const Key('profile-did-icon-target'))),
    const Size.square(44),
  );
  expect(
    tester.getSize(find.byKey(const Key('profile-homepage-icon-target'))),
    const Size.square(44),
  );
  expect(
    tester.getRect(
      find.byKey(const Key('profile-identity-document-icon-target')),
    ),
    const Rect.fromLTWH(16, 465, 44, 44),
  );
  expect(
    tester.getRect(find.byKey(const Key('profile-identity-document-icon-box'))),
    const Rect.fromLTWH(27, 476, 22, 22),
  );
  for (final title in <String>['DID', '主页', '身份卡', '设置']) {
    final text = tester.widget<Text>(find.text(title));
    expect(text.style?.fontSize, 16);
    expect(text.style?.fontWeight, FontWeight.w400);
    expect(text.style?.height, 1.25);
  }
  expect(find.byKey(const Key('profile-did-value')), findsNothing);
  expect(find.byKey(const Key('profile-homepage-value')), findsNothing);
  expect(
    tester.widget<Icon>(find.byKey(const Key('profile-did-arrow'))).icon,
    CupertinoIcons.chevron_right,
  );
  expect(
    tester.widget<Icon>(find.byKey(const Key('profile-homepage-arrow'))).icon,
    CupertinoIcons.chevron_right,
  );
  expect(tester.getRect(find.text('身份卡')).left, closeTo(68, 0.1));
  final identityTitle = tester.widget<Text>(find.text('身份卡'));
  expect(identityTitle.style?.fontSize, 16);
  expect(identityTitle.style?.fontWeight, FontWeight.w400);
  expect(identityTitle.style?.height, 1.25);
  expect(find.text('完整资料，让协作更可信'), findsNothing);
  expect(find.byKey(const Key('profile-identity-empty-state')), findsNothing);
  expect(
    find.byKey(const Key('profile-expanded-identity-summary')),
    findsNothing,
  );
  expect(find.byKey(const Key('profile-expanded-did-row')), findsNothing);
  expect(find.byKey(const Key('profile-expanded-homepage-row')), findsNothing);
  expect(
    tester
        .widget<Icon>(find.byKey(const Key('profile-identity-document-arrow')))
        .size,
    18,
  );
  expect(settings, Rect.fromLTWH(0, 514, _compactSize.width, 52));
  expect(
    tester.getRect(find.byKey(const Key('profile-navigation-divider'))),
    Rect.fromLTWH(0, 513, _compactSize.width, 1),
  );
  expect(find.byKey(const Key('profile-identity-document')), findsNothing);
}

void _expectCompactSettingsGeometry(WidgetTester tester) {
  final header = tester.getRect(
    find.byKey(const Key('settings-compact-header')),
  );
  final avatar = tester.getRect(
    find.byKey(const Key('settings-profile-avatar')),
  );
  final account = tester.getRect(
    find.byKey(const Key('settings-account-group')),
  );
  final app = tester.getRect(find.byKey(const Key('settings-app-group')));
  final security = tester.getRect(
    find.byKey(const Key('settings-security-group')),
  );

  expect(header.height, closeTo(64, 0.1));
  expect(
    tester
        .widget<CupertinoPageScaffold>(find.byType(CupertinoPageScaffold))
        .backgroundColor,
    AwikiMeColors.background,
  );
  expect(
    tester.getRect(find.byKey(const Key('settings-back-button'))),
    const Rect.fromLTWH(8, 10, 44, 44),
  );
  expect(avatar.left, closeTo(20, 0.1));
  expect(avatar.top, closeTo(87, 0.1));
  expect(avatar.size, const Size.square(58));
  expect(account.top, closeTo(208, 0.1));
  expect(account.left, 0);
  expect(account.width, _compactSize.width);
  expect(account.height, closeTo(146, 0.1));
  expect(
    tester.getSize(find.byKey(const Key('settings-devices-row'))).height,
    closeTo(72, 0.1),
  );
  expect(
    tester.getSize(find.byKey(const Key('settings-personal-agent-row'))).height,
    closeTo(72, 0.1),
  );
  expect(app.top, closeTo(394, 0.1));
  expect(app.left, 0);
  expect(app.width, _compactSize.width);
  expect(app.height, closeTo(183, 0.1));
  expect(
    tester
        .getSize(find.byKey(const Key('settings-current-version-row')))
        .height,
    closeTo(60, 0.1),
  );
  expect(
    tester.getSize(find.byKey(const Key('settings-check-updates-row'))).height,
    closeTo(60, 0.1),
  );
  expect(
    tester.getSize(find.byKey(const Key('settings-language-row'))).height,
    closeTo(60, 0.1),
  );
  expect(security.top, closeTo(617, 0.1));
  expect(security.left, 0);
  expect(security.width, _compactSize.width);
  expect(security.height, closeTo(223, 0.1));
  expect(
    tester
        .getSize(find.byKey(const Key('settings-export-credential-row')))
        .height,
    closeTo(68, 0.1),
  );
  expect(
    tester.getSize(find.byKey(const Key('settings-logout-row'))).height,
    closeTo(68, 0.1),
  );
  expect(
    tester
        .getSize(find.byKey(const Key('settings-delete-credential-row')))
        .height,
    closeTo(84, 0.1),
  );
  expect(find.byKey(const Key('settings-danger-section-title')), findsNothing);
  expect(
    tester.getSize(find.byKey(const Key('settings-current-version-icon'))),
    const Size.square(24),
  );
  expect(
    find.descendant(
      of: find.byKey(const Key('settings-current-version-row')),
      matching: find.byIcon(CupertinoIcons.chevron_right),
    ),
    findsNothing,
  );
}

void _expectCompactShellHeader(WidgetTester tester, {required String title}) {
  final header = find.byKey(const Key('shell-compact-header'));
  expect(tester.getRect(header).height, closeTo(64, 0.1));
  final titleText = tester.widget<Text>(
    find.descendant(of: header, matching: find.text(title)),
  );
  expect(titleText.style?.fontSize, 16);
  expect(titleText.style?.fontWeight, FontWeight.w400);
  expect(titleText.style?.height, 1.25);
  expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
}

void _expectCompactAgentPeerInfoGeometry(WidgetTester tester) {
  final header = tester.getRect(
    find.byKey(const Key('peer-info-compact-agent-header')),
  );
  final avatar = tester.getRect(find.byKey(const Key('peer-info-avatar')));
  final follow = tester.getRect(find.byKey(const Key('chat-follow-button')));
  final badges = tester.getRect(
    find.byKey(const Key('peer-info-compact-agent-badges')),
  );
  final did = tester.getRect(
    find.byKey(const Key('peer-info-compact-agent-did-row')),
  );
  final homepage = tester.getRect(
    find.byKey(const Key('peer-info-compact-agent-homepage-row')),
  );
  final identity = tester.getRect(
    find.byKey(const Key('peer-info-identity-document')),
  );

  expect(header.height, closeTo(64, 0.1));
  expect(avatar.top, closeTo(92, 0.1));
  expect(avatar.size, const Size.square(80));
  expect(avatar.center.dx, closeTo(_compactSize.width / 2, 0.1));
  expect(follow.top, closeTo(274, 0.1));
  expect(follow.size, const Size(198, 48));
  expect(follow.center.dx, closeTo(_compactSize.width / 2, 0.1));
  expect(badges.top, closeTo(344, 0.1));
  expect(did.top, closeTo(414, 0.1));
  expect(homepage.top, closeTo(484, 0.1));
  expect(identity.left, closeTo(24, 0.1));
  expect(identity.top, closeTo(570, 0.1));
  expect(identity.width, closeTo(_compactSize.width - 48, 0.1));
  expect(identity.height, closeTo(104, 0.1));
  expect(find.byKey(const Key('compact-bottom-navigation')), findsNothing);
}

Future<void> _captureScreenshot(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureBoundaryKey),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final bytes = byteData!.buffer.asUint8List();
  final golden = File('$_screenshotsDir/$name.png');
  if (autoUpdateGoldenFiles) {
    await golden.parent.create(recursive: true);
    await golden.writeAsBytes(bytes, flush: true);
  } else {
    expect(
      golden.existsSync(),
      isTrue,
      reason: 'Missing visual baseline. Run this test with --update-goldens.',
    );
    expect(
      bytes,
      orderedEquals(await golden.readAsBytes()),
      reason: '$name changed. Review it before using --update-goldens.',
    );
  }
  image.dispose();
}

Future<void> _pumpVisualFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 360));
}
