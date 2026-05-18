import 'dart:async';

import '../apis/attachment_api.dart';
import '../apis/conversation_api.dart';
import '../apis/group_api.dart';
import '../apis/local_store_api.dart';
import '../apis/message_api.dart';
import '../apis/outbox_api.dart';
import '../apis/realtime_api.dart';
import '../apis/reserved_apis.dart';
import '../awiki_im_client.dart';
import '../models/client_models.dart';
import '../models/common.dart';
import '../models/error_models.dart';
import '../models/event_models.dart';
import '../models/group_models.dart';
import '../models/message_models.dart';

class FakeAwikiImClient implements AwikiImClient {
  FakeAwikiImClient()
    : _conversationsApi = _FakeConversationApi(),
      _messagesApi = _FakeMessageApi(),
      _groupsApi = _FakeGroupApi(),
      _realtimeApi = _FakeRealtimeApi(),
      _attachmentsApi = _FakeAttachmentApi(),
      _outboxApi = _FakeOutboxApi(),
      _localStoreApi = _FakeLocalStoreApi(),
      _directSecureApi = _ReservedDirectSecureApi(),
      _groupE2eeApi = _ReservedGroupE2eeApi(),
      _migrationApi = _ReservedMigrationApi(),
      _advancedAttachmentApi = _ReservedAdvancedAttachmentApi() {
    _conversationsApi._client = this;
    _messagesApi._client = this;
    _groupsApi._client = this;
    _realtimeApi._client = this;
    _attachmentsApi._client = this;
    _outboxApi._client = this;
    _localStoreApi._client = this;
  }

  final StreamController<ImEventDto> _eventController =
      StreamController<ImEventDto>.broadcast();
  final StreamController<ImConnectionStateDto> _connectionController =
      StreamController<ImConnectionStateDto>.broadcast();

  final _FakeConversationApi _conversationsApi;
  final _FakeMessageApi _messagesApi;
  final _FakeGroupApi _groupsApi;
  final _FakeRealtimeApi _realtimeApi;
  final _FakeAttachmentApi _attachmentsApi;
  final _FakeOutboxApi _outboxApi;
  final _FakeLocalStoreApi _localStoreApi;
  final _ReservedDirectSecureApi _directSecureApi;
  final _ReservedGroupE2eeApi _groupE2eeApi;
  final _ReservedMigrationApi _migrationApi;
  final _ReservedAdvancedAttachmentApi _advancedAttachmentApi;

  ImClientConfig? _config;
  ImSessionContext? _session;
  ImConnectionState _connectionState = ImConnectionState.idle;
  ImErrorDto? _lastError;
  int _nextId = 1;
  int _serverSequence = 1;
  final List<ImMessageDto> _messages = <ImMessageDto>[];
  final Map<String, ImConversationDto> _conversations =
      <String, ImConversationDto>{};
  final Map<String, ImGroupDto> _groups = <String, ImGroupDto>{};
  final Map<String, List<ImGroupMemberDto>> _members =
      <String, List<ImGroupMemberDto>>{};
  final Map<String, ImOutboxItemDto> _outbox = <String, ImOutboxItemDto>{};

  @override
  Stream<ImEventDto> get events => _eventController.stream;

  @override
  Stream<ImConnectionStateDto> get connectionStates =>
      _connectionController.stream;

  @override
  Future<void> initialize(ImClientConfig config) async {
    _config = config;
    _setConnectionState(ImConnectionState.idle);
  }

  @override
  Future<void> setSession(ImSessionContext session) async {
    _requireInitialized();
    _session = session;
  }

  @override
  Future<void> updateAuth(ImAuthUpdate update) async {
    final current = _session;
    if (current == null) {
      throw _error(ImErrorCode.unauthenticated, 'IM session is not set.');
    }
    _session = ImSessionContext(
      credentialName: current.credentialName,
      did: current.did,
      handle: current.handle,
      displayName: current.displayName,
      jwtToken: update.jwtToken ?? current.jwtToken,
      didDocument: current.didDocument,
      keyMaterialRef: current.keyMaterialRef,
      importedPrivateKey: current.importedPrivateKey,
      signerDelegateRef: current.signerDelegateRef,
    );
  }

