import 'package:flutter/services.dart';

import '../domain/entities/chat_message.dart';
import '../domain/entities/session_identity.dart';
import '../domain/services/e2ee_facade.dart';

class MethodChannelE2eeFacade implements E2eeFacade {
  MethodChannelE2eeFacade({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('ai.awiki.awikime/e2ee');

  final MethodChannel _channel;

  @override
  Future<ChatMessage> decryptIncomingMessage(ChatMessage message) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'decryptIncomingMessage',
      <String, Object?>{
        'localId': message.localId,
        'threadId': message.threadId,
        'senderDid': message.senderDid,
        'receiverDid': message.receiverDid,
        'groupId': message.groupId,
        'content': message.content,
        'originalType': message.originalType,
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_result',
        message: 'E2EE decrypt result is empty',
      );
    }
    return message.copyWith(content: result['content']?.toString() ?? message.content);
  }

  @override
  Future<EncryptedPayload> encryptOutgoing({
    required String peerDid,
    required String originalType,
    required String plaintext,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'encryptOutgoing',
      <String, Object?>{
        'peerDid': peerDid,
        'originalType': originalType,
        'plaintext': plaintext,
      },
    );
    if (result == null) {
      throw PlatformException(
        code: 'empty_result',
        message: 'E2EE encrypt result is empty',
      );
    }
    return EncryptedPayload(
      content: result,
      originalType: originalType,
      sessionId: result['session_id']?.toString() ?? '',
    );
  }

  @override
  Future<Map<String, Object?>> exportSessionState() async {
    final result = await _channel.invokeMapMethod<String, Object?>('exportSessionState');
    return result ?? const <String, Object?>{};
  }

  @override
  Future<void> importSessionState(Map<String, Object?> state) async {
    await _channel.invokeMethod<void>('importSessionState', state);
  }

  @override
  Future<void> initialize(SessionIdentity identity) async {
    await _channel.invokeMethod<void>(
      'initialize',
      <String, Object?>{
        'did': identity.did,
        'credentialName': identity.credentialName,
        'displayName': identity.displayName,
        'handle': identity.handle,
      },
    );
  }

  @override
  Future<bool> isSupported() async {
    final result = await _channel.invokeMethod<bool>('isSupported');
    return result ?? false;
  }

  @override
  Future<E2eeProcessResult> processIncomingProtocolMessage(ChatMessage message) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'processIncomingProtocolMessage',
      <String, Object?>{
        'localId': message.localId,
        'threadId': message.threadId,
        'senderDid': message.senderDid,
        'content': message.content,
      },
    );
    return E2eeProcessResult(
      protocolResponses: (result?['protocolResponses'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => item.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(),
    );
  }

  @override
  Future<void> ensureSession(String peerDid) async {
    await _channel.invokeMethod<void>(
      'ensureSession',
      <String, Object?>{'peerDid': peerDid},
    );
  }
}

