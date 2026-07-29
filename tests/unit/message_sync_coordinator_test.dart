import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/application/models/message_sync_diagnostics.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';
import 'devices/device_test_support.dart';

void main() {
  test('single-flight coalesces concurrent sync requests', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final firstSync = Completer<void>();
    final sync = FakeMessageSyncService()..syncNowCompleter = firstSync;
    final container = _container(gateway, sync);
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final first = coordinator.requestSync('startup', immediate: true);
    await pumpEventQueue();
    final second = coordinator.requestSync('app_resumed', immediate: true);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup']);
    expect(sync.activeSyncNowCalls, 1);
    expect(sync.maxActiveSyncNowCalls, 1);

    firstSync.complete();
    await Future.wait(<Future<void>>[first, second]);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup', 'app_resumed']);
    expect(sync.maxActiveSyncNowCalls, 1);
    expect(
      container.read(conversationListProvider).conversations,
      hasLength(1),
    );
  });

  test(
    'first sync prepares one bounded conversation seed without prewarming',
    () async {
      final conversation = _conversation();
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[conversation];
      final sync = FakeMessageSyncService();
      final container = _container(gateway, sync, syncV2ReadEnabled: true);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);

      expect(gateway.listConversationsCalls, 1);
      expect(sync.syncReasons, ['startup']);
      expect(gateway.fetchLocalDmHistoryCalls, 0);
      expect(gateway.fetchLocalGroupHistoryCalls, 0);
      expect(gateway.fetchDmHistoryCalls, 0);
      expect(container.read(conversationListProvider).conversations, [
        conversation,
      ]);
    },
  );

  test('subsequent sync does not reseed or prewarm local histories', () async {
    final conversation = _conversation();
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('startup', immediate: true);
    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('realtime_hint', immediate: true);
    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('websocket_reconnect', immediate: true);

    expect(gateway.listConversationsCalls, 1);
    expect(sync.syncReasons, [
      'startup',
      'realtime_hint',
      'websocket_reconnect',
    ]);
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchLocalGroupHistoryCalls, 0);
  });

  test('replacing a delayed sync completes all coalesced waiters', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final sync = FakeMessageSyncService();
    final container = _container(
      gateway,
      sync,
      minInterval: const Duration(milliseconds: 50),
    );
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    await coordinator.requestSync('startup', immediate: true);
    final firstDelayed = coordinator.requestSync('app_resumed');
    final secondDelayed = coordinator.requestSync('realtime_gap');

    await Future.wait(<Future<void>>[
      firstDelayed,
      secondDelayed,
    ]).timeout(const Duration(seconds: 1));

    expect(sync.syncReasons, ['startup', 'realtime_gap']);
  });

  test('sync completion after dispose is ignored', () async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[_conversation()];
    final sync = _BlockingMessageSyncService();
    final container = _container(gateway, sync);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    final request = coordinator.requestSync('startup', immediate: true);
    await pumpEventQueue();

    expect(sync.syncReasons, ['startup']);

    container.dispose();
    sync.complete();

    await request.timeout(const Duration(seconds: 1));
    await pumpEventQueue();
  });

  test(
    'same DID auth-generation change rejects stale sync completion',
    () async {
      final gateway = FakeAwikiGateway();
      final syncCompletion = Completer<void>();
      final sync = FakeMessageSyncService()..syncNowCompleter = syncCompletion;
      final devices = FakeDeviceManagementCore();
      final conversations = _BoundReadyConversationService(
        gateway,
        ownerIdentityId: 'owner-a',
      );
      final container = _container(
        gateway,
        sync,
        devices: devices,
        session: _boundSession(deviceAuthGeneration: '1'),
        conversationService: conversations,
      );
      addTearDown(container.dispose);
      addTearDown(conversations.dispose);

      final oldSync = container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);
      await pumpEventQueue();
      expect(sync.syncReasons, ['startup']);

      container
          .read(sessionProvider.notifier)
          .setSession(_boundSession(deviceAuthGeneration: '2'));
      container.read(messageSyncCoordinatorProvider.notifier).resetForSession();
      syncCompletion.complete();
      await oldSync;
      await pumpEventQueue();

      expect(devices.registryCalls, 0);
      expect(devices.joinRequestCalls, 0);
      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.idle,
      );
    },
  );

  test('successful reliable sync refreshes the verified Join inbox', () async {
    final gateway = FakeAwikiGateway();
    final sync = FakeMessageSyncService();
    final devices = FakeDeviceManagementCore()
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
    final container = _container(gateway, sync, devices: devices);
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('system_notification_changed', immediate: true);

    expect(devices.registryCalls, 1);
    expect(devices.joinRequestCalls, 1);
  });

  test('safe diagnostics refresh is typed and best-effort', () async {
    final gateway = FakeAwikiGateway();
    final successAt = DateTime.utc(2026, 7, 29, 8);
    final retryAt = DateTime.utc(2026, 7, 29, 8, 1);
    final messaging = _DiagnosticMessagingService(
      gateway,
      diagnostics: AppMessageSyncDiagnostics(
        lastSuccessAt: successAt,
        mode: AppMessageSyncMode.retryable,
        pendingMutationCount: 2,
        dirtyDomains: const <AppMessageSyncDirtyDomain>[
          AppMessageSyncDirtyDomain.messages,
          AppMessageSyncDirtyDomain.readState,
        ],
        retryState: AppMessageSyncRetryState.scheduled,
        nextRetryAt: retryAt,
      ),
    );
    final sync = FakeMessageSyncService();
    final container = _container(gateway, sync, messagingService: messaging);
    addTearDown(container.dispose);
    final coordinator = container.read(messageSyncCoordinatorProvider.notifier);

    await coordinator.requestSync('startup', immediate: true);

    var state = container.read(messageSyncCoordinatorProvider);
    expect(messaging.diagnosticsCalls, 1);
    expect(state.lastSuccessAt, successAt);
    expect(state.mode, AppMessageSyncMode.retryable);
    expect(state.pendingMutationCount, 2);
    expect(state.dirtyDomains, <AppMessageSyncDirtyDomain>[
      AppMessageSyncDirtyDomain.messages,
      AppMessageSyncDirtyDomain.readState,
    ]);
    expect(state.retryState, AppMessageSyncRetryState.scheduled);
    expect(state.nextRetryAt, retryAt);

    messaging.nextDiagnosticsError = StateError('diagnostics unavailable');
    sync.deltaResult = const MessageSyncOutcome(
      status: MessageSyncStatus.changed,
      eventsApplied: 1,
      pagesFetched: 1,
    );
    await coordinator.requestSync('realtime_hint', immediate: true);

    state = container.read(messageSyncCoordinatorProvider);
    expect(messaging.diagnosticsCalls, 2);
    expect(state.status, MessageSyncCoordinatorStatus.idle);
    expect(state.lastStatus, MessageSyncStatus.changed);
    expect(state.lastError, isNull);
    expect(state.lastSuccessAt, successAt);
    expect(state.pendingMutationCount, 2);
  });

  test(
    'v2 committed live incoming message notifies once by event and message',
    () async {
      final message = ChatMessage(
        localId: 'message-1',
        remoteId: 'message-1',
        conversationId: 'dm:peer-scope:v1:peer',
        threadId: 'dm:peer-scope:v1:peer',
        senderDid: 'did:test:peer',
        senderName: 'Peer',
        receiverDid: 'did:test:me',
        content: 'committed hello',
        createdAt: DateTime.utc(2026, 7, 28, 9),
        isMine: false,
        sendState: MessageSendState.sent,
      );
      final committed = CommittedIncomingMessage(
        eventId: 'event-1',
        logicalMessageId: 'message-1',
        message: message,
      );
      final notifications = FakeNotificationFacade();
      final sync = FakeMessageSyncService(
        deltaResult: MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
          committedIncomingMessages: <CommittedIncomingMessage>[committed],
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      await coordinator.requestSync('realtime_message', immediate: true);
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          CommittedIncomingMessage(
            eventId: 'event-2',
            logicalMessageId: 'message-1',
            message: message,
          ),
        ],
      );
      await coordinator.requestSync(
        'realtime_duplicate_message',
        immediate: true,
      );
      sync.deltaResult = MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          CommittedIncomingMessage(
            eventId: 'event-1',
            logicalMessageId: 'message-2',
            message: message,
          ),
        ],
      );
      await coordinator.requestSync(
        'realtime_duplicate_event',
        immediate: true,
      );

      expect(notifications.inAppCalls, 1);
      expect(notifications.lastInAppTitle, 'Peer');
      expect(notifications.lastInAppBody, 'committed hello');
    },
  );

  test('recovery-required outcome never synthesizes a notification', () async {
    final notifications = FakeNotificationFacade();
    final container = _container(
      FakeAwikiGateway(),
      FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.recoveryRequired,
          eventsApplied: 0,
          pagesFetched: 1,
        ),
      ),
      notifications: notifications,
      syncV2ReadEnabled: true,
    );
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('startup', immediate: true);

    expect(notifications.inAppCalls, 0);
    expect(notifications.systemCalls, 0);
  });

  test(
    'outgoing bootstrap recovery history and replay outcomes do not notify',
    () async {
      final notifications = FakeNotificationFacade();
      final sync = FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.changed,
          eventsApplied: 1,
          pagesFetched: 1,
        ),
      );
      final container = _container(
        FakeAwikiGateway(),
        sync,
        notifications: notifications,
        syncV2ReadEnabled: true,
      );
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      for (final reason in <String>[
        'outgoing',
        'bootstrap',
        'recovery',
        'history',
        'replay',
      ]) {
        await coordinator.requestSync(reason, immediate: true);
      }

      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
    },
  );

  test('failed reliable sync does not refresh the Join inbox', () async {
    final gateway = FakeAwikiGateway();
    final devices = FakeDeviceManagementCore();
    final container = _container(
      gateway,
      _FailingMessageSyncService(),
      devices: devices,
    );
    addTearDown(container.dispose);

    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync('system_notification_changed', immediate: true);

    expect(devices.registryCalls, 0);
    expect(devices.joinRequestCalls, 0);
    expect(
      container.read(messageSyncCoordinatorProvider).lastError,
      isA<StateError>(),
    );
  });
}

