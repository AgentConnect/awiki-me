import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/domain/entities/agent/acp_session.dart';

import '../../e2e/flutter/support/coding_agent_oracles.dart';

void main() {
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
