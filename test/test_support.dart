import 'dart:async';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
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
import 'package:awiki_me/src/domain/repositories/awiki_account_gateway.dart';
import 'package:awiki_me/src/domain/repositories/awiki_gateway.dart';
import 'package:awiki_me/src/domain/services/e2ee_facade.dart';
import 'package:awiki_me/src/domain/services/notification_facade.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/domain/services/update_service.dart';
import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/data/services/locale_preference_service.dart';
import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget buildLocalizedTestApp({
  required Widget home,
  Locale locale = const Locale('zh'),
  FakeAwikiGateway? gateway,
  FakeRealtimeGateway? realtimeGateway,
  FakeNotificationFacade? notificationFacade,
  FakeE2eeFacade? e2eeFacade,
  FakeLocalePreferenceService? localePreferenceService,
  FakeUpdateService? updateService,
  SessionIdentity? session,
  UserProfile? profile,
  AppLocaleMode localeMode = AppLocaleMode.system,
  Future<String?> Function(String url)? homepageMarkdownLoader,
  List<Override> providerOverrides = const <Override>[],
}) {
  final resolvedGateway = gateway ?? FakeAwikiGateway();
  final resolvedRealtime = realtimeGateway ?? FakeRealtimeGateway();
  final resolvedNotification = notificationFacade ?? FakeNotificationFacade();
  final resolvedE2ee = e2eeFacade ?? FakeE2eeFacade();
  final resolvedLocalePreference =
      localePreferenceService ?? FakeLocalePreferenceService();
  final resolvedUpdateService = updateService ?? FakeUpdateService();
  return ProviderScope(
    overrides: <Override>[
      awikiGatewayProvider.overrideWithValue(resolvedGateway),
      awikiAccountGatewayProvider.overrideWithValue(resolvedGateway),
      realtimeGatewayProvider.overrideWithValue(resolvedRealtime),
      notificationFacadeProvider.overrideWithValue(resolvedNotification),
      e2eeFacadeProvider.overrideWithValue(resolvedE2ee),
      localePreferenceServiceProvider.overrideWithValue(
        resolvedLocalePreference,
      ),
      updateServiceProvider.overrideWithValue(resolvedUpdateService),
      ...fakeApplicationServiceOverrides(
        resolvedGateway,
        realtimeGateway: resolvedRealtime,
      ),
      appLocaleModeProvider.overrideWith((ref) => localeMode),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        if (session != null) {
          controller.setSession(session);
        }
        if (resolvedGateway.localCredentials.isNotEmpty) {
          controller.setLocalCredentials(resolvedGateway.localCredentials);
        }
        return controller;
      }),
      profileProvider.overrideWith((ref) {
        return TestProfileController(ref, initialProfile: profile);
      }),
      if (homepageMarkdownLoader != null)
        homepageMarkdownLoaderProvider.overrideWithValue(
          homepageMarkdownLoader,
        ),
      appRuntimeProvider.overrideWith((ref) => AppRuntimeController(ref)),
      ...providerOverrides,
    ],
    child: CupertinoApp(
      locale: locale,
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

List<Override> fakeApplicationServiceOverrides(
  FakeAwikiGateway gateway, {
  FakeRealtimeGateway? realtimeGateway,
}) {
  final resolvedRealtime = realtimeGateway ?? FakeRealtimeGateway();
  return <Override>[
    appSessionServiceProvider.overrideWithValue(FakeAppSessionService(gateway)),
    profileApplicationServiceProvider.overrideWithValue(
      FakeProfileApplicationService(gateway),
    ),
    conversationServiceProvider.overrideWithValue(
      FakeConversationService(gateway),
    ),
    messagingServiceProvider.overrideWithValue(FakeMessagingService(gateway)),
    groupApplicationServiceProvider.overrideWithValue(
      FakeGroupApplicationService(gateway),
    ),
    relationshipApplicationServiceProvider.overrideWithValue(
      FakeRelationshipApplicationService(gateway),
    ),
    onboardingServiceProvider.overrideWithValue(FakeOnboardingService(gateway)),
    onboardingSupportServiceProvider.overrideWithValue(
      FakeOnboardingSupportService(gateway),
    ),
    realtimeApplicationServiceProvider.overrideWithValue(
      FakeRealtimeApplicationService(
        gateway: gateway,
        realtimeGateway: resolvedRealtime,
      ),
    ),
  ];
}

String normalizeTestIdentity(String rawValue) {
  var value = rawValue.trim();
  while (value.startsWith('@')) {
    value = value.substring(1).trimLeft();
  }
  return value;
}

class FakeUpdateService implements UpdateService {
  AppVersion currentVersion = const AppVersion(
    version: '0.1.0',
    buildNumber: 1,
  );
  AppUpdateManifest? latestManifest;
  bool openReleaseNotesCalled = false;
  bool openDownloadPageCalled = false;
  bool installUpdateCalled = false;
  bool openInstallPermissionSettingsCalled = false;
  int checkForUpdatesCalls = 0;
  Object? checkError;
  Object? installError;

  @override
  Future<AppUpdateCheckResult> checkForUpdates({required bool force}) async {
    checkForUpdatesCalls += 1;
    if (checkError != null) {
      throw checkError!;
    }
    return AppUpdateCheckResult(
      currentVersion: currentVersion,
      latestManifest: latestManifest,
    );
  }

  @override
  Future<AppVersion> getCurrentVersion() async => currentVersion;

  @override
  Future<void> installUpdate(AppUpdateManifest manifest) async {
    installUpdateCalled = true;
    if (installError != null) {
      throw installError!;
    }
  }

  @override
  Future<void> openDownloadPage(AppUpdateManifest? manifest) async {
    openDownloadPageCalled = true;
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    openInstallPermissionSettingsCalled = true;
  }

  @override
  Future<void> openReleaseNotes(AppUpdateManifest? manifest) async {
    openReleaseNotesCalled = true;
  }
}

class FakeAwikiGateway implements AwikiGateway, AwikiAccountGateway {
  List<SessionIdentity> localCredentials = const <SessionIdentity>[];
  List<ConversationSummary> conversations = const <ConversationSummary>[];
  Map<String, List<ChatMessage>> dmHistoryByPeerDid =
      <String, List<ChatMessage>>{};
  Map<String, List<ChatMessage>> groupHistoryByGroupId =
      <String, List<ChatMessage>>{};
  List<RelationshipSummary> followers = const <RelationshipSummary>[];
  List<RelationshipSummary> following = const <RelationshipSummary>[];
  List<GroupSummary> groups = const <GroupSummary>[];
  Map<String, List<GroupMemberSummary>> groupMembersByGroupId =
      <String, List<GroupMemberSummary>>{};
  Map<String, UserProfile> publicProfilesByQuery = <String, UserProfile>{};
  Map<String, RelationshipSummary> relationshipsByDidOrHandle =
      <String, RelationshipSummary>{};
  SessionIdentity? importedCredential;
  String? exportedPath;
  UserProfile? myProfile;
  UserProfile? publicProfile;
  UserProfile? updatedProfile;
  SessionIdentity? loginResult;
  bool emailVerificationResult = false;
  String? lastLoginCredentialName;
  ProfilePatch? lastProfilePatch;
  RealtimeUpdate? nextRealtimeUpdate;
  bool failNextSend = false;
  Duration sendDelay = Duration.zero;
  SessionIdentity? refreshedSession;
  HandleRegistrationStatus handleRegistrationStatus =
      HandleRegistrationStatus.notRegistered;
  String? lastFollowedDidOrHandle;
  String? lastRegisteredNickName;
  String? lastRegisteredProfileMarkdown;
  String? lastEmailRegisteredNickName;
  String? lastEmailRegisteredProfileMarkdown;
  String? lastCreatedGroupName;
  String? lastCreatedGroupSlug;
  String? lastCreatedGroupDescription;
  String? lastCreatedGroupGoal;
  String? lastCreatedGroupRules;
  String? lastCreatedGroupPrompt;
  String? lastJoinedGroupDid;
  String? lastAddedGroupId;
  String? lastAddedMemberDid;
  String? lastAddedMemberRole;
  String? lastSentThreadId;
  String? lastSentPeerDid;
  String? lastSentGroupId;
  String? lastSentContent;
  String? nextSentMessageId;
  int listLocalCredentialsCalls = 0;
  int importCalls = 0;
  int exportCalls = 0;
  int loginCalls = 0;
  int refreshSessionCalls = 0;
  int fetchDmHistoryCalls = 0;
  int fetchGroupHistoryCalls = 0;
  int markReadCalls = 0;
  int listConversationsCalls = 0;
  int sendOtpCalls = 0;
  int sendEmailVerificationCalls = 0;
  int checkEmailVerifiedCalls = 0;
  int lookupHandleRegistrationCalls = 0;
  int registerHandleCalls = 0;
  int registerHandleWithEmailCalls = 0;
  int recoverHandleCalls = 0;

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
    fetchDmHistoryCalls += 1;
    return dmHistoryByPeerDid[peerDid] ?? const <ChatMessage>[];
  }

  @override
  Future<List<ChatMessage>> fetchGroupHistory(String groupId) async {
    fetchGroupHistoryCalls += 1;
    return groupHistoryByGroupId[groupId] ?? const <ChatMessage>[];
  }

  @override
  Future<void> follow(String didOrHandle) async {
    lastFollowedDidOrHandle = didOrHandle;
    final profile =
        publicProfilesByQuery[didOrHandle] ??
        publicProfilesByQuery[normalizeTestIdentity(didOrHandle)] ??
        publicProfile;
    final summary = RelationshipSummary(
      did: profile?.did ?? didOrHandle,
      displayName: profile == null
          ? didOrHandle
          : (profile.nickName.isNotEmpty
                ? profile.nickName
                : profile.handle ?? profile.did),
      relationship: 'following',
    );
    following = <RelationshipSummary>[
      ...following.where((item) => item.did != summary.did),
      summary,
    ];
    relationshipsByDidOrHandle[didOrHandle] = summary;
    relationshipsByDidOrHandle[summary.did] = summary;
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
    lastCreatedGroupName = name;
    lastCreatedGroupSlug = slug;
    lastCreatedGroupDescription = description;
    lastCreatedGroupGoal = goal;
    lastCreatedGroupRules = rules;
    lastCreatedGroupPrompt = messagePrompt;
    final group = GroupSummary(
      groupId: 'group-${groups.length + 1}',
      name: name,
      description: description,
      memberCount: 1,
      lastMessageAt: DateTime.now(),
      myRole: 'owner',
    );
    groups = <GroupSummary>[
      ...groups.where((item) => item.groupId != group.groupId),
      group,
    ];
    groupMembersByGroupId[group.groupId] =
        groupMembersByGroupId[group.groupId] ??
        <GroupMemberSummary>[
          GroupMemberSummary(
            userId: loginResult?.did ?? 'did:test:sender',
            did: loginResult?.did ?? 'did:test:sender',
            handle: loginResult?.handle ?? 'tester',
            role: 'owner',
            profileUrl: null,
          ),
        ];
    return group;
  }

  @override
  Future<RealtimeUpdate?> consumeRealtimeEvent(
    Map<String, Object?> event,
  ) async {
    return nextRealtimeUpdate;
  }

  @override
  Future<GroupSummary> getGroup(String groupId) async {
    return groups.firstWhere(
      (item) => item.groupId == groupId,
      orElse: () => GroupSummary(
        groupId: groupId,
        name: groupId,
        description: '',
        memberCount: 0,
        lastMessageAt: null,
      ),
    );
  }

  @override
  Future<RelationshipSummary> getRelationshipStatus(String didOrHandle) async {
    return relationshipsByDidOrHandle[didOrHandle] ??
        relationshipsByDidOrHandle[normalizeTestIdentity(didOrHandle)] ??
        RelationshipSummary(
          did: didOrHandle,
          displayName: didOrHandle,
          relationship: 'none',
        );
  }

  @override
  Future<SessionIdentity?> importCredentialFromZip() async {
    importCalls += 1;
    return importedCredential;
  }

  @override
  Future<GroupSummary> joinGroup(String groupDid) async {
    lastJoinedGroupDid = groupDid;
    final group = GroupSummary(
      groupId: groupDid,
      name: 'Joined $groupDid',
      description: '',
      memberCount: 1,
      lastMessageAt: DateTime.now(),
      myRole: 'member',
    );
    groups = <GroupSummary>[
      ...groups.where((item) => item.groupId != group.groupId),
      group,
    ];
    return group;
  }

  @override
  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberDid,
    String role = 'member',
  }) async {
    lastAddedGroupId = groupId;
    lastAddedMemberDid = memberDid;
    lastAddedMemberRole = role;
    final members = <GroupMemberSummary>[
      ...(groupMembersByGroupId[groupId] ?? const <GroupMemberSummary>[]),
    ];
    if (!members.any((item) => item.did == memberDid)) {
      members.add(
        GroupMemberSummary(
          userId: memberDid,
          did: memberDid,
          handle: memberDid,
          role: role,
          profileUrl: null,
        ),
      );
    }
    groupMembersByGroupId[groupId] = members;
    final current = await getGroup(groupId);
    final updated = GroupSummary(
      groupId: current.groupId,
      name: current.name,
      description: current.description,
      memberCount: members.length,
      lastMessageAt: current.lastMessageAt,
      myRole: current.myRole,
    );
    groups = <GroupSummary>[
      ...groups.where((item) => item.groupId != updated.groupId),
      updated,
    ];
    return updated;
  }

  @override
  Future<bool> checkEmailVerified({required String email}) async {
    checkEmailVerifiedCalls += 1;
    return emailVerificationResult;
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    listConversationsCalls += 1;
    return conversations;
  }

  @override
  Future<List<RelationshipSummary>> listFollowers() async {
    return followers;
  }

  @override
  Future<List<GroupMemberSummary>> listGroupMembers(String groupId) async {
    return groupMembersByGroupId[groupId] ?? const <GroupMemberSummary>[];
  }

  @override
  Future<List<GroupSummary>> listGroups() async {
    return groups;
  }

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async {
    listLocalCredentialsCalls += 1;
    return localCredentials;
  }

  @override
  Future<List<RelationshipSummary>> listFollowing() async {
    return following;
  }

  @override
  Future<UserProfile> loadMyProfile() async {
    if (myProfile != null) {
      return myProfile!;
    }
    if (updatedProfile != null) {
      return updatedProfile!;
    }
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    final normalized = normalizeTestIdentity(didOrHandle);
    if (publicProfilesByQuery.containsKey(didOrHandle)) {
      return publicProfilesByQuery[didOrHandle]!;
    }
    if (publicProfilesByQuery.containsKey(normalized)) {
      return publicProfilesByQuery[normalized]!;
    }
    if (publicProfile != null) {
      return publicProfile!;
    }
    throw UnimplementedError();
  }

  @override
  Future<SessionIdentity> loginWithLocalCredential(
    String credentialName,
  ) async {
    loginCalls += 1;
    lastLoginCredentialName = credentialName;
    if (loginResult != null) {
      return loginResult!;
    }
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {}

  @override
  Future<void> markRead(String threadId) async {
    markReadCalls += 1;
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
    registerHandleCalls += 1;
    lastRegisteredNickName = nickName;
    lastRegisteredProfileMarkdown = profileMarkdown;
    loginResult = SessionIdentity(
      did: 'did:wba:awiki.ai:$handle:e1_registered',
      credentialName: handle,
      displayName: nickName?.isNotEmpty == true ? nickName! : handle,
      handle: handle,
      jwtToken: 'registered-token',
    );
    return loginResult!;
  }

  @override
  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    registerHandleWithEmailCalls += 1;
    lastEmailRegisteredNickName = nickName;
    lastEmailRegisteredProfileMarkdown = profileMarkdown;
    loginResult = SessionIdentity(
      did: 'did:wba:awiki.ai:$handle:e1_email_registered',
      credentialName: handle,
      displayName: nickName?.isNotEmpty == true ? nickName! : handle,
      handle: handle,
      jwtToken: 'email-registered-token',
    );
    return loginResult!;
  }

  @override
  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    recoverHandleCalls += 1;
    loginResult = SessionIdentity(
      did: 'did:wba:awiki.ai:$handle:e1_recovered',
      credentialName: handle,
      displayName: handle,
      handle: handle,
      jwtToken: 'recovered-token',
    );
    return loginResult!;
  }

  @override
  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  }) async {
    lookupHandleRegistrationCalls += 1;
    return handleRegistrationStatus;
  }

  @override
  Future<SessionIdentity?> restoreSession() async {
    return null;
  }

  @override
  Future<SessionIdentity?> currentSession() async {
    return loginResult ??
        (localCredentials.isNotEmpty ? localCredentials.first : null);
  }

  @override
  Future<SessionIdentity?> refreshSession() async {
    refreshSessionCalls += 1;
    if (refreshedSession != null) {
      loginResult = refreshedSession;
      return refreshedSession;
    }
    return currentSession();
  }

  @override
  Future<Object> currentAnpSession({bool requireSigning = false}) {
    throw UnsupportedError(
      'ANP session is not available in IM Core migration test support.',
    );
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
  Future<void> sendEmailVerification({required String email}) async {
    sendEmailVerificationCalls += 1;
  }

  @override
  Future<void> sendOtp({required String phone}) async {
    sendOtpCalls += 1;
  }

  @override
  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
  }) async {
    lastSentThreadId = threadId;
    lastSentPeerDid = peerDid;
    lastSentGroupId = groupId;
    lastSentContent = content;
    if (failNextSend) {
      failNextSend = false;
      throw StateError('send failed');
    }
    if (sendDelay > Duration.zero) {
      await Future<void>.delayed(sendDelay);
    }
    final sentId =
        nextSentMessageId ?? 'sent-${DateTime.now().microsecondsSinceEpoch}';
    nextSentMessageId = null;
    return ChatMessage(
      localId: sentId,
      remoteId: sentId,
      threadId: threadId,
      senderDid: loginResult?.did ?? 'did:test:sender',
      senderName: loginResult?.displayName ?? loginResult?.handle ?? 'tester',
      receiverDid: peerDid,
      groupId: groupId,
      content: content,
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sent,
    );
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

class FakeProfileApplicationService implements ProfileApplicationService {
  const FakeProfileApplicationService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<UserProfile> loadMyProfile() {
    return gateway.loadMyProfile();
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    return gateway.loadPublicProfile(didOrHandle);
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    return gateway.updateProfile(patch);
  }
}

class FakeAppSessionService implements AppSessionService {
  FakeAppSessionService(this.gateway);

  final FakeAwikiGateway gateway;
  AppSession? _current;

  @override
  Future<AppSession> activateIdentity(AppSession identity) async {
    _current = identity;
    return identity;
  }

  @override
  Future<AppSession?> currentSession() async => _current;

  @override
  Future<List<AppSession>> listLocalIdentities() async {
    final identities = await gateway.listLocalCredentials();
    return identities.map(_appSessionFromLegacy).toList();
  }

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) async {
    final session = await gateway.loginWithLocalCredential(identityIdOrAlias);
    _current = _appSessionFromLegacy(session);
    return _current!;
  }

  @override
  Future<void> logout() async {
    _current = null;
    await gateway.logout();
  }

  @override
  Future<AppSession?> refreshSession() async {
    final session = await gateway.refreshSession();
    if (session == null) {
      return null;
    }
    _current = _appSessionFromLegacy(session);
    return _current;
  }

  @override
  Future<AppSession?> restoreSession() async {
    final session = await gateway.restoreSession();
    if (session == null) {
      return null;
    }
    _current = _appSessionFromLegacy(session);
    return _current;
  }
}

