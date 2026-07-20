// [INPUT]: Tenant scope, environment gates, platform secret storage, and native IM Core.
// [OUTPUT]: Fully composed AWiki Me adapters/services for one immutable storage scope.
// [POS]: Production composition root; device secrets remain owned by Vault-backed IM Core.

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../application/config/awiki_environment_config.dart';
import '../application/attachment_cache_service.dart';
import '../application/agent/agent_control_service.dart';
import '../application/agent/agent_control_status_store.dart';
import '../application/app_session_service.dart';
import '../application/conversation_service.dart';
import '../application/directory_application_service.dart';
import '../application/group_application_service.dart';
import '../application/messaging_service.dart';
import '../application/message_sync_service.dart';
import '../application/models/product_local_models.dart';
import '../application/onboarding_service.dart';
import '../application/onboarding_support_service.dart';
import '../application/peer_identity_service.dart';
import '../application/ports/agent_inventory_port.dart';
import '../application/ports/device_management_core_port.dart';
import '../application/ports/identity_core_port.dart';
import '../application/ports/personal_agent_binding_port.dart';
import '../application/ports/root_key_transfer_port.dart';
import '../application/product_local_store.dart';
import '../application/profile_application_service.dart';
import '../application/realtime_application_service.dart';
import '../application/relationship_application_service.dart';
import '../data/compat/compat_awiki_account_gateway.dart';
import '../data/compat/compat_awiki_gateway.dart';
import '../data/compat/compat_realtime_gateway.dart';
import '../data/agent/user_service_agent_inventory_adapter.dart';
import '../data/agent/user_service_personal_agent_binding_adapter.dart';
import '../data/im_core/awiki_im_core_auth_adapter.dart';
import '../data/im_core/awiki_im_core_agent_control_status_store.dart';
import '../data/im_core/awiki_im_core_config.dart';
import '../data/im_core/awiki_im_core_conversation_adapter.dart';
import '../data/im_core/awiki_im_core_directory_adapter.dart';
import '../data/im_core/awiki_im_core_device_management_adapter.dart';
import '../data/im_core/awiki_im_core_group_adapter.dart';
import '../data/im_core/awiki_im_core_identity_adapter.dart';
import '../data/im_core/awiki_im_core_message_adapter.dart';
import '../data/im_core/awiki_im_core_message_sync_adapter.dart';
import '../data/im_core/awiki_im_core_paths.dart';
import '../data/im_core/awiki_im_core_profile_adapter.dart';
import '../data/im_core/awiki_im_core_realtime_adapter.dart';
import '../data/im_core/awiki_im_core_root_key_transfer_adapter.dart';
import '../data/im_core/awiki_im_core_relationship_adapter.dart';
import '../data/im_core/awiki_im_core_runtime.dart';
import '../data/im_core/awiki_im_core_secret_storage.dart';
import '../data/im_core/storage_scope_im_core_validator.dart';
import '../data/local/awiki_product_local_store_sqlite.dart';
import '../data/services/app_key_value_store.dart';
import '../data/services/app_notification_facade.dart';
import '../data/services/app_update_service.dart';
import '../data/services/awiki_onboarding_support_service.dart';
import '../data/services/key_value_active_session_store.dart';
import '../data/services/file_attachment_cache_service.dart';
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
import '../application/tenant/app_tenant.dart';
import '../data/storage/awiki_storage_scope_layout.dart';
import '../data/storage/scope_secret_repository_factory.dart';
import '../data/tenant/app_tenant_store.dart';

