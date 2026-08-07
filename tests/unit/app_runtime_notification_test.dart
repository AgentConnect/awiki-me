import 'dart:async';

import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/account_state_sync_request_bus.dart';
import 'package:awiki_me/src/application/app_presentation_service.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/desktop_shell_service.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/group_collection_page.dart';
import 'package:awiki_me/src/application/models/push_installation.dart';
import 'package:awiki_me/src/application/models/remote_push_sync_receipt.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/application/ports/push_installation_port.dart';
import 'package:awiki_me/src/application/ports/remote_push_sync_port.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/remote_push_installation_coordinator.dart';
import 'package:awiki_me/src/application/remote_push_message_reference.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_terminal_notification.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/notification_target.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/domain/services/remote_push_client.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/remote_push_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_navigation_provider.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';
import 'devices/device_test_support.dart';

class _RecordingAccountStateSyncRequestBus extends AccountStateSyncRequestBus {
  final List<String> reasons = <String>[];
  int failuresRemaining = 0;

  void clear() {
    reasons.clear();
    failuresRemaining = 0;
  }

  @override
  bool get hasHandler => true;

  @override
  void attach(AccountStateSyncRequestHandler handler) {}

  @override
  void detach() {}

  @override
  Future<void> request(
    String reason, {
    bool force = false,
    AccountStateVersionFloor? minimumVersion,
  }) async {
    reasons.add(reason);
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('account state sync failed');
    }
  }
}

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
    late FakeDeviceManagementCore deviceCore;
    late _RecordingAccountStateSyncRequestBus accountStateRequests;
    late _BoundSessionConversationService boundConversationService;
    late _RecordingRemotePushInstallationCoordinator pushInstallations;
    late _RecordingRemotePushClient remotePushClient;
    late ProviderContainer container;
    late Duration messageSyncMinInterval;

    ProviderContainer createContainer({
      bool enableRemotePush = false,
      bool enableRemotePushEvents = false,
      RemotePushSyncPort? remotePushSyncPort,
      AppSessionService? appSessions,
    }) {
      final effectiveSessions =
          appSessions ?? _CurrentBarrierAppSessionService(gateway);
      return ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(
              messageSyncV2ReadEnabled: enableRemotePushEvents,
            ),
          ),
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
            conversationService: boundConversationService,
          ),
          appSessionServiceProvider.overrideWithValue(effectiveSessions),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          appPresentationServiceProvider.overrideWithValue(
            const _ForegroundAppPresentationService(),
          ),
          desktopShellServiceProvider.overrideWithValue(desktopShell),
          accountStateSyncRequestBusProvider.overrideWithValue(
            accountStateRequests,
          ),
          if (enableRemotePush)
            remotePushInstallationCoordinatorProvider.overrideWithValue(
              pushInstallations,
            ),
          if (enableRemotePush)
            remotePushStorageScopeIdProvider.overrideWithValue(_pushScopeId),
          if (enableRemotePushEvents)
            remotePushClientProvider.overrideWithValue(remotePushClient),
          if (remotePushSyncPort != null)
            remotePushSyncPortProvider.overrideWithValue(remotePushSyncPort),
          appRuntimeProvider.overrideWith(
            (ref) => AppRuntimeController(
              ref,
              realtimeSyncRetryBaseDelay: Duration.zero,
            ),
          ),
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => MessageSyncCoordinator(
              ref,
              minInterval: messageSyncMinInterval,
              failureBackoff: Duration.zero,
            ),
          ),
          deviceManagementCorePortProvider.overrideWithValue(deviceCore),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
    }

    void enableRemotePushLifecycle() {
      container.dispose();
      container = createContainer(enableRemotePush: true);
    }

    void enableRemotePushEventRuntime() {
      container.dispose();
      container = createContainer(
        enableRemotePush: true,
        enableRemotePushEvents: true,
      );
    }

    setUp(() {
      gateway = FakeAwikiGateway();
      realtimeGateway = FakeRealtimeGateway();
      notificationFacade = FakeNotificationFacade();
      messageSyncService = FakeMessageSyncService();
      desktopShell = _FakeDesktopShellService();
      boundConversationService = _BoundSessionConversationService(gateway);
      pushInstallations = _RecordingRemotePushInstallationCoordinator();
      remotePushClient = _RecordingRemotePushClient();
      remotePushClient.conversationService = boundConversationService;
      accountStateRequests = _RecordingAccountStateSyncRequestBus();
      messageSyncMinInterval = Duration.zero;
      deviceCore = FakeDeviceManagementCore()
        ..registry = const DeviceRegistrySnapshot(
          did: 'did:test:me',
          devices: <DeviceSummary>[
            DeviceSummary(
              protocolDeviceId: 'admin-current',
              signingKeyId: 'did:test:me#admin-sign',
              e2eeKeyId: 'did:test:me#admin-e2ee',
              status: DeviceStatus.active,
              role: DeviceRole.admin,
              managementReady: true,
              isCurrent: true,
            ),
          ],
        );
      gateway.myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      );
      gateway.conversations = const <ConversationSummary>[];
      container = createContainer();
      addTearDown(() async {
        container.dispose();
        await remotePushClient.dispose();
        await boundConversationService.dispose();
      });
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

    Future<void> activateBound({
      String ownerIdentityId = 'owner-identity-a',
      String accountId = 'account-a',
      String did = 'did:test:me',
      String protocolDeviceId = 'device-a',
    }) {
      boundConversationService.prepareOwner(ownerIdentityId);
      return _activateRuntimeSession(
        container,
        SessionIdentity(
          did: did,
          credentialName: ownerIdentityId,
          displayName: 'Bound',
          accountBinding: SessionAccountBinding(
            ownerIdentityId: ownerIdentityId,
            accountId: accountId,
            currentDid: did,
            protocolDeviceId: protocolDeviceId,
            identityGeneration: '1',
            deviceAuthGeneration: '1',
          ),
        ),
      );
    }

    Future<void> settleAgentInventoryRefresh() {
      return container.read(agentsProvider.notifier).syncRemoteInventory();
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

    void seedRuntimeAgent() {
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
              'runtime': 'codex',
              'display_name': 'Codex',
              'status': 'ready',
            },
          ],
        },
      );
    }

    RealtimeUpdate buildRuntimeUpdate({
      String messageId = 'remote-1',
      String content = 'Runtime final reply',
    }) {
      return RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: messageId,
          remoteId: messageId,
          threadId: 'dm:runtime',
          senderDid: 'did:agent:runtime',
          senderName: 'Codex',
          receiverDid: 'did:test:me',
          content: content,
          createdAt: DateTime(2026, 7, 27, 12),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:runtime',
          conversationId: 'dm:runtime',
          displayName: 'Codex',
          lastMessagePreview: content,
          lastMessageAt: DateTime(2026, 7, 27, 12),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:agent:runtime',
        ),
      );
    }

    Map<String, Object?> terminalPayload({
      String eventId = 'evt_run_terminal:run_1:completed',
      String state = 'finished',
      String? outcome = 'completed',
      String summary = '任务已完成',
      String? nextStep,
      String? finalMessageId = 'remote-1',
    }) => <String, Object?>{
      'schema': 'awiki.agent.status.v1',
      'event_id': eventId,
      'run_id': 'run_1',
      'state': state,
      if (outcome != null) 'business_outcome': outcome,
      'summary': summary,
      'next_step': nextStep,
      'final_message_id': finalMessageId,
    };

    Future<void> emitControl(Map<String, Object?> payload) async {
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        agentControlPayload: payload,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'status'});
      await pumpEventQueue();
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

    test('激活身份时清理上一身份的会话和联系人详情', () async {
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());
      container
          .read(friendsWorkspaceNavigationProvider.notifier)
          .showProfileDid('did:test:old-contact');

      await activate();

      expect(container.read(selectedConversationProvider), isNull);
      final friendsNavigation = container.read(
        friendsWorkspaceNavigationProvider,
      );
      expect(friendsNavigation.detail, FriendsWorkspaceDetail.overview);
      expect(friendsNavigation.selectedDid, isNull);
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

    test('退出登录时清理当前会话和联系人详情', () async {
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
      container
          .read(friendsWorkspaceNavigationProvider.notifier)
          .showProfileDid('did:test:stale-contact');

      await container.read(appRuntimeProvider.notifier).logout();

      expect(container.read(selectedConversationProvider), isNull);
      final friendsNavigation = container.read(
        friendsWorkspaceNavigationProvider,
      );
      expect(friendsNavigation.detail, FriendsWorkspaceDetail.overview);
      expect(friendsNavigation.selectedDid, isNull);
    });

    test('非法通知 payload 只打开消息列表并清理旧选择', () async {
      await activate();
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());
      container
          .read(shellDestinationProvider.notifier)
          .select(ShellDestination.profile);

      notificationFacade.emitActivation(const NotificationActivation.invalid());
      await pumpEventQueue();

      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
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

      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
      expect(container.read(selectedConversationProvider), isNull);
      expect(desktopShell.showWindowCalls, 1);
    });

    test('同 scope 但 owner 不匹配的通知只打开消息列表', () async {
      await activate();
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());
      container
          .read(shellDestinationProvider.notifier)
          .select(ShellDestination.tasks);

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

      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
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

      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
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
      const coldSession = SessionIdentity(
        did: 'did:test:me',
        credentialName: 'default',
        displayName: 'Me',
        handle: 'me',
        jwtToken: 'token',
      );
      await _commitRuntimeSession(container, coldSession);
      container.read(sessionProvider.notifier).setSession(coldSession);
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
      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
      expect(
        container.read(selectedConversationProvider),
        conversation.conversationId,
      );
      expect(gateway.fetchLocalDmHistoryCalls, greaterThan(0));
      expect(gateway.lastFetchedLocalDmPeerDid, conversation.targetDid);
    });

    test('前台收到消息时静默同步，不显示 UI feedback 或系统通知', () async {
      gateway.nextRealtimeUpdate = buildUpdate();
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('前台当前可见会话收到消息时不显示全局 UI feedback', () async {
      final update = buildUpdate();
      gateway.nextRealtimeUpdate = update;
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      container
          .read(chatThreadsProvider.notifier)
          .markConversationVisible(update.conversationHint!);

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('激活身份后后台调度 startup 可靠同步', () async {
      final conversation = ConversationSummary(
        threadId: 'dm:startup-seed',
        conversationId: 'dm:startup-seed',
        displayName: 'Startup peer',
        lastMessagePreview: 'seeded before sync',
        lastMessageAt: DateTime.utc(2026, 7, 29),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:test:startup-peer',
      );
      gateway.conversations = <ConversationSummary>[conversation];

      await activate();

      expect(gateway.listConversationsCalls, 1);
      expect(container.read(conversationListProvider).conversations, [
        conversation,
      ]);
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('startup'));
      expect(gateway.listConversationsCalls, 2);
      expect(container.read(appRuntimeProvider).isBusy, isFalse);
    });

    test(
      'auth revoked fences realtime timers sync and old projections',
      () async {
        enableRemotePushLifecycle();
        gateway.conversations = <ConversationSummary>[
          ConversationSummary(
            threadId: 'dm:revoked',
            conversationId: 'dm:revoked',
            displayName: 'Old projection',
            lastMessagePreview: 'must be hidden',
            lastMessageAt: DateTime.utc(2026, 7, 28),
            unreadCount: 1,
            isGroup: false,
            targetDid: 'did:test:peer',
          ),
        ];
        messageSyncService.deltaResult = const MessageSyncOutcome(
          status: MessageSyncStatus.authRevoked,
          eventsApplied: 0,
          pagesFetched: 1,
          errorCode: 'device_auth_revoked',
        );
        container
            .read(appLifecycleProvider.notifier)
            .setLifecycle(AppLifecycleState.resumed);

        await activateBound();
        await pumpEventQueue();

        expect(
          container.read(messageSyncCoordinatorProvider).status,
          MessageSyncCoordinatorStatus.idle,
        );
        expect(container.read(appRuntimeProvider).authRevoked, isTrue);
        expect(container.read(sessionProvider).session, isNull);
        expect(container.read(conversationListProvider).conversations, isEmpty);
        expect(
          container.read(chatThreadProvider('dm:revoked')).messages,
          isEmpty,
        );
        expect(realtimeGateway.isConnected, isFalse);
        expect(gateway.logoutCalls, 1);
        expect(pushInstallations.calls, contains('deactivate'));
        expect(pushInstallations.calls, isNot(contains('disable')));

        final callsAfterFence = messageSyncService.syncReasons.length;
        container
            .read(appLifecycleProvider.notifier)
            .setLifecycle(AppLifecycleState.paused);
        container
            .read(appLifecycleProvider.notifier)
            .setLifecycle(AppLifecycleState.resumed);
        await container
            .read(messageSyncCoordinatorProvider.notifier)
            .requestSync('manual_refresh', immediate: true);
        await pumpEventQueue();

        expect(messageSyncService.syncReasons, hasLength(callsAfterFence));
        expect(realtimeGateway.isConnected, isFalse);

        messageSyncService.deltaResult = const MessageSyncOutcome(
          status: MessageSyncStatus.idle,
          eventsApplied: 0,
          pagesFetched: 1,
        );
        await activate();
        await pumpEventQueue();

        expect(container.read(sessionProvider).session, isNotNull);
        expect(container.read(appRuntimeProvider).authRevoked, isFalse);
        expect(
          container.read(messageSyncCoordinatorProvider).status,
          MessageSyncCoordinatorStatus.idle,
        );
      },
    );

    test('系统通知变化独立刷新可信 Join 收件箱，不依赖消息同步成功', () async {
      await activate();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      final joinRequestCallsBeforeEvent = deviceCore.joinRequestCalls;
      deviceCore.joinRequests = <DeviceJoinRequestNotice>[
        DeviceJoinRequestNotice(
          eventId: 'event-join-1',
          joinSessionId: 'join-1',
          did: 'did:test:me',
          protocolDeviceId: 'device-new',
          candidateKeyFingerprint: 'sha256:abc123',
          issuedAt: DateTime.utc(2026, 7, 26, 10),
          expiresAt: DateTime.utc(2030),
          state: DeviceJoinRemoteState.pending,
          claimedByCurrentDevice: false,
          canStartVerification: true,
        ),
      ];
      messageSyncService.nextDeltaError = StateError('sync unavailable');
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        systemNotificationChanged: true,
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{
        'type': 'system_notification_changed',
      });
      await pumpEventQueue();

      expect(
        messageSyncService.syncReasons,
        contains('system_notification_changed'),
      );
      expect(
        deviceCore.joinRequestCalls,
        greaterThan(joinRequestCallsBeforeEvent),
      );
      expect(
        container
            .read(devicesProvider)
            .visibleJoinRequests
            .map((request) => request.joinSessionId),
        contains('join-1'),
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
      expect(container.read(conversationListProvider).conversations, isEmpty);
    });

    test('已授权成员设备按精确 DID 单飞激活一次', () async {
      const joinedDid = 'did:test:joined-member';
      gateway.loginResult = const SessionIdentity(
        did: joinedDid,
        credentialName: 'joined-local',
        displayName: 'Joined',
        handle: 'joined',
      );
      final runtime = container.read(appRuntimeProvider.notifier);

      await Future.wait(<Future<void>>[
        runtime.activateJoinedMember(joinedDid),
        runtime.activateJoinedMember(joinedDid),
      ]);

      expect(gateway.loginCalls, 1);
      expect(gateway.lastLoginCredentialName, joinedDid);
      expect(container.read(sessionProvider).session?.did, joinedDid);
      expect(container.read(appRuntimeProvider).activatedDid, joinedDid);
    });

    test('成员设备激活遇到错误 DID 时失败关闭并登出', () async {
      gateway.loginResult = const SessionIdentity(
        did: 'did:test:wrong',
        credentialName: 'wrong-local',
        displayName: 'Wrong',
        handle: 'wrong',
      );

      await expectLater(
        container
            .read(appRuntimeProvider.notifier)
            .activateJoinedMember('did:test:expected'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'joined_identity_did_mismatch',
          ),
        ),
      );

      expect(gateway.loginCalls, 1);
      expect(gateway.logoutCalls, 1);
      expect(container.read(sessionProvider).session, isNull);
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

    test('恢复前台先等待 fresh binding 与 epoch barrier', () async {
      final sessions = _BarrierControlledAppSessionService(
        gateway,
        _epochAppSession('first'),
      );
      container.dispose();
      container = createContainer(appSessions: sessions);
      await _activateRuntimeSession(container, _epochSession('first'));
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();

      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await _pumpUntil(() => sessions.refreshCalls == 1);

      expect(messageSyncService.syncReasons, isNot(contains('app_resumed')));

      sessions.completeRefresh();
      await _pumpUntil(
        () => messageSyncService.syncReasons.contains('app_resumed'),
      );
    });

    test('恢复前台 barrier 失败时不恢复实时或业务同步', () async {
      final sessions = _BarrierControlledAppSessionService(
        gateway,
        _epochAppSession('first'),
      );
      container.dispose();
      container = createContainer(appSessions: sessions);
      await _activateRuntimeSession(container, _epochSession('first'));
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();

      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await _pumpUntil(() => sessions.refreshCalls == 1);
      sessions.failRefresh();
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, isNot(contains('app_resumed')));
    });

    test('realtime reconnect 与 recovery 共享 fresh epoch barrier', () async {
      final sessions = _BarrierControlledAppSessionService(
        gateway,
        _epochAppSession('first'),
      );
      container.dispose();
      container = createContainer(appSessions: sessions);
      await _activateRuntimeSession(container, _epochSession('first'));
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();

      realtimeGateway.setStatus(RealtimeConnectionStatus.disconnected);
      realtimeGateway.setStatus(RealtimeConnectionStatus.connected);
      await _pumpUntil(() => sessions.refreshCalls == 1);

      expect(
        messageSyncService.syncReasons,
        isNot(contains('realtime_reconnected')),
      );
      sessions.completeRefresh();
      await _pumpUntil(
        () => messageSyncService.syncReasons.contains('realtime_reconnected'),
      );
      expect(sessions.refreshCalls, 1);
    });

    test('前台周期对账弥补丢失的实时提示并在后台停止', () async {
      final periodicSync = FakeMessageSyncService();
      final periodicContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: periodicSync,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          deviceManagementCorePortProvider.overrideWithValue(deviceCore),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          appRuntimeProvider.overrideWith(
            (ref) => AppRuntimeController(
              ref,
              foregroundCatchUpInterval: const Duration(milliseconds: 10),
            ),
          ),
        ],
      );
      addTearDown(periodicContainer.dispose);

      await _activateRuntimeSession(
        periodicContainer,
        const SessionIdentity(
          did: 'did:test:me',
          credentialName: 'default',
          displayName: 'Me',
          handle: 'me',
          jwtToken: 'token',
        ),
      );
      await pumpEventQueue();
      periodicSync.syncReasons.clear();
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(periodicSync.syncReasons, contains('foreground_catch_up'));

      periodicContainer
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      await pumpEventQueue();
      periodicSync.syncReasons.clear();
      await Future<void>.delayed(const Duration(milliseconds: 35));

      expect(periodicSync.syncReasons, isEmpty);
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
          appSessionServiceProvider.overrideWithValue(
            _CurrentBarrierAppSessionService(gateway),
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
        domains: const <SyncDomain>{SyncDomain.message},
        reason: 'message_available',
        syncDirty: true,
        gapDetected: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_gap'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
    });

    test('realtime sync-only hint 调度 delta，不直接构造消息', () async {
      await activate();
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message},
        reason: 'message_available',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('message_available'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
    });

    test('realtime message domain 绕过普通同步最小间隔', () async {
      messageSyncMinInterval = const Duration(minutes: 1);
      await activateBound();
      await pumpEventQueue();
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );
      await coordinator.requestSync('rate_limit_baseline', immediate: true);
      messageSyncService.syncReasons.clear();
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message},
        reason: 'message_available',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, <String>['message_available']);
    });

    test('v2 多域 hint 合并后分别路由消息与账号状态协调器', () async {
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      accountStateRequests.clear();
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{
          SyncDomain.message,
          SyncDomain.profile,
          SyncDomain.agentInventory,
        },
        reason: 'account_and_message_changed',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, <String>[
        'account_and_message_changed',
      ]);
      expect(accountStateRequests.reasons, <String>[
        'account_and_message_changed',
      ]);
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
    });

    test('未知 v2 domain 只触发账号 Manifest 对账', () async {
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      accountStateRequests.clear();
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        reason: 'unknown_domain_changed',
        syncDirty: true,
        hasUnknownDomain: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, isEmpty);
      expect(accountStateRequests.reasons, <String>['unknown_domain_changed']);
    });

    test('消息域同步失败后按 session fence 退避重试且不并发', () async {
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      messageSyncService.nextDeltaError = StateError('temporary delta failure');
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message},
        reason: 'message_retry',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, <String>[
        'message_retry',
        'automatic_retry',
      ]);
      expect(messageSyncService.maxActiveSyncNowCalls, 1);
    });

    test('账号域 request bus 抛错后由 runtime 有界退避重试', () async {
      await activateBound();
      await pumpEventQueue();
      accountStateRequests.clear();
      accountStateRequests.failuresRemaining = 1;
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.profile},
        reason: 'profile_retry',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(accountStateRequests.reasons, <String>[
        'profile_retry',
        'profile_retry',
      ]);
    });

    test('session 切换会取消旧 owner 已排队的失败重试', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
            conversationService: boundConversationService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          accountStateSyncRequestBusProvider.overrideWithValue(
            accountStateRequests,
          ),
          appRuntimeProvider.overrideWith(
            (ref) => AppRuntimeController(
              ref,
              realtimeSyncRetryBaseDelay: const Duration(milliseconds: 30),
            ),
          ),
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => MessageSyncCoordinator(
              ref,
              minInterval: Duration.zero,
              failureBackoff: Duration.zero,
            ),
          ),
          deviceManagementCorePortProvider.overrideWithValue(deviceCore),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
      await activateBound();
      await pumpEventQueue();
      accountStateRequests.clear();
      accountStateRequests.failuresRemaining = 1;
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.profile},
        reason: 'old_owner_retry',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();
      expect(accountStateRequests.reasons, <String>['old_owner_retry']);

      await activateBound(
        ownerIdentityId: 'owner-identity-b',
        accountId: 'account-b',
        did: 'did:test:next',
        protocolDeviceId: 'device-b',
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();

      expect(accountStateRequests.reasons, <String>['old_owner_retry']);
      expect(
        container.read(sessionProvider).session?.ownerIdentityId,
        'owner-identity-b',
      );
    });

    test('重复乱序多域 hint 保持跨协调器单飞并合并 follow-up', () async {
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      accountStateRequests.clear();
      final firstSync = Completer<void>();
      messageSyncService.syncNowCompleter = firstSync;

      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message},
        reason: 'message_available',
        syncDirty: true,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.agentStatus, SyncDomain.profile},
        reason: 'account_changed',
        syncDirty: true,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message, SyncDomain.profile},
        reason: 'message_available',
        syncDirty: true,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      expect(messageSyncService.activeSyncNowCalls, 1);
      expect(messageSyncService.maxActiveSyncNowCalls, 1);
      firstSync.complete();
      await pumpEventQueue();

      expect(messageSyncService.maxActiveSyncNowCalls, 1);
      expect(messageSyncService.syncReasons, hasLength(2));
      expect(accountStateRequests.reasons, <String>['message_available']);
    });

    test('容器销毁后进行中的实时同步 drain 不再读取旧 provider', () async {
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      final inFlightSync = Completer<void>();
      messageSyncService.syncNowCompleter = inFlightSync;
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message},
        reason: 'dispose_during_message_sync',
        syncDirty: true,
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();
      expect(messageSyncService.activeSyncNowCalls, 1);

      container.dispose();
      inFlightSync.complete();
      await pumpEventQueue();

      expect(messageSyncService.activeSyncNowCalls, 0);
    });

    test('旧 owner hint 完成后不能清空或代替新 session 调度', () async {
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      accountStateRequests.clear();
      final oldSync = Completer<void>();
      messageSyncService.syncNowCompleter = oldSync;
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:me',
        domains: <SyncDomain>{SyncDomain.message},
        reason: 'old_owner_message',
        syncDirty: true,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();

      await activateBound(
        ownerIdentityId: 'owner-identity-b',
        accountId: 'account-b',
        did: 'did:test:next',
        protocolDeviceId: 'device-b',
      );
      accountStateRequests.clear();
      gateway.nextRealtimeUpdate = const RealtimeUpdate(
        ownerDid: 'did:test:next',
        domains: <SyncDomain>{SyncDomain.deviceRegistry},
        reason: 'new_owner_registry',
        syncDirty: true,
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'sync'});
      await pumpEventQueue();
      expect(accountStateRequests.reasons, isEmpty);

      messageSyncService.syncNowCompleter = null;
      oldSync.complete();
      await pumpEventQueue();

      expect(accountStateRequests.reasons, <String>['new_owner_registry']);
      expect(
        container.read(sessionProvider).session?.ownerIdentityId,
        'owner-identity-b',
      );
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
      await _pumpUntil(
        () =>
            conversations.fastCalls == 2 &&
            !container.read(messageSyncCoordinatorProvider).isSyncing,
        reason: 'startup sync post-commit conversation read did not finish',
      );

      expect(conversations.fastCalls, 2);
      expect(conversations.enrichCalls, 2);
      expect(
        container.read(conversationListProvider).conversations.single.threadId,
        'dm:1',
      );
      slowProfile.complete();
      await Future<void>.delayed(Duration.zero);
    });

    test('恢复和重连复用资料刷新但每次 Core 提交都重新读取会话', () async {
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
          appSessionServiceProvider.overrideWithValue(
            _CurrentBarrierAppSessionService(gateway),
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
      await _pumpUntil(
        () =>
            sync.syncReasons.contains('startup') &&
            sync.syncReasons.contains('app_resumed') &&
            conversations.fastCalls == 3 &&
            !container.read(messageSyncCoordinatorProvider).isSyncing,
        reason: 'startup and resume post-commit reads did not finish',
      );

      expect(sync.syncReasons, contains('startup'));
      expect(sync.syncReasons, contains('app_resumed'));
      expect(conversations.fastCalls, 3);
      expect(conversations.enrichCalls, 3);
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
      await _pumpUntil(
        () =>
            profiles.loadCalls == 2 &&
            groups.loadCalls == 2 &&
            container.read(profileProvider).profile?.did == 'did:test:second' &&
            container.read(groupProvider).groups.length == 1 &&
            container.read(groupProvider).groups.single.groupId ==
                'group-second',
      );

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

    test('本地身份切换后自动为新身份调度 startup 可靠同步', () async {
      final sessions = _EpochAppSessionService(gateway);
      messageSyncService = _IdentitySwitchUnreadMessageSyncService(gateway);
      addTearDown(sessions.completeFirstRefreshIfPending);
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
          appSessionServiceProvider.overrideWithValue(sessions),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          desktopShellServiceProvider.overrideWithValue(desktopShell),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      final runtime = container.read(appRuntimeProvider.notifier);

      await _activateRuntimeSession(container, _epochSession('first'));
      await _pumpUntil(
        () =>
            messageSyncService.syncReasons.contains('startup') &&
            !container.read(messageSyncCoordinatorProvider).isSyncing,
        reason: 'first identity startup sync did not finish',
      );
      final firstEpoch = container.read(sessionProvider).activeEpoch!;
      messageSyncService.syncReasons.clear();

      await runtime.loginWithLocalCredential('second');
      await _pumpUntil(
        () =>
            messageSyncService.syncReasons.contains('startup') &&
            !container.read(messageSyncCoordinatorProvider).isSyncing,
        reason: 'second identity startup sync was not scheduled automatically',
      );

      final secondEpoch = container.read(sessionProvider).activeEpoch!;
      expect(container.read(sessionProvider).session?.did, 'did:test:second');
      expect(secondEpoch.identityKey, 'second');
      expect(secondEpoch, isNot(equals(firstEpoch)));
      expect(messageSyncService.syncReasons, <String>['startup']);
      expect(
        container.read(messageSyncCoordinatorProvider).lastReason,
        'startup',
      );
      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(1));
      expect(conversations.single.unreadCount, 1);
      expect(conversations.single.lastMessagePreview, 'new identity unread');
      expect(messageSyncService.conversationAfterRequests, isEmpty);
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

    test('撤权后延迟完成的 profile 刷新不能回填已清理投影', () async {
      final profileRelease = Completer<void>();
      final profiles = _BlockingProfileService(profileRelease);
      final sync = FakeMessageSyncService();
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
          profileApplicationServiceProvider.overrideWithValue(profiles),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );

      await activate();
      await profiles.started.future;
      sync.deltaResult = const MessageSyncOutcome(
        status: MessageSyncStatus.authRevoked,
        eventsApplied: 0,
        pagesFetched: 1,
        errorCode: 'device_auth_revoked',
      );
      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('manual_refresh', immediate: true);
      await pumpEventQueue();
      expect(container.read(sessionProvider).session, isNull);

      profileRelease.complete();
      await pumpEventQueue();

      expect(container.read(profileProvider).profile, isNull);
      expect(container.read(appRuntimeProvider).authRevoked, isTrue);
    });

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
      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.lastInAppTitle, isNull);

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
      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.lastInAppTitle, isNull);
    });

    test('v2 reader普通消息只信 committed 通知且保留 encrypted realtime 旧路径', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: <Override>[
          awikiEnvironmentConfigProvider.overrideWithValue(
            AwikiEnvironmentConfig(messageSyncV2ReadEnabled: true),
          ),
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          ...fakeApplicationServiceOverrides(
            gateway,
            realtimeGateway: realtimeGateway,
            messageSyncService: messageSyncService,
          ),
          realtimeGatewayProvider.overrideWithValue(realtimeGateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          appPresentationServiceProvider.overrideWithValue(
            const _ForegroundAppPresentationService(),
          ),
          deviceManagementCorePortProvider.overrideWithValue(deviceCore),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
          messageSyncCoordinatorProvider.overrideWith(
            (ref) => MessageSyncCoordinator(
              ref,
              minInterval: Duration.zero,
              failureBackoff: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();

      final incoming = buildUpdate().message!;
      messageSyncService.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          CommittedIncomingMessage(
            eventId: 'event-committed-1',
            logicalMessageId: incoming.remoteId!,
            message: incoming,
          ),
        ],
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: incoming,
        conversationHint: buildUpdate().conversationHint,
        group: GroupSummary(
          groupId: 'group-persistent',
          conversationId: 'group:group-persistent',
          name: 'Persistent Group',
          description: '',
          memberCount: 2,
          lastMessageAt: DateTime.utc(2026, 7, 28),
          myRole: 'member',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(messageSyncService.syncReasons, contains('realtime_message'));
      expect(container.read(chatThreadProvider('dm:1')).messages, isEmpty);
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(container.read(groupProvider).groups, isEmpty);
      expect(notificationFacade.inAppCalls, 0);
      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.systemCalls, 0);

      messageSyncService.deltaResult = const MessageSyncOutcome(
        status: MessageSyncStatus.idle,
        eventsApplied: 0,
        pagesFetched: 0,
      );
      for (final reason in <String>[
        'group.member_changed',
        'group.profile_updated',
      ]) {
        gateway.nextRealtimeUpdate = RealtimeUpdate(
          ownerDid: 'did:test:me',
          group: GroupSummary(
            groupId: 'group-stage-two-state',
            conversationId: 'group:group-stage-two-state',
            name: 'Stage Two Group',
            description: '',
            memberCount: 2,
            lastMessageAt: DateTime.utc(2026, 7, 28, 1),
            myRole: 'member',
          ),
          domains: const <SyncDomain>{SyncDomain.message},
          reason: reason,
          syncDirty: true,
        );
        await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
        await pumpEventQueue();
      }

      expect(container.read(groupProvider).groups, isEmpty);
      expect(notificationFacade.inAppCalls, 0);
      expect(container.read(uiFeedbackProvider), isNull);

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'encrypted-1',
          remoteId: 'encrypted-1',
          threadId: 'dm:encrypted',
          senderDid: 'did:test:encrypted-peer',
          senderName: 'Encrypted Peer',
          receiverDid: 'did:test:me',
          content: 'existing secure realtime payload',
          createdAt: DateTime.utc(2026, 7, 28, 1),
          isMine: false,
          isEncrypted: true,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:encrypted',
          conversationId: 'dm:encrypted',
          displayName: 'Encrypted Peer',
          lastMessagePreview: 'existing secure realtime payload',
          lastMessageAt: DateTime.utc(2026, 7, 28, 1),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:test:encrypted-peer',
        ),
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(notificationFacade.inAppCalls, 0);
      expect(container.read(uiFeedbackProvider), isNull);

      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'encrypted-group-control-1',
          remoteId: 'encrypted-group-control-1',
          conversationId: 'group:secure-group',
          threadId: 'group:secure-group',
          senderDid: 'did:test:encrypted-peer',
          senderName: 'Encrypted Peer',
          groupId: 'secure-group',
          content: 'opaque group control',
          originalType: 'application/awiki-group-e2ee+json',
          createdAt: DateTime.utc(2026, 7, 28, 2),
          isMine: false,
          isEncrypted: true,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'group:secure-group',
          conversationId: 'group:secure-group',
          displayName: 'Secure Group',
          lastMessagePreview: 'opaque group control',
          lastMessageAt: DateTime.utc(2026, 7, 28, 2),
          unreadCount: 1,
          isGroup: true,
          groupId: 'secure-group',
        ),
        group: GroupSummary(
          groupId: 'secure-group',
          conversationId: 'group:secure-group',
          name: 'Secure Group',
          description: '',
          memberCount: 2,
          lastMessageAt: DateTime.utc(2026, 7, 28, 2),
          myRole: 'member',
        ),
        syncDirty: true,
        reason: 'group.e2ee.update',
      );
      await realtimeGateway.emit(const <String, Object?>{'type': 'group'});
      await pumpEventQueue();

      expect(
        container.read(groupProvider).groups.single.groupId,
        'secure-group',
      );
      expect(notificationFacade.inAppCalls, 0);
      expect(container.read(uiFeedbackProvider), isNull);
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

    test('Skill Agent 即使被旧模型标成 daemon，前台也不显示消息横幅', () async {
      const skillDid =
          'did:wba:agent-connect.cn:agent:skill:skill-test:e1_skill';
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'daemon',
          'daemon_agent_did': skillDid,
          'daemon': <String, Object?>{
            'agent_did': skillDid,
            'display_name': 'AWiki Skill Agent',
            'status': 'ready',
          },
        },
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'skill-normal',
          remoteId: 'skill-normal',
          threadId: 'dm:skill',
          senderDid: skillDid,
          senderName: 'AWiki Skill Agent',
          receiverDid: 'did:test:me',
          content: '任务已完成',
          createdAt: DateTime(2026, 7, 29, 10, 17),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:skill',
          conversationId: 'dm:skill',
          displayName: 'AWiki Skill Agent',
          lastMessagePreview: '任务已完成',
          lastMessageAt: DateTime(2026, 7, 29, 10, 17),
          unreadCount: 1,
          isGroup: false,
          targetDid: skillDid,
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('Skill Agent 即使被旧模型标成 daemon，后台仍显示系统通知', () async {
      const skillDid =
          'did:wba:agent-connect.cn:agent:skill:skill-test:e1_skill';
      container.read(agentsProvider.notifier).applyControlPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'daemon',
          'daemon_agent_did': skillDid,
          'daemon': <String, Object?>{
            'agent_did': skillDid,
            'display_name': 'AWiki Skill Agent',
            'status': 'ready',
          },
        },
      );
      gateway.nextRealtimeUpdate = RealtimeUpdate(
        ownerDid: 'did:test:me',
        message: ChatMessage(
          localId: 'skill-background',
          remoteId: 'skill-background',
          threadId: 'dm:skill',
          senderDid: skillDid,
          senderName: 'AWiki Skill Agent',
          receiverDid: 'did:test:me',
          content: '任务已完成',
          createdAt: DateTime(2026, 7, 29, 10, 18),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversationHint: ConversationSummary(
          threadId: 'dm:skill',
          conversationId: 'dm:skill',
          displayName: 'AWiki Skill Agent',
          lastMessagePreview: '任务已完成',
          lastMessageAt: DateTime(2026, 7, 29, 10, 18),
          unreadCount: 1,
          isGroup: false,
          targetDid: skillDid,
        ),
      );
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);

      await activate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.systemNotificationCount, 1);
      expect(notificationFacade.lastSystemTitle, 'AWiki Skill Agent');
    });

    test('Runtime Agent 普通实时消息先进入相关窗口且只触发 core sync', () async {
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
      await settleAgentInventoryRefresh();
      seedRuntimeAgent();
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
      expect(notificationFacade.lastInAppTitle, isNull);
    });

    test('实时 Agent hint 不覆盖现有会话，只调度 core sync', () async {
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
      await settleAgentInventoryRefresh();
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
      expect(notificationFacade.lastInAppTitle, isNull);
    });

    test('Agent inventory 完成前的实时消息前台静默且不会污染最近会话', () async {
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
      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.lastInAppTitle, isNull);
    });

    test('实时控制状态只调度可靠同步，不直接更新智能体投影', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await Future<void>.delayed(Duration.zero);
      messageSyncService.syncReasons.clear();
      final agentsBeforeHint = container
          .read(agentsProvider)
          .agents
          .map(
            (agent) =>
                '${agent.agentDid}|${agent.latest.status}|'
                '${agent.latest.version ?? ''}',
          )
          .toList(growable: false);

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
      await pumpEventQueue();

      expect(
        container
            .read(agentsProvider)
            .agents
            .map(
              (agent) =>
                  '${agent.agentDid}|${agent.latest.status}|'
                  '${agent.latest.version ?? ''}',
            )
            .toList(growable: false),
        agentsBeforeHint,
      );
      expect(
        messageSyncService.syncReasons,
        contains('realtime_agent_control'),
      );
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(
        container.read(chatThreadProvider('did:agent:daemon')).messages,
        isEmpty,
      );
      expect(notificationFacade.lastInAppTitle, isNull);
      expect(notificationFacade.lastSystemTitle, isNull);
    });

    test('前台三种业务终态保持安静且不进入通知 facade', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();

      for (final entry in <(String, String?)>[
        ('completed', null),
        ('blocked', '补充访问权限'),
        ('action_required', '确认是否继续'),
      ]) {
        await emitControl(
          terminalPayload(
            eventId: 'evt_${entry.$1}',
            outcome: entry.$1,
            nextStep: entry.$2,
            finalMessageId: 'msg_${entry.$1}',
          ),
        );
        expect(container.read(uiFeedbackProvider), isNull);
      }

      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 0);
      expect(container.read(conversationListProvider).conversations, isEmpty);
    });

    test('前台真实运行失败保持安静', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();

      await emitControl(
        terminalPayload(
          eventId: 'evt_failed',
          state: 'failed',
          outcome: null,
          finalMessageId: null,
        ),
      );

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 0);
    });

    test('running 状态不通知', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();

      await emitControl(terminalPayload(state: 'running'));

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 0);
    });

    test('同一 run 的同一终态在 replay 和不同 event id 下只通知一次', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();

      await emitControl(terminalPayload());
      await emitControl(terminalPayload());
      await emitControl(terminalPayload(eventId: 'evt_reconnected'));

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 0);
    });

    test('普通最终回复先到时三种业务终态胜出且只通知一次', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await settleAgentInventoryRefresh();
      seedRuntimeAgent();

      for (final entry in <(String, String?)>[
        ('completed', null),
        ('blocked', '补充访问权限'),
        ('action_required', '确认是否继续'),
      ]) {
        final messageId = 'msg_message_first_${entry.$1}';
        gateway.nextRealtimeUpdate = buildRuntimeUpdate(messageId: messageId);
        await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
        await emitControl(
          terminalPayload(
            eventId: 'evt_message_first_${entry.$1}',
            outcome: entry.$1,
            nextStep: entry.$2,
            finalMessageId: messageId,
          ),
        );

        expect(container.read(uiFeedbackProvider), isNull);
      }

      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 0);
    });

    test('completed 状态先到时普通最终回复不双响', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await settleAgentInventoryRefresh();
      seedRuntimeAgent();

      await emitControl(terminalPayload());
      gateway.nextRealtimeUpdate = buildRuntimeUpdate();
      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      await pumpEventQueue();

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 0);
    });

    test('Runtime Agent 非终态消息在相关窗口超时后回退普通通知', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await activate();
      await settleAgentInventoryRefresh();
      seedRuntimeAgent();
      gateway.nextRealtimeUpdate = buildRuntimeUpdate(
        messageId: 'msg_timeout',
        content: 'Progress needs attention',
      );

      await realtimeGateway.emit(const <String, Object?>{'type': 'message'});
      expect(notificationFacade.inAppNotificationCount, 0);

      await Future<void>.delayed(
        AgentTerminalNotificationDeduplicator.runtimeMessageCorrelationWindow +
            const Duration(milliseconds: 100),
      );
      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
      await emitControl(
        terminalPayload(
          eventId: 'evt_timeout_late',
          finalMessageId: 'msg_timeout',
        ),
      );
      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
    });

    test(
      'logout cancels pending Runtime Agent ordinary notification',
      () async {
        container
            .read(appLifecycleProvider.notifier)
            .setLifecycle(AppLifecycleState.resumed);
        await activate();
        await settleAgentInventoryRefresh();
        seedRuntimeAgent();
        gateway.nextRealtimeUpdate = buildRuntimeUpdate(
          messageId: 'msg_logout_pending',
        );
        await realtimeGateway.emit(const <String, Object?>{'type': 'message'});

        await container.read(appRuntimeProvider.notifier).logout();
        await Future<void>.delayed(
          AgentTerminalNotificationDeduplicator
                  .runtimeMessageCorrelationWindow +
              const Duration(milliseconds: 100),
        );

        expect(notificationFacade.inAppNotificationCount, 0);
        expect(notificationFacade.systemNotificationCount, 0);
      },
    );

    test('后台终态仅发送一次本地系统通知', () async {
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      await activate();

      await emitControl(
        terminalPayload(outcome: 'action_required', nextStep: '确认是否继续'),
      );
      await emitControl(
        terminalPayload(
          eventId: 'evt_replay',
          outcome: 'action_required',
          nextStep: '确认是否继续',
        ),
      );

      expect(container.read(uiFeedbackProvider), isNull);
      expect(notificationFacade.inAppNotificationCount, 0);
      expect(notificationFacade.systemNotificationCount, 1);
      expect(notificationFacade.lastSystemTitle, isNotEmpty);
      expect(notificationFacade.lastSystemBody, contains('确认是否继续'));
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

    test('实时 Personal Agent 控制 payload 回收到 chat provider', () async {
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
              'display_name': 'Hermes Personal Agent',
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

    test('实时连接失败通过 fresh barrier 后重新连接', () async {
      const failedSession = SessionIdentity(
        did: 'did:test:me',
        credentialName: 'default',
        displayName: 'Me',
        handle: 'me',
        jwtToken: 'token',
      );
      await _commitRuntimeSession(container, failedSession);
      container.read(sessionProvider.notifier).setSession(failedSession);
      container.read(appRuntimeProvider);

      realtimeGateway.setStatus(RealtimeConnectionStatus.failed);
      await pumpEventQueue();

      expect(gateway.refreshSessionCalls, 1);
      expect(gateway.listConversationsCalls, 1);
      expect(
        realtimeGateway.connectionStatus,
        RealtimeConnectionStatus.connected,
      );
    });

    test('实时连接失败且 barrier 失败时不恢复业务', () async {
      final sessions = _BarrierControlledAppSessionService(
        gateway,
        _epochAppSession('first'),
      );
      container.dispose();
      container = createContainer(appSessions: sessions);
      await _activateRuntimeSession(container, _epochSession('first'));
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();

      realtimeGateway.setStatus(RealtimeConnectionStatus.failed);
      await _pumpUntil(() => sessions.refreshCalls == 1);
      sessions.failRefresh();
      await pumpEventQueue();

      expect(realtimeGateway.connectionStatus, RealtimeConnectionStatus.failed);
      expect(
        messageSyncService.syncReasons,
        isNot(contains('realtime_reconnected')),
      );
    });

    test('绑定 Push installation 使用当前 scope、epoch 与协议设备', () async {
      enableRemotePushLifecycle();
      await activateBound(protocolDeviceId: 'protocol-device-a');
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);

      final epoch = container.read(sessionProvider).activeEpoch!;
      final bound = pushInstallations.boundSessions.single;
      expect(bound.storageScopeId, _pushScopeId);
      expect(bound.ownerDid, 'did:test:me');
      expect(bound.generation, epoch.generation);
      expect(bound.logicalDeviceId, 'protocol-device-a');
    });

    test('缺少 account binding 或协议设备时仍绑定并可在登出时 disable', () async {
      enableRemotePushLifecycle();

      await activate();
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);
      expect(pushInstallations.boundSessions.single.logicalDeviceId, isNull);

      pushInstallations.calls.clear();
      await container.read(appRuntimeProvider.notifier).logout();
      expect(pushInstallations.calls, <String>['deactivate', 'disable']);

      await activateBound(protocolDeviceId: '   ');
      await _pumpUntil(() => pushInstallations.boundSessions.length == 2);
      expect(pushInstallations.boundSessions.last.logicalDeviceId, isNull);
    });

    test('binding owner 不匹配时拒绝生成 Push installation session', () {
      final resolved = resolveRemotePushInstallationSession(
        storageScopeId: _pushScopeId,
        sessionState: const SessionState(
          generation: 7,
          session: SessionIdentity(
            did: 'did:test:me',
            credentialName: 'owner-identity-a',
            displayName: 'Me',
            accountBinding: SessionAccountBinding(
              ownerIdentityId: 'owner-identity-a',
              accountId: 'account-a',
              currentDid: 'did:test:other-owner',
              protocolDeviceId: 'wrong-owner-device',
              identityGeneration: '1',
              deviceAuthGeneration: '1',
            ),
          ),
        ),
      );

      expect(resolved, isNull);
    });

    test('Push 绑定失败不会使已提交登录失败', () async {
      enableRemotePushLifecycle();
      pushInstallations.failBind = true;

      await activateBound();
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);

      expect(container.read(sessionProvider).session?.did, 'did:test:me');
      expect(container.read(appRuntimeProvider).activatedDid, 'did:test:me');
    });

    test('登出先本地停用并在 session 清除前尝试远端 disable', () async {
      enableRemotePushLifecycle();
      await activateBound();
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);
      pushInstallations.calls.clear();
      pushInstallations.failDisable = true;
      pushInstallations.onDisable = () {
        expect(container.read(sessionProvider).session, isNotNull);
      };

      await container.read(appRuntimeProvider.notifier).logout();

      expect(pushInstallations.calls, <String>['deactivate', 'disable']);
      expect(container.read(sessionProvider).session, isNull);
      expect(gateway.logoutCalls, 1);
    });

    test('身份替换和凭据删除都先停用当前 Push installation', () async {
      enableRemotePushLifecycle();
      await activateBound();
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);
      pushInstallations.calls.clear();

      await container
          .read(appRuntimeProvider.notifier)
          .prepareIdentityActivation();

      expect(pushInstallations.calls, <String>['deactivate', 'disable']);
      expect(container.read(sessionProvider).session, isNull);

      await activateBound();
      await _pumpUntil(() => pushInstallations.boundSessions.length == 2);
      pushInstallations.calls.clear();

      await container
          .read(appRuntimeProvider.notifier)
          .deleteCurrentCredential();

      expect(pushInstallations.calls, <String>['deactivate', 'disable']);
      expect(container.read(sessionProvider).session, isNull);
    });

    test('本地身份登录替换时 Push disable 失败也继续激活新身份', () async {
      enableRemotePushLifecycle();
      await activateBound();
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);
      pushInstallations.calls.clear();
      pushInstallations.failDisable = true;
      gateway.loginResult = const SessionIdentity(
        did: 'did:test:second',
        credentialName: 'second',
        displayName: 'Second',
        jwtToken: 'token-second',
        accountBinding: SessionAccountBinding(
          ownerIdentityId: 'owner-identity-b',
          accountId: 'account-b',
          currentDid: 'did:test:second',
          protocolDeviceId: 'device-b',
          identityGeneration: '2',
          deviceAuthGeneration: '2',
        ),
      );
      boundConversationService.prepareOwner('owner-identity-b');

      await container
          .read(appRuntimeProvider.notifier)
          .loginWithLocalCredential('second');

      expect(pushInstallations.calls.take(2), <String>[
        'deactivate',
        'disable',
      ]);
      expect(container.read(sessionProvider).session?.did, 'did:test:second');
      expect(
        container.read(appRuntimeProvider).activatedDid,
        'did:test:second',
      );
    });

    test('恢复前台时刷新当前 Push installation', () async {
      enableRemotePushLifecycle();
      await activateBound();
      await _pumpUntil(() => pushInstallations.boundSessions.isNotEmpty);
      pushInstallations.calls.clear();

      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.paused);
      container
          .read(appLifecycleProvider.notifier)
          .setLifecycle(AppLifecycleState.resumed);
      await _pumpUntil(() => pushInstallations.refreshedSessions.isNotEmpty);

      expect(pushInstallations.calls, <String>['refresh']);
      expect(
        pushInstallations.refreshedSessions.single.logicalDeviceId,
        'device-a',
      );
    });

    test(
      '冷启动 Push 等待 patch 和 active session 后以 remote_push 刷新投影再 ack',
      () async {
        final patchGate = Completer<void>();
        boundConversationService.patchGate = patchGate;
        final conversation = _remotePushConversation('conversation-cold');
        final committed = _remotePushCommittedMessage(
          conversation,
          logicalId: 'logical-cold',
        );
        messageSyncService.deltaResult = MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[committed],
        );
        remotePushClient.addPending(
          _remotePushEvent(
            'delivery-cold',
            kind: RemotePushEventKind.notificationReceived,
          ),
        );
        enableRemotePushEventRuntime();

        final activation = activateBound();
        await pumpEventQueue();

        expect(messageSyncService.syncReasons, isEmpty);
        expect(remotePushClient.acknowledged, isEmpty);

        gateway.conversations = <ConversationSummary>[conversation];
        patchGate.complete();
        await activation;
        await _pumpUntil(() => remotePushClient.acknowledged.isNotEmpty);

        expect(
          messageSyncService.syncReasons.first,
          anyOf('startup', 'remote_push'),
        );
        expect(
          container
              .read(conversationListProvider)
              .conversations
              .map((item) => item.conversationId),
          contains(conversation.conversationId),
        );
        expect(notificationFacade.inAppCalls, 0);
        expect(notificationFacade.systemCalls, 0);
        expect(boundConversationService.fastRefreshCompleted, isTrue);
        expect(remotePushClient.ackObservedAfterFastRefresh, isTrue);
      },
    );

    test(
      'notification_opened 精确 mid 打开 committed canonical conversation',
      () async {
        final conversation = _remotePushConversation('conversation-opened');
        final committed = _remotePushCommittedMessage(
          conversation,
          logicalId: 'logical-opened',
        );
        messageSyncService.deltaResult = MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[committed],
        );
        enableRemotePushEventRuntime();
        await activateBound();
        await pumpEventQueue();
        messageSyncService.syncReasons.clear();
        gateway.conversations = <ConversationSummary>[conversation];

        remotePushClient.emit(
          _remotePushEvent(
            'delivery-opened',
            kind: RemotePushEventKind.notificationOpened,
            mid: remotePushOpaqueMessageReference('logical-opened'),
          ),
        );
        await _pumpUntil(() => remotePushClient.acknowledged.isNotEmpty);

        expect(messageSyncService.syncReasons.first, 'remote_push');
        expect(
          container.read(shellDestinationProvider),
          ShellDestination.messages,
        );
        expect(
          container.read(selectedConversationProvider),
          conversation.conversationId,
        );
      },
    );

    test('无法匹配的 notification_opened 回退消息列表并清除旧选择', () async {
      enableRemotePushEventRuntime();
      await activateBound();
      await pumpEventQueue();
      messageSyncService.syncReasons.clear();
      container
          .read(shellDestinationProvider.notifier)
          .select(ShellDestination.agents);
      container
          .read(selectedConversationProvider.notifier)
          .selectConversation(staleSelectedConversation());

      remotePushClient.emit(
        _remotePushEvent(
          'delivery-unmatched',
          kind: RemotePushEventKind.notificationOpened,
          mid: remotePushOpaqueMessageReference('not-committed'),
        ),
      );
      await _pumpUntil(() => remotePushClient.acknowledged.isNotEmpty);

      expect(
        container.read(shellDestinationProvider),
        ShellDestination.messages,
      );
      expect(container.read(selectedConversationProvider), isNull);
    });

    test('通知激活 barrier 失败时不导航旧 epoch', () async {
      final sessions = _BarrierControlledAppSessionService(
        gateway,
        _epochAppSession('first'),
      );
      container.dispose();
      container = createContainer(appSessions: sessions);
      await _activateRuntimeSession(container, _epochSession('first'));
      container
          .read(shellDestinationProvider.notifier)
          .select(ShellDestination.tasks);

      notificationFacade.emitActivation(const NotificationActivation.invalid());
      await _pumpUntil(() => sessions.refreshCalls == 1);
      sessions.failRefresh();
      await pumpEventQueue();

      expect(container.read(shellDestinationProvider), ShellDestination.tasks);
    });

    test(
      'logout during Push sync fences acknowledgement and navigation',
      () async {
        final syncGate = Completer<void>();
        final conversation = _remotePushConversation('conversation-logout');
        messageSyncService
          ..deltaResult = MessageSyncOutcome(
            status: MessageSyncStatus.changed,
            eventsApplied: 1,
            pagesFetched: 1,
            committedIncomingMessages: <CommittedIncomingMessage>[
              _remotePushCommittedMessage(
                conversation,
                logicalId: 'logical-logout',
              ),
            ],
          )
          ..syncNowCompleter = syncGate;
        remotePushClient.addPending(
          _remotePushEvent(
            'delivery-logout',
            kind: RemotePushEventKind.notificationOpened,
            mid: remotePushOpaqueMessageReference('logical-logout'),
          ),
        );
        enableRemotePushEventRuntime();

        var activationCompleted = false;
        final activation = activateBound().whenComplete(
          () => activationCompleted = true,
        );
        await _pumpUntil(() => messageSyncService.syncReasons.isNotEmpty);
        expect(activationCompleted, isTrue);
        await container.read(appRuntimeProvider.notifier).logout();
        syncGate.complete();
        await activation;
        await pumpEventQueue();

        expect(remotePushClient.acknowledged, isEmpty);
        expect(container.read(selectedConversationProvider), isNull);
      },
    );

    test(
      'identity A Push completion cannot select identity B conversation',
      () async {
        final syncGate = Completer<void>();
        final conversation = _remotePushConversation('conversation-a');
        messageSyncService
          ..deltaResult = MessageSyncOutcome(
            status: MessageSyncStatus.changed,
            eventsApplied: 1,
            pagesFetched: 1,
            committedIncomingMessages: <CommittedIncomingMessage>[
              _remotePushCommittedMessage(conversation, logicalId: 'logical-a'),
            ],
          )
          ..syncNowCompleter = syncGate;
        remotePushClient.addPending(
          _remotePushEvent(
            'delivery-a',
            kind: RemotePushEventKind.notificationOpened,
            mid: remotePushOpaqueMessageReference('logical-a'),
          ),
        );
        enableRemotePushEventRuntime();

        final activation = activateBound();
        await _pumpUntil(() => messageSyncService.syncReasons.isNotEmpty);
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:b',
                credentialName: 'identity-b',
                displayName: 'B',
              ),
            );
        syncGate.complete();
        await activation;
        await pumpEventQueue();

        expect(remotePushClient.acknowledged, isEmpty);
        expect(container.read(selectedConversationProvider), isNull);
      },
    );

    test(
      'resume drains retained Push and refreshes installation registration',
      () async {
        enableRemotePushEventRuntime();
        await activateBound();
        await pumpEventQueue();
        messageSyncService.syncReasons.clear();
        pushInstallations.calls.clear();
        remotePushClient.acknowledgeError = StateError('first ack fails');

        remotePushClient.emit(
          _remotePushEvent(
            'delivery-resume',
            kind: RemotePushEventKind.messageReceived,
          ),
        );
        await _pumpUntil(() => remotePushClient.acknowledgeAttempts == 1);
        expect(remotePushClient.acknowledged, isEmpty);

        remotePushClient.acknowledgeError = null;
        container
            .read(appLifecycleProvider.notifier)
            .setLifecycle(AppLifecycleState.paused);
        container
            .read(appLifecycleProvider.notifier)
            .setLifecycle(AppLifecycleState.resumed);
        await _pumpUntil(() => remotePushClient.acknowledged.isNotEmpty);

        expect(
          messageSyncService.syncReasons,
          containsAll(<String>['remote_push', 'app_resumed']),
        );
        expect(pushInstallations.calls, contains('refresh'));
      },
    );

    test(
      'registration_changed refreshes installation without message sync',
      () async {
        enableRemotePushEventRuntime();
        await activateBound();
        await pumpEventQueue();
        messageSyncService.syncReasons.clear();
        pushInstallations.calls.clear();

        remotePushClient.emit(
          _remotePushEvent(
            'delivery-registration',
            kind: RemotePushEventKind.registrationChanged,
          ),
        );
        await _pumpUntil(() => pushInstallations.refreshedSessions.isNotEmpty);

        expect(pushInstallations.calls, <String>['refresh']);
        expect(messageSyncService.syncReasons, isEmpty);
      },
    );

    test(
      'successful receipt followed by stale navigation retains event without selection',
      () async {
        final conversation = _remotePushConversation('conversation-stale-nav');
        final committed = _remotePushCommittedMessage(
          conversation,
          logicalId: 'logical-stale-nav',
        );
        late ProviderContainer eventContainer;
        final syncPort = _RecordingRemotePushSyncPort(
          receipt: RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[committed],
          ),
          beforeReturn: () {
            eventContainer
                .read(sessionProvider.notifier)
                .setSession(
                  const SessionIdentity(
                    did: 'did:test:b',
                    credentialName: 'identity-b',
                    displayName: 'B',
                  ),
                );
          },
        );
        remotePushClient.addPending(
          _remotePushEvent(
            'delivery-stale-nav',
            kind: RemotePushEventKind.notificationOpened,
            mid: remotePushOpaqueMessageReference('logical-stale-nav'),
          ),
        );
        container.dispose();
        eventContainer = container = createContainer(
          enableRemotePush: true,
          enableRemotePushEvents: true,
          remotePushSyncPort: syncPort,
        );
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:a',
                credentialName: 'identity-a',
                displayName: 'A',
              ),
            );
        final context = _remotePushContext(container);
        final coordinator = container.read(
          remotePushMessageSyncCoordinatorProvider,
        )!;

        await coordinator.activateSession(context);

        expect(syncPort.calls, 1);
        expect(remotePushClient.acknowledged, isEmpty);
        expect(container.read(selectedConversationProvider), isNull);
      },
    );

    test(
      'session change during canonical commit retains event without selection',
      () async {
        final conversation = _remotePushConversation('conversation-gated-nav');
        final committed = _remotePushCommittedMessage(
          conversation,
          logicalId: 'logical-gated-nav',
        );
        final syncPort = _RecordingRemotePushSyncPort(
          receipt: RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.succeeded,
            committedIncomingMessages: <CommittedIncomingMessage>[committed],
          ),
        );
        final commitGate = Completer<void>();
        boundConversationService.ensureConversationGate = commitGate;
        remotePushClient.addPending(
          _remotePushEvent(
            'delivery-gated-nav',
            kind: RemotePushEventKind.notificationOpened,
            mid: remotePushOpaqueMessageReference('logical-gated-nav'),
          ),
        );
        container.dispose();
        container = createContainer(
          enableRemotePush: true,
          enableRemotePushEvents: true,
          remotePushSyncPort: syncPort,
        );
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:a',
                credentialName: 'identity-a',
                displayName: 'A',
              ),
            );
        gateway.conversations = <ConversationSummary>[conversation];
        final coordinator = container.read(
          remotePushMessageSyncCoordinatorProvider,
        )!;
        final drain = coordinator.activateSession(
          _remotePushContext(container),
        );
        await boundConversationService.ensureConversationStarted.future;

        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:b',
                credentialName: 'identity-b',
                displayName: 'B',
              ),
            );
        commitGate.complete();
        await drain;

        expect(remotePushClient.acknowledged, isEmpty);
        expect(container.read(selectedConversationProvider), isNull);
      },
    );

    test(
      'session change during registration refresh deactivates old queued drain',
      () async {
        final refreshGate = Completer<void>();
        pushInstallations.refreshGate = refreshGate;
        final syncPort = _RecordingRemotePushSyncPort();
        container.dispose();
        container = createContainer(
          enableRemotePush: true,
          enableRemotePushEvents: true,
          remotePushSyncPort: syncPort,
        );
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:a',
                credentialName: 'identity-a',
                displayName: 'A',
              ),
            );
        final coordinator = container.read(
          remotePushMessageSyncCoordinatorProvider,
        )!;
        await coordinator.activateSession(_remotePushContext(container));

        remotePushClient.emit(
          _remotePushEvent(
            'delivery-refresh',
            kind: RemotePushEventKind.registrationChanged,
          ),
        );
        await pushInstallations.refreshStarted.future;
        remotePushClient.emit(
          _remotePushEvent(
            'delivery-after-refresh',
            kind: RemotePushEventKind.messageReceived,
          ),
        );
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:b',
                credentialName: 'identity-b',
                displayName: 'B',
              ),
            );
        refreshGate.complete();
        await pumpEventQueue();

        expect(syncPort.calls, 0);
        expect(remotePushClient.acknowledged, isEmpty);
      },
    );

    test(
      'current-session registration refresh failure still triggers queued drain',
      () async {
        pushInstallations.failRefresh = true;
        final syncPort = _RecordingRemotePushSyncPort();
        container.dispose();
        container = createContainer(
          enableRemotePush: true,
          enableRemotePushEvents: true,
          remotePushSyncPort: syncPort,
        );
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:test:a',
                credentialName: 'identity-a',
                displayName: 'A',
              ),
            );
        final coordinator = container.read(
          remotePushMessageSyncCoordinatorProvider,
        )!;
        await coordinator.activateSession(_remotePushContext(container));

        remotePushClient.emit(
          _remotePushEvent(
            'delivery-refresh-failure',
            kind: RemotePushEventKind.registrationChanged,
          ),
        );
        remotePushClient.emit(
          _remotePushEvent(
            'delivery-after-refresh-failure',
            kind: RemotePushEventKind.messageReceived,
          ),
        );
        await _pumpUntil(() => remotePushClient.acknowledged.isNotEmpty);

        expect(syncPort.calls, 1);
        expect(remotePushClient.acknowledged.single, <String>[
          'delivery-after-refresh-failure',
        ]);
      },
    );
  });
}