class FakeConversationService implements ConversationService {
  const FakeConversationService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) {
    return gateway.listConversations();
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) {
    return gateway.markRead(_threadIdForFakeGateway(thread));
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) {
    return gateway.deleteLocalThread(threadId);
  }
}

class FakeMessagingService implements MessagingService {
  const FakeMessagingService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) {
    return switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => gateway.fetchDmHistory(
        peerDidOrHandle,
      ),
      AppGroupThreadRef(:final groupDid) => gateway.fetchGroupHistory(groupDid),
      AppMessageThreadRef(:final threadId) => _loadThreadHistory(threadId),
    };
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    final groupId = failed.groupId?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      return sendText(
        thread: AppThreadRef.group(groupId),
        content: failed.content,
      );
    }
    final peer = failed.isMine ? failed.receiverDid : failed.senderDid;
    if (peer == null || peer.trim().isEmpty) {
      throw StateError('Cannot retry message without peer or group id.');
    }
    return sendText(thread: AppThreadRef.direct(peer), content: failed.content);
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) {
    return switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => gateway.sendTextMessage(
        threadId: _directThreadId(peerDidOrHandle),
        peerDid: peerDidOrHandle,
        content: content,
      ),
      AppGroupThreadRef(:final groupDid) => gateway.sendTextMessage(
        threadId: _groupThreadId(groupDid),
        groupId: groupDid,
        content: content,
      ),
      AppMessageThreadRef(:final threadId) => throw StateError(
        'Cannot send through test IM Core without peerDid or groupId: $threadId',
      ),
    };
  }

  Future<List<ChatMessage>> _loadThreadHistory(String threadId) {
    if (threadId.startsWith('group:')) {
      return gateway.fetchGroupHistory(threadId.substring('group:'.length));
    }
    if (threadId.startsWith('dm:')) {
      return gateway.fetchDmHistory(threadId.substring('dm:'.length));
    }
    return Future<List<ChatMessage>>.value(const <ChatMessage>[]);
  }
}

