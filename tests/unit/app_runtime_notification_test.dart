import 'dart:async';

import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/desktop_shell_service.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/notification_target.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('Notification facade lifecycle', () {
    AppBootstrap buildBootstrap(
      FakeNotificationFacade notifications, {
      required bool disposeNotificationFacade,
    }) {
      final gateway = FakeAwikiGateway();
      return AppBootstrap(
        environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
        accountGateway: gateway,
        gateway: gateway,
        realtimeGateway: FakeRealtimeGateway(),
        notificationFacade: notifications,
        e2eeFacade: FakeE2eeFacade(),
        localePreferenceService: FakeLocalePreferenceService(),
        updateService: FakeUpdateService(),
        disposeNotificationFacade: disposeNotificationFacade,
      );
    }

    test('tenant bootstrap does not dispose an app-lifetime facade', () async {
      final notifications = FakeNotificationFacade();
      final bootstrap = buildBootstrap(
        notifications,
        disposeNotificationFacade: false,
      );

      await bootstrap.dispose();

      expect(notifications.disposed, isFalse);
    });

    test('standalone bootstrap still owns its notification facade', () async {
      final notifications = FakeNotificationFacade();
      final bootstrap = buildBootstrap(
        notifications,
        disposeNotificationFacade: true,
      );

      await bootstrap.dispose();

      expect(notifications.disposed, isTrue);
    });
  });

  group('AppRuntime notifications', () {
    late FakeAwikiGateway gateway;
    late FakeRealtimeGateway realtimeGateway;
    late FakeNotificationFacade notificationFacade;
    late FakeMessageSyncService messageSyncService;
    late _FakeDesktopShellService desktopShell;
    late ProviderContainer container;

    setUp(() {
      gateway = FakeAwikiGateway();
      realtimeGateway = FakeRealtimeGateway();
      notificationFacade = FakeNotificationFacade();
      messageSyncService = FakeMessageSyncService();
      desktopShell = _FakeDesktopShellService();
      gateway.myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
      gateway.conversations = const <ConversationSummary>[];
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          desktopShellServiceProvider.overrideWithValue(desktopShell),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> activate() async {
      await _activateRuntimeSession(
        container,
        const SessionIdentity(
          did: 'did:test:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
          jwtToken: 'token',
        ),
      );
    }

    RealtimeUpdate buildUpdate() {
      return RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'remote-1',
          remoteId: 'remote-1',
          threadId: 'dm:1',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          receiverDid: 'did:test:me',
          content: 'hello',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:1',
          conversationId: 'dm:1',
          displayName: 'Peer',
          lastMessagePreview: 'hello',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:test:peer',
        ),
      );
    }

    ConversationSummary staleSelectedConversation() {
      return ConversationSummary(
        threadId: 'group:old-group',
        conversationId: 'group:old-group',
        displayName: '旧身份群聊',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 4, 5, 12),
        unreadCount: 0,
        isGroup: true,
        groupId: 'old-group',
      );
    }

    test('激活身份时清理上一身份的选中会话', () async {
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());

      await activate();

      expect(container.read(selectedConversationProvider), isNull);
    });

    test(
      'committed activation replaces the old identity state after E2EE',
      () async {
        await _activateRuntimeSession(container, _epochSession('first'));
        container
            .read(groupProvider.notifier)
            .upsertGroup(
              const GroupSummary(
                conversationId: 'group:first',
                groupId: 'group-first',
                displayName: 'First owner group',
                description: '',
                memberCount: 1,
                lastMessageAt: null,
              ),
            );

        final activation = _activateRuntimeSession(
          container,
          _epochSession('second'),
        );
        await activation;

        expect(container.read(sessionProvider).session?.did, 'did:test:second');
        expect(container.read(groupProvider).groups, isEmpty);
      },
    );

    test(
      'committed activation uses the latest session snapshot for its lease',
      () async {
        final committed = await _commitRuntimeSession(
          container,
          _epochSession('first'),
        );

        await container
            .read(appRuntimeProvider.notifier)
            .activateCommittedSession(
              committed.copyWith(jwtToken: 'stale-token'),
            );

        expect(
          container.read(sessionProvider).session?.jwtToken,
          'token-first',
        );
      },
    );

    test(
      'aborting a committed session during E2EE clears Core lease and UI',
      () async {
        final sessions = FakeAppSessionService(gateway);
        final e2ee = _FirstBlockingE2eeFacade();
        addTearDown(e2ee.completeFirstIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            desktopShellServiceProvider.overrideWithValue(desktopShell),
            e2eeFacadeProvider.overrideWithValue(e2ee),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        final committed = await _commitRuntimeSession(
          container,
          _epochSession('first'),
        );
        final lease = (await sessions.currentSessionLease())!;

        final activation = runtime.activateCommittedSession(committed);
        await e2ee.firstStarted;
        expect(container.read(sessionProvider).session, isNull);

        expect(await sessions.abortSessionIfCurrent(lease), isTrue);
        e2ee.completeFirst();
        await activation;

        expect(await sessions.currentSession(), isNull);
        expect(await sessions.currentSessionLease(), isNull);
        expect(container.read(sessionProvider).session, isNull);
        expect(container.read(sessionProvider).activeEpoch, isNull);
      },
    );

    test('E2EE failure aborts the matching committed session', () async {
      final sessions = FakeAppSessionService(gateway);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
          ),
          appSessionServiceProvider.overrideWithValue(sessions),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          desktopShellServiceProvider.overrideWithValue(desktopShell),
          e2eeFacadeProvider.overrideWithValue(_FailingE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      final committed = await _commitRuntimeSession(
        container,
        _epochSession('first'),
      );

      await expectLater(
        container
            .read(appRuntimeProvider.notifier)
            .activateCommittedSession(committed),
        throwsStateError,
      );

      expect(await sessions.currentSession(), isNull);
      expect(await sessions.currentSessionLease(), isNull);
      expect(container.read(sessionProvider).session, isNull);
      expect(
        container.read(realtimeApplicationServiceProvider).isRunning,
        isFalse,
      );
    });

    test(
      'timed out E2EE cannot publish late and a replacement still activates',
      () async {
        final sessions = FakeAppSessionService(gateway);
        final e2ee = _FirstBlockingE2eeFacade();
        addTearDown(e2ee.completeFirstIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            desktopShellServiceProvider.overrideWithValue(desktopShell),
            e2eeFacadeProvider.overrideWithValue(e2ee),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
            appRuntimeProvider.overrideWith(
              (ref) => AppRuntimeController(
                ref,
                requestTimeout: const Duration(milliseconds: 20),
              ),
            ),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        final first = await _commitRuntimeSession(
          container,
          _epochSession('first'),
        );

        await expectLater(
          runtime.activateCommittedSession(first),
          throwsA(isA<TimeoutException>()),
        );
        expect(await sessions.currentSessionLease(), isNull);
        expect(container.read(sessionProvider).session, isNull);

        final second = await _commitRuntimeSession(
          container,
          _epochSession('second'),
        );
        final secondActivation = runtime.activateCommittedSession(second);
        e2ee.completeFirst();
        await secondActivation;

        expect(container.read(sessionProvider).session?.did, 'did:test:second');
        expect(e2ee.initializedDids, <String>[
          'did:test:first',
          'did:test:second',
        ]);
      },
    );

    test(
      'superseded E2EE completion cannot clear the replacement session',
      () async {
        final sessions = FakeAppSessionService(gateway);
        final e2ee = _FirstBlockingE2eeFacade();
        addTearDown(e2ee.completeFirstIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            desktopShellServiceProvider.overrideWithValue(desktopShell),
            e2eeFacadeProvider.overrideWithValue(e2ee),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        final first = await _commitRuntimeSession(
          container,
          _epochSession('first'),
        );

        final firstActivation = runtime.activateCommittedSession(first);
        await e2ee.firstStarted;
        final second = await _commitRuntimeSession(
          container,
          _epochSession('second'),
        );
        final secondActivation = runtime.activateCommittedSession(second);

        e2ee.completeFirst();
        await Future.wait<void>(<Future<void>>[
          firstActivation,
          secondActivation,
        ]);

        expect(container.read(sessionProvider).session?.did, 'did:test:second');
        expect(
          container.read(sessionProvider).session?.credentialName,
          'second',
        );
        expect(e2ee.initializedDids, <String>[
          'did:test:first',
          'did:test:second',
        ]);
      },
    );

    test(
      'same-identity reactivation supersedes a blocked old E2EE epoch',
      () async {
        final sessions = FakeAppSessionService(gateway);
        final e2ee = _FirstBlockingE2eeFacade();
        addTearDown(e2ee.completeFirstIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            desktopShellServiceProvider.overrideWithValue(desktopShell),
            e2eeFacadeProvider.overrideWithValue(e2ee),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        const session = SessionIdentity(
          did: 'did:test:same',
          credentialName: 'same',
          displayName: 'Same identity',
          jwtToken: 'first-token',
        );
        final first = await _commitRuntimeSession(container, session);

        final firstActivation = runtime.activateCommittedSession(first);
        await e2ee.firstStarted;
        final second = await _commitRuntimeSession(
          container,
          const SessionIdentity(
            did: 'did:test:same',
            credentialName: 'same',
            displayName: 'Same identity',
            jwtToken: 'replacement-token',
          ),
        );
        final secondActivation = runtime.activateCommittedSession(second);

        e2ee.completeFirst();
        await Future.wait<void>(<Future<void>>[
          firstActivation,
          secondActivation,
        ]);

        expect(container.read(sessionProvider).activeEpoch, isNotNull);
        expect(
          container.read(sessionProvider).session?.jwtToken,
          'replacement-token',
        );
        expect(e2ee.initializedDids, <String>[
          'did:test:same',
          'did:test:same',
        ]);
      },
    );

    test('退出登录时清理当前选中会话', () async {
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              handle: 'me',
              jwtToken: 'token',
            ),
          );
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());

      await container.read(appRuntimeProvider.notifier).logout();

      expect(container.read(selectedConversationProvider), isNull);
    });

    test('非法通知 payload 只打开消息列表并清理旧选择', () async {
      await activate();
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());
      container.read(shellTabProvider.notifier).setTab(3);

      notificationFacade.emitActivation(const NotificationActivation.invalid());
      await pumpEventQueue();

      expect(container.read(shellTabProvider), 0);
      expect(container.read(selectedConversationProvider), isNull);
      expect(desktopShell.showWindowCalls, 1);
    });

    test('跨 scope 通知不切换身份或会话', () async {
      await activate();
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());

      notificationFacade.emitActivation(
        NotificationActivation.valid(
          NotificationTarget(
            storageScopeId: StorageScopeId.generate(),
            ownerDid: 'did:test:me',
            conversationId: 'dm:foreign',
          ),
        ),
      );
      await pumpEventQueue();

      expect(container.read(shellTabProvider), 0);
      expect(container.read(selectedConversationProvider), isNull);
      expect(desktopShell.showWindowCalls, 1);
    });

    test('同 scope 但 owner 不匹配的通知只打开消息列表', () async {
      await activate();
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());
      container.read(shellTabProvider.notifier).setTab(3);

      notificationFacade.emitActivation(
        NotificationActivation.valid(
          NotificationTarget(
            storageScopeId: container
                .read(activeAppTenantProvider)
                .storageScopeId,
            ownerDid: 'did:test:other-local-identity',
            conversationId: 'dm:foreign-owner',
          ),
        ),
      );
      await pumpEventQueue();

      expect(container.read(shellTabProvider), 0);
      expect(container.read(selectedConversationProvider), isNull);
      expect(desktopShell.showWindowCalls, 1);
      expect(gateway.fetchLocalDmHistoryCalls, 0);
    });

    test('同 scope 通知打开 canonical conversation', () async {
      final conversation = ConversationSummary(
        threadId: 'dm:did:test:notification-peer',
        conversationId: 'dm:did:test:notification-peer',
        displayName: 'Notification peer',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 7, 21),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:notification-peer',
      );
      gateway.conversations = <ConversationSummary>[conversation];
      await activate();

      notificationFacade.emitActivation(
        NotificationActivation.valid(
          NotificationTarget(
            storageScopeId: container
                .read(activeAppTenantProvider)
                .storageScopeId,
            ownerDid: 'did:test:me',
            conversationId: conversation.conversationId,
          ),
        ),
      );
      await pumpEventQueue();

      expect(container.read(shellTabProvider), 0);
      expect(
        container.read(selectedConversationProvider),
        conversation.conversationId,
      );
      expect(desktopShell.showWindowCalls, 1);
      expect(gateway.fetchLocalDmHistoryCalls, greaterThan(0));
      expect(gateway.lastFetchedLocalDmPeerDid, conversation.targetDid);
    });

    test('旧 epoch 的通知路由完成后不会覆盖新身份选择', () async {
      final oldConversation = ConversationSummary(
        threadId: 'dm:old-notification',
        conversationId: 'dm:old-notification',
        displayName: 'Old notification',
        lastMessagePreview: 'old',
        lastMessageAt: DateTime(2026, 7, 21),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:old-peer',
      );
      final newConversation = ConversationSummary(
        threadId: 'dm:new-selection',
        conversationId: 'dm:new-selection',
        displayName: 'New selection',
        lastMessagePreview: 'new',
        lastMessageAt: DateTime(2026, 7, 22),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:new-peer',
      );
      gateway.conversations = <ConversationSummary>[oldConversation];
      await _activateRuntimeSession(container, _epochSession('first'));
      desktopShell.showWindowCompleter = Completer<void>();

      notificationFacade.emitActivation(
        NotificationActivation.valid(
          NotificationTarget(
            storageScopeId: container
                .read(activeAppTenantProvider)
                .storageScopeId,
            ownerDid: 'did:test:first',
            conversationId: oldConversation.conversationId,
          ),
        ),
      );
      await _pumpUntil(() => desktopShell.showWindowCalls == 1);

      await _activateRuntimeSession(container, _epochSession('second'));
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(newConversation);
      desktopShell.showWindowCompleter!.complete();
      await pumpEventQueue();

      expect(
        container.read(selectedConversationProvider),
        newConversation.conversationId,
      );
    });

    test('冷启动 initial activation 聚焦并恢复 canonical conversation', () async {
      final conversation = ConversationSummary(
        threadId: 'dm:did:test:cold-start-peer',
        conversationId: 'dm:did:test:cold-start-peer',
        displayName: 'Cold start peer',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 7, 21),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:cold-start-peer',
      );
      gateway.conversations = <ConversationSummary>[conversation];
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              handle: 'me',
              jwtToken: 'token',
            ),
          );
      notificationFacade.initialNotificationActivation =
          NotificationActivation.valid(
            NotificationTarget(
              storageScopeId: container
                  .read(activeAppTenantProvider)
                  .storageScopeId,
              ownerDid: 'did:test:me',
              conversationId: conversation.conversationId,
            ),
          );

      await container.read(appRuntimeProvider.notifier).initialize();
      await pumpEventQueue();

      expect(desktopShell.showWindowCalls, 1);
      expect(container.read(shellTabProvider), 0);
      expect(
        container.read(selectedConversationProvider),
        conversation.conversationId,
      );
      expect(gateway.fetchLocalDmHistoryCalls, greaterThan(0));
      expect(gateway.lastFetchedLocalDmPeerDid, conversation.targetDid);
    });

    test('前台收到消息时显示应用内提示', () async {
      gateway.nextRealtimeUpdate = buildUpdate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastInAppTitle, 'Peer');
      expect(notificationFacade.lastInAppBody, 'hello');
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('激活身份后后台调度 startup 可靠同步', () async {
      await activate();
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('startup'));
      expect(container.read(appRuntimeProvider).isBusy, isFalse);
    });

    test('恢复前台时调度 app_resumed 可靠同步', () async {
      await activate();
      messageSyncService.syncReasons.clear();

      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('app_resumed'));
    });

    test('恢复前台时不强制刷新已加载的智能体列表', () async {
      final agentControl = _CountingAgentControlService();
      final lifecycleContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          agentControlServiceProvider.overrideWithValue(agentControl),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(lifecycleContainer.dispose);

      await _activateRuntimeSession(
        lifecycleContainer,
        const SessionIdentity(
          did: 'did:test:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
          jwtToken: 'token',
        ),
      );
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final callsAfterStartup = agentControl.listAgentsCalls;

      lifecycleContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      lifecycleContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(messageSyncService.syncReasons, contains('app_resumed'));
      expect(agentControl.listAgentsCalls, callsAfterStartup);
    });

    test('进入后台时裁剪隐藏会话缓存但保留可见会话', () async {
      final visibleConversation = ConversationSummary(
        threadId: 'dm:visible',
        conversationId: 'dm:visible',
        displayName: 'Visible',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:visible',
      );
      final hiddenConversation = ConversationSummary(
        threadId: 'dm:hidden',
        conversationId: 'dm:hidden',
        displayName: 'Hidden',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:hidden',
      );
      final cacheContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          chatThreadsProvider.overrideWith(
            (ref) => ChatThreadsController(
              ref,
              cachePolicy: const ThreadMemoryCachePolicy(
                hotThreadMessageLimit: 10,
                warmThreadMessageLimit: 4,
                coldThreadMessageLimit: 1,
                maxTotalCachedMessages: 20,
                maxCachedCanonicalThreads: 20,
              ),
            ),
          ),
        ],
      );
      addTearDown(cacheContainer.dispose);
      final controller = cacheContainer.read(chatThreadsProvider.notifier);
      controller.markConversationVisible(visibleConversation);
      for (var i = 0; i < 4; i += 1) {
        controller.debugSeedMessageForTesting(
          _runtimeTestMessage(visibleConversation, i),
        );
        controller.debugSeedMessageForTesting(
          _runtimeTestMessage(hiddenConversation, i),
        );
      }

      cacheContainer.read(appRuntimeProvider);
      cacheContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      expect(
        cacheContainer
            .read(chatThreadProvider(visibleConversation.threadId))
            .messages,
        hasLength(4),
      );
      expect(
        cacheContainer
            .read(chatThreadProvider(hiddenConversation.threadId))
            .messages,
        hasLength(1),
      );
    });

    test('内存压力会回收隐藏会话缓存但保留可见会话', () {
      final visibleConversation = ConversationSummary(
        threadId: 'dm:memory-visible',
        conversationId: 'dm:memory-visible',
        displayName: 'Visible',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:memory-visible',
      );
      final hiddenConversation = ConversationSummary(
        threadId: 'dm:memory-hidden',
        conversationId: 'dm:memory-hidden',
        displayName: 'Hidden',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 29, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:memory-hidden',
      );
      final cacheContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          chatThreadsProvider.overrideWith(
            (ref) => ChatThreadsController(
              ref,
              cachePolicy: const ThreadMemoryCachePolicy(
                hotThreadMessageLimit: 10,
                warmThreadMessageLimit: 4,
                coldThreadMessageLimit: 1,
                maxTotalCachedMessages: 20,
                maxCachedCanonicalThreads: 20,
              ),
            ),
          ),
        ],
      );
      addTearDown(cacheContainer.dispose);
      final controller = cacheContainer.read(chatThreadsProvider.notifier);
      controller.markConversationVisible(visibleConversation);
      for (var i = 0; i < 4; i += 1) {
        controller.debugSeedMessageForTesting(
          _runtimeTestMessage(visibleConversation, i),
        );
        controller.debugSeedMessageForTesting(
          _runtimeTestMessage(hiddenConversation, i),
        );
      }

      controller.trimForMemoryPressure();

      expect(
        cacheContainer
            .read(chatThreadProvider(visibleConversation.threadId))
            .messages,
        hasLength(4),
      );
      expect(
        cacheContainer
            .read(chatThreadProvider(hiddenConversation.threadId))
            .messages,
        isEmpty,
      );
      expect(controller.debugCacheStats().evictedThreadCount, 1);
    });

    test('realtime gap hint 只调度 delta，不直接改消息投影', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: buildUpdate().message,
        conversationHint: buildUpdate().conversationHint,
        syncDirty: true,
        gapDetected: true,
        syncEventSeq: '42',
        syncEventType: 'message.created',
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_gap'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
    });

    test('后台收到消息时触发系统通知', () async {
      gateway.nextRealtimeUpdate = buildUpdate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastSystemTitle, 'Peer');
      expect(notificationFacade.lastSystemBody, 'hello');
      expect(notificationFacade.lastInAppTitle, isNull);
    });

    test('后台系统通知标题使用发信人短昵称', () async {
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'remote-2',
          remoteId: 'remote-2',
          threadId: 'dm:2',
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          senderName: 'did:wba:awiki.ai:user:alice:e1_key',
          receiverDid: 'did:test:me',
          content: 'hello',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:2',
          conversationId: 'dm:2',
          displayName: 'did:wba:awiki.ai:user:alice:e1_key',
          lastMessagePreview: 'hello',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:wba:awiki.ai:user:alice:e1_key',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastSystemTitle, 'alice');
      expect(notificationFacade.lastSystemBody, 'hello');
    });

    test('激活身份先刷新本地会话列表，不等待 profile/agents/friends/groups', () async {
      final slowProfile = Completer<void>();
      gateway.myProfile = null;
      final conversations = _RecordingConversationService(<ConversationSummary>[
        buildUpdate().conversationHint!,
      ]);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
          ),
          conversationServiceProvider.overrideWithValue(conversations),
          profileApplicationServiceProvider.overrideWithValue(
            _BlockingProfileService(slowProfile),
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );

      await activate();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(conversations.fastCalls, 1);
      expect(conversations.enrichCalls, 1);
      expect(
        container.read(conversationListProvider).conversations.single.threadId,
        'dm:1',
      );
      slowProfile.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('恢复和重连短时间重复触发时复用同一次后台刷新', () async {
      final slowProfile = Completer<void>();
      final sync = FakeMessageSyncService();
      gateway.myProfile = null;
      final conversations = _RecordingConversationService(<ConversationSummary>[
        buildUpdate().conversationHint!,
      ]);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: sync,
          ),
          conversationServiceProvider.overrideWithValue(conversations),
          profileApplicationServiceProvider.overrideWithValue(
            _BlockingProfileService(slowProfile),
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );

      await activate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sync.syncReasons, contains('startup'));
      expect(sync.syncReasons, contains('app_resumed'));
      expect(conversations.fastCalls, 2);
      expect(conversations.enrichCalls, 2);
      slowProfile.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('身份切换启动独立后台刷新且旧身份迟到结果不会覆盖新身份', () async {
      final profiles = _EpochProfileService();
      final groups = _EpochGroupService();
      addTearDown(profiles.completeFirstIfPending);
      addTearDown(groups.completeFirstIfPending);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
          ),
          profileApplicationServiceProvider.overrideWithValue(profiles),
          groupApplicationServiceProvider.overrideWithValue(groups),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      final runtime = container.read(appRuntimeProvider.notifier);
      await _activateRuntimeSession(container, _epochSession('first'));
      await _pumpUntil(() => profiles.loadCalls == 1 && groups.loadCalls == 1);

      await runtime.logout();
      await _activateRuntimeSession(container, _epochSession('second'));
      await _pumpUntil(() => profiles.loadCalls == 2 && groups.loadCalls == 2);

      expect(container.read(profileProvider).profile?.did, 'did:test:second');
      expect(
        container.read(groupProvider).groups.single.groupId,
        'group-second',
      );

      profiles.completeFirst();
      groups.completeFirst();
      await pumpEventQueue();

      expect(container.read(sessionProvider).session?.did, 'did:test:second');
      expect(container.read(profileProvider).profile?.did, 'did:test:second');
      expect(
        container.read(groupProvider).groups.single.groupId,
        'group-second',
      );
    });

    test('realtime recovery is isolated by session epoch', () async {
      final sessions = _EpochAppSessionService(gateway);
      addTearDown(sessions.completeFirstRefreshIfPending);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
          ),
          appSessionServiceProvider.overrideWithValue(sessions),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      await _activateRuntimeSession(container, _epochSession('first'));
      await _pumpUntil(
        () => container.read(realtimeConnectionStatusProvider).hasValue,
        reason: 'realtime status subscription did not start',
      );
      realtimeGateway.setStatus(RealtimeConnectionStatus.failed);
      await _pumpUntil(
        () => sessions.refreshCalls == 1,
        reason: 'first recovery did not start',
      );

      await _activateRuntimeSession(container, _epochSession('second'));
      await pumpEventQueue();
      realtimeGateway.setStatus(RealtimeConnectionStatus.failed);
      await _pumpUntil(
        () => sessions.refreshCalls == 2,
        reason: 'second recovery did not start',
      );

      sessions.completeFirstRefresh();
      await pumpEventQueue();

      expect(sessions.refreshCalls, 2);
      expect(container.read(sessionProvider).session?.did, 'did:test:second');
      expect(container.read(sessionProvider).session?.credentialName, 'second');
    });

    test(
      'direct identity login invalidates the old epoch before Core switch',
      () async {
        final sessions = _EpochAppSessionService(gateway)..blockNextLogin();
        addTearDown(sessions.completeLoginIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        await _activateRuntimeSession(container, _epochSession('first'));

        final login = runtime.loginWithLocalCredential('second');
        await _pumpUntil(() => sessions.loginCalls == 1);

        expect(container.read(sessionProvider).session, isNull);
        expect(container.read(sessionProvider).activeEpoch, isNull);

        gateway.nextRealtimeUpdate = const RealtimeUpdate(
          ownerDid: 'did:test:first',
          group: GroupSummary(
            conversationId: 'group:stale',
            groupId: 'group-stale',
            displayName: 'stale',
            description: '',
            memberCount: 1,
            lastMessageAt: null,
          ),
          syncDirty: true,
        );
        await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
        expect(container.read(groupProvider).groups, isEmpty);

        sessions.completeLogin();
        await login;

        expect(container.read(sessionProvider).session?.did, 'did:test:second');
        expect(
          container.read(sessionProvider).session?.credentialName,
          'second',
        );

        await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
        expect(container.read(groupProvider).groups, isEmpty);
      },
    );

    test(
      'failed identity login restores the predecessor lease with a new epoch',
      () async {
        final sessions = _FailingIdentityLoginAppSessionService(gateway);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        await _activateRuntimeSession(container, _epochSession('first'));
        final originalEpoch = container.read(sessionProvider).activeEpoch!;
        final originalLease = (await sessions.currentSessionLease())!;

        await runtime.loginWithLocalCredential('second');

        final restoredLease = (await sessions.currentSessionLease())!;
        expect(restoredLease.transition, same(originalLease.transition));
        expect(restoredLease.session.identityId, 'first');
        expect(container.read(sessionProvider).session?.did, 'did:test:first');
        expect(
          container.read(sessionProvider).activeEpoch,
          isNot(equals(originalEpoch)),
        );
      },
    );

    test(
      'rapid identity login intents only activate the latest intent',
      () async {
        final sessions = _EpochAppSessionService(gateway)..blockNextLogin();
        addTearDown(sessions.completeLoginIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        await _activateRuntimeSession(container, _epochSession('first'));

        final firstLogin = runtime.loginWithLocalCredential('second');
        await _pumpUntil(() => sessions.loginCalls == 1);
        final latestLogin = runtime.loginWithLocalCredential('second');
        await _pumpUntil(() => sessions.loginCalls == 2);
        sessions.completeLogin();
        await Future.wait<void>(<Future<void>>[firstLogin, latestLogin]);

        expect(container.read(sessionProvider).session?.did, 'did:test:second');
        expect(container.read(uiFeedbackProvider), isNull);
      },
    );

    test(
      'a stale login auth failure cannot report or logout the latest identity',
      () async {
        final sessions = _DelayedStaleAuthFailureSessionService(gateway);
        addTearDown(sessions.releaseFirstIfPending);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            appSessionServiceProvider.overrideWithValue(sessions),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        final runtime = container.read(appRuntimeProvider.notifier);
        await _activateRuntimeSession(container, _epochSession('first'));

        final staleLogin = runtime.loginWithLocalCredential('stale');
        await sessions.firstStarted.future;
        final latestLogin = runtime.loginWithLocalCredential('second');
        await latestLogin;
        sessions.releaseFirst();
        await staleLogin;

        expect(container.read(sessionProvider).session?.did, 'did:test:second');
        expect(container.read(uiFeedbackProvider), isNull);
        expect(gateway.logoutCalls, 0);
      },
    );

    test('timed out local login cannot commit or activate late', () async {
      final sessions = _EpochAppSessionService(gateway)..blockNextLogin();
      addTearDown(sessions.completeLoginIfPending);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
          ),
          appSessionServiceProvider.overrideWithValue(sessions),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          appRuntimeProvider.overrideWith(
            (ref) => AppRuntimeController(
              ref,
              requestTimeout: const Duration(milliseconds: 20),
            ),
          ),
        ],
      );
      final runtime = container.read(appRuntimeProvider.notifier);

      final login = runtime.loginWithLocalCredential('second');
      await _pumpUntil(() => sessions.loginCalls == 1);
      await login;

      expect(container.read(sessionProvider).session, isNull);
      expect(await sessions.currentSessionLease(), isNull);

      sessions.completeLogin();
      await pumpEventQueue();

      expect(await sessions.currentSession(), isNull);
      expect(await sessions.currentSessionLease(), isNull);
      expect(container.read(sessionProvider).session, isNull);
    });

    test(
      'same-owner relogin drops an update queued for the old epoch',
      () async {
        final queuedRealtime = _QueuedRealtimeApplicationService();
        addTearDown(queuedRealtime.dispose);
        container.dispose();
        container = ProviderContainer(
          overrides: <Override>[
            awikiGatewayProvider.overrideWithValue(gateway),
            awikiAccountGatewayProvider.overrideWithValue(gateway),
            ...fakeApplicationServiceOverrides(
              gateway,
              realtimeGateway: realtimeGateway,
            ),
            realtimeApplicationServiceProvider.overrideWithValue(
              queuedRealtime,
            ),
            realtimeGatewayProvider.overrideWithValue(realtimeGateway),
            notificationFacadeProvider.overrideWithValue(notificationFacade),
            desktopShellServiceProvider.overrideWithValue(desktopShell),
            e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
            updateServiceProvider.overrideWithValue(FakeUpdateService()),
          ],
        );
        const session = SessionIdentity(
          did: 'did:test:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
          jwtToken: 'token',
        );
        await _activateRuntimeSession(container, session);

        queuedRealtime.emit(buildUpdate());
        container.read(sessionProvider.notifier).clear();
        await _activateRuntimeSession(container, session);
        await pumpEventQueue();

        expect(notificationFacade.lastSystemTitle, isNull);
        expect(notificationFacade.lastSystemBody, isNull);
      },
    );

    test('实时附件消息通知使用附件预览', () async {
      container.read(appLocaleModeProvider.notifier).state =
          AppLocaleMode.zhHans;
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'remote-attachment',
          remoteId: 'remote-attachment',
          threadId: 'dm:attachment',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          receiverDid: 'did:test:me',
          content: '',
          originalType: 'application/anp-attachment-manifest+json',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
          attachment: const ChatAttachment(
            attachmentId: 'att-1',
            filename: 'report.pdf',
            mimeType: 'application/pdf',
          ),
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:attachment',
          conversationId: 'dm:attachment',
          displayName: 'Peer',
          lastMessagePreview: '[附件] report.pdf',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:test:peer',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(notificationFacade.lastSystemTitle, 'Peer');
      expect(notificationFacade.lastSystemBody, '附件：report.pdf');
    });

    test('实时 direct 与 group 消息只调度 core sync，不直接写 list/timeline', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);
      messageSyncService.syncReasons.clear();

      gateway.nextRealtimeUpdate = buildUpdate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(notificationFacade.lastInAppTitle, 'Peer');
      expect(notificationFacade.lastInAppBody, 'hello');

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'group-remote-1',
          remoteId: 'group-remote-1',
          threadId: 'group:group-1',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          groupId: 'group-1',
          content: 'hello group',
          createdAt: DateTime(2026, 4, 5, 12, 5),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'group:group-1',
          conversationId: 'group:group-1',
          displayName: '融资协作群',
          lastMessagePreview: 'hello group',
          lastMessageAt: DateTime(2026, 4, 5, 12, 5),
          unreadCount: 1,
          isGroup: true,
          groupId: 'group-1',
        ),
        group: GroupSummary(
          groupId: 'group-1',
          conversationId: 'group:group-1',
          name: '融资协作群',
          description: '',
          memberCount: 2,
          lastMessageAt: DateTime(2026, 4, 5, 12, 5),
          myRole: 'member',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(
        container.read(chatThreadProvider('group:group-1')).messages,
        isEmpty,
      );
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(groupProvider).groups.single.groupId, 'group-1');
      expect(notificationFacade.lastInAppTitle, 'Peer');
      expect(notificationFacade.lastInAppBody, 'hello group');
    });

    test('实时消息更新最近会话但不会覆盖未读 @ 我状态', () async {
      final conversationService = _RecordingConversationService(
        const <ConversationSummary>[],
      );
      addTearDown(conversationService.dispose);
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          conversationServiceProvider.overrideWithValue(conversationService),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
      await activate();
      await pumpEventQueue();

      final mentionedConversation = ConversationSummary(
        threadId: 'group:group-mention',
        conversationId: 'group:group-mention',
        displayName: '群聊',
        lastMessagePreview: '@me 请看',
        lastMessageAt: DateTime(2026, 4, 5, 12),
        unreadCount: 1,
        unreadMentionCount: 1,
        firstUnreadMentionMessageId: 'msg-mention-1',
        isGroup: true,
        groupId: 'group-mention',
      );
      conversationService.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:test:me',
          version: 1,
          unreadTotal: 1,
          item: mentionedConversation,
        ),
      );
      await pumpEventQueue();

      final afterMentionPatch = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(afterMentionPatch.unreadCount, 1);
      expect(afterMentionPatch.unreadMentionCount, 1);
      expect(afterMentionPatch.firstUnreadMentionMessageId, 'msg-mention-1');

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'msg-normal-2',
          remoteId: 'msg-normal-2',
          threadId: 'group:group-mention',
          senderDid: 'did:test:peer',
          senderName: 'Peer',
          groupId: 'group-mention',
          content: '普通消息',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'group:group-mention',
          conversationId: 'group:group-mention',
          displayName: '群聊',
          lastMessagePreview: '普通消息',
          lastMessageAt: DateTime(2026, 4, 5, 12, 1),
          unreadCount: 1,
          unreadMentionCount: 0,
          isGroup: true,
          groupId: 'group-mention',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      final afterRealtime = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(afterRealtime.lastMessagePreview, '@me 请看');
      expect(afterRealtime.unreadCount, 1);
      expect(afterRealtime.unreadMentionCount, 1);
      expect(afterRealtime.firstUnreadMentionMessageId, 'msg-mention-1');
      expect(
        container.read(chatThreadProvider('group:group-mention')).messages,
        isEmpty,
      );

      conversationService.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:test:me',
          version: 2,
          unreadTotal: 2,
          item: mentionedConversation.copyWith(
            lastMessagePreview: '普通消息',
            lastMessageAt: DateTime(2026, 4, 5, 12, 1),
            unreadCount: 2,
            unreadMentionCount: 1,
            firstUnreadMentionMessageId: 'msg-mention-1',
          ),
        ),
      );
      await pumpEventQueue();

      final afterPatch = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(afterPatch.lastMessagePreview, '普通消息');
      expect(afterPatch.unreadCount, 2);
      expect(afterPatch.unreadMentionCount, 1);
      expect(afterPatch.firstUnreadMentionMessageId, 'msg-mention-1');
    });

    test('实时 direct peer-scoped 消息只调度 core sync，不预热 alias', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      final conversation = ConversationSummary(
        threadId: 'direct-handle:alice.awiki.info',
        conversationId: 'direct-handle:alice.awiki.info',
        displayName: 'Alice',
        lastMessagePreview: 'hello alias',
        lastMessageAt: DateTime(2026, 4, 5, 12, 10),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:alice',
        targetPeer: 'alice.awiki.info',
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'alias-direct-1',
          remoteId: 'alias-direct-1',
          threadId: 'dm:peer-scope:v1:alice',
          senderDid: 'did:test:alice',
          senderName: 'Alice',
          receiverDid: 'did:test:me',
          content: 'hello alias',
          createdAt: DateTime(2026, 4, 5, 12, 10),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: conversation,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      for (final key in <String>[
        'dm:peer-scope:v1:alice',
        'direct-handle:alice.awiki.info',
        'did:test:alice',
        'direct:did:test:alice',
        'direct-did:did:test:alice',
        'direct:alice.awiki.info',
        'direct-handle:alice',
        'dm:pending:alice.awiki.info',
        'dm:did:test:alice:did:test:me',
      ]) {
        expect(
          container.read(chatThreadProvider(key)).messages,
          isEmpty,
          reason: 'realtime payload must not prewarm $key directly',
        );
      }

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'alias-direct-1',
          remoteId: 'alias-direct-1',
          threadId: 'dm:peer-scope:v1:alice',
          senderDid: 'did:test:alice',
          senderName: 'Alice',
          receiverDid: 'did:test:me',
          content: 'hello alias',
          createdAt: DateTime(2026, 4, 5, 12, 10),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: conversation,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'direct'});
      await pumpEventQueue();

      expect(
        container.read(chatThreadProvider('dm:peer-scope:v1:alice')).messages,
        isEmpty,
      );
      expect(
        container
            .read(chatThreadProvider('direct-handle:alice.awiki.info'))
            .messages,
        isEmpty,
      );
    });

    test('实时 group 消息只调度 core sync，不预热 canonical 或 alias thread', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'alias-group-1',
          remoteId: 'alias-group-1',
          threadId: 'sdk-group-thread-alpha',
          senderDid: 'did:test:alice',
          senderName: 'Alice',
          groupId: 'did:test:group:alpha',
          content: 'hello group alias',
          createdAt: DateTime(2026, 4, 5, 12, 15),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'group:did:test:group:alpha',
          conversationId: 'group:did:test:group:alpha',
          displayName: 'Alpha',
          lastMessagePreview: 'hello group alias',
          lastMessageAt: DateTime(2026, 4, 5, 12, 15),
          unreadCount: 1,
          isGroup: true,
          groupId: 'did:test:group:alpha',
        ),
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
      await pumpEventQueue();

      for (final key in <String>[
        'group:did:test:group:alpha',
        'sdk-group-thread-alpha',
      ]) {
        expect(
          container.read(chatThreadProvider(key)).messages,
          isEmpty,
          reason: 'realtime payload must not prewarm $key directly',
        );
      }
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(
        container.read(chatThreadProvider('did:test:group:alpha')).messages,
        isEmpty,
      );
    });

    test('Daemon Agent 普通实时消息不进入聊天、未读或通知', () async {
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
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
              'status': 'ready',
            },
          ],
        },
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'daemon-normal',
          remoteId: 'daemon-normal',
          threadId: 'dm:daemon',
          senderDid: 'did:agent:daemon',
          senderName: '代理 1',
          receiverDid: 'did:test:me',
          content: 'control-plane text should be hidden',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:daemon',
          conversationId: 'dm:daemon',
          displayName: '代理 1',
          lastMessagePreview: 'control-plane text should be hidden',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:daemon',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(container.read(chatThreadProvider('dm:daemon')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(conversationListProvider).unreadCount, 0);
      expect(notificationFacade.lastBadgeCount, 0);
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('Runtime Agent 普通实时消息只触发通知和 core sync', () async {
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
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
              'status': 'ready',
            },
          ],
        },
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'runtime-normal',
          remoteId: 'runtime-normal',
          threadId: 'dm:runtime',
          senderDid: 'did:agent:runtime',
          senderName: 'Hermes',
          receiverDid: 'did:test:me',
          content: 'Hermes reply',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:runtime',
          conversationId: 'dm:runtime',
          displayName: 'Hermes',
          lastMessagePreview: 'Hermes reply',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:runtime',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      messageSyncService.syncReasons.clear();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(
        container.read(chatThreadProvider('dm:runtime')).messages,
        isEmpty,
      );
      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, isEmpty);
      expect(container.read(conversationListProvider).unreadCount, 0);
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(notificationFacade.lastInAppTitle, 'Hermes');
      expect(notificationFacade.lastInAppBody, 'Hermes reply');
    });

    test('实时 Agent hint 不覆盖现有会话，只调度 core sync', () async {
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime:hermes',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'handle': 'hermes',
              'display_name': 'Hermes',
              'status': 'ready',
            },
          ],
        },
      );
      final pendingAlias = ConversationSummary(
        threadId: 'dm:pending:hermes.awiki.info',
        conversationId: 'dm:pending:hermes.awiki.info',
        displayName: 'Hermes',
        lastMessagePreview: '在吗？',
        lastMessageAt: DateTime(2026, 7, 3, 12, 0),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:agent:runtime:hermes',
        targetPeer: 'hermes.awiki.info',
      );
      container
          .read(conversationListProvider.notifier)
          .upsertConversation(pendingAlias);
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'runtime-normalized',
          remoteId: 'runtime-normalized',
          threadId: 'dm:peer-scope:v1:hermes-runtime',
          senderDid: 'did:agent:runtime:hermes',
          senderName: 'Hermes',
          receiverDid: 'did:test:me',
          content: '在的',
          createdAt: DateTime(2026, 7, 3, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:peer-scope:v1:hermes-runtime',
          conversationId: 'dm:peer-scope:v1:hermes-runtime',
          displayName: 'hermes',
          lastMessagePreview: '在的',
          lastMessageAt: DateTime(2026, 7, 3, 12, 1),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'hermes',
          targetPeer: 'hermes',
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      messageSyncService.syncReasons.clear();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, pendingAlias.threadId);
      expect(conversations.single.targetDid, 'did:agent:runtime:hermes');
      expect(conversations.single.targetPeer, 'hermes.awiki.info');
      expect(conversations.single.lastMessagePreview, '在吗？');
      expect(
        container
            .read(chatThreadProvider('dm:peer-scope:v1:hermes-runtime'))
            .messages,
        isEmpty,
      );
      expect(
        container.read(chatThreadProvider(pendingAlias.threadId)).messages,
        isEmpty,
      );
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(notificationFacade.lastInAppTitle, 'Hermes');
    });

    test('实时消息的过期 conversation hint 不会污染最近会话', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'runtime-stale-hint',
          remoteId: 'runtime-stale-hint',
          threadId: 'dm:peer-scope:v1:runtime',
          senderDid: 'did:agent:runtime',
          senderName: 'Hermes',
          receiverDid: 'did:test:me',
          content: 'runtime reply',
          createdAt: DateTime(2026, 4, 5, 12, 2),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:human',
          conversationId: 'dm:human',
          displayName: 'zhuocheng',
          lastMessagePreview: 'runtime reply',
          lastMessageAt: DateTime(2026, 4, 5, 12, 2),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:human:zhuocheng',
        ),
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(
        container.read(chatThreadProvider('dm:peer-scope:v1:runtime')).messages,
        isEmpty,
      );
      expect(container.read(chatThreadProvider('dm:human')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(conversationListProvider).unreadCount, 0);
      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(notificationFacade.lastInAppTitle, 'Hermes');
    });

    test('实时控制状态只更新智能体状态', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        agentControlPayload: <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'daemon',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
            'version': '0.2.0',
            'platform': 'darwin-arm64',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'needs_config',
            },
          ],
        },
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'status'});

      final agents = container.read(agentsProvider).agents;
      final daemon = agents.singleWhere((agent) => agent.isDaemon);
      final runtime = agents.singleWhere((agent) => agent.isRuntime);
      expect(daemon.agentDid, 'did:agent:daemon');
      expect(daemon.latest.status, 'ready');
      expect(daemon.latest.version, '0.2.0');
      expect(runtime.agentDid, 'did:agent:runtime');
      expect(runtime.kind, AgentKind.runtime);
      expect(runtime.daemonAgentDid, 'did:agent:daemon');
      expect(runtime.latest.status, 'needs_config');
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(
        container.read(chatThreadProvider('did:agent:daemon')).messages,
        isEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('实时可见控制状态不进入最近会话、消息或通知', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        agentControlPayload: const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'runtime',
          'runtime_agent_did': 'did:agent:runtime',
          'runtime': <String, Object?>{
            'agent_did': 'did:agent:runtime',
            'status': 'ready',
          },
        },
        conversation: ConversationSummary(
          threadId: 'dm:runtime',
          conversationId: 'dm:runtime',
          displayName: 'Hermes',
          lastMessagePreview: 'Agent 已准备好。',
          lastMessageAt: DateTime(2026, 4, 5, 12, 0),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:runtime',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'status'});

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, isEmpty);
      expect(
        container.read(chatThreadProvider('dm:runtime')).messages,
        isEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('实时 Message Agent 控制 payload 回收到 chat provider', () async {
      final conversation = ConversationSummary(
        threadId: 'direct:did:human:bob',
        conversationId: 'direct:did:human:bob',
        displayName: 'Bob',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 6, 19, 10, 0),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:human:bob',
      );
      container
          .read(conversationListProvider.notifier)
          .upsertConversation(conversation);
      container
          .read(chatThreadsProvider.notifier)
          .debugSeedMessageForTesting(
            ChatMessage(
              localId: 'msg_1',
              remoteId: 'msg_1',
              threadId: conversation.threadId,
              senderDid: 'did:human:bob',
              receiverDid: 'did:test:me',
              content: 'hello',
              createdAt: DateTime(2026, 6, 19, 10, 0),
              isMine: false,
              sendState: MessageSendState.sent,
            ),
          );
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
          'daemon_agent_did': 'did:agent:daemon',
          'daemon': <String, Object?>{
            'agent_did': 'did:agent:daemon',
            'status': 'ready',
            'display_name': 'Message Daemon',
          },
          'runtimes': <Object?>[
            <String, Object?>{
              'agent_did': 'did:agent:runtime',
              'daemon_agent_did': 'did:agent:daemon',
              'runtime': 'hermes',
              'status': 'ready',
              'display_name': 'Hermes Message Agent',
            },
          ],
        },
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);

      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        agentControlPayload: <String, Object?>{
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
        },
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'control'});

      final action = container
          .read(chatThreadProvider(conversation.threadId))
          .appActionRecords['act_draft'];
      expect(action, isNotNull);
      expect(action!.state, 'requires_confirmation');
      expect(action.request?.args['draft_text'], '收到，我会处理。');
      expect(
        container.read(conversationListProvider).conversations,
        isNotEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('实时连接失败时刷新会话数据但不使用相同 token 循环重连', () async {
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:me',
              credentialName: 'default',
              displayName: 'Me',
              handle: 'me',
              jwtToken: 'token',
            ),
          );
      container.read(appRuntimeProvider);

      realtimeGateway.setStatus(RealtimeConnectionStatus.failed);
      await pumpEventQueue();

      expect(gateway.refreshSessionCalls, 1);
      expect(gateway.listConversationsCalls, 1);
      expect(realtimeGateway.connectionStatus, RealtimeConnectionStatus.failed);
    });
  });
}

