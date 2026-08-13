import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/agent/agent_control_status_store.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/agent_control_projection_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  const daemonDid = 'did:agent:daemon';
  const runtimeDid = 'did:agent:runtime';
  final conversation = ConversationSummary(
    conversationId: 'dm:runtime',
    threadId: 'dm:me:runtime',
    displayName: 'Runtime',
    lastMessagePreview: '',
    lastMessageAt: DateTime.utc(2026, 8, 13),
    unreadCount: 0,
    isGroup: false,
    targetDid: runtimeDid,
  );

  test(
    'committed running status advances a pending turn without realtime',
    () async {
      final gateway = FakeAwikiGateway();
      final events = _ControlEventStore();
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: daemonDid,
            kind: AgentKind.daemon,
            displayName: 'Daemon',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: runtimeDid,
            kind: AgentKind.runtime,
            daemonAgentDid: daemonDid,
            displayName: 'Runtime',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          ...fakeApplicationServiceOverrides(
            gateway,
            agentControlService: control,
          ),
          agentControlStatusStoreProvider.overrideWithValue(events),
          sessionProvider.overrideWith((ref) {
            return SessionController()..setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me.json',
                displayName: 'Me',
                handle: 'me',
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(events.close);

      final projectionSubscription = container.listen(
        agentControlProjectionCoordinatorProvider,
        (_, __) {},
      );
      addTearDown(projectionSubscription.close);
      await container.read(agentsProvider.notifier).load();
      await container
          .read(chatThreadsProvider.notifier)
          .sendMessage(
            conversation: conversation,
            content: 'work',
            expectedAgentReplyDid: runtimeDid,
          );
      var thread = container.read(
        chatThreadProvider(conversation.conversationId),
      );
      expect(thread.agentPendingTurns, hasLength(1));
      expect(
        thread.agentPendingTurns.single.hasAuthoritativeRunStatus,
        isFalse,
      );
      final sourceMessageId = thread.agentPendingTurns.single.remoteMessageId!;

      events.emit(
        AgentControlEvent(
          messageId: 'status-running-message',
          daemonAgentDid: daemonDid,
          isReplay: false,
          payload: _runPayload(
            eventId: 'event-running',
            sourceMessageId: sourceMessageId,
            status: 'running',
          ),
        ),
      );
      await pumpEventQueue();

      thread = container.read(chatThreadProvider(conversation.conversationId));
      expect(thread.agentPendingTurns, hasLength(1));
      expect(thread.agentPendingTurns.single.hasAuthoritativeRunStatus, isTrue);

      events.emit(
        AgentControlEvent(
          messageId: 'status-finished-message',
          daemonAgentDid: daemonDid,
          isReplay: false,
          payload: _runPayload(
            eventId: 'event-finished',
            sourceMessageId: sourceMessageId,
            status: 'finished',
          ),
        ),
      );
      await pumpEventQueue();

      expect(
        container
            .read(chatThreadProvider(conversation.conversationId))
            .agentPendingTurns,
        isEmpty,
      );
    },
  );

  test(
    'realtime acceleration and committed replay project one event once',
    () async {
      final gateway = FakeAwikiGateway();
      final events = _ControlEventStore();
      final control = FakeAgentControlService()
        ..agents = const <AgentSummary>[
          AgentSummary(
            agentDid: daemonDid,
            kind: AgentKind.daemon,
            displayName: 'Daemon',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ];
      final container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          ...fakeApplicationServiceOverrides(
            gateway,
            agentControlService: control,
          ),
          agentControlStatusStoreProvider.overrideWithValue(events),
          sessionProvider.overrideWith((ref) {
            return SessionController()..setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me.json',
                displayName: 'Me',
                handle: 'me',
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(events.close);

      final projectionSubscription = container.listen(
        agentControlProjectionCoordinatorProvider,
        (_, __) {},
      );
      addTearDown(projectionSubscription.close);
      final coordinator = container.read(
        agentControlProjectionCoordinatorProvider.notifier,
      );
      await container.read(agentsProvider.notifier).load();
      const payload = <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'event_id': 'event-daemon-ready',
        'status_scope': 'daemon',
        'daemon_agent_did': daemonDid,
        'daemon': <String, Object?>{'agent_did': daemonDid, 'status': 'ready'},
      };

      coordinator.applyRealtimePayload(payload);
      events.emit(
        const AgentControlEvent(
          messageId: 'status-daemon-ready',
          daemonAgentDid: daemonDid,
          payload: payload,
          isReplay: false,
        ),
      );
      await pumpEventQueue();

      expect(
        container.read(agentsProvider).seenControlEventIds,
        contains('event-daemon-ready'),
        reason: 'committed topology projection must still run after realtime',
      );
    },
  );

  test('committed Personal Agent action converges without realtime', () async {
    final gateway = FakeAwikiGateway();
    final events = _ControlEventStore();
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          displayName: 'Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: runtimeDid,
          kind: AgentKind.runtime,
          daemonAgentDid: daemonDid,
          runtime: 'hermes',
          displayName: 'Hermes Personal Agent',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
        ...fakeApplicationServiceOverrides(
          gateway,
          agentControlService: control,
        ),
        agentControlStatusStoreProvider.overrideWithValue(events),
        sessionProvider.overrideWith((ref) {
          return SessionController()..setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);
    final projectionSubscription = container.listen(
      agentControlProjectionCoordinatorProvider,
      (_, __) {},
    );
    addTearDown(projectionSubscription.close);
    await container.read(agentsProvider.notifier).load();

    events.emit(
      const AgentControlEvent(
        messageId: 'action-message',
        daemonAgentDid: daemonDid,
        isReplay: false,
        payload: <String, Object?>{
          'schema': AgentControlPayloads.appActionSchema,
          'action_id': 'action-draft',
          'action': 'message.create_draft',
          'state': 'requires_confirmation',
          'daemon_agent_did': daemonDid,
          'runtime_agent_did': runtimeDid,
          'source_message_id': 'source-message',
          'conversation_id': 'dm:runtime',
          'requires_confirmation': true,
          'args': <String, Object?>{'draft_text': 'Draft reply'},
        },
      ),
    );
    await pumpEventQueue();

    final action = container
        .read(chatThreadProvider('dm:runtime'))
        .appActionRecords['action-draft'];
    expect(action, isNotNull);
    expect(action?.state, 'requires_confirmation');
    expect(action?.request?.args['draft_text'], 'Draft reply');
    expect(
      container.read(agentsProvider).seenControlEventIds,
      isNot(contains('action-message')),
    );
  });

  test('completed committed stream retries and replays local status', () async {
    final gateway = FakeAwikiGateway();
    final events = _RestartingControlEventStore();
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          displayName: 'Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'offline'),
        ),
      ];
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
        ...fakeApplicationServiceOverrides(
          gateway,
          agentControlService: control,
        ),
        agentControlStatusStoreProvider.overrideWithValue(events),
        sessionProvider.overrideWith((ref) {
          return SessionController()..setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);
    final projectionSubscription = container.listen(
      agentControlProjectionCoordinatorProvider,
      (_, __) {},
    );
    addTearDown(projectionSubscription.close);

    await container.read(agentsProvider.notifier).load();
    expect(events.watchCount, 1);
    events.latestPayload = const <String, Object?>{
      'schema': AgentControlPayloads.statusSchema,
      'event_id': 'event-ready-after-restart',
      'status_scope': 'snapshot',
      'daemon_agent_did': daemonDid,
      'daemon': <String, Object?>{'agent_did': daemonDid, 'status': 'ready'},
    };

    await events.closeCurrent();
    await _waitUntil(() => events.watchCount >= 2);
    await pumpEventQueue();

    expect(container.read(agentsProvider).agents.single.latest.status, 'ready');
    expect(
      container.read(agentsProvider).seenControlEventIds,
      contains('event-ready-after-restart'),
    );
  });

  test('queued committed event cannot cross the session epoch fence', () async {
    final gateway = FakeAwikiGateway();
    final events = _ControlEventStore();
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: daemonDid,
          kind: AgentKind.daemon,
          displayName: 'Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'offline'),
        ),
      ];
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
        ...fakeApplicationServiceOverrides(
          gateway,
          agentControlService: control,
        ),
        agentControlStatusStoreProvider.overrideWithValue(events),
        sessionProvider.overrideWith((ref) {
          return SessionController()..setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(events.close);
    final projectionSubscription = container.listen(
      agentControlProjectionCoordinatorProvider,
      (_, __) {},
    );
    addTearDown(projectionSubscription.close);
    await container.read(agentsProvider.notifier).load();

    events.emit(
      const AgentControlEvent(
        messageId: 'stale-status-message',
        daemonAgentDid: daemonDid,
        isReplay: false,
        payload: <String, Object?>{
          'schema': AgentControlPayloads.statusSchema,
          'event_id': 'event-from-old-session',
          'status_scope': 'snapshot',
          'daemon_agent_did': daemonDid,
          'daemon': <String, Object?>{
            'agent_did': daemonDid,
            'status': 'ready',
          },
        },
      ),
    );
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:other',
            credentialName: 'other.json',
            displayName: 'Other',
            handle: 'other',
          ),
        );
    await pumpEventQueue();

    expect(
      container.read(agentsProvider).seenControlEventIds,
      isNot(contains('event-from-old-session')),
    );
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for coordinator condition.');
}

Map<String, Object?> _runPayload({
  required String eventId,
  required String sourceMessageId,
  required String status,
}) {
  return <String, Object?>{
    'schema': AgentControlPayloads.statusSchema,
    'event_id': eventId,
    'status_scope': 'run',
    'daemon_agent_did': 'did:agent:daemon',
    'conversation_id': 'dm:runtime',
    'state': status,
    'runs': <Object?>[
      <String, Object?>{
        'run_id': 'run:$sourceMessageId',
        'runtime_agent_did': 'did:agent:runtime',
        'source_message_id': sourceMessageId,
        'conversation_id': 'dm:runtime',
        'status': status,
      },
    ],
  };
}

class _ControlEventStore
    implements AgentControlStatusStore, AgentControlEventStore {
  final StreamController<AgentControlEvent> _events =
      StreamController<AgentControlEvent>.broadcast();

  void emit(AgentControlEvent event) => _events.add(event);

  Future<void> close() => _events.close();

  @override
  Stream<AgentControlEvent> watchDaemonControlEvents({
    required String daemonAgentDid,
  }) {
    return _events.stream.where(
      (event) => event.daemonAgentDid == daemonAgentDid,
    );
  }

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async => null;

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) async => null;

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async => null;
}

class _RestartingControlEventStore
    implements AgentControlStatusStore, AgentControlEventStore {
  final List<StreamController<AgentControlEvent>> _streams =
      <StreamController<AgentControlEvent>>[];

  Map<String, Object?>? latestPayload;
  int watchCount = 0;

  Future<void> closeCurrent() async {
    if (_streams.isNotEmpty && !_streams.last.isClosed) {
      await _streams.last.close();
    }
  }

  Future<void> close() async {
    for (final stream in _streams) {
      if (!stream.isClosed) {
        await stream.close();
      }
    }
  }

  @override
  Stream<AgentControlEvent> watchDaemonControlEvents({
    required String daemonAgentDid,
  }) {
    watchCount += 1;
    final stream = StreamController<AgentControlEvent>();
    _streams.add(stream);
    return stream.stream;
  }

  @override
  Future<Map<String, Object?>?> findLatestDaemonStatusPayload({
    required String daemonAgentDid,
  }) async => latestPayload;

  @override
  Future<Map<String, Object?>?> findDaemonStatusPayload({
    required String daemonAgentDid,
    required String requestId,
  }) async => null;

  @override
  Future<Map<String, Object?>?> findStatusPayload({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String requestId,
    required String statusScope,
  }) async => null;
}