  @override
  Future<void> clearSession() async {
    _session = null;
    _setConnectionState(ImConnectionState.idle);
  }

  @override
  Future<void> close() async {
    _setConnectionState(ImConnectionState.disconnected);
    await _eventController.close();
    await _connectionController.close();
  }

  @override
  Future<ImEngineStatusDto> status() async {
    return ImEngineStatusDto(
      initialized: _config != null,
      hasSession: _session != null,
      runtimeMode: _runtimeMode,
      connectionState: _connectionState,
      storePath: _config?.storePath,
      schemaVersion: 1,
      lastError: _lastError,
      metadata: <String, Object?>{'fake': true},
    );
  }

  @override
  Future<ImCapabilitiesDto> capabilities() async {
    return ImCapabilitiesDto(
      runtimeMode: _runtimeMode,
      localCache: true,
      outbox: true,
      realtime: true,
      attachments: true,
      advancedAttachments: false,
      directSecure: false,
      groupE2ee: false,
      migration: false,
      metadata: const <String, Object?>{
        'reserved': <String>[
          'advancedAttachments',
          'directSecure',
          'groupE2ee',
          'migration',
        ],
      },
    );
  }

  @override
  ImConversationApi get conversations => _conversationsApi;

  @override
  ImMessageApi get messages => _messagesApi;

  @override
  ImGroupApi get groups => _groupsApi;

  @override
  ImRealtimeApi get realtime => _realtimeApi;

  @override
  ImAttachmentApi get attachments => _attachmentsApi;

  @override
  ImOutboxApi get outbox => _outboxApi;

  @override
  ImLocalStoreApi get localStore => _localStoreApi;

  @override
  ImDirectSecureApi get directSecure => _directSecureApi;

  @override
  ImGroupE2eeApi get groupE2ee => _groupE2eeApi;

  @override
  ImMigrationApi get migration => _migrationApi;

  @override
  ImAdvancedAttachmentApi get advancedAttachments => _advancedAttachmentApi;

  ImRuntimeMode get _runtimeMode => _config?.runtimeMode ?? ImRuntimeMode.fake;

  void _requireInitialized() {
    if (_config == null) {
      throw _error(ImErrorCode.notReady, 'IM client is not initialized.');
    }
  }

  ImSessionContext _requireSession() {
    _requireInitialized();
    final session = _session;
    if (session == null) {
      throw _error(ImErrorCode.unauthenticated, 'IM session is not set.');
    }
    return session;
  }

  ImException _error(
    ImErrorCode code,
    String message, {
    bool retryable = false,
  }) {
    final exception = imException(code, message, retryable: retryable);
    _lastError = exception.error;
    return exception;
  }

  String _id(String prefix) => '$prefix-${_nextId++}';

  String _directThreadId(String ownerDid, String peerDidOrHandle) {
    final parts = <String>[ownerDid, peerDidOrHandle]..sort();
    return 'dm:${parts[0]}:${parts[1]}';
  }

  ImThreadRef _threadForTarget(ImSendTarget target, String ownerDid) {
    final groupId = target.groupId?.trim() ?? '';
    if (groupId.isNotEmpty) {
      return ImThreadRef(
        threadId: 'group:$groupId',
        kind: ImThreadKind.group,
        groupId: groupId,
      );
    }
    final peer = target.peerDidOrHandle?.trim() ?? '';
    if (peer.isEmpty) {
      throw _error(
        ImErrorCode.targetRequired,
        'Direct message target required.',
      );
    }
    return ImThreadRef(
      threadId: _directThreadId(ownerDid, peer),
      kind: ImThreadKind.direct,
      peerDid: peer.startsWith('did:') ? peer : null,
      peerHandle: peer.startsWith('did:') ? null : peer,
    );
  }

  void _setConnectionState(ImConnectionState state) {
    _connectionState = state;
    final dto = ImConnectionStateDto(
      state: state,
      runtimeMode: _runtimeMode,
      changedAt: DateTime.now().toUtc(),
      lastErrorCode: _lastError?.code.name,
      lastErrorMessage: _lastError?.message,
    );
    if (!_connectionController.isClosed) {
      _connectionController.add(dto);
    }
    _emit(
      ImEventDto(
        eventId: _id('event'),
        kind: ImEventKind.connectionChanged,
        occurredAt: dto.changedAt,
        connectionState: dto,
      ),
    );
  }

