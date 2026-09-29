import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/agent_visual_status.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

const _agent = 'did:runtime';
const _route = 'core-local-route';
const _inventory = [
  AgentSummary(
    agentDid: _agent,
    kind: AgentKind.runtime,
    daemonAgentDid: 'did:daemon',
    runtime: 'opencode',
    displayName: 'Agent',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
    recentRuns: [
      AgentRunStatus(
        runId: 'a',
        messageId: 'message-a',
        runtimeAgentDid: _agent,
        status: 'running',
      ),
    ],
  ),
];
Map<String, Object?> _work(String run) => {
  'run_id': run,
  'source_message_id': 'message-$run',
  'requester_did': 'did:me',
};
Map<String, Object?> _snapshot(
  int revision, {
  String? active = 'a',
  String? waiting,
  String session = 'session',
  bool group = false,
}) => {
  'schema': 'awiki.acp.session.v1',
  'session_key': session,
  'agent_did': _agent,
  'conversation_id': 'remote-alias',
  'revision': revision,
  'group': group,
  'active': active == null ? null : _work(active),
  'waiting': waiting == null ? null : _work(waiting),
  'history': [],
  'text': 'streamed text',
  'tools': [],
  'questions': [],
};
Map<String, Object?> _task(
  String run,
  int revision, {
  String state = 'finished',
  String session = 'session',
  bool group = false,
}) => {
  'schema': 'awiki.acp.task.v1',
  'session_key': session,
  'agent_did': _agent,
  'conversation_id': 'remote-alias',
  'revision': revision,
  'group': group,
  ..._work(run),
  'state': state,
  'text': 'saved text for $run',
  'tools': [
    {'title': 'Read', 'status': 'completed'},
  ],
  'questions': [
    {
      'id': 'q',
      'status': 'answered',
      'response': {
        'action': 'accept',
        'content': {'choice': 'yes'},
      },
    },
  ],
};
ChatMessage _message(
  Map<String, Object?> payload, {
  String route = _route,
  String sender = _agent,
  bool group = false,
  MessageSendState sendState = MessageSendState.sent,
}) => ChatMessage(
  localId: 'control',
  threadId: route,
  conversationId: route,
  senderDid: sender,
  content: '',
  createdAt: DateTime.utc(2026),
  isMine: false,
  sendState: sendState,
  groupId: group ? 'group-id' : null,
  originalType: 'application/json',
  payloadJson: jsonEncode(payload),
);

class _ProjectionHarness extends AcpSessionController {
  AcpProjection get value => state;
  void session(Map<String, Object?> value) => applyConversation(
    _message({'schema': 'awiki.acp.status.v1', 'acp': value}),
    _route,
  );
  void task(Map<String, Object?> value) => applyConversation(
    _message({'schema': 'awiki.acp.status.v1', 'acp_task': value}),
    _route,
  );
  void daemon(Map<String, Object?> value) => applyDaemon(
    {
      'schema': 'awiki.agent.status.v1',
      'daemon_agent_did': 'did:daemon',
      'runs': [value],
    },
    'did:daemon',
    _inventory,
  );
}

class _ChatHarness extends ChatThreadsController {
  _ChatHarness(super.ref);
  void pending(
    List<String> runs, {
    String route = _route,
    String agent = _agent,
  }) {
    state = {
      ...state,
      route: ChatThreadState(
        threadId: route,
        agentPendingTurns: [
          for (final run in runs)
            AgentPendingTurn(
              agentDid: agent,
              localMessageId: 'local-$run',
              remoteMessageId: 'message-$run',
              startedAt: DateTime.utc(2026),
            ),
        ],
      ),
    };
  }
}