final _pushScopeId = StorageScopeId.parse(
  '00000000-0000-4000-8000-000000000002',
);

final class _RecordingRemotePushInstallationCoordinator
    extends RemotePushInstallationCoordinator {
  _RecordingRemotePushInstallationCoordinator()
    : super(
        client: _NoopRemotePushClient(),
        installations: _NoopPushInstallationPort(),
      );

  final List<String> calls = <String>[];
  final List<RemotePushInstallationSession> boundSessions =
      <RemotePushInstallationSession>[];
  final List<RemotePushInstallationSession> refreshedSessions =
      <RemotePushInstallationSession>[];
  bool failBind = false;
  bool failDisable = false;
  bool failRefresh = false;
  void Function()? onDisable;
  Completer<void>? refreshGate;
  final Completer<void> refreshStarted = Completer<void>();

  @override
  Future<void> bindActiveSession(RemotePushInstallationSession session) async {
    calls.add('bind');
    boundSessions.add(session);
    if (failBind) {
      throw StateError('bind failed');
    }
  }

  @override
  void deactivateLocally(RemotePushInstallationSession session) {
    calls.add('deactivate');
  }

  @override
  Future<void> disableActiveInstallation(
    RemotePushInstallationSession session,
  ) async {
    calls.add('disable');
    onDisable?.call();
    if (failDisable) {
      throw StateError('disable failed');
    }
  }

  @override
  Future<void> refreshActiveSession(
    RemotePushInstallationSession session,
  ) async {
    calls.add('refresh');
    refreshedSessions.add(session);
    if (!refreshStarted.isCompleted) {
      refreshStarted.complete();
    }
    await refreshGate?.future;
    if (failRefresh) {
      throw StateError('refresh failed');
    }
  }
}

