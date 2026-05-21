import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/group_display_name.dart';
import '../awiki_sdk/awiki_anp_session.dart';
import '../awiki_sdk/awiki_message_client.dart';
import '../awiki_sdk/awiki_service_client.dart';
import '../awiki_sdk/awiki_service_error.dart';
import '../awiki_sdk/awiki_user_client.dart';
import '../awiki_sdk/awiki_wire_mapper.dart';
import '../services/awiki_local_cache.dart';
import '../../domain/entities/bridge_capabilities.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/realtime_update.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import '../../domain/repositories/awiki_gateway.dart';

enum _RelationshipDirection { followers, following }

class AwikiAnpGateway implements AwikiGateway {
  AwikiAnpGateway({
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required AwikiAccountGateway accountGateway,
    AwikiLocalCache? localCache,
    http.Client? httpClient,
    AwikiMessageClient? messageClient,
    AwikiUserClient? userClient,
    AwikiWireMapper mapper = const AwikiWireMapper(),
  }) : _httpClient = httpClient ?? http.Client(),
       _accountGateway = accountGateway,
       _localCache = localCache ?? AwikiLocalCache(),
       _mapper = mapper,
       _messageClient = messageClient,
       _userClient = userClient;

  factory AwikiAnpGateway.fromEnvironment({
    required AwikiAccountGateway accountGateway,
    AwikiLocalCache? localCache,
  }) {
    const userServiceUrl = String.fromEnvironment(
      'AWIKI_USER_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    );
    const messageServiceUrl = String.fromEnvironment(
      'AWIKI_MESSAGE_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    );
    return AwikiAnpGateway(
      userServiceUrl: userServiceUrl,
      messageServiceUrl: messageServiceUrl,
      accountGateway: accountGateway,
      localCache: localCache,
    );
  }

  final String userServiceUrl;
  final String messageServiceUrl;
  final http.Client _httpClient;
  final AwikiAccountGateway _accountGateway;
  final AwikiLocalCache _localCache;
  final AwikiWireMapper _mapper;
  final AwikiMessageClient? _messageClient;
  final AwikiUserClient? _userClient;

  static const int _maxInboxLimit = 100;

  String? _messageServiceDid;
  AwikiMessageClient? _messages;
  AwikiUserClient? _users;

  AwikiMessageClient get _messageService {
    return _messages ??=
        _messageClient ??
        AwikiMessageClient(
          serviceClient: AwikiServiceClient(
            baseUrl: messageServiceUrl,
            httpClient: _httpClient,
          ),
        );
  }

  AwikiUserClient get _userService {
    return _users ??=
        _userClient ??
        AwikiUserClient(
          serviceClient: AwikiServiceClient(
            baseUrl: userServiceUrl,
            httpClient: _httpClient,
          ),
          httpClient: _httpClient,
        );
  }

  @override
  Future<BridgeCapabilities> loadCapabilities() async {
    return const BridgeCapabilities(
      profileMarkdown: true,
      localDeleteOnly: true,
      systemPushStub: true,
      e2ee: E2eeCapability(
        supported: false,
        pluginRequired: false,
        enabledByDefault: false,
      ),
    );
  }

  @override
  Future<UserProfile> loadMyProfile() async {
    final session = await _requireSession();
    return _toUserProfile(
      await _userService.getMe(bearerToken: session.jwtToken ?? ''),
    );
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    final session = await _requireSession();
    return _toUserProfile(
      await _userService.updateMe(
        bearerToken: session.jwtToken ?? '',
        patch: <String, Object?>{
          if (patch.nickName != null) 'nick_name': patch.nickName,
          if (patch.bio != null) 'bio': patch.bio,
          if (patch.tags != null) 'tags': patch.tags,
          if (patch.profileMarkdown != null)
            'profile_md': patch.profileMarkdown,
        },
      ),
    );
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    final session = await _optionalSession();
    return _toUserProfile(
      await _userService.getPublicProfile(
        didOrHandle: didOrHandle,
        bearerToken: session?.jwtToken,
      ),
    );
  }

  @override
  Future<List<RelationshipSummary>> listFollowers() async {
    final result = await _withRefreshedSessionRetry(
      (session) => _userService.relationshipRpc(
        method: 'get_followers',
        params: const <String, Object?>{'limit': 100, 'offset': 0},
        bearerToken: session.jwtToken ?? '',
      ),
    );
    return _toRelationshipList(
      result,
      fallbackRelationship: 'follower',
      direction: _RelationshipDirection.followers,
    );
  }

  @override
  Future<List<RelationshipSummary>> listFollowing() async {
    final result = await _withRefreshedSessionRetry(
      (session) => _userService.relationshipRpc(
        method: 'get_following',
        params: const <String, Object?>{'limit': 100, 'offset': 0},
        bearerToken: session.jwtToken ?? '',
      ),
    );
    return _toRelationshipList(
      result,
      fallbackRelationship: 'following',
      direction: _RelationshipDirection.following,
    );
  }

  @override
  Future<void> follow(String didOrHandle) async {
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    _logGateway('follow input=$didOrHandle targetDid=$targetDid');
    await _withRefreshedSessionRetry(
      (session) => _userService.relationshipRpc(
        method: 'follow',
        params: <String, Object?>{'target_did': targetDid},
        bearerToken: session.jwtToken ?? '',
      ),
    );
  }

  @override
  Future<void> unfollow(String didOrHandle) async {
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    _logGateway('unfollow input=$didOrHandle targetDid=$targetDid');
    await _withRefreshedSessionRetry(
      (session) => _userService.relationshipRpc(
        method: 'unfollow',
        params: <String, Object?>{'target_did': targetDid},
        bearerToken: session.jwtToken ?? '',
      ),
    );
  }

  @override
  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle) async {
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    _logGateway('relationship.status input=$didOrHandle targetDid=$targetDid');
    final result = await _withRefreshedSessionRetry(
      (session) => _userService.relationshipRpc(
        method: 'get_status',
        params: <String, Object?>{'target_did': targetDid},
        bearerToken: session.jwtToken ?? '',
      ),
    );
    _logGateway('relationship.status result=${_compactDebugMap(result)}');
    final did = _firstNonEmpty(<Object?>[
      result['target_did'],
      result['to_did'],
      result['peer_did'],
      result['did'],
      targetDid,
    ]);
    return RelationshipSummary(
      did: did,
      displayName:
          result['display_name']?.toString() ??
          result['name']?.toString() ??
          did,
      relationship: result['status']?.toString() ?? 'none',
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final session = await _requireAnpSession();
    try {
      final inbox = await _messageService.getInbox(
        session: session,
        limit: _maxInboxLimit,
      );
      final messages = _extractMessages(inbox);
      final built = _mapper.conversationsFromInbox(
        messages: messages,
        ownerDid: session.did,
      );
      final cached = await _localCache.loadConversations(ownerDid: session.did);
      final merged = await _applyCachedGroupNames(
        ownerDid: session.did,
        conversations: _mapper.mergeConversations(cached, built),
      );
      await _localCache.upsertConversations(
        ownerDid: session.did,
        conversations: merged,
      );
      return merged;
    } catch (_) {
      final cached = await _localCache.loadConversations(ownerDid: session.did);
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<List<ChatMessage>> fetchDmHistory(String peerDid) async {
    final session = await _requireAnpSession();
    final threadId = _mapper.threadIdForPeer(
      ownerDid: session.did,
      peerDid: peerDid,
    );
    try {
      final result = await _messageService.getDirectHistory(
        session: session,
        peerDid: peerDid,
        limit: 100,
      );
      final messages =
          _extractMessages(result)
              .map((item) => _mapper.toChatMessage(item, ownerDid: session.did))
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _localCache.upsertMessages(
        ownerDid: session.did,
        threadId: threadId,
        messages: messages,
      );
      return messages;
    } catch (_) {
      final cached = await _localCache.loadMessages(
        ownerDid: session.did,
        threadId: threadId,
      );
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<List<ChatMessage>> fetchGroupHistory(String groupId) async {
    final session = await _requireAnpSession();
    final threadId = 'group:$groupId';
    try {
      final result = await _messageService.listGroupMessages(
        session: session,
        groupDid: groupId,
        limit: 100,
      );
      final messages =
          _extractMessages(result)
              .map(
                (item) => _mapper.toChatMessage(
                  item,
                  ownerDid: session.did,
                  forceThreadId: threadId,
                  forceGroupId: groupId,
                ),
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _localCache.upsertMessages(
        ownerDid: session.did,
        threadId: threadId,
        messages: messages,
      );
      return messages;
    } catch (_) {
      final cached = await _localCache.loadMessages(
        ownerDid: session.did,
        threadId: threadId,
      );
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
  }) async {
    final session = await _requireAnpSession(requireSigning: true);
    final identity = await _accountGateway.currentSession();
    final isGroup = groupId != null && groupId.isNotEmpty;
    _logGateway(
      'message.send threadId=$threadId isGroup=$isGroup peerDid=${peerDid ?? ''} groupId=${groupId ?? ''}',
    );
    final result = isGroup
        ? await _messageService.sendGroup(
            session: session,
            groupDid: groupId,
            text: content,
          )
        : await _messageService.sendDirect(
            session: session,
            targetDid: peerDid ?? '',
            text: content,
          );
    final createdAt =
        _mapper.parseDate(result['accepted_at'] ?? result['created_at']) ??
        DateTime.now();
    final remoteId =
        result['message_id']?.toString() ??
        result['id']?.toString() ??
        result['msg_id']?.toString();
    final sent = ChatMessage(
      localId: remoteId ?? 'local-${DateTime.now().microsecondsSinceEpoch}',
      remoteId: remoteId,
      threadId: threadId,
      senderDid: session.did,
      senderName: identity?.handle ?? identity?.displayName,
      receiverDid: peerDid,
      groupId: groupId,
      content: content,
      createdAt: createdAt,
      isMine: true,
      sendState: MessageSendState.sent,
      serverSequence: int.tryParse(
        result['server_seq']?.toString() ??
            result['group_event_seq']?.toString() ??
            '',
      ),
    );
    await _localCache.upsertMessages(
      ownerDid: session.did,
      threadId: threadId,
      messages: <ChatMessage>[sent],
    );
    final groupDisplayName = isGroup
        ? await _cachedGroupDisplayName(ownerDid: session.did, groupId: groupId)
        : null;
    await _localCache.upsertConversations(
      ownerDid: session.did,
      conversations: <ConversationSummary>[
        ConversationSummary(
          threadId: threadId,
          displayName: isGroup
              ? groupDisplayName ?? GroupDisplayName.fallback(groupId)
              : peerDid ?? threadId,
          lastMessagePreview: content,
          lastMessageAt: sent.createdAt,
          unreadCount: 0,
          isGroup: isGroup,
          targetDid: peerDid,
          groupId: groupId,
          avatarSeed: peerDid ?? groupId,
        ),
      ],
    );
    return sent;
  }

  @override
  Future<ChatMessage> retryMessage(ChatMessage message) {
    return sendTextMessage(
      threadId: message.threadId,
      peerDid: message.receiverDid,
      groupId: message.groupId,
      content: message.content,
    );
  }

  @override
  Future<void> markRead(String threadId) async {
    final session = await _requireAnpSession();
    final inbox = await _messageService.getInbox(
      session: session,
      limit: _maxInboxLimit,
    );
    final ids = <String>[];
    for (final item in _extractMessages(inbox)) {
      if (_mapper.threadIdForMessage(item, ownerDid: session.did) != threadId) {
        continue;
      }
      final id = _mapper.messageIdOf(item);
      if (id.isNotEmpty) {
        ids.add(id);
      }
    }
    if (ids.isNotEmpty) {
      await _messageService.markRead(session: session, messageIds: ids);
    }
    await _localCache.markThreadRead(ownerDid: session.did, threadId: threadId);
  }

  @override
  Future<void> deleteLocalThread(String threadId) async {
    final session = await _requireAnpSession();
    await _localCache.deleteThread(ownerDid: session.did, threadId: threadId);
  }

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
  }) async {
    final session = await _requireAnpSession(requireSigning: true);
    final serviceDid = await _resolveMessageServiceDid(session);
    final result = await _messageService.createGroup(
      session: session,
      serviceDid: serviceDid,
      name: name,
      slug: slug,
      description: description,
      goal: goal,
      rules: rules,
      messagePrompt: messagePrompt,
    );
    final created = _mapper.toGroupSummary(result);
    var summary = created;
    if (created.groupId.isNotEmpty) {
      try {
        summary = await getGroup(created.groupId);
      } catch (error) {
        _logGateway('group.create snapshot fallback: $error');
      }
    }
    await _localCache.upsertGroups(
      ownerDid: session.did,
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<GroupSummary> joinGroup(String groupDid) async {
    final normalizedGroupDid = groupDid.trim();
    if (!normalizedGroupDid.startsWith('did:')) {
      throw ArgumentError('请输入有效的 Group DID。');
    }
    final session = await _requireAnpSession(requireSigning: true);
    final result = await _messageService.joinGroup(
      session: session,
      groupDid: normalizedGroupDid,
    );
    final fallback = _mapper.toGroupSummary(<String, Object?>{
      ...result,
      'group_did': normalizedGroupDid,
    });
    var summary = fallback;
    try {
      summary = await getGroup(normalizedGroupDid);
    } catch (error) {
      _logGateway('group.join snapshot fallback: $error');
    }
    await _localCache.upsertGroups(
      ownerDid: session.did,
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberDid,
    String role = 'member',
  }) async {
    final normalizedGroupId = groupId.trim();
    final normalizedMemberDid = memberDid.trim();
    if (!normalizedGroupId.startsWith('did:')) {
      throw ArgumentError('请输入有效的 Group DID。');
    }
    if (!normalizedMemberDid.startsWith('did:')) {
      throw ArgumentError('请输入有效的成员 DID。');
    }
    final session = await _requireAnpSession(requireSigning: true);
    final result = await _messageService.addGroupMember(
      session: session,
      groupDid: normalizedGroupId,
      memberDid: normalizedMemberDid,
      role: role,
    );
    final fallback = _mapper.toGroupSummary(<String, Object?>{
      ...result,
      'group_did': normalizedGroupId,
    });
    var summary = fallback;
    try {
      summary = await getGroup(normalizedGroupId);
    } catch (error) {
      _logGateway('group.add snapshot fallback: $error');
    }
    await _localCache.upsertGroups(
      ownerDid: session.did,
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<GroupSummary> getGroup(String groupId) async {
    final session = await _requireAnpSession();
    final result = await _messageService.getGroup(
      session: session,
      groupDid: groupId,
    );
    final summary = _mapper.toGroupSummary(<String, Object?>{
      ...result,
      'group_did': groupId,
    });
    await _localCache.upsertGroups(
      ownerDid: session.did,
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<List<GroupSummary>> listGroups() async {
    final session = await _requireAnpSession();
    final cachedGroups = await _localCache.loadGroups(ownerDid: session.did);
    try {
      final inbox = await _messageService.getInbox(
        session: session,
        limit: _maxInboxLimit,
      );
      final grouped = <String, GroupSummary>{
        for (final item in cachedGroups) item.groupId: item,
      };
      for (final item in _extractMessages(inbox)) {
        final groupId = _mapper.groupIdFromWire(item);
        if (groupId.isEmpty) {
          continue;
        }
        final sentAt = _mapper.parseDate(
          item['sent_at'] ?? item['created_at'] ?? item['accepted_at'],
        );
        final current = grouped[groupId];
        if (current == null ||
            (sentAt != null &&
                (current.lastMessageAt ?? DateTime(1970)).isBefore(sentAt))) {
          final groupName = _mapper.groupDisplayNameFromWire(
            item,
            groupId: groupId,
            previousDisplayName: current?.name,
            fallback: GroupDisplayName.fallback(groupId),
          );
          grouped[groupId] = GroupSummary(
            groupId: groupId,
            name: groupName,
            description: _groupDescriptionFromWire(item, current),
            memberCount:
                int.tryParse(item['member_count']?.toString() ?? '') ?? 0,
            lastMessageAt: sentAt,
            myRole: current?.myRole,
          );
        }
      }
      for (final entry in List<MapEntry<String, GroupSummary>>.from(
        grouped.entries,
      )) {
        final group = entry.value;
        if (!GroupDisplayName.isIdLike(group.name, group.groupId)) {
          continue;
        }
        try {
          grouped[entry.key] = await getGroup(group.groupId);
        } catch (error) {
          _logGateway('group.list snapshot fallback: $error');
        }
      }
      final merged = grouped.values.toList()
        ..sort(
          (a, b) => (b.lastMessageAt ?? DateTime(1970)).compareTo(
            a.lastMessageAt ?? DateTime(1970),
          ),
        );
      await _localCache.upsertGroups(ownerDid: session.did, groups: merged);
      return merged;
    } catch (_) {
      if (cachedGroups.isNotEmpty) {
        return cachedGroups;
      }
      rethrow;
    }
  }

  @override
  Future<List<GroupMemberSummary>> listGroupMembers(String groupId) async {
    final session = await _requireAnpSession();
    final result = await _messageService.listGroupMembers(
      session: session,
      groupDid: groupId,
    );
    return _mapper
        .mapList(result['members'] ?? result['items'] ?? result)
        .map(_mapper.toGroupMemberSummary)
        .where((item) => item.did.isNotEmpty)
        .toList();
  }

  Future<SessionIdentity> _requireSession() async {
    final session = await _accountGateway.currentSession();
    if (session == null || session.did.isEmpty) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    return session;
  }

  Future<SessionIdentity?> _optionalSession() {
    return _accountGateway.currentSession();
  }

  Future<T> _withRefreshedSessionRetry<T>(
    Future<T> Function(SessionIdentity session) action,
  ) async {
    final session = await _requireSession();
    try {
      return await action(session);
    } catch (error) {
      if (!_isExpiredAuthError(error)) {
        rethrow;
      }
      final refreshed = await _accountGateway.refreshSession();
      if (refreshed == null || refreshed.jwtToken?.isNotEmpty != true) {
        throw StateError('登录状态已失效，请重新登录。');
      }
      return action(refreshed);
    }
  }

  bool _isExpiredAuthError(Object error) {
    if (error is! AwikiServiceError || !error.isUnauthorized) {
      return false;
    }
    final normalized = error.message.toLowerCase();
    return normalized.contains('token has expired') ||
        normalized.contains('token expired') ||
        normalized.contains('expired');
  }

  UserProfile _toUserProfile(Map<String, Object?> result) {
    return UserProfile(
      did: result['did']?.toString() ?? '',
      nickName:
          result['nick_name']?.toString() ?? result['name']?.toString() ?? '',
      bio: result['bio']?.toString() ?? '',
      tags: _toStringList(result['tags']),
      profileMarkdown: result['profile_md']?.toString() ?? '',
      handle: result['handle']?.toString(),
      region: result['region']?.toString(),
    );
  }

  List<String> _toStringList(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const <String>[];
  }

  List<RelationshipSummary> _toRelationshipList(
    Map<String, Object?> result, {
    required String fallbackRelationship,
    required _RelationshipDirection direction,
  }) {
    final rows = _extractRelationshipRows(result);
    _logGateway(
      'relationship.list direction=${direction.name} count=${rows.length} raw=${_compactDebugMap(result)}',
    );
    return rows
        .expand((item) {
          final did = _relationshipDid(item, direction);
          if (!_isE1Did(did)) {
            _logGateway(
              'relationship.row.skip_legacy direction=${direction.name} did=$did fields=${_compactDebugMap(item)}',
            );
            return const <RelationshipSummary>[];
          }
          final name =
              item['display_name']?.toString() ??
              item['name']?.toString() ??
              item['nick_name']?.toString() ??
              item['handle']?.toString() ??
              did;
          _logGateway(
            'relationship.row direction=${direction.name} did=$did name=$name fields=${_compactDebugMap(item)}',
          );
          return <RelationshipSummary>[
            RelationshipSummary(
              did: did,
              displayName: name,
              relationship:
                  item['relationship']?.toString() ??
                  item['status']?.toString() ??
                  fallbackRelationship,
            ),
          ];
        })
        .where((item) => item.did.isNotEmpty)
        .toList();
  }

  String _relationshipDid(
    Map<String, Object?> item,
    _RelationshipDirection direction,
  ) {
    final preferred = direction == _RelationshipDirection.following
        ? <Object?>[
            item['target_did'],
            item['to_did'],
            item['following_did'],
            item['followed_did'],
            item['peer_did'],
            item['did'],
            item['user_did'],
            item['from_did'],
          ]
        : <Object?>[
            item['from_did'],
            item['follower_did'],
            item['user_did'],
            item['peer_did'],
            item['did'],
            item['target_did'],
            item['to_did'],
          ];
    return _firstNonEmpty(preferred);
  }

  String _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  void _ensureE1Did(String did) {
    if (!_isE1Did(did)) {
      throw StateError('当前仅支持新版 e1 DID，无法添加旧版账号。');
    }
  }

  bool _isE1Did(String did) {
    final parts = did.split(':');
    return parts.isNotEmpty && parts.last.startsWith('e1_');
  }

  List<Map<String, Object?>> _extractRelationshipRows(Object? raw) {
    final direct = _mapper.mapList(raw);
    if (direct.isNotEmpty) {
      return direct;
    }
    if (raw is! Map) {
      return const <Map<String, Object?>>[];
    }
    final map = raw.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    const keys = <String>[
      'items',
      'list',
      'followers',
      'following',
      'results',
      'records',
      'relationships',
      'users',
      'data',
    ];
    for (final key in keys) {
      final rows = _extractRelationshipRows(map[key]);
      if (rows.isNotEmpty) {
        return rows;
      }
    }
    return const <Map<String, Object?>>[];
  }

  Future<String> _resolveDidOrHandle(String value) async {
    if (value.startsWith('did:')) {
      _ensureE1Did(value);
      return value;
    }
    final session = await _optionalSession();
    Map<String, Object?> result;
    try {
      result = await _userService.getPublicProfile(
        didOrHandle: value,
        bearerToken: session?.jwtToken,
      );
    } catch (error) {
      if (!_isExpiredAuthError(error)) {
        rethrow;
      }
      final refreshed = await _accountGateway.refreshSession();
      result = await _userService.getPublicProfile(
        didOrHandle: value,
        bearerToken: refreshed?.jwtToken,
      );
    }
    final did = result['did']?.toString() ?? '';
    if (did.isEmpty) {
      throw StateError('Failed to resolve handle to DID: $value');
    }
    _ensureE1Did(did);
    _logGateway(
      'resolve input=$value did=$did result=${_compactDebugMap(result)}',
    );
    return did;
  }

  @override
  Future<RealtimeUpdate?> consumeRealtimeEvent(
    Map<String, Object?> event,
  ) async {
    final session = await _requireAnpSession();
    final normalized = _normalizeRealtimeEvent(event);
    final senderDid = normalized['sender_did']?.toString() ?? '';
    final groupId =
        normalized['group_did']?.toString() ??
        normalized['group_id']?.toString() ??
        '';
    if (senderDid.isEmpty && groupId.isEmpty) {
      return null;
    }

    final message = _mapper.toChatMessage(normalized, ownerDid: session.did);
    final existingConversation = await _loadConversationByThread(
      ownerDid: session.did,
      threadId: message.threadId,
    );
    final cachedGroupName = groupId.isNotEmpty
        ? await _cachedGroupDisplayName(ownerDid: session.did, groupId: groupId)
        : null;
    final mappingEvent = cachedGroupName == null
        ? normalized
        : <String, Object?>{...normalized, 'group_name': cachedGroupName};
    final conversation = _mapper.conversationFromMessage(
      message: message,
      ownerDid: session.did,
      previous: existingConversation,
      event: mappingEvent,
    );
    await _localCache.upsertMessages(
      ownerDid: session.did,
      threadId: message.threadId,
      messages: <ChatMessage>[message],
    );
    await _localCache.upsertConversations(
      ownerDid: session.did,
      conversations: <ConversationSummary>[conversation],
    );

    GroupSummary? group;
    if ((message.groupId ?? '').isNotEmpty) {
      final groupName = _mapper.groupDisplayNameFromWire(
        mappingEvent,
        previousDisplayName: existingConversation?.displayName,
        fallback: GroupDisplayName.fallback(message.groupId),
      );
      group = GroupSummary(
        groupId: message.groupId!,
        name: groupName,
        description: normalized['group_description']?.toString() ?? '',
        memberCount:
            int.tryParse(normalized['member_count']?.toString() ?? '') ?? 0,
        lastMessageAt: message.createdAt,
        myRole: normalized['my_role']?.toString(),
      );
      await _localCache.upsertGroups(
        ownerDid: session.did,
        groups: <GroupSummary>[group],
      );
    }
    return RealtimeUpdate(
      message: message,
      conversation: conversation,
      group: group,
    );
  }

  Future<AwikiAnpSession> _requireAnpSession({bool requireSigning = false}) {
    return _accountGateway.currentAnpSession(requireSigning: requireSigning);
  }

  void _logGateway(String message) {
    debugPrint('[awiki_me.anp] $message');
    developer.log(message, name: 'awiki_me.anp');
  }

  String _compactDebugMap(Map<String, Object?> map) {
    const interestingKeys = <String>{
      'did',
      'target_did',
      'user_did',
      'from_did',
      'to_did',
      'peer_did',
      'follower_did',
      'following_did',
      'followed_did',
      'display_name',
      'name',
      'nick_name',
      'handle',
      'status',
      'relationship',
      'items',
      'list',
      'followers',
      'following',
      'relationships',
    };
    return <String, Object?>{
      for (final entry in map.entries)
        if (interestingKeys.contains(entry.key)) entry.key: entry.value,
    }.toString();
  }

  Future<String> _resolveMessageServiceDid(AwikiAnpSession session) async {
    final cached = _messageServiceDid;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    try {
      final capabilities = await _messageService.getCapabilities(
        session: session,
      );
      final serviceDid = capabilities['service_did']?.toString() ?? '';
      if (serviceDid.isNotEmpty) {
        _messageServiceDid = serviceDid;
        return serviceDid;
      }
    } catch (_) {
      // Fall back to the default service DID derived from the message service host.
    }
    final host = Uri.tryParse(messageServiceUrl)?.host ?? '';
    if (host.isEmpty) {
      throw StateError('Unable to resolve message service DID.');
    }
    _messageServiceDid = 'did:wba:$host';
    return _messageServiceDid!;
  }

  List<Map<String, Object?>> _extractMessages(Map<String, Object?> result) {
    return _mapper.mapList(
      result['messages'] ?? result['items'] ?? result['records'] ?? result,
    );
  }

  Future<ConversationSummary?> _loadConversationByThread({
    required String ownerDid,
    required String threadId,
  }) async {
    final conversations = await _localCache.loadConversations(
      ownerDid: ownerDid,
    );
    for (final item in conversations) {
      if (item.threadId == threadId) {
        return item;
      }
    }
    return null;
  }

  Future<String?> _cachedGroupDisplayName({
    required String ownerDid,
    required String? groupId,
  }) async {
    final normalizedGroupId = groupId?.trim() ?? '';
    if (normalizedGroupId.isEmpty) {
      return null;
    }
    final groups = await _localCache.loadGroups(ownerDid: ownerDid);
    for (final group in groups) {
      if (group.groupId == normalizedGroupId &&
          !GroupDisplayName.isIdLike(group.name, normalizedGroupId)) {
        return group.name;
      }
    }
    final conversations = await _localCache.loadConversations(
      ownerDid: ownerDid,
    );
    for (final conversation in conversations) {
      if (conversation.groupId == normalizedGroupId &&
          !GroupDisplayName.isIdLike(
            conversation.displayName,
            normalizedGroupId,
          )) {
        return conversation.displayName;
      }
    }
    return null;
  }

  Future<List<ConversationSummary>> _applyCachedGroupNames({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    final groups = await _localCache.loadGroups(ownerDid: ownerDid);
    if (groups.isEmpty) {
      return conversations;
    }
    final groupNamesById = <String, String>{
      for (final group in groups)
        if (!GroupDisplayName.isIdLike(group.name, group.groupId))
          group.groupId: group.name,
    };
    if (groupNamesById.isEmpty) {
      return conversations;
    }
    return conversations.map((conversation) {
      final groupId = conversation.groupId?.trim() ?? '';
      final groupName = groupNamesById[groupId];
      if (!conversation.isGroup ||
          groupName == null ||
          groupName == conversation.displayName) {
        return conversation;
      }
      return ConversationSummary(
        threadId: conversation.threadId,
        displayName: groupName,
        lastMessagePreview: conversation.lastMessagePreview,
        lastMessageAt: conversation.lastMessageAt,
        unreadCount: conversation.unreadCount,
        isGroup: conversation.isGroup,
        targetDid: conversation.targetDid,
        groupId: conversation.groupId,
        avatarSeed: conversation.avatarSeed,
      );
    }).toList();
  }

  String _groupDescriptionFromWire(
    Map<String, Object?> item,
    GroupSummary? current,
  ) {
    final body = _asStringKeyMap(item['body']);
    final group = _asStringKeyMap(item['group']);
    final profile = _asStringKeyMap(item['group_profile']);
    final snapshot = _asStringKeyMap(item['group_snapshot']);
    final bodyProfile = _asStringKeyMap(body['group_profile']);
    final bodySnapshot = _asStringKeyMap(body['group_snapshot']);
    return _firstString(<Object?>[
      item['group_description'],
      item['description'],
      body['group_description'],
      body['description'],
      profile['description'],
      snapshot['description'],
      group['description'],
      bodyProfile['description'],
      bodySnapshot['description'],
      current?.description,
    ]);
  }

  String _firstString(List<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return fallback;
  }

  Map<String, Object?> _normalizeRealtimeEvent(Map<String, Object?> event) {
    final params = event['params'];
    final meta = event['meta'];
    final body = event['body'];
    final message = event['message'];
    final normalized = <String, Object?>{};
    void merge(Object? value) {
      if (value is Map) {
        normalized.addAll(
          value.map<String, Object?>(
            (key, entryValue) => MapEntry(key.toString(), entryValue),
          ),
        );
      }
    }

    merge(event);
    merge(params);
    merge(meta);
    merge(body);
    merge(message);
    final normalizedMeta = _asStringKeyMap(meta);
    final normalizedTarget = _asStringKeyMap(normalizedMeta['target']);
    final targetDid = normalizedTarget['did']?.toString() ?? '';
    if (targetDid.isNotEmpty) {
      final targetKind = normalizedTarget['kind']?.toString() ?? '';
      if (targetKind == 'group') {
        normalized.putIfAbsent('group_did', () => targetDid);
      } else {
        normalized.putIfAbsent('target_did', () => targetDid);
      }
    }
    return normalized;
  }

  Map<String, Object?> _asStringKeyMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return value.map<String, Object?>(
      (key, entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
}