  void _emit(ImEventDto event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  ImPage<T> _page<T>(List<T> all, int limit, String? cursor) {
    final start = int.tryParse(cursor ?? '') ?? 0;
    final safeStart = start.clamp(0, all.length);
    final safeLimit = limit <= 0 ? all.length : limit;
    final end = (safeStart + safeLimit).clamp(safeStart, all.length);
    final items = all.sublist(safeStart, end);
    return ImPage<T>(
      items: items,
      nextCursor: end < all.length ? end.toString() : null,
      hasMore: end < all.length,
    );
  }

  void _upsertConversation(ImMessageDto message) {
    final thread = message.thread;
    final preview =
        message.plaintextText ??
        (message.attachments.isNotEmpty
            ? message.attachments.first.fileName
            : '');
    final previous = _conversations[thread.threadId];
    final unread =
        message.direction == ImMessageDirection.inbound &&
            message.readState == ImReadState.unread
        ? (previous?.unreadCount ?? 0) + 1
        : previous?.unreadCount ?? 0;
    _conversations[thread.threadId] = ImConversationDto(
      thread: thread,
      displayName: thread.kind == ImThreadKind.group
          ? thread.groupId ?? thread.threadId
          : thread.peerHandle ?? thread.peerDid ?? thread.threadId,
      lastMessagePreview: preview,
      lastMessageAt: message.createdAt,
      unreadCount: unread,
      securityMode: message.securityMode,
      avatarSeed: thread.groupId ?? thread.peerDid ?? thread.peerHandle,
    );
  }
}

class _FakeConversationApi implements ImConversationApi {
  late FakeAwikiImClient _client;

  @override
  Future<ImPage<ImConversationDto>> list(
    ImListConversationsRequest request,
  ) async {
    _client._requireSession();
    final items =
        _client._conversations.values
            .where(
              (item) =>
                  request.kind == null || item.thread.kind == request.kind,
            )
            .where((item) => !request.unreadOnly || item.unreadCount > 0)
            .toList()
          ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    return _client._page(items, request.limit, request.cursor);
  }

  @override
  Future<ImConversationDto?> get(String threadId) async {
    _client._requireSession();
    return _client._conversations[threadId];
  }

  @override
  Future<void> markThreadRead(String threadId) async {
    _client._requireSession();
    final previous = _client._conversations[threadId];
    if (previous != null) {
      _client._conversations[threadId] = ImConversationDto(
        thread: previous.thread,
        displayName: previous.displayName,
        lastMessagePreview: previous.lastMessagePreview,
        lastMessageAt: previous.lastMessageAt,
        unreadCount: 0,
        securityMode: previous.securityMode,
        avatarSeed: previous.avatarSeed,
        metadata: previous.metadata,
      );
    }
    for (var i = 0; i < _client._messages.length; i++) {
      final message = _client._messages[i];
      if (message.thread.threadId == threadId) {
        _client._messages[i] = message.copyWith(readState: ImReadState.read);
      }
    }
  }

  @override
  Future<void> deleteLocalThread(String threadId) async {
    _client._requireSession();
    _client._conversations.remove(threadId);
    _client._messages.removeWhere(
      (message) => message.thread.threadId == threadId,
    );
  }
}

class _FakeMessageApi implements ImMessageApi {
  late FakeAwikiImClient _client;

