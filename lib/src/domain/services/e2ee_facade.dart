import '../entities/chat_message.dart';
import '../entities/session_identity.dart';

class EncryptedPayload {
  const EncryptedPayload({
    required this.content,
    required this.originalType,
    required this.sessionId,
  });

  final Map<String, Object?> content;
  final String originalType;
  final String sessionId;
}

class E2eeProcessResult {
  const E2eeProcessResult({
    this.decryptedMessage,
    this.protocolResponses = const <Map<String, Object?>>[],
  });

  final ChatMessage? decryptedMessage;
  final List<Map<String, Object?>> protocolResponses;
}

abstract class E2eeFacade {
  Future<bool> isSupported();

  Future<void> initialize(SessionIdentity identity);

  Future<void> ensureSession(String peerDid);

  Future<EncryptedPayload> encryptOutgoing({
    required String peerDid,
    required String originalType,
    required String plaintext,
  });

  Future<E2eeProcessResult> processIncomingProtocolMessage(ChatMessage message);

  Future<ChatMessage> decryptIncomingMessage(ChatMessage message);

  Future<Map<String, Object?>> exportSessionState();

  Future<void> importSessionState(Map<String, Object?> state);
}

