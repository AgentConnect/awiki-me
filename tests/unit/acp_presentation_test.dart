import 'dart:async';

import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';
import 'package:awiki_me/src/presentation/agents/acp_session_provider.dart';
import 'package:awiki_me/src/presentation/agents/acp_task_status.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'acp_runtime_test.dart' show RecordingControl, snapshot;

Map<String, Object?> question(Map<String, Object?> properties) => {
  'id': 'q',
  'run_id': 'a',
  'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 60000,
  'request': {
    'message': 'Help choose the next step',
    'requestedSchema': {
      'type': 'object',
      'required': properties.keys.toList(),
      'properties': properties,
    },
  },
};

Future<void> pumpQuestion(
  WidgetTester tester,
  RecordingControl service,
  Map<String, Object?> value,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [acpControlServiceProvider.overrideWithValue(service)],
    child: CupertinoApp(
      home: CupertinoPageScaffold(
        child: SingleChildScrollView(
          child: AcpQuestionForm(
            session: AcpSession.parse(snapshot())!,
            question: value,
            canAnswer: true,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a long model row keeps its geometry while the command is pending',
    (tester) async {
      final service = RecordingControl()
        ..completion = Completer<Map<String, Object?>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acpControlServiceProvider.overrideWithValue(service)],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 280,
                  child: AcpActionButton(
                    session: AcpSession.parse(snapshot())!,
                    action: 'set_model',
                    values: const {'model_id': 'long'},
                    label: 'Long model',
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'A model with a long description that spans several lines on a small phone and must keep the same space while saving.',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final finder = find.byType(AcpActionButton);
      final before = tester.getRect(finder);
      await tester.tap(finder);
      await tester.pump();
      expect(tester.getRect(finder), before);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      service.completion!.complete({});
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('question drafts survive scrolling out of the message list', (
    tester,
  ) async {
    final service = RecordingControl();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final session = AcpSession.parse(snapshot())!;
    final value = question({
      'name': {'type': 'string'},
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [acpControlServiceProvider.overrideWithValue(service)],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
            child: ListView.builder(
              controller: scroll,
              itemCount: 30,
              itemBuilder: (_, i) => i == 0
                  ? AcpQuestionForm(
                      key: const ValueKey('q'),
                      session: session,
                      question: value,
                      canAnswer: true,
                    )
                  : SizedBox(height: 120, child: Text('Message $i')),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('acp-field:name')),
      'Keep this answer',
    );
    await tester.pump();
    scroll.jumpTo(2200);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const ValueKey('acp-field:name')),
          )
          .controller!
          .text,
      'Keep this answer',
    );
    await tester.tap(find.text('Submit answer'));
    await tester.pump();
    expect(
      acpMap(acpMap(service.requests.single['args'])['response'])['content'],
      {'name': 'Keep this answer'},
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'concurrent questions keep separate inputs and command identities',
    (tester) async {
      final service = RecordingControl()
        ..completion = Completer<Map<String, Object?>>();
      final session = AcpSession.parse(snapshot())!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [acpControlServiceProvider.overrideWithValue(service)],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final id in ['one', 'two'])
                      AcpQuestionForm(
                        key: ValueKey(id),
                        session: session,
                        question: question({
                          'name': {'type': 'string'},
                        })..['id'] = id,
                        canAnswer: true,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (final id in ['one', 'two']) {
        final form = find.byKey(ValueKey(id));
        final field = find.descendant(
          of: form,
          matching: find.byKey(const ValueKey('acp-field:name')),
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, 'Answer $id');
        await tester.pump();
        final submit = find.descendant(
          of: form,
          matching: find.text('Submit answer'),
        );
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
      }
      expect(service.requests, hasLength(2));
      expect(
        service.requests[0]['command'],
        isNot(service.requests[1]['command']),
      );
      for (var i = 0; i < 2; i++) {
        final args = acpMap(service.requests[i]['args']);
        final id = i == 0 ? 'one' : 'two';
        expect(args['question_id'], id);
        expect(acpMap(args['response'])['content'], {'name': 'Answer $id'});
      }
      service.completion!.complete({});
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'single and multiple choices preserve wire values and supplementary text',
    (tester) async {
      final service = RecordingControl();
      await pumpQuestion(
        tester,
        service,
        question({
          'route': {
            'type': 'string',
            'oneOf': [
              {'const': 'safe', 'title': 'A careful rollout'},
              {'const': 'fast', 'title': 'Ship immediately'},
            ],
          },
          'targets': {
            'type': 'array',
            'minItems': 2,
            'maxItems': 2,
            'items': {
              'type': 'string',
              'enum': ['mac', 'ios', 'android'],
              'enumNames': ['Mac desktop', 'iPhone', 'Android phone'],
            },
          },
          'notes': {'type': 'string', 'minLength': 3},
        }),
      );
      await tester.tap(find.text('A careful rollout'));
      await tester.tap(find.text('Mac desktop'));
      await tester.enterText(
        find.byKey(const ValueKey('acp-field:notes')),
        'Keep my full answer.',
      );
      await tester.ensureVisible(find.text('Submit answer'));
      await tester.tap(find.text('Submit answer'));
      await tester.pumpAndSettle();
      expect(service.requests, isEmpty);
      expect(find.text('Select at least 2 options.'), findsOneWidget);
      await tester.ensureVisible(find.text('iPhone'));
      await tester.tap(find.text('iPhone'));
      await tester.pump();
      await tester.ensureVisible(find.text('Submit answer'));
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(acpMap(service.requests.single['args'])['response'], {
        'action': 'accept',
        'content': {
          'route': 'safe',
          'targets': ['mac', 'ios'],
          'notes': 'Keep my full answer.',
        },
      });
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(service.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'number and string constraints give inline errors without sending',
    (tester) async {
      final service = RecordingControl();
      await pumpQuestion(
        tester,
        service,
        question({
          'count': {'type': 'integer', 'minimum': 1, 'maximum': 3},
          'code': {'type': 'string', 'minLength': 2, 'maxLength': 4},
        }),
      );
      for (final input in ['abc', '1.5', '4', '-1']) {
        await tester.enterText(
          find.byKey(const ValueKey('acp-field:count')),
          input,
        );
        await tester.enterText(
          find.byKey(const ValueKey('acp-field:code')),
          'too long',
        );
        await tester.tap(find.text('Submit answer'));
        await tester.pump();
        expect(service.requests, isEmpty);
      }
      await tester.enterText(
        find.byKey(const ValueKey('acp-field:count')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('acp-field:code')),
        'OK',
      );
      await tester.pump();
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(
        acpMap(acpMap(service.requests.single['args'])['response'])['content'],
        {'count': 2, 'code': 'OK'},
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unconfirmed response freezes values and retries the same command',
    (tester) async {
      final service = RecordingControl()
        ..completion = Completer<Map<String, Object?>>();
      await pumpQuestion(
        tester,
        service,
        question({
          'name': {'type': 'string'},
        }),
      );
      await tester.enterText(
        find.byKey(const ValueKey('acp-field:name')),
        'Alice',
      );
      await tester.pump();
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      service.completion!.completeError(TimeoutException('test'));
      await tester.pump();
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('acp-field:name')),
            )
            .enabled,
        isFalse,
      );
      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(service.requests, hasLength(1));
      service.completion = Completer<Map<String, Object?>>();
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(service.requests, hasLength(2));
      expect(service.requests[1], service.requests[0]);
      service.completion!.complete({});
      await tester.pump();
      expect(
        find.text('Response sent. Waiting for the agent.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'expiry locks an edited question and a replacement starts empty',
    (tester) async {
      final service = RecordingControl();
      final value = question({
        'name': {'type': 'string'},
      })..['expires_at_ms'] = DateTime.now().millisecondsSinceEpoch + 1000;
      await pumpQuestion(tester, service, value);
      await tester.enterText(
        find.byKey(const ValueKey('acp-field:name')),
        'Old answer',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('Submit answer'));
      expect(service.requests, isEmpty);
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('acp-field:name')),
            )
            .enabled,
        isFalse,
      );
      await pumpQuestion(
        tester,
        service,
        question({
          'name': {'type': 'string'},
        })..['id'] = 'new-question',
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('acp-field:name')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('acp-field:name')),
            )
            .enabled,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsupported form has an explicit explanation and a working exit',
    (tester) async {
      final service = RecordingControl();
      await pumpQuestion(
        tester,
        service,
        question({
          'nested': {'type': 'object'},
        }),
      );
      expect(find.text('Submit answer'), findsNothing);
      expect(find.textContaining('not supported'), findsOneWidget);
      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(acpMap(service.requests.single['args'])['response'], {
        'action': 'decline',
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a required boolean needs an explicit answer', (tester) async {
    final service = RecordingControl();
    await pumpQuestion(
      tester,
      service,
      question({
        'confirm': {'type': 'boolean'},
      }),
    );
    await tester.tap(find.text('Submit answer'));
    await tester.pump();
    expect(service.requests, isEmpty);
    expect(find.text('Please answer this question.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending answer locks fields and alternative responses', (
    tester,
  ) async {
    final service = RecordingControl()
      ..completion = Completer<Map<String, Object?>>();
    await pumpQuestion(
      tester,
      service,
      question({
        'name': {'type': 'string'},
      }),
    );
    await tester.enterText(
      find.byKey(const ValueKey('acp-field:name')),
      'Alice',
    );
    await tester.pump();
    await tester.tap(find.text('Submit answer'));
    await tester.pump();
    expect(
      tester
          .widget<CupertinoTextField>(
            find.byKey(const ValueKey('acp-field:name')),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(service.requests, hasLength(1));
    service.completion!.complete({});
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}