class _RecordingConversationService implements ConversationService {
  _RecordingConversationService(this.items);

  final List<ConversationSummary> items;
  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);
  int fastCalls = 0;
  int enrichCalls = 0;
  int listCalls = 0;

  void emitPatch(ConversationListPatch patch) {
    _patches.add(patch);
  }

  Future<void> dispose() {
    return _patches.close();
  }

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    return const <ConversationSummary>[];
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return _patches.stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(conversations: items, version: 1);
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return items;
  }

  @override
  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversationSummariesFast(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    enrichCalls += 1;
    return conversations;
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    listCalls += 1;
    return items;
  }

  @override
  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversations(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> ensureConversationInRecents({
    required String ownerDid,
    required String conversationId,
    DateTime? updatedAt,
  }) async {}
}

class _BlockingProfileService implements ProfileApplicationService {
  _BlockingProfileService(this.completer);

  final Completer<void> completer;

  @override
  Future<UserProfile> loadMyProfile() async {
    await completer.future;
    return const UserProfile(
      did: 'did:test:me',
      nickName: 'Me',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'me',
    );
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

SessionIdentity _epochSession(String identity) {
  return SessionIdentity(
    did: 'did:test:$identity',
    credentialName: identity,
    displayName: identity,
    handle: identity,
    jwtToken: 'token-$identity',
  );
}

AppSession _epochAppSession(String identity) {
  return AppSession(
    did: 'did:test:$identity',
    identityId: identity,
    displayName: identity,
    handle: identity,
    localAlias: identity,
    authenticated: true,
    jwtToken: 'token-$identity',
  );
}

Future<AppSession> _commitRuntimeSession(
  ProviderContainer container,
  SessionIdentity session,
) {
  return container
      .read(appSessionServiceProvider)
      .activateIdentity(
        AppSession(
          did: session.did,
          identityId: session.credentialName,
          displayName: session.displayName,
          handle: session.handle,
          localAlias: session.credentialName,
          authenticated: session.jwtToken != null,
          jwtToken: session.jwtToken,
        ),
      );
}

Future<void> _activateRuntimeSession(
  ProviderContainer container,
  SessionIdentity session,
) async {
  final committed = await _commitRuntimeSession(container, session);
  await container
      .read(appRuntimeProvider.notifier)
      .activateCommittedSession(committed);
}

Future<void> _pumpUntil(bool Function() predicate, {String? reason}) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (predicate()) {
      return;
    }
    await pumpEventQueue();
  }
  expect(
    predicate(),
    isTrue,
    reason: reason ?? 'condition did not become true',
  );
}

