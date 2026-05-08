import 'dart:io';

import '../data/gateways/awiki_anp_gateway.dart';
import '../data/services/awiki_account_service.dart';
import '../data/services/awiki_local_cache.dart';
import '../data/services/awiki_ws_realtime_gateway.dart';
import '../data/services/app_key_value_store.dart';
import '../data/services/app_notification_facade.dart';
import '../data/services/app_update_service.dart';
import '../data/services/dart_did_registration_facade.dart';
import '../data/services/locale_preference_service.dart';
import '../data/services/method_channel_document_picker_service.dart';
import '../domain/repositories/awiki_account_gateway.dart';
import '../data/services/noop_e2ee_facade.dart';
import '../domain/services/did_registration_facade.dart';
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
  });

  final AwikiAccountGateway accountGateway;
  final AwikiGateway gateway;
  final RealtimeGateway realtimeGateway;
  final NotificationFacade notificationFacade;
  final E2eeFacade e2eeFacade;
  final LocalePreferenceService localePreferenceService;
  final UpdateService updateService;

  static Future<AppBootstrap> create() async {
    final didRegistrationFacade = _buildDidRegistrationFacade();
    final accountStorage = SecureAppKeyValueStore();
    final preferenceStorage = await _buildPreferenceStore();
    final documentPickerService = MethodChannelDocumentPickerService();
    final accountGateway = AwikiAccountService.fromEnvironment(
      storage: accountStorage,
      didRegistrationFacade: didRegistrationFacade,
      documentPickerService: documentPickerService,
    );
    final gateway = AwikiAnpGateway.fromEnvironment(
      accountGateway: accountGateway,
      localCache: AwikiLocalCache(),
    );
    final realtimeGateway = AwikiWsRealtimeGateway();
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
    );
  }

  static DidRegistrationFacade _buildDidRegistrationFacade() {
    return DartDidRegistrationFacade();
  }

  static Future<AppKeyValueStore> _buildPreferenceStore() async {
    if (Platform.isMacOS) {
      // macOS debug builds are not consistently signed for Keychain access.
      return FileAppKeyValueStore.create();
    }
    return SecureAppKeyValueStore();
  }
}
