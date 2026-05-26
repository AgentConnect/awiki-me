import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_thread_ref.dart';
import '../../application/ports/conversation_core_port.dart';
import '../../domain/entities/conversation_summary.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

const int _markThreadReadPageSize = 100;
const int _markThreadReadMaxPages = 10;

class AwikiImCoreConversationAdapter implements ConversationCorePort {
  AwikiImCoreConversationAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final client = await _runtime.currentClient();
    final ownerDid = (await client.identity.current()).did;
    final page = await client.messages.conversations(
      limit: limit,
      unreadOnly: unreadOnly,
    );
    return page.items
        .map(
          (conversation) =>
              _mappers.conversationFromCore(conversation, ownerDid: ownerDid),
        )
        .toList();
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {
    final client = await _runtime.currentClient();
    final ownerDid = (await client.identity.current()).did;
    final coreThread = coreThreadRefForMarkRead(thread, ownerDid);
    final messageIds = <String>{};
    String? cursor;

    for (var pageIndex = 0; pageIndex < _markThreadReadMaxPages; pageIndex++) {
      final page = await client.messages.history(
        coreThread,
        limit: _markThreadReadPageSize,
        cursor: cursor,
      );
      messageIds.addAll(
        unreadIncomingMessageIdsForMarkRead(page.items, ownerDid: ownerDid),
      );
      final nextCursor = page.nextCursor?.trim();
      if (!page.hasMore ||
          nextCursor == null ||
          nextCursor.isEmpty ||
          nextCursor == cursor) {
        break;
      }
      cursor = nextCursor;
    }

    if (messageIds.isEmpty) {
      return;
    }
    await client.messages.markRead(messageIds.toList(growable: false));
  }
}

core.ThreadRef coreThreadRefForMarkRead(AppThreadRef thread, String ownerDid) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => core.ThreadRef.direct(
      peerDidOrHandle,
    ),
    AppGroupThreadRef(:final groupDid) => core.ThreadRef.group(
      _stripGroupPrefix(groupDid),
    ),
    AppMessageThreadRef(:final threadId) => _coreThreadRefFromThreadId(
      threadId,
      ownerDid,
    ),
  };
}

List<String> unreadIncomingMessageIdsForMarkRead(
  Iterable<core.Message> messages, {
  required String ownerDid,
}) {
  return messages
      .where((message) => _shouldMarkMessageRead(message, ownerDid))
      .map((message) => message.id.trim())
      .where((messageId) => messageId.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

core.ThreadRef _coreThreadRefFromThreadId(String threadId, String ownerDid) {
  final raw = threadId.trim();
  if (raw.startsWith('group:')) {
    return core.ThreadRef.group(_stripGroupPrefix(raw));
  }
  final peer = _directPeerFromThreadId(ownerDid, raw);
  if (peer != null) {
    return core.ThreadRef.direct(peer);
  }
  throw UnsupportedError('Cannot mark unread messages for thread $threadId.');
}

String _stripGroupPrefix(String groupDid) {
  final raw = groupDid.trim();
  return raw.startsWith('group:') ? raw.substring('group:'.length) : raw;
}

String? _directPeerFromThreadId(String ownerDid, String threadId) {
  final raw = threadId.trim();
  if (!raw.startsWith('dm:')) {
    return null;
  }
  final body = raw.substring('dm:'.length);
  final owner = ownerDid.trim();
  if (owner.isEmpty) {
    return null;
  }
  if (body.startsWith('$owner:')) {
    return _nonEmpty(body.substring(owner.length + 1));
  }
  if (body.endsWith(':$owner')) {
    return _nonEmpty(body.substring(0, body.length - owner.length - 1));
  }
  return null;
}

bool _shouldMarkMessageRead(core.Message message, String ownerDid) {
  if (message.direction == core.MessageDirection.outgoing ||
      message.sender.trim() == ownerDid.trim()) {
    return false;
  }
  return _messageReadState(message) != true;
}

bool? _messageReadState(core.Message message) {
  for (final attribute in message.metadata.attributes) {
    if (attribute.key != 'is_read') {
      continue;
    }
    return switch (attribute.value.trim().toLowerCase()) {
      'true' || '1' => true,
      'false' || '0' => false,
      _ => null,
    };
  }
  return null;
}

String? _nonEmpty(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
