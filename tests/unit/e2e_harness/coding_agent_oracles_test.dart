import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';

import '../../e2e/flutter/support/coding_agent_oracles.dart';

void main() {
  test(
    'focused ACP selection keeps one complete client or all four by default',
    () {
      expect(codingAgentAcpKinds('').map((k) => k.driverId), [
        'opencode',
        'gemini',
        'kimi',
        'deepseek-harness',
      ]);
      for (final driver in ['opencode', 'gemini', 'kimi', 'deepseek-harness']) {
        expect(codingAgentAcpKinds(driver).map((k) => k.driverId), [driver]);
      }
      for (final driver in ['codex', 'unknown', 'KIMI', 'kimi,gemini']) {
        expect(() => codingAgentAcpKinds(driver), throwsStateError);
      }
    },
  );

  test(
    'group focus preserves creation and requires an explicit valid driver',
    () {
      expect(codingAgentAcpCaseNumbers(''), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
      for (final driver in ['opencode', 'gemini', 'kimi', 'deepseek-harness']) {
        expect(codingAgentAcpCaseNumbers(driver), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
        expect(codingAgentAcpCaseNumbers(driver, groupOnly: true), [1, 9]);
      }
      for (final driver in ['', 'unknown', 'codex']) {
        expect(
          () => codingAgentAcpCaseNumbers(driver, groupOnly: true),
          throwsStateError,
        );
      }
    },
  );

  test(
    'Daemon query excludes prior instructions embedded in group history',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE tasks (task_text TEXT)');
      const prompt = '@agent Answer my question';
      await db.insert('tasks', {
        'task_text': jsonEncode({
          'schema': 'awiki.runtime.user_message_task.v1',
          'content_text': prompt,
        }),
      });
      await db.insert('tasks', {
        'task_text': jsonEncode({
          'schema': 'awiki.runtime.user_message_task.v1',
          'content_text': '@agent A competing instruction',
          'recent_group_context': {
            'messages': [
              {'text': prompt},
            ],
          },
        }),
      });
      await db.insert('tasks', {'task_text': 'ordinary non-JSON task'});
      await db.insert('tasks', {'task_text': '{"content_text":"$prompt"}'});
      final rows = await db.rawQuery(
        'SELECT rowid FROM tasks t WHERE ($codingAgentCurrentPromptSql) = ?',
        [prompt],
      );
      expect(rows.map((r) => r['rowid']), [1]);
      expect(
        await db.rawQuery(
          'SELECT rowid FROM tasks t WHERE ($codingAgentCurrentPromptSql) = ?',
          ['ordinary non-JSON task'],
        ),
        hasLength(1),
      );
    },
  );
  test(
    'Daemon query matches attachment captions in both supported languages',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE tasks (task_text TEXT)');
      const caption = 'Read the file.\nPreserve all bytes.';
      for (final headers in [
        ('消息文本:', '附件资源:'),
        ('Message text:', 'Attachment resources:'),
      ]) {
        await db.insert('tasks', {
          'task_text':
              '${headers.$1}\n$caption\n\n${headers.$2}\n1. filename: input.txt',
        });
      }
      await db.insert('tasks', {
        'task_text': '消息文本:\nA different instruction\n\n附件资源:\n$caption',
      });
      await db.insert('tasks', {
        'task_text': jsonEncode({
          'schema': 'awiki.runtime.user_message_task.v1',
          'content_text': 'Another instruction',
          'recent_group_context': {
            'messages': [
              {'text': caption},
            ],
          },
        }),
      });
      final rows = await db.rawQuery(
        'SELECT rowid FROM tasks t WHERE ($codingAgentCurrentPromptSql) = ?',
        [caption],
      );
      expect(rows.map((r) => r['rowid']), [1, 2]);
    },
  );

  test('lost native text entry is retried before sending', () async {
    var value = '';
    var attempts = 0;
    await enterStableCodingAgentText(
      expected: 'hello',
      enter: () async {
        attempts++;
        value = attempts == 1 ? '' : 'hello';
      },
      read: () => value,
    );
    expect(attempts, 2);
    expect(value, 'hello');
  });

  test('retained text entry needs no retry', () async {
    var attempts = 0;
    await enterStableCodingAgentText(
      expected: 'hello',
      enter: () async => attempts++,
      read: () => 'hello',
    );
    expect(attempts, 1);
  });

  test(
    'unretained text fails after bounded entry attempts without its content',
    () async {
      var attempts = 0;
      await expectLater(
        enterStableCodingAgentText(
          expected: 'private text',
          enter: () async => attempts++,
          read: () => '',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message.toString().contains('private text'),
            'does not report text',
            isFalse,
          ),
        ),
      );
      expect(attempts, 3);
    },
  );

  test(
    'busy fixture requires an unexpired unanswered question for this run',
    () {
      AcpSession session({
        Map<String, Object?> question = const {
          'run_id': 'active',
          'expires_at_ms': 101,
        },
        bool active = true,
        bool stopping = false,
      }) => AcpSession.parse({
        'schema': 'awiki.acp.session.v1',
        'session_key': 'session',
        'agent_did': 'agent',
        'conversation_id': 'conversation',
        'revision': 1,
        'active': active ? {'run_id': 'active'} : {},
        'stopping': stopping,
        'questions': [question],
      })!;

      expect(hasAcpBlockingQuestion(session(), nowMs: 100), isTrue);
      for (final value in [
        session(active: false),
        session(stopping: true),
        session(question: {}),
        session(question: {'run_id': 'other', 'expires_at_ms': 101}),
        session(question: {'run_id': 'active', 'expires_at_ms': 100}),
        session(
          question: {
            'run_id': 'active',
            'expires_at_ms': 101,
            'response': {'action': 'accept'},
          },
        ),
      ]) {
        expect(hasAcpBlockingQuestion(value, nowMs: 100), isFalse);
      }
    },
  );

  test('question progress cannot substitute the chosen answer', () {
    expect(
      matchesCodingAgentFinal(
        'Asking.USER_CHOSE_BLUE',
        'USER_CHOSE_BLUE',
        allowProgressText: true,
      ),
      isTrue,
    );
    expect(
      matchesCodingAgentFinal(
        'Asking.USER_CHOSE_RED',
        'USER_CHOSE_BLUE',
        allowProgressText: true,
      ),
      isFalse,
    );
  });
  test('ordinary and image reply checks remain exact', () {
    expect(matchesCodingAgentFinal('RED_IMAGE_OK', 'RED_IMAGE_OK'), isTrue);
    for (final value in [null, 'BLUE_IMAGE_OK', 'Note: RED_IMAGE_OK']) {
      expect(matchesCodingAgentFinal(value, 'RED_IMAGE_OK'), isFalse);
    }
  });

  test(
    'file completion allows prior narration but requires the final marker',
    () {
      const marker = 'FILE_ROUNDTRIP_DONE';
      expect(
        matchesCodingAgentFinal(
          'Copying. Sending.$marker\n',
          marker,
          allowProgressText: true,
        ),
        isTrue,
      );
      for (final value in [null, 'Sending.', '$marker but delivery failed']) {
        expect(
          matchesCodingAgentFinal(value, marker, allowProgressText: true),
          isFalse,
        );
      }
    },
  );
}
