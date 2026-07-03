import 'dart:io';

import 'package:flutter/foundation.dart';

import '../application/config/awiki_environment_config.dart';
import '../application/agent/agent_control_service.dart';
import '../application/agent/agent_control_status_store.dart';
import '../application/app_session_service.dart';
import '../application/conversation_service.dart';
import '../application/directory_application_service.dart';
import '../application/group_application_service.dart';
import '../application/messaging_service.dart';
import '../application/message_sync_service.dart';
import '../application/onboarding_service.dart';
import '../application/onboarding_support_service.dart';
import '../application/peer_identity_service.dart';
import '../application/ports/agent_inventory_port.dart';
import '../application/ports/identity_core_port.dart';
import '../application/ports/message_agent_binding_port.dart';
import '../application/product_local_store.dart';
import '../application/profile_application_service.dart';
import '../application/realtime_application_service.dart';
import '../application/relationship_application_service.dart';
import '../data/compat/compat_awiki_account_gateway.dart';
import '../data/compat/compat_awiki_gateway.dart';
import '../data/compat/compat_realtime_gateway.dart';
import '../data/agent/user_service_agent_inventory_adapter.dart';
import '../data/agent/user_service_message_agent_binding_adapter.dart';
import '../data/im_core/awiki_im_core_auth_adapter.dart';
import '../data/im_core/awiki_im_core_agent_control_status_store.dart';
import '../data/im_core/awiki_im_core_config.dart';
import '../data/im_core/awiki_im_core_conversation_adapter.dart';
import '../data/im_core/awiki_im_core_directory_adapter.dart';
import '../data/im_core/awiki_im_core_group_adapter.dart';
import '../data/im_core/awiki_im_core_identity_adapter.dart';
import '../data/im_core/awiki_im_core_message_adapter.dart';
import '../data/im_core/awiki_im_core_message_sync_adapter.dart';
import '../data/im_core/awiki_im_core_paths.dart';
import '../data/im_core/awiki_im_core_profile_adapter.dart';
import '../data/im_core/awiki_im_core_realtime_adapter.dart';
import '../data/im_core/awiki_im_core_relationship_adapter.dart';
import '../data/im_core/awiki_im_core_runtime.dart';
import '../data/im_core/awiki_im_core_secret_storage.dart';
import '../data/local/awiki_product_local_store_sqlite.dart';
import '../data/services/app_key_value_store.dart';
import '../data/services/app_notification_facade.dart';
import '../data/services/app_update_service.dart';
import '../data/services/awiki_onboarding_support_service.dart';
import '../data/services/key_value_active_session_store.dart';
import '../data/services/locale_preference_service.dart';
import '../data/services/user_service_peer_identity_service.dart';
import '../domain/repositories/awiki_account_gateway.dart';
import '../data/services/noop_e2ee_facade.dart';
import '../domain/repositories/awiki_gateway.dart';
import '../domain/services/e2ee_facade.dart';
import '../domain/services/notification_facade.dart';
import '../domain/services/realtime_gateway.dart';
import '../domain/services/update_service.dart';
import '../core/performance_logger.dart';

class AppBootstrap {
  AppBootstrap({
    required this.environment,
    required this.accountGateway,
    required this.gateway,
    required this.realtimeGateway,
    required this.notificationFacade,
    required this.e2eeFacade,
    required this.localePreferenceService,
    required this.updateService,
    this.appSessionService,
    this.identityCorePort,
    this.onboardingService,
    this.onboardingSupportService,
    this.messagingService,
    this.messageSyncService,
    this.conversationService,
    this.agentInventoryPort,
    this.messageAgentBindingPort,
    this.agentControlService,
    this.agentControlStatusStore,
    this.groupApplicationService,
    this.profileApplicationService,
    this.directoryApplicationService,
    this.relationshipApplicationService,
    this.realtimeApplicationService,
    this.productLocalStore,
    this.peerIdentityService,
  });

  final AwikiEnvironmentConfig environment;
  final AwikiAccountGateway accountGateway;
  final AwikiGateway gateway;
  final RealtimeGateway realtimeGateway;
  final NotificationFacade notificationFacade;
  final E2eeFacade e2eeFacade;
  final LocalePreferenceService localePreferenceService;
  final UpdateService updateService;
  final AppSessionService? appSessionService;
  final IdentityCorePort? identityCorePort;
  final OnboardingService? onboardingService;
  final OnboardingSupportService? onboardingSupportService;
  final MessagingService? messagingService;
  final MessageSyncService? messageSyncService;
  final ConversationService? conversationService;
  final AgentInventoryPort? agentInventoryPort;
  final MessageAgentBindingPort? messageAgentBindingPort;
  final AgentControlService? agentControlService;
  final AgentControlStatusStore? agentControlStatusStore;
  final GroupApplicationService? groupApplicationService;
  final ProfileApplicationService? profileApplicationService;
  final DirectoryApplicationService? directoryApplicationService;
  final RelationshipApplicationService? relationshipApplicationService;
  final RealtimeApplicationService? realtimeApplicationService;
  final ProductLocalStore? productLocalStore;
  final PeerIdentityService? peerIdentityService;