class FakeGroupApplicationService implements GroupApplicationService {
  const FakeGroupApplicationService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberDid,
    String role = 'member',
  }) {
    return gateway.addGroupMember(
      groupId: groupDid,
      memberDid: memberDid,
      role: role,
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
  }) {
    return gateway.createGroup(
      name: name,
      slug: slug,
      description: description,
      goal: goal,
      rules: rules,
      messagePrompt: messagePrompt,
    );
  }

  @override
  Future<GroupSummary> getGroup(String groupDid) => gateway.getGroup(groupDid);

  @override
  Future<GroupSummary> joinGroup(String groupDid) {
    return gateway.joinGroup(groupDid);
  }

  @override
  Future<void> leaveGroup(String groupDid) {
    return Future<void>.value();
  }

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) {
    return gateway.listGroups();
  }

  @override
  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  }) {
    return gateway.listGroupMembers(groupDid);
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) {
    return gateway.fetchGroupHistory(groupDid);
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberDid,
  }) {
    throw UnimplementedError();
  }
}

class FakeRelationshipApplicationService
    implements RelationshipApplicationService {
  const FakeRelationshipApplicationService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<void> follow(String peer) => gateway.follow(peer);

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) async {
    return CoreRelationshipPage(
      items: await gateway.listFollowers(),
      hasMore: false,
    );
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) async {
    return CoreRelationshipPage(
      items: await gateway.listFollowing(),
      hasMore: false,
    );
  }

  @override
  Future<RelationshipSummary> status(String peer) {
    return gateway.getRelationshipStatus(peer);
  }

  @override
  Future<void> unfollow(String peer) => gateway.unfollow(peer);
}

