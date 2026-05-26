import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_thread_ref.dart';
import '../../application/ports/message_core_port.dart';
import '../../domain/entities/chat_message.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreMessageAdapter implements MessageCorePort {
  AwikiImCoreMessageAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    final client = await _runtime.currentClient();
    final ownerDid = (await client.identity.current()).did;
    final result = await client.messages.sendText(
      core.SendTextRequest(
        target: _mappers.messageTargetToCore(thread),
        text: content,
      ),
    );
    return _mappers.chatMessageFromCore(result.message, ownerDid: ownerDid);
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) async {
    final client = await _runtime.currentClient();
    final ownerDid = (await client.identity.current()).did;
    final page = await client.messages.history(
      _mappers.threadRefToCore(thread),
      limit: limit,
      cursor: cursor,
    );
    return page.items
        .map(
          (message) =>
              _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
        )
        .where((message) => message.hasDisplayableText)
        .toList();
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    return sendText(
      thread: _threadFromFailedMessage(failed),
      content: failed.content,
    );
  }
}

AppThreadRef _threadFromFailedMessage(ChatMessage failed) {
  final groupId = failed.groupId;
  if (groupId != null && groupId.trim().isNotEmpty) {
    return AppThreadRef.group(groupId);
  }
  final peer = failed.isMine ? failed.receiverDid : failed.senderDid;
  if (peer == null || peer.trim().isEmpty) {
    throw StateError('Cannot retry message without a direct peer or group id.');
  }
  return AppThreadRef.direct(peer);
}
