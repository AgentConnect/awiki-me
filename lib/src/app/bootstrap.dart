import 'dart:io';

import 'package:flutter/foundation.dart';

import '../application/app_session_service.dart';
import '../application/conversation_service.dart';
import '../application/directory_application_service.dart';
import '../application/group_application_service.dart';
import '../application/messaging_service.dart';
import '../application/onboarding_service.dart';
import '../application/onboarding_support_service.dart';
import '../application/product_local_store.dart';
import '../application/profile_application_service.dart';
import '../application/realtime_application_service.dart';
import '../application/relationship_application_service.dart';
import '../data/compat/compat_awiki_account_gateway.dart';
import '../data/compat/compat_awiki_gateway.dart';
import '../data/compat/compat_realtime_gateway.dart';
import '../data/im_core/awiki_im_core_auth_adapter.dart';
import '../data/im_core/awiki_im_core_config.dart';
import '../data/im_core/awiki_im_core_conversation_adapter.dart';
import '../data/im_core/awiki_im_core_directory_adapter.dart';
import '../data/im_core/awiki_im_core_group_adapter.dart';
import '../data/im_core/awiki_im_core_identity_adapter.dart';
import '../data/im_core/awiki_im_core_message_adapter.dart';
import '../data/im_core/awiki_im_core_paths.dart';
import '../data/im_core/awiki_im_core_profile_adapter.dart';
import '../data/im_core/awiki_im_core_realtime_adapter.dart';
import '../data/im_core/awiki_im_core_relationship_adapter.dart';
import '../data/im_core/awiki_im_core_runtime.dart';
import '../data/local/awiki_product_local_store_sqlite.dart';
import '../data/services/app_key_value_store.dart';
import '../data/services/app_notification_facade.dart';
import '../data/services/app_update_service.dart';
import '../data/services/awiki_onboarding_support_service.dart';
import '../data/services/locale_preference_service.dart';
import '../domain/repositories/awiki_account_gateway.dart';
import '../data/services/noop_e2ee_facade.dart';
import '../domain/repositories/awiki_gateway.dart';
import '../domain/services/e2ee_facade.dart';
import '../domain/services/notification_facade.dart';
import '../domain/services/realtime_gateway.dart';
import '../domain/services/update_service.dart';

class AppBootstrap {
  AppBootstrap({
    required this.accountGateway,
    required this.gateway,
    required this.realtimeGateway,
    required this.notificationFacade,
    required this.e2eeFacade,
    required this.localePreferenceService,
    required this.updateService,
    this.appSessionService,
    this.onboardingService,
    this.onboardingSupportService,
    this.messagingService,
    this.conversationService,
    this.groupApplicationService,
    this.profileApplicationService,
    this.directoryApplicationService,
    this.relationshipApplicationService,
    this.realtimeApplicationService,
    this.productLocalStore,
  });

  final AwikiAccountGateway accountGateway;
  final AwikiGateway gateway;
  final RealtimeGateway realtimeGateway;
  final NotificationFacade notificationFacade;
  final E2eeFacade e2eeFacade;
  final LocalePreferenceService localePreferenceService;
  final UpdateService updateService;
  final AppSessionService? appSessionService;
  final OnboardingService? onboardingService;
  final OnboardingSupportService? onboardingSupportService;
  final MessagingService? messagingService;
  final ConversationService? conversationService;
  final GroupApplicationService? groupApplicationService;
  final ProfileApplicationService? profileApplicationService;
  final DirectoryApplicationService? directoryApplicationService;
  final RelationshipApplicationService? relationshipApplicationService;
  final RealtimeApplicationService? realtimeApplicationService;
  final ProductLocalStore? productLocalStore;

  static Future<AppBootstrap> create() async {
    final preferenceStorage = await _buildPreferenceStore();

    final runtime = AwikiImCoreRuntime(
      config: AwikiImCoreEnvironmentConfig.fromEnvironment(),
      paths: await AwikiImCorePathLayout.fromPlatform(),
    );
    final productLocalStore = AwikiProductLocalStoreSqlite();

    final identityAdapter = AwikiImCoreIdentityAdapter(runtime: runtime);
    final authAdapter = AwikiImCoreAuthAdapter(runtime: runtime);
    final messageAdapter = AwikiImCoreMessageAdapter(runtime: runtime);
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
    final conversationService = ImCoreConversationService(
      conversations: conversationAdapter,
      localStore: productLocalStore,
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
      realtime: realtimeAdapter,
    );
    final onboardingService = ImCoreOnboardingService(
      identities: identityAdapter,
      sessions: appSessionService,
      profiles: profileAdapter,
    );
    final onboardingSupportService =
        AwikiOnboardingSupportService.fromEnvironment();

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
    return AppBootstrap(
      accountGateway: accountGateway,
      gateway: gateway,
      realtimeGateway: realtimeGateway,
      notificationFacade: notificationFacade,
      e2eeFacade: e2eeFacade,
      localePreferenceService: localePreferenceService,
      updateService: updateService,
      appSessionService: appSessionService,
      onboardingService: onboardingService,
      onboardingSupportService: onboardingSupportService,
      messagingService: messagingService,
      conversationService: conversationService,
      groupApplicationService: groupApplicationService,
      profileApplicationService: profileApplicationService,
      directoryApplicationService: directoryApplicationService,
      relationshipApplicationService: relationshipApplicationService,
      realtimeApplicationService: realtimeApplicationService,
      productLocalStore: productLocalStore,
    );
  }

  @visibleForTesting
  static Future<AppKeyValueStore> buildAccountStoreForTesting() {
    return _buildAccountStore();
  }

  static Future<AppKeyValueStore> _buildAccountStore() async {
    if (Platform.isMacOS && !kReleaseMode) {
      // Local macOS debug/profile builds are usually ad-hoc signed, and
      // Keychain writes can fail after a successful backend registration.
      return FileAppKeyValueStore.create(fileName: 'awiki_me_credentials.json');
    }
    return SecureAppKeyValueStore();
  }

  static Future<AppKeyValueStore> _buildPreferenceStore() async {
    if (Platform.isMacOS) {
      // macOS debug builds are not consistently signed for Keychain access.
      return FileAppKeyValueStore.create();
    }
    return SecureAppKeyValueStore();
  }
}
