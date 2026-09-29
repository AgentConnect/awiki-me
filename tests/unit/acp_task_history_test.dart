import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_history_provider.dart';
import 'acp_runtime_test.dart' show RecordingControl, snapshot, control;

const query = (
  agentDid: 'did:agent:runtime',
  sessionKey: 'session-1',
  conversationId: 'conversation-1',
  sourcesJson: '["source-a","source-b"]',
);

class _HistoryControl extends RecordingControl {
  _HistoryControl(this.respond);
  final Future<Map<String, Object?>> Function(int page) respond;
  @override
  Future<Map<String, Object?>> send({
    required String agentDid,
    required String commandId,
    required Map<String, Object?> args,
  }) {
    requests.add({'agent': agentDid, 'command': commandId, 'args': args});
    return respond(requests.length);
  }
}

Map<String, Object?> page({
  bool more = false,
  int? cursor,
  String session = 'session-1',
}) => {
  'session_key': session,
  'task_history': {
    'tasks': [
      {'run_id': 'r'},
    ],
    'has_more': more,
    'next_cursor': cursor,
  },
};
ProviderContainer containerFor(RecordingControl service) {
  final container = ProviderContainer(
    overrides: [acpControlServiceProvider.overrideWithValue(service)],
  );
  container
      .read(acpSessionsProvider.notifier)
      .applyConversation(control(snapshot()), 'conversation-1');
  return container;
}

void main() {
  test(
    'history follows bounded cursors for exact visible source IDs',
    () async {
      final service = _HistoryControl(
        (n) async => page(more: n == 1, cursor: n == 1 ? 12 : null),
      );
      final container = containerFor(service);
      addTearDown(container.dispose);
      final subscription = container.listen(
        acpTaskHistoryProvider(query),
        (_, __) {},
      );
      addTearDown(subscription.close);
      expect(await container.read(acpTaskHistoryProvider(query).future), 2);
      expect(service.requests, hasLength(2));
      expect((service.requests[0]['args'] as Map)['source_message_ids'], [
        'source-a',
        'source-b',
      ]);
      expect((service.requests[1]['args'] as Map)['cursor'], 12);
      expect(
        service.requests[0]['command'],
        isNot(service.requests[1]['command']),
      );
    },
  );
  test(
    'foreign page and repeated cursor fail without endless retries',
    () async {
      for (final foreign in [true, false]) {
        final service = _HistoryControl(
          (n) async => page(
            more: true,
            cursor: 12,
            session: foreign ? 'foreign' : 'session-1',
          ),
        );
        final container = containerFor(service);
        final subscription = container.listen(
          acpTaskHistoryProvider(query),
          (_, __) {},
        );
        await expectLater(
          container.read(acpTaskHistoryProvider(query).future),
          throwsStateError,
        );
        expect(service.requests, hasLength(foreign ? 1 : 2));
        subscription.close();
        container.dispose();
      }
    },
  );
  test('leaving the message window stops subsequent pages', () async {
    final response = Completer<Map<String, Object?>>();
    final service = _HistoryControl((_) => response.future);
    final container = containerFor(service);
    final subscription = container.listen(
      acpTaskHistoryProvider(query),
      (_, __) {},
    );
    expect(service.requests, hasLength(1));
    subscription.close();
    container.dispose();
    response.complete(page(more: true, cursor: 10));
    await Future<void>.delayed(Duration.zero);
    expect(service.requests, hasLength(1));
  });
  test(
    'Core window queries include off-page reply sources and cap each request at 50',
    () {
      final messages = [
        for (var n = 0; n < 55; n++)
          ChatMessage(
            localId: 'local-$n',
            remoteId: 'remote-$n',
            conversationId: 'conversation-1',
            threadId: 'thread',
            senderDid: 'did:agent:runtime',
            content: '',
            createdAt: DateTime.utc(2026),
            isMine: false,
            sendState: MessageSendState.sent,
            payloadJson: n == 0
                ? jsonEncode({
                    'annotations': {
                      'awiki_reply_to_message_id': 'off-page-source',
                      'awiki_run_id': 'run',
                    },
                  })
                : null,
          ),
      ];
      final sessions = [AcpSession.parse(snapshot())!];
      expect(acpHistoryQueries(sessions, messages, {}), isEmpty);
      expect(
        acpHistoryQueries(
          [
            AcpSession.parse({...snapshot(), 'task_history_available': false})!,
          ],
          messages,
          {'did:agent:runtime'},
        ),
        isEmpty,
      );
      final queries = acpHistoryQueries(sessions, messages, {
        'did:agent:runtime',
      });
      expect(queries, hasLength(2));
      final sources = [
        for (final q in queries) ...(jsonDecode(q.sourcesJson) as List),
      ];
      expect(sources, hasLength(56));
      expect(sources, contains('off-page-source'));
      expect((jsonDecode(queries.first.sourcesJson) as List).length, 50);
    },
  );
}
