import 'dart:async';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/data/compat/compat_awiki_gateway.dart';
import 'package:awiki_me/src/data/compat/compat_realtime_gateway.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'compat gateway maps old gateway calls into application services',
    () async {
      final sessions = _FakeSessions(_appSession());
      final conversations = _FakeConversations();
      final messages = _FakeMessages();
      final gateway = CompatAwikiGateway(
        sessions: sessions,
        profiles: _FakeProfiles(),
        relationships: _FakeRelationships(),
        conversations: conversations,
        messages: messages,
        groups: _FakeGroups(),
      );

      await gateway.listConversations();
      await gateway.sendTextMessage(
        threadId: 'dm:alice:bob',
        peerDid: 'did:bob',
        content: 'hi',
      );
      await gateway.sendTextMessage(
        threadId: 'group:did:group',
        groupId: 'did:group',
        content: 'group hi',
      );
      await gateway.deleteLocalThread('thread-1');

      expect(conversations.ownerDids, ['did:alice']);
      expect(messages.sentThreads[0], isA<AppDirectThreadRef>());
      expect(messages.sentThreads[1], isA<AppGroupThreadRef>());
      expect(conversations.hiddenThreads, ['did:alice/thread-1/true']);
    },
  );

  test(
    'compat gateway consumes typed realtime updates from compat realtime',
    () async {
      final gateway = CompatAwikiGateway(
        sessions: _FakeSessions(_appSession()),
        profiles: _FakeProfiles(),
        relationships: _FakeRelationships(),
        conversations: _FakeConversations(),
        messages: _FakeMessages(),
        groups: _FakeGroups(),
      );
      final update = _update();

      expect(
        await gateway.consumeRealtimeEvent(<String, Object?>{
          compatRealtimeUpdateEventKey: update,
        }),
        same(update),
      );
      expect(await gateway.consumeRealtimeEvent(<String, Object?>{}), isNull);
    },
  );

  test(
    'compat realtime gateway forwards typed updates as legacy map events',
    () async {
      final realtime = _FakeRealtimeService();
      final gateway = CompatRealtimeGateway(realtime: realtime);
      final events = <Map<String, Object?>>[];
      final statuses = <RealtimeConnectionStatus>[];
      final statusSub = gateway.connectionStatusStream.listen(statuses.add);
      addTearDown(statusSub.cancel);

      await gateway.connect(
        session: const SessionIdentity(
          did: 'did:alice',
          credentialName: 'alice',
          displayName: 'Alice',
        ),
        onMessage: (event) async => events.add(event),
      );
      realtime.emitStatus(RealtimeConnectionStatus.connected);
      realtime.emitUpdate(_update());
      await pumpEventQueue();
      await gateway.disconnect();

      expect(
        events.single[compatRealtimeUpdateEventKey],
        isA<RealtimeUpdate>(),
      );
      expect(statuses, contains(RealtimeConnectionStatus.connected));
      expect(gateway.connectionStatus, RealtimeConnectionStatus.disconnected);
    },
  );
}

AppSession _appSession() {
  return const AppSession(
    did: 'did:alice',
    identityId: 'id-alice',
    displayName: 'Alice',
  );
}

RealtimeUpdate _update() {
  final message = ChatMessage(
    localId: 'msg-1',
    threadId: 'dm:alice:bob',
    senderDid: 'did:bob',
    content: 'hi',
    createdAt: DateTime.utc(2026, 5, 23),
    isMine: false,
    sendState: MessageSendState.sent,
  );
  return RealtimeUpdate(message: message, conversation: _conversation());
}

ConversationSummary _conversation() {
  return ConversationSummary(
    threadId: 'dm:alice:bob',
    displayName: 'Bob',
    lastMessagePreview: 'hi',
    lastMessageAt: DateTime.utc(2026, 5, 23),
    unreadCount: 1,
    isGroup: false,
    targetDid: 'did:bob',
  );
}