final class _NoopRemotePushClient implements RemotePushClient {
  @override
  Stream<RemotePushEvent> get events => const Stream<RemotePushEvent>.empty();

  @override
  List<RemotePushEvent> get pendingEvents => const <RemotePushEvent>[];

  @override
  RemotePushRegistration? get registration => null;

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<RemotePushRegistration?> initialize() async => null;
}

final class _RecordingRemotePushClient implements RemotePushClient {
  final StreamController<RemotePushEvent> _events =
      StreamController<RemotePushEvent>.broadcast(sync: true);
  final Map<String, RemotePushEvent> _pending = <String, RemotePushEvent>{};
  final List<List<String>> acknowledged = <List<String>>[];
  Object? acknowledgeError;
  int acknowledgeAttempts = 0;
  bool ackObservedAfterFastRefresh = false;
  _BoundSessionConversationService? conversationService;

  void addPending(RemotePushEvent event) {
    _pending[event.deliveryId] = event;
  }

  void emit(RemotePushEvent event) {
    addPending(event);
    _events.add(event);
  }

  @override
  Stream<RemotePushEvent> get events => _events.stream;

  @override
  List<RemotePushEvent> get pendingEvents =>
      List<RemotePushEvent>.unmodifiable(_pending.values);

  @override
  RemotePushRegistration? get registration => null;

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {
    acknowledgeAttempts += 1;
    ackObservedAfterFastRefresh =
        conversationService?.fastRefreshCompleted == true;
    final error = acknowledgeError;
    if (error != null) {
      throw error;
    }
    final ids = deliveryIds.toList(growable: false);
    acknowledged.add(ids);
    for (final deliveryId in ids) {
      _pending.remove(deliveryId);
    }
  }

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<RemotePushRegistration?> initialize() async => null;
}

