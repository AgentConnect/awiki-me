import 'dart:io';

import '../data/gateways/awiki_rpc_gateway.dart';
import '../data/services/awiki_local_cache.dart';
import '../data/services/awiki_ws_realtime_gateway.dart';
import '../data/services/app_notification_facade.dart';
import '../data/services/dart_did_registration_facade.dart';
import '../data/services/locale_preference_service.dart';
import '../data/services/method_channel_document_picker_service.dart';
import '../data/services/method_channel_did_registration_facade.dart';
import '../data/services/noop_did_registration_facade.dart';
import '../data/services/noop_e2ee_facade.dart';
import '../domain/services/did_registration_facade.dart';
import '../domain/repositories/awiki_gateway.dart';
import '../domain/services/e2ee_facade.dart';
import '../domain/services/notification_facade.dart';
import '../domain/services/realtime_gateway.dart';

class AppBootstrap {
  AppBootstrap({
    required this.gateway,
    required this.realtimeGateway,
    required this.notificationFacade,
    required this.e2eeFacade,
    required this.localePreferenceService,
  });

  final AwikiGateway gateway;
  final RealtimeGateway realtimeGateway;
  final NotificationFacade notificationFacade;
  final E2eeFacade e2eeFacade;
  final LocalePreferenceService localePreferenceService;

  static Future<AppBootstrap> create() async {
    final didRegistrationFacade = _buildDidRegistrationFacade();
    final gateway = AwikiRpcGateway.fromEnvironment(
      localCache: AwikiLocalCache(),
      didRegistrationFacade: didRegistrationFacade,
      documentPickerService: MethodChannelDocumentPickerService(),
    );
    final realtimeGateway = AwikiWsRealtimeGateway();
    final notificationFacade = AppNotificationFacade();
    final e2eeFacade = NoopE2eeFacade();
    final localePreferenceService = LocalePreferenceService();
    return AppBootstrap(
      gateway: gateway,
      realtimeGateway: realtimeGateway,
      notificationFacade: notificationFacade,
      e2eeFacade: e2eeFacade,
      localePreferenceService: localePreferenceService,
    );
  }

  static DidRegistrationFacade _buildDidRegistrationFacade() {
    if (Platform.isAndroid) {
      return MethodChannelDidRegistrationFacade();
    }
    if (Platform.isIOS) {
      return DartDidRegistrationFacade();
    }
    return NoopDidRegistrationFacade();
  }
}