class FakeOnboardingService implements OnboardingService {
  const FakeOnboardingService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    return _appSessionFromLegacy(
      await gateway.recoverHandle(phone: phone, otp: otp, handle: handle),
    );
  }

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    return _appSessionFromLegacy(
      await gateway.registerHandleWithEmail(
        email: email,
        handle: handle,
        inviteCode: inviteCode,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      ),
    );
  }

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    return _appSessionFromLegacy(
      await gateway.registerHandle(
        phone: phone,
        otp: otp,
        handle: handle,
        inviteCode: inviteCode,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      ),
    );
  }
}

class FakeOnboardingSupportService implements OnboardingSupportService {
  const FakeOnboardingSupportService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<bool> checkEmailVerified({required String email}) {
    return gateway.checkEmailVerified(email: email);
  }

  @override
  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  }) {
    return gateway.lookupHandleRegistration(handle: handle);
  }

  @override
  Future<void> sendEmailVerification({required String email}) {
    return gateway.sendEmailVerification(email: email);
  }

  @override
  Future<void> sendOtp({required String phone}) {
    return gateway.sendOtp(phone: phone);
  }
}

AppSession _appSessionFromLegacy(SessionIdentity session) {
  return AppSession(
    did: session.did,
    identityId: session.credentialName,
    displayName: session.displayName,
    handle: session.handle,
    localAlias: session.credentialName,
    authenticated: session.jwtToken != null,
  );
}

