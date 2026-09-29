import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/application/agent/acp_control_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/thread_message_patch.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'test_support.dart';

class _AcpSessionHarness extends AcpSessionController {
  AcpProjection get projection => state;
}

Map<String, Object?> snapshot({int revision = 1, bool group = false}) => {
  'schema': 'awiki.acp.session.v1',
  'session_key': 'session-1',
  'agent_did': 'did:agent:runtime',
  'conversation_id': 'conversation-1',
  'revision': revision,
  'task_history_available': true,
  'group': group,
  'active': {
    'run_id': 'a',
    'source_message_id': 'message-a',
    'requester_did': 'did:alice',
  },
  'waiting': {
    'run_id': 'b',
    'source_message_id': 'message-b',
    'requester_did': 'did:alice',
  },
  'questions': [],
  'history': [],
  'text': 'partial',
};
ChatMessage control(
  Map<String, Object?> value, {
  String sender = 'did:agent:runtime',
  String conversation = 'conversation-1',
}) => ChatMessage(
  localId: 'control',
  remoteId: 'control',
  threadId: 'thread-1',
  conversationId: conversation,
  senderDid: sender,
  content: '',
  createdAt: DateTime.utc(2026),
  isMine: false,
  sendState: MessageSendState.sent,
  originalType: 'application/json',
  payloadJson: jsonEncode({'schema': 'awiki.acp.status.v1', 'acp': value}),
);

class RecordingControl implements AcpControlService {
  final List<Map<String, Object?>> requests = [];
  Completer<Map<String, Object?>>? completion;
  void Function(Map<String, Object?>)? onModelConfirmed;
  @override
  MessagingService get messages => throw UnimplementedError();
  @override
  void Function(ChatMessage)? get onCommittedResponse => null;
  @override
  Future<Map<String, Object?>> send({
    required String agentDid,
    required String commandId,
    required Map<String, Object?> args,
  }) {
    requests.add({'agent': agentDid, 'command': commandId, 'args': args});
    if (completion != null) return completion!.future;
    if (args['action'] == 'set_model') {
      final confirmed = {
        ...snapshot(revision: (args['revision'] as int) + 1),
        'active': null,
        'waiting': null,
        'model_id': args['model_id'],
      };
      onModelConfirmed?.call(confirmed);
      return Future.value({
        'prepared_session_key': 'session-1',
        'sessions': [confirmed],
      });
    }
    return Future.value({});
  }
}

