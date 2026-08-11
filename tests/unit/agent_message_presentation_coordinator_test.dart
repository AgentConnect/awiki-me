import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent_message_presentation_store.dart';
import 'package:awiki_me/src/application/app_presentation_service.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/agent_notification_preference.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/application/ports/agent_notification_preference_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_message_v1.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/notification_facade.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_urgent_opt_in_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_urgent_overlay_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'devices/device_test_support.dart';
import 'test_support.dart';

const _senderDid = 'did:test:trusted-agent';
const _conversationId = 'dm:peer-scope:v1:trusted-agent';
final _now = DateTime.utc(2026, 8, 11, 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'WS-first background commit defers durably to provider without App native UI',
    () async {
      final notifications = FakeNotificationFacade();
      final harness = await _Harness.create(notifications: notifications);
      addTearDown(harness.dispose);
      await harness.enableUrgent();
      harness.background();
      harness.sync.deltaResult = _outcome(
        eventId: 'evt_agent_urgent_1',
        acceptedAt: _now,
      );

      await harness.run();
      harness.sync.deltaResult = const MessageSyncOutcome(
        status: MessageSyncStatus.idle,
        eventsApplied: 0,
        pagesFetched: 1,
      );
      await harness.remotePush();

      expect(notifications.structuredNotificationCount, 0);
      expect(notifications.systemCalls, 0);
      expect(notifications.urgentCueCalls, 0);
      expect(notifications.structuredEligibilityCalls, 0);
      expect(harness.receiptLedgerJson, contains('deferredProvider'));
    },
  );

  test(
    'provider-presented commit becomes terminal without App presentation',
    () async {
      final notifications = FakeNotificationFacade();
      final harness = await _Harness.create(notifications: notifications);
      addTearDown(harness.dispose);
      await harness.enableUrgent();
      harness.background();
      harness.sync.deltaResult = _outcome(
        eventId: 'evt_agent_provider_1',
        acceptedAt: _now,
      );

      await harness.remotePush();
      await harness.run();

      expect(notifications.structuredNotificationCount, 0);
      expect(notifications.urgentCueCalls, 0);
      expect(harness.receiptLedgerJson, contains('providerPresented'));
    },
  );

  test(
    'simultaneous WS and provider order converges to provider terminal only',
    () async {
      final sync = _GatedMessageSyncService();
      final notifications = FakeNotificationFacade();
      final harness = await _Harness.create(
        notifications: notifications,
        messageSync: sync,
      );
      addTearDown(() {
        sync.release();
        return harness.dispose();
      });
      await harness.enableUrgent();
      harness.background();
      sync.deltaResult = _outcome(
        eventId: 'evt_agent_simultaneous_1',
        acceptedAt: _now,
      );

      final websocket = harness.run();
      await sync.started.future;
      final provider = harness.remotePush();
      await pumpEventQueue();
      sync.release();
      await Future.wait(<Future<void>>[websocket, provider]);

      expect(notifications.structuredNotificationCount, 0);
      expect(notifications.urgentCueCalls, 0);
      expect(harness.receiptLedgerJson, contains('providerPresented'));
      expect(harness.receiptLedgerJson, isNot(contains('deferredProvider')));
    },
  );

  test(
    'existing claim defers in background and never re-cues foreground',
    () async {
      final background = await _Harness.create();
      addTearDown(background.dispose);
      await background.enableUrgent();
      await background.claim('evt_agent_claimed_background_1');
      background.background();
      background.sync.deltaResult = _outcome(
        eventId: 'evt_agent_claimed_background_1',
        acceptedAt: _now,
      );

      await background.run();

      expect(background.notifications.structuredNotificationCount, 0);
      expect(background.receiptLedgerJson, contains('deferredProvider'));

      final foreground = await _Harness.create();
      addTearDown(foreground.dispose);
      await foreground.enableUrgent();
      await foreground.claim('evt_agent_claimed_foreground_1');
      foreground.foreground();
      foreground.sync.deltaResult = _outcome(
        eventId: 'evt_agent_claimed_foreground_1',
        acceptedAt: _now,
      );

      await foreground.run();

      expect(foreground.notifications.urgentCueCalls, 0);
      expect(foreground.container.read(agentUrgentOverlayProvider), isNull);
    },
  );

  test(
    'foreground current chat cues only; other chat adds one callout',
    () async {
      final notifications = FakeNotificationFacade();
      final harness = await _Harness.create(notifications: notifications);
      addTearDown(harness.dispose);
      await harness.enableUrgent();
      harness.foreground();
      harness.container
          .read(selectedConversationProvider.notifier)
          .selectConversationId(_conversationId);
      harness.sync.deltaResult = _outcome(
        eventId: 'evt_agent_current_1',
        acceptedAt: _now,
      );

      await harness.run();

      expect(notifications.urgentCueCalls, 1);
      expect(notifications.structuredNotificationCount, 0);
      expect(harness.container.read(agentUrgentOverlayProvider), isNull);

      harness.container
          .read(selectedConversationProvider.notifier)
          .selectConversationId('dm:peer-scope:v1:other');
      harness.sync.deltaResult = _outcome(
        eventId: 'evt_agent_other_1',
        acceptedAt: _now,
      );
      await harness.run();

      expect(notifications.urgentCueCalls, 2);
      expect(
        harness.container.read(agentUrgentOverlayProvider)?.conversationId,
        _conversationId,
      );

      harness.sync.deltaResult = _outcome(
        eventId: 'evt_agent_other_2',
        acceptedAt: _now,
      );
      await harness.run();

      expect(notifications.urgentCueCalls, 2);
    },
  );

  test('mute read failure fails closed before any native behavior', () async {
    final notifications = FakeNotificationFacade();
    final localStore = _MuteFailingProductLocalStore();
    final harness = await _Harness.create(
      notifications: notifications,
      localStore: localStore,
    );
    addTearDown(harness.dispose);
    await harness.enableUrgent();
    harness.foreground();
    harness.sync.deltaResult = _outcome(
      eventId: 'evt_agent_mute_failure_1',
      acceptedAt: _now,
    );

    await harness.run();

    expect(notifications.structuredNotificationCount, 0);
    expect(notifications.urgentCueCalls, 0);
    expect(
      localStore.preferences.values.map((item) => item.valueJson).join('\n'),
      contains('suppressedMuted'),
    );
  });

  test('opt-in trust time and permission gates fail closed', () async {
    final defaultOptIn = await _Harness.create();
    addTearDown(defaultOptIn.dispose);
    defaultOptIn.foreground();
    defaultOptIn.container
        .read(selectedConversationProvider.notifier)
        .selectConversationId(_conversationId);
    defaultOptIn.sync.deltaResult = _outcome(
      eventId: 'evt_agent_optout_1',
      acceptedAt: _now,
    );
    await defaultOptIn.run();
    expect(defaultOptIn.notifications.urgentCueCalls, 0);

    final untrusted = await _Harness.create(activeState: 'archived');
    addTearDown(untrusted.dispose);
    await untrusted.enableUrgent();
    untrusted.foreground();
    untrusted.container
        .read(selectedConversationProvider.notifier)
        .selectConversationId(_conversationId);
    untrusted.sync.deltaResult = _outcome(
      eventId: 'evt_agent_untrusted_1',
      acceptedAt: _now,
    );
    await untrusted.run();
    expect(untrusted.notifications.urgentCueCalls, 0);

    final future = await _Harness.create();
    addTearDown(future.dispose);
    await future.enableUrgent();
    future.foreground();
    future.container
        .read(selectedConversationProvider.notifier)
        .selectConversationId(_conversationId);
    future.sync.deltaResult = _outcome(
      eventId: 'evt_agent_future_1',
      acceptedAt: _now.add(const Duration(seconds: 1)),
    );
    await future.run();
    expect(future.notifications.urgentCueCalls, 0);

    final deniedNotifications = FakeNotificationFacade()
      ..structuredEligibility = StructuredNotificationEligibility.denied;
    final denied = await _Harness.create(notifications: deniedNotifications);
    addTearDown(denied.dispose);
    await denied.enableUrgent();
    denied.foreground();
    denied.container
        .read(selectedConversationProvider.notifier)
        .selectConversationId(_conversationId);
    denied.sync.deltaResult = _outcome(
      eventId: 'evt_agent_denied_1',
      acceptedAt: _now,
    );
    await denied.run();
    expect(deniedNotifications.structuredNotificationCount, 0);
    expect(deniedNotifications.urgentCueCalls, 0);
  });

  test(
    'real sender rate ledger downgrades the fourth urgent presentation',
    () async {
      final harness = await _Harness.create();
      addTearDown(harness.dispose);
      await harness.enableUrgent();
      harness.foreground();
      harness.container
          .read(selectedConversationProvider.notifier)
          .selectConversationId(_conversationId);

      for (var index = 0; index < 4; index += 1) {
        harness.sync.deltaResult = _outcome(
          eventId: 'evt_agent_rate_$index',
          acceptedAt: _now,
        );
        await harness.run();
      }

      expect(harness.notifications.structuredNotificationCount, 0);
      expect(harness.notifications.urgentCueCalls, 3);
    },
  );

  test(
    'session fence change during permission await stops presentation',
    () async {
      final notifications = _BlockingNotificationFacade();
      final harness = await _Harness.create(notifications: notifications);
      addTearDown(() {
        notifications.release();
        return harness.dispose();
      });
      await harness.enableUrgent();
      harness.foreground();
      harness.container
          .read(selectedConversationProvider.notifier)
          .selectConversationId(_conversationId);
      harness.sync.deltaResult = _outcome(
        eventId: 'evt_agent_fence_1',
        acceptedAt: _now,
      );

      final pending = harness.run();
      await notifications.started.future;
      harness.container
          .read(sessionProvider.notifier)
          .activateSession(_session(deviceAuthGeneration: '2'));
      notifications.release();
      await pending;

      expect(notifications.structuredNotificationCount, 0);
      expect(notifications.urgentCueCalls, 0);
      expect(harness.container.read(agentUrgentOverlayProvider), isNull);
    },
  );

  test('invalid typed projection stays timeline-only', () async {
    final harness = await _Harness.create();
    addTearDown(harness.dispose);
    harness.background();
    harness.sync.deltaResult = MessageSyncOutcome(
      status: MessageSyncStatus.changed,
      eventsApplied: 1,
      pagesFetched: 1,
      committedIncomingMessages: <CommittedIncomingMessage>[
        CommittedIncomingMessage(
          eventId: 'core-invalid-1',
          logicalMessageId: 'logical-invalid-1',
          authoritativeReceivedAt: _now,
          message: _chatMessage(
            projection: const InvalidAgentMessageProjection(),
          ),
        ),
      ],
    );

    await harness.run();

    expect(harness.notifications.structuredNotificationCount, 0);
    expect(harness.notifications.systemCalls, 0);
  });
}

