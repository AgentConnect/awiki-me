import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/attachment_cache_service.dart';
import 'package:awiki_me/src/application/attachment_picker_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/peer_identity_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/product_local_store.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/domain/entities/bridge_capabilities.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_invocation_policy.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/message_agent_binding.dart';
import 'package:awiki_me/src/domain/entities/agent/install_command.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_agent_identity.dart';
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
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const Map<String, Object?> genericCliCapabilityDiagnostics = <String, Object?>{
  'config_summary': <String, Object?>{
    'generic_cli': <String, Object?>{
      'capability_schema_version': 1,
      'supported_drivers': <String>['codex', 'claude-code', 'command'],
      'supported_workspace_modes': <String>[
        'route-root',
        'shared-root',
        'worktree-per-task',
      ],
      'supported_sandbox_modes': <String>[
        'read-only',
        'workspace-write',
        'danger-full-access',
      ],
      'supported_runtime_create_args': <String>[
        'runtime',
        'driver_id',
        'workspace_mode',
        'workspace_strategy',
        'default_sandbox',
        'default_model',
        'driver_config',
        'recipient_policy',
        'client_request_id',
      ],
      'route_session_supported': true,
      'native_resume_supported': true,
      'profile_concurrency_cap_supported': false,
      'max_parallel_runs_per_profile': 1,
      'runtime_target_required': true,
    },
  },
};

const AgentLatestStatus readyDaemonStatusWithGenericCliCapability =
    AgentLatestStatus(
      status: 'ready',
      platform: 'darwin-arm64',
      diagnosticsSummary: genericCliCapabilityDiagnostics,
    );

Map<String, Object?> genericCliRuntimeCardDiagnostics({
  String lifecycleState = 'needs_setup',
  bool supported = true,
  int statusSchemaVersion = 1,
  String runtimeFamily = 'generic-cli',
  String driverId = 'codex',
  bool setupReady = false,
  String setupState = 'binary_missing',
  String queueState = 'idle',
  String activeRunState = 'idle',
  String routeSessionState = 'none',
  int queuedCount = 0,
  int runningCount = 0,
  int deadLetterCount = 0,
  int failedCount = 0,
  int? oldestQueuedAgeMs,
  String nextAction = 'setup_required',
  bool containsUserContent = false,
  bool containsProviderAuthMaterial = false,
  String lastMessageIdWatermarkPolicy = 'final_only',
}) {
  return <String, Object?>{
    'config_summary': <String, Object?>{
      'runtime_card': <String, Object?>{
        'supported': supported,
        'status_schema_version': statusSchemaVersion,
        'runtime_family': runtimeFamily,
        'driver_id': driverId,
        'lifecycle_state': lifecycleState,
        'setup_ready': setupReady,
        'setup_state': setupState,
        'queue_state': queueState,
        'active_run_state': activeRunState,
        'route_session_state': routeSessionState,
        'queued_count': queuedCount,
        'running_count': runningCount,
        'dead_letter_count': deadLetterCount,
        'failed_count': failedCount,
        'oldest_queued_age_ms': oldestQueuedAgeMs,
        'next_action': nextAction,
        'contains_user_content': containsUserContent,
        'contains_provider_auth_material': containsProviderAuthMaterial,
        'last_message_id_watermark_policy': lastMessageIdWatermarkPolicy,
      },
    },
  };
}

