import '../../application/app_session_service.dart';
import '../../application/conversation_service.dart';
import '../../application/group_application_service.dart';
import '../../application/messaging_service.dart';
import '../../application/models/app_thread_ref.dart';
import '../../application/profile_application_service.dart';
import '../../application/relationship_application_service.dart';
import '../../domain/entities/bridge_capabilities.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/realtime_update.dart';
import '../../domain/entities/relationship_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/awiki_gateway.dart';

const String compatRealtimeUpdateEventKey = '_awikiImCoreRealtimeUpdate';

class CompatAwikiGateway implements AwikiGateway {
  CompatAwikiGateway({
    required AppSessionService sessions,
    required ProfileApplicationService profiles,
    required RelationshipApplicationService relationships,
    required ConversationService conversations,
    required MessagingService messages,
    required GroupApplicationService groups,
  }) : _sessions = sessions,
       _profiles = profiles,
       _relationships = relationships,
       _conversations = conversations,
       _messages = messages,
       _groups = groups;

  final AppSessionService _sessions;
  final ProfileApplicationService _profiles;
  final RelationshipApplicationService _relationships;
  final ConversationService _conversations;
  final MessagingService _messages;
  final GroupApplicationService _groups;

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
  Future<UserProfile> loadMyProfile() => _profiles.loadMyProfile();

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    return _profiles.updateProfile(patch);
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    return _profiles.loadPublicProfile(didOrHandle);
  }

  @override
  Future<List<RelationshipSummary>> listFollowers() async {
    return (await _relationships.listFollowers()).items;
  }

  @override
  Future<List<RelationshipSummary>> listFollowing() async {
    return (await _relationships.listFollowing()).items;
  }

  @override
  Future<void> follow(String didOrHandle) => _relationships.follow(didOrHandle);

  @override
  Future<void> unfollow(String didOrHandle) {
    return _relationships.unfollow(didOrHandle);
  }

  @override
  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle) {
    return _relationships.status(didOrHandle);
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    final session = await _requireSession();
    return _conversations.listConversations(ownerDid: session.did);
  }

  @override
  Future<List<ChatMessage>> fetchDmHistory(String peerDid) {
    return _messages.loadHistory(AppThreadRef.direct(peerDid));
  }

  @override
  Future<List<ChatMessage>> fetchGroupHistory(String groupId) {
    return _messages.loadHistory(AppThreadRef.group(groupId));
  }

  @override
  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
  }) {
    return _messages.sendText(
      thread: _sendThreadRef(
        threadId: threadId,
        peerDid: peerDid,
        groupId: groupId,
      ),
      content: content,
    );
  }

  @override
  Future<ChatMessage> retryMessage(ChatMessage message) {
    return _messages.retryByResendOriginalContent(message);
  }

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
  }) {
    return _groups.createGroup(
      name: name,
      slug: slug,
      description: description,
      goal: goal,
      rules: rules,
      messagePrompt: messagePrompt,
    );
  }

  @override
  Future<GroupSummary> joinGroup(String groupDid) =>
      _groups.joinGroup(groupDid);

  @override
  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberDid,
    String role = 'member',
  }) {
    return _groups.addMember(
      groupDid: groupId,
      memberDid: memberDid,
      role: role,
    );
  }

  @override
  Future<GroupSummary> getGroup(String groupId) => _groups.getGroup(groupId);

  @override
  Future<List<GroupSummary>> listGroups() => _groups.listGroups();

  @override
  Future<List<GroupMemberSummary>> listGroupMembers(String groupId) {
    return _groups.listMembers(groupId);
  }

  @override
  Future<RealtimeUpdate?> consumeRealtimeEvent(
    Map<String, Object?> event,
  ) async {
    final update = event[compatRealtimeUpdateEventKey];
    return update is RealtimeUpdate ? update : null;
  }

  @override
  Future<void> markRead(String threadId) {
    return _conversations.markThreadRead(AppThreadRef.thread(threadId));
  }

  @override
  Future<void> deleteLocalThread(String threadId) async {
    final session = await _requireSession();
    await _conversations.setThreadHidden(
      ownerDid: session.did,
      threadId: threadId,
      hidden: true,
    );
  }

  Future<({String did})> _requireSession() async {
    final session = await _sessions.currentSession();
    if (session == null) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    return (did: session.did);
  }
}

AppThreadRef _sendThreadRef({
  required String threadId,
  String? peerDid,
  String? groupId,
}) {
  final group = groupId?.trim();
  if (group != null && group.isNotEmpty) {
    return AppThreadRef.group(group);
  }
  final peer = peerDid?.trim();
  if (peer != null && peer.isNotEmpty) {
    return AppThreadRef.direct(peer);
  }
  if (threadId.startsWith('group:')) {
    return AppThreadRef.group(threadId.substring('group:'.length));
  }
  throw StateError('Cannot send through IM Core without peerDid or groupId.');
}
