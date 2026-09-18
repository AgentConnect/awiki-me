import 'dart:async';
import 'dart:convert';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/application/product_local_store.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/presentation/agents/acp_question_controller.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'acp_runtime_test.dart' show RecordingControl, snapshot;
import 'test_support.dart' show buildLocalizedTestApp;

Map<String, Object?> question({bool shared = true}) => {
  'id': 'q',
  'run_id': 'a',
  'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 60000,
  'interaction_version': 2,
  'source': shared ? 'awiki_mcp' : 'acp_elicitation',
  'definition_hash': 'hash',
  'can_custom_answer': shared,
  'can_additional_text': shared,
  'can_cancel_question': !shared,
  'request': {
    'message': 'Choose a route',
    'requestedSchema': {
      'type': 'object',
      'required': ['route'],
      'properties': {
        'route': {
          'type': 'string',
          'oneOf': [
            {'const': 'a', 'title': 'Route A'},
            {'const': 'b', 'title': 'Route B'},
          ],
        },
      },
    },
  },
};
Widget surface(RecordingControl service, Map<String, Object?> q) =>
    ProviderScope(
      overrides: [acpControlServiceProvider.overrideWithValue(service)],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: AcpQuestionForm(
              session: AcpSession.parse(snapshot())!,
              question: q,
              canAnswer: true,
            ),
          ),
        ),
      ),
    );
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets(
    'agent regex patterns are submitted without running on the UI isolate',
    (tester) async {
      final service = RecordingControl();
      final q = question(shared: false);
      q['request'] = {
        'message': 'Enter a value',
        'requestedSchema': {
          'type': 'object',
          'required': ['value'],
          'properties': {
            'value': {'type': 'string', 'pattern': r'^(a+)+$'},
          },
        },
      };
      await tester.pumpWidget(surface(service, q));
      // Kept short so this regression fails safely if local matching returns.
      final input = '${'a' * 18}!';
      await tester.enterText(find.byType(CupertinoTextField), input);
      await tap(tester, find.text('Submit answer'));
      expect(service.requests, hasLength(1));
      final response = acpMap(
        acpMap(service.requests.single['args'])['response'],
      );
      expect(response['content'], {'value': input});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'daemon format rejection keeps text editable and allows a corrected answer',
    (tester) async {
      final service = RecordingControl()..completion = Completer();
      final q = question(shared: false);
      q['request'] = {
        'message': 'Use uppercase letters',
        'requestedSchema': {
          'type': 'object',
          'required': ['code'],
          'properties': {
            'code': {'type': 'string', 'pattern': r'^[A-Z]+$'},
          },
        },
      };
      await tester.pumpWidget(surface(service, q));
      await tester.enterText(find.byType(CupertinoTextField), 'abc');
      await tap(tester, find.text('Submit answer'));
      expect(service.requests, hasLength(1));
      service.completion!.completeError(StateError('answer_pattern_mismatch'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The answer does not meet the requirements.'),
        findsOneWidget,
      );
      final field = tester.widget<CupertinoTextField>(
        find.byType(CupertinoTextField),
      );
      expect(field.controller!.text, 'abc');
      expect(field.enabled, isNot(false));
      service.completion = null;
      await tester.enterText(find.byType(CupertinoTextField), 'ABC');
      await tap(tester, find.text('Submit answer'));
      expect(service.requests, hasLength(2));
      expect(
        service.requests[0]['command'],
        isNot(service.requests[1]['command']),
      );
      expect(
        acpMap(acpMap(service.requests.last['args'])['response'])['content'],
        {'code': 'ABC'},
      );
      expect(
        find.text('Answer received. Waiting for the agent.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'accepted answer history expands with actual labels and supplement after interruption',
    (tester) async {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: CupertinoPageScaffold(
            child: AcpQuestionHistory(
              question: {
                ...question(),
                'status': 'answered',
                'response': const {
                  'action': 'accept',
                  'answer_format': 'awiki.answer.v2',
                  'mode': 'structured',
                  'content': {'route': 'b'},
                  'text': '补充说明',
                },
              },
              taskState: 'interrupted',
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('acp-question-history:q')));
      await tester.pumpAndSettle();
      expect(find.text('回答已接收，任务未完成'), findsOneWidget);
      expect(find.textContaining('Route B'), findsOneWidget);
      expect(find.text('补充说明'), findsOneWidget);
      expect(find.text('提交回答'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'structured answer preserves actual option value and supplemental Unicode',
    (tester) async {
      final service = RecordingControl();
      await tester.pumpWidget(surface(service, question()));
      await tap(tester, find.text('Route B'));
      await tap(tester, find.text('+ Additional details (optional)'));
      await tester.enterText(
        find.byKey(const Key('acp-additional-text')),
        '  保留\n原文  ',
      );
      await tap(tester, find.text('Submit answer'));
      final args = acpMap(service.requests.single['args']);
      expect(args['definition_hash'], 'hash');
      expect(args['response'], {
        'action': 'accept',
        'answer_format': 'awiki.answer.v2',
        'mode': 'structured',
        'content': {'route': 'b'},
        'text': '  保留\n原文  ',
      });
      expect(find.text('More'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mode toggles retain both drafts but custom submission has no hidden choice',
    (tester) async {
      final service = RecordingControl();
      await tester.pumpWidget(surface(service, question()));
      await tap(tester, find.text('Route A'));
      await tap(tester, find.text('Write my own answer'));
      await tester.enterText(
        find.byKey(const Key('acp-custom-answer')),
        '  Neither\nplease keep this  ',
      );
      await tap(tester, find.text('Back to fields'));
      await tap(tester, find.text('Write my own answer'));
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('acp-custom-answer')),
            )
            .controller!
            .text,
        '  Neither\nplease keep this  ',
      );
      await tap(tester, find.text('Submit answer'));
      expect(acpMap(service.requests.single['args'])['response'], {
        'action': 'accept',
        'answer_format': 'awiki.answer.v2',
        'mode': 'custom',
        'text': '  Neither\nplease keep this  ',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty or oversized custom text is rejected and skip never carries draft',
    (tester) async {
      final service = RecordingControl();
      await tester.pumpWidget(surface(service, question()));
      await tap(tester, find.text('Write my own answer'));
      await tap(tester, find.text('Submit answer'));
      expect(service.requests, isEmpty);
      await tester.enterText(
        find.byKey(const Key('acp-custom-answer')),
        '字' * 5462,
      );
      await tap(tester, find.text('Submit answer'));
      expect(service.requests, isEmpty);
      await tap(tester, find.text('Skip question'));
      expect(acpMap(service.requests.single['args'])['response'], {
        'action': 'decline',
        'answer_format': 'awiki.answer.v2',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'native choices are strict and cancellation has a separate secondary action',
    (tester) async {
      final service = RecordingControl();
      await tester.pumpWidget(surface(service, question(shared: false)));
      expect(find.text('Write my own answer'), findsNothing);
      expect(find.text('+ Additional details (optional)'), findsNothing);
      await tap(tester, find.text('More'));
      await tester.pumpAndSettle();
      expect(service.requests, isEmpty);
      await tap(tester, find.text('Dismiss question'));
      await tester.pumpAndSettle();
      expect(acpMap(service.requests.single['args'])['response'], {
        'action': 'cancel',
        'answer_format': 'awiki.answer.v2',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'local draft and exact uncertain command survive reopening without automatic submission',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final service = RecordingControl()..completion = Completer();
      final session = AcpSession.parse(snapshot())!;
      final q = question();
      final scope = acpQuestionScope(session, q);
      final first = _Harness(scope, service, store, 'did:alice', () => true);
      await Future<void>.delayed(Duration.zero);
      first.edit({
        'answers': {'route': 'a'},
        'custom_text': 'My draft',
        'mode': 'custom',
      });
      final send = first.submit(session, q, {
        'action': 'accept',
        'answer_format': 'awiki.answer.v2',
        'mode': 'custom',
        'text': 'My draft',
      });
      await Future<void>.delayed(Duration.zero);
      service.completion!.completeError(TimeoutException('offline'));
      await send;
      expect(first.draft.phase, AcpAnswerPhase.uncertain);
      first.dispose();
      service.completion = null;
      final reopened = _Harness(scope, service, store, 'did:alice', () => true);
      addTearDown(reopened.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(reopened.draft.data['custom_text'], 'My draft');
      expect(service.requests, hasLength(1));
      expect(reopened.draft.phase, AcpAnswerPhase.uncertain);
      reopened.edit({'custom_text': 'must not overwrite'});
      expect(reopened.draft.data['custom_text'], 'My draft');
      await reopened.submit(
        AcpSession.parse({...snapshot(), 'revision': 9})!,
        q,
        {'action': 'accept', 'text': 'ignored new content'},
      );
      expect(service.requests, hasLength(2));
      expect(service.requests[0]['command'], service.requests[1]['command']);
      expect(service.requests[0]['args'], service.requests[1]['args']);
      expect(reopened.draft.phase, AcpAnswerPhase.accepted);
    },
  );

  test('corrupt saved retry cannot target another task or action', () async {
    final store = _ControlledStore();
    final service = RecordingControl()..completion = Completer();
    final session = AcpSession.parse(snapshot())!;
    final q = question();
    final scope = acpQuestionScope(session, q);
    final first = _Harness(scope, service, store, 'did:alice', () => true);
    await Future<void>.delayed(Duration.zero);
    final sending = first.submit(session, q, {
      'action': 'decline',
      'answer_format': 'awiki.answer.v2',
    });
    await Future<void>.delayed(Duration.zero);
    service.completion!.completeError(TimeoutException('offline'));
    await sending;
    first.dispose();
    store.corruptScope = true;
    final reopened = _Harness(scope, service, store, 'did:alice', () => true);
    addTearDown(reopened.dispose);
    await Future<void>.delayed(Duration.zero);
    expect(reopened.draft.error, 'draft_load_failed');
    await reopened.submit(session, q, {'action': 'decline'});
    expect(service.requests, hasLength(1));
  });
  test(
    'leaving a form waits for queued writes and releases the controller',
    () async {
      final store = _ControlledStore()..writeGate = Completer<void>();
      final session = AcpSession.parse(snapshot())!;
      final scope = acpQuestionScope(session, question());
      final provider = acpQuestionControllerProvider(scope);
      final container = ProviderContainer(
        overrides: [
          productLocalStoreProvider.overrideWithValue(store),
          acpControlServiceProvider.overrideWithValue(RecordingControl()),
        ],
      );
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:alice',
              credentialName: 'alice',
              displayName: 'Alice',
            ),
          );
      addTearDown(container.dispose);
      final listener = container.listen(provider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      final first = container.read(provider.notifier);
      first.edit({'custom_text': 'Retain the last keystroke'});
      listener.close();
      await container.pump();
      expect(first.mounted, isTrue);
      store.writeGate!.complete();
      await first.flush();
      await container.pump();
      expect(first.mounted, isFalse);
      final reopened = container.listen(provider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(provider).data['custom_text'],
        'Retain the last keystroke',
      );
      reopened.close();
    },
  );

  test(
    'identity, conversation, definition and requester isolate stored edits and submissions',
    () async {
      final store = InMemoryAwikiProductLocalStore();
      final service = RecordingControl();
      final session = AcpSession.parse(snapshot())!;
      final q = question();
      var current = true;
      final first = _Harness(
        acpQuestionScope(session, q),
        service,
        store,
        'did:alice',
        () => current,
      );
      await Future<void>.delayed(Duration.zero);
      first.edit({'custom_text': 'private'});
      await Future<void>.delayed(Duration.zero);
      current = false;
      await first.submit(session, q, {'action': 'decline'});
      expect(service.requests, isEmpty);
      first.dispose();
      for (final pair in [
        ('did:bob', session, q),
        (
          'did:alice',
          AcpSession.parse(snapshot(), localConversationId: 'other')!,
          q,
        ),
        ('did:alice', session, {...q, 'definition_hash': 'changed'}),
      ]) {
        final c = _Harness(
          acpQuestionScope(pair.$2, pair.$3),
          service,
          store,
          pair.$1,
          () => true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(c.draft.data, isEmpty);
        if (pair.$1 == 'did:bob') {
          await c.submit(pair.$2, pair.$3, {'action': 'decline'});
          expect(service.requests, isEmpty);
        }
        c.dispose();
      }
    },
  );
}

class _Harness extends AcpQuestionController {
  _Harness(
    super.scope,
    super.service,
    ProductLocalStore super.store,
    String super.owner,
    super.current,
  );
  AcpQuestionDraft get draft => state;
}

class _ControlledStore extends InMemoryAwikiProductLocalStore {
  bool corruptScope = false;
  Completer<void>? writeGate;
  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    await writeGate?.future;
    await super.saveUiPreference(preference);
  }

  @override
  Future<LocalUiPreference?> loadUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    final row = await super.loadUiPreference(ownerDid: ownerDid, key: key);
    if (!corruptScope || row == null) return row;
    final data = jsonDecode(row.valueJson) as Map<String, dynamic>;
    (data['args'] as Map)['run_id'] = 'another-task';
    return LocalUiPreference(
      ownerDid: ownerDid,
      key: key,
      valueJson: jsonEncode(data),
      updatedAt: row.updatedAt,
    );
  }
}