void main() {
  test(
    'rejection arriving before send acknowledgement leaves no reservation',
    () async {
      final gateway = FakeAwikiGateway()
        ..nextSentMessageId = 'message-early'
        ..sendTextMessageCompleter = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          ...fakeApplicationServiceOverrides(gateway),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me',
              displayName: 'Me',
            ),
          );
      final chat = container.read(chatThreadsProvider.notifier);
      final conversation = ConversationSummary(
        conversationId: _route,
        threadId: _route,
        targetDid: _agent,
        displayName: 'Agent',
        lastMessagePreview: '',
        lastMessageAt: DateTime.utc(2026),
        unreadCount: 0,
        isGroup: false,
      );
      final sending = chat.sendMessage(
        conversation: conversation,
        content: 'hello',
        expectedAgentReplyDid: _agent,
      );
      container
          .read(acpSessionsProvider.notifier)
          .applyConversation(
            _message({
              'schema': 'awiki.acp.status.v1',
              'acp_rejection': {
                'schema': 'awiki.acp.rejection.v1',
                'agent_did': _agent,
                'source_message_id': 'message-early',
                'reason': 'waiting_slot_full',
              },
            }),
            _route,
          );
      gateway.sendTextMessageCompleter!.complete();
      await sending;
      expect(gateway.sendTextMessageCalls, 1);
      expect(
        chat.thread(_route).messages.any((m) => m.remoteId == 'message-early'),
        isTrue,
      );
      expect(chat.thread(_route).agentPendingTurns, isEmpty);
      expect(container.read(acpSessionsProvider).rejections, hasLength(1));
    },
  );
  for (final reason in ['group_busy', 'waiting_slot_full']) {
    test('$reason settles only the rejected route, agent and message', () {
      final gateway = FakeAwikiGateway();
      final container = ProviderContainer(
        overrides: [
          ...fakeApplicationServiceOverrides(gateway),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          chatThreadsProvider.overrideWith((ref) => _ChatHarness(ref)),
        ],
      );
      addTearDown(container.dispose);
      final chat = container.read(chatThreadsProvider.notifier) as _ChatHarness;
      chat.pending(['a', 'b']);
      chat.pending(['a'], route: 'other-route');
      final projection = container.read(acpSessionsProvider.notifier);
      void reject(String agent) => projection.applyConversation(
        _message({
          'schema': 'awiki.acp.status.v1',
          'acp_rejection': {
            'schema': 'awiki.acp.rejection.v1',
            'agent_did': agent,
            'conversation_id': 'remote-alias',
            'source_message_id': 'message-a',
            'reason': reason,
          },
        }, sender: agent),
        _route,
      );
      reject('did:other-agent');
      expect(chat.thread(_route).agentPendingTurns, hasLength(2));
      reject(_agent);
      expect(
        chat.thread(_route).agentPendingTurns.single.remoteMessageId,
        'message-b',
      );
      expect(chat.thread('other-route').agentPendingTurns, hasLength(1));
      expect(
        container.read(acpSessionsProvider).rejections,
        hasLength(2),
        reason: 'Multiple mentioned agents must retain separate rejections',
      );
      reject(_agent);
      expect(chat.thread(_route).agentPendingTurns, hasLength(1));
    });
  }

  test(
    'background records converge without inventing another conversation route',
    () {
      final c = _ProjectionHarness();
      addTearDown(c.dispose);
      c.daemon({'acp': _snapshot(1)});
      expect(c.value.busyForAgent(_agent), isTrue);
      expect(c.value.sessions, isEmpty);
      c.daemon({'acp_task': _task('a', 2)});
      expect(c.value.busyForAgent(_agent), isFalse);
      expect(c.value.tasks.values.single.conversationId, isNull);
      c.session(_snapshot(1));
      expect(c.value.tasks.values.single.conversationId, _route);
      expect(c.value.forConversation(_route).single.busy, isFalse);
      c.session(
        _snapshot(3),
      ); // Even a higher snapshot cannot revive a terminal run.
      expect(c.value.busyForAgent(_agent), isFalse);
      expect(c.value.forConversation(_route).single.busy, isFalse);
      expect(c.value.tasks.values.single.text, 'saved text for a');
    },
  );

  test(
    'new work, summaries, delivery updates and replays preserve prior details',
    () {
      final c = _ProjectionHarness();
      addTearDown(c.dispose);
      c.session(_snapshot(2));
      c.task(_task('a', 3, state: 'cancelled'));
      c.session({
        ..._snapshot(4, active: 'b'),
        'history': [
          {..._work('a'), 'state': 'cancelled', 'revision': 3},
        ],
      });
      c.task(_task('a', 2, state: 'running'));
      expect(c.value.busyForAgent(_agent), isTrue);
      expect(c.value.tasks['$_agent:a']?.tools, hasLength(1));
      expect(
        c.value.tasks['$_agent:a']?.questions.single['status'],
        'answered',
      );
      c.task({
        ..._task('b', 5),
        'delivery': {'state': 'pending'},
      });
      expect(c.value.busyForAgent(_agent), isFalse);
      c.task({
        ..._task('b', 6),
        'delivery': {'state': 'failed'},
      });
      expect(c.value.tasks['$_agent:b']?.state, 'finished');
      expect(c.value.tasks['$_agent:b']?.delivery['state'], 'failed');
      expect(c.value.busyForAgent(_agent), isFalse);
      c.session({
        ..._snapshot(7, active: null),
        'history': [
          {..._work('b'), 'revision': 5, 'state': 'finished'},
        ],
      });
      expect(c.value.tasks['$_agent:b']?.text, 'saved text for b');
    },
  );

  test(
    'private control replies cannot bind history from other sessions or groups',
    () {
      final c = _ProjectionHarness();
      addTearDown(c.dispose);
      c.applyConversation(
        _message({
          'schema': 'awiki.acp.command-result.v1',
          'acp_result': {
            'sessions': [
              _snapshot(1),
              _snapshot(1, session: 'group-session', group: true),
            ],
            'task_history': {
              'tasks': [_task('g', 2, session: 'group-session', group: true)],
            },
          },
        }),
        _route,
      );
      expect(c.value.sessions, isEmpty);
      expect(c.value.tasks.values.single.conversationId, isNull);
      c.applyConversation(
        _message({
          'schema': 'awiki.acp.command-result.v1',
          'acp_result': {
            'prepared_session_key': 'session',
            'sessions': [
              _snapshot(2, active: null),
              _snapshot(1, session: 'group-session', group: true),
            ],
          },
        }),
        _route,
      );
      expect(c.value.sessions.keys, ['session']);
      expect(c.value.tasks.values.single.conversationId, isNull);
      c.applyConversation(
        _message(
          {
            'schema': 'awiki.acp.status.v1',
            'acp_task': _task('g', 2, session: 'group-session', group: true),
          },
          route: 'core-group',
          group: true,
        ),
        'core-group',
      );
      expect(c.value.tasks.values.single.conversationId, 'core-group');
    },
  );

  test(
    'uncommitted, spoofed, cross-group and cross-route updates are rejected',
    () {
      final c = _ProjectionHarness();
      addTearDown(c.dispose);
      c.session(_snapshot(1));
      final task = _task('a', 2);
      for (final message in [
        _message({
          'schema': 'awiki.acp.status.v1',
          'acp_task': task,
        }, sender: 'did:forged'),
        _message({
          'schema': 'awiki.acp.status.v1',
          'acp_task': task,
        }, sendState: MessageSendState.sending),
        _message({
          'schema': 'awiki.acp.status.v1',
          'acp_task': task,
        }, group: true),
      ]) {
        c.applyConversation(message, _route);
      }
      c.applyConversation(
        _message({
          'schema': 'awiki.acp.status.v1',
          'acp_task': task,
        }, route: 'other'),
        'other',
      );
      expect(c.value.tasks['$_agent:a']?.state, 'running');
      expect(c.value.busyForAgent(_agent), isTrue);
    },
  );

  test(
    'ACP idle overrides legacy running records but preserves a newly sent turn',
    () {
      expect(
        AgentVisualStatus.fromAgent(
          _inventory.single,
          authoritativeBusy: false,
        ).kind,
        AgentVisualStatusKind.ready,
      );
      expect(
        AgentVisualStatus.fromAgent(
          _inventory.single,
          authoritativeBusy: false,
          hasPendingTurn: true,
        ).kind,
        AgentVisualStatusKind.processing,
      );
      expect(
        AgentVisualStatus.fromAgent(_inventory.single).kind,
        AgentVisualStatusKind.processing,
      );
    },
  );

  for (final terminal in ['finished', 'cancelled', 'failed', 'interrupted']) {
    test(
      '$terminal settles only its exact pending command, including background events',
      () {
        final gateway = FakeAwikiGateway();
        final container = ProviderContainer(
          overrides: [
            ...fakeApplicationServiceOverrides(gateway),
            notificationFacadeProvider.overrideWithValue(
              FakeNotificationFacade(),
            ),
            chatThreadsProvider.overrideWith((ref) => _ChatHarness(ref)),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me',
                displayName: 'Me',
              ),
            );
        final chat =
            container.read(chatThreadsProvider.notifier) as _ChatHarness;
        chat.pending(['a', 'b']);
        final projection = container.read(acpSessionsProvider.notifier);
        void daemon(Map<String, Object?> value) => projection.applyDaemon(
          {
            'schema': 'awiki.agent.status.v1',
            'daemon_agent_did': 'did:daemon',
            'runs': [value],
          },
          'did:daemon',
          _inventory,
        );
        daemon({'acp': _snapshot(1, active: null)});
        expect(
          chat.thread(_route).agentPendingTurns,
          hasLength(2),
          reason: 'Idle cannot clear unaccepted sends',
        );
        daemon({'acp_task': _task('a', 2, state: terminal)});
        expect(
          chat.thread(_route).agentPendingTurns.single.remoteMessageId,
          'message-b',
        );
        chat.applyAgentRunStatusPayload({
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'snapshot',
          'runtimes': [
            {'agent_did': _agent},
          ],
          'runs': [],
        });
        expect(
          chat.thread(_route).agentPendingTurns.single.remoteMessageId,
          'message-b',
        );
        daemon({'acp_task': _task('b', 3)});
        expect(container.read(pendingAgentDidsProvider), isEmpty);
        daemon({'acp_task': _task('a', 1, state: 'running')});
        expect(container.read(pendingAgentDidsProvider), isEmpty);
        container
            .read(sessionProvider.notifier)
            .setSession(
              const SessionIdentity(
                did: 'did:other',
                credentialName: 'other',
                displayName: 'Other',
              ),
            );
        expect(container.read(acpSessionsProvider).tasks, isEmpty);
        expect(container.read(acpSessionsProvider).activity, isEmpty);
      },
    );
  }
}