final class _Harness {
  _Harness._({
    required this.container,
    required this.sync,
    required this.notifications,
    required this.localStore,
    required this.conversations,
    required this.preferences,
  });

  static Future<_Harness> create({
    FakeNotificationFacade? notifications,
    FakeProductLocalStore? localStore,
    FakeMessageSyncService? messageSync,
    String activeState = 'active',
  }) async {
    final store = localStore ?? FakeProductLocalStore();
    await store.replaceAgentInventorySnapshot(
      ProductAgentInventorySnapshot(
        binding: const ProductAccountBinding(
          ownerIdentityId: 'owner-a',
          accountId: 'account-a',
        ),
        domainVersion: '1',
        refreshedAt: _now,
        agents: <ProductAgentInventoryItem>[
          ProductAgentInventoryItem(
            agentDid: _senderDid,
            activeState: activeState,
            payloadJson: '{}',
          ),
        ],
      ),
    );
    final gateway = FakeAwikiGateway();
    final sync = messageSync ?? FakeMessageSyncService();
    final facade = notifications ?? FakeNotificationFacade();
    final session = _session();
    final conversations = _BoundReadyConversationService(gateway);
    final preferences = _TestPreferencePort();
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        awikiEnvironmentConfigProvider.overrideWithValue(
          AwikiEnvironmentConfig(messageSyncV2ReadEnabled: true),
        ),
        notificationFacadeProvider.overrideWithValue(facade),
        appPresentationServiceProvider.overrideWithValue(
          const _ForegroundPresentationService(),
        ),
        deviceManagementCorePortProvider.overrideWithValue(
          FakeDeviceManagementCore(),
        ),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: sync,
          conversationService: conversations,
        ),
        productLocalStoreProvider.overrideWithValue(store),
        agentNotificationPreferencePortProvider.overrideWithValue(preferences),
        appSessionServiceProvider.overrideWithValue(
          _StaticAppSessionService(session),
        ),
        agentMessagePresentationClockProvider.overrideWithValue(() => _now),
        messageSyncCoordinatorProvider.overrideWith(
          (ref) => MessageSyncCoordinator(
            ref,
            minInterval: Duration.zero,
            failureBackoff: Duration.zero,
          ),
        ),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(session);
          return controller;
        }),
      ],
    );
    return _Harness._(
      container: container,
      sync: sync,
      notifications: facade,
      localStore: store,
      conversations: conversations,
      preferences: preferences,
    );
  }

  final ProviderContainer container;
  final FakeMessageSyncService sync;
  final FakeNotificationFacade notifications;
  final FakeProductLocalStore localStore;
  final _BoundReadyConversationService conversations;
  final _TestPreferencePort preferences;

  String get receiptLedgerJson =>
      localStore.preferences.values.map((item) => item.valueJson).join('\n');

  Future<void> enableUrgent() async {
    preferences.urgent = AgentNotificationUrgentPreference.enabled;
  }

  Future<void> claim(String eventId) => container
      .read(agentMessagePresentationStoreProvider)
      .claim(
        owner: AgentMessagePresentationOwnerScope(
          ownerIdentityId: 'owner-a',
          accountId: 'account-a',
        ),
        eventId: eventId,
        senderDid: _senderDid,
        now: _now,
      )
      .then<void>((_) {});

  void foreground() => container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.resumed);

  void background() => container
      .read(appLifecycleProvider.notifier)
      .setLifecycle(AppLifecycleState.paused);

  Future<void> run() => container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('test', immediate: true);

  Future<void> remotePush() async {
    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestRemotePushSync();
  }

  Future<void> dispose() async {
    container.dispose();
    await conversations.dispose();
  }
}