class _EpochProfileService implements ProfileApplicationService {
  final Completer<UserProfile> _first = Completer<UserProfile>();
  int loadCalls = 0;

  @override
  Future<UserProfile> loadMyProfile() {
    loadCalls += 1;
    if (loadCalls == 1) {
      return _first.future;
    }
    return Future<UserProfile>.value(_profile('second'));
  }

  void completeFirst() {
    if (!_first.isCompleted) {
      _first.complete(_profile('first'));
    }
  }

  void completeFirstIfPending() => completeFirst();

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }

  static UserProfile _profile(String identity) {
    return UserProfile(
      did: 'did:test:$identity',
      nickName: identity,
      bio: '',
      tags: const <String>[],
      profileMarkdown: '',
      handle: identity,
    );
  }
}

class _EpochGroupService extends FakeGroupApplicationService {
  _EpochGroupService() : super(FakeAwikiGateway());

  final Completer<List<GroupSummary>> _first = Completer<List<GroupSummary>>();
  int loadCalls = 0;

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) {
    loadCalls += 1;
    if (loadCalls == 1) {
      return _first.future;
    }
    return Future<List<GroupSummary>>.value(<GroupSummary>[_group('second')]);
  }

  void completeFirst() {
    if (!_first.isCompleted) {
      _first.complete(<GroupSummary>[_group('first')]);
    }
  }

  void completeFirstIfPending() => completeFirst();

  static GroupSummary _group(String identity) {
    return GroupSummary(
      conversationId: 'group:$identity',
      groupId: 'group-$identity',
      displayName: identity,
      description: '',
      memberCount: 1,
      lastMessageAt: null,
    );
  }
}

