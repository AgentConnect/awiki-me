import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/support/wait_for_app_pair_message.dart';

ChatMessage message({
  String id = 'expected',
  String sender = 'sender',
  String receiver = 'receiver',
  bool mine = false,
  String content = 'body',
  MessageSendState state = MessageSendState.sent,
}) => ChatMessage(
  localId: id,
  remoteId: id,
  threadId: 'thread',
  senderDid: sender,
  receiverDid: receiver,
  content: content,
  createdAt: DateTime.utc(2026),
  isMine: mine,
  sendState: state,
);

class Clock {
  var elapsed = Duration.zero;
  DateTime now() => DateTime.utc(2026).add(elapsed);
  Future<void> delay(Duration duration) async => elapsed += duration;
}

Future<AppPairMessageObservation> observe(
  Clock clock,
  Future<List<ChatMessage>> Function() read, {
  Duration timeout = const Duration(seconds: 90),
}) => waitForAppPairMessage(
  read: read,
  content: 'body',
  messageId: 'expected',
  senderDid: 'sender',
  receiverDid: 'receiver',
  isMine: false,
  timeout: timeout,
  now: clock.now,
  delay: clock.delay,
);

void main() {
  test(
    'bulk backlog can converge after the ordinary message deadline',
    () async {
      for (final seconds in [90, 300]) {
        final clock = Clock();
        final result = await observe(
          clock,
          () async => clock.elapsed.inSeconds < 120 ? [] : [message()],
          timeout: Duration(seconds: seconds),
        );
        expect(result.match != null, seconds == 300);
        expect(clock.elapsed.inSeconds, seconds == 300 ? 120 : 90);
      }
    },
  );

  test('progress never renews the absolute bulk deadline', () async {
    final clock = Clock();
    var reads = 0;
    final result = await observe(
      clock,
      () async => [message(content: 'other-${reads++}')],
      timeout: const Duration(minutes: 5),
    );
    expect(result.match, isNull);
    expect(clock.elapsed, const Duration(minutes: 5));
    expect(reads, greaterThan(1));
    expect(result.messages.single.content, startsWith('other-'));
  });

  test(
    'matching content cannot replace exact identity or committed state',
    () async {
      for (final wrong in [
        message(id: 'other'),
        message(sender: 'other'),
        message(receiver: 'other'),
        message(mine: true),
        message(state: MessageSendState.sending),
        message(state: MessageSendState.failed),
      ]) {
        final result = await observe(
          Clock(),
          () async => [wrong],
          timeout: const Duration(seconds: 1),
        );
        expect(result.match, isNull);
      }
    },
  );

  test('duplicate content fails even when one message is exact', () async {
    await expectLater(
      observe(Clock(), () async => [message(), message(id: 'duplicate')]),
      throwsA(isA<TestFailure>()),
    );
  });

  test('read failure is propagated rather than converted to success', () async {
    await expectLater(
      observe(Clock(), () async => throw StateError('unavailable')),
      throwsStateError,
    );
  });

  test('exact committed message returns immediately', () async {
    final clock = Clock();
    final expected = message();
    final result = await observe(clock, () async => [expected]);
    expect(result.match, same(expected));
    expect(clock.elapsed, Duration.zero);
  });
}
