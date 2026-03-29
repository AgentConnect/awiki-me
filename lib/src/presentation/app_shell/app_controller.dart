import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../../domain/entities/bridge_capabilities.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/awiki_gateway.dart';
import '../../domain/services/e2ee_facade.dart';
import '../../domain/services/notification_facade.dart';
import '../../domain/services/realtime_gateway.dart';
import '../chat/chat_page.dart';

class AppController extends ChangeNotifier {
  static const Duration _requestTimeout = Duration(seconds: 20);

  AppController({
    required AwikiGateway gateway,
    required RealtimeGateway realtimeGateway,
    required NotificationFacade notificationFacade,
    required E2eeFacade e2eeFacade,
  })  : _gateway = gateway,
        _realtimeGateway = realtimeGateway,
        _notificationFacade = notificationFacade,
        _e2eeFacade = e2eeFacade;

  final AwikiGateway _gateway;
  final RealtimeGateway _realtimeGateway;
  final NotificationFacade _notificationFacade;
  final E2eeFacade _e2eeFacade;

  SessionIdentity? session;
  UserProfile? profile;
  BridgeCapabilities? capabilities;
  List<ConversationSummary> conversations = const <ConversationSummary>[];
  List<RelationshipSummary> followers = const <RelationshipSummary>[];
  List<RelationshipSummary> following = const <RelationshipSummary>[];
  List<GroupSummary> groups = const <GroupSummary>[];
  List<SessionIdentity> localCredentials = const <SessionIdentity>[];
  final Map<String, List<ChatMessage>> messagesByThread =
      <String, List<ChatMessage>>{};
  final Map<String, List<GroupMemberSummary>> membersByGroup =
      <String, List<GroupMemberSummary>>{};
  bool isInitialized = false;
  bool isBusy = false;
  String? errorMessage;
  String? infoMessage;
  DateTime? lastFriendsRefreshAt;
  String? lastFriendsRefreshError;
  int friendsRefreshCount = 0;
  final Set<String> _openingGroupThreadIds = <String>{};

  Future<void> initialize() async {
    if (isInitialized) {
      return;
    }
    await _runBusy(() async {
      capabilities = await _gateway.loadCapabilities();
      session = await _gateway.restoreSession();
      if (session != null) {
        await _e2eeFacade.initialize(session!);
        await refreshHome();
        await _realtimeGateway.connect(
          session: session!,
          onMessage: _handleRealtimeMessage,
        );
      }
      isInitialized = true;
    });
  }

  bool get isLoggedIn => session != null;

  int get unreadCount => conversations.fold<int>(
        0,
        (sum, item) => sum + item.unreadCount,
      );