final class _TestPreferencePort implements AgentNotificationPreferencePort {
  AgentNotificationUrgentPreference urgent =
      AgentNotificationUrgentPreference.disabled;

  @override
  Future<AgentNotificationPreference> getAgentNotificationPreference() async =>
      AgentNotificationPreference(
        schema: 'awiki.agent.message.v1',
        urgent: urgent,
        updatedAt: null,
      );

  @override
  Future<AgentNotificationPreference> setAgentNotificationPreference({
    required AgentNotificationUrgentPreference urgent,
  }) async {
    this.urgent = urgent;
    return getAgentNotificationPreference();
  }
}

MessageSyncOutcome _outcome({
  required String eventId,
  required DateTime? acceptedAt,
}) => MessageSyncOutcome(
  status: MessageSyncStatus.changed,
  eventsApplied: 1,
  pagesFetched: 1,
  committedIncomingMessages: <CommittedIncomingMessage>[
    CommittedIncomingMessage(
      eventId: 'core-$eventId',
      logicalMessageId: 'logical-$eventId',
      authoritativeReceivedAt: acceptedAt,
      message: _chatMessage(
        projection: ValidAgentMessageProjection(
          AgentMessageV1(
            eventId: eventId,
            taskName: 'Production worker recovery',
            kind: AgentMessageKind.alert,
            level: AgentMessageLevel.urgent,
            summary: 'Check the production worker',
            detail: null,
            action: AgentMessageAction.openConversation,
          ),
        ),
      ),
    ),
  ],
);