class _EpochAppSessionService extends FakeAppSessionService {
  _EpochAppSessionService(super.gateway);

  final Completer<AppSession?> _firstRefresh = Completer<AppSession?>();
  Completer<AppSession>? _login;
  int refreshCalls = 0;
  int loginCalls = 0;

  @override
  Future<AppSession?> refreshSession() {
    refreshCalls += 1;
    if (refreshCalls == 1) {
      return _firstRefresh.future;
    }
    return Future<AppSession?>.value(_epochAppSession('second'));
  }

  void completeFirstRefresh() {
    if (!_firstRefresh.isCompleted) {
      _firstRefresh.complete(_epochAppSession('first'));
    }
  }

  void completeFirstRefreshIfPending() => completeFirstRefresh();

  void blockNextLogin() {
    _login = Completer<AppSession>();
  }

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) async {
    loginCalls += 1;
    final session =
        await (_login?.future ??
            Future<AppSession>.value(_epochAppSession('second')));
    return super.activateIdentity(session, transition: transition);
  }

  void completeLogin() {
    final login = _login;
    if (login != null && !login.isCompleted) {
      login.complete(_epochAppSession('second'));
    }
  }

  void completeLoginIfPending() => completeLogin();
}

class _FailingIdentityLoginAppSessionService extends FakeAppSessionService {
  _FailingIdentityLoginAppSessionService(super.gateway);

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) async {
    throw StateError('identity vault unavailable');
  }
}

