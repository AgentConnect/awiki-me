import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/personal_agent_feature_visibility.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/presentation/agents/agent_inbox_panel.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/presentation/shared/widgets/awiki_glass.dart';

import 'test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'personal agent settings entry remains readable and opens in $brightness',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(1200, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = AwikiMeTheme.forPlatform(
          TargetPlatform.android,
          brightness: brightness,
        );
        final control = FakeAgentControlService()
          ..agents = const [
            AgentSummary(
              agentDid: 'did:agent:daemon',
              kind: AgentKind.daemon,
              handle: 'awiki-daemon-test',
              displayName: 'Daemon',
              activeState: 'active',
              latest: AgentLatestStatus(
                status: 'ready',
                platform: 'linux-amd64',
              ),
            ),
          ];
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: Theme(
              data: theme.materialTheme,
              child: const AgentsWorkspacePage(),
            ),
            session: const SessionIdentity(
              did: 'did:human:me',
              credentialName: 'default',
              displayName: 'Me',
            ),
            providerOverrides: [
              agentControlServiceProvider.overrideWithValue(control),
              identityCorePortProvider.overrideWithValue(
                FakeIdentityCorePort(),
              ),
              agentImEnabledProvider.overrideWithValue(true),
              personalAgentFeatureVisibleProvider.overrideWithValue(true),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey<String>('agent-list-tile-did:agent:daemon'),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(
          const Key('personal-agent-settings-entry-card'),
        );
        expect(entry, findsOneWidget);
        final card = tester.widget<AppPressableTile>(entry);
        expect(card.onTap, isNotNull);
        final background =
            (tester
                        .widget<AnimatedContainer>(
                          find
                              .descendant(
                                of: entry,
                                matching: find.byType(AnimatedContainer),
                              )
                              .first,
                        )
                        .decoration!
                    as BoxDecoration)
                .color!;
        expect(background, theme.tokens.surface);
        for (final item in [
          (
            '个人助理',
            brightness == Brightness.dark
                ? theme.tokens.title
                : const Color(0xFF101B32),
          ),
          (
            '配置个人助理的启用、暂停和 Daemon 管理',
            brightness == Brightness.dark
                ? theme.tokens.secondaryText
                : const Color(0xFF66728A),
          ),
        ]) {
          final label = tester.widget<Text>(
            find.descendant(of: entry, matching: find.text(item.$1)),
          );
          final foreground = label.style!.color!;
          final luminances = [
            foreground.computeLuminance(),
            background.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + 0.05) / (luminances.first + 0.05),
            greaterThanOrEqualTo(4.5),
          );
          expect(foreground, item.$2);
        }
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(PersonalAgentSettingsPage), findsOneWidget);
        expect(control.lastBootstrapDaemonDid, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  final dark = AwikiMeTheme.forPlatform(
    TargetPlatform.android,
    brightness: Brightness.dark,
  );

  testWidgets('compact contacts retain the dark list surface', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Theme(data: dark.materialTheme, child: const FriendsPage()),
      ),
    );
    await tester.pumpAndSettle();
    final surface = tester.widget<AwikiGlassBackdrop>(
      find.byKey(const Key('shell-tab-page-surface')),
    );
    expect(surface.color, dark.tokens.background);
    expect(
      tester.widget<Text>(find.text('联系人').first).style!.color,
      dark.tokens.title,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('agent inbox header, notice and panel use dark semantic colors', (
    tester,
  ) async {
    final conversation = ConversationSummary(
      conversationId: 'dm:dark-panel',
      threadId: 'dm:dark-panel',
      displayName: 'Peer',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 9, 28),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Theme(
          data: dark.materialTheme,
          child: AgentInboxPage(conversation: conversation),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('Agent 收件箱');
    expect(tester.widget<Text>(title).style!.color, dark.tokens.title);
    expect(
      tester.widget<Text>(find.text('当前会话不是 Runtime Agent 会话')).style!.color,
      dark.tokens.secondaryText,
    );
    final panel = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: title, matching: find.byType(DecoratedBox)),
        )
        .where(
          (widget) =>
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  dark.tokens.subtleSurface,
        );
    expect(panel, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