String _threadIdForFakeGateway(AppThreadRef thread) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => _directThreadId(
      peerDidOrHandle,
    ),
    AppGroupThreadRef(:final groupDid) => _groupThreadId(groupDid),
    AppMessageThreadRef(:final threadId) => threadId,
  };
}

String _directThreadId(String peerDidOrHandle) => 'dm:$peerDidOrHandle';

String _groupThreadId(String groupDid) {
  return groupDid.startsWith('group:') ? groupDid : 'group:$groupDid';
}

class FakeLocalePreferenceService extends LocalePreferenceService {
  FakeLocalePreferenceService({
    AppLocaleMode initialMode = AppLocaleMode.system,
  }) : _storedMode = initialMode,
       super();

  AppLocaleMode _storedMode;
  int saveCalls = 0;

  @override
  Future<AppLocaleMode> loadMode() async {
    return _storedMode;
  }

  @override
  Future<void> saveMode(AppLocaleMode mode) async {
    saveCalls += 1;
    _storedMode = mode;
  }
}

class FakeRealtimeGateway implements RealtimeGateway {
  RealtimeMessageHandler? onMessage;
  bool _isConnected = false;
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.idle;
  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();

  @override
  bool get isConnected => _isConnected;

  @override
  RealtimeConnectionStatus get connectionStatus => _status;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  @override
  Future<void> connect({
    required SessionIdentity session,
    required RealtimeMessageHandler onMessage,
  }) async {
    setStatus(RealtimeConnectionStatus.connecting);
    _isConnected = true;
    this.onMessage = onMessage;
    setStatus(RealtimeConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    onMessage = null;
    setStatus(RealtimeConnectionStatus.idle);
  }

  Future<void> emit(Map<String, Object?> event) async {
    await onMessage?.call(event);
  }

  void setStatus(RealtimeConnectionStatus status) {
    _status = status;
    _isConnected = status == RealtimeConnectionStatus.connected;
    _statusController.add(status);
  }
}

class FakeRealtimeApplicationService implements RealtimeApplicationService {
  FakeRealtimeApplicationService({
    required this.gateway,
    required this.realtimeGateway,
  });

