import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../data/services/locale_preference_service.dart';
import '../domain/entities/realtime_update.dart';
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
      final realtime = ref.watch(realtimeApplicationServiceProvider);
      return realtime.connectionStates;
    });

final realtimeUpdatesProvider = StreamProvider<RealtimeUpdate>((ref) {
  final realtime = ref.watch(realtimeApplicationServiceProvider);
  return realtime.updates;
});

final appSessionServiceProvider = Provider<AppSessionService>(
  (ref) =>
      throw UnimplementedError('appSessionServiceProvider must be overridden'),
);

final onboardingServiceProvider = Provider<OnboardingService>(
  (ref) =>
      throw UnimplementedError('onboardingServiceProvider must be overridden'),
);

final onboardingSupportServiceProvider = Provider<OnboardingSupportService>(
  (ref) => throw UnimplementedError(
    'onboardingSupportServiceProvider must be overridden',
  ),
);

final messagingServiceProvider = Provider<MessagingService>(
  (ref) =>
      throw UnimplementedError('messagingServiceProvider must be overridden'),
);

final conversationServiceProvider = Provider<ConversationService>(
  (ref) => throw UnimplementedError(
    'conversationServiceProvider must be overridden',
  ),
);

final groupApplicationServiceProvider = Provider<GroupApplicationService>(
  (ref) => throw UnimplementedError(
    'groupApplicationServiceProvider must be overridden',
  ),
);

final profileApplicationServiceProvider = Provider<ProfileApplicationService>(
  (ref) => throw UnimplementedError(
    'profileApplicationServiceProvider must be overridden',
  ),
);

final directoryApplicationServiceProvider =
    Provider<DirectoryApplicationService>(
      (ref) => throw UnimplementedError(
        'directoryApplicationServiceProvider must be overridden',
      ),
    );

final relationshipApplicationServiceProvider =
    Provider<RelationshipApplicationService>(
      (ref) => throw UnimplementedError(
        'relationshipApplicationServiceProvider must be overridden',
      ),
    );

final realtimeApplicationServiceProvider = Provider<RealtimeApplicationService>(
  (ref) => throw UnimplementedError(
    'realtimeApplicationServiceProvider must be overridden',
  ),
);

final productLocalStoreProvider = Provider<ProductLocalStore>(
  (ref) =>
      throw UnimplementedError('productLocalStoreProvider must be overridden'),
);

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