ProviderContainer _container(
  FakeAwikiGateway gateway,
  FakeMessageSyncService sync, {
  Duration minInterval = Duration.zero,
  FakeDeviceManagementCore? devices,
  FakeNotificationFacade? notifications,
  bool syncV2ReadEnabled = false,
  SessionIdentity? session,
  FakeMessagingService? messagingService,
  ConversationService? conversationService,
}) {
  return ProviderContainer(
    overrides: <Override>[
      awikiGatewayProvider.overrideWithValue(gateway),
      awikiEnvironmentConfigProvider.overrideWithValue(
        AwikiEnvironmentConfig(messageSyncV2ReadEnabled: syncV2ReadEnabled),
      ),
      notificationFacadeProvider.overrideWithValue(
        notifications ?? FakeNotificationFacade(),
      ),
      deviceManagementCorePortProvider.overrideWithValue(
        devices ?? FakeDeviceManagementCore(),
      ),
      ...fakeApplicationServiceOverrides(
        gateway,
        messageSyncService: sync,
        messagingService: messagingService,
        conversationService: conversationService,
      ),
      messageSyncCoordinatorProvider.overrideWith(
        (ref) => MessageSyncCoordinator(
          ref,
          minInterval: minInterval,
          failureBackoff: Duration.zero,
        ),
      ),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        controller.setSession(
          session ??
              const SessionIdentity(
                did: 'did:test:me',
                credentialName: 'default',
                displayName: 'Me',
                handle: 'me',
              ),
        );
        return controller;
      }),
    ],
  );
}

