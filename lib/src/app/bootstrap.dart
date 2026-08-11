// [INPUT]: Tenant scope, environment gates, platform secret storage, and native IM Core.
// [OUTPUT]: Fully composed AWiki Me adapters/services for one immutable storage scope.
// [POS]: Production composition root; device secrets remain owned by Vault-backed IM Core.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../application/config/awiki_client_version.dart';
import '../application/config/awiki_environment_config.dart';
import '../application/attachment_cache_service.dart';
import '../application/desktop_shell_service.dart';
import '../application/agent/agent_control_service.dart';
import '../application/agent/agent_control_status_store.dart';
import '../application/auth/auth_session_coordinator.dart';
import '../application/app_bootstrap_epoch_barrier.dart';
import '../application/app_session_service.dart';
import '../application/conversation_service.dart';
import '../application/directory_application_service.dart';
import '../application/display_scale_preference_service.dart';
import '../application/group_application_service.dart';
import '../application/messaging_service.dart';
import '../application/message_sync_service.dart';
import '../application/models/product_local_models.dart';
import '../application/onboarding_service.dart';
import '../application/onboarding_support_service.dart';
import '../application/peer_identity_service.dart';
import '../application/ports/agent_inventory_port.dart';
import '../application/ports/account_state_sync_port.dart';
import '../application/ports/agent_notification_preference_port.dart';
import '../application/ports/device_management_core_port.dart';
import '../application/ports/group_encryption_core_port.dart';
import '../application/ports/handle_recovery_core_port.dart';
import '../application/ports/identity_core_port.dart';
import '../application/ports/legacy_registry_epoch_adoption_port.dart';
import '../application/ports/personal_agent_binding_port.dart';
import '../application/ports/root_key_transfer_port.dart';
import '../application/product_local_store.dart';
import '../application/profile_application_service.dart';
import '../application/realtime_application_service.dart';
import '../application/relationship_application_service.dart';
import '../application/remote_push_installation_coordinator.dart';
import '../application/sms_otp_cooldown_service.dart';
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
import '../data/im_core/awiki_im_core_group_encryption_adapter.dart';
import '../data/im_core/awiki_im_core_handle_recovery_adapter.dart';
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
import '../data/services/authenticated_user_service_rpc_client.dart';
import '../data/services/awiki_onboarding_support_service.dart';
import '../data/services/awiki_onboarding_utility_client.dart';
import '../data/services/user_service_account_state_sync_adapter.dart';
import '../data/services/key_value_active_session_store.dart';
import '../data/services/key_value_display_scale_preference_service.dart';
import '../data/services/key_value_sms_otp_cooldown_service.dart';
import '../data/services/file_attachment_cache_service.dart';
import '../data/services/locale_preference_service.dart';
import '../data/services/user_service_peer_identity_service.dart';
import '../data/push/user_service_push_installation_adapter.dart';
import '../domain/repositories/awiki_account_gateway.dart';
import '../data/services/noop_e2ee_facade.dart';
import '../domain/repositories/awiki_gateway.dart';
import '../domain/services/e2ee_facade.dart';
import '../domain/services/notification_facade.dart';
import '../domain/services/remote_push_client.dart';
import '../domain/services/realtime_gateway.dart';
import '../domain/services/update_service.dart';
import '../core/performance_logger.dart';
import '../application/tenant/app_tenant.dart';
import '../data/storage/awiki_storage_scope_layout.dart';
import '../data/storage/scope_secret_repository_factory.dart';
import '../data/tenant/app_tenant_store.dart';
import 'macos_notification_smoke.dart';

enum AppBootstrapProgress {
  preparing,
  upgradingLocalState,
  migratingLocalOverlays,
  startingApplication,
}

