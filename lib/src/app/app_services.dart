import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/locale_preference_service.dart';
import '../domain/repositories/awiki_account_gateway.dart';
import '../domain/repositories/awiki_gateway.dart';
import '../domain/services/e2ee_facade.dart';
import '../domain/services/notification_facade.dart';
import '../domain/services/realtime_gateway.dart';
import '../domain/services/update_service.dart';

final awikiGatewayProvider = Provider<AwikiGateway>(
  (ref) => throw UnimplementedError('awikiGatewayProvider must be overridden'),
);

final awikiAccountGatewayProvider = Provider<AwikiAccountGateway>(
  (ref) => throw UnimplementedError(
    'awikiAccountGatewayProvider must be overridden',
  ),
);

final realtimeGatewayProvider = Provider<RealtimeGateway>(
  (ref) =>
      throw UnimplementedError('realtimeGatewayProvider must be overridden'),
);

final realtimeConnectionStatusProvider =
    StreamProvider<RealtimeConnectionStatus>((ref) {
      final gateway = ref.watch(realtimeGatewayProvider);
      return gateway.connectionStatusStream;
    });

final notificationFacadeProvider = Provider<NotificationFacade>(
  (ref) =>
      throw UnimplementedError('notificationFacadeProvider must be overridden'),
);

final e2eeFacadeProvider = Provider<E2eeFacade>(
  (ref) => throw UnimplementedError('e2eeFacadeProvider must be overridden'),
);

final localePreferenceServiceProvider = Provider<LocalePreferenceService>(
  (ref) => throw UnimplementedError(
    'localePreferenceServiceProvider must be overridden',
  ),
);

final updateServiceProvider = Provider<UpdateService>(
  (ref) => throw UnimplementedError('updateServiceProvider must be overridden'),
);
