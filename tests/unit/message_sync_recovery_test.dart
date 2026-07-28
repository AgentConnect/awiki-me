import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'devices/device_test_support.dart';
import 'test_support.dart';

void main() {
  test(
    'recovery required retries the same syncNow once and stays degraded if still required',
    () async {
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[_conversation()];
      final sync = FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.recoveryRequired,
          eventsApplied: 0,
          pagesFetched: 1,
        ),
      );
      final container = _container(gateway, sync, syncV2ReadEnabled: true);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('startup', immediate: true);
      await pumpEventQueue();

      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.recoveryRequired,
      );
      expect(sync.syncReasons, <String>['startup', 'startup']);
      expect(gateway.listConversationsCalls, 0);
    },
  );

  test(
    'automatic recovery exposes recovering only while syncNow is active',
    () async {
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[_conversation()];
      final sync = _BlockingRecoveryMessageSyncService();
      final container = _container(gateway, sync, syncV2ReadEnabled: true);
      addTearDown(container.dispose);

      await container
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync('app_resumed', immediate: true);
      await pumpEventQueue();

      expect(sync.syncReasons, <String>['app_resumed', 'app_resumed']);
      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.recovering,
      );
      expect(gateway.listConversationsCalls, 0);

      sync.completeRecovery();
      await pumpEventQueue();

      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.idle,
      );
      expect(
        container.read(messageSyncCoordinatorProvider).lastStatus,
        MessageSyncStatus.changed,
      );
      expect(gateway.listConversationsCalls, 1);
    },
  );

  test(
    'auth revoked is terminal until a new session resets the fence',
    () async {
      final gateway = FakeAwikiGateway()
        ..conversations = <ConversationSummary>[_conversation()];
      final sync = FakeMessageSyncService(
        deltaResult: const MessageSyncOutcome(
          status: MessageSyncStatus.authRevoked,
          eventsApplied: 0,
          pagesFetched: 1,
          errorCode: 'device_auth_revoked',
        ),
      );
      final container = _container(gateway, sync);
      addTearDown(container.dispose);
      final coordinator = container.read(
        messageSyncCoordinatorProvider.notifier,
      );

      await coordinator.requestSync('startup', immediate: true);
      await coordinator.requestSync('foreground_catch_up', immediate: true);

      expect(sync.syncReasons, <String>['startup']);
      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.authRevoked,
      );
      expect(gateway.listConversationsCalls, 0);

      coordinator.resetForSession();

      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.idle,
      );
    },
  );

  test(
    'old session completion cannot refresh the replacement session',
    () async {
      final notifications = FakeNotificationFacade();
      final sync = _SessionSwitchMessageSyncService();
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

      final oldRequest = coordinator.requestSync('startup', immediate: true);
      await pumpEventQueue();
      container
          .read(sessionProvider.notifier)
          .setSession(
            _boundSession(owner: 'owner-new', account: 'account-new'),
          );
      coordinator.resetForSession();
      final newRequest = coordinator.requestSync('startup', immediate: true);

      sync.completeOldSession();
      await Future.wait(<Future<void>>[oldRequest, newRequest]);
      await pumpEventQueue();

      expect(sync.syncReasons, <String>['startup', 'startup']);
      expect(notifications.inAppCalls, 0);
      expect(notifications.systemCalls, 0);
      expect(
        container.read(messageSyncCoordinatorProvider).status,
        MessageSyncCoordinatorStatus.idle,
      );
    },
  );
}

ProviderContainer _container(
  FakeAwikiGateway gateway,
  FakeMessageSyncService sync, {
  FakeNotificationFacade? notifications,
  bool syncV2ReadEnabled = false,
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
        FakeDeviceManagementCore(),
      ),
      ...fakeApplicationServiceOverrides(gateway, messageSyncService: sync),
      messageSyncCoordinatorProvider.overrideWith(
        (ref) => MessageSyncCoordinator(
          ref,
          minInterval: Duration.zero,
          failureBackoff: Duration.zero,
        ),
      ),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        controller.setSession(
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

class _BlockingRecoveryMessageSyncService extends FakeMessageSyncService {
  final Completer<MessageSyncOutcome> _recoveryCompleter =
      Completer<MessageSyncOutcome>();
  var _calls = 0;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) {
    syncReasons.add(reason);
    _calls += 1;
    if (_calls == 1) {
      return Future<MessageSyncOutcome>.value(
        const MessageSyncOutcome(
          status: MessageSyncStatus.recoveryRequired,
          eventsApplied: 0,
          pagesFetched: 1,
        ),
      );
    }
    return _recoveryCompleter.future;
  }

  void completeRecovery() {
    _recoveryCompleter.complete(
      const MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 3,
        pagesFetched: 2,
      ),
    );
  }
}

class _SessionSwitchMessageSyncService extends FakeMessageSyncService {
  final Completer<MessageSyncOutcome> _oldSession =
      Completer<MessageSyncOutcome>();
  var _calls = 0;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) {
    syncReasons.add(reason);
    _calls += 1;
    if (_calls == 1) {
      return _oldSession.future;
    }
    return Future<MessageSyncOutcome>.value(
      const MessageSyncOutcome(
        status: MessageSyncStatus.idle,
        eventsApplied: 0,
        pagesFetched: 1,
      ),
    );
  }

  void completeOldSession() {
    final message = ChatMessage(
      localId: 'old-message',
      remoteId: 'old-message',
      conversationId: 'dm:old',
      threadId: 'dm:old',
      senderDid: 'did:test:old-peer',
      receiverDid: 'did:test:me',
      content: 'must stay fenced',
      createdAt: DateTime.utc(2026, 7, 28),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    _oldSession.complete(
      MessageSyncOutcome(
        status: MessageSyncStatus.changed,
        eventsApplied: 1,
        pagesFetched: 1,
        committedIncomingMessages: <CommittedIncomingMessage>[
          CommittedIncomingMessage(
            eventId: 'old-event',
            logicalMessageId: 'old-message',
            message: message,
          ),
        ],
      ),
    );
  }
}

SessionIdentity _boundSession({
  required String owner,
  required String account,
}) {
  return SessionIdentity(
    did: 'did:test:$owner',
    credentialName: owner,
    displayName: owner,
    accountBinding: SessionAccountBinding(
      ownerIdentityId: owner,
      accountId: account,
      currentDid: 'did:test:$owner',
      protocolDeviceId: 'device-$owner',
      identityGeneration: '1',
      deviceAuthGeneration: '1',
    ),
  );
}