enum AppBootstrapProgress {
  preparing,
  upgradingLocalState,
  migratingLocalOverlays,
  startingApplication,
}

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
    this.deviceManagementCorePort,
    this.rootKeyTransferPort,
    this.onboardingService,
    this.onboardingSupportService,
    this.messagingService,
    this.messageSyncService,
    this.conversationService,
    this.agentInventoryPort,
    this.personalAgentBindingPort,
    this.agentControlService,
    this.agentControlStatusStore,
    this.groupApplicationService,
    this.profileApplicationService,
    this.directoryApplicationService,
    this.relationshipApplicationService,
    this.realtimeApplicationService,
    this.productLocalStore,
    this.peerIdentityService,
    this.attachmentCacheService,
    this.storageScopeLayout,
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
  final DeviceManagementCorePort? deviceManagementCorePort;
  final RootKeyTransferPort? rootKeyTransferPort;
  final OnboardingService? onboardingService;
  final OnboardingSupportService? onboardingSupportService;
  final MessagingService? messagingService;
  final MessageSyncService? messageSyncService;
  final ConversationService? conversationService;
  final AgentInventoryPort? agentInventoryPort;
  final PersonalAgentBindingPort? personalAgentBindingPort;
  final AgentControlService? agentControlService;
  final AgentControlStatusStore? agentControlStatusStore;
  final GroupApplicationService? groupApplicationService;
  final ProfileApplicationService? profileApplicationService;
  final DirectoryApplicationService? directoryApplicationService;
  final RelationshipApplicationService? relationshipApplicationService;
  final RealtimeApplicationService? realtimeApplicationService;
  final ProductLocalStore? productLocalStore;
  final PeerIdentityService? peerIdentityService;
  final AttachmentCacheService? attachmentCacheService;
  final AwikiStorageScopeLayout? storageScopeLayout;

  static Future<AppBootstrap> create({
    AwikiEnvironmentConfig? environment,
    String? appStateRoot,
    AppTenantProfile? tenant,
    void Function(AppBootstrapProgress progress)? onProgress,
  }) async {
    final totalWatch = Stopwatch()..start();
    final scopeSecretRepository = buildScopeSecretRepository(
      appStateRoot: appStateRoot,
    );
    final tenantStore = AppTenantStore(
      appStateRoot: appStateRoot,
      secretRepository: scopeSecretRepository,
      readyValidator: StorageScopeImCoreValidator(
        repository: scopeSecretRepository,
      ).call,
      initialTenantFactory: environment != null && tenant == null
          ? () => defaultTenantProfile().copyWith(
              backendBaseUrl: environment.baseUrl,
              didHost: environment.didDomain,
            )
          : null,
    );
    final registry = await tenantStore.loadRegistry();
    final effectiveTenant = tenant ?? registry.activeTenant;
    final registeredTenant = registry.tenants.singleWhere(
      (item) =>
          item.tenantProfileId == effectiveTenant.tenantProfileId &&
          item.storageScopeId == effectiveTenant.storageScopeId,
      orElse: () => throw const FormatException('tenant_scope_unregistered'),
    );
    final effectiveEnvironment =
        environment ??
        AwikiEnvironmentConfig(
          baseUrl: registeredTenant.backendBaseUrl,
          didDomain: registeredTenant.didHost,
        );
    final preferenceStorage = await AwikiPerformanceLogger.async(
      'bootstrap.preference_store',
      () => _buildPreferenceStore(appStateRoot: appStateRoot),
    );

    final storageScopeLayout = await tenantStore.layoutForScope(
      registeredTenant.storageScopeId,
    );
    final pathLayout = AwikiImCorePathLayout.fromStorageScope(
      storageScopeLayout,
    );
    final runtime = AwikiImCoreRuntime(
      config: AwikiImCoreEnvironmentConfig.fromAwikiEnvironment(
        effectiveEnvironment,
      ),
      paths: pathLayout,
      scopeId: registeredTenant.storageScopeId,
      vaultSecretProvider: ScopeAwikiImCoreVaultSecretProvider(
        repository: scopeSecretRepository,
      ),
      multiDeviceJoinEnabled: effectiveEnvironment.multiDeviceJoinEnabled,
      multiDeviceRootTransferEnabled:
          effectiveEnvironment.multiDeviceRootTransferEnabled,
      onProgress: (progress) {
        if (progress == AwikiImCoreRuntimeProgress.upgradingLocalState) {
          onProgress?.call(AppBootstrapProgress.upgradingLocalState);
        }
      },
    );
    await runtime.openAndValidate();
    try {
      final productLocalStore = AwikiProductLocalStoreSqlite(
        databasePath: storageScopeLayout.productDatabasePath,
      );
      if (runtime.hasCanonicalOverlayMigrationWork) {
        onProgress?.call(AppBootstrapProgress.migratingLocalOverlays);
      }
      await productLocalStore.migrateCanonicalConversationAliases(
        runtime.localStateUpgradeResult?.aliasMappings.map(
              (mapping) => ProductConversationAliasMigration(
                ownerDid: mapping.ownerDid,
                legacyConversationId: mapping.legacyConversationId,
                canonicalConversationId: mapping.canonicalConversationId,
              ),
            ) ??
            const <ProductConversationAliasMigration>[],
      );
      final activeSessionStore = KeyValueActiveSessionStore(
        storage: preferenceStorage,
        scopeId: registeredTenant.storageScopeId,
      );
      final attachmentCacheService = FileAttachmentCacheService(
        rootDirectory: () async =>
            Directory(storageScopeLayout.attachmentsRoot),
      );

      final identityAdapter = AwikiImCoreIdentityAdapter(runtime: runtime);
      final deviceManagementAdapter =
          effectiveEnvironment.multiDeviceJoinEnabled
          ? AwikiImCoreDeviceManagementAdapter(
              runtime: runtime,
              userServiceUrl: effectiveEnvironment.userServiceUrl,
              targetHandleDomain: effectiveEnvironment.didDomain,
            )
          : null;
      final rootKeyTransferAdapter =
          effectiveEnvironment.multiDeviceRootTransferEnabled
          ? AwikiImCoreRootKeyTransferAdapter(runtime: runtime)
          : null;
      final authAdapter = AwikiImCoreAuthAdapter(runtime: runtime);
      final messageAdapter = AwikiImCoreMessageAdapter(runtime: runtime);
      final messageSyncAdapter = AwikiImCoreMessageSyncAdapter(
        runtime: runtime,
      );
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
      final agentInventoryPort =
          UserServiceAgentInventoryAdapter.fromEnvironment(
            environment: effectiveEnvironment,
          );
      final personalAgentBindingPort = UserServicePersonalAgentBindingAdapter(
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
        personalAgentBindings: personalAgentBindingPort,
        identities: identityAdapter,
        environment: effectiveEnvironment,
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
      final relationshipApplicationService =
          ImCoreRelationshipApplicationService(
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
        deviceManagementCorePort: deviceManagementAdapter,
        rootKeyTransferPort: rootKeyTransferAdapter,
        onboardingService: onboardingService,
        onboardingSupportService: onboardingSupportService,
        messagingService: messagingService,
        messageSyncService: messageSyncService,
        conversationService: conversationService,
        agentInventoryPort: agentInventoryPort,
        personalAgentBindingPort: personalAgentBindingPort,
        agentControlService: agentControlService,
        agentControlStatusStore: agentControlStatusStore,
        groupApplicationService: groupApplicationService,
        profileApplicationService: profileApplicationService,
        directoryApplicationService: directoryApplicationService,
        relationshipApplicationService: relationshipApplicationService,
        realtimeApplicationService: realtimeApplicationService,
        productLocalStore: productLocalStore,
        peerIdentityService: peerIdentityService,
        attachmentCacheService: attachmentCacheService,
        storageScopeLayout: storageScopeLayout,
      );
      onProgress?.call(AppBootstrapProgress.startingApplication);
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'bootstrap.create',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'custom_state_root': appStateRoot?.trim().isNotEmpty == true,
          'storage_scope_bound': true,
        },
      );
      return bootstrap;
    } on Object {
      await runtime.dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[
      if (realtimeApplicationService != null)
        realtimeApplicationService!.stop().catchError((_) {}),
      if (appSessionService is ImCoreAppSessionService)
        (appSessionService! as ImCoreAppSessionService)
            .disposeRuntime()
            .catchError((_) {}),
      if (productLocalStore is AwikiProductLocalStoreSqlite)
        (productLocalStore! as AwikiProductLocalStoreSqlite).close().catchError(
          (_) {},
        ),
    ]);
  }

  @visibleForTesting
  static Future<AppKeyValueStore> buildAccountStoreForTesting() {
    return _buildAccountStore();
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
}

bool _hasStateRoot(String? value) => value != null && value.trim().isNotEmpty;