class _DelayedStaleAuthFailureSessionService extends FakeAppSessionService {
  _DelayedStaleAuthFailureSessionService(super.gateway);

  final Completer<void> firstStarted = Completer<void>();
  final Completer<void> _releaseFirst = Completer<void>();
  int _loginCalls = 0;

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) async {
    _loginCalls += 1;
    if (_loginCalls == 1) {
      firstStarted.complete();
      await _releaseFirst.future;
      throw StateError('session_expired');
    }
    return super.activateIdentity(
      _epochAppSession('second'),
      transition: transition,
    );
  }

  void releaseFirst() {
    if (!_releaseFirst.isCompleted) {
      _releaseFirst.complete();
    }
  }

  void releaseFirstIfPending() => releaseFirst();
}

class _FirstBlockingE2eeFacade extends FakeE2eeFacade {
  final Completer<void> _firstStarted = Completer<void>();
  final Completer<void> _releaseFirst = Completer<void>();
  int _initializeCalls = 0;
  final List<String> initializedDids = <String>[];

  Future<void> get firstStarted => _firstStarted.future;

  @override
  Future<void> initialize(SessionIdentity identity) async {
    _initializeCalls += 1;
    initializedDids.add(identity.did);
    if (_initializeCalls != 1) {
      return;
    }
    _firstStarted.complete();
    await _releaseFirst.future;
  }