final class _RecordingRemotePushSyncPort implements RemotePushSyncPort {
  _RecordingRemotePushSyncPort({
    this.receipt = const RemotePushSyncReceipt(
      disposition: RemotePushSyncDisposition.succeeded,
    ),
    this.beforeReturn,
  });

  final RemotePushSyncReceipt receipt;
  final void Function()? beforeReturn;
  int calls = 0;

  @override
  Future<RemotePushSyncReceipt> requestRemotePushSync({
    RemotePushPresentationDisposition presentation =
        RemotePushPresentationDisposition.providerPresented,
  }) async {
    calls += 1;
    beforeReturn?.call();
    return receipt;
  }
}

final class _NoopPushInstallationPort implements PushInstallationPort {
  @override
  Future<PushInstallation> disable(String installationId) {
    throw UnimplementedError();
  }

  @override
  Future<PushInstallation> upsert(RemotePushRegistration registration) {
    throw UnimplementedError();
  }
}

class _BoundSessionConversationService extends FakeConversationService {
  _BoundSessionConversationService(super.gateway);

  final List<StreamController<ConversationListPatch>> _controllers =
      <StreamController<ConversationListPatch>>[];
  String? _ownerIdentityId;
  void Function()? onWatchPatches;
  Completer<void>? patchGate;
  Completer<void>? ensureConversationGate;
  final Completer<void> ensureConversationStarted = Completer<void>();
  bool fastRefreshCompleted = false;