SessionIdentity _boundSession({required String deviceAuthGeneration}) {
  return SessionIdentity(
    did: 'did:test:me',
    credentialName: 'owner-a',
    displayName: 'Me',
    handle: 'me',
    accountBinding: SessionAccountBinding(
      ownerIdentityId: 'owner-a',
      accountId: 'account-a',
      currentDid: 'did:test:me',
      protocolDeviceId: 'device-a',
      identityGeneration: '1',
      deviceAuthGeneration: deviceAuthGeneration,
    ),
  );
}

ConversationSummary _conversation() {
  return ConversationSummary(
    threadId: 'dm:did:test:me:did:test:peer',
    conversationId: 'dm:did:test:me:did:test:peer',
    displayName: 'Peer',
    lastMessagePreview: 'hello',
    lastMessageAt: DateTime.utc(2026, 6, 27, 9),
    unreadCount: 0,
    isGroup: false,
    targetDid: 'did:test:peer',
  );
}

class _BlockingMessageSyncService extends FakeMessageSyncService {
  final Completer<MessageSyncOutcome> _syncCompleter =
      Completer<MessageSyncOutcome>();

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) {
    syncReasons.add(reason);
    return _syncCompleter.future;
  }

  void complete() {
    if (_syncCompleter.isCompleted) {
      return;
    }
    _syncCompleter.complete(
      const MessageSyncOutcome(
        status: MessageSyncStatus.idle,
        eventsApplied: 0,
        pagesFetched: 0,
      ),
    );
  }
}

class _DiagnosticMessagingService extends FakeMessagingService
    implements MessageSyncDiagnosticsService {
  _DiagnosticMessagingService(super.gateway, {required this.diagnostics});

  AppMessageSyncDiagnostics diagnostics;
  Object? nextDiagnosticsError;
  int diagnosticsCalls = 0;

  @override
  Future<AppMessageSyncDiagnostics> syncDiagnostics() async {
    diagnosticsCalls += 1;
    final error = nextDiagnosticsError;
    nextDiagnosticsError = null;
    if (error != null) {
      throw error;
    }
    return diagnostics;
  }
}

class _BoundReadyConversationService extends FakeConversationService {
  _BoundReadyConversationService(
    super.gateway, {
    required this.ownerIdentityId,
  });

  final String ownerIdentityId;
  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    scheduleMicrotask(() {
      if (_patches.isClosed) {
        return;
      }
      _patches.add(
        ConversationListPatch(
          kind: ConversationListPatchKind.reset,
          ownerIdentityId: ownerIdentityId,
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

class _FailingMessageSyncService extends FakeMessageSyncService {
  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) async {
    syncReasons.add(reason);
    throw StateError('sync_failed');
  }
}