  void completeFirst() {
    if (!_releaseFirst.isCompleted) {
      _releaseFirst.complete();
    }
  }

  void completeFirstIfPending() => completeFirst();
}

class _FailingE2eeFacade extends FakeE2eeFacade {
  @override
  Future<void> initialize(SessionIdentity identity) async {
    throw StateError('e2ee initialization failed');
  }
}

class _CountingAgentControlService extends FakeAgentControlService {
  int listAgentsCalls = 0;

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    listAgentsCalls += 1;
    return super.listAgents(includeInactive: includeInactive);
  }
}

class _QueuedRealtimeApplicationService implements RealtimeApplicationService {
  final StreamController<RealtimeUpdate> _updates =
      StreamController<RealtimeUpdate>.broadcast();
  final StreamController<RealtimeConnectionStatus> _connectionStates =
      StreamController<RealtimeConnectionStatus>.broadcast();
  bool _isRunning = false;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates =>
      _connectionStates.stream;

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<RealtimeUpdate> get updates => _updates.stream;

  void emit(RealtimeUpdate update) {
    _updates.add(update);
  }

  @override
  Future<void> start() async {
    _isRunning = true;
    _connectionStates.add(RealtimeConnectionStatus.connected);
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _connectionStates.add(RealtimeConnectionStatus.idle);
  }

