import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/app/app_appearance.dart';
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
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:awiki_me/src/presentation/shared/widgets/awiki_glass.dart';
import 'package:awiki_me/src/presentation/shared/widgets/awiki_desktop.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoIcons, CupertinoPageRoute, CupertinoPageScaffold;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter/widgets.dart'
    show
        Brightness,
        EditableText,
        FontWeight,
        Key,
        Navigator,
        NavigatorState,
        Offset,
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
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  testWidgets('reference matrix renders login and chat in both appearances', (
    tester,
  ) async {
    const sizes = [
      Size(360, 800),
      Size(390, 844),
      Size(430, 932),
      Size(600, 960),
      Size(820, 1180),
      Size(1024, 768),
      Size(1366, 768),
      Size(1440, 900),
      Size(1920, 1080),
    ];
    try {
      for (final appearance in [AppAppearance.light, AppAppearance.dark]) {
        final brightness = appearance == AppAppearance.dark
            ? Brightness.dark
            : Brightness.light;
        for (final size in sizes) {
          final platform = size.width < 700
              ? TargetPlatform.iOS
              : TargetPlatform.macOS;
          final name =
              'reference-${appearance.name}-${size.width.toInt()}x${size.height.toInt()}';
          await _prepareEnvironment(tester, size: size, platform: platform);
          await _pumpOnboarding(tester, appearance: appearance);
          final login = find.byKey(const Key('onboarding-mac-auth-card'));
          expect(login, findsOneWidget);
          expect(
            tester.element(login).awikiTheme.colorScheme.brightness,
            brightness,
          );
          expect(tester.takeException(), isNull, reason: '$name login layout');
          await _captureScreenshot(tester, '$name-login');

          await _prepareEnvironment(tester, size: size, platform: platform);
          await _pumpVisualApp(
            tester,
            _createVisualHarness(),
            appearance: appearance,
          );
          final row = find.byKey(
            const Key('conversation-row:dm:peer-scope:v1:hermes-ui'),
          );
          expect(row, findsOneWidget);
          expect(
            tester.element(row).awikiTheme.colorScheme.brightness,
            brightness,
          );
          expect(tester.takeException(), isNull, reason: '$name list layout');
          await _captureScreenshot(tester, '$name-list');
          await tester.tap(row);
          await _pumpVisualFrames(tester);
          final input = find.byKey(const Key('chat-composer-input'));
          expect(input, findsOneWidget);
          if (find
              .byKey(const Key('chat-compact-composer'))
              .evaluate()
              .isNotEmpty) {
            final send = find.byKey(const Key('chat-send-button'));
            expect(tester.widget<AppIconButton>(send).onPressed, isNull);
            expect(tester.widget<AppIconButton>(send).semanticLabel, '发送');
            expect(
              tester
                  .getRect(find.byKey(const Key('chat-attachment-button')))
                  .right,
              lessThan(tester.getRect(input).left),
            );
          }
          expect(
            tester.element(input).awikiTheme.colorScheme.brightness,
            brightness,
          );
          expect(tester.takeException(), isNull, reason: '$name chat layout');
          await _captureScreenshot(tester, '$name-chat');
          if (size == const Size(390, 844)) {
            await tester.enterText(input, '第一行草稿\n第二行草稿\n第三行草稿');
            await _pumpVisualFrames(tester);
            expect(
              tester.takeException(),
              isNull,
              reason: '$name multiline composer',
            );
            await _captureScreenshot(tester, '$name-composer');
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await _pumpVisualFrames(tester);
            expect(
              tester.getRect(find.byKey(const Key('chat-send-button'))).bottom,
              lessThanOrEqualTo(size.height - 300),
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$name keyboard composer',
            );
            await _captureScreenshot(tester, '$name-keyboard');
            tester.view.resetViewInsets();
          }
        }
      }
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('design tour renders every module in both appearances', (
    tester,
  ) async {
    Future<void> openApp(
      AppAppearance appearance,
      Size size,
      TargetPlatform platform,
    ) async {
      await _prepareEnvironment(tester, size: size, platform: platform);
      await _pumpVisualApp(
        tester,
        _createVisualHarness(),
        appearance: appearance,
      );
    }

    Future<void> tapKey(String key) async {
      await tester.tap(find.byKey(Key(key)).first);
      await _pumpVisualFrames(tester);
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      await _captureScreenshot(tester, name);
    }

    try {
      for (final appearance in [AppAppearance.light, AppAppearance.dark]) {
        final phone = 'tour-${appearance.name}-phone';
        await openApp(appearance, const Size(390, 844), TargetPlatform.iOS);
        await capture('$phone-messages');
        await tapKey('conversation-row:dm:peer-scope:v1:hermes-ui');
        await capture('$phone-chat');
        await tapKey('chat-back-button');
        await tapKey('conversation-row:group:did:test:group:product');
        await capture('$phone-group-chat');
        await tapKey('chat-back-button');
        await tapKey('compact-nav-agents');
        await capture('$phone-agents');
        await tapKey('compact-nav-contacts');
        await capture('$phone-contacts');
        await tapKey('friends-all-contact:did:test:person:alice');
        await capture('$phone-peer-profile');

        await openApp(appearance, const Size(390, 844), TargetPlatform.iOS);
        await tapKey('compact-nav-profile');
        await capture('$phone-me');
        await tapKey('profile-settings-row');
        await capture('$phone-settings');
        await tapKey('settings-devices-row');
        await capture('$phone-devices');

        final desk = 'tour-${appearance.name}-desk';
        await openApp(appearance, const Size(1440, 900), TargetPlatform.macOS);
        await tapKey('conversation-row:dm:peer-scope:v1:hermes-ui');
        await capture('$desk-messages');
        await tapKey('conversation-quick-actions-button');
        await tapKey('quick-action-start-conversation');
        await capture('$desk-start-chat');
        await tester.tapAt(const Offset(8, 450));
        await _pumpVisualFrames(tester);
        await tapKey('desktop-rail-agents');
        await capture('$desk-agents');
        await tapKey('desktop-rail-contacts');
        await capture('$desk-contacts');
        await tapKey('desktop-rail-settings');
        await capture('$desk-settings');
        if (find
            .byKey(const Key('settings-devices-row'))
            .evaluate()
            .isNotEmpty) {
          await tapKey('settings-devices-row');
          await capture('$desk-devices');
        }
      }
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('glass audit renders secondary phone surfaces', (tester) async {
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      await _captureScreenshot(tester, name);
    }

    Future<void> tapKey(String key) async {
      final finder = find.byKey(Key(key)).first;
      await tester.ensureVisible(finder);
      await _pumpVisualFrames(tester);
      await tester.tap(finder);
      await _pumpVisualFrames(tester);
    }

    Future<void> popTop() async {
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      navigator.pop();
      await _pumpVisualFrames(tester);
    }

    try {
      for (final appearance in [AppAppearance.light, AppAppearance.dark]) {
        final name = 'audit-${appearance.name}';
        await _prepareEnvironment(
          tester,
          size: const Size(390, 844),
          platform: TargetPlatform.iOS,
        );
        await _pumpOnboarding(tester, appearance: appearance);
        await tapKey('onboarding-tenant-switcher-button');
        await capture('$name-tenant-menu');
        await tester.tapAt(const Offset(40, 700));
        await _pumpVisualFrames(tester);
        final loginNavigator = Navigator.of(
          tester.element(find.byKey(const Key('onboarding-mac-auth-card'))),
        );
        unawaited(
          loginNavigator.push(
            CupertinoPageRoute<void>(builder: (_) => const DeviceJoinPage()),
          ),
        );
        await _pumpVisualFrames(tester);
        await capture('$name-device-join');

        await _prepareEnvironment(
          tester,
          size: const Size(390, 844),
          platform: TargetPlatform.iOS,
        );
        await _pumpVisualApp(
          tester,
          _createVisualHarness(),
          appearance: appearance,
        );
        await tapKey('shell-quick-actions-button');
        await capture('$name-quick-actions');
        await tapKey('quick-action-start-conversation');
        await capture('$name-start-chat');
        await tester.tapAt(const Offset(8, 60));
        await _pumpVisualFrames(tester);
        await tapKey('conversation-row:dm:peer-scope:v1:hermes-ui');
        await tapKey('chat-information-button');
        await capture('$name-chat-information');
        await tapKey('chat-information-back-button');
        await tapKey('chat-back-button');
        await tapKey('compact-nav-contacts');
        await tapKey('friends-category-tab-groups');
        await capture('$name-groups');
        await tapKey('compact-nav-profile');
        await tapKey('profile-edit-button');
        await capture('$name-profile-edit');
        await popTop();
        await tapKey('profile-settings-row');
        await tapKey('settings-language-row');
        await capture('$name-language');
        await popTop();
        await tapKey('settings-display-row');
        await capture('$name-display');
        await popTop();
        await tapKey('settings-logout-row');
        await capture('$name-logout-dialog');
      }
    } finally {
      await _resetEnvironment(tester);
    }
  });

  testWidgets('capture compact and expanded onboarding', (tester) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _compactSize,
        platform: TargetPlatform.iOS,
      );
      await _pumpOnboarding(tester);
      expect(find.byKey(const Key('onboarding-mac-auth-card')), findsOneWidget);
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
      expect(find.byKey(const Key('onboarding-brand-pane')), findsOneWidget);
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
    final semantics = tester.ensureSemantics();
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
      await _verifyConversationFilters(tester);

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
      expect(find.text('同时清空历史消息'), findsNothing);
      expect(find.text('单会话历史清理待 Core 支持'), findsNothing);
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
      await _verifyConversationFilters(tester);
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:hermes-ui')),
      );
      await _pumpVisualFrames(tester);
      expect(find.text('product-brief.pdf'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('mac-desktop-rail-slot'))).width,
        closeTo(68 * AwikiDisplayScale.layoutBaseline, 0.1),
      );
      expect(
        tester
            .getSize(find.byKey(const Key('mac-conversation-list-pane')))
            .width,
        closeTo(264 * AwikiDisplayScale.layoutBaseline, 0.1),
      );
      expect(find.byTooltip('消息'), findsOneWidget);
      expect(find.bySemanticsLabel('消息'), findsOneWidget);
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
      semantics.dispose();
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
      await tester.tap(find.byKey(const Key('compact-nav-agents')));
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
      await tester.tap(find.byKey(const Key('desktop-rail-agents')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('agents-expanded-layout')), findsOneWidget);
      _expectExpandedAgentHeaderUsesAvailableWidth(tester);
      expect(
        tester.widget(find.byKey(const Key('agents-more-actions-button'))),
        isA<AwikiSoftIconButton>(),
      );
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
        const Size(32, 32),
      );
      expect(find.byKey(const Key('peer-profile-follow')), findsNothing);
      expect(find.byKey(const Key('peer-profile-unfollow')), findsOneWidget);
      expect(find.text('已关注'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('peer-profile-delete-thread-visual')),
                matching: find.text('清空聊天记录'),
              ),
            )
            .style
            ?.fontSize,
        16,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('peer-profile-delete-thread-visual')))
            .height,
        52,
      );
      await _captureScreenshot(tester, '09e-compact-contact-profile');

      await tester.tap(find.bySemanticsLabel('返回'));
      await _pumpVisualFrames(tester);

      await tester.tap(find.bySemanticsLabel('我的'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('profile-compact-summary')), findsOneWidget);
      expect(find.byKey(const Key('profile-back-button')), findsNothing);
      expect(
        find.byKey(const Key('compact-bottom-navigation')),
        findsOneWidget,
      );
      _expectCompactProfileGeometry(tester);
      await _captureScreenshot(tester, '10-compact-profile');

      // Compact identity-card editing was replaced by the owned profile editor.
      await tester.tap(find.byKey(const Key('profile-edit-button')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.byKey(const Key('profile-edit-page')), findsOneWidget);
      expect(find.byKey(const Key('profile-edit-dialog')), findsNothing);
      expect(
        find.byKey(const Key('profile-edit-nickname-row')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-edit-bio-row')), findsOneWidget);
      expect(find.byKey(const Key('profile-edit-tags-row')), findsOneWidget);
      expect(find.byKey(const Key('profile-edit-save-button')), findsOneWidget);
      await _captureScreenshot(tester, '10b-compact-profile-edit');
      await tester.tap(find.byKey(const Key('profile-edit-back-button')));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      expect(find.byKey(const Key('profile-edit-page')), findsNothing);
      _expectCompactProfileGeometry(tester);

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
      expect(tester.getSize(securityGroup).width, _compactSize.width - 32);
      expect(
        tester.getSize(
          find.byKey(const Key('settings-delete-credential-icon')),
        ),
        const Size.square(24),
      );
      await _captureScreenshot(tester, '11b-compact-settings-danger');

      await tester.tap(find.byKey(const Key('settings-delete-credential-row')));
      await _pumpVisualFrames(tester);
      expect(find.text('退出并删除当前数据'), findsWidgets);
      expect(find.textContaining('不会注销线上身份或影响其他设备'), findsOneWidget);
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

      await tester.tap(find.bySemanticsLabel('我的'));
      await _pumpVisualFrames(tester);
      expect(
        find.byKey(const Key('desktop-current-identity-dialog')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-settings-row')), findsNothing);
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

  testWidgets('display scale ticks switch presets from settings', (
    tester,
  ) async {
    try {
      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      await _pumpVisualApp(tester, _createVisualHarness());
      await tester.tap(find.bySemanticsLabel('设置'));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('mac-settings-list-pane')), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings-display-row')));
      await _pumpVisualFrames(tester);

      for (final percent in <int>[90, 100, 110, 120]) {
        expect(find.byKey(Key('display-scale-tick-$percent')), findsOneWidget);
      }
      final sliderRect = tester.getRect(
        find.byKey(const Key('display-scale-slider')),
      );
      await tester.tapAt(
        Offset(
          sliderRect.left + 22 + (sliderRect.width - 44) * 0.72,
          sliderRect.center.dy,
        ),
      );
      await _pumpVisualFrames(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('display-scale-value'))).data,
        '120%',
      );
      await tester.tap(find.byKey(const Key('display-scale-tick-110')));
      await _pumpVisualFrames(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('display-scale-value'))).data,
        '110%',
      );
      await tester.tap(find.byKey(const Key('display-scale-tick-100')));
      await _pumpVisualFrames(tester);
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
      expect(find.text('发起聊天'), findsOneWidget);
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
      expect(find.text('发起聊天'), findsOneWidget);
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
      final compactHarness = _createVisualHarness();
      await _pumpVisualApp(tester, compactHarness);
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:alice')),
      );
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-information-button')));
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-information-peer-row')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('peer-profile-scroll')), findsOneWidget);
      expect(
        compactHarness.gateway.loadPublicProfileQueries,
        contains(_humanDid),
      );
      await _captureScreenshot(tester, '16-compact-peer-profile');

      await _prepareEnvironment(
        tester,
        size: _expandedSize,
        platform: TargetPlatform.macOS,
      );
      final expandedHarness = _createVisualHarness();
      await _pumpVisualApp(tester, expandedHarness);
      await tester.tap(
        find.byKey(const Key('conversation-row:dm:peer-scope:v1:alice')),
      );
      await _pumpVisualFrames(tester);
      await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
      await _pumpVisualFrames(tester);
      expect(find.byKey(const Key('peer-profile-scroll')), findsOneWidget);
      expect(
        expandedHarness.gateway.loadPublicProfileQueries,
        contains(_humanDid),
      );
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
  tester.view.resetViewInsets();
}

Future<void> _pumpOnboarding(
  WidgetTester tester, {
  AppAppearance appearance = AppAppearance.light,
}) async {
  final harness = createFakeAwikiMeAppHarness();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureBoundaryKey,
      child: AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: [
          ...harness.providerOverrides,
          initialAppAppearanceProvider.overrideWithValue(appearance),
        ],
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
      latest: test_support.readyDaemonStatusWithAcpCapability,
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
  FakeAwikiMeAppHarness harness, {
  AppAppearance appearance = AppAppearance.light,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureBoundaryKey,
      child: AwikiMeApp(
        bootstrap: harness.bootstrap,
        providerOverrides: [
          ...harness.providerOverrides,
          initialAppAppearanceProvider.overrideWithValue(appearance),
        ],
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
    tester
        .widget<AwikiGlassBackdrop>(find.byKey(const Key('agents-list-pane')))
        .color,
    AwikiMeColors.surface,
  );
  // Section label, glass tree card and install row stack inside a 16-unit
  // gutter under the divider-less header.
  expect(section.top, closeTo(68, 0.1));
  expect(section.left, closeTo(16, 0.1));
  expect(section.height, closeTo(36, 0.1));
  expect(
    tester.getCenter(find.byKey(const Key('agents-install-daemon-button'))).dx,
    closeTo(356 + (_compactSize.width - 390), 1.5),
  );
  expect(daemon.top, closeTo(108, 0.1));
  expect(daemon.height, closeTo(64, 0.1));
  expect(install.height, closeTo(52, 0.1));
  expect(install.left, closeTo(16, 0.1));
}

void _expectCompactProfileGeometry(WidgetTester tester) {
  Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
  final summary = rect('profile-compact-summary');
  final avatar = rect('profile-avatar');
  final navigation = rect('profile-navigation-group');

  // The root Me tab has no title bar; the glass identity card leads.
  expect(find.byKey(const Key('profile-compact-header')), findsNothing);
  expect(
    tester
        .widget<AwikiGlassBackdrop>(
          find.byKey(const Key('shell-tab-page-surface')),
        )
        .color,
    AwikiMeColors.surface,
  );
  expect(summary.left, 16);
  expect(summary.top, 16);
  expect(summary.width, _compactSize.width - 32);
  expect(
    tester.widget(find.byKey(const Key('profile-compact-summary'))),
    isA<AwikiGlassSurface>(),
  );
  expect(avatar.size, const Size.square(64));
  expect(find.byKey(const Key('profile-edit-chevron')), findsOneWidget);
  final displayName = tester.widget<Text>(
    find.byKey(const Key('profile-display-name')),
  );
  expect(displayName.data, 'UI Reviewer');
  expect(displayName.maxLines, 1);
  expect(displayName.style?.fontSize, 20);
  expect(displayName.style?.fontWeight, FontWeight.w400);
  expect(
    tester.widget<Text>(find.byKey(const Key('profile-handle-value'))).data,
    '@ui-reviewer.awiki.ai',
  );
  expect(rect('profile-statistics').height, 30);
  expect(navigation.top - summary.bottom, 14);
  expect(navigation.left, 16);
  expect(navigation.width, _compactSize.width - 32);
  for (final key in [
    'profile-devices-row',
    'profile-homepage-row',
    'profile-settings-row',
  ]) {
    expect(rect(key).height, 52, reason: key);
  }
  for (final text in ['设备管理', '主页', '设置']) {
    final label = tester.widget<Text>(find.text(text));
    expect(label.style?.fontSize, 16);
    expect(label.style?.fontWeight, FontWeight.w400);
  }
  for (final key in [
    'profile-did-row',
    'profile-did-value',
    'profile-identity-document-row',
    'profile-identity-document',
    'profile-identity-empty-state',
  ]) {
    expect(find.byKey(Key(key)), findsNothing);
  }
}

void _expectCompactSettingsGeometry(WidgetTester tester) {
  Rect rect(String key) => tester.getRect(find.byKey(Key(key)));
  final header = rect('settings-compact-header');
  final profile = rect('settings-profile-row');
  final account = rect('settings-account-group');
  final app = rect('settings-app-group');
  final security = rect('settings-security-group');
  expect(header, Rect.fromLTWH(0, 0, _compactSize.width, 64));
  expect(
    tester
        .widget<CupertinoPageScaffold>(find.byType(CupertinoPageScaffold))
        .backgroundColor,
    AwikiMeColors.surface,
  );
  expect(rect('settings-back-button'), const Rect.fromLTWH(12, 10, 44, 44));
  expect(profile.height, 84);
  expect(profile.top, greaterThan(account.top));
  expect(rect('settings-profile-avatar').size, const Size.square(52));
  expect(app.top - account.bottom, 14);
  expect(security.top - app.bottom, 14);
  for (final group in [account, app, security]) {
    expect(group.left, 16);
    expect(group.width, _compactSize.width - 32);
  }
  for (final key in [
    'settings-devices-row',
    'settings-current-version-row',
    'settings-check-updates-row',
    'settings-language-row',
    'settings-recover-handle-did-row',
    'settings-export-credential-row',
    'settings-logout-row',
    'settings-delete-credential-row',
  ]) {
    expect(rect(key).height, 52, reason: key);
  }
  expect(security.bottom, lessThan(_compactSize.height));
  expect(find.byKey(const Key('settings-personal-agent-row')), findsNothing);
  expect(find.byKey(const Key('settings-danger-section-title')), findsNothing);
  expect(rect('settings-current-version-icon').size, const Size.square(24));
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

void _expectExpandedAgentHeaderUsesAvailableWidth(WidgetTester tester) {
  final header = tester.getRect(
    find.byKey(const Key('agents-persistent-detail-header')),
  );
  final identity = tester.getRect(
    find.byKey(const Key('agent-detail-identity-layout')),
  );
  final actions = tester.getRect(
    find.byKey(const Key('agents-persistent-detail-actions')),
  );
  expect(actions.center.dy, closeTo(identity.center.dy, 0.5));
  expect(actions.right, closeTo(header.right - 14.8, 1));
  expect(header.contains(identity.topLeft), isTrue);
  expect(header.contains(identity.bottomRight), isTrue);
  expect(header.contains(actions.topLeft), isTrue);
  expect(header.contains(actions.bottomRight), isTrue);
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

Future<void> _verifyConversationFilters(WidgetTester tester) async {
  final alice = find.byKey(
    const Key('conversation-row:dm:peer-scope:v1:alice'),
  );
  final agent = find.byKey(
    const Key('conversation-row:dm:peer-scope:v1:hermes-ui'),
  );
  final group = find.byKey(
    const Key('conversation-row:group:did:test:group:product'),
  );
  await tester.tap(find.byKey(const Key('conversation-filter-unread')));
  await _pumpVisualFrames(tester);
  expect(alice, findsOneWidget);
  expect(group, findsNothing);
  await tester.tap(find.byKey(const Key('conversation-filter-group')));
  await _pumpVisualFrames(tester);
  expect(group, findsOneWidget);
  expect(alice, findsNothing);
  await tester.tap(find.byKey(const Key('conversation-filter-agent')));
  await _pumpVisualFrames(tester);
  expect(agent, findsOneWidget);
  expect(alice, findsNothing);
  expect(group, findsNothing);
  await tester.tap(find.byKey(const Key('conversation-filter-all')));
  await _pumpVisualFrames(tester);
  expect(alice, findsOneWidget);
  expect(agent, findsOneWidget);
  expect(group, findsOneWidget);
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