ChatMessage _message(String content) {
  return ChatMessage(
    localId: 'msg-$content',
    threadId: 'dm:alice:bob',
    senderDid: 'did:alice',
    receiverDid: 'did:bob',
    content: content,
    createdAt: DateTime.utc(2026, 5, 23),
    isMine: true,
    sendState: MessageSendState.sent,
  );
}

class _FakeSessions implements AppSessionService {
  _FakeSessions(this.session);

  final AppSession? session;

  @override
  Future<AppSession> activateIdentity(AppSession identity) async => identity;

  @override
  Future<AppSession?> currentSession() async => session;

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    if (session != null) session!,
  ];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async =>
      session!;

  @override
  Future<AppSession?> refreshSession() async => session;

  @override
  Future<AppSession?> restoreSession() async => session;
}

class _FakeProfiles implements ProfileApplicationService {
  @override
  Future<UserProfile> loadMyProfile() async => _profile('did:alice');

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    return _profile(didOrHandle);
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    return _profile('did:alice');
  }
}

class _FakeRelationships implements RelationshipApplicationService {
  @override
  Future<void> follow(String peer) async {}

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) async {
    return const CoreRelationshipPage(
      items: <RelationshipSummary>[],
      hasMore: false,
    );
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) async {
    return const CoreRelationshipPage(
      items: <RelationshipSummary>[],
      hasMore: false,
    );
  }

  @override
  Future<RelationshipSummary> status(String peer) async {
    return RelationshipSummary(
      did: peer,
      displayName: peer,
      relationship: 'none',
    );
  }

  @override
  Future<void> unfollow(String peer) async {}
}

class _FakeConversations implements ConversationService {
  final List<String> ownerDids = <String>[];
  final List<String> hiddenThreads = <String>[];

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    ownerDids.add(ownerDid);
    return <ConversationSummary>[_conversation()];
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) async {}

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {
    hiddenThreads.add('$ownerDid/$threadId/$hidden');
  }
}

class _FakeMessages implements MessagingService {
  final List<AppThreadRef> sentThreads = <AppThreadRef>[];

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) async =>
      AttachmentDownloadResult(attachmentId: attachmentId ?? 'attachment-1');

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) async => <ChatMessage>[];

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) async {
    return failed;
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) async {
    sentThreads.add(thread);
    return _message(caption ?? attachment.filename);
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    sentThreads.add(thread);
    return _message('');
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    sentThreads.add(thread);
    return _message(content);
  }
}

class _FakeGroups implements GroupApplicationService {
  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberDid,
    String role = 'member',
  }) async => _group();

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
  }) async => _group();

  @override
  Future<GroupSummary> getGroup(String groupDid) async => _group();

  @override
  Future<GroupSummary> joinGroup(String groupDid) async => _group();

  @override
  Future<void> leaveGroup(String groupDid) async {}

  @override
  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  }) async {
    return const <GroupMemberSummary>[];
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) async => const <ChatMessage>[];

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) async =>
      <GroupSummary>[_group()];

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberDid,
  }) async => _group();
}

class _FakeRealtimeService implements RealtimeApplicationService {
  final StreamController<RealtimeConnectionStatus> _statuses =
      StreamController<RealtimeConnectionStatus>.broadcast();
  final StreamController<RealtimeUpdate> _updates =
      StreamController<RealtimeUpdate>.broadcast();
  bool _running = false;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates => _statuses.stream;

  @override
  bool get isRunning => _running;

  @override
  Stream<RealtimeUpdate> get updates => _updates.stream;

  @override
  Future<void> start() async {
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  void emitStatus(RealtimeConnectionStatus status) => _statuses.add(status);

  void emitUpdate(RealtimeUpdate update) => _updates.add(update);
}

UserProfile _profile(String did) {
  return UserProfile(
    did: did,
    nickName: did,
    bio: '',
    tags: const <String>[],
    profileMarkdown: '',
  );
}

GroupSummary _group() {
  return const GroupSummary(
    groupId: 'did:group',
    name: 'Group',
    description: '',
    memberCount: 1,
    lastMessageAt: null,
  );
}