  @override
  Future<ImPage<ImMessageDto>> list(ImListMessagesRequest request) async {
    _client._requireSession();
    final items =
        _client._messages
            .where(
              (message) => message.thread.threadId == request.thread.threadId,
            )
            .where(
              (message) =>
                  request.includeLocalPending ||
                  message.sendState != ImSendState.queued &&
                      message.sendState != ImSendState.sending,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return _client._page(items, request.limit, request.cursor);
  }

  @override
  Future<ImSendResultDto> send(ImSendMessageRequest request) async {
    final session = _client._requireSession();
    if (request.securityMode != ImSecurityMode.transportProtected) {
      throw _client._error(
        ImErrorCode.featureDisabled,
        'Secure message modes are reserved in the fake IM core.',
      );
    }
    if ((request.text ?? '').trim().isEmpty && request.attachments.isEmpty) {
      throw _client._error(
        ImErrorCode.messageTextRequired,
        'Message text or attachment is required.',
      );
    }
    final thread = _client._threadForTarget(request.target, session.did);
    final now = DateTime.now().toUtc();
    final forceFail = request.metadata['forceFail'] == true;
    final localId = _client._id('local');
    final remoteId = forceFail ? null : _client._id('remote');
    final attachments = <ImAttachmentDto>[
      for (final input in request.attachments)
        ImAttachmentDto(
          attachmentId: _client._id('attachment'),
          fileName: input.fileName,
          mimeType: input.mimeType ?? 'application/octet-stream',
          sizeBytes: input.bytes?.length,
          localPath: input.localPath,
        ),
    ];
    final message = ImMessageDto(
      localId: localId,
      remoteId: remoteId,
      thread: thread,
      direction: ImMessageDirection.outbound,
      kind: attachments.isEmpty ? ImMessageKind.text : ImMessageKind.attachment,
      securityMode: request.securityMode,
      sendState: forceFail ? ImSendState.failed : ImSendState.sent,
      readState: ImReadState.read,
      senderDid: session.did,
      senderHandle: session.handle,
      senderDisplayName: session.displayName,
      receiverDid: thread.kind == ImThreadKind.direct
          ? thread.peerDid ?? thread.peerHandle
          : null,
      groupId: thread.groupId,
      plaintextText: request.text,
      content: <String, Object?>{
        if (request.text != null) 'text': request.text,
        'messageType': request.messageType,
      },
      attachments: attachments,
      createdAt: now,
      acceptedAt: forceFail ? null : now,
      serverSequence: forceFail ? null : _client._serverSequence++,
      operationId: request.clientOperationId ?? _client._id('operation'),
      errorCode: forceFail ? ImErrorCode.transportUnavailable.name : null,
      retryHint: forceFail ? 'retry-after-transport-recovers' : null,
    );
    _client._messages.add(message);
    _client._upsertConversation(message);
    if (forceFail) {
      final outboxId = _client._id('outbox');
      _client._outbox[outboxId] = ImOutboxItemDto(
        outboxId: outboxId,
        target: request.target,
        visibleMessage: message,
        state: ImSendState.failed,
        attemptCount: 1,
        lastErrorCode: ImErrorCode.transportUnavailable.name,
        retryHint: 'retry-after-transport-recovers',
        createdAt: now,
        lastAttemptAt: now,
      );
    }
    _client._emit(
      ImEventDto(
        eventId: _client._id('event'),
        kind: ImEventKind.messageUpdated,
        occurredAt: now,
        message: message,
        conversation: _client._conversations[thread.threadId],
      ),
    );
    return ImSendResultDto(
      message: message,
      accepted: !forceFail,
      finalAcceptance: !forceFail,
      remoteMessageId: remoteId,
      operationId: message.operationId,
      deliveryState: message.sendState.name,
    );
  }

  @override
  Future<void> markRead(ImMarkReadRequest request) async {
    _client._requireSession();
    if (request.threadId != null) {
      await _client.conversations.markThreadRead(request.threadId!);
      return;
    }
    final ids = request.messageIds.toSet();
    for (var i = 0; i < _client._messages.length; i++) {
      final message = _client._messages[i];
      if (ids.contains(message.localId) ||
          (message.remoteId != null && ids.contains(message.remoteId))) {
        _client._messages[i] = message.copyWith(readState: ImReadState.read);
      }
    }
  }

  @override
  Future<void> sync(ImSyncRequest request) async {
    _client._requireSession();
    _client._emit(
      ImEventDto(
        eventId: _client._id('event'),
        kind: ImEventKind.syncCompleted,
        occurredAt: DateTime.now().toUtc(),
        metadata: <String, Object?>{
          if (request.threadId != null) 'threadId': request.threadId,
        },
      ),
    );
  }
}

class _FakeAttachmentApi implements ImAttachmentApi {
  late FakeAwikiImClient _client;