  Future<void> loginWithOtp({
    required String phone,
    required String otp,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      session = await _gateway.registerHandle(
        phone: phone,
        otp: otp,
        handle: handle,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      );
      profile = await _gateway.loadMyProfile();
      await refreshHome();
      if (session != null && !_realtimeGateway.isConnected) {
        await _realtimeGateway.connect(
          session: session!,
          onMessage: _handleRealtimeMessage,
        );
      }
    });
  }

  Future<void> loginExistingWithOtp({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    await _runBusy(() async {
      session = await _gateway.recoverHandle(
        phone: phone,
        otp: otp,
        handle: handle,
      );
      profile = await _gateway.loadMyProfile();
      await refreshHome();
      if (session != null && !_realtimeGateway.isConnected) {
        await _realtimeGateway.connect(
          session: session!,
          onMessage: _handleRealtimeMessage,
        );
      }
    });
  }

  Future<void> requestOtp(String phone) async {
    await _runBusy(() => _gateway.sendOtp(phone: phone));
  }

  Future<void> refreshLocalCredentials() async {
    localCredentials = await _gateway.listLocalCredentials();
    notifyListeners();
  }

  Future<void> requestEmailActivation(String email) async {
    await _runBusy(() => _gateway.sendEmailVerification(email: email));
  }

  Future<bool> checkEmailActivation(String email) async {
    var verified = false;
    await _runBusy(() async {
      verified = await _gateway.checkEmailVerified(email: email);
      if (!verified) {
        errorMessage = '邮箱尚未激活，请先点击邮件中的激活链接。';
      }
    });
    return verified;
  }

  Future<void> loginWithEmail({
    required String email,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      final verified = await _gateway.checkEmailVerified(email: email);
      if (!verified) {
        throw StateError('邮箱尚未激活，请先点击邮件中的激活链接。');
      }
      session = await _gateway.registerHandleWithEmail(
        email: email,
        handle: handle,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      );
      profile = await _gateway.loadMyProfile();
      await refreshHome();
      if (session != null && !_realtimeGateway.isConnected) {
        await _realtimeGateway.connect(
          session: session!,
          onMessage: _handleRealtimeMessage,
        );
      }
    });
  }

  Future<void> refreshHome() async {
    profile = await _gateway.loadMyProfile();
    conversations = await _gateway.listConversations();
    followers = await _gateway.listFollowers();
    following = await _gateway.listFollowing();
    groups = await _gateway.listGroups();
    await _notificationFacade.updateBadgeCount(unreadCount);
    notifyListeners();
  }

  Future<void> openConversation(ConversationSummary conversation) async {
    await _runBusy(() async {
      final history = conversation.isGroup
          ? await _gateway.fetchGroupHistory(conversation.groupId ?? '')
          : await _gateway.fetchDmHistory(conversation.targetDid ?? '');
      messagesByThread[conversation.threadId] = _sortMessages(history);
      await _gateway.markRead(conversation.threadId);
      await refreshHome();
    });
  }

  List<ChatMessage> messagesForThread(String threadId) {
    return messagesByThread[threadId] ?? const <ChatMessage>[];
  }

  Future<void> sendMessage({
    required ConversationSummary conversation,
    required String content,
  }) async {
    if (content.trim().isEmpty || session == null) {
      return;
    }
    final pending = ChatMessage(
      localId: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      threadId: conversation.threadId,
      senderDid: session!.did,
      senderName: session!.handle ?? session!.displayName,
      receiverDid: conversation.targetDid,
      groupId: conversation.groupId,
      content: content.trim(),
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sending,
    );
    final messages =
        List<ChatMessage>.from(messagesForThread(conversation.threadId))
          ..add(pending);
    messagesByThread[conversation.threadId] = _sortMessages(messages);
    notifyListeners();

    try {
      final sent = await _gateway.sendTextMessage(
        threadId: conversation.threadId,
        peerDid: conversation.targetDid,
        groupId: conversation.groupId,
        content: content.trim(),
      );
      final replaced = messages
          .map((item) => item.localId == pending.localId ? sent : item)
          .toList();
      messagesByThread[conversation.threadId] = _sortMessages(replaced);
    } catch (_) {
      final failed = pending.copyWith(sendState: MessageSendState.failed);
      final replaced = messages
          .map((item) => item.localId == pending.localId ? failed : item)
          .toList();
      messagesByThread[conversation.threadId] = _sortMessages(replaced);
    }
    await refreshHome();
  }

  Future<void> retryMessage({
    required ConversationSummary conversation,
    required ChatMessage message,
  }) async {
    final retried = await _gateway.retryMessage(message);
    final updated = messagesForThread(conversation.threadId)
        .map((item) => item.localId == message.localId ? retried : item)
        .toList();
    messagesByThread[conversation.threadId] = _sortMessages(updated);
    await refreshHome();
  }

  Future<void> updateMyProfile(ProfilePatch patch) async {
    await _runBusy(() async {
      profile = await _gateway.updateProfile(patch);
      infoMessage = '个人资料已更新';
    });
  }

  Future<void> followUser(String didOrHandle) async {
    await _runBusy(() async {
      await _gateway.follow(didOrHandle);
      await refreshHome();
    });
  }

  Future<void> refreshFriendsTab() async {
    await _runBusy(() async {
      followers = await _gateway.listFollowers();
      following = await _gateway.listFollowing();
    });
    lastFriendsRefreshAt = DateTime.now();
    lastFriendsRefreshError = errorMessage;
    friendsRefreshCount += 1;
    notifyListeners();
  }

  Future<void> logout() async {
    await _runBusy(() async {
      await _realtimeGateway.disconnect();
      await _gateway.logout();
      localCredentials = await _gateway.listLocalCredentials();
      session = null;
      profile = null;
      conversations = const <ConversationSummary>[];
      followers = const <RelationshipSummary>[];
      following = const <RelationshipSummary>[];
      groups = const <GroupSummary>[];
      messagesByThread.clear();
      membersByGroup.clear();
      lastFriendsRefreshAt = null;
      lastFriendsRefreshError = null;
      friendsRefreshCount = 0;
      await _notificationFacade.updateBadgeCount(0);
    });
  }

  Future<void> loginWithLocalCredential(String credentialName) async {
    await _runBusy(() async {
      session = await _gateway.loginWithLocalCredential(credentialName);
      await _e2eeFacade.initialize(session!);
      await refreshHome();
      if (!_realtimeGateway.isConnected) {
        await _realtimeGateway.connect(
          session: session!,
          onMessage: _handleRealtimeMessage,
        );
      }
    });
  }

  Future<void> deleteCurrentCredential() async {
    final current = session;
    if (current == null) {
      return;
    }
    await _runBusy(() async {
      await _realtimeGateway.disconnect();
      await _gateway.deleteLocalCredential(current.credentialName);
      await _gateway.logout();
      localCredentials = await _gateway.listLocalCredentials();
      session = null;
      profile = null;
      conversations = const <ConversationSummary>[];
      followers = const <RelationshipSummary>[];
      following = const <RelationshipSummary>[];
      groups = const <GroupSummary>[];
      messagesByThread.clear();
      membersByGroup.clear();
      lastFriendsRefreshAt = null;
      lastFriendsRefreshError = null;
      friendsRefreshCount = 0;
      await _notificationFacade.updateBadgeCount(0);
    });
  }

  Future<void> exportCurrentCredential() async {
    await _runBusy(() async {
      final exportedPath = await _gateway.exportCurrentCredentialAsZip();
      if (exportedPath != null && exportedPath.isNotEmpty) {
        infoMessage = '已导出到 $exportedPath';
      }
    });
  }

  Future<void> importCredentialArchive() async {
    await _runBusy(() async {
      final imported = await _gateway.importCredentialFromZip();
      if (imported == null) {
        return;
      }
      localCredentials = await _gateway.listLocalCredentials();
      infoMessage = '导入成功，请选择该凭证登录';
    });
  }

  Future<void> unfollowUser(String didOrHandle) async {
    await _runBusy(() async {
      await _gateway.unfollow(didOrHandle);
      await refreshHome();
    });
  }

  Future<RelationshipSummary?> checkRelationship(String didOrHandle) async {
    RelationshipSummary? status;
    await _runBusy(() async {
      status = await _gateway.getRelationshipStatus(didOrHandle);
    });
    return status;
  }

  Future<UserProfile?> loadPeerProfile(String didOrHandle) async {
    UserProfile? peerProfile;
    await _runBusy(() async {
      peerProfile = await _gateway.loadPublicProfile(didOrHandle);
    });
    return peerProfile;
  }

  Future<void> loadGroupMembers(String groupId) async {
    await _runBusy(() async {
      membersByGroup[groupId] = await _gateway.listGroupMembers(groupId);
      notifyListeners();
    });
  }

  Future<void> refreshGroups() async {
    await _runBusy(() async {
      groups = await _gateway.listGroups();
      notifyListeners();
    });
  }

  Future<GroupSummary?> refreshGroup(String groupId) async {
    GroupSummary? group;
    await _runBusy(() async {
      group = await _gateway.getGroup(groupId);
      _upsertGroup(group!);
      membersByGroup[groupId] = await _gateway.listGroupMembers(groupId);
      notifyListeners();
    });
    return group;
  }

  Future<void> deleteThread(String threadId) async {
    await _gateway.deleteLocalThread(threadId);
    messagesByThread.remove(threadId);
    await refreshHome();
  }

  Future<GroupSummary?> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    String? groupMode,
  }) async {
    GroupSummary? createdGroup;
    await _runBusy(() async {
      createdGroup = await _gateway.createGroup(
        name: name,
        slug: slug,
        description: description,
        goal: goal,
        rules: rules,
        messagePrompt: messagePrompt,
        groupMode: groupMode,
      );
      _upsertGroup(createdGroup!);
      notifyListeners();
    });
    return createdGroup;
  }

  Future<GroupSummary?> joinGroup(String joinCode) async {
    GroupSummary? joinedGroup;
    await _runBusy(() async {
      joinedGroup = await _gateway.joinGroup(joinCode);
      _upsertGroup(joinedGroup!);
      notifyListeners();
    });
    return joinedGroup;
  }

  Future<String?> getGroupJoinCode(String groupId) async {
    String? joinCode;
    await _runBusy(() async {
      joinCode = await _gateway.getGroupJoinCode(groupId);
      final refreshed = await _gateway.getGroup(groupId);
      _upsertGroup(refreshed);
      notifyListeners();
    });
    return joinCode;
  }

  Future<String?> refreshGroupJoinCode(String groupId) async {
    String? joinCode;
    await _runBusy(() async {
      joinCode = await _gateway.refreshGroupJoinCode(groupId);
      final refreshed = await _gateway.getGroup(groupId);
      _upsertGroup(refreshed);
      notifyListeners();
    });
    return joinCode;
  }

  Future<void> openGroupChat(
    BuildContext context, {
    required GroupSummary group,
  }) async {
    final conversation = ConversationSummary(
      threadId: 'group:${group.groupId}',
      displayName: group.name,
      lastMessagePreview: '',
      lastMessageAt: group.lastMessageAt ?? DateTime.now(),
      unreadCount: 0,
      isGroup: true,
      groupId: group.groupId,
      avatarSeed: group.groupId,
    );
    if (_openingGroupThreadIds.contains(conversation.threadId)) {
      return;
    }
    _openingGroupThreadIds.add(conversation.threadId);
    try {
      await openConversation(conversation);
      if (!context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        CupertinoPageRoute<void>(
          builder: (_) => ChatPage(
            controller: this,
            conversation: conversation,
          ),
        ),
      );
    } finally {
      _openingGroupThreadIds.remove(conversation.threadId);
    }
  }

  Future<void> _handleRealtimeMessage(Map<String, Object?> event) async {
    final update = await _gateway.consumeRealtimeEvent(event);
    if (update == null) {
      return;
    }

    final threadMessages = List<ChatMessage>.from(
      messagesByThread[update.conversation.threadId] ?? const <ChatMessage>[],
    );
    final messageIndex = threadMessages.indexWhere(
      (item) =>
          (update.message.remoteId != null &&
              item.remoteId == update.message.remoteId) ||
          item.localId == update.message.localId,
    );
    if (messageIndex >= 0) {
      threadMessages[messageIndex] = update.message;
    } else {
      threadMessages.add(update.message);
    }
    messagesByThread[update.conversation.threadId] =
        _sortMessages(threadMessages);

    _upsertConversation(update.conversation);
    if (update.group != null) {
      _upsertGroup(update.group!);
    }

    await _notificationFacade.updateBadgeCount(unreadCount);
    notifyListeners();

    if (!update.message.isMine) {
      await _notificationFacade.showInAppBanner(
        title: update.conversation.displayName,
        body: update.message.content.isNotEmpty
            ? update.message.content
            : '你收到了新消息',
      );
    }
  }

  void _upsertConversation(ConversationSummary conversation) {
    final byThread = <String, ConversationSummary>{
      for (final item in conversations) item.threadId: item,
    };
    byThread[conversation.threadId] = conversation;
    final merged = byThread.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    conversations = merged;
  }

  void _upsertGroup(GroupSummary group) {
    final byGroupId = <String, GroupSummary>{
      for (final item in groups) item.groupId: item,
    };
    byGroupId[group.groupId] = group;
    final merged = byGroupId.values.toList()
      ..sort(
        (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
                a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    groups = merged;
  }

  List<ChatMessage> _sortMessages(List<ChatMessage> messages) {
    final sorted = List<ChatMessage>.from(messages);
    sorted.sort((a, b) {
      final aSeq = a.serverSequence;
      final bSeq = b.serverSequence;
      if (aSeq != null && bSeq != null && aSeq != bSeq) {
        return aSeq.compareTo(bSeq);
      }
      if (aSeq != null && bSeq == null) {
        return -1;
      }
      if (aSeq == null && bSeq != null) {
        return 1;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    isBusy = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await action().timeout(_requestTimeout);
    } on TimeoutException {
      errorMessage = '请求超时，请检查网络后重试。';
    } catch (error) {
      errorMessage = _friendlyErrorMessage(error);
      if (errorMessage == '登录状态已失效，请重新登录。') {
        await _resetSessionStateAfterExpiry();
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return '操作失败，请稍后重试。';
    }
    if (raw.contains('TimeoutException') || raw.contains('timed out')) {
      return '请求超时，请检查网络后重试。';
    }
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    if (raw.startsWith('StateError: ')) {
      return raw.substring('StateError: '.length);
    }
    return raw;
  }

  Future<void> _resetSessionStateAfterExpiry() async {
    await _realtimeGateway.disconnect();
    localCredentials = await _gateway.listLocalCredentials();
    session = null;
    profile = null;
    conversations = const <ConversationSummary>[];
    followers = const <RelationshipSummary>[];
    following = const <RelationshipSummary>[];
    groups = const <GroupSummary>[];
    messagesByThread.clear();
    membersByGroup.clear();
    lastFriendsRefreshAt = null;
    lastFriendsRefreshError = null;
    friendsRefreshCount = 0;
    await _notificationFacade.updateBadgeCount(0);
  }
}