const String awikiMeReleaseLine = String.fromEnvironment(
  'AWIKI_RELEASE',
  defaultValue: '0714',
);

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
    this.tenantRegistry,
    this.displayScalePreferenceService =
        const NoopDisplayScalePreferenceService(),
    this.smsOtpCooldownService = const NoopSmsOtpCooldownService(),
    this.desktopShellService = const NoopDesktopShellService(),
    this.appSessionService,
    this.identityCorePort,
    this.deviceManagementCorePort,
    this.rootKeyTransferPort,
    this.groupEncryptionCorePort,
    this.handleRecoveryCorePort,
    this.legacyRegistryEpochAdoptionPort,
    this.onboardingService,
    this.onboardingSupportService,
    this.messagingService,
    this.messageSyncService,
    this.conversationService,
    this.agentInventoryPort,
    this.accountStateSyncPort,
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
    this.userServiceHttpClient,
    this.storageScopeLayout,
    this.remotePushClient,
    this.remotePushInstallationCoordinator,
    this.agentNotificationPreferencePort,
    this.remotePushDisposeTimeout = const Duration(seconds: 3),
    this.disposeNotificationFacade = true,
  });

  final AwikiEnvironmentConfig environment;
  final AwikiAccountGateway accountGateway;
  final AwikiGateway gateway;
  final RealtimeGateway realtimeGateway;
  final NotificationFacade notificationFacade;
  final E2eeFacade e2eeFacade;
  final LocalePreferenceService localePreferenceService;
  final UpdateService updateService;
  final AppTenantRegistry? tenantRegistry;
  final DisplayScalePreferenceService displayScalePreferenceService;
  final SmsOtpCooldownService smsOtpCooldownService;
  final DesktopShellService desktopShellService;
  final AppSessionService? appSessionService;
  final IdentityCorePort? identityCorePort;
  final DeviceManagementCorePort? deviceManagementCorePort;
  final RootKeyTransferPort? rootKeyTransferPort;
  final GroupEncryptionCorePort? groupEncryptionCorePort;
  final HandleRecoveryCorePort? handleRecoveryCorePort;
  final LegacyRegistryEpochAdoptionPort? legacyRegistryEpochAdoptionPort;
  final OnboardingService? onboardingService;
  final OnboardingSupportService? onboardingSupportService;
  final MessagingService? messagingService;
  final MessageSyncService? messageSyncService;
  final ConversationService? conversationService;
  final AgentInventoryPort? agentInventoryPort;
  final AccountStateSyncPort? accountStateSyncPort;
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
  final AwikiOnboardingUtilityHttpClient? userServiceHttpClient;
  final AwikiStorageScopeLayout? storageScopeLayout;
  final RemotePushClient? remotePushClient;
  final RemotePushInstallationCoordinator? remotePushInstallationCoordinator;
  final AgentNotificationPreferencePort? agentNotificationPreferencePort;
  final Duration remotePushDisposeTimeout;
  final bool disposeNotificationFacade;
  Future<void>? _disposeOperation;

  static Future<AppBootstrap> create({
    AwikiEnvironmentConfig? environment,
    String? appStateRoot,
    AppTenantProfile? tenant,
    DesktopShellService? desktopShellService,
    NotificationFacade? notificationFacade,
    RemotePushClient? remotePushClient,
    @visibleForTesting
    Future<AppBootstrap> Function()? createCoreBootstrapForTesting,
    @visibleForTesting
    AwikiOnboardingUtilityHttpClient? remotePushHttpClientForTesting,
    void Function(AppBootstrapProgress progress)? onProgress,
  }) async {
    final coreBootstrapFactory = createCoreBootstrapForTesting;
    if (coreBootstrapFactory != null) {
      final coreBootstrap = await coreBootstrapFactory();
      return _composeRemotePush(
        coreBootstrap,
        remotePushClient: remotePushClient,
        httpClient: remotePushHttpClientForTesting,
      );
    }
    final totalWatch = Stopwatch()..start();
    final shell = desktopShellService ?? const NoopDesktopShellService();
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
      platformStorageRoots: shell.getStorageRoots,
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
    final clientVersion = await _loadAwikiMeClientVersion();
    final userServiceHttpClient = AwikiOnboardingUtilityHttpClient(
      baseUrl: effectiveEnvironment.userServiceUrl,
      clientVersionHeader: clientVersion.headerValue,
    );
    final userServiceUtilityClient = AwikiOnboardingUtilityClient(
      serviceClient: userServiceHttpClient,
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
        clientVersionInfo: clientVersion,
      ),
      paths: pathLayout,
      scopeId: registeredTenant.storageScopeId,
      vaultSecretProvider: ScopeAwikiImCoreVaultSecretProvider(
        repository: scopeSecretRepository,
      ),
      multiDeviceDeviceRevokeEnabled:
          effectiveEnvironment.multiDeviceDeviceRevokeEnabled,
      multiDeviceDirectE2eeEnabled:
          effectiveEnvironment.multiDeviceDirectE2eeEnabled,
      multiDeviceGroupE2eeEnabled:
          effectiveEnvironment.multiDeviceGroupE2eeEnabled,
      multiDeviceAudience: effectiveEnvironment.multiDeviceAudience,
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
      final deviceManagementAdapter = AwikiImCoreDeviceManagementAdapter(
        runtime: runtime,
        userServiceUrl: effectiveEnvironment.userServiceUrl,
        targetHandleDomain: effectiveEnvironment.didDomain,
        userServiceClient: userServiceHttpClient,
      );
      final rootKeyTransferAdapter = AwikiImCoreRootKeyTransferAdapter(
        runtime: runtime,
      );
      final handleRecoveryAdapter = AwikiImCoreHandleRecoveryAdapter(
        runtime: runtime,
      );
      final authAdapter = AwikiImCoreAuthAdapter(runtime: runtime);
      final messageAdapter = AwikiImCoreMessageAdapter(runtime: runtime);
      final messageSyncAdapter = AwikiImCoreMessageSyncAdapter(
        runtime: runtime,
        syncV2ReadEnabled: effectiveEnvironment.messageSyncV2ReadEnabled,
      );
      final conversationAdapter = AwikiImCoreConversationAdapter(
        runtime: runtime,
      );
      final groupAdapter = AwikiImCoreGroupAdapter(runtime: runtime);
      final groupEncryptionAdapter =
          effectiveEnvironment.multiDeviceGroupE2eeEnabled
          ? AwikiImCoreGroupEncryptionAdapter(runtime: runtime)
          : null;
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
            client: userServiceHttpClient,
          );
      final accountStateSyncPort =
          UserServiceAccountStateSyncAdapter.fromEnvironment(
            environment: effectiveEnvironment,
            client: userServiceHttpClient,
          );
      final personalAgentBindingPort = UserServicePersonalAgentBindingAdapter(
        userServiceUrl: effectiveEnvironment.userServiceUrl,
        client: userServiceHttpClient,
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
        legacyUpgrades: identityAdapter,
        activeSessionStore: activeSessionStore,
        expectedDidDomain: effectiveEnvironment.didDomain,
        realtime: realtimeAdapter,
        bootstrapEpochBarrier: AppBootstrapEpochBarrier(
          recovery: handleRecoveryAdapter,
          local: productLocalStore,
        ),
      );
      final onboardingService = ImCoreOnboardingService(
        identities: identityAdapter,
        legacyUpgrades: identityAdapter,
        sessions: appSessionService,
        profiles: profileAdapter,
      );
      final onboardingSupportService = AwikiOnboardingSupportService(
        userServiceUrl: effectiveEnvironment.userServiceUrl,
        userClient: userServiceUtilityClient,
      );
      final peerIdentityService = UserServicePeerIdentityService(
        userServiceUrl: effectiveEnvironment.userServiceUrl,
        userClient: userServiceUtilityClient,
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

      final effectiveNotificationFacade =
          notificationFacade ??
          await AppNotificationFacade.create(desktopShell: shell);
      unawaited(
        runMacosNotificationSmoke(
          notificationFacade: effectiveNotificationFacade,
          enabled: const bool.fromEnvironment('AWIKI_MACOS_NOTIFICATION_SMOKE'),
          isMacOS: Platform.isMacOS,
          isReleaseMode: kReleaseMode,
          delay: const Duration(seconds: 8),
        ),
      );
      final e2eeFacade = NoopE2eeFacade();
      final localePreferenceService = LocalePreferenceService(
        storage: preferenceStorage,
      );
      final displayScalePreferenceService =
          KeyValueDisplayScalePreferenceService(storage: preferenceStorage);
      final smsOtpCooldownService = KeyValueSmsOtpCooldownService(
        storage: preferenceStorage,
        scopeId: registeredTenant.storageScopeId.value,
      );
      final updateService = AppUpdateService(storage: preferenceStorage);
      final bootstrap = AppBootstrap(
        environment: effectiveEnvironment,
        accountGateway: accountGateway,
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        notificationFacade: effectiveNotificationFacade,
        e2eeFacade: e2eeFacade,
        localePreferenceService: localePreferenceService,
        displayScalePreferenceService: displayScalePreferenceService,
        smsOtpCooldownService: smsOtpCooldownService,
        updateService: updateService,
        tenantRegistry: registry,
        desktopShellService: shell,
        appSessionService: appSessionService,
        identityCorePort: identityAdapter,
        deviceManagementCorePort: deviceManagementAdapter,
        rootKeyTransferPort: rootKeyTransferAdapter,
        groupEncryptionCorePort: groupEncryptionAdapter,
        handleRecoveryCorePort: handleRecoveryAdapter,
        legacyRegistryEpochAdoptionPort: handleRecoveryAdapter,
        onboardingService: onboardingService,
        onboardingSupportService: onboardingSupportService,
        messagingService: messagingService,
        messageSyncService: messageSyncService,
        conversationService: conversationService,
        agentInventoryPort: agentInventoryPort,
        accountStateSyncPort: accountStateSyncPort,
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
        userServiceHttpClient: userServiceHttpClient,
        storageScopeLayout: storageScopeLayout,
        disposeNotificationFacade: notificationFacade == null,
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
      return _composeRemotePush(
        bootstrap,
        remotePushClient: remotePushClient,
        httpClient: remotePushHttpClientForTesting,
      );
    } on Object {
      await runtime.dispose();
      rethrow;
    }
  }

  static AppBootstrap _composeRemotePush(
    AppBootstrap coreBootstrap, {
    required RemotePushClient? remotePushClient,
    AwikiOnboardingUtilityHttpClient? httpClient,
  }) {
    if (remotePushClient == null) {
      return coreBootstrap;
    }
    final sessions = coreBootstrap.appSessionService;
    if (sessions == null) {
      throw StateError('remote_push_app_session_service_required');
    }
    final pushHttpClient =
        httpClient ??
        coreBootstrap.userServiceHttpClient ??
        AwikiOnboardingUtilityHttpClient(
          baseUrl: coreBootstrap.environment.userServiceUrl,
        );
    final pushAuthenticatedClient = AuthenticatedUserServiceRpcClient(
      client: pushHttpClient,
      sessions: AuthSessionCoordinator(sessions: sessions),
    );
    final pushInstallations = UserServicePushInstallationAdapter(
      userServiceUrl: coreBootstrap.environment.userServiceUrl,
      client: pushHttpClient,
      authenticatedClient: pushAuthenticatedClient,
    );
    return coreBootstrap._copyWithRemotePush(
      client: remotePushClient,
      coordinator: RemotePushInstallationCoordinator(
        client: remotePushClient,
        installations: pushInstallations,
      ),
      agentNotificationPreferencePort: pushInstallations,
    );
  }

  AppBootstrap _copyWithRemotePush({
    required RemotePushClient client,
    required RemotePushInstallationCoordinator coordinator,
    required AgentNotificationPreferencePort agentNotificationPreferencePort,
  }) {
    return AppBootstrap(
      environment: environment,
      accountGateway: accountGateway,
      gateway: gateway,
      realtimeGateway: realtimeGateway,
      notificationFacade: notificationFacade,
      e2eeFacade: e2eeFacade,
      localePreferenceService: localePreferenceService,
      displayScalePreferenceService: displayScalePreferenceService,
      smsOtpCooldownService: smsOtpCooldownService,
      updateService: updateService,
      tenantRegistry: tenantRegistry,
      desktopShellService: desktopShellService,
      appSessionService: appSessionService,
      identityCorePort: identityCorePort,
      deviceManagementCorePort: deviceManagementCorePort,
      rootKeyTransferPort: rootKeyTransferPort,
      groupEncryptionCorePort: groupEncryptionCorePort,
      handleRecoveryCorePort: handleRecoveryCorePort,
      legacyRegistryEpochAdoptionPort: legacyRegistryEpochAdoptionPort,
      onboardingService: onboardingService,
      onboardingSupportService: onboardingSupportService,
      messagingService: messagingService,
      messageSyncService: messageSyncService,
      conversationService: conversationService,
      agentInventoryPort: agentInventoryPort,
      accountStateSyncPort: accountStateSyncPort,
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
      userServiceHttpClient: userServiceHttpClient,
      storageScopeLayout: storageScopeLayout,
      remotePushClient: client,
      remotePushInstallationCoordinator: coordinator,
      agentNotificationPreferencePort: agentNotificationPreferencePort,
      remotePushDisposeTimeout: remotePushDisposeTimeout,
      disposeNotificationFacade: disposeNotificationFacade,
    );
  }

  Future<void> dispose() {
    return _disposeOperation ??= _disposeResources();
  }

  Future<void> _disposeResources() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> disposeStep(Future<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    final pushInstallations = remotePushInstallationCoordinator;
    if (pushInstallations != null) {
      try {
        await pushInstallations.disableCurrentInstallation().timeout(
          remotePushDisposeTimeout,
        );
      } catch (_) {
        // Push registration is best-effort and must not block Core teardown.
      }
    }
    final sessions = appSessionService;
    if (sessions is ImCoreAppSessionService) {
      await disposeStep(sessions.disposeRuntime);
    } else {
      final realtime = realtimeApplicationService;
      if (realtime != null) {
        await disposeStep(realtime.stop);
      }
    }
    final localStore = productLocalStore;
    if (localStore is AwikiProductLocalStoreSqlite) {
      await disposeStep(localStore.close);
    }
    if (disposeNotificationFacade) {
      await disposeStep(notificationFacade.dispose);
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
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

Future<AwikiClientVersion> _loadAwikiMeClientVersion() async {
  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version.trim();
  final build = int.tryParse(packageInfo.buildNumber);
  if (version.isEmpty || build == null || build <= 0) {
    throw const FormatException('app_package_version_invalid');
  }
  return AwikiClientVersion(
    product: 'awiki-me',
    release: awikiMeReleaseLine,
    version: version,
    build: build,
  );
}