ChatMessage _chatMessage({required AgentMessageProjection projection}) =>
    ChatMessage(
      localId: 'local-${projection.hashCode}',
      remoteId: 'remote-${projection.hashCode}',
      conversationId: _conversationId,
      threadId: _conversationId,
      senderDid: _senderDid,
      senderName: 'Build Agent',
      receiverDid: 'did:test:me',
      content: '',
      originalType: AgentMessageV1.schema,
      createdAt: _now,
      isMine: false,
      sendState: MessageSendState.sent,
      agentMessage: projection,
    );

SessionIdentity _session({String deviceAuthGeneration = '1'}) =>
    SessionIdentity(
      did: 'did:test:me',
      credentialName: 'owner-a',
      displayName: 'Me',
      localIdentityId: 'owner-a',
      accountBinding: SessionAccountBinding(
        ownerIdentityId: 'owner-a',
        accountId: 'account-a',
        currentDid: 'did:test:me',
        protocolDeviceId: 'device-a',
        identityGeneration: '1',
        deviceAuthGeneration: deviceAuthGeneration,
      ),
    );

final class _StaticAppSessionService implements AppSessionService {
  const _StaticAppSessionService(this.session);

  final SessionIdentity session;

  @override
  Future<AppSession?> refreshSession() async => AppSession(
    did: session.did,
    identityId: session.credentialName,
    displayName: session.displayName,
    localAlias: session.credentialName,
    authenticated: true,
    accountBinding: session.accountBinding,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ForegroundPresentationService implements AppPresentationService {
  const _ForegroundPresentationService();

  @override
  Future<AppPresentationState?> currentState() async =>
      const AppPresentationState(
        applicationActive: true,
        windowVisible: true,
        windowMiniaturized: false,
      );
}

final class _MuteFailingProductLocalStore extends FakeProductLocalStore {
  @override
  Future<ProductConversationOverlay?> loadConversationOverlayByConversationId({
    required String ownerDid,
    required String conversationId,
  }) => Future<ProductConversationOverlay?>.error(StateError('unavailable'));
}

final class _BlockingNotificationFacade extends FakeNotificationFacade {
  final Completer<void> started = Completer<void>();
  final Completer<void> _gate = Completer<void>();

  @override
  Future<StructuredNotificationEligibility>
  structuredNotificationEligibility() async {
    if (!started.isCompleted) started.complete();
    await _gate.future;
    return StructuredNotificationEligibility.allowed;
  }

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

final class _GatedMessageSyncService extends FakeMessageSyncService {
  final Completer<void> started = Completer<void>();
  final Completer<void> _gate = Completer<void>();

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    if (!started.isCompleted) started.complete();
    await _gate.future;
    return deltaResult;
  }

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

final class _BoundReadyConversationService extends FakeConversationService {
  _BoundReadyConversationService(super.gateway);

  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    scheduleMicrotask(() {
      if (_patches.isClosed) return;
      _patches.add(
        ConversationListPatch(
          kind: ConversationListPatchKind.reset,
          ownerIdentityId: 'owner-a',
          ownerDid: ownerDid,
          version: 1,
          unreadTotal: 0,
          items: gateway.conversations,
        ),
      );
    });
    return _patches.stream;
  }

  Future<void> dispose() => _patches.close();
}