  final FakeAwikiGateway gateway;
  final FakeRealtimeGateway realtimeGateway;
  final StreamController<RealtimeUpdate> _updatesController =
      StreamController<RealtimeUpdate>.broadcast(sync: true);

  @override
  Stream<RealtimeConnectionStatus> get connectionStates async* {
    yield realtimeGateway.connectionStatus;
    yield* realtimeGateway.connectionStatusStream;
  }

  @override
  bool get isRunning => realtimeGateway.isConnected;

  @override
  Stream<RealtimeUpdate> get updates => _updatesController.stream;

  @override
  Future<void> start() {
    return realtimeGateway.connect(
      session: const SessionIdentity(
        did: 'did:test:me',
        credentialName: 'default',
        displayName: 'Me',
      ),
      onMessage: (event) async {
        final update = await gateway.consumeRealtimeEvent(event);
        if (update != null) {
          _updatesController.add(update);
        }
      },
    );
  }

  @override
  Future<void> stop() {
    return realtimeGateway.disconnect();
  }
}

class FakeNotificationFacade implements NotificationFacade {
  String? lastInAppTitle;
  String? lastInAppBody;
  String? lastSystemTitle;
  String? lastSystemBody;
  int lastBadgeCount = 0;

  @override
  Future<void> showSystemNotification({
    required String title,
    required String body,
  }) async {
    lastSystemTitle = title;
    lastSystemBody = body;
  }

  @override
  Future<void> showInAppBanner({
    required String title,
    required String body,
  }) async {
    lastInAppTitle = title;
    lastInAppBody = body;
  }

  @override
  Future<void> updateBadgeCount(int count) async {
    lastBadgeCount = count;
  }
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

class TestProfileController extends ProfileController {
  TestProfileController(super.ref, {UserProfile? initialProfile}) {
    if (initialProfile != null) {
      state = ProfileState(profile: initialProfile);
    }
  }
}