  @override
  Future<ImSendResultDto> sendAttachment(ImSendMessageRequest request) {
    return _client.messages.send(request);
  }

  @override
  Future<ImAttachmentDownloadResultDto> download(
    ImAttachmentDownloadRequest request,
  ) async {
    _client._requireSession();
    ImMessageDto? message;
    for (final item in _client._messages) {
      if (item.thread.threadId == request.thread.threadId &&
          (item.localId == request.messageId ||
              item.remoteId == request.messageId)) {
        message = item;
        break;
      }
    }
    if (message == null) {
      throw _client._error(ImErrorCode.messageNotFound, 'Message not found.');
    }
    ImAttachmentDto? attachment;
    for (final item in message.attachments) {
      if (request.attachmentId == null ||
          item.attachmentId == request.attachmentId) {
        attachment = item;
        break;
      }
    }
    if (attachment == null) {
      throw _client._error(
        ImErrorCode.attachmentNotFound,
        'Attachment not found.',
      );
    }
    return ImAttachmentDownloadResultDto(
      transferId: _client._id('transfer'),
      outputPath: request.outputPath,
      attachment: attachment,
    );
  }

  @override
  Stream<ImAttachmentTransferEventDto> transferEvents(String transferId) {
    return Stream<ImAttachmentTransferEventDto>.value(
      ImAttachmentTransferEventDto(transferId: transferId, state: 'completed'),
    );
  }
}

class _FakeGroupApi implements ImGroupApi {
  late FakeAwikiImClient _client;

  @override
  Future<ImGroupDto> create(ImCreateGroupRequest request) async {
    final session = _client._requireSession();
    final groupId = _client._id('group');
    final group = ImGroupDto(
      groupId: groupId,
      groupDid: groupId,
      name: request.name,
      description: request.description,
      slug: request.slug,
      goal: request.goal,
      rules: request.rules,
      messagePrompt: request.messagePrompt,
      policy: request.policy,
      myRole: 'owner',
      membershipStatus: 'active',
      memberCount: 1,
      metadata: request.metadata,
    );
    _client._groups[groupId] = group;
    _client._members[groupId] = <ImGroupMemberDto>[
      ImGroupMemberDto(
        did: session.did,
        handle: session.handle,
        role: 'owner',
        status: 'active',
      ),
    ];
    return group;
  }

  @override
  Future<ImGroupDto> get(String groupId) async {
    _client._requireSession();
    return _client._groups[groupId] ??
        (throw _client._error(ImErrorCode.groupRequired, 'Group not found.'));
  }

  @override
  Future<ImGroupDto> join(ImJoinGroupRequest request) async =>
      get(request.groupId);

  @override
  Future<ImGroupDto> addMember(ImGroupMemberMutationRequest request) async {
    final group = await get(request.groupId);
    final members = _client._members.putIfAbsent(
      request.groupId,
      () => <ImGroupMemberDto>[],
    );
    members.add(
      ImGroupMemberDto(
        did: request.memberDidOrHandle,
        role: request.role,
        status: 'active',
      ),
    );
    final updated = ImGroupDto(
      groupId: group.groupId,
      groupDid: group.groupDid,
      name: group.name,
      description: group.description,
      slug: group.slug,
      goal: group.goal,
      rules: group.rules,
      messagePrompt: group.messagePrompt,
      docUrl: group.docUrl,
      policy: group.policy,
      myRole: group.myRole,
      membershipStatus: group.membershipStatus,
      memberCount: members.length,
      lastMessageAt: group.lastMessageAt,
      metadata: group.metadata,
    );
    _client._groups[request.groupId] = updated;
    return updated;
  }

  @override
  Future<ImGroupDto> removeMember(ImGroupMemberMutationRequest request) async {
    final group = await get(request.groupId);
    final members = _client._members.putIfAbsent(
      request.groupId,
      () => <ImGroupMemberDto>[],
    )..removeWhere((member) => member.did == request.memberDidOrHandle);
    final updated = ImGroupDto(
      groupId: group.groupId,
      groupDid: group.groupDid,
      name: group.name,
      description: group.description,
      slug: group.slug,
      goal: group.goal,
      rules: group.rules,
      messagePrompt: group.messagePrompt,
      docUrl: group.docUrl,
      policy: group.policy,
      myRole: group.myRole,
      membershipStatus: group.membershipStatus,
      memberCount: members.length,
      lastMessageAt: group.lastMessageAt,
      metadata: group.metadata,
    );
    _client._groups[request.groupId] = updated;
    return updated;
  }

