import '../../core/group_display_name.dart';
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
    final body = _nestedMap(map['body']);
    final meta = _nestedMap(map['meta']);
    final profile = _nestedMap(map['group_profile']);
    final snapshot = _nestedMap(map['group_snapshot']);
    final group = _nestedMap(map['group']);
    final bodyProfile = _nestedMap(body['group_profile']);
    final bodySnapshot = _nestedMap(body['group_snapshot']);
    final metaProfile = _nestedMap(meta['group_profile']);
    final metaSnapshot = _nestedMap(meta['group_snapshot']);
    final groupId = _firstString(<Object?>[
      map['group_did'],
      map['group_id'],
      body['group_did'],
      body['group_id'],
      group['group_did'],
      group['group_id'],
      group['did'],
      snapshot['group_did'],
      snapshot['group_id'],
      snapshot['did'],
      profile['group_did'],
      profile['group_id'],
      profile['did'],
      meta['group_did'],
      meta['group_id'],
      map['did'],
      map['id'],
    ]);
    final name = GroupDisplayName.firstFriendly(<Object?>[
      map['group_name'],
      map['group_display_name'],
      body['group_name'],
      body['group_display_name'],
      profile['display_name'],
      profile['name'],
      snapshot['display_name'],
      snapshot['name'],
      group['display_name'],
      group['name'],
      bodyProfile['display_name'],
      bodyProfile['name'],
      bodySnapshot['display_name'],
      bodySnapshot['name'],
      metaProfile['display_name'],
      metaProfile['name'],
      metaSnapshot['display_name'],
      metaSnapshot['name'],
      map['display_name'],
      map['name'],
    ], groupId: groupId);
    return GroupSummary(
      groupId: groupId,
      name: name ?? GroupDisplayName.fallback(groupId),
      description: _firstString(<Object?>[
        map['description'],
        body['description'],
        profile['description'],
        snapshot['description'],
        group['description'],
        bodyProfile['description'],
        bodySnapshot['description'],
        metaProfile['description'],
        metaSnapshot['description'],
      ]),
      memberCount:
          int.tryParse(
            _firstString(<Object?>[
              map['member_count'],
              map['members_count'],
              body['member_count'],
              body['members_count'],
              profile['member_count'],
              profile['members_count'],
              snapshot['member_count'],
              snapshot['members_count'],
              group['member_count'],
              group['members_count'],
            ]),
          ) ??
          0,
      lastMessageAt: parseDate(
        _firstNullableString(<Object?>[
          map['last_message_at'],
          map['updated_at'],
          map['created_at'],
          body['last_message_at'],
          body['updated_at'],
          body['created_at'],
          snapshot['last_message_at'],
          snapshot['updated_at'],
          snapshot['created_at'],
          group['last_message_at'],
          group['updated_at'],
          group['created_at'],
        ]),
      ),
      myRole: _firstNullableString(<Object?>[
        map['my_role'],
        map['role'],
        body['my_role'],
        body['role'],
        meta['my_role'],
        meta['role'],
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
          ? groupDisplayNameFromWire(
              item,
              groupId: groupId,
              fallback: GroupDisplayName.fallback(groupId),
            )
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
        ? groupDisplayNameFromWire(
            event,
            groupId: message.groupId,
            previousDisplayName: previous?.displayName,
            fallback: GroupDisplayName.fallback(message.groupId),
          )
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
      byThread[item.threadId] = _mergeConversation(
        previous: byThread[item.threadId],
        incoming: item,
      );
    }
    final merged = byThread.values.toList();
    merged.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return merged;
  }

  ConversationSummary _mergeConversation({
    required ConversationSummary? previous,
    required ConversationSummary incoming,
  }) {
    if (previous == null || !incoming.isGroup) {
      return incoming;
    }
    final groupId = incoming.groupId?.trim() ?? '';
    final previousName = previous.displayName.trim();
    if (groupId.isEmpty ||
        GroupDisplayName.isIdLike(previousName, groupId) ||
        !GroupDisplayName.isIdLike(incoming.displayName, groupId)) {
      return incoming;
    }
    return ConversationSummary(
      threadId: incoming.threadId,
      displayName: previous.displayName,
      lastMessagePreview: incoming.lastMessagePreview,
      lastMessageAt: incoming.lastMessageAt,
      unreadCount: incoming.unreadCount,
      isGroup: incoming.isGroup,
      targetDid: incoming.targetDid,
      groupId: incoming.groupId,
      avatarSeed: incoming.avatarSeed,
    );
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

  String groupIdFromWire(Map<String, Object?> item) {
    return _groupIdFromMessage(item);
  }

  String groupDisplayNameFromWire(
    Map<String, Object?> item, {
    String? groupId,
    String? previousDisplayName,
    String fallback = 'Group',
  }) {
    final body = _nestedMap(item['body']);
    final meta = _nestedMap(item['meta']);
    final group = _nestedMap(item['group']);
    final profile = _nestedMap(item['group_profile']);
    final snapshot = _nestedMap(item['group_snapshot']);
    final bodyProfile = _nestedMap(body['group_profile']);
    final bodySnapshot = _nestedMap(body['group_snapshot']);
    final metaProfile = _nestedMap(meta['group_profile']);
    final metaSnapshot = _nestedMap(meta['group_snapshot']);
    return GroupDisplayName.firstFriendly(<Object?>[
          item['group_name'],
          item['group_display_name'],
          body['group_name'],
          body['group_display_name'],
          profile['display_name'],
          profile['name'],
          snapshot['display_name'],
          snapshot['name'],
          group['display_name'],
          group['name'],
          bodyProfile['display_name'],
          bodyProfile['name'],
          bodySnapshot['display_name'],
          bodySnapshot['name'],
          metaProfile['display_name'],
          metaProfile['name'],
          metaSnapshot['display_name'],
          metaSnapshot['name'],
          previousDisplayName,
        ], groupId: groupId) ??
        fallback;
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
      meta['group_did'],
      meta['group_id'],
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
