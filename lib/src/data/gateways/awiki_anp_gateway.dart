import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../awiki_sdk/awiki_anp_session.dart';
import '../awiki_sdk/awiki_message_client.dart';
import '../awiki_sdk/awiki_service_client.dart';
import '../awiki_sdk/awiki_user_client.dart';
import '../awiki_sdk/awiki_wire_mapper.dart';
import '../services/awiki_local_cache.dart';
import '../services/credential_archive_service.dart';
import '../services/document_picker_service.dart';
import '../services/noop_did_registration_facade.dart';
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
import 'awiki_rpc_gateway.dart';

class AwikiAnpGateway implements AwikiGateway {
  AwikiAnpGateway({
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
    AwikiMessageClient? messageClient,
    AwikiUserClient? userClient,
    AwikiGateway? legacyGateway,
    AwikiWireMapper mapper = const AwikiWireMapper(),
  }) : _httpClient = httpClient ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _localCache = localCache ?? AwikiLocalCache(),
       _didRegistrationFacade =
           didRegistrationFacade ?? NoopDidRegistrationFacade(),
       _credentialArchiveService =
           credentialArchiveService ?? CredentialArchiveService(),
       _documentPickerService = documentPickerService,
       _localCredentialsRootPath = localCredentialsRootPath,
       _session = initialSession,
       _mapper = mapper,
       _messageClient = messageClient,
       _userClient = userClient,
       _legacyGateway = legacyGateway;