  void prepareOwner(String ownerIdentityId) {
    _ownerIdentityId = ownerIdentityId;
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    final controller = StreamController<ConversationListPatch>.broadcast(
      sync: true,
    );
    _controllers.add(controller);
    final ownerIdentityId = _ownerIdentityId;
    if (ownerIdentityId != null) {
      scheduleMicrotask(() async {
        await patchGate?.future;
        if (controller.isClosed) {
          return;
        }
        controller.add(
          ConversationListPatch(
            kind: ConversationListPatchKind.reset,
            ownerIdentityId: ownerIdentityId,
            ownerDid: ownerDid,
            version: 1,
            unreadTotal: 0,
            items: gateway.conversations,
          ),
        );
        onWatchPatches?.call();
      });
    }
    return controller.stream;
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final conversations = await super.listConversationSummariesFast(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
    fastRefreshCompleted = true;
    return conversations;
  }

  @override
  Future<void> ensureConversationInRecents({
    required String ownerDid,
    required String conversationId,
    DateTime? updatedAt,
  }) async {
    if (!ensureConversationStarted.isCompleted) {
      ensureConversationStarted.complete();
    }
    await ensureConversationGate?.future;
    await super.ensureConversationInRecents(
      ownerDid: ownerDid,
      conversationId: conversationId,
      updatedAt: updatedAt,
    );
  }

  Future<void> dispose() async {
    await Future.wait<void>(
      _controllers
          .where((controller) => !controller.isClosed)
          .map((controller) => controller.close()),
    );
  }
}

ConversationSummary _remotePushConversation(String conversationId) {
  return ConversationSummary(
    threadId: 'thread:$conversationId',
    conversationId: conversationId,
    displayName: 'Push peer',
    lastMessagePreview: 'Core committed',
    lastMessageAt: DateTime(2026, 7, 30, 12),
    unreadCount: 1,
    isGroup: false,
    targetDid: 'did:test:push-peer',
  );
}

CommittedIncomingMessage _remotePushCommittedMessage(
  ConversationSummary conversation, {
  required String logicalId,
}) {
  return CommittedIncomingMessage(
    eventId: 'event:$logicalId',
    logicalMessageId: logicalId,
    message: ChatMessage(
      localId: 'local:$logicalId',
      remoteId: 'remote:$logicalId',
      conversationId: conversation.conversationId,
      threadId: conversation.threadId,
      senderDid: 'did:test:push-peer',
      receiverDid: 'did:test:me',
      content: 'Core committed',
      createdAt: DateTime(2026, 7, 30, 12),
      isMine: false,
      sendState: MessageSendState.sent,
    ),
  );
}

RemotePushEvent _remotePushEvent(
  String deliveryId, {
  required RemotePushEventKind kind,
  String? mid,
}) {
  return RemotePushEvent(
    deliveryId: deliveryId,
    kind: kind,
    payload: <String, Object?>{
      if (mid != null)
        'extraMap': <String, Object?>{
          'mid': mid,
          'exp':
              DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond,
        },
    },
    receivedAt: DateTime.now().toUtc(),
  );
}

RemotePushSessionContext _remotePushContext(ProviderContainer container) {
  final epoch = container.read(sessionProvider).activeEpoch!;
  return RemotePushSessionContext(
    storageScopeId: container.read(activeAppTenantProvider).storageScopeId,
    ownerDid: epoch.ownerDid,
    generation: epoch.generation,
  );
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
  Future<AppConversationReadCommitResult> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) async => AppConversationReadCommitResult.acknowledged(watermark);

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
  final Completer<void> started = Completer<void>();

