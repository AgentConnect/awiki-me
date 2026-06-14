import 'chat_message.dart';
import 'conversation_summary.dart';

bool sameConversationTarget(
  ConversationSummary first,
  ConversationSummary second,
) {
  if (first.threadId == second.threadId) {
    return true;
  }
  if (first.isGroup || second.isGroup) {
    return first.isGroup &&
        second.isGroup &&
        sameNonEmpty(first.groupId, second.groupId);
  }
  return sameDirectConversationTarget(first, second);
}

bool sameDirectConversationTarget(
  ConversationSummary first,
  ConversationSummary second,
) {
  if (sameNonEmpty(first.targetDid, second.targetDid)) {
    return true;
  }
  final firstPeer = normalizedDirectPeer(first.targetPeer);
  final secondPeer = normalizedDirectPeer(second.targetPeer);
  return firstPeer != null && firstPeer == secondPeer;
}

bool sameNonEmpty(String? first, String? second) {
  final a = first?.trim();
  final b = second?.trim();
  return a != null && a.isNotEmpty && b != null && b.isNotEmpty && a == b;
}

String? normalizedDirectPeer(String? value) {
  final peer = value?.trim();
  if (peer == null || peer.isEmpty) {
    return null;
  }
  return peer.startsWith('did:') ? peer : peer.toLowerCase();
}

String? directPeerDidFromMessages(List<ChatMessage> messages) {
  for (final message in messages.reversed) {
    if (message.isMine) {
      final receiver = message.receiverDid?.trim();
      if (receiver != null && receiver.isNotEmpty) {
        return receiver;
      }
      continue;
    }
    final sender = message.senderDid.trim();
    if (sender.isNotEmpty) {
      return sender;
    }
  }
  return null;
}
