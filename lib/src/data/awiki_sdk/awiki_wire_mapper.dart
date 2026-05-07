import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';

class AwikiWireMapper {
  const AwikiWireMapper();

  List<Map<String, Object?>> mapList(Object? raw) {
    if (raw is List) {
      return raw.whereType<Map<Object?, Object?>>().map(_stringKeyMap).toList();
    }
    if (raw is Map) {
      final map = _stringKeyMap(raw);
      for (final key in const <String>[
        'messages',
        'items',
        'list',
        'records',
        'results',
        'members',
        'groups',
        'data',
      ]) {
        final nested = mapList(map[key]);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return const <Map<String, Object?>>[];
  }

  ChatMessage toChatMessage(
    Map<String, Object?> item, {
    required String ownerDid,
    String? forceThreadId,
    String? forceGroupId,
  }) {
    final meta = _nestedMap(item['meta']);
    final body = _nestedMap(item['body']);
    final target = _nestedMap(meta['target']);
    final content = _firstString(<Object?>[
      item['content'],
      item['text'],
      body['text'],
      _nestedMap(item['content'])['text'],
    ]);
    final senderDid = _firstString(<Object?>[
      item['sender_did'],
      item['from'],
      meta['sender_did'],
      body['sender_did'],
    ]);
    final receiverDid = _firstNullableString(<Object?>[
      item['receiver_did'],
      item['target_did'],
      item['recipient_did'],
      item['peer_did'],
      target['did'],
      meta['target_did'],
      body['receiver_did'],
    ]);
    final groupId =
        forceGroupId ??
        _firstNullableString(<Object?>[
          item['group_did'],
          item['group_id'],
          body['group_did'],
          body['group_id'],
          target['kind'] == 'group' ? target['did'] : null,
        ]);
    final messageId = messageIdOf(item);
    return ChatMessage(
      localId: messageId.isNotEmpty
          ? messageId
          : 'local-${DateTime.now().microsecondsSinceEpoch}',
      remoteId: messageId.isEmpty ? null : messageId,
      threadId: forceThreadId ?? threadIdForMessage(item, ownerDid: ownerDid),
      senderDid: senderDid,
      senderName: _firstNullableString(<Object?>[
        item['sender_name'],
        item['display_name'],
        item['handle'],
        item['member_handle'],
      ]),
      receiverDid: receiverDid,
      groupId: groupId,
      content: content,
      originalType: _firstString(<Object?>[
        item['type'],
        item['message_type'],
        item['content_type'],
      ], fallback: 'text'),
      createdAt:
          parseDate(
            _firstNullableString(<Object?>[
              item['sent_at'],
              item['created_at'],
              item['accepted_at'],
              item['timestamp'],
              meta['created_at'],
              body['accepted_at'],
            ]),
          ) ??
          DateTime.now(),
      isMine: senderDid == ownerDid,
      sendState: MessageSendState.sent,
      serverSequence: int.tryParse(
        _firstString(<Object?>[
          item['server_seq'],
          item['server_sequence'],
          item['seq'],
          item['group_event_seq'],
          body['group_event_seq'],
        ]),
      ),
      isEncrypted:
          item['_e2ee'] == true ||
          _firstString(<Object?>[
            item['type'],
            item['message_type'],
          ]).startsWith('e2ee_'),
    );
  }

  GroupSummary toGroupSummary(Map<String, Object?> map) {
    final profile = _nestedMap(map['group_profile']);
    final snapshot = _nestedMap(map['group_snapshot']);
    final group = _nestedMap(map['group']);
    final source = <String, Object?>{...snapshot, ...group, ...profile, ...map};
    final groupId = _firstString(<Object?>[
      source['group_did'],
      source['group_id'],
      source['did'],
      source['id'],
    ]);
    return GroupSummary(
      groupId: groupId,
      name: _firstString(<Object?>[
        source['display_name'],
        source['name'],
      ], fallback: groupId.isNotEmpty ? 'Group $groupId' : 'Unnamed Group'),
      description: _firstString(<Object?>[source['description']]),
      memberCount:
          int.tryParse(
            _firstString(<Object?>[
              source['member_count'],
              source['members_count'],
            ]),
          ) ??
          0,
      lastMessageAt: parseDate(
        _firstNullableString(<Object?>[
          source['last_message_at'],
          source['updated_at'],
          source['created_at'],
        ]),
      ),
      myRole: _firstNullableString(<Object?>[
        source['my_role'],
        source['role'],
      ]),
    );
  }

  GroupMemberSummary toGroupMemberSummary(Map<String, Object?> item) {
    return GroupMemberSummary(
      userId: _firstString(<Object?>[
        item['user_id'],
        item['member_id'],
        item['id'],
      ]),
      did: _firstString(<Object?>[
        item['did'],
        item['member_did'],
        item['user_did'],
      ]),
      handle: _firstString(<Object?>[item['handle'], item['member_handle']]),
      role: _firstString(<Object?>[item['role']], fallback: 'member'),
      profileUrl: _firstNullableString(<Object?>[
        item['profile_url'],
        item['avatar_url'],
      ]),
    );
  }

  List<ConversationSummary> conversationsFromInbox({
    required List<Map<String, Object?>> messages,
    required String ownerDid,
  }) {
    final latest = <String, Map<String, Object?>>{};
    final unread = <String, int>{};
    for (final item in messages) {
      final threadId = threadIdForMessage(item, ownerDid: ownerDid);
      final sentAt =
          parseDate(
            _firstNullableString(<Object?>[
              item['sent_at'],
              item['created_at'],
              item['accepted_at'],
            ]),
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final current = latest[threadId];
      if (current == null) {
        latest[threadId] = item;
      } else {
        final currentAt =
            parseDate(
              _firstNullableString(<Object?>[
                current['sent_at'],
                current['created_at'],
                current['accepted_at'],
              ]),
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (currentAt.isBefore(sentAt)) {
          latest[threadId] = item;
        }
      }
      final senderDid = _firstString(<Object?>[
        item['sender_did'],
        item['from'],
      ]);
      if (senderDid.isNotEmpty && senderDid != ownerDid) {
        unread[threadId] = (unread[threadId] ?? 0) + 1;
      }
    }
    final conversations = latest.entries.map((entry) {
      final item = entry.value;
      final groupId = _groupIdFromMessage(item);
      final isGroup = groupId.isNotEmpty;
      final peerDid = isGroup
          ? ''
          : peerDidFromMessage(item, ownerDid: ownerDid);
      final displayName = isGroup
          ? _firstString(<Object?>[
              item['group_name'],
              item['display_name'],
            ], fallback: groupId.isNotEmpty ? 'Group $groupId' : 'Group')
          : _firstString(<Object?>[
              item['sender_name'],
              item['display_name'],
              item['handle'],
              peerDid,
            ], fallback: 'Unknown');
      final message = toChatMessage(item, ownerDid: ownerDid);
      return ConversationSummary(
        threadId: entry.key,
        displayName: displayName,
        lastMessagePreview: message.content,
        lastMessageAt: message.createdAt,
        unreadCount: unread[entry.key] ?? 0,
        isGroup: isGroup,
        targetDid: isGroup ? null : peerDid,
        groupId: isGroup ? groupId : null,
        avatarSeed: isGroup ? groupId : peerDid,
      );
    }).toList();
    conversations.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return conversations;
  }

  ConversationSummary conversationFromMessage({
    required ChatMessage message,
    required String ownerDid,
    required ConversationSummary? previous,
    Map<String, Object?> event = const <String, Object?>{},
  }) {
    final isGroup = (message.groupId ?? '').isNotEmpty;
    final peerDid = isGroup
        ? ''
        : peerDidFromMessage(event, ownerDid: ownerDid);
    final displayName = isGroup
        ? _firstString(<Object?>[
            event['group_name'],
            previous?.displayName,
            message.groupId,
          ], fallback: 'Group')
        : _firstString(<Object?>[
            event['sender_name'],
            message.senderName,
            previous?.displayName,
            peerDid,
          ], fallback: 'Unknown');
    return ConversationSummary(
      threadId: message.threadId,
      displayName: displayName,
      lastMessagePreview: message.content,
      lastMessageAt: message.createdAt,
      unreadCount: message.isMine ? 0 : (previous?.unreadCount ?? 0) + 1,
      isGroup: isGroup,
      targetDid: isGroup ? null : peerDid,
      groupId: message.groupId,
      avatarSeed: isGroup ? message.groupId : peerDid,
    );
  }

  List<ConversationSummary> mergeConversations(
    List<ConversationSummary> local,
    List<ConversationSummary> remote,
  ) {
    final byThread = <String, ConversationSummary>{};
    for (final item in local) {
      byThread[item.threadId] = item;
    }
    for (final item in remote) {
      byThread[item.threadId] = item;
    }
    final merged = byThread.values.toList();
    merged.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return merged;
  }

  String threadIdForMessage(
    Map<String, Object?> item, {
    required String ownerDid,
  }) {
    final groupId = _groupIdFromMessage(item);
    if (groupId.isNotEmpty) {
      return 'group:$groupId';
    }
    return threadIdForPeer(
      ownerDid: ownerDid,
      peerDid: peerDidFromMessage(item, ownerDid: ownerDid),
    );
  }

  String threadIdForPeer({required String ownerDid, required String peerDid}) {
    final pair = <String>[ownerDid, peerDid]..sort();
    return 'dm:${pair[0]}:${pair[1]}';
  }

  String peerDidFromMessage(
    Map<String, Object?> item, {
    required String ownerDid,
  }) {
    final meta = _nestedMap(item['meta']);
    final target = _nestedMap(meta['target']);
    final senderDid = _firstString(<Object?>[
      item['sender_did'],
      item['from'],
      meta['sender_did'],
    ]);
    final receiverDid = _firstString(<Object?>[
      item['receiver_did'],
      item['target_did'],
      item['recipient_did'],
      item['peer_did'],
      target['did'],
      meta['target_did'],
    ]);
    if (senderDid == ownerDid && receiverDid.isNotEmpty) {
      return receiverDid;
    }
    if (senderDid.isNotEmpty && senderDid != ownerDid) {
      return senderDid;
    }
    return receiverDid;
  }

  String messageIdOf(Map<String, Object?> item) {
    final meta = _nestedMap(item['meta']);
    return _firstString(<Object?>[
      item['message_id'],
      item['id'],
      item['msg_id'],
      item['remote_id'],
      meta['message_id'],
    ]);
  }

  DateTime? parseDate(Object? raw) {
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.toString());
  }

  String _groupIdFromMessage(Map<String, Object?> item) {
    final meta = _nestedMap(item['meta']);
    final target = _nestedMap(meta['target']);
    final body = _nestedMap(item['body']);
    return _firstString(<Object?>[
      item['group_did'],
      item['group_id'],
      body['group_did'],
      body['group_id'],
      target['kind'] == 'group' ? target['did'] : null,
    ]);
  }

  Map<String, Object?> _nestedMap(Object? raw) {
    if (raw is Map) {
      return _stringKeyMap(raw);
    }
    return const <String, Object?>{};
  }

  Map<String, Object?> _stringKeyMap(Map<Object?, Object?> raw) {
    return raw.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String _firstString(List<Object?> values, {String fallback = ''}) {
    return _firstNullableString(values) ?? fallback;
  }

  String? _firstNullableString(List<Object?> values) {
    for (final value in values) {
      if (value == null) {
        continue;
      }
      final text = value.toString();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }
}
