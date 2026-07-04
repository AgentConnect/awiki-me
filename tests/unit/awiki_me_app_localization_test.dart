import 'dart:async';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/ports/conversation_core_port.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('AwikiMeApp localization', () {
    late AppBootstrap bootstrap;

    setUp(() {
      final gateway = FakeAwikiGateway();
      final realtimeGateway = FakeRealtimeGateway();
      bootstrap = AppBootstrap(
        environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
        accountGateway: gateway,
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        notificationFacade: FakeNotificationFacade(),
        e2eeFacade: FakeE2eeFacade(),
        localePreferenceService: FakeLocalePreferenceService(),
        updateService: FakeUpdateService(),
        appSessionService: FakeAppSessionService(gateway),
        onboardingService: FakeOnboardingService(gateway),
        onboardingSupportService: FakeOnboardingSupportService(gateway),
        messagingService: FakeMessagingService(gateway),
        conversationService: FakeConversationService(gateway),
        groupApplicationService: FakeGroupApplicationService(gateway),
        profileApplicationService: FakeProfileApplicationService(gateway),
        relationshipApplicationService: FakeRelationshipApplicationService(
          gateway,
        ),
        realtimeApplicationService: FakeRealtimeApplicationService(
          gateway: gateway,
          realtimeGateway: realtimeGateway,
        ),
      );
    });

    testWidgets('uses English when system locale is English', (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('en'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pump();

      expect(find.text('Switch identity'), findsWidgets);
      expect(find.text('Log in or register'), findsWidgets);
    });

    testWidgets('falls back to Chinese for unsupported locales', (
      tester,
    ) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('fr'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pump();

      expect(find.text('切换身份'), findsWidgets);
      expect(find.text('登录或注册'), findsWidgets);
    });

    testWidgets('uses explicit locale override from settings provider', (
      tester,
    ) async {
      tester.binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('zh'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => AppLocaleMode.english),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Switch identity'), findsWidgets);
      expect(find.text('Log in or register'), findsWidgets);
    });

    testWidgets('tapping outside an input dismisses keyboard focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => AppLocaleMode.english),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Log in or register'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.pump();

      final focusNode = tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Log in or register'));
      await tester.pump();

      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets('tapping the focused input keeps keyboard focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            appLocaleModeProvider.overrideWith((ref) => AppLocaleMode.english),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Log in or register'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.pump();

      final focusNode = tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode;
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.byType(CupertinoTextField).first);
      await tester.pump();

      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets(
      'keyboard shortcuts adjust display scale while input is focused',
      (tester) async {
        await tester.pumpWidget(
          AwikiMeApp(
            bootstrap: bootstrap,
            providerOverrides: <Override>[
              appLocaleModeProvider.overrideWith(
                (ref) => AppLocaleMode.english,
              ),
            ],
          ),
        );
        await tester.pump();

        BuildContext appContext() => tester.element(find.byType(AppShell));
        expect(
          AwikiDisplayScaleScope.of(appContext()),
          AwikiDisplayScale.normal,
        );

        await tester.tap(find.byType(CupertinoTextField).first);
        await tester.pump();
        final focusNode = tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode;
        expect(focusNode.hasFocus, isTrue);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(AwikiDisplayScaleScope.of(appContext()), greaterThan(1));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(
          AwikiDisplayScaleScope.of(appContext()),
          AwikiDisplayScale.normal,
        );
      },
    );

    testWidgets('conversation service uses provider-scoped agent inventory', (
      tester,
    ) async {
      final gateway = FakeAwikiGateway();
      final realtimeGateway = FakeRealtimeGateway();
      final conversationService = ImCoreConversationService(
        conversations: _StaticConversationCore(<ConversationSummary>[
          ConversationSummary(
            threadId: 'dm:did:me:did:agent:daemon',
            displayName: '代理 1',
            lastMessagePreview: '',
            lastMessageAt: DateTime.utc(2026, 6, 3),
            unreadCount: 0,
            isGroup: false,
            targetDid: 'did:agent:daemon',
          ),
          ConversationSummary(
            threadId: 'dm:did:me:did:agent:runtime',
            displayName: 'Hermes',
            lastMessagePreview: 'Hermes 已准备好。',
            lastMessageAt: DateTime.utc(2026, 6, 3),
            unreadCount: 0,
            isGroup: false,
            targetDid: 'did:agent:runtime',
          ),
        ]),
        localStore: InMemoryAwikiProductLocalStore(),
      );
      final app = AwikiMeApp(
        bootstrap: AppBootstrap(
          environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          accountGateway: gateway,
          gateway: gateway,
          realtimeGateway: realtimeGateway,
          notificationFacade: FakeNotificationFacade(),
          e2eeFacade: FakeE2eeFacade(),
          localePreferenceService: FakeLocalePreferenceService(),
          updateService: FakeUpdateService(),
          appSessionService: FakeAppSessionService(gateway),
          onboardingService: FakeOnboardingService(gateway),
          onboardingSupportService: FakeOnboardingSupportService(gateway),
          messagingService: FakeMessagingService(gateway),
          conversationService: conversationService,
          agentInventoryPort: FakeAgentInventoryPort()
            ..agents = const <AgentSummary>[
              AgentSummary(
                agentDid: 'did:agent:daemon',
                kind: AgentKind.daemon,
                displayName: '代理 1',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
              AgentSummary(
                agentDid: 'did:agent:runtime',
                kind: AgentKind.runtime,
                daemonAgentDid: 'did:agent:daemon',
                runtime: 'hermes',
                displayName: 'Hermes',
                activeState: 'active',
                latest: AgentLatestStatus(status: 'ready'),
              ),
            ],
          agentControlService: FakeAgentControlService(),
          groupApplicationService: FakeGroupApplicationService(gateway),
          profileApplicationService: FakeProfileApplicationService(gateway),
          relationshipApplicationService: FakeRelationshipApplicationService(
            gateway,
          ),
          realtimeApplicationService: FakeRealtimeApplicationService(
            gateway: gateway,
            realtimeGateway: realtimeGateway,
          ),
          productLocalStore: InMemoryAwikiProductLocalStore(),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me',
              displayName: 'Me',
              jwtToken: 'jwt',
            ),
          );

      final conversations = await container
          .read(conversationServiceProvider)
          .listConversations(ownerDid: 'did:me');

      expect(conversations.map((item) => item.targetDid), [
        'did:agent:runtime',
      ]);
    });

    testWidgets('agent control commands use bootstrap-scoped environment', (
      tester,
    ) async {
      final gateway = FakeAwikiGateway();
      final realtimeGateway = FakeRealtimeGateway();
      final environment = AwikiEnvironmentConfig(
        baseUrl: 'https://awiki.ai',
        agentImEnabled: false,
      );
      final inventory = FakeAgentInventoryPort();
      final messaging = FakeMessagingService(gateway);
      final app = AwikiMeApp(
        bootstrap: AppBootstrap(
          environment: environment,
          accountGateway: gateway,
          gateway: gateway,
          realtimeGateway: realtimeGateway,
          notificationFacade: FakeNotificationFacade(),
          e2eeFacade: FakeE2eeFacade(),
          localePreferenceService: FakeLocalePreferenceService(),
          updateService: FakeUpdateService(),
          appSessionService: FakeAppSessionService(gateway),
          onboardingService: FakeOnboardingService(gateway),
          onboardingSupportService: FakeOnboardingSupportService(gateway),
          messagingService: messaging,
          agentInventoryPort: inventory,
          agentControlService: DefaultAgentControlService(
            inventory: inventory,
            messages: messaging,
            environment: environment,
          ),
          conversationService: FakeConversationService(gateway),
          groupApplicationService: FakeGroupApplicationService(gateway),
          profileApplicationService: FakeProfileApplicationService(gateway),
          relationshipApplicationService: FakeRelationshipApplicationService(
            gateway,
          ),
          realtimeApplicationService: FakeRealtimeApplicationService(
            gateway: gateway,
            realtimeGateway: realtimeGateway,
          ),
        ),
      );

      await tester.pumpWidget(app);
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final command = await container
          .read(agentControlServiceProvider)
          .createDaemonInstallCommand(
            controllerDid: 'did:human:me',
            controllerHandle: 'alice.awiki.ai',
            clientPlatform: 'linux',
          );

      expect(container.read(agentImEnabledProvider), isFalse);
      expect(
        command.command,
        "curl -fsSL 'https://awiki.ai/daemon/install.sh' | "
        "AWIKI_DAEMON_BASE_URL='https://awiki.ai' "
        "AWIKI_DAEMON_DOWNLOAD_BASE_URLS='https://awiki.ai/daemon' "
        "sh -s -- --token 'daemon-token'",
      );
      expect(
        command.fallbackCommand,
        'awiki-deamon install --token daemon-token --base-url https://awiki.ai',
      );
    });
  });
}

class _StaticConversationCore implements ConversationCorePort {
  const _StaticConversationCore(this.items);

  final List<ConversationSummary> items;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot() async {
    return const <ConversationSummary>[];
  }

  @override
  Future<void> clearConversationSnapshot() async {}

  @override
  Stream<CoreConversationPatch> watchConversationPatches() {
    return StreamController<CoreConversationPatch>().stream;
  }

  @override
  Future<CoreConversationPatch> repairConversationStore() async {
    return const CoreConversationPatch(
      kind: CoreConversationPatchKind.reset,
      ownerDid: 'did:me',
      version: 1,
      unreadTotal: 0,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return (await listConversationPage(
      limit: limit,
      unreadOnly: unreadOnly,
    )).items;
  }

  @override
  Future<CoreConversationPage> listConversationPage({
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return CoreConversationPage(
      items: items.take(limit).toList(),
      hasMore: false,
    );
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {}
}