  @override
  Future<ImGroupDto> leave(ImLeaveGroupRequest request) async =>
      get(request.groupId);

  @override
  Future<ImGroupDto> update(ImUpdateGroupRequest request) async {
    final group = await get(request.groupId);
    final updated = ImGroupDto(
      groupId: group.groupId,
      groupDid: group.groupDid,
      name: request.name ?? group.name,
      description: request.description ?? group.description,
      slug: request.slug ?? group.slug,
      goal: request.goal ?? group.goal,
      rules: request.rules ?? group.rules,
      messagePrompt: request.messagePrompt ?? group.messagePrompt,
      docUrl: request.docUrl ?? group.docUrl,
      policy: request.policy ?? group.policy,
      myRole: group.myRole,
      membershipStatus: group.membershipStatus,
      memberCount: group.memberCount,
      lastMessageAt: group.lastMessageAt,
      metadata: <String, Object?>{...group.metadata, ...request.metadata},
    );
    _client._groups[request.groupId] = updated;
    return updated;
  }

  @override
  Future<ImPage<ImGroupMemberDto>> listMembers(
    ImListGroupMembersRequest request,
  ) async {
    _client._requireSession();
    final members =
        _client._members[request.groupId] ?? const <ImGroupMemberDto>[];
    return _client._page(members, request.limit, null);
  }

  @override
  Future<ImPage<ImMessageDto>> listMessages(
    ImListGroupMessagesRequest request,
  ) async {
    final thread = ImThreadRef(
      threadId: 'group:${request.groupId}',
      kind: ImThreadKind.group,
      groupId: request.groupId,
    );
    return _client.messages.list(
      ImListMessagesRequest(
        thread: thread,
        limit: request.limit,
        cursor: request.cursor,
      ),
    );
  }
}

class _FakeRealtimeApi implements ImRealtimeApi {
  late FakeAwikiImClient _client;

  @override
  Future<void> connect(ImRealtimeConnectRequest request) async {
    _client._requireSession();
    _client._setConnectionState(ImConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _client._setConnectionState(ImConnectionState.disconnected);
  }

  @override
  Future<ImConnectionStateDto> status() async {
    final state = await _client.status();
    return ImConnectionStateDto(
      state: state.connectionState,
      runtimeMode: state.runtimeMode,
      changedAt: DateTime.now().toUtc(),
      lastErrorCode: state.lastError?.code.name,
      lastErrorMessage: state.lastError?.message,
    );
  }
}

class _FakeOutboxApi implements ImOutboxApi {
  late FakeAwikiImClient _client;

  @override
  Future<ImPage<ImOutboxItemDto>> list(ImListOutboxRequest request) async {
    _client._requireSession();
    final items =
        _client._outbox.values
            .where(
              (item) => !request.failedOnly || item.state == ImSendState.failed,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return _client._page(items, request.limit, request.cursor);
  }

  @override
  Future<ImSendResultDto> retry(String outboxId) async {
    _client._requireSession();
    final item = _client._outbox[outboxId];
    if (item == null) {
      throw _client._error(
        ImErrorCode.messageNotFound,
        'Outbox item not found.',
      );
    }
    final result = await _client.messages.send(
      ImSendMessageRequest(
        target: item.target,
        text: item.visibleMessage?.plaintextText ?? 'retry',
        metadata: const <String, Object?>{},
      ),
    );
    _client._outbox.remove(outboxId);
    return result;
  }

  @override
  Future<void> drop(String outboxId) async {
    _client._requireSession();
    _client._outbox.remove(outboxId);
  }
}

class _FakeLocalStoreApi implements ImLocalStoreApi {
  late FakeAwikiImClient _client;