Widget buildLocalizedTestApp({
  required Widget home,
  Locale locale = const Locale('zh'),
  FakeAwikiGateway? gateway,
  FakeRealtimeGateway? realtimeGateway,
  FakeNotificationFacade? notificationFacade,
  FakeE2eeFacade? e2eeFacade,
  FakeLocalePreferenceService? localePreferenceService,
  FakeUpdateService? updateService,
  AttachmentCacheService? attachmentCacheService,
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
      profileHomepageResolverProvider.overrideWithValue(
        ProfileHomepageResolver(
          environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
        ),
      ),
      attachmentPickerServiceProvider.overrideWithValue(
        FakeAttachmentPickerService(),
      ),
      ...fakeApplicationServiceOverrides(
        resolvedGateway,
        realtimeGateway: resolvedRealtime,
        attachmentCacheService: attachmentCacheService,
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
  AttachmentCacheService? attachmentCacheService,
}) {
  final resolvedRealtime = realtimeGateway ?? FakeRealtimeGateway();
  return <Override>[
    appSessionServiceProvider.overrideWithValue(FakeAppSessionService(gateway)),
    identityCorePortProvider.overrideWithValue(FakeIdentityCorePort()),
    profileApplicationServiceProvider.overrideWithValue(
      FakeProfileApplicationService(gateway),
    ),
    peerIdentityServiceProvider.overrideWithValue(FakePeerIdentityService()),
    conversationServiceProvider.overrideWithValue(
      FakeConversationService(gateway),
    ),
    messagingServiceProvider.overrideWithValue(FakeMessagingService(gateway)),
    attachmentCacheServiceProvider.overrideWithValue(
      attachmentCacheService ?? FakeAttachmentCacheService(),
    ),
    productLocalStoreProvider.overrideWithValue(FakeProductLocalStore()),
    agentInventoryPortProvider.overrideWithValue(FakeAgentInventoryPort()),
    agentControlServiceProvider.overrideWithValue(FakeAgentControlService()),
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

class FakeAttachmentPickerService implements AttachmentPickerService {
  AttachmentDraft? nextPick;
  String? nextSavedPath = '/tmp/attachment';
  int pickCalls = 0;
  int saveCalls = 0;
  String? lastSavedFilename;
  String? lastSavedMimeType;
  Uint8List? lastSavedBytes;

  @override
  Future<AttachmentDraft?> pickAttachment() async {
    pickCalls += 1;
    return nextPick;
  }

  @override
  Future<String?> saveAttachment({
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    saveCalls += 1;
    lastSavedFilename = filename;
    lastSavedMimeType = mimeType;
    lastSavedBytes = bytes;
    return nextSavedPath;
  }
}

class FakeAttachmentCacheService implements AttachmentCacheService {
  final Map<String, String> pathsByKey = <String, String>{};
  final Map<String, Uint8List> bytesByKey = <String, Uint8List>{};
  int cacheLocalSourceCalls = 0;
  int cacheDownloadedBytesCalls = 0;
  int lookupCalls = 0;
  String? lastMessageId;
  String? lastAttachmentId;
  String? lastFilename;
  String? lastMimeType;
  String? lastSourcePath;

  @override
  Future<String?> cacheLocalSource({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required String sourcePath,
  }) async {
    cacheLocalSourceCalls += 1;
    lastMessageId = messageId;
    lastAttachmentId = attachmentId;
    lastFilename = filename;
    lastMimeType = mimeType;
    lastSourcePath = sourcePath;
    final path = '/tmp/awiki-test-cache/$messageId/$attachmentId/$filename';
    pathsByKey[_key(messageId, attachmentId)] = path;
    return path;
  }

  @override
  Future<String> cacheDownloadedBytes({
    required String messageId,
    required String attachmentId,
    required String filename,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    cacheDownloadedBytesCalls += 1;
    lastMessageId = messageId;
    lastAttachmentId = attachmentId;
    lastFilename = filename;
    lastMimeType = mimeType;
    bytesByKey[_key(messageId, attachmentId)] = bytes;
    final path = '/tmp/awiki-test-cache/$messageId/$attachmentId/$filename';
    pathsByKey[_key(messageId, attachmentId)] = path;
    return path;
  }

  @override
  Future<String?> lookup({
    required String messageId,
    required String attachmentId,
  }) async {
    lookupCalls += 1;
    lastMessageId = messageId;
    lastAttachmentId = attachmentId;
    return pathsByKey[_key(messageId, attachmentId)];
  }

  String _key(String messageId, String attachmentId) =>
      '$messageId::$attachmentId';
}

class FakeAwikiGateway implements AwikiGateway, AwikiAccountGateway {
  List<SessionIdentity> localCredentials = const <SessionIdentity>[];
  List<ConversationSummary> conversations = const <ConversationSummary>[];
  Map<String, List<ChatMessage>> dmHistoryByPeerDid =
      <String, List<ChatMessage>>{};
  Map<String, List<ChatMessage>> localDmHistoryByPeerDid =
      <String, List<ChatMessage>>{};
  Map<String, List<List<ChatMessage>>> dmHistoryBatchesByPeerDid =
      <String, List<List<ChatMessage>>>{};
  Map<String, List<ChatMessage>> groupHistoryByGroupId =
      <String, List<ChatMessage>>{};
  Map<String, List<ChatMessage>> localGroupHistoryByGroupId =
      <String, List<ChatMessage>>{};
  Completer<void>? fetchDmHistoryCompleter;
  Completer<void>? fetchLocalDmHistoryCompleter;
  List<RelationshipSummary> followers = const <RelationshipSummary>[];
  List<RelationshipSummary> following = const <RelationshipSummary>[];
  List<GroupSummary> groups = const <GroupSummary>[];
  Object? getGroupError;
  Object? listGroupMembersError;
  Completer<void>? listGroupMembersCompleter;
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
  bool failNextFollow = false;
  bool failNextListConversations = false;
  bool failNextFetchDmHistory = false;
  bool failNextFetchLocalDmHistory = false;
  bool failNextSendOtp = false;
  bool failListFollowing = false;
  bool failListFollowers = false;
  bool failNextJoinGroup = false;
  bool failNextAddGroupMember = false;
  bool includeLocalPathInSentAttachment = true;
  Duration sendDelay = Duration.zero;
  SessionIdentity? refreshedSession;
  HandleRegistrationStatus handleRegistrationStatus =
      HandleRegistrationStatus.notRegistered;
  String? lastFollowedDidOrHandle;
  String? lastUnfollowedDidOrHandle;
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
  String? lastAddedMemberRef;
  String? lastAddedMemberRole;
  String? lastRemovedGroupId;
  String? lastRemovedMemberRef;
  String? lastSentThreadId;
  String? lastSentPeerDid;
  String? lastSentGroupId;
  String? lastSentContent;
  Map<String, Object?>? lastSentPayload;
  String? lastSentPayloadPeerDid;
  String? lastSentPayloadIdempotencyKey;
  AttachmentDraft? lastSentAttachment;
  String? lastSentAttachmentCaption;
  String? lastSentAttachmentIdempotencyKey;
  String? nextSentMessageId;
  List<String> nextSentMessageIds = <String>[];
  int listLocalCredentialsCalls = 0;
  int importCalls = 0;
  int exportCalls = 0;
  int loginCalls = 0;
  int refreshSessionCalls = 0;
  int fetchDmHistoryCalls = 0;
  String? lastFetchedDmPeerDid;
  int fetchLocalDmHistoryCalls = 0;
  String? lastFetchedLocalDmPeerDid;
  int fetchGroupHistoryCalls = 0;
  int fetchLocalGroupHistoryCalls = 0;
  int markReadCalls = 0;
  String? lastMarkReadThreadId;
  int listConversationsCalls = 0;
  int sendOtpCalls = 0;
  int sendEmailVerificationCalls = 0;
  int checkEmailVerifiedCalls = 0;
  int lookupHandleRegistrationCalls = 0;
  int validateHandleCalls = 0;
  int registerHandleCalls = 0;
  int registerHandleWithEmailCalls = 0;
  int recoverHandleCalls = 0;
  int logoutCalls = 0;
  int deleteLocalThreadCalls = 0;
  String? lastDeletedLocalThreadId;
  int deleteLocalCredentialCalls = 0;
  Completer<void>? logoutCompleter;
  Completer<void>? deleteLocalCredentialCompleter;

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
  Future<void> deleteLocalCredential(String credentialName) async {
    deleteLocalCredentialCalls += 1;
    final completer = deleteLocalCredentialCompleter;
    if (completer != null) {
      await completer.future;
    }
    localCredentials = localCredentials
        .where((credential) => credential.credentialName != credentialName)
        .toList();
    if (loginResult?.credentialName == credentialName) {
      loginResult = null;
    }
  }

  @override
  Future<void> deleteLocalThread(String threadId) async {
    deleteLocalThreadCalls += 1;
    lastDeletedLocalThreadId = threadId;
  }

  @override
  Future<String?> exportCurrentCredentialAsZip() async {
    exportCalls += 1;
    return exportedPath;
  }

  @override
  Future<List<ChatMessage>> fetchDmHistory(String peerDid) async {
    fetchDmHistoryCalls += 1;
    lastFetchedDmPeerDid = peerDid;
    if (failNextFetchDmHistory) {
      failNextFetchDmHistory = false;
      throw StateError('fetch history failed');
    }
    final completer = fetchDmHistoryCompleter;
    if (completer != null) {
      await completer.future;
      fetchDmHistoryCompleter = null;
    }
    final batches = dmHistoryBatchesByPeerDid[peerDid];
    if (batches != null && batches.isNotEmpty) {
      return batches.removeAt(0);
    }
    return dmHistoryByPeerDid[peerDid] ?? const <ChatMessage>[];
  }

  @override
  Future<List<ChatMessage>> fetchGroupHistory(String groupId) async {
    fetchGroupHistoryCalls += 1;
    return groupHistoryByGroupId[groupId] ?? const <ChatMessage>[];
  }

  Future<List<ChatMessage>> fetchLocalDmHistory(String peerDid) async {
    fetchLocalDmHistoryCalls += 1;
    lastFetchedLocalDmPeerDid = peerDid;
    if (failNextFetchLocalDmHistory) {
      failNextFetchLocalDmHistory = false;
      throw StateError('fetch local history failed');
    }
    final completer = fetchLocalDmHistoryCompleter;
    if (completer != null) {
      await completer.future;
      fetchLocalDmHistoryCompleter = null;
    }
    return localDmHistoryByPeerDid[peerDid] ?? const <ChatMessage>[];
  }

  Future<List<ChatMessage>> fetchLocalGroupHistory(String groupId) async {
    fetchLocalGroupHistoryCalls += 1;
    return localGroupHistoryByGroupId[groupId] ?? const <ChatMessage>[];
  }

  @override
  Future<void> follow(String didOrHandle) async {
    if (failNextFollow) {
      failNextFollow = false;
      throw StateError('follow failed');
    }
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
      membershipStatus: 'active',
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
    if (getGroupError != null) {
      throw getGroupError!;
    }
    return groups.firstWhere(
      (item) => item.groupId == groupId,
      orElse: () => GroupSummary(
        groupId: groupId,
        name: groupId,
        description: '',
        memberCount: 0,
        lastMessageAt: null,
        membershipStatus: null,
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
    if (failNextJoinGroup) {
      failNextJoinGroup = false;
      throw StateError('join group failed');
    }
    lastJoinedGroupDid = groupDid;
    final group = GroupSummary(
      groupId: groupDid,
      name: 'Joined $groupDid',
      description: '',
      memberCount: 1,
      lastMessageAt: DateTime.now(),
      myRole: 'member',
      membershipStatus: 'active',
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
    required String memberRef,
    String role = 'member',
  }) async {
    if (failNextAddGroupMember) {
      failNextAddGroupMember = false;
      throw StateError('add member failed');
    }
    lastAddedGroupId = groupId;
    lastAddedMemberRef = memberRef;
    lastAddedMemberRole = role;
    final members = <GroupMemberSummary>[
      ...(groupMembersByGroupId[groupId] ?? const <GroupMemberSummary>[]),
    ];
    if (!members.any((item) => item.did == memberRef)) {
      members.add(
        GroupMemberSummary(
          userId: memberRef,
          did: memberRef,
          handle: memberRef,
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
      membershipStatus: current.membershipStatus,
    );
    groups = <GroupSummary>[
      ...groups.where((item) => item.groupId != updated.groupId),
      updated,
    ];
    return updated;
  }

  @override
  Future<GroupSummary> removeGroupMember({
    required String groupId,
    required String memberRef,
  }) async {
    lastRemovedGroupId = groupId;
    lastRemovedMemberRef = memberRef;
    final members = <GroupMemberSummary>[
      for (final item
          in groupMembersByGroupId[groupId] ?? const <GroupMemberSummary>[])
        if (item.did != memberRef && item.handle != memberRef) item,
    ];
    groupMembersByGroupId[groupId] = members;
    final current = await getGroup(groupId);
    final updated = GroupSummary(
      groupId: current.groupId,
      name: current.name,
      description: current.description,
      memberCount: members.length,
      lastMessageAt: current.lastMessageAt,
      myRole: current.myRole,
      membershipStatus: current.membershipStatus,
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
    if (failNextListConversations) {
      failNextListConversations = false;
      throw StateError('conversation refresh failed');
    }
    return conversations;
  }

  @override
  Future<List<RelationshipSummary>> listFollowers() async {
    if (failListFollowers) {
      throw StateError('followers unavailable');
    }
    return followers;
  }

  @override
  Future<List<GroupMemberSummary>> listGroupMembers(String groupId) async {
    if (listGroupMembersError != null) {
      throw listGroupMembersError!;
    }
    final completer = listGroupMembersCompleter;
    if (completer != null) {
      await completer.future;
      listGroupMembersCompleter = null;
    }
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
    if (failListFollowing) {
      throw StateError('following unavailable');
    }
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
  Future<void> logout() async {
    logoutCalls += 1;
    final completer = logoutCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  Future<void> markRead(String threadId) async {
    markReadCalls += 1;
    lastMarkReadThreadId = threadId;
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
      did: 'did:wba:awiki.info:$handle:e1_registered',
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
      did: 'did:wba:awiki.info:$handle:e1_email_registered',
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
      did: 'did:wba:awiki.info:$handle:e1_recovered',
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

  Future<HandleAvailability> validateHandle({
    required String handle,
    String? domain,
  }) async {
    validateHandleCalls += 1;
    final normalizedHandle = handle.trim().toLowerCase();
    final normalizedDomain = domain?.trim().toLowerCase();
    final registered =
        handleRegistrationStatus == HandleRegistrationStatus.registered;
    return HandleAvailability(
      handle: normalizedHandle,
      domain: normalizedDomain,
      fullHandle: normalizedDomain == null
          ? null
          : '$normalizedHandle.$normalizedDomain',
      available: !registered,
      reason: registered ? 'unavailable' : null,
      message: registered ? "Handle '$normalizedHandle' 已被占用" : null,
    );
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
    if (failNextSendOtp) {
      failNextSendOtp = false;
      throw StateError('otp gateway unavailable');
    }
  }

  @override
  Future<ChatMessage> sendTextMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required String content,
    String originalType = 'text',
    String? payloadJson,
    List<ChatMessageMention> mentions = const <ChatMessageMention>[],
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
    final sentId = nextSentMessageIds.isNotEmpty
        ? nextSentMessageIds.removeAt(0)
        : (nextSentMessageId ??
              'sent-${DateTime.now().microsecondsSinceEpoch}');
    if (nextSentMessageIds.isEmpty) {
      nextSentMessageId = null;
    }
    return ChatMessage(
      localId: sentId,
      remoteId: sentId,
      threadId: threadId,
      senderDid: loginResult?.did ?? 'did:test:sender',
      senderName: loginResult?.displayName ?? loginResult?.handle ?? 'tester',
      receiverDid: peerDid,
      groupId: groupId,
      content: content,
      originalType: originalType,
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sent,
      payloadJson: payloadJson,
      mentions: mentions,
    );
  }

  Future<ChatMessage> sendAttachmentMessage({
    required String threadId,
    String? peerDid,
    String? groupId,
    required AttachmentDraft attachment,
    String? caption,
  }) async {
    lastSentThreadId = threadId;
    lastSentPeerDid = peerDid;
    lastSentGroupId = groupId;
    lastSentAttachment = attachment;
    lastSentAttachmentCaption = caption;
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
      content: caption ?? '',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sent,
      attachment: ChatAttachment(
        attachmentId: sentId,
        filename: attachment.filename,
        mimeType: attachment.mimeType,
        sizeBytes: attachment.sizeBytes,
        caption: caption,
        localPath: includeLocalPathInSentAttachment
            ? attachment.localPath
            : null,
      ),
    );
  }

  @override
  Future<void> unfollow(String didOrHandle) async {
    lastUnfollowedDidOrHandle = didOrHandle;
    final normalized = normalizeTestIdentity(didOrHandle);
    following = following
        .where((item) => item.did != didOrHandle && item.did != normalized)
        .toList();
    relationshipsByDidOrHandle[didOrHandle] = RelationshipSummary(
      did: didOrHandle,
      displayName: didOrHandle,
      relationship: 'none',
    );
    relationshipsByDidOrHandle[normalized] = RelationshipSummary(
      did: normalized,
      displayName: normalized,
      relationship: 'none',
    );
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    lastProfilePatch = patch;
    if (updatedProfile != null) {
      return updatedProfile!;
    }
    throw UnimplementedError();
  }
}

class FakePeerIdentityService implements PeerIdentityService {
  FakePeerIdentityService({
    this.identities = const <String, PeerAgentIdentity>{},
  });

  final Map<String, PeerAgentIdentity> identities;

  @override
  Future<PeerAgentIdentity> resolveAgentIdentity(String didOrHandle) async {
    final normalized = normalizeTestIdentity(didOrHandle);
    return identities[didOrHandle] ??
        identities[normalized] ??
        const PeerAgentIdentity.human();
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
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async {
    final deleted = _current;
    await gateway.deleteLocalCredential(identityIdOrAlias);
    if (deleted != null) {
      _current = null;
      return deleted;
    }
    final fallback = SessionIdentity(
      did: 'did:test:$identityIdOrAlias',
      credentialName: identityIdOrAlias,
      displayName: identityIdOrAlias,
      handle: identityIdOrAlias,
      jwtToken: null,
    );
    return _appSessionFromLegacy(fallback);
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
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) {
    return gateway.listConversations();
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    return conversations;
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) {
    return gateway.listConversations();
  }

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
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

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) {
    return gateway.deleteLocalThread(conversation.visibilityKey);
  }

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {
    // Test gateway-backed service has no persistent overlay store.
  }
}

class FakeMessagingService
    implements MessagingService, LocalHistoryMessagingService {
  const FakeMessagingService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) async {
    return AttachmentDownloadResult(
      attachmentId: attachmentId ?? 'attachment-1',
      filename: 'download.txt',
      mimeType: 'text/plain',
      sizeBytes: 5,
      bytes: Uint8List.fromList(<int>[104, 101, 108, 108, 111]),
    );
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) {
    final history = switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => gateway.fetchDmHistory(
        peerDidOrHandle,
      ),
      AppGroupThreadRef(:final groupDid) => gateway.fetchGroupHistory(groupDid),
      AppMessageThreadRef(:final threadId) => _loadThreadHistory(threadId),
    };
    return history.then(
      (messages) => messages
          .where(
            (message) => includeControlPayloads || message.hasRenderableContent,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) {
    final history = switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => gateway.fetchLocalDmHistory(
        peerDidOrHandle,
      ),
      AppGroupThreadRef(:final groupDid) => gateway.fetchLocalGroupHistory(
        groupDid,
      ),
      AppMessageThreadRef(:final threadId) => _loadLocalThreadHistory(threadId),
    };
    return history.then(
      (messages) => messages
          .where(
            (message) => includeControlPayloads || message.hasRenderableContent,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    final mentionPayload = ChatMentionPayload.tryParsePayloadJson(
      failed.payloadJson,
    );
    if (mentionPayload != null && mentionPayload.hasValidMentions) {
      return sendPayload(
        thread: failed.groupId?.trim().isNotEmpty == true
            ? AppThreadRef.group(failed.groupId!)
            : AppThreadRef.direct(failed.receiverDid ?? failed.senderDid),
        payload: ChatMentionPayload.toP9Json(
          text: mentionPayload.text,
          draftMentions: failed.mentions.map(
            (mention) => ChatMentionDraft(
              localId: mention.id,
              surface: mention.surface,
              start: mention.start,
              end: mention.end,
              target: mention.target,
              role: mention.role,
            ),
          ),
        ),
      );
    }
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
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) {
    gateway.lastSentAttachmentIdempotencyKey = idempotencyKey;
    return switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) =>
        gateway.sendAttachmentMessage(
          threadId: _directThreadId(peerDidOrHandle),
          peerDid: peerDidOrHandle,
          attachment: attachment,
          caption: caption,
        ),
      AppGroupThreadRef(:final groupDid) => gateway.sendAttachmentMessage(
        threadId: _groupThreadId(groupDid),
        groupId: groupDid,
        attachment: attachment,
        caption: caption,
      ),
      AppMessageThreadRef(:final threadId) => throw StateError(
        'Cannot send through test IM Core without peerDid or groupId: $threadId',
      ),
    };
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) {
    gateway.lastSentPayload = payload;
    gateway.lastSentPayloadIdempotencyKey = idempotencyKey;
    if (thread case AppDirectThreadRef(:final peerDidOrHandle)) {
      gateway.lastSentPayloadPeerDid = peerDidOrHandle;
    }
    final payloadJson = jsonEncode(payload);
    final mentionPayload = ChatMentionPayload.tryParsePayloadJson(payloadJson);
    final content = mentionPayload?.text ?? '';
    return switch (thread) {
      AppDirectThreadRef(:final peerDidOrHandle) => gateway.sendTextMessage(
        threadId: _directThreadId(peerDidOrHandle),
        peerDid: peerDidOrHandle,
        content: content,
        payloadJson: payloadJson,
        mentions: mentionPayload?.mentions ?? const <ChatMessageMention>[],
        originalType: 'application/json',
      ),
      AppGroupThreadRef(:final groupDid) => gateway.sendTextMessage(
        threadId: _groupThreadId(groupDid),
        groupId: groupDid,
        content: content,
        payloadJson: payloadJson,
        mentions: mentionPayload?.mentions ?? const <ChatMessageMention>[],
        originalType: 'application/json',
      ),
      AppMessageThreadRef(:final threadId) => throw StateError(
        'Cannot send through test IM Core without peerDid or groupId: $threadId',
      ),
    };
  }

  @override
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) {
    return sendPayload(
      thread: thread,
      payload: ChatMentionPayload.toP9Json(text: text, draftMentions: mentions),
      secure: false,
      idempotencyKey: idempotencyKey,
    );
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

  Future<List<ChatMessage>> _loadLocalThreadHistory(String threadId) {
    if (threadId.startsWith('group:')) {
      return gateway.fetchLocalGroupHistory(
        threadId.substring('group:'.length),
      );
    }
    if (threadId.startsWith('dm:')) {
      return gateway.fetchLocalDmHistory(threadId.substring('dm:'.length));
    }
    return Future<List<ChatMessage>>.value(const <ChatMessage>[]);
  }
}

class FakeAgentInventoryPort implements AgentInventoryPort {
  List<AgentSummary> agents = const <AgentSummary>[];
  Map<String, AgentInvocationPolicy> invocationPolicies =
      <String, AgentInvocationPolicy>{};
  AgentRegistrationToken nextDaemonToken = const AgentRegistrationToken(
    token: 'daemon-token',
  );
  AgentRegistrationToken nextRuntimeToken = const AgentRegistrationToken(
    token: 'runtime-token',
  );

  @override
  Future<AgentRegistrationToken> issueDaemonToken({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    return nextDaemonToken;
  }

  @override
  Future<AgentRegistrationToken> issueRuntimeToken({
    required String controllerDid,
    required String daemonAgentDid,
    required String runtime,
    required String handle,
    required String displayName,
    String? driverId,
    String? workspaceMode,
    String? defaultSandbox,
    String? defaultModel,
    Map<String, Object?>? driverConfig,
  }) async {
    return nextRuntimeToken;
  }

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    return agents;
  }

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy({
    required String agentDid,
  }) async {
    return invocationPolicies[agentDid] ?? const AgentInvocationPolicy();
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    invocationPolicies[agentDid] = policy;
    return policy;
  }

  @override
  Future<void> unbindAgent({required String agentDid}) async {
    agents = agents.where((agent) => agent.agentDid != agentDid).toList();
  }

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) async {
    final updated = AgentSummary(
      agentDid: agentDid,
      kind: AgentKind.daemon,
      displayName: displayName,
      activeState: 'active',
      latest: const AgentLatestStatus(status: 'ready'),
    );
    agents = <AgentSummary>[
      for (final agent in agents)
        if (agent.agentDid == agentDid) updated else agent,
    ];
    return updated;
  }
}

class FakeAgentControlService implements AgentControlService {
  List<AgentSummary> agents = <AgentSummary>[
    const AgentSummary(
      agentDid: 'did:agent:daemon',
      kind: AgentKind.daemon,
      handle: 'awiki-daemon-test',
      displayName: '代理 1',
      activeState: 'active',
      latest: readyDaemonStatusWithGenericCliCapability,
    ),
  ];
  InstallCommand? lastInstallCommand;
  InstallCommand nextInstallCommand = const InstallCommand(
    token: AgentRegistrationToken(token: 'daemon-token'),
    command:
        'curl -fsSL https://awiki.info/daemon/install.sh | sh -s -- --token daemon-token',
    fallbackCommand:
        'awiki-deamon install --token daemon-token --base-url https://awiki.info',
    installerUrl: 'https://awiki.info/daemon/install.sh',
    packageUrlTemplate:
        'https://awiki.info/daemon/releases/<version>/awiki-deamon-<os>-<arch>.tar.gz',
  );
  String? lastRefreshedDaemonDid;
  String? lastInstallControllerDid;
  String? lastInstallControllerHandle;
  String? lastInstallClientPlatform;
  String? lastRuntimeCreateDaemonDid;
  RuntimeAgentKind? lastRuntimeCreateKind;
  String? lastRuntimeCreateControllerDid;
  String? lastBootstrapDaemonDid;
  String? lastBootstrapControllerDid;
  String? lastBootstrapAppInstanceId;
  UserSubkeyPackage? lastBootstrapUserSubkeyPackage;
  String? lastRuntimeCreateHandle;
  String? lastRuntimeCreateDisplayName;
  String? lastRuntimeCreateWorkspaceMode;
  String? lastRuntimeCreateSandbox;
  String? lastRuntimeCreateModel;
  String? lastRuntimeCreateClientRequestId;
  String? lastResetDaemonDid;
  String? lastResetRuntimeDid;
  String? lastRetryDaemonDid;
  String? lastRetryRuntimeDid;
  String? lastRetryRunId;
  String? lastInboxDaemonDid;
  String? lastInboxRuntimeDid;
  String? lastInboxScope;
  int? lastInboxLimit;
  String? lastInboxCursor;
  String nextInboxRequestId = 'cmd_runtime_inbox_test';
  String? lastInboxThreadDaemonDid;
  String? lastInboxThreadRuntimeDid;
  String? lastInboxThreadId;
  String? lastInboxThreadKind;
  String? lastInboxThreadPeerHandle;
  int? lastInboxThreadLimit;
  String? lastInboxThreadCursor;
  String nextInboxThreadRequestId = 'cmd_runtime_inbox_thread_test';
  String? lastUnboundAgentDid;
  String? lastDeletedDaemonDid;
  String? lastDeletedRuntimeDaemonDid;
  String? lastDeletedRuntimeDid;
  String? lastPausedMessageAgentDaemonDid;
  String? lastPausedMessageAgentDid;
  String? lastDeletedMessageAgentDaemonDid;
  String? lastDeletedMessageAgentDid;
  String? lastRevokedMessageAgentDaemonDid;
  String? lastRevokedMessageAgentDid;
  String? lastRenamedAgentDid;
  String? lastDisplayName;
  String? lastUpgradeDaemonDid;
  String nextUpgradeCommandId = 'cmd_daemon_upgrade_test';
  String? lastCancelledUpgradeDaemonDid;
  String? lastCancelledUpgradeCommandId;
  String? lastCancelledUpgradeTargetCommandId;
  String nextCancelUpgradeCommandId = 'cmd_daemon_upgrade_cancel_test';
  Map<String, AgentInvocationPolicy> invocationPolicies =
      <String, AgentInvocationPolicy>{};
  String? lastInvocationPolicyAgentDid;
  AgentInvocationPolicy? lastInvocationPolicy;
  DaemonBootstrapPublicKey? lastBootstrapDaemonPublicKey;

  @override
  Future<InstallCommand> createDaemonInstallCommand({
    required String controllerDid,
    required String controllerHandle,
    required String clientPlatform,
  }) async {
    lastInstallControllerDid = controllerDid;
    lastInstallControllerHandle = controllerHandle;
    lastInstallClientPlatform = clientPlatform;
    return lastInstallCommand = nextInstallCommand;
  }

  @override
  Future<void> createHermesRuntime({
    required String daemonAgentDid,
    required String controllerDid,
    required String handle,
    required String displayName,
    String? clientRequestId,
  }) {
    return createRuntimeAgent(
      daemonAgentDid: daemonAgentDid,
      controllerDid: controllerDid,
      options: RuntimeAgentCreateOptions(
        kind: RuntimeAgentKind.hermes,
        handle: handle,
        displayName: displayName,
      ),
      clientRequestId: clientRequestId,
    );
  }

  @override
  Future<void> createRuntimeAgent({
    required String daemonAgentDid,
    required String controllerDid,
    required RuntimeAgentCreateOptions options,
    String? clientRequestId,
  }) async {
    lastRuntimeCreateDaemonDid = daemonAgentDid;
    lastRuntimeCreateControllerDid = controllerDid;
    lastRuntimeCreateKind = options.kind;
    lastRuntimeCreateHandle = options.handle;
    lastRuntimeCreateDisplayName = options.displayName;
    lastRuntimeCreateWorkspaceMode = options.workspaceMode;
    lastRuntimeCreateSandbox = options.sandbox;
    lastRuntimeCreateModel = options.model;
    lastRuntimeCreateClientRequestId = clientRequestId;
  }

  @override
  Future<void> ensureMessageAgentBootstrap({
    required String daemonAgentDid,
    required String controllerDid,
    required String appInstanceId,
    required UserSubkeyPackage userSubkeyPackage,
    required DaemonBootstrapPublicKey daemonBootstrapPublicKey,
    String? userHandle,
    String? runtimeRegistrationToken,
    String? runId,
  }) async {
    lastBootstrapDaemonDid = daemonAgentDid;
    lastBootstrapControllerDid = controllerDid;
    lastBootstrapAppInstanceId = appInstanceId;
    lastBootstrapUserSubkeyPackage = userSubkeyPackage;
    lastBootstrapDaemonPublicKey = daemonBootstrapPublicKey;
  }

  @override
  Future<List<AgentSummary>> listAgents({bool includeInactive = false}) async {
    return agents;
  }

  @override
  Future<AgentInvocationPolicy> getInvocationPolicy(String agentDid) async {
    return invocationPolicies[agentDid] ?? const AgentInvocationPolicy();
  }

  @override
  Future<AgentInvocationPolicy> updateInvocationPolicy({
    required String agentDid,
    required AgentInvocationPolicy policy,
  }) async {
    lastInvocationPolicyAgentDid = agentDid;
    lastInvocationPolicy = policy;
    invocationPolicies[agentDid] = policy;
    return policy;
  }

  @override
  Future<void> refreshDaemonStatus(
    String daemonAgentDid, {
    String? commandId,
  }) async {
    lastRefreshedDaemonDid = daemonAgentDid;
  }

  @override
  Future<void> resetRuntimeSession({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    String? conversationId,
  }) async {
    lastResetDaemonDid = daemonAgentDid;
    lastResetRuntimeDid = runtimeAgentDid;
  }

  @override
  Future<void> retryRun({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String runId,
  }) async {
    lastRetryDaemonDid = daemonAgentDid;
    lastRetryRuntimeDid = runtimeAgentDid;
    lastRetryRunId = runId;
  }

  @override
  Future<String> queryRuntimeInbox({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    String scope = 'all',
    int limit = 20,
    String? cursor,
  }) async {
    lastInboxDaemonDid = daemonAgentDid;
    lastInboxRuntimeDid = runtimeAgentDid;
    lastInboxScope = scope;
    lastInboxLimit = limit;
    lastInboxCursor = cursor;
    return nextInboxRequestId;
  }

  @override
  Future<String> queryRuntimeInboxThread({
    required String daemonAgentDid,
    required String runtimeAgentDid,
    required String threadId,
    required String kind,
    String? peerDid,
    String? peerHandle,
    String? groupDid,
    int limit = 20,
    String? cursor,
  }) async {
    lastInboxThreadDaemonDid = daemonAgentDid;
    lastInboxThreadRuntimeDid = runtimeAgentDid;
    lastInboxThreadId = threadId;
    lastInboxThreadKind = kind;
    lastInboxThreadPeerHandle = peerHandle;
    lastInboxThreadLimit = limit;
    lastInboxThreadCursor = cursor;
    return nextInboxThreadRequestId;
  }

  @override
  Future<void> unbindAgent(String agentDid) async {
    lastUnboundAgentDid = agentDid;
    agents = agents.where((agent) => agent.agentDid != agentDid).toList();
  }

  @override
  Future<void> deleteDaemon(String daemonAgentDid) async {
    lastDeletedDaemonDid = daemonAgentDid;
  }

  @override
  Future<void> deleteRuntimeAgent({
    required String daemonAgentDid,
    required String runtimeAgentDid,
  }) async {
    lastDeletedRuntimeDaemonDid = daemonAgentDid;
    lastDeletedRuntimeDid = runtimeAgentDid;
  }

  @override
  Future<MessageAgentBinding> pauseMessageAgent({
    required String daemonAgentDid,
    required String messageAgentDid,
  }) async {
    lastPausedMessageAgentDaemonDid = daemonAgentDid;
    lastPausedMessageAgentDid = messageAgentDid;
    return _messageAgentBinding(
      daemonAgentDid: daemonAgentDid,
      messageAgentDid: messageAgentDid,
      status: 'disabled',
    );
  }

  @override
  Future<MessageAgentBinding> deleteMessageAgent({
    required String daemonAgentDid,
    required String messageAgentDid,
  }) async {
    lastDeletedMessageAgentDaemonDid = daemonAgentDid;
    lastDeletedMessageAgentDid = messageAgentDid;
    lastPausedMessageAgentDaemonDid = daemonAgentDid;
    lastPausedMessageAgentDid = messageAgentDid;
    lastDeletedRuntimeDaemonDid = daemonAgentDid;
    lastDeletedRuntimeDid = messageAgentDid;
    return _messageAgentBinding(
      daemonAgentDid: daemonAgentDid,
      messageAgentDid: messageAgentDid,
      status: 'disabled',
    );
  }

  @override
  Future<MessageAgentBinding> revokeMessageAgentAuthorization({
    required String daemonAgentDid,
    required String messageAgentDid,
  }) async {
    lastRevokedMessageAgentDaemonDid = daemonAgentDid;
    lastRevokedMessageAgentDid = messageAgentDid;
    return _messageAgentBinding(
      daemonAgentDid: daemonAgentDid,
      messageAgentDid: messageAgentDid,
      status: 'revoked',
    );
  }

  @override
  Future<AgentSummary> updateDisplayName({
    required String agentDid,
    required String displayName,
  }) async {
    lastRenamedAgentDid = agentDid;
    lastDisplayName = displayName;
    final index = agents.indexWhere((agent) => agent.agentDid == agentDid);
    if (index < 0) {
      return agents.first;
    }
    final current = agents[index];
    final updated = AgentSummary(
      agentDid: current.agentDid,
      kind: current.kind,
      daemonAgentDid: current.daemonAgentDid,
      runtime: current.runtime,
      handle: current.handle,
      displayName: displayName,
      activeState: current.activeState,
      latest: current.latest,
    );
    agents = <AgentSummary>[
      for (final agent in agents)
        if (agent.agentDid == agentDid) updated else agent,
    ];
    return updated;
  }

  @override
  Future<String> upgradeDaemon(
    String daemonAgentDid, {
    String? commandId,
  }) async {
    lastUpgradeDaemonDid = daemonAgentDid;
    return commandId ?? nextUpgradeCommandId;
  }

  @override
  Future<String> cancelDaemonUpgrade(
    String daemonAgentDid, {
    String? commandId,
    String? upgradeCommandId,
  }) async {
    lastCancelledUpgradeDaemonDid = daemonAgentDid;
    lastCancelledUpgradeCommandId = commandId;
    lastCancelledUpgradeTargetCommandId = upgradeCommandId;
    return commandId ?? nextCancelUpgradeCommandId;
  }
}

class FakeProductLocalStore implements ProductLocalStore {
  final Map<String, ProductConversationOverlay> overlays =
      <String, ProductConversationOverlay>{};
  final Map<String, MessageDraft> drafts = <String, MessageDraft>{};
  final Map<String, LocalUiPreference> preferences =
      <String, LocalUiPreference>{};
  final Map<String, LocalAgentState> agentStates = <String, LocalAgentState>{};

  String _key(String ownerDid, String id) => '$ownerDid::$id';

  @override
  Future<void> warmUp() async {}

  @override
  Future<void> deleteAgentState({
    required String ownerDid,
    required String agentDid,
  }) async {
    agentStates.remove(_key(ownerDid, agentDid));
  }

  @override
  Future<void> deleteConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    overlays.remove(_key(ownerDid, threadId));
  }

  @override
  Future<void> deleteDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    drafts.remove(_key(ownerDid, threadId));
  }

  @override
  Future<void> deleteUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    preferences.remove(_key(ownerDid, key));
  }

  @override
  Future<List<LocalAgentState>> loadAgentStates({
    required String ownerDid,
  }) async {
    return agentStates.values
        .where((state) => state.ownerDid == ownerDid)
        .toList();
  }

  @override
  Future<ProductConversationOverlay?> loadConversationOverlay({
    required String ownerDid,
    required String threadId,
  }) async {
    return overlays[_key(ownerDid, threadId)];
  }

  @override
  Future<Map<String, ProductConversationOverlay>> loadConversationOverlays({
    required String ownerDid,
    Iterable<String>? threadIds,
  }) async {
    final ids = threadIds?.toSet();
    return <String, ProductConversationOverlay>{
      for (final overlay in overlays.values)
        if (overlay.ownerDid == ownerDid &&
            (ids == null || ids.contains(overlay.threadId)))
          overlay.threadId: overlay,
    };
  }

  @override
  Future<MessageDraft?> loadDraft({
    required String ownerDid,
    required String threadId,
  }) async {
    return drafts[_key(ownerDid, threadId)];
  }

  @override
  Future<LocalUiPreference?> loadUiPreference({
    required String ownerDid,
    required String key,
  }) async {
    return preferences[_key(ownerDid, key)];
  }

  @override
  Future<void> saveAgentState(LocalAgentState state) async {
    agentStates[_key(state.ownerDid, state.agentDid)] = state;
  }

  @override
  Future<void> saveDraft(MessageDraft draft) async {
    drafts[_key(draft.ownerDid, draft.threadId)] = draft;
  }

  @override
  Future<void> saveUiPreference(LocalUiPreference preference) async {
    preferences[_key(preference.ownerDid, preference.key)] = preference;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    required DateTime updatedAt,
  }) {
    return setConversationHidden(
      ownerDid: ownerDid,
      conversationKey: threadId,
      hidden: hidden,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> setConversationHidden({
    required String ownerDid,
    required String conversationKey,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final key = _key(ownerDid, conversationKey);
    final existing = overlays[key];
    overlays[key] =
        (existing ??
                ProductConversationOverlay(
                  ownerDid: ownerDid,
                  threadId: conversationKey,
                  updatedAt: updatedAt,
                ))
            .copyWith(hidden: hidden, updatedAt: updatedAt);
  }

  @override
  Future<void> upsertConversationOverlay(
    ProductConversationOverlay overlay,
  ) async {
    overlays[_key(overlay.ownerDid, overlay.threadId)] = overlay;
  }
}

class FakeGroupApplicationService implements GroupApplicationService {
  const FakeGroupApplicationService(this.gateway);

  final FakeAwikiGateway gateway;

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) {
    return gateway.addGroupMember(
      groupId: groupDid,
      memberRef: memberRef,
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
    required String memberRef,
  }) {
    return gateway.removeGroupMember(groupId: groupDid, memberRef: memberRef);
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
  Future<HandleAvailability> validateHandle({
    required String handle,
    String? domain,
  }) {
    return gateway.validateHandle(handle: handle, domain: domain);
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

class FakeIdentityCorePort implements IdentityCorePort {
  FakeIdentityCorePort({
    UserSubkeyPackage? daemonSubkeyPackage,
    AppSession? defaultSession,
  }) : daemonSubkeyPackage =
           daemonSubkeyPackage ??
           const UserSubkeyPackage(
             userDid: 'did:human:me',
             verificationMethod: 'did:human:me#daemon-key-1',
             publicKeyMultibase: 'zPublic',
             privateKeyMultibase: 'zPrivate',
           ),
       defaultSession =
           defaultSession ??
           const AppSession(
             did: 'did:human:me',
             identityId: 'default',
             displayName: 'Me',
             localAlias: 'default',
           );

  final UserSubkeyPackage daemonSubkeyPackage;
  final AppSession defaultSession;
  String? lastDaemonSubkeySelector;
  String? lastEnsuredDaemonSubkeySelector;
  String? lastRevokedDaemonSubkeySelector;

  @override
  Future<AppSession?> defaultIdentity() async => defaultSession;

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    defaultSession,
  ];

  @override
  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) async {
    lastDaemonSubkeySelector = identityIdOrAlias;
    return daemonSubkeyPackage;
  }

  @override
  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) async {
    lastEnsuredDaemonSubkeySelector = identityIdOrAlias;
    return daemonSubkeyPackage;
  }

  @override
  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  ) async {
    lastRevokedDaemonSubkeySelector = identityIdOrAlias;
    return DaemonSubkeyAuthorizationRevokeResult(
      userDid: daemonSubkeyPackage.userDid,
      verificationMethod: daemonSubkeyPackage.verificationMethod,
      updated: true,
    );
  }

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async => defaultSession;

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => defaultSession;

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => defaultSession;

  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async =>
      defaultSession;

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async =>
      defaultSession;
}

AppSession _appSessionFromLegacy(SessionIdentity session) {
  return AppSession(
    did: session.did,
    identityId: session.credentialName,
    displayName: session.displayName,
    handle: session.handle,
    localAlias: session.credentialName,
    authenticated: session.jwtToken != null,
    jwtToken: session.jwtToken,
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

MessageAgentBinding _messageAgentBinding({
  required String daemonAgentDid,
  required String messageAgentDid,
  required String status,
}) {
  return MessageAgentBinding(
    id: 'binding_$messageAgentDid',
    userDid: 'did:human:me',
    daemonAgentDid: daemonAgentDid,
    messageAgentDid: messageAgentDid,
    runtimeProvider: 'hermes',
    runtimeProfile: const <String, Object?>{'profile': 'message_agent'},
    delegatedKeyVerificationMethod: 'did:human:me#daemon-key-1',
    status: status,
  );
}