  factory AwikiAnpGateway.fromEnvironment({
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
    return AwikiAnpGateway(
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
  final DidRegistrationFacade _didRegistrationFacade;
  final CredentialArchiveService _credentialArchiveService;
  final DocumentPickerService? _documentPickerService;
  final String? _localCredentialsRootPath;
  final AwikiWireMapper _mapper;
  final AwikiMessageClient? _messageClient;
  final AwikiUserClient? _userClient;
  final AwikiGateway? _legacyGateway;

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
  String? _messageServiceDid;
  AwikiGateway? _legacy;
  AwikiMessageClient? _messages;
  AwikiUserClient? _users;

  AwikiGateway get _delegate {
    return _legacy ??=
        _legacyGateway ??
        AwikiRpcGateway(
          userServiceUrl: userServiceUrl,
          messageServiceUrl: messageServiceUrl,
          secureStorage: _secureStorage,
          localCache: _localCache,
          didRegistrationFacade: _didRegistrationFacade,
          credentialArchiveService: _credentialArchiveService,
          documentPickerService: _documentPickerService,
          initialSession: _session,
          httpClient: _httpClient,
          localCredentialsRootPath: _localCredentialsRootPath,
        );
  }

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
  Future<BridgeCapabilities> loadCapabilities() => _delegate.loadCapabilities();

  @override
  Future<SessionIdentity?> restoreSession() async {
    if (_session != null) {
      return _session;
    }

    final did =
        await _secureStorage.read(key: _sessionDidKey) ??
        const String.fromEnvironment('AWIKI_DID', defaultValue: '');
    final token =
        await _secureStorage.read(key: _sessionTokenKey) ??
        const String.fromEnvironment('AWIKI_ACCESS_TOKEN', defaultValue: '');
    if (did.isEmpty || token.isEmpty) {
      return null;
    }

    final credentialName =
        await _secureStorage.read(key: _sessionCredentialKey) ??
        const String.fromEnvironment(
          'AWIKI_CREDENTIAL_NAME',
          defaultValue: 'default',
        );
    final displayName =
        await _secureStorage.read(key: _sessionDisplayNameKey) ??
        const String.fromEnvironment(
          'AWIKI_DISPLAY_NAME',
          defaultValue: 'awikime',
        );
    final handle =
        await _secureStorage.read(key: _sessionHandleKey) ??
        const String.fromEnvironment('AWIKI_HANDLE', defaultValue: '');
    _session = SessionIdentity(
      did: did,
      credentialName: credentialName,
      displayName: displayName,
      handle: handle.isEmpty ? null : handle,
      jwtToken: token,
    );
    await _persistSession(_session!);
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
    await _clearStoredIdentityMaterial();
  }

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async {
    final credentials = await _delegate.listLocalCredentials();
    return credentials.where(_isE1Identity).toList();
  }

  @override
  Future<SessionIdentity> loginWithLocalCredential(
    String credentialName,
  ) async {
    _session = await _delegate.loginWithLocalCredential(credentialName);
    _ensureE1Identity(_session!);
    return _session!;
  }

  @override
  Future<void> deleteLocalCredential(String credentialName) {
    return _delegate.deleteLocalCredential(credentialName);
  }

  @override
  Future<String?> exportCurrentCredentialAsZip() {
    return _delegate.exportCurrentCredentialAsZip();
  }

  @override
  Future<SessionIdentity?> importCredentialFromZip() async {
    _session = await _delegate.importCredentialFromZip();
    if (_session != null) {
      _ensureE1Identity(_session!);
    }
    return _session;
  }

  @override
  Future<void> sendOtp({required String phone}) {
    return _userService.sendOtp(phone: _normalizePhone(phone));
  }

  @override
  Future<void> sendEmailVerification({required String email}) {
    return _userService.sendEmailVerification(
      baseUrl: userServiceUrl,
      email: email,
    );
  }

  @override
  Future<bool> checkEmailVerified({required String email}) {
    return _userService.checkEmailVerified(
      baseUrl: userServiceUrl,
      email: email,
    );
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
    _session = await _registerHandleCore(
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
    return _session!;
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
    _session = await _registerHandleCore(
      pluginPayload: await _didRegistrationFacade.buildRegisterHandleParams(
        email: normalizedEmail,
        handle: normalizedHandle,
        inviteCode: inviteCode,
        nickName: nickName,
      ),
      authParams: <String, Object?>{'email': normalizedEmail},
      handle: normalizedHandle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
    return _session!;
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
    _session = await _registerHandleCore(
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
    return _session!;
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
    final session = await _requireSession();
    final result = await _userService.relationshipRpc(
      method: 'get_followers',
      params: const <String, Object?>{'limit': 100, 'offset': 0},
      bearerToken: session.jwtToken ?? '',
    );
    return _toRelationshipList(result, fallbackRelationship: 'follower');
  }

  @override
  Future<List<RelationshipSummary>> listFollowing() async {
    final session = await _requireSession();
    final result = await _userService.relationshipRpc(
      method: 'get_following',
      params: const <String, Object?>{'limit': 100, 'offset': 0},
      bearerToken: session.jwtToken ?? '',
    );
    return _toRelationshipList(result, fallbackRelationship: 'following');
  }

  @override
  Future<void> follow(String didOrHandle) async {
    final session = await _requireSession();
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    await _userService.relationshipRpc(
      method: 'follow',
      params: <String, Object?>{'target_did': targetDid},
      bearerToken: session.jwtToken ?? '',
    );
  }

  @override
  Future<void> unfollow(String didOrHandle) async {
    final session = await _requireSession();
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    await _userService.relationshipRpc(
      method: 'unfollow',
      params: <String, Object?>{'target_did': targetDid},
      bearerToken: session.jwtToken ?? '',
    );
  }

  @override
  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle) async {
    final session = await _requireSession();
    final targetDid = await _resolveDidOrHandle(didOrHandle);
    final result = await _userService.relationshipRpc(
      method: 'get_status',
      params: <String, Object?>{'target_did': targetDid},
      bearerToken: session.jwtToken ?? '',
    );
    return RelationshipSummary(
      did: result['did']?.toString() ?? targetDid,
      displayName:
          result['display_name']?.toString() ??
          result['name']?.toString() ??
          targetDid,
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
      final merged = _mapper.mergeConversations(cached, built);
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
    final isGroup = groupId != null && groupId.isNotEmpty;
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
      senderName: _session?.handle ?? _session?.displayName,
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
    await _localCache.upsertConversations(
      ownerDid: session.did,
      conversations: <ConversationSummary>[
        ConversationSummary(
          threadId: threadId,
          displayName: peerDid ?? groupId ?? threadId,
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
    String? groupMode,
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
      admissionMode: groupMode == null || groupMode.isEmpty
          ? 'open-join'
          : groupMode,
    );
    final created = _mapper.toGroupSummary(result);
    final summary = created.groupId.isNotEmpty
        ? await getGroup(created.groupId)
        : created;
    await _localCache.upsertGroups(
      ownerDid: session.did,
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<GroupSummary> joinGroup(String joinCode) async {
    if (!joinCode.startsWith('did:')) {
      return _delegate.joinGroup(joinCode);
    }
    final session = await _requireAnpSession(requireSigning: true);
    final result = await _messageService.joinGroup(
      session: session,
      groupDid: joinCode,
    );
    final summary = _mapper.toGroupSummary(<String, Object?>{
      'group_did': joinCode,
      ...result,
    });
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
      'group_did': groupId,
      ...result,
    });
    await _localCache.upsertGroups(
      ownerDid: session.did,
      groups: <GroupSummary>[summary],
    );
    return summary;
  }

  @override
  Future<String?> getGroupJoinCode(String groupId) {
    return _delegate.getGroupJoinCode(groupId);
  }

  @override
  Future<String?> refreshGroupJoinCode(String groupId) {
    return _delegate.refreshGroupJoinCode(groupId);
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
        final groupId =
            item['group_did']?.toString() ?? item['group_id']?.toString() ?? '';
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
    final result = rpcMethod == 'recover_handle'
        ? await _userService.recoverHandle(params: params)
        : await _userService.register(params: params);
    final didFromPayload = _extractDidFromPluginPayload(pluginPayload);
    final did = result['did']?.toString() ?? didFromPayload;
    final token = result['access_token']?.toString() ?? '';
    if (did.isEmpty || token.isEmpty) {
      throw StateError(
        'Handle registration succeeded but did/access_token is missing.',
      );
    }
    if (!_isE1Did(did)) {
      throw StateError('Only e1 DID identities are supported.');
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
      key: _sessionTokenKey,
      value: identity.jwtToken ?? '',
    );
    await _secureStorage.write(
      key: _sessionCredentialKey,
      value: identity.credentialName,
    );
    await _secureStorage.write(
      key: _sessionDisplayNameKey,
      value: identity.displayName,
    );
    await _secureStorage.write(
      key: _sessionHandleKey,
      value: identity.handle ?? '',
    );
    await _upsertSavedCredential(identity);
  }

  Future<void> _persistIdentityMaterialFromPluginPayload(
    Map<String, Object?> payload,
  ) async {
    final didDocument = payload['did_document'];
    final privateKeyPem = payload['private_key_pem']?.toString() ?? '';
    final domain = payload['domain']?.toString() ?? _didDomain();
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
    await _secureStorage.write(key: _sessionDidDomainKey, value: domain);
  }

  Future<void> _clearStoredIdentityMaterial() async {
    await _secureStorage.delete(key: _sessionDidDocumentKey);
    await _secureStorage.delete(key: _sessionPrivateKeyPemKey);
    await _secureStorage.delete(key: _sessionDidDomainKey);
  }

  Future<void> _refreshSessionOnRestore() async {
    try {
      await _tryRecoverAuthTokenViaStoredIdentity();
    } catch (_) {
      // Best-effort only; expired tokens are handled by service calls later.
    }
  }

  Future<bool> _tryRecoverAuthTokenViaStoredIdentity() async {
    final currentSession = _session;
    if (currentSession == null) {
      return false;
    }
    final didDocumentRaw = await _secureStorage.read(
      key: _sessionDidDocumentKey,
    );
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
    final result = await _userService.verifyDidAuth(
      authorization: authorization,
      domain: domain,
    );
    final newToken = result['access_token']?.toString() ?? '';
    final recoveredDid =
        result['did']?.toString() ??
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
  }

  Future<SessionIdentity?> _optionalSession() async {
    return _session ?? await restoreSession();
  }

  Future<SessionIdentity> _requireSession() async {
    final session = await _optionalSession();
    if (session == null || session.did.isEmpty) {
      throw StateError(
        'No active awiki session DID. Please restore session first.',
      );
    }
    _ensureE1Identity(session);
    return session;
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
          .map(
            (item) => item.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
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
            (item) => item.did.isNotEmpty && (item.jwtToken ?? '').isNotEmpty,
          )
          .toList();
    } catch (_) {
      return const <SessionIdentity>[];
    }
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
  }) {
    return _extractRelationshipRows(result)
        .map((item) {
          final did =
              item['did']?.toString() ??
              item['target_did']?.toString() ??
              item['user_did']?.toString() ??
              item['to_did']?.toString() ??
              item['from_did']?.toString() ??
              '';
          final name =
              item['display_name']?.toString() ??
              item['name']?.toString() ??
              item['nick_name']?.toString() ??
              item['handle']?.toString() ??
              did;
          return RelationshipSummary(
            did: did,
            displayName: name,
            relationship:
                item['relationship']?.toString() ??
                item['status']?.toString() ??
                fallbackRelationship,
          );
        })
        .where((item) => item.did.isNotEmpty)
        .toList();
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
      return value;
    }
    final session = await _optionalSession();
    final result = await _userService.getPublicProfile(
      didOrHandle: value,
      bearerToken: session?.jwtToken,
    );
    final did = result['did']?.toString() ?? '';
    if (did.isEmpty) {
      throw StateError('Failed to resolve handle to DID: $value');
    }
    return did;
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

  String _didDomain() {
    final configured = Uri.tryParse(userServiceUrl)?.host ?? '';
    if (configured.isNotEmpty) {
      return configured;
    }
    return 'awiki.ai';
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
    final conversation = _mapper.conversationFromMessage(
      message: message,
      ownerDid: session.did,
      previous: existingConversation,
      event: normalized,
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
      group = GroupSummary(
        groupId: message.groupId!,
        name:
            normalized['group_name']?.toString() ??
            existingConversation?.displayName ??
            'Group ${message.groupId}',
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

  Future<AwikiAnpSession> _requireAnpSession({
    bool requireSigning = false,
  }) async {
    var session = _session;
    session ??= await restoreSession();
    if (session == null || session.did.isEmpty) {
      throw StateError(
        'No active awiki session DID. Please restore session first.',
      );
    }
    final didDocumentRaw = await _secureStorage.read(
      key: _sessionDidDocumentKey,
    );
    final privateKeyPem = await _secureStorage.read(
      key: _sessionPrivateKeyPemKey,
    );
    Map<String, Object?>? didDocument;
    if (didDocumentRaw != null && didDocumentRaw.isNotEmpty) {
      final decoded = jsonDecode(didDocumentRaw);
      if (decoded is Map) {
        didDocument = decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }
    final anpSession = AwikiAnpSession(
      did: session.did,
      jwtToken: session.jwtToken ?? '',
      didDocument: didDocument,
      privateKeyPem: privateKeyPem,
    );
    if (!anpSession.isE1Did) {
      throw StateError('Only e1 DID identities are supported.');
    }
    if (requireSigning && !anpSession.canSign) {
      throw StateError('ANP signed message requires local DID key material.');
    }
    return anpSession;
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

  Map<String, Object?> _normalizeRealtimeEvent(Map<String, Object?> event) {
    final params = event['params'];
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
    merge(body);
    merge(message);
    return normalized;
  }

  bool _isE1Identity(SessionIdentity identity) => _isE1Did(identity.did);

  bool _isE1Did(String did) => did.trim().split(':').last.startsWith('e1_');

  void _ensureE1Identity(SessionIdentity identity) {
    if (!_isE1Identity(identity)) {
      throw StateError('Only e1 DID identities are supported.');
    }
  }
}