  @override
  Future<UserProfile> loadMyProfile() async {
    if (!started.isCompleted) {
      started.complete();
    }
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
          accountBinding: session.accountBinding,
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

  final Completer<GroupCollectionPage<GroupSummary>> _first =
      Completer<GroupCollectionPage<GroupSummary>>();
  int loadCalls = 0;

  @override
  Future<GroupCollectionPage<GroupSummary>> listGroups({
    int limit = 100,
    String? cursor,
  }) {
    loadCalls += 1;
    if (loadCalls == 1) {
      return _first.future;
    }
    return Future<GroupCollectionPage<GroupSummary>>.value(
      GroupCollectionPage<GroupSummary>(
        items: <GroupSummary>[_group('second')],
        hasMore: false,
      ),
    );
  }

  void completeFirst() {
    if (!_first.isCompleted) {
      _first.complete(
        GroupCollectionPage<GroupSummary>(
          items: <GroupSummary>[_group('first')],
          hasMore: false,
        ),
      );
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

class _IdentitySwitchUnreadMessageSyncService extends FakeMessageSyncService {
  _IdentitySwitchUnreadMessageSyncService(this.gateway);

  final FakeAwikiGateway gateway;
  int _calls = 0;
  static const _conversationId = 'dm:peer-scope:v1:identity-switch-peer';

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    _calls += 1;
    if (_calls == 2) {
      gateway.conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: _conversationId,
          conversationId: _conversationId,
          displayName: 'First identity',
          lastMessagePreview: 'new identity unread',
          lastMessageAt: DateTime.utc(2026, 7, 26),
          unreadCount: 1,
          isGroup: false,
          targetDid: 'did:test:first',
        ),
      ];
    }
    return MessageSyncOutcome(
      status: _calls == 2 ? MessageSyncStatus.changed : MessageSyncStatus.idle,
      eventsApplied: _calls == 2 ? 1 : 0,
      pagesFetched: 1,
    );
  }
}

class _BarrierControlledAppSessionService extends FakeAppSessionService {
  _BarrierControlledAppSessionService(super.gateway, this.refreshedSession);

  final AppSession refreshedSession;
  final Completer<AppSession?> _refresh = Completer<AppSession?>();
  int refreshCalls = 0;

  @override
  Future<AppSession?> refreshSession() {
    refreshCalls += 1;
    return _refresh.future;
  }

  void completeRefresh() {
    if (!_refresh.isCompleted) {
      _refresh.complete(refreshedSession);
    }
  }

  void failRefresh() {
    if (!_refresh.isCompleted) {
      _refresh.completeError(StateError('epoch_barrier_failed'));
    }
  }
}

class _CurrentBarrierAppSessionService extends FakeAppSessionService {
  _CurrentBarrierAppSessionService(super.gateway);

  @override
  Future<AppSession?> refreshSession() async {
    final refreshed = await super.refreshSession();
    return refreshed ?? currentSession();
  }
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

final class _ForegroundAppPresentationService
    implements AppPresentationService {
  const _ForegroundAppPresentationService();

  @override
  Future<AppPresentationState?> currentState() async {
    return const AppPresentationState(
      applicationActive: true,
      windowVisible: true,
      windowMiniaturized: false,
    );
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
