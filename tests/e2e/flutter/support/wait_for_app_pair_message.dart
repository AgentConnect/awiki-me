import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

class AppPairMessageObservation {
  const AppPairMessageObservation(this.messages, this.match);

  final List<ChatMessage> messages;
  final ChatMessage? match;
}

/// Observes committed history only. A bulk recovery may need a larger bounded
/// processing budget than one ordinary message; neither budget triggers sync.
Future<AppPairMessageObservation> waitForAppPairMessage({
  required Future<List<ChatMessage>> Function() read,
  required String content,
  required String messageId,
  required String senderDid,
  required String receiverDid,
  required bool isMine,
  Duration timeout = const Duration(seconds: 90),
  DateTime Function()? now,
  Future<void> Function(Duration)? delay,
}) async {
  final clock = now ?? DateTime.now;
  final pause = delay ?? Future<void>.delayed;
  final deadline = clock().add(timeout);
  var lastMessages = const <ChatMessage>[];
  while (clock().isBefore(deadline)) {
    lastMessages = await read();
    final matches = lastMessages
        .where((message) => message.content == content)
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The App-pair history projected a duplicate exact message.');
    }
    if (matches.length == 1) {
      final message = matches.single;
      if (message.remoteId == messageId &&
          message.senderDid == senderDid &&
          message.receiverDid == receiverDid &&
          message.isMine == isMine &&
          message.sendState == MessageSendState.sent) {
        return AppPairMessageObservation(lastMessages, message);
      }
    }
    final remaining = deadline.difference(clock());
    if (remaining <= Duration.zero) break;
    await pause(
      remaining < const Duration(milliseconds: 750)
          ? remaining
          : const Duration(milliseconds: 750),
    );
  }
  return AppPairMessageObservation(lastMessages, null);
}
