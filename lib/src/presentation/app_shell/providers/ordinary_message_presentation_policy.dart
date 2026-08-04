import '../../../domain/entities/chat_message.dart';

bool isOrdinaryMessagePresentationEligible(ChatMessage message) {
  if (!message.hasRenderableContent ||
      message.isMine ||
      message.isGroupSystemEvent ||
      message.isAgentControlPayload) {
    return false;
  }
  final type = message.originalType.trim().toLowerCase();
  if (message.isEncrypted && type.contains('e2ee')) {
    return false;
  }
  return true;
}
