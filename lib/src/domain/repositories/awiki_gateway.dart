import '../entities/bridge_capabilities.dart';
import '../entities/chat_message.dart';
import '../entities/conversation_summary.dart';
import '../entities/group_member_summary.dart';
import '../entities/group_summary.dart';
import '../entities/profile_patch.dart';
import '../entities/realtime_update.dart';
import '../entities/relationship_summary.dart';
import '../entities/user_profile.dart';

abstract class AwikiGateway {
  Future<BridgeCapabilities> loadCapabilities();

  Future<UserProfile> loadMyProfile();

  Future<UserProfile> updateProfile(ProfilePatch patch);

  Future<UserProfile> loadPublicProfile(String didOrHandle);

  Future<List<RelationshipSummary>> listFollowers();

  Future<List<RelationshipSummary>> listFollowing();

  Future<void> follow(String didOrHandle);

  Future<void> unfollow(String didOrHandle);

  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle);

  Future<List<ConversationSummary>> listConversations();

  Future<List<ChatMessage>> fetchDmHistory(String peerDid);

  Future<List<ChatMessage>> fetchGroupHistory(String groupId);

  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
  });

  Future<ChatMessage> retryMessage(ChatMessage message);

  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
  });

  Future<GroupSummary> joinGroup(String groupDid);

  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberDid,
    String role = 'member',
  });

  Future<GroupSummary> getGroup(String groupId);

  Future<List<GroupSummary>> listGroups();

  Future<List<GroupMemberSummary>> listGroupMembers(String groupId);

  Future<RealtimeUpdate?> consumeRealtimeEvent(Map<String, Object?> event);

  Future<void> markRead(String threadId);

  Future<void> deleteLocalThread(String threadId);
}