  Future<void> dispose() async {
    await _updates.close();
    await _connectionStates.close();
  }
}

final class _FakeDesktopShellService implements DesktopShellService {
  int showWindowCalls = 0;
  Completer<void>? showWindowCompleter;

  @override
  Stream<DesktopShellEvent> get events =>
      const Stream<DesktopShellEvent>.empty();

  @override
  Future<void> completeExit() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<DesktopStorageRoots> getStorageRoots() async =>
      const DesktopStorageRoots(
        support: 'support',
        cache: 'cache',
        temp: 'temp',
      );

  @override
  Future<void> hideWindow() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setUnreadCount(int count) async {}

  @override
  Future<void> showWindow() async {
    showWindowCalls += 1;
    await showWindowCompleter?.future;
  }
}

ChatMessage _runtimeTestMessage(ConversationSummary conversation, int index) {
  return ChatMessage(
    localId: '${conversation.threadId}:local:$index',
    remoteId: '${conversation.threadId}:remote:$index',
    threadId: conversation.threadId,
    senderDid: conversation.targetDid ?? 'did:test:peer',
    receiverDid: 'did:test:me',
    content: 'message $index',
    createdAt: DateTime(2026, 6, 29, 10, index),
    isMine: false,
    sendState: MessageSendState.sent,
  );
}