void main() {
  test(
    'ACP committed stream follows the canonical conversation across device-specific aliases',
    () async {
      final messages = _CanonicalAcpMessages();
      final container = ProviderContainer(
        overrides: [messagingServiceProvider.overrideWithValue(messages)],
      );
      addTearDown(container.dispose);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:alice',
              credentialName: 'alice',
              displayName: 'Alice',
            ),
          );
      final provider = acpConversationProjectionProvider((
        conversationId: 'canonical-conversation',
        threadId: 'device-specific-alias',
      ));
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);
      await container.read(provider.future);
      expect(
        container.read(acpSessionsProvider).sessions['session-1']?.revision,
        1,
      );
      expect(messages.requested, ['canonical-conversation']);
    },
  );
  test('all seven brands use ACP while product IDs stay stable', () {
    expect(
      RuntimeAgentKind.values.where((k) => k.isAcp).map((k) => k.runtime),
      [
        'hermes',
        'codex',
        'claude-code',
        'opencode',
        'gemini',
        'kimi',
        'deepseek-harness',
      ],
    );
    expect(RuntimeAgentKind.hermes.driverId, 'hermes');
    expect(RuntimeAgentKind.codex.runtime, 'codex');
    expect(RuntimeAgentKind.claudeCode.runtime, 'claude-code');
  });
  test(
    'committed revisions converge and forged sender or conversation is ignored',
    () {
      final controller = _AcpSessionHarness();
      addTearDown(controller.dispose);
      controller.applyConversation(
        control(snapshot(revision: 4)),
        'conversation-1',
      );
      controller.applyConversation(
        control(snapshot(revision: 2)),
        'conversation-1',
      );
      controller.applyConversation(
        control(snapshot(revision: 5), sender: 'did:forged'),
        'conversation-1',
      );
      controller.applyConversation(
        control(snapshot(revision: 6), conversation: 'another-conversation'),
        'conversation-1',
      );
      expect(controller.projection.sessions['session-1']?.revision, 4);
    },
  );
  test(
    'Core committed route maps the daemon alias without moving an existing session',
    () {
      final controller = _AcpSessionHarness();
      addTearDown(controller.dispose);
      final value = {...snapshot(), 'conversation_id': 'direct:did:alice'};
      controller.applyConversation(
        control(value, conversation: 'dm:peer-scope:v1:agent'),
        'dm:peer-scope:v1:agent',
      );
      expect(
        controller.projection.sessions['session-1']?.conversationId,
        'dm:peer-scope:v1:agent',
      );
      expect(
        controller.projection.sessions['session-1']?.data['conversation_id'],
        'direct:did:alice',
      );
      controller.applyConversation(
        control({
          ...value,
          'revision': 2,
        }, conversation: 'dm:peer-scope:v1:other'),
        'dm:peer-scope:v1:other',
      );
      expect(controller.projection.sessions['session-1']?.revision, 1);
      controller.applyConversation(
        control({...value, 'revision': 3, 'group': true}),
        'conversation-1',
      );
      expect(controller.projection.sessions['session-1']?.revision, 1);
    },
  );
  test('daemon snapshot requires the runtime binding from inventory', () {
    final controller = _AcpSessionHarness();
    addTearDown(controller.dispose);
    final inventory = [
      AgentSummary.fromJson({
        'agent_did': 'did:agent:runtime',
        'agent_kind': 'runtime',
        'daemon_agent_did': 'did:daemon',
        'display_name': 'Agent',
        'status': {'status': 'ready'},
      }),
    ];
    final payload = {
      'schema': 'awiki.agent.status.v1',
      'daemon_agent_did': 'did:forged',
      'acp_result': {
        'sessions': [snapshot()],
      },
    };
    controller.applyDaemon(payload, 'did:forged', inventory);
    expect(controller.projection.sessions, isEmpty);
    payload['daemon_agent_did'] = 'did:daemon';
    controller.applyDaemon(payload, 'did:daemon', inventory);
    expect(
      controller.projection.sessions,
      isEmpty,
      reason: 'Daemon channel cannot invent the runtime display route',
    );
    controller.applyConversation(
      control(snapshot(), conversation: 'dm:peer-scope:v1:agent'),
      'dm:peer-scope:v1:agent',
    );
    payload['acp_result'] = {
      'sessions': [snapshot(revision: 2)],
    };
    controller.applyDaemon(payload, 'did:daemon', inventory);
    expect(controller.projection.sessions['session-1']?.revision, 2);
    expect(
      controller.projection.sessions['session-1']?.conversationId,
      'dm:peer-scope:v1:agent',
    );
  });
  test(
    'identity epoch change clears all projected task and question state',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final subscription = container.listen(acpSessionsProvider, (_, __) {});
      addTearDown(subscription.close);
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:alice',
              credentialName: 'alice',
              displayName: 'Alice',
            ),
          );
      container
          .read(acpSessionsProvider.notifier)
          .applyConversation(control(snapshot()), 'conversation-1');
      expect(container.read(acpSessionsProvider).sessions, hasLength(1));
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:bob',
              credentialName: 'bob',
              displayName: 'Bob',
            ),
          );
      expect(container.read(acpSessionsProvider).sessions, isEmpty);
    },
  );
  test(
    'private waiting full blocks input, while ordinary group text continues',
    () {
      final session = AcpSession.parse(snapshot())!;
      expect(
        acpSendBlock(
          session: session,
          daemonOffline: false,
          group: false,
          invokesAgent: true,
        ),
        AcpSendBlock.waitingFull,
      );
      expect(
        acpSendBlock(
          session: session,
          daemonOffline: false,
          group: true,
          invokesAgent: true,
        ),
        AcpSendBlock.groupBusy,
      );
      expect(
        acpSendBlock(
          session: session,
          daemonOffline: true,
          group: true,
          invokesAgent: false,
        ),
        isNull,
      );
      expect(
        acpSendBlock(
          session: null,
          daemonOffline: true,
          group: false,
          invokesAgent: true,
        ),
        AcpSendBlock.offline,
      );
    },
  );
  test(
    'task controls bind exact message identity and history preserves cancellation',
    () {
      final data = snapshot()
        ..['history'] = [
          {
            'run_id': 'old',
            'source_message_id': 'old-message',
            'state': 'cancelled',
          },
        ];
      final session = AcpSession.parse(data)!;
      expect(session.taskFor({'message-b'})?['state'], 'waiting');
      expect(session.taskFor({'old-message'})?['state'], 'cancelled');
      expect(session.taskFor({'unrelated'}), isNull);
      expect(acpCommandArgs(session, 'stop', values: {'run_id': 'a'}), {
        'session_key': 'session-1',
        'revision': 1,
        'action': 'stop',
        'run_id': 'a',
      });
    },
  );

  testWidgets(
    'private messages show stop and waiting controls, group messages omit them',
    (tester) async {
      for (final group in [false, true]) {
        final session = AcpSession.parse(snapshot(group: group))!;
        await tester.pumpWidget(
          ProviderScope(
            child: CupertinoApp(
              home: CupertinoPageScaffold(
                child: Column(
                  children: [
                    AcpTaskStatus(
                      session: session,
                      task: session.taskFor({'message-a'})!,
                      viewerDid: 'did:alice',
                      alignEnd: true,
                    ),
                    AcpTaskStatus(
                      session: session,
                      task: session.taskFor({'message-b'})!,
                      viewerDid: 'did:alice',
                      alignEnd: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('Stop'), group ? findsNothing : findsOneWidget);
        expect(find.text('Run'), group ? findsNothing : findsOneWidget);
        expect(find.text('Cancel'), group ? findsNothing : findsOneWidget);
      }
    },
  );

  testWidgets(
    'lost context reset requires confirmation and cancellation sends nothing',
    (tester) async {
      final service = RecordingControl();
      final session = AcpSession.parse({
        ...snapshot(),
        'active': <String, Object?>{},
        'waiting': <String, Object?>{},
        'context_lost': true,
      })!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acpControlServiceProvider.overrideWithValue(service)],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: AcpSessionOptions(session: session),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start again'));
      await tester.pumpAndSettle();
      expect(service.requests, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.requests, isEmpty);
      await tester.tap(find.text('Start again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(service.requests, hasLength(1));
      expect(acpMap(service.requests.single['args']), {
        'session_key': 'session-1',
        'revision': 1,
        'action': 'reset_context',
        'confirmed': true,
      });
    },
  );

  testWidgets(
    'model sheet row accepts taps across the row and submits the exact model',
    (tester) async {
      final service = RecordingControl();
      final session = AcpSession.parse({
        ...snapshot(),
        'active': <String, Object?>{},
        'waiting': <String, Object?>{},
        'models': [
          {'id': 'deepseek-flash', 'name': 'Flash'},
        ],
      })!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acpControlServiceProvider.overrideWithValue(service)],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: AcpSessionOptions(session: session),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AcpSessionOptions)),
      );
      service.onModelConfirmed = (value) => container
          .read(acpSessionsProvider.notifier)
          .applyConversation(control(value), 'conversation-1');
      await tester.tap(find.byKey(const Key('acp-model-menu')));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('acp-model:deepseek-flash'));
      final bounds = tester.getRect(row);
      await tester.tapAt(Offset(bounds.right - 16, bounds.center.dy));
      await tester.pumpAndSettle();
      expect(service.requests, hasLength(1));
      expect(acpMap(service.requests.single['args']), {
        'session_key': 'session-1',
        'revision': 1,
        'action': 'set_model',
        'model_id': 'deepseek-flash',
      });
      expect(find.byKey(const Key('acp-model-picker')), findsNothing);
    },
  );

  testWidgets(
    'question has no default submission and sends the actual entered answer without draft access',
    (tester) async {
      final service = RecordingControl()
        ..completion = Completer<Map<String, Object?>>();
      final session = AcpSession.parse(snapshot())!;
      final question = {
        'id': 'q1',
        'run_id': 'a',
        'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 60000,
        'request': {
          'message': 'Your name?',
          'requestedSchema': {
            'type': 'object',
            'required': ['name'],
            'properties': {
              'name': {'type': 'string'},
            },
          },
        },
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acpControlServiceProvider.overrideWithValue(service)],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: AcpQuestionForm(
                session: session,
                question: question,
                canAnswer: true,
              ),
            ),
          ),
        ),
      );
      expect(service.requests, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('acp-field:name')),
        'Alice',
      );
      await tester.pump();
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(service.requests, hasLength(1));
      final args = acpMap(service.requests.single['args']);
      expect(args['question_id'], 'q1');
      expect(args['response'], {
        'action': 'accept',
        'content': {'name': 'Alice'},
      });
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      service.completion!.complete({});
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('expired or other-requester questions cannot be submitted', (
    tester,
  ) async {
    final service = RecordingControl();
    final session = AcpSession.parse(snapshot(group: true))!;
    for (final expired in [false, true]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acpControlServiceProvider.overrideWithValue(service)],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: AcpQuestionForm(
                key: ValueKey(expired),
                session: session,
                canAnswer: expired,
                question: {
                  'id': 'q',
                  'run_id': 'a',
                  'expires_at_ms':
                      DateTime.now().millisecondsSinceEpoch +
                      (expired ? -10 : 60000),
                  'request': const {
                    'message': 'Answer?',
                    'requestedSchema': {'type': 'object', 'properties': {}},
                  },
                },
              ),
            ),
          ),
        ),
      );
      final buttons = tester.widgetList<CupertinoButton>(
        find.byType(CupertinoButton),
      );
      expect(buttons.every((b) => b.onPressed == null), isTrue);
      expect(service.requests, isEmpty);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

class _CanonicalAcpMessages extends FakeMessagingService
    implements CommittedControlMessagingService {
  _CanonicalAcpMessages() : super(FakeAwikiGateway());
  final requested = <String>[];
  ThreadMessagePatch patch(AppThreadRef thread) => ThreadMessagePatch(
    kind: ThreadMessagePatchKind.reset,
    ownerDid: 'did:alice',
    version: 1,
    threadKind: 'direct',
    threadId: thread.stableId,
    conversationId: 'canonical-conversation',
    messages: thread.stableId == 'canonical-conversation'
        ? [control(snapshot(), conversation: 'canonical-conversation')]
        : [],
  );
  @override
  Stream<ThreadMessagePatch> watchControlThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  }) {
    requested.add(thread.stableId);
    return Stream.value(patch(thread));
  }

  @override
  Future<ThreadMessagePatch> repairControlThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) async => patch(thread);
}
