import 'package:awiki_me/src/domain/entities/bridge_capabilities.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/repositories/awiki_gateway.dart';
import 'package:awiki_me/src/domain/services/e2ee_facade.dart';
import 'package:awiki_me/src/domain/services/notification_facade.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/app_controller.dart';

class FakeAwikiGateway implements AwikiGateway {
  List<SessionIdentity> localCredentials = const <SessionIdentity>[];
  SessionIdentity? importedCredential;
  String? exportedPath;
  UserProfile? updatedProfile;
  ProfilePatch? lastProfilePatch;
  int listLocalCredentialsCalls = 0;
  int importCalls = 0;
  int exportCalls = 0;

  @override
  Future<BridgeCapabilities> loadCapabilities() async {
    return const BridgeCapabilities(
      profileMarkdown: true,
      groupJoinCode: true,
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
  Future<void> deleteLocalCredential(String credentialName) async {}

  @override
  Future<void> deleteLocalThread(String threadId) async {}

  @override
  Future<String?> exportCurrentCredentialAsZip() async {
    exportCalls += 1;
    return exportedPath;
  }

  @override
  Future<List<ChatMessage>> fetchDmHistory(String peerDid) async {
    return const <ChatMessage>[];
  }

  @override
  Future<List<ChatMessage>> fetchGroupHistory(String groupId) async {
    return const <ChatMessage>[];
  }

  @override
  Future<void> follow(String didOrHandle) async {}

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
    throw UnimplementedError();
  }

  @override
  Future<RealtimeUpdate?> consumeRealtimeEvent(
      Map<String, Object?> event) async {
    return null;
  }

  @override
  Future<String?> getGroupJoinCode(String groupId) async {
    return null;
  }

  @override
  Future<GroupSummary> getGroup(String groupId) async {
    throw UnimplementedError();
  }

  @override
  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle) async {
    throw UnimplementedError();
  }

  @override
  Future<SessionIdentity?> importCredentialFromZip() async {
    importCalls += 1;
    return importedCredential;
  }

  @override
  Future<GroupSummary> joinGroup(String joinCode) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> checkEmailVerified({required String email}) async {
    return false;
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    return const <ConversationSummary>[];
  }

  @override
  Future<List<RelationshipSummary>> listFollowers() async {
    return const <RelationshipSummary>[];
  }

  @override
  Future<List<GroupMemberSummary>> listGroupMembers(String groupId) async {
    return const <GroupMemberSummary>[];
  }

  @override
  Future<List<GroupSummary>> listGroups() async {
    return const <GroupSummary>[];
  }

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async {
    listLocalCredentialsCalls += 1;
    return localCredentials;
  }

  @override
  Future<List<RelationshipSummary>> listFollowing() async {
    return const <RelationshipSummary>[];
  }

  @override
  Future<UserProfile> loadMyProfile() async {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    throw UnimplementedError();
  }

  @override
  Future<SessionIdentity> loginWithLocalCredential(
      String credentialName) async {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> markRead(String threadId) async {}

  @override
  Future<String?> refreshGroupJoinCode(String groupId) async {
    return null;
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
    throw UnimplementedError();
  }

  @override
  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SessionIdentity?> restoreSession() async {
    return null;
  }

  @override
  Future<ChatMessage> retryMessage(ChatMessage message) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendEmailVerification({required String email}) async {}

  @override
  Future<void> sendOtp({required String phone}) async {}

  @override
  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> unfollow(String didOrHandle) async {}

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    lastProfilePatch = patch;
    if (updatedProfile != null) {
      return updatedProfile!;
    }
    throw UnimplementedError();
  }
}

class FakeRealtimeGateway implements RealtimeGateway {
  @override
  bool get isConnected => false;

  @override
  Future<void> connect({
    required SessionIdentity session,
    required RealtimeMessageHandler onMessage,
  }) async {}

  @override
  Future<void> disconnect() async {}
}

class FakeNotificationFacade implements NotificationFacade {
  @override
  Future<void> showInAppBanner({
    required String title,
    required String body,
  }) async {}

  @override
  Future<void> updateBadgeCount(int count) async {}
}

class FakeE2eeFacade implements E2eeFacade {
  @override
  Future<ChatMessage> decryptIncomingMessage(ChatMessage message) async {
    return message;
  }

  @override
  Future<void> ensureSession(String peerDid) async {}

  @override
  Future<EncryptedPayload> encryptOutgoing({
    required String peerDid,
    required String originalType,
    required String plaintext,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, Object?>> exportSessionState() async {
    return const <String, Object?>{};
  }

  @override
  Future<void> importSessionState(Map<String, Object?> state) async {}

  @override
  Future<void> initialize(SessionIdentity identity) async {}

  @override
  Future<bool> isSupported() async {
    return false;
  }

  @override
  Future<E2eeProcessResult> processIncomingProtocolMessage(
    ChatMessage message,
  ) async {
    return const E2eeProcessResult();
  }
}

class RecordingAppController extends AppController {
  RecordingAppController({
    required super.gateway,
    required super.realtimeGateway,
    required super.notificationFacade,
    required super.e2eeFacade,
  });

  int exportCalls = 0;
  int importCalls = 0;
  int updateProfileCalls = 0;
  ProfilePatch? lastProfilePatch;

  @override
  Future<void> exportCurrentCredential() async {
    exportCalls += 1;
  }

  @override
  Future<void> importCredentialArchive() async {
    importCalls += 1;
  }

  @override
  Future<void> updateMyProfile(ProfilePatch patch) async {
    updateProfileCalls += 1;
    lastProfilePatch = patch;
  }
}