  static Future<AppBootstrap> create({
    AwikiEnvironmentConfig? environment,
    String? appStateRoot,
  }) async {
    final totalWatch = Stopwatch()..start();
    final effectiveEnvironment =
        environment ?? AwikiEnvironmentConfig.fromEnvironment();
    final preferenceStorage = await AwikiPerformanceLogger.async(
      'bootstrap.preference_store',
      () => _buildPreferenceStore(appStateRoot: appStateRoot),
    );

    final pathLayout = await AwikiPerformanceLogger.async(
      'bootstrap.im_core_paths',
      () => AwikiImCorePathLayout.fromPlatform(
        appStateRoot: appStateRoot,
        stateNamespace: effectiveEnvironment.stateNamespace,
      ),
    );
    final vaultSecretStorage = await AwikiPerformanceLogger.async(
      'bootstrap.im_core_vault_secret_store',
      () => _buildVaultSecretStore(appStateRoot: appStateRoot),
    );
    final runtime = AwikiImCoreRuntime(
      config: AwikiImCoreEnvironmentConfig.fromAwikiEnvironment(
        effectiveEnvironment,
      ),
      paths: pathLayout,
      vaultSecretProvider: StoredAwikiImCoreVaultSecretProvider(
        storage: vaultSecretStorage,
      ),
    );
    final productLocalStore = AwikiProductLocalStoreSqlite(
      stateNamespace: effectiveEnvironment.stateNamespace,
    );
    final activeSessionStore = KeyValueActiveSessionStore(
      storage: preferenceStorage,
      stateNamespace: effectiveEnvironment.stateNamespace,
    );

    final identityAdapter = AwikiImCoreIdentityAdapter(runtime: runtime);
    final authAdapter = AwikiImCoreAuthAdapter(runtime: runtime);
    final messageAdapter = AwikiImCoreMessageAdapter(runtime: runtime);
    final messageSyncAdapter = AwikiImCoreMessageSyncAdapter(runtime: runtime);
    final conversationAdapter = AwikiImCoreConversationAdapter(
      runtime: runtime,
    );
    final groupAdapter = AwikiImCoreGroupAdapter(runtime: runtime);
    final profileAdapter = AwikiImCoreProfileAdapter(runtime: runtime);
    final directoryAdapter = AwikiImCoreDirectoryAdapter(runtime: runtime);
    final relationshipAdapter = AwikiImCoreRelationshipAdapter(
      runtime: runtime,
    );
    final realtimeAdapter = AwikiImCoreRealtimeAdapter(runtime: runtime);
    final messagingService = ImCoreMessagingService(messages: messageAdapter);
    final messageSyncService = ImCoreMessageSyncService(
      sync: messageSyncAdapter,
    );
    final agentInventoryPort = UserServiceAgentInventoryAdapter.fromEnvironment(
      environment: effectiveEnvironment,
    );
    final messageAgentBindingPort = UserServiceMessageAgentBindingAdapter(
      userServiceUrl: effectiveEnvironment.userServiceUrl,
    );
    final conversationService = ImCoreConversationService(
      conversations: conversationAdapter,
      localStore: productLocalStore,
      agentInventory: agentInventoryPort,
    );
    final agentControlService = DefaultAgentControlService(
      inventory: agentInventoryPort,
      messages: messagingService,
      messageAgentBindings: messageAgentBindingPort,
      identities: identityAdapter,
    );
    final agentControlStatusStore = AwikiImCoreAgentControlStatusStore(
      messages: messageAdapter,
    );
    final groupApplicationService = ImCoreGroupApplicationService(
      groups: groupAdapter,
    );
    final profileApplicationService = ImCoreProfileApplicationService(
      profiles: profileAdapter,
    );
    final directoryApplicationService = ImCoreDirectoryApplicationService(
      directory: directoryAdapter,
    );
    final relationshipApplicationService = ImCoreRelationshipApplicationService(
      relationships: relationshipAdapter,
    );
    final realtimeApplicationService = ImCoreRealtimeApplicationService(
      realtime: realtimeAdapter,
    );
    final appSessionService = ImCoreAppSessionService(
      runtime: runtime,
      identities: identityAdapter,
      auth: authAdapter,
      activeSessionStore: activeSessionStore,
      expectedDidDomain: effectiveEnvironment.didDomain,
      realtime: realtimeAdapter,
    );
    final onboardingService = ImCoreOnboardingService(
      identities: identityAdapter,
      sessions: appSessionService,
      profiles: profileAdapter,
    );
    final onboardingSupportService = AwikiOnboardingSupportService(
      userServiceUrl: effectiveEnvironment.userServiceUrl,
    );
    final peerIdentityService = UserServicePeerIdentityService(
      userServiceUrl: effectiveEnvironment.userServiceUrl,
    );

    final accountGateway = CompatAwikiAccountGateway(
      sessions: appSessionService,
      onboarding: onboardingService,
      onboardingSupport: onboardingSupportService,
    );
    final gateway = CompatAwikiGateway(
      sessions: appSessionService,
      profiles: profileApplicationService,
      relationships: relationshipApplicationService,
      conversations: conversationService,
      messages: messagingService,
      groups: groupApplicationService,
    );
    final realtimeGateway = CompatRealtimeGateway(
      realtime: realtimeApplicationService,
    );

    final notificationFacade = await AppNotificationFacade.create();
    final e2eeFacade = NoopE2eeFacade();
    final localePreferenceService = LocalePreferenceService(
      storage: preferenceStorage,
    );
    final updateService = AppUpdateService(storage: preferenceStorage);
    final bootstrap = AppBootstrap(
      environment: effectiveEnvironment,
      accountGateway: accountGateway,
      gateway: gateway,
      realtimeGateway: realtimeGateway,
      notificationFacade: notificationFacade,
      e2eeFacade: e2eeFacade,
      localePreferenceService: localePreferenceService,
      updateService: updateService,
      appSessionService: appSessionService,
      identityCorePort: identityAdapter,
      onboardingService: onboardingService,
      onboardingSupportService: onboardingSupportService,
      messagingService: messagingService,
      messageSyncService: messageSyncService,
      conversationService: conversationService,
      agentInventoryPort: agentInventoryPort,
      messageAgentBindingPort: messageAgentBindingPort,
      agentControlService: agentControlService,
      agentControlStatusStore: agentControlStatusStore,
      groupApplicationService: groupApplicationService,
      profileApplicationService: profileApplicationService,
      directoryApplicationService: directoryApplicationService,
      relationshipApplicationService: relationshipApplicationService,
      realtimeApplicationService: realtimeApplicationService,
      productLocalStore: productLocalStore,
      peerIdentityService: peerIdentityService,
    );
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'bootstrap.create',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        'custom_state_root': appStateRoot?.trim().isNotEmpty == true,
        'state_namespace': effectiveEnvironment.stateNamespace,
      },
    );
    return bootstrap;
  }

  @visibleForTesting
  static Future<AppKeyValueStore> buildAccountStoreForTesting() {
    return _buildAccountStore();
  }

  @visibleForTesting
  static Future<AppKeyValueStore> buildVaultSecretStoreForTesting({
    String? appStateRoot,
  }) {
    return _buildVaultSecretStore(appStateRoot: appStateRoot);
  }

  static Future<AppKeyValueStore> _buildAccountStore({
    String? appStateRoot,
  }) async {
    if (_hasStateRoot(appStateRoot) || awikiE2eAppStateRoot() != null) {
      return FileAppKeyValueStore.create(
        fileName: 'awiki_me_credentials.json',
        appStateRoot: appStateRoot,
      );
    }
    if (Platform.isMacOS && !kReleaseMode) {
      // Local macOS debug/profile builds are usually ad-hoc signed, and
      // Keychain writes can fail after a successful backend registration.
      return FileAppKeyValueStore.create(fileName: 'awiki_me_credentials.json');
    }
    return SecureAppKeyValueStore();
  }

  static Future<AppKeyValueStore> _buildPreferenceStore({
    String? appStateRoot,
  }) async {
    if (_hasStateRoot(appStateRoot) || awikiE2eAppStateRoot() != null) {
      return FileAppKeyValueStore.create(appStateRoot: appStateRoot);
    }
    if (Platform.isMacOS) {
      // macOS debug builds are not consistently signed for Keychain access.
      return FileAppKeyValueStore.create();
    }
    return SecureAppKeyValueStore();
  }

  static Future<AppKeyValueStore> _buildVaultSecretStore({
    String? appStateRoot,
  }) async {
    final e2eRoot = awikiE2eAppStateRoot();
    if (e2eRoot != null) {
      return FileAppKeyValueStore.create(
        fileName: 'awiki_me_im_core_vault.json',
        appStateRoot: e2eRoot,
        strictRead: true,
        privateFile: true,
      );
    }
    return SecureAppKeyValueStore();
  }
}

bool _hasStateRoot(String? value) => value != null && value.trim().isNotEmpty;
