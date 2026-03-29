import '../../domain/entities/chat_message.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/services/e2ee_facade.dart';

class NoopE2eeFacade implements E2eeFacade {
  @override
  Future<ChatMessage> decryptIncomingMessage(ChatMessage message) async {
    throw UnsupportedError('AWiki Me 当前未启用 E2EE，请接入原生插件实现');
  }

  @override
  Future<EncryptedPayload> encryptOutgoing({
    required String peerDid,
    required String originalType,
    required String plaintext,
  }) async {
    throw UnsupportedError('AWiki Me 当前未启用 E2EE，请接入原生插件实现');
  }

  @override
  Future<Map<String, Object?>> exportSessionState() async {
    return const <String, Object?>{};
  }

  @override
  Future<void> importSessionState(Map<String, Object?> state) async {}

  @override
  Future<void> initialize(SessionIdentity identity) async {}

  @override
  Future<bool> isSupported() async {
    return false;
  }

  @override
  Future<E2eeProcessResult> processIncomingProtocolMessage(ChatMessage message) async {
    return const E2eeProcessResult();
  }

  @override
  Future<void> ensureSession(String peerDid) async {
    throw UnsupportedError('AWiki Me 当前未启用 E2EE，请接入原生插件实现');
  }
}