  @override
  Future<ImStoreStatsDto> stats() async {
    _client._requireInitialized();
    final unread = _client._conversations.values.fold<int>(
      0,
      (sum, item) => sum + item.unreadCount,
    );
    return ImStoreStatsDto(
      messageCount: _client._messages.length,
      conversationCount: _client._conversations.length,
      groupCount: _client._groups.length,
      outboxCount: _client._outbox.length,
      unreadCount: unread,
      schemaVersion: 1,
      storePath: _client._config?.storePath ?? 'memory://fake-im-core',
    );
  }

  @override
  Future<void> clear(ImClearStoreRequest request) async {
    _client._messages.clear();
    _client._conversations.clear();
    _client._groups.clear();
    _client._members.clear();
    if (request.includeOutbox) {
      _client._outbox.clear();
    }
  }

  @override
  Future<void> compact() async {
    _client._requireInitialized();
  }
}

Never _reservedFeature([String feature = 'reserved feature']) {
  throw imException(
    ImErrorCode.featureDisabled,
    '$feature is reserved and disabled in Phase 1 fake IM core.',
  );
}

class _ReservedDirectSecureApi implements ImDirectSecureApi {
  @override
  Future<void> drop(String outboxId) async => _reservedFeature('direct secure');

  @override
  Future<ImPage<ImOutboxItemDto>> failed(ImListOutboxRequest request) async =>
      _reservedFeature('direct secure');

  @override
  Future<ImDirectSecureInitResultDto> init(
    ImDirectSecurePeerRequest request,
  ) async => _reservedFeature('direct secure');

  @override
  Future<ImDirectSecureRepairResultDto> repair(
    ImDirectSecurePeerRequest request,
  ) async => _reservedFeature('direct secure');

  @override
  Future<ImSendResultDto> retry(String outboxId) async =>
      _reservedFeature('direct secure');

  @override
  Future<ImDirectSecureStatusDto> status({String? peerDidOrHandle}) async =>
      _reservedFeature('direct secure');
}

class _ReservedGroupE2eeApi implements ImGroupE2eeApi {
  @override
  Future<ImPage<ImGroupE2eeNoticeDto>> pending(
    ImGroupE2eeNoticeRequest request,
  ) async => _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeMutationResultDto> processLeaveRequest(
    ImGroupE2eeProcessLeaveRequest request,
  ) async => _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeKeyPackageResultDto> publishKeyPackage(
    ImGroupE2eePublishKeyPackageRequest request,
  ) async => _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeRepairResultDto> repair(
    ImGroupE2eeNoticeRequest request,
  ) async => _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeMutationResultDto> rejoin(
    ImGroupE2eeRejoinRequest request,
  ) async => _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeMutationResultDto> recoverMember(
    ImGroupE2eeMemberRequest request,
  ) async => _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeStatusDto> status(ImGroupE2eeStatusRequest request) async =>
      _reservedFeature('group E2EE');

  @override
  Future<ImGroupE2eeMutationResultDto> updateKey(
    ImGroupE2eeMemberRequest request,
  ) async => _reservedFeature('group E2EE');
}

class _ReservedMigrationApi implements ImMigrationApi {
  @override
  Future<ImExportResultDto> exportStore(ImExportStoreRequest request) async =>
      _reservedFeature('migration');

  @override
  Future<ImImportResultDto> importStore(ImImportStoreRequest request) async =>
      _reservedFeature('migration');

  @override
  Future<ImMigrationPlanDto> plan(ImMigrationPlanRequest request) async =>
      _reservedFeature('migration');

  @override
  Future<ImSyncRepairResultDto> repairSync(ImSyncRepairRequest request) async =>
      _reservedFeature('migration');

  @override
  Future<ImMigrationResultDto> run(ImMigrationRunRequest request) async =>
      _reservedFeature('migration');

  @override
  Future<ImSyncStateDto> syncState() async => _reservedFeature('migration');
}

class _ReservedAdvancedAttachmentApi implements ImAdvancedAttachmentApi {
  @override
  Future<void> cancelTransfer(String transferId) async =>
      _reservedFeature('advanced attachments');

  @override
  Future<ImAttachmentUploadSessionDto> createUploadSession(
    ImAttachmentUploadSessionRequest request,
  ) async => _reservedFeature('advanced attachments');

  @override
  Future<ImAttachmentTransferResultDto> resumeTransfer(
    String transferId,
  ) async => _reservedFeature('advanced attachments');
}
