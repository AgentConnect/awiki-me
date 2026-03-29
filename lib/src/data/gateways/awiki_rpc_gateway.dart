import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../data/services/awiki_local_cache.dart';
import '../../data/services/credential_archive_service.dart';
import '../../data/services/document_picker_service.dart';
import '../../data/services/noop_did_registration_facade.dart';
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
import '../../domain/repositories/awiki_gateway.dart';
import '../../domain/services/did_registration_facade.dart';

class AwikiRpcGateway implements AwikiGateway {
  static const Duration _networkTimeout = Duration(seconds: 20);
  static const String _credentialsDirectoryName = 'awiki_me';

  AwikiRpcGateway({
    required this.userServiceUrl,
    required this.messageServiceUrl,
    FlutterSecureStorage? secureStorage,
    AwikiLocalCache? localCache,
    DidRegistrationFacade? didRegistrationFacade,
    CredentialArchiveService? credentialArchiveService,
    DocumentPickerService? documentPickerService,
    SessionIdentity? initialSession,
    http.Client? httpClient,
    String? localCredentialsRootPath,
  })  : _httpClient = httpClient ?? http.Client(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _localCache = localCache ?? AwikiLocalCache(),
        _credentialArchiveService =
            credentialArchiveService ?? CredentialArchiveService(),
        _documentPickerService = documentPickerService,
        _didRegistrationFacade =
            didRegistrationFacade ?? NoopDidRegistrationFacade(),
        _session = initialSession,
        _localCredentialsRootPathOverride = localCredentialsRootPath;

  factory AwikiRpcGateway.fromEnvironment({
    AwikiLocalCache? localCache,
    DidRegistrationFacade? didRegistrationFacade,
    DocumentPickerService? documentPickerService,
  }) {
    const userServiceUrl = String.fromEnvironment(
      'AWIKI_USER_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    );
    const messageServiceUrl = String.fromEnvironment(
      'AWIKI_MESSAGE_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    );
    return AwikiRpcGateway(
      userServiceUrl: userServiceUrl,
      messageServiceUrl: messageServiceUrl,
      localCache: localCache,
      didRegistrationFacade: didRegistrationFacade,
      documentPickerService: documentPickerService,
    );
  }

  final String userServiceUrl;
  final String messageServiceUrl;
  final http.Client _httpClient;
  final FlutterSecureStorage _secureStorage;
  final AwikiLocalCache _localCache;
  final CredentialArchiveService _credentialArchiveService;
  final DocumentPickerService? _documentPickerService;
  final DidRegistrationFacade _didRegistrationFacade;
  final Random _random = Random();
  final String? _localCredentialsRootPathOverride;
  static const int _maxInboxLimit = 100;

  static const String _sessionDidKey = 'awiki_me_session_did';
  static const String _sessionTokenKey = 'awiki_me_session_token';
  static const String _sessionCredentialKey = 'awiki_me_session_credential';
  static const String _sessionDisplayNameKey = 'awiki_me_session_display_name';
  static const String _sessionHandleKey = 'awiki_me_session_handle';
  static const String _savedCredentialsKey = 'awiki_me_saved_credentials';
  static const String _sessionDidDocumentKey = 'awiki_me_session_did_document';
  static const String _sessionPrivateKeyPemKey =
      'awiki_me_session_private_key_pem';
  static const String _sessionDidDomainKey = 'awiki_me_session_did_domain';

  SessionIdentity? _session;

  @override
  Future<BridgeCapabilities> loadCapabilities() async {
    return const BridgeCapabilities(
      profileMarkdown: true,
      groupJoinCode: true,
      localDeleteOnly: true,
      systemPushStub: true,
      e2ee: E2eeCapability(
        supported: false,
        pluginRequired: true,
        enabledByDefault: false,
      ),
    );
  }

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    String? groupMode,
  }) async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'create',
      params: <String, Object?>{
        'name': name,
        'slug': slug,
        'description': description,
        'goal': goal,
        'rules': rules,
        if (messagePrompt != null && messagePrompt.isNotEmpty)
          'message_prompt': messagePrompt,
        if (groupMode != null && groupMode.isNotEmpty) 'group_mode': groupMode,
        'join_enabled': true,
      },
      authRequired: true,
    );
    final created = _toGroupSummary(result);
    final summary =
        created.groupId.isNotEmpty ? await getGroup(created.groupId) : created;
    await _localCache.upsertGroups(
      ownerDid: _requireDid(),
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<void> deleteLocalThread(String threadId) async {
    await _localCache.deleteThread(
      ownerDid: _requireDid(),
      threadId: threadId,
    );
  }

  @override
  Future<List<ChatMessage>> fetchDmHistory(String peerDid) async {
    final did = _requireDid();
    final threadId = _threadIdForPeer(ownerDid: did, peerDid: peerDid);
    try {
      final result = await _rpcCall(
        baseUrl: messageServiceUrl,
        path: '/message/rpc',
        method: 'get_history',
        params: <String, Object?>{
          'user_did': did,
          'peer_did': peerDid,
          'limit': 100,
        },
        authRequired: true,
      );
      final messages = _toMapList(result['messages'])
          .map((item) => _toChatMessage(item, did: did))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _localCache.upsertMessages(
        ownerDid: did,
        threadId: threadId,
        messages: messages,
      );
      return messages;
    } catch (_) {
      final cached = await _localCache.loadMessages(
        ownerDid: did,
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
    final did = _requireDid();
    final threadId = 'group:$groupId';
    try {
      final result = await _rpcCall(
        baseUrl: userServiceUrl,
        path: '/group/rpc',
        method: 'list_messages',
        params: <String, Object?>{
          'group_id': groupId,
          'limit': 100,
        },
        authRequired: true,
      );
      final messages = _toMapList(result['messages'])
          .map(
            (item) => _toChatMessage(
              item,
              did: did,
              forceThreadId: threadId,
              groupId: groupId,
            ),
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _localCache.upsertMessages(
        ownerDid: did,
        threadId: threadId,
        messages: messages,
      );
      return messages;
    } catch (_) {
      final cached = await _localCache.loadMessages(
        ownerDid: did,
        threadId: threadId,
      );
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<void> follow(String didOrHandle) async {
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/relationships/rpc',
      method: 'follow',
      params: <String, Object?>{'target_did': targetDid},
      authRequired: true,
    );
  }

  @override
  Future<List<RelationshipSummary>> listFollowers() async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/relationships/rpc',
      method: 'get_followers',
      params: const <String, Object?>{'limit': 100, 'offset': 0},
      authRequired: true,
    );
    return _toRelationshipList(result, fallbackRelationship: 'follower');
  }

  @override
  Future<List<RelationshipSummary>> listFollowing() async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/relationships/rpc',
      method: 'get_following',
      params: const <String, Object?>{'limit': 100, 'offset': 0},
      authRequired: true,
    );
    return _toRelationshipList(result, fallbackRelationship: 'following');
  }

  @override
  Future<List<GroupMemberSummary>> listGroupMembers(String groupId) async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'list_members',
      params: <String, Object?>{'group_id': groupId},
      authRequired: true,
    );
    final members = _toMapList(result['members']);
    return members
        .map(
          (item) => GroupMemberSummary(
            userId: item['user_id']?.toString() ?? '',
            did:
                item['did']?.toString() ?? item['member_did']?.toString() ?? '',
            handle: item['handle']?.toString() ??
                item['member_handle']?.toString() ??
                '',
            role: item['role']?.toString() ?? 'member',
            profileUrl: item['profile_url']?.toString(),
          ),
        )
        .toList();
  }

  @override
  Future<GroupSummary> getGroup(String groupId) async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'get',
      params: <String, Object?>{'group_id': groupId},
      authRequired: true,
    );
    final summary = _toGroupSummary(result);
    await _localCache.upsertGroups(
      ownerDid: _requireDid(),
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<String?> getGroupJoinCode(String groupId) async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'get_join_code',
      params: <String, Object?>{'group_id': groupId},
      authRequired: true,
    );
    final summary = _toGroupSummary(<String, Object?>{
      ...result,
      'group_id': groupId,
    });
    await _localCache.upsertGroups(
      ownerDid: _requireDid(),
      groups: <GroupSummary>[summary],
    );
    return result['join_code']?.toString() ?? result['passcode']?.toString();
  }

  @override
  Future<String?> refreshGroupJoinCode(String groupId) async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'refresh_join_code',
      params: <String, Object?>{'group_id': groupId},
      authRequired: true,
    );
    final summary = _toGroupSummary(<String, Object?>{
      ...result,
      'group_id': groupId,
    });
    await _localCache.upsertGroups(
      ownerDid: _requireDid(),
      groups: <GroupSummary>[summary],
    );
    return result['join_code']?.toString() ?? result['passcode']?.toString();
  }

  @override
  Future<List<GroupSummary>> listGroups() async {
    final ownerDid = _requireDid();
    final cachedGroups = await _localCache.loadGroups(ownerDid: ownerDid);
    try {
      final inbox = await _rpcCall(
        baseUrl: messageServiceUrl,
        path: '/message/rpc',
        method: 'get_inbox',
        params: <String, Object?>{
          'user_did': ownerDid,
          'limit': _maxInboxLimit,
        },
        authRequired: true,
      );
      final messages = _toMapList(inbox['messages']);
      final grouped = <String, GroupSummary>{
        for (final item in cachedGroups) item.groupId: item,
      };
      for (final item in messages) {
        final groupId = item['group_id']?.toString();
        if (groupId == null || groupId.isEmpty) {
          continue;
        }
        final sentAt = _parseDate(item['sent_at'] ?? item['created_at']);
        final current = grouped[groupId];
        if (current == null ||
            (sentAt != null &&
                (current.lastMessageAt ?? DateTime(1970)).isBefore(sentAt))) {
          grouped[groupId] = GroupSummary(
            groupId: groupId,
            name: item['group_name']?.toString() ?? 'Group $groupId',
            description: item['group_description']?.toString() ?? '',
            memberCount:
                int.tryParse(item['member_count']?.toString() ?? '') ?? 0,
            lastMessageAt: sentAt,
            myRole: current?.myRole,
          );
        }
      }
      final merged = grouped.values.toList()
        ..sort(
          (a, b) => (b.lastMessageAt ?? DateTime(1970))
              .compareTo(a.lastMessageAt ?? DateTime(1970)),
        );
      await _localCache.upsertGroups(ownerDid: ownerDid, groups: merged);
      return merged;
    } catch (_) {
      if (cachedGroups.isNotEmpty) {
        return cachedGroups;
      }
      rethrow;
    }
  }

  @override
  Future<RealtimeUpdate?> consumeRealtimeEvent(
    Map<String, Object?> event,
  ) async {
    final ownerDid = _session?.did;
    if (ownerDid == null || ownerDid.isEmpty) {
      return null;
    }

    final senderDid = event['sender_did']?.toString() ?? '';
    final groupId = event['group_id']?.toString() ?? '';
    if (senderDid.isEmpty && groupId.isEmpty) {
      return null;
    }

    final message = _toChatMessage(event, did: ownerDid);
    final existingConversation = await _loadConversationByThread(
      ownerDid: ownerDid,
      threadId: message.threadId,
    );
    final conversation = _conversationFromRealtimeEvent(
      event,
      ownerDid: ownerDid,
      message: message,
      previous: existingConversation,
    );

    await _localCache.upsertMessages(
      ownerDid: ownerDid,
      threadId: message.threadId,
      messages: <ChatMessage>[message],
    );
    await _localCache.upsertConversations(
      ownerDid: ownerDid,
      conversations: <ConversationSummary>[conversation],
    );

    GroupSummary? group;
    if ((message.groupId ?? '').isNotEmpty) {
      group = GroupSummary(
        groupId: message.groupId!,
        name: event['group_name']?.toString() ??
            existingConversation?.displayName ??
            'Group ${message.groupId}',
        description: event['group_description']?.toString() ?? '',
        memberCount: int.tryParse(event['member_count']?.toString() ?? '') ?? 0,
        lastMessageAt: message.createdAt,
        myRole: event['my_role']?.toString(),
      );
      await _localCache.upsertGroups(
        ownerDid: ownerDid,
        groups: <GroupSummary>[group],
      );
    }

    return RealtimeUpdate(
      message: message,
      conversation: conversation,
      group: group,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final did = _requireDid();
    try {
      final inbox = await _rpcCall(
        baseUrl: messageServiceUrl,
        path: '/message/rpc',
        method: 'get_inbox',
        params: <String, Object?>{
          'user_did': did,
          'limit': _maxInboxLimit,
        },
        authRequired: true,
      );
      final built = _buildConversationsFromInbox(
        messages: _toMapList(inbox['messages']),
        ownerDid: did,
      );
      final cached = await _localCache.loadConversations(ownerDid: did);
      final merged = _mergeConversations(cached, built);
      await _localCache.upsertConversations(
        ownerDid: did,
        conversations: merged,
      );
      return merged;
    } catch (_) {
      final cached = await _localCache.loadConversations(ownerDid: did);
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<UserProfile> loadMyProfile() async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/profile/rpc',
      method: 'get_me',
      params: const <String, Object?>{},
      authRequired: true,
    );
    return UserProfile(
      did: (result['did'] ?? '') as String,
      nickName: (result['nick_name'] ?? result['name'] ?? '') as String,
      bio: (result['bio'] ?? '') as String,
      tags: ((result['tags'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      profileMarkdown: (result['profile_md'] ?? '') as String,
      handle: result['handle']?.toString(),
      region: result['region']?.toString(),
    );
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    final params = didOrHandle.startsWith('did:')
        ? <String, Object?>{'did': didOrHandle}
        : <String, Object?>{'handle': didOrHandle};

    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/profile/rpc',
      method: 'get_public_profile',
      params: params,
      authRequired: true,
    );
    return UserProfile(
      did: (result['did'] ?? '') as String,
      nickName: (result['nick_name'] ?? result['name'] ?? '') as String,
      bio: (result['bio'] ?? '') as String,
      tags: ((result['tags'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      profileMarkdown: (result['profile_md'] ?? '') as String,
      handle: result['handle']?.toString(),
      region: result['region']?.toString(),
    );
  }

  @override
  Future<void> markRead(String threadId) async {
    final did = _requireDid();
    final inbox = await _rpcCall(
      baseUrl: messageServiceUrl,
      path: '/message/rpc',
      method: 'get_inbox',
      params: <String, Object?>{
        'user_did': did,
        'limit': _maxInboxLimit,
      },
      authRequired: true,
    );
    final messages = _toMapList(inbox['messages']);
    final ids = <String>[];
    for (final item in messages) {
      if (_threadIdForMessage(item, ownerDid: did) != threadId) {
        continue;
      }
      final msgId = item['id']?.toString() ?? item['msg_id']?.toString() ?? '';
      if (msgId.isNotEmpty) {
        ids.add(msgId);
      }
    }
    if (ids.isEmpty) {
      return;
    }
    await _rpcCall(
      baseUrl: messageServiceUrl,
      path: '/message/rpc',
      method: 'mark_read',
      params: <String, Object?>{
        'user_did': did,
        'message_ids': ids,
      },
      authRequired: true,
    );
    await _localCache.markThreadRead(ownerDid: did, threadId: threadId);
  }

  @override
  Future<SessionIdentity> registerHandle({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedPhone = _normalizePhone(phone);
    final sanitizedOtp = _sanitizeOtp(otp);
    return _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        phone: normalizedPhone,
        otp: sanitizedOtp,
        handle: normalizedHandle,
        inviteCode: inviteCode,
        nickName: nickName,
      ),
      authParams: <String, Object?>{
        'phone': normalizedPhone,
        'otp_code': sanitizedOtp,
      },
      handle: normalizedHandle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  @override
  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedEmail = email.trim().toLowerCase();
    return _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        email: normalizedEmail,
        handle: normalizedHandle,
        inviteCode: inviteCode,
        nickName: nickName,
      ),
      authParams: <String, Object?>{
        'email': normalizedEmail,
      },
      handle: normalizedHandle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  @override
  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedPhone = _normalizePhone(phone);
    final sanitizedOtp = _sanitizeOtp(otp);
    return _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        phone: normalizedPhone,
        otp: sanitizedOtp,
        handle: normalizedHandle,
      ),
      authParams: <String, Object?>{
        'phone': normalizedPhone,
        'otp_code': sanitizedOtp,
      },
      handle: normalizedHandle,
      rpcMethod: 'recover_handle',
    );
  }

  @override
  Future<SessionIdentity?> restoreSession() async {
    if (_session != null) {
      return _session;
    }

    final did = await _secureStorage.read(key: _sessionDidKey) ??
        const String.fromEnvironment('AWIKI_DID', defaultValue: '');
    final token = await _secureStorage.read(key: _sessionTokenKey) ??
        const String.fromEnvironment('AWIKI_ACCESS_TOKEN', defaultValue: '');
    if (did.isEmpty || token.isEmpty) {
      return null;
    }

    final credentialName =
        await _secureStorage.read(key: _sessionCredentialKey) ??
            const String.fromEnvironment('AWIKI_CREDENTIAL_NAME',
                defaultValue: 'default');
    final displayName =
        await _secureStorage.read(key: _sessionDisplayNameKey) ??
            const String.fromEnvironment('AWIKI_DISPLAY_NAME',
                defaultValue: 'awikime');
    final handle = await _secureStorage.read(key: _sessionHandleKey) ??
        const String.fromEnvironment('AWIKI_HANDLE', defaultValue: '');

    _session = SessionIdentity(
      did: did,
      credentialName: credentialName,
      displayName: displayName,
      handle: handle.isEmpty ? null : handle,
      jwtToken: token,
    );
    await _persistSession(_session!);
    await _hydrateStoredIdentityMaterialFromCredential(credentialName);
    await _refreshSessionOnRestore();
    return _session;
  }

  @override
  Future<void> logout() async {
    _session = null;
    await _secureStorage.delete(key: _sessionDidKey);
    await _secureStorage.delete(key: _sessionTokenKey);
    await _secureStorage.delete(key: _sessionCredentialKey);
    await _secureStorage.delete(key: _sessionDisplayNameKey);
    await _secureStorage.delete(key: _sessionHandleKey);
    await _secureStorage.delete(key: _sessionDidDocumentKey);
    await _secureStorage.delete(key: _sessionPrivateKeyPemKey);
    await _secureStorage.delete(key: _sessionDidDomainKey);
  }

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async {
    final catalogSessions = await _loadSavedCredentialsFromStorage();
    try {
      final rootPath = await _localCredentialsRootPath();
      if (rootPath.isEmpty) {
        return catalogSessions;
      }
      final rootDir = Directory(rootPath);
      if (!await rootDir.exists()) {
        return catalogSessions;
      }

      final indexFile = File('$rootPath/index.json');
      if (!await indexFile.exists()) {
        return catalogSessions;
      }
      final indexPayload = jsonDecode(await indexFile.readAsString());
      if (indexPayload is! Map) {
        return const <SessionIdentity>[];
      }
      final index = indexPayload.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final defaultCredentialName =
          index['default_credential_name']?.toString() ?? '';
      final rawCredentials = index['credentials'];
      if (rawCredentials is! Map) {
        return const <SessionIdentity>[];
      }

      final sessions = <SessionIdentity>[];
      for (final entry in rawCredentials.entries) {
        final credentialName = entry.key.toString();
        final detail = entry.value;
        if (detail is! Map) {
          continue;
        }
        final map = detail.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        final dirName = map['dir_name']?.toString() ?? '';
        if (dirName.isEmpty) {
          continue;
        }
        final identityFile = File('$rootPath/$dirName/identity.json');
        final authFile = File('$rootPath/$dirName/auth.json');
        if (!await identityFile.exists() || !await authFile.exists()) {
          continue;
        }
        final identityRaw = jsonDecode(await identityFile.readAsString());
        final authRaw = jsonDecode(await authFile.readAsString());
        if (identityRaw is! Map || authRaw is! Map) {
          continue;
        }
        final identity = identityRaw.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        final auth = authRaw.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        final did = identity['did']?.toString() ?? map['did']?.toString() ?? '';
        final token = auth['jwt_token']?.toString() ?? '';
        if (did.isEmpty || token.isEmpty) {
          continue;
        }
        final displayName = identity['name']?.toString() ??
            map['name']?.toString() ??
            identity['handle']?.toString() ??
            map['handle']?.toString() ??
            credentialName;
        sessions.add(
          SessionIdentity(
            did: did,
            credentialName: credentialName,
            displayName: displayName,
            handle: identity['handle']?.toString() ?? map['handle']?.toString(),
            jwtToken: token,
          ),
        );
      }

      sessions.sort((a, b) {
        final aIsDefault = a.credentialName == defaultCredentialName;
        final bIsDefault = b.credentialName == defaultCredentialName;
        if (aIsDefault && !bIsDefault) {
          return -1;
        }
        if (!aIsDefault && bIsDefault) {
          return 1;
        }
        return a.credentialName.compareTo(b.credentialName);
      });
      return _mergeSessions(catalogSessions, sessions);
    } catch (_) {
      return catalogSessions;
    }
  }

  @override
  Future<SessionIdentity> loginWithLocalCredential(
      String credentialName) async {
    await _refreshCredentialViaCli(credentialName);
    final sessions = await listLocalCredentials();
    final target =
        sessions.where((item) => item.credentialName == credentialName);
    if (target.isEmpty) {
      throw StateError('本地未找到凭证：$credentialName');
    }
    final session = target.first;
    await _persistSession(session);
    await _hydrateStoredIdentityMaterialFromCredential(credentialName);
    await _refreshSessionOnRestore();
    return _session ?? session;
  }

  @override
  Future<void> deleteLocalCredential(String credentialName) async {
    final scriptPath = _resolveSetupIdentityScriptPath();
    if (scriptPath == null) {
      throw StateError(
        '当前仓库未内置 setup_identity.py，请通过 '
        'AWIKI_SETUP_IDENTITY_SCRIPT 显式配置脚本路径后再删除凭证。',
      );
    }
    final command = Platform.isWindows ? 'python' : 'python3';
    final result = await Process.run(
      command,
      <String>[scriptPath, '--delete', credentialName],
      workingDirectory: _resolveProjectRootForScript(scriptPath),
    );
    if (result.exitCode != 0) {
      final stderr = (result.stderr ?? '').toString().trim();
      throw StateError(
        stderr.isNotEmpty ? stderr : '删除凭证失败：$credentialName',
      );
    }
    await _removeSavedCredentialFromStorage(credentialName);
  }

  @override
  Future<String?> exportCurrentCredentialAsZip() async {
    final current = _session;
    if (current == null) {
      throw StateError('当前没有已登录凭证可导出。');
    }
    final fileName =
        _credentialArchiveService.buildExportFileName(session: current);
    final exportBundle = await _resolveExportBundle(current);
    try {
      final zipBytes = Uint8List.fromList(_credentialArchiveService.buildZip(
        manifest: exportBundle.manifest,
        credentialDirectory: exportBundle.credentialDirectory,
      ));
      if (zipBytes.isEmpty) {
        throw StateError('凭证打包失败，请稍后重试。');
      }
      return _saveZipFile(
        fileName: fileName,
        bytes: zipBytes,
      );
    } finally {
      if (exportBundle.disposeAfterUse &&
          await exportBundle.credentialDirectory.exists()) {
        await exportBundle.credentialDirectory.parent.delete(recursive: true);
      }
    }
  }

  @override
  Future<SessionIdentity?> importCredentialFromZip() async {
    final zipBytes = await _pickZipFile();
    if (zipBytes == null || zipBytes.isEmpty) {
      return null;
    }
    final tempDir = await Directory.systemTemp.createTemp(
      'awiki-credential-import-',
    );
    try {
      final bundle = _credentialArchiveService.unpackZip(
        bytes: zipBytes,
        destinationRoot: tempDir,
      );
      final imported = await _importCredentialBundle(bundle);
      return imported;
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  @override
  Future<ChatMessage> retryMessage(ChatMessage message) async {
    return sendTextMessage(
      threadId: message.threadId,
      peerDid: message.receiverDid,
      groupId: message.groupId,
      content: message.content,
    );
  }

  @override
  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
  }) async {
    final did = _requireDid();
    final clientMsgId =
        'awikime-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(9999)}';
    final isGroupMessage = groupId != null && groupId.isNotEmpty;
    final result = await _rpcCall(
      baseUrl: isGroupMessage ? userServiceUrl : messageServiceUrl,
      path: isGroupMessage ? '/group/rpc' : '/message/rpc',
      method: isGroupMessage ? 'post_message' : 'send',
      params: <String, Object?>{
        if (!isGroupMessage) 'sender_did': did,
        if (peerDid != null && peerDid.isNotEmpty) 'receiver_did': peerDid,
        if (groupId != null && groupId.isNotEmpty) 'group_id': groupId,
        'content': content,
        if (!isGroupMessage) 'type': 'text',
        'client_msg_id': clientMsgId,
      },
      authRequired: true,
    );
    final sent = ChatMessage(
      localId: result['id']?.toString() ??
          result['message_id']?.toString() ??
          'local-${DateTime.now().microsecondsSinceEpoch}',
      remoteId: result['id']?.toString() ?? result['message_id']?.toString(),
      threadId: threadId,
      senderDid: did,
      senderName: _session?.handle ?? _session?.displayName,
      receiverDid: peerDid,
      groupId: groupId,
      content: content,
      createdAt: _parseDate(result['sent_at'] ?? result['created_at']) ??
          DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sent,
      serverSequence: int.tryParse(result['server_seq']?.toString() ?? ''),
    );
    await _localCache.upsertMessages(
      ownerDid: did,
      threadId: threadId,
      messages: <ChatMessage>[sent],
    );
    await _localCache.upsertConversations(
      ownerDid: did,
      conversations: <ConversationSummary>[
        ConversationSummary(
          threadId: threadId,
          displayName: peerDid ?? groupId ?? threadId,
          lastMessagePreview: content,
          lastMessageAt: sent.createdAt,
          unreadCount: 0,
          isGroup: groupId != null && groupId.isNotEmpty,
          targetDid: peerDid,
          groupId: groupId,
          avatarSeed: peerDid ?? groupId,
        ),
      ],
    );
    return sent;
  }

  @override
  Future<void> sendOtp({required String phone}) async {
    final normalizedPhone = _normalizePhone(phone);
    await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/handle/rpc',
      method: 'send_otp',
      params: <String, Object?>{'phone': normalizedPhone},
    );
  }

  @override
  Future<void> sendEmailVerification({required String email}) async {
    final uri =
        Uri.parse(userServiceUrl).resolve('/user-service/auth/email-send');
    final response = await _httpClient
        .post(
          uri,
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'email': email.trim().toLowerCase(),
          }),
        )
        .timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Email send HTTP error ${response.statusCode}: ${response.body}');
    }
  }

  @override
  Future<bool> checkEmailVerified({required String email}) async {
    final uri = Uri.parse(userServiceUrl)
        .resolve('/user-service/auth/email-status')
        .replace(
      queryParameters: <String, String>{
        'email': email.trim().toLowerCase(),
      },
    );
    final response = await _httpClient.get(uri).timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Email status HTTP error ${response.statusCode}: ${response.body}');
    }
    final payload = jsonDecode(response.body);
    if (payload is Map<String, Object?>) {
      return payload['verified'] == true;
    }
    return false;
  }

  @override
  Future<void> unfollow(String didOrHandle) async {
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/relationships/rpc',
      method: 'unfollow',
      params: <String, Object?>{'target_did': targetDid},
      authRequired: true,
    );
  }

  @override
  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle) async {
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/relationships/rpc',
      method: 'get_status',
      params: <String, Object?>{'target_did': targetDid},
      authRequired: true,
    );
    return RelationshipSummary(
      did: (result['did'] ?? '') as String,
      displayName: (result['display_name'] ?? result['name'] ?? '') as String,
      relationship: (result['status'] ?? 'none') as String,
    );
  }

  @override
  Future<GroupSummary> joinGroup(String joinCode) async {
    final joined = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'join',
      params: <String, Object?>{'passcode': joinCode},
      authRequired: true,
    );
    final groupId = joined['group_id']?.toString() ?? '';
    if (groupId.isEmpty) {
      return _toGroupSummary(joined);
    }
    final detail = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/group/rpc',
      method: 'get',
      params: <String, Object?>{'group_id': groupId},
      authRequired: true,
    );
    final summary = _toGroupSummary(<String, Object?>{...joined, ...detail});
    await _localCache.upsertGroups(
      ownerDid: _requireDid(),
      groups: <GroupSummary>[summary],
    );
    try {
      await listGroupMembers(summary.groupId);
    } catch (_) {
      // Best-effort hydration only.
    }
    try {
      await fetchGroupHistory(summary.groupId);
    } catch (_) {
      // A newly joined group may not have any history yet.
    }
    return summary;
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/profile/rpc',
      method: 'update_me',
      params: <String, Object?>{
        if (patch.nickName != null) 'nick_name': patch.nickName,
        if (patch.bio != null) 'bio': patch.bio,
        if (patch.tags != null) 'tags': patch.tags,
        if (patch.profileMarkdown != null) 'profile_md': patch.profileMarkdown,
      },
      authRequired: true,
    );
    return UserProfile(
      did: (result['did'] ?? '') as String,
      nickName: (result['nick_name'] ?? result['name'] ?? '') as String,
      bio: (result['bio'] ?? '') as String,
      tags: ((result['tags'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      profileMarkdown: (result['profile_md'] ?? '') as String,
      handle: result['handle']?.toString(),
      region: result['region']?.toString(),
    );
  }

  Future<Map<String, Object?>> _rpcCall({
    required String baseUrl,
    required String path,
    required String method,
    required Map<String, Object?> params,
    bool authRequired = false,
    bool allowAuthRecovery = true,
  }) async {
    final uri = Uri.parse(baseUrl).resolve(path);
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = _session?.jwtToken;
    if (authRequired && token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await _httpClient
        .post(
          uri,
          headers: headers,
          body: jsonEncode(
            <String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'method': method,
              'params': params,
            },
          ),
        )
        .timeout(_networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (authRequired &&
          allowAuthRecovery &&
          response.statusCode == 401 &&
          await _tryRecoverAuthToken()) {
        return _rpcCall(
          baseUrl: baseUrl,
          path: path,
          method: method,
          params: params,
          authRequired: authRequired,
          allowAuthRecovery: false,
        );
      }
      if (authRequired && response.statusCode == 401) {
        await _clearExpiredSession();
        throw StateError('登录状态已失效，请重新登录。');
      }
      throw Exception(
          'RPC HTTP error ${response.statusCode}: ${response.body}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    if (payload['error'] != null) {
      final errorText = payload['error'].toString();
      final invalidToken = errorText.contains('Invalidtoken') ||
          errorText.contains('Invalid token');
      if (authRequired &&
          allowAuthRecovery &&
          invalidToken &&
          await _tryRecoverAuthToken()) {
        return _rpcCall(
          baseUrl: baseUrl,
          path: path,
          method: method,
          params: params,
          authRequired: authRequired,
          allowAuthRecovery: false,
        );
      }
      if (authRequired && invalidToken) {
        await _clearExpiredSession();
        throw StateError('登录状态已失效，请重新登录。');
      }
      throw Exception('RPC error: ${payload['error']}');
    }
    final result = payload['result'];
    if (result is Map) {
      return result.map((k, v) => MapEntry(k.toString(), v));
    }
    if (result is List) {
      return <String, Object?>{'items': result};
    }
    return <String, Object?>{'value': result};
  }

  Future<bool> _tryRecoverAuthToken() async {
    final credentialName = _session?.credentialName;
    if (await _tryRecoverAuthTokenViaStoredIdentity()) {
      return true;
    }

    if (credentialName != null && credentialName.isNotEmpty) {
      await _hydrateStoredIdentityMaterialFromCredential(credentialName);
      if (await _tryRecoverAuthTokenViaStoredIdentity()) {
        return true;
      }
    }

    if (credentialName == null || credentialName.isEmpty) {
      return false;
    }
    await _refreshCredentialViaCli(credentialName);
    final sessions = await listLocalCredentials();
    final matched =
        sessions.where((item) => item.credentialName == credentialName);
    if (matched.isEmpty) {
      return false;
    }
    final refreshed = matched.first;
    if ((refreshed.jwtToken ?? '').isEmpty) {
      return false;
    }
    await _persistSession(refreshed);
    return true;
  }

  Future<SessionIdentity> _registerHandleCore({
    required Map<String, Object?> pluginPayload,
    required Map<String, Object?> authParams,
    required String handle,
    String rpcMethod = 'register',
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final params = <String, Object?>{
      ...pluginPayload,
      'handle': handle,
      ...authParams,
      if (inviteCode != null && inviteCode.isNotEmpty)
        'invite_code': inviteCode,
      if (nickName != null && nickName.isNotEmpty) 'name': nickName,
      'is_public': true,
    };
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did-auth/rpc',
      method: rpcMethod,
      params: params,
    );

    final didFromPayload = _extractDidFromPluginPayload(pluginPayload);
    final did = result['did']?.toString() ?? didFromPayload;
    final token = result['access_token']?.toString() ?? '';
    if (did.isEmpty || token.isEmpty) {
      throw StateError(
          'Handle registration succeeded but did/access_token is missing.');
    }
    final identity = SessionIdentity(
      did: did,
      credentialName: 'default',
      displayName: nickName?.isNotEmpty == true ? nickName! : handle,
      handle: handle,
      jwtToken: token,
    );
    await _persistSession(identity);
    await _persistIdentityMaterialFromPluginPayload(pluginPayload);
    if (profileMarkdown != null && profileMarkdown.isNotEmpty) {
      await updateProfile(ProfilePatch(profileMarkdown: profileMarkdown));
    }
    return identity;
  }

  Future<void> _persistSession(SessionIdentity identity) async {
    _session = identity;
    await _secureStorage.write(key: _sessionDidKey, value: identity.did);
    await _secureStorage.write(
        key: _sessionTokenKey, value: identity.jwtToken ?? '');
    await _secureStorage.write(
        key: _sessionCredentialKey, value: identity.credentialName);
    await _secureStorage.write(
        key: _sessionDisplayNameKey, value: identity.displayName);
    await _secureStorage.write(
        key: _sessionHandleKey, value: identity.handle ?? '');
    await _upsertSavedCredential(identity);
    await _syncSessionToLocalCredential(identity);
  }

  Future<void> _persistIdentityMaterialFromPluginPayload(
    Map<String, Object?> payload,
  ) async {
    final didDocument = payload['did_document'];
    final privateKeyPem = payload['private_key_pem']?.toString() ?? '';
    final domain = payload['domain']?.toString() ?? userServiceUrl;
    if (didDocument is! Map<Object?, Object?> || privateKeyPem.isEmpty) {
      return;
    }
    final normalizedDidDocument = didDocument.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
    await _secureStorage.write(
      key: _sessionDidDocumentKey,
      value: jsonEncode(normalizedDidDocument),
    );
    await _secureStorage.write(
      key: _sessionPrivateKeyPemKey,
      value: privateKeyPem,
    );
    await _secureStorage.write(
      key: _sessionDidDomainKey,
      value: domain,
    );
  }

  Future<bool> _tryRecoverAuthTokenViaStoredIdentity() async {
    try {
      final currentSession = _session;
      if (currentSession == null) {
        return false;
      }
      final didDocumentRaw =
          await _secureStorage.read(key: _sessionDidDocumentKey);
      final privateKeyPem =
          await _secureStorage.read(key: _sessionPrivateKeyPemKey) ?? '';
      if (didDocumentRaw == null ||
          didDocumentRaw.isEmpty ||
          privateKeyPem.isEmpty) {
        return false;
      }

      final decoded = jsonDecode(didDocumentRaw);
      if (decoded is! Map) {
        return false;
      }
      final didDocument = decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final didFromDocument = didDocument['id']?.toString() ?? '';
      if (didFromDocument.isEmpty || didFromDocument != currentSession.did) {
        await _clearStoredIdentityMaterial();
        return false;
      }

      final domain =
          await _secureStorage.read(key: _sessionDidDomainKey) ?? _didDomain();
      final authorization = await _didRegistrationFacade.generateDidAuthHeader(
        didDocument: didDocument,
        privateKeyPem: privateKeyPem,
        domain: domain,
      );

      final result = await _rpcCall(
        baseUrl: userServiceUrl,
        path: '/user-service/did-auth/rpc',
        method: 'verify',
        params: <String, Object?>{
          'authorization': authorization,
          'domain': domain,
        },
        allowAuthRecovery: false,
      );
      final newToken = result['access_token']?.toString() ?? '';
      final recoveredDid = result['did']?.toString() ??
          result['user_did']?.toString() ??
          didFromDocument;
      if (newToken.isEmpty || recoveredDid != currentSession.did) {
        return false;
      }
      await _persistSession(
        SessionIdentity(
          did: currentSession.did,
          credentialName: currentSession.credentialName,
          displayName: currentSession.displayName,
          handle: currentSession.handle,
          jwtToken: newToken,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshSessionOnRestore() async {
    try {
      await _tryRecoverAuthTokenViaStoredIdentity();
    } catch (_) {
      // Best-effort only. If refresh fails here, normal auth recovery still has a chance later.
    }
  }

  Future<void> _clearExpiredSession() async {
    _session = null;
    await _secureStorage.delete(key: _sessionDidKey);
    await _secureStorage.delete(key: _sessionTokenKey);
    await _secureStorage.delete(key: _sessionCredentialKey);
    await _secureStorage.delete(key: _sessionDisplayNameKey);
    await _secureStorage.delete(key: _sessionHandleKey);
    await _clearStoredIdentityMaterial();
  }

  Future<void> _clearStoredIdentityMaterial() async {
    await _secureStorage.delete(key: _sessionDidDocumentKey);
    await _secureStorage.delete(key: _sessionPrivateKeyPemKey);
    await _secureStorage.delete(key: _sessionDidDomainKey);
  }

  String _extractDidFromPluginPayload(Map<String, Object?> payload) {
    final did = payload['did']?.toString();
    if (did != null && did.isNotEmpty) {
      return did;
    }
    final document = payload['did_document'];
    if (document is Map<Object?, Object?>) {
      final id = document['id']?.toString();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }
    return '';
  }

  Future<List<SessionIdentity>> _loadSavedCredentialsFromStorage() async {
    try {
      final raw = await _secureStorage.read(key: _savedCredentialsKey);
      if (raw == null || raw.isEmpty) {
        return const <SessionIdentity>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <SessionIdentity>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.map<String, Object?>(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .map(
            (item) => SessionIdentity(
              did: item['did']?.toString() ?? '',
              credentialName: item['credential_name']?.toString() ?? 'default',
              displayName: item['display_name']?.toString() ?? 'AWiki Me',
              handle: item['handle']?.toString(),
              jwtToken: item['jwt_token']?.toString(),
            ),
          )
          .where(
              (item) => item.did.isNotEmpty && (item.jwtToken ?? '').isNotEmpty)
          .toList();
    } catch (_) {
      return const <SessionIdentity>[];
    }
  }

  Future<void> _upsertSavedCredential(SessionIdentity identity) async {
    final existing = await _loadSavedCredentialsFromStorage();
    final merged = _mergeSessions(existing, <SessionIdentity>[identity]);
    final payload = merged
        .map(
          (item) => <String, Object?>{
            'did': item.did,
            'credential_name': item.credentialName,
            'display_name': item.displayName,
            'handle': item.handle,
            'jwt_token': item.jwtToken,
          },
        )
        .toList();
    await _secureStorage.write(
      key: _savedCredentialsKey,
      value: jsonEncode(payload),
    );
  }

  Future<void> _removeSavedCredentialFromStorage(String credentialName) async {
    final existing = await _loadSavedCredentialsFromStorage();
    final filtered = existing
        .where((item) => item.credentialName != credentialName)
        .toList();
    final payload = filtered
        .map(
          (item) => <String, Object?>{
            'did': item.did,
            'credential_name': item.credentialName,
            'display_name': item.displayName,
            'handle': item.handle,
            'jwt_token': item.jwtToken,
          },
        )
        .toList();
    await _secureStorage.write(
      key: _savedCredentialsKey,
      value: jsonEncode(payload),
    );
  }

  List<SessionIdentity> _mergeSessions(
    List<SessionIdentity> first,
    List<SessionIdentity> second,
  ) {
    final map = <String, SessionIdentity>{};
    for (final item in first) {
      map[item.credentialName] = item;
    }
    for (final item in second) {
      map[item.credentialName] = item;
    }
    final values = map.values.toList();
    values.sort((a, b) => a.credentialName.compareTo(b.credentialName));
    return values;
  }

  Future<Map<String, Object?>> _loadCredentialIndex() async {
    final rootPath = await _localCredentialsRootPath();
    final indexFile = File(
      '$rootPath${Platform.pathSeparator}index.json',
    );
    if (!await indexFile.exists()) {
      return <String, Object?>{
        'schema_version': 3,
        'default_credential_name': null,
        'credentials': <String, Object?>{},
      };
    }
    final decoded = jsonDecode(await indexFile.readAsString());
    if (decoded is! Map) {
      throw StateError('本地凭证索引格式不正确。');
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Map<String, Map<String, Object?>> _credentialsFromIndex(
    Map<String, Object?> index,
  ) {
    final rawCredentials = index['credentials'];
    if (rawCredentials is! Map) {
      throw StateError('本地凭证索引缺少 credentials。');
    }
    return rawCredentials.map<String, Map<String, Object?>>((key, value) {
      if (value is! Map) {
        throw StateError('凭证索引项格式不正确：$key');
      }
      return MapEntry(
        key.toString(),
        value.map<String, Object?>(
          (entryKey, entryValue) => MapEntry(entryKey.toString(), entryValue),
        ),
      );
    });
  }

  Map<String, Object?>? _resolveCredentialIndexEntry({
    required Map<String, Map<String, Object?>> credentials,
    required String credentialName,
    String? fallbackDefaultName,
  }) {
    final direct = credentials[credentialName];
    if (direct != null) {
      return direct;
    }
    if (credentialName == 'default' &&
        fallbackDefaultName != null &&
        fallbackDefaultName.isNotEmpty) {
      return credentials[fallbackDefaultName];
    }
    return null;
  }

  Future<Directory> _credentialsRootDirectory() async {
    final rootPath = await _localCredentialsRootPath();
    if (rootPath.isEmpty) {
      throw StateError('无法定位本地凭证目录。');
    }
    return Directory(rootPath);
  }

  Future<String> _localCredentialsRootPath() async {
    final overridePath = _localCredentialsRootPathOverride;
    if (overridePath != null && overridePath.trim().isNotEmpty) {
      return overridePath.trim();
    }
    final configured = const String.fromEnvironment(
      'AWIKI_CREDENTIALS_DIR',
      defaultValue: '',
    ).trim();
    if (configured.isNotEmpty) {
      return configured;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final supportDir = await getApplicationSupportDirectory();
      return '${supportDir.path}${Platform.pathSeparator}.openclaw'
          '${Platform.pathSeparator}credentials'
          '${Platform.pathSeparator}$_credentialsDirectoryName';
    }
    final home = Platform.environment['HOME']?.trim() ?? '';
    if (home.isEmpty) {
      return '';
    }
    return '$home/.openclaw/credentials/$_credentialsDirectoryName';
  }

  Future<String?> _saveZipFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final service = _documentPickerService;
    if (service == null) {
      throw StateError('当前平台暂不支持导出身份凭证。');
    }
    return service.saveZipFile(fileName: fileName, bytes: bytes);
  }

  Future<Uint8List?> _pickZipFile() async {
    final service = _documentPickerService;
    if (service == null) {
      throw StateError('当前平台暂不支持导入身份凭证。');
    }
    return service.pickZipFile();
  }

  Future<_ResolvedExportBundle> _resolveExportBundle(
    SessionIdentity session,
  ) async {
    final credentialRoot = await _credentialsRootDirectory();
    final index = await _loadCredentialIndex();
    final credentials = _credentialsFromIndex(index);
    final entry = _resolveCredentialIndexEntry(
      credentials: credentials,
      credentialName: session.credentialName,
      fallbackDefaultName: index['default_credential_name']?.toString(),
    );
    if (entry != null) {
      final credentialDirName = entry['dir_name']?.toString() ?? '';
      if (credentialDirName.isNotEmpty) {
        final credentialDirectory = Directory(
          '${credentialRoot.path}${Platform.pathSeparator}$credentialDirName',
        );
        if (credentialDirectory.existsSync()) {
          return _ResolvedExportBundle(
            manifest: _credentialArchiveService.buildManifest(
              indexEntry: entry,
              credentialName: session.credentialName,
              session: session,
            ),
            credentialDirectory: credentialDirectory,
          );
        }
      }
    }
    return _buildEphemeralExportBundle(session);
  }

  Future<_ResolvedExportBundle> _buildEphemeralExportBundle(
    SessionIdentity session,
  ) async {
    final didDocumentRaw =
        await _secureStorage.read(key: _sessionDidDocumentKey);
    final privateKeyPem =
        await _secureStorage.read(key: _sessionPrivateKeyPemKey) ?? '';
    if (didDocumentRaw == null ||
        didDocumentRaw.isEmpty ||
        privateKeyPem.isEmpty) {
      throw StateError('未找到当前凭证的本地索引信息。');
    }
    final decodedDidDocument = jsonDecode(didDocumentRaw);
    if (decodedDidDocument is! Map) {
      throw StateError('当前凭证的 DID 文档格式不正确。');
    }
    final tempRoot = await Directory.systemTemp.createTemp('awiki-export-');
    final credentialDirectory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}credential',
    );
    await credentialDirectory.create(recursive: true);
    final uniqueId = session.did.contains(':')
        ? session.did.split(':').last
        : session.credentialName;
    final identityPayload = <String, Object?>{
      'did': session.did,
      'unique_id': uniqueId,
      'name': session.displayName,
      if (session.handle != null && session.handle!.isNotEmpty)
        'handle': session.handle,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    final authPayload = <String, Object?>{
      'jwt_token': session.jwtToken ?? '',
    };
    await File(
      '${credentialDirectory.path}${Platform.pathSeparator}identity.json',
    ).writeAsString(jsonEncode(identityPayload));
    await File(
      '${credentialDirectory.path}${Platform.pathSeparator}auth.json',
    ).writeAsString(jsonEncode(authPayload));
    await File(
      '${credentialDirectory.path}${Platform.pathSeparator}did_document.json',
    ).writeAsString(didDocumentRaw);
    await File(
      '${credentialDirectory.path}${Platform.pathSeparator}key-1-private.pem',
    ).writeAsString(privateKeyPem);
    final manifest = <String, Object?>{
      'bundle_version': CredentialArchiveService.bundleVersion,
      'credential_name': session.credentialName,
      'dir_name': uniqueId,
      'did': session.did,
      'unique_id': uniqueId,
      'display_name': session.displayName,
      'handle': session.handle,
      'created_at': identityPayload['created_at'],
      'exported_at': DateTime.now().toIso8601String(),
    };
    return _ResolvedExportBundle(
      manifest: manifest,
      credentialDirectory: credentialDirectory,
      disposeAfterUse: true,
    );
  }

  Future<SessionIdentity> _importCredentialBundle(
    ImportedCredentialBundle bundle,
  ) async {
    final credentialRoot = await _credentialsRootDirectory();
    await credentialRoot.create(recursive: true);
    final manifest = bundle.manifest;
    final credentialName = manifest['credential_name']?.toString().trim() ?? '';
    final dirName = manifest['dir_name']?.toString().trim() ?? '';
    final did = manifest['did']?.toString().trim() ?? '';
    if (credentialName.isEmpty || dirName.isEmpty || did.isEmpty) {
      throw const FormatException('ZIP 包缺少必要的凭证元信息。');
    }
    final index = await _loadCredentialIndex();
    final credentials = _credentialsFromIndex(index);
    final existingEntry = credentials[credentialName];
    final isDefaultCredential =
        (index['default_credential_name']?.toString() == credentialName) ||
            credentialName == 'default' ||
            existingEntry?['is_default'] == true;
    final targetDir = Directory(
      '${credentialRoot.path}${Platform.pathSeparator}$dirName',
    );
    final tempTargetDir = Directory('${targetDir.path}.importing');
    if (await tempTargetDir.exists()) {
      await tempTargetDir.delete(recursive: true);
    }
    await _copyDirectory(bundle.credentialDirectory, tempTargetDir);

    final identity = await _buildImportedSessionIdentity(
      credentialName: credentialName,
      credentialDirectory: tempTargetDir,
    );
    final previousDirName = existingEntry?['dir_name']?.toString() ?? '';
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await tempTargetDir.rename(targetDir.path);

    final updatedCredentials = Map<String, Object?>.from(
      index['credentials'] as Map,
    );
    updatedCredentials[credentialName] = <String, Object?>{
      'credential_name': credentialName,
      'dir_name': dirName,
      'did': did,
      'unique_id': manifest['unique_id']?.toString() ?? '',
      'user_id': null,
      'name': manifest['display_name']?.toString() ?? identity.displayName,
      'handle': manifest['handle']?.toString() ?? identity.handle,
      'created_at': manifest['created_at']?.toString() ?? '',
      'is_default': isDefaultCredential,
    };
    if (isDefaultCredential) {
      index['default_credential_name'] = credentialName;
    }
    index['credentials'] = updatedCredentials;
    await _writeCredentialIndex(index);
    if (previousDirName.isNotEmpty && previousDirName != dirName) {
      await _deleteDirIfUnreferenced(previousDirName,
          exceptCredential: credentialName);
    }
    await _upsertSavedCredential(identity);
    return identity;
  }

  Future<void> _writeCredentialIndex(Map<String, Object?> index) async {
    final root = await _credentialsRootDirectory();
    await root.create(recursive: true);
    final indexFile = File('${root.path}${Platform.pathSeparator}index.json');
    await indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(index),
      flush: true,
    );
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      final relativePath = entity.path.substring(source.path.length + 1);
      final targetPath =
          '${destination.path}${Platform.pathSeparator}$relativePath';
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
        continue;
      }
      if (entity is File) {
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetFile.path);
      }
    }
  }

  Future<void> _deleteDirIfUnreferenced(
    String dirName, {
    required String exceptCredential,
  }) async {
    final index = await _loadCredentialIndex();
    final credentials = _credentialsFromIndex(index);
    final stillReferenced = credentials.entries.any(
      (entry) =>
          entry.key != exceptCredential &&
          entry.value['dir_name']?.toString() == dirName,
    );
    if (stillReferenced) {
      return;
    }
    final targetDir = Directory(
      '${(await _credentialsRootDirectory()).path}${Platform.pathSeparator}$dirName',
    );
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
  }

  Future<SessionIdentity> _buildImportedSessionIdentity({
    required String credentialName,
    required Directory credentialDirectory,
  }) async {
    final identityFile = File(
      '${credentialDirectory.path}${Platform.pathSeparator}identity.json',
    );
    final authFile = File(
      '${credentialDirectory.path}${Platform.pathSeparator}auth.json',
    );
    final identity = await _readJsonMap(identityFile);
    final auth = await _readJsonMap(authFile);
    final did = identity['did']?.toString() ?? '';
    final jwtToken = auth['jwt_token']?.toString() ?? '';
    if (did.isEmpty || jwtToken.isEmpty) {
      throw const FormatException('ZIP 包中的凭证内容不完整。');
    }
    final displayName = identity['name']?.toString() ??
        identity['handle']?.toString() ??
        credentialName;
    return SessionIdentity(
      did: did,
      credentialName: credentialName,
      displayName: displayName,
      handle: identity['handle']?.toString(),
      jwtToken: jwtToken,
    );
  }

  Future<Map<String, Object?>> _readJsonMap(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw FormatException('文件格式不正确：${file.path}');
    }
    return decoded.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  String _didDomain() {
    final configured = Uri.tryParse(userServiceUrl)?.host ?? '';
    if (configured.isNotEmpty) {
      return configured;
    }
    return 'awiki.ai';
  }

  Future<void> _refreshCredentialViaCli(String credentialName) async {
    try {
      if (!(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
        return;
      }
      final scriptPath = _resolveSetupIdentityScriptPath();
      if (scriptPath == null) {
        return;
      }
      final command = Platform.isWindows ? 'python' : 'python3';
      await Process.run(
        command,
        <String>[scriptPath, '--load', credentialName],
        workingDirectory: _resolveProjectRootForScript(scriptPath),
      );
    } catch (_) {
      // Best-effort refresh only.
    }
  }

  Future<void> _hydrateStoredIdentityMaterialFromCredential(
    String credentialName,
  ) async {
    final payload = await _loadCredentialPayload(credentialName);
    if (payload == null) {
      await _clearStoredIdentityMaterial();
      return;
    }
    final didDocument = payload['did_document'];
    final privateKeyPem = payload['private_key_pem']?.toString() ?? '';
    if (didDocument is! Map<String, Object?> || privateKeyPem.isEmpty) {
      await _clearStoredIdentityMaterial();
      return;
    }
    await _secureStorage.write(
      key: _sessionDidDocumentKey,
      value: jsonEncode(didDocument),
    );
    await _secureStorage.write(
      key: _sessionPrivateKeyPemKey,
      value: privateKeyPem,
    );
    await _secureStorage.write(
      key: _sessionDidDomainKey,
      value: payload['domain']?.toString() ?? _didDomain(),
    );
  }

  Future<Map<String, Object?>?> _loadCredentialPayload(
    String credentialName,
  ) async {
    try {
      final rootPath = await _localCredentialsRootPath();
      if (rootPath.isEmpty) {
        return null;
      }
      final indexFile = File('$rootPath/index.json');
      if (!await indexFile.exists()) {
        return null;
      }
      final indexPayload = jsonDecode(await indexFile.readAsString());
      if (indexPayload is! Map) {
        return null;
      }
      final index = indexPayload.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final rawCredentials = index['credentials'];
      if (rawCredentials is! Map) {
        return null;
      }
      final credentials = rawCredentials.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      var resolvedName = credentialName;
      if (!credentials.containsKey(credentialName) &&
          credentialName == 'default') {
        final defaultName = index['default_credential_name']?.toString() ?? '';
        if (defaultName.isNotEmpty && credentials.containsKey(defaultName)) {
          resolvedName = defaultName;
        }
      }
      final detail = credentials[resolvedName];
      if (detail is! Map) {
        return null;
      }
      final map = detail.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final dirName = map['dir_name']?.toString() ?? '';
      if (dirName.isEmpty) {
        return null;
      }
      final identityFile = File('$rootPath/$dirName/identity.json');
      final authFile = File('$rootPath/$dirName/auth.json');
      final didDocumentFile = File('$rootPath/$dirName/did_document.json');
      final privateKeyFile = File('$rootPath/$dirName/key-1-private.pem');
      if (!await identityFile.exists() || !await authFile.exists()) {
        return null;
      }
      final identityRaw = jsonDecode(await identityFile.readAsString());
      final authRaw = jsonDecode(await authFile.readAsString());
      if (identityRaw is! Map || authRaw is! Map) {
        return null;
      }
      final identity = identityRaw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final auth = authRaw.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      Map<String, Object?>? didDocument;
      if (await didDocumentFile.exists()) {
        final didDocumentRaw = jsonDecode(await didDocumentFile.readAsString());
        if (didDocumentRaw is Map) {
          didDocument = didDocumentRaw.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      }
      String? privateKeyPem;
      if (await privateKeyFile.exists()) {
        privateKeyPem = await privateKeyFile.readAsString();
      }
      return <String, Object?>{
        'did': identity['did']?.toString() ?? map['did']?.toString() ?? '',
        'display_name': identity['name']?.toString() ??
            map['name']?.toString() ??
            identity['handle']?.toString() ??
            map['handle']?.toString() ??
            resolvedName,
        'handle': identity['handle']?.toString() ?? map['handle']?.toString(),
        'jwt_token': auth['jwt_token']?.toString() ?? '',
        'did_document': didDocument,
        'private_key_pem': privateKeyPem,
        'domain': _didDomain(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _syncSessionToLocalCredential(SessionIdentity identity) async {
    try {
      final index = await _loadCredentialIndex();
      final credentials = _credentialsFromIndex(index);
      final entry = _resolveCredentialIndexEntry(
        credentials: credentials,
        credentialName: identity.credentialName,
        fallbackDefaultName: index['default_credential_name']?.toString(),
      );
      final dirName = entry?['dir_name']?.toString() ?? '';
      if (dirName.isEmpty) {
        return;
      }
      final rootPath = await _localCredentialsRootPath();
      if (rootPath.isEmpty) {
        return;
      }
      final authFile = File('$rootPath/$dirName/auth.json');
      if (await authFile.exists()) {
        final authRaw = jsonDecode(await authFile.readAsString());
        if (authRaw is Map) {
          final auth = authRaw.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          );
          auth['jwt_token'] = identity.jwtToken ?? '';
          await authFile.writeAsString(jsonEncode(auth), flush: true);
        }
      }
      final identityFile = File('$rootPath/$dirName/identity.json');
      if (await identityFile.exists()) {
        final identityRaw = jsonDecode(await identityFile.readAsString());
        if (identityRaw is Map) {
          final payload = identityRaw.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          );
          payload['did'] = identity.did;
          payload['name'] = identity.displayName;
          payload['handle'] = identity.handle;
          await identityFile.writeAsString(jsonEncode(payload), flush: true);
        }
      }
    } catch (_) {
      // Best-effort sync only.
    }
  }

  String? _resolveSetupIdentityScriptPath() {
    final fromEnv = const String.fromEnvironment(
      'AWIKI_SETUP_IDENTITY_SCRIPT',
      defaultValue: '',
    ).trim();
    if (fromEnv.isNotEmpty && File(fromEnv).existsSync()) {
      return fromEnv;
    }
    return null;
  }

  String _resolveProjectRootForScript(String scriptPath) {
    return File(scriptPath).parent.parent.path;
  }

  String _requireDid() {
    final did = _session?.did;
    if (did == null || did.isEmpty) {
      throw StateError(
          'No active awiki session DID. Please restore session first.');
    }
    return did;
  }

  String _sanitizeOtp(String code) {
    return code.replaceAll(RegExp(r'\s+'), '');
  }

  String _normalizePhone(String phone) {
    final raw = phone.trim();
    final intlPattern = RegExp(r'^\+\d{1,3}\d{6,14}$');
    final cnLocalPattern = RegExp(r'^1[3-9]\d{9}$');
    if (raw.startsWith('+')) {
      if (!intlPattern.hasMatch(raw)) {
        throw ArgumentError('手机号格式不正确，请使用 +国家码手机号，例如 +8613800138000');
      }
      return raw;
    }
    if (cnLocalPattern.hasMatch(raw)) {
      return '+86$raw';
    }
    throw ArgumentError('手机号格式不正确，请输入国际格式或中国大陆 11 位手机号');
  }

  String _normalizeHandle(String handle) {
    final normalized = handle.trim().toLowerCase();
    final pattern = RegExp(r'^[a-z0-9-]{2,32}$');
    if (!pattern.hasMatch(normalized)) {
      throw ArgumentError('handle 仅支持小写字母、数字、中划线，长度 2-32，不能包含下划线');
    }
    return normalized;
  }

  Future<String> _resolveDidOrHandle(String value) async {
    if (value.startsWith('did:')) {
      return value;
    }
    final result = await _rpcCall(
      baseUrl: userServiceUrl,
      path: '/user-service/did/profile/rpc',
      method: 'get_public_profile',
      params: <String, Object?>{'handle': value},
    );
    final did = result['did']?.toString() ?? '';
    if (did.isEmpty) {
      throw StateError('Failed to resolve handle to DID: $value');
    }
    return did;
  }

  List<RelationshipSummary> _toRelationshipList(
    Map<String, Object?> result, {
    required String fallbackRelationship,
  }) {
    final rows = _extractRelationshipRows(result);
    return rows
        .map((item) {
          final did = item['did']?.toString() ??
              item['target_did']?.toString() ??
              item['user_did']?.toString() ??
              item['to_did']?.toString() ??
              item['from_did']?.toString() ??
              '';
          final name = item['display_name']?.toString() ??
              item['name']?.toString() ??
              item['nick_name']?.toString() ??
              item['handle']?.toString() ??
              did;
          return RelationshipSummary(
            did: did,
            displayName: name,
            relationship: item['relationship']?.toString() ??
                item['status']?.toString() ??
                fallbackRelationship,
          );
        })
        .where((item) => item.did.isNotEmpty)
        .toList();
  }

  List<ConversationSummary> _mergeConversations(
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

  List<Map<String, Object?>> _extractRelationshipRows(Object? raw) {
    final direct = _toMapList(raw);
    if (direct.isNotEmpty) {
      return direct;
    }
    if (raw is! Map) {
      return const <Map<String, Object?>>[];
    }
    final map = raw
        .map<String, Object?>((key, value) => MapEntry(key.toString(), value));
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

  Future<ConversationSummary?> _loadConversationByThread({
    required String ownerDid,
    required String threadId,
  }) async {
    final conversations =
        await _localCache.loadConversations(ownerDid: ownerDid);
    for (final item in conversations) {
      if (item.threadId == threadId) {
        return item;
      }
    }
    return null;
  }

  ConversationSummary _conversationFromRealtimeEvent(
    Map<String, Object?> event, {
    required String ownerDid,
    required ChatMessage message,
    required ConversationSummary? previous,
  }) {
    final isGroup = (message.groupId ?? '').isNotEmpty;
    final peerDid =
        isGroup ? '' : _peerDidFromMessage(event, ownerDid: ownerDid);
    final fallbackDisplayName = isGroup
        ? 'Group ${message.groupId ?? ''}'
        : (peerDid.isNotEmpty ? peerDid : 'Unknown');
    final displayName = isGroup
        ? event['group_name']?.toString()
        : event['sender_name']?.toString();

    return ConversationSummary(
      threadId: message.threadId,
      displayName: (displayName != null && displayName.isNotEmpty)
          ? displayName.toString()
          : previous?.displayName ?? fallbackDisplayName,
      lastMessagePreview: message.content,
      lastMessageAt: message.createdAt,
      unreadCount: message.isMine ? 0 : (previous?.unreadCount ?? 0) + 1,
      isGroup: isGroup,
      targetDid: isGroup ? null : peerDid,
      groupId: message.groupId,
      avatarSeed: isGroup ? message.groupId : peerDid,
    );
  }

  GroupSummary _toGroupSummary(Map<String, Object?> map) {
    return GroupSummary(
      groupId: map['group_id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed Group',
      description: map['description']?.toString() ?? '',
      memberCount: int.tryParse(map['member_count']?.toString() ?? '') ?? 0,
      lastMessageAt: _parseDate(map['last_message_at'] ?? map['updated_at']),
      myRole: map['my_role']?.toString(),
    );
  }

  List<Map<String, Object?>> _toMapList(Object? raw) {
    if (raw is! List) {
      return const <Map<String, Object?>>[];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((item) => item.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value)))
        .toList();
  }

  DateTime? _parseDate(Object? raw) {
    if (raw == null) {
      return null;
    }
    return DateTime.tryParse(raw.toString());
  }

  ChatMessage _toChatMessage(
    Map<String, Object?> item, {
    required String did,
    String? forceThreadId,
    String? groupId,
  }) {
    final senderDid = item['sender_did']?.toString() ?? '';
    final receiverDid = item['receiver_did']?.toString();
    final resolvedGroupId = groupId ?? item['group_id']?.toString();
    return ChatMessage(
      localId: item['id']?.toString() ??
          item['msg_id']?.toString() ??
          '${DateTime.now().microsecondsSinceEpoch}',
      remoteId: item['id']?.toString() ?? item['msg_id']?.toString(),
      threadId: forceThreadId ?? _threadIdForMessage(item, ownerDid: did),
      senderDid: senderDid,
      senderName: item['sender_name']?.toString() ??
          item['handle']?.toString() ??
          item['member_handle']?.toString(),
      receiverDid: receiverDid,
      groupId: resolvedGroupId,
      content: item['content']?.toString() ?? '',
      originalType: item['type']?.toString() ?? 'text',
      createdAt:
          _parseDate(item['sent_at'] ?? item['created_at']) ?? DateTime.now(),
      isMine: senderDid == did,
      sendState: MessageSendState.sent,
      serverSequence: int.tryParse(item['server_seq']?.toString() ?? ''),
      isEncrypted: (item['_e2ee'] == true) ||
          ((item['type']?.toString() ?? '').startsWith('e2ee_')),
    );
  }

  String _threadIdForMessage(Map<String, Object?> item,
      {required String ownerDid}) {
    final groupId = item['group_id']?.toString();
    if (groupId != null && groupId.isNotEmpty) {
      return 'group:$groupId';
    }
    final peerDid = _peerDidFromMessage(item, ownerDid: ownerDid);
    final pair = <String>[ownerDid, peerDid]..sort();
    return 'dm:${pair[0]}:${pair[1]}';
  }

  String _threadIdForPeer({required String ownerDid, required String peerDid}) {
    final pair = <String>[ownerDid, peerDid]..sort();
    return 'dm:${pair[0]}:${pair[1]}';
  }

  String _peerDidFromMessage(Map<String, Object?> item,
      {required String ownerDid}) {
    final senderDid = item['sender_did']?.toString() ?? '';
    final receiverDid = item['receiver_did']?.toString() ?? '';
    if (senderDid == ownerDid && receiverDid.isNotEmpty) {
      return receiverDid;
    }
    if (senderDid.isNotEmpty && senderDid != ownerDid) {
      return senderDid;
    }
    return receiverDid;
  }

  List<ConversationSummary> _buildConversationsFromInbox({
    required List<Map<String, Object?>> messages,
    required String ownerDid,
  }) {
    final latest = <String, Map<String, Object?>>{};
    final unread = <String, int>{};
    for (final item in messages) {
      final threadId = _threadIdForMessage(item, ownerDid: ownerDid);
      final sentAt = _parseDate(item['sent_at'] ?? item['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final current = latest[threadId];
      if (current == null) {
        latest[threadId] = item;
      } else {
        final currentAt =
            _parseDate(current['sent_at'] ?? current['created_at']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
        if (currentAt.isBefore(sentAt)) {
          latest[threadId] = item;
        }
      }
      final senderDid = item['sender_did']?.toString() ?? '';
      if (senderDid.isNotEmpty && senderDid != ownerDid) {
        unread[threadId] = (unread[threadId] ?? 0) + 1;
      }
    }
    return latest.entries.map((entry) {
      final item = entry.value;
      final isGroup = (item['group_id']?.toString().isNotEmpty ?? false);
      final displayName = isGroup
          ? item['group_name']?.toString() ?? 'Group'
          : (item['sender_name']?.toString().isNotEmpty ?? false)
              ? item['sender_name']!.toString()
              : item['sender_did']?.toString() ?? 'Unknown';
      return ConversationSummary(
        threadId: entry.key,
        displayName: displayName,
        lastMessagePreview: item['content']?.toString() ?? '',
        lastMessageAt:
            _parseDate(item['sent_at'] ?? item['created_at']) ?? DateTime.now(),
        unreadCount: unread[entry.key] ?? 0,
        isGroup: isGroup,
        targetDid:
            isGroup ? null : _peerDidFromMessage(item, ownerDid: ownerDid),
        groupId: isGroup ? item['group_id']?.toString() : null,
        avatarSeed: displayName,
      );
    }).toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  }
}

class _ResolvedExportBundle {
  const _ResolvedExportBundle({
    required this.manifest,
    required this.credentialDirectory,
    this.disposeAfterUse = false,
  });

  final Map<String, Object?> manifest;
  final Directory credentialDirectory;
  final bool disposeAfterUse;
}
