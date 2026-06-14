import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../unit_test/test_support.dart';

class FakeAwikiMeAppHarness {
  FakeAwikiMeAppHarness({
    required this.bootstrap,
    required this.gateway,
    required this.realtimeGateway,
    required this.notificationFacade,
    required this.providerOverrides,
  });

  final AppBootstrap bootstrap;
  final FakeAwikiGateway gateway;
  final FakeRealtimeGateway realtimeGateway;
  final FakeNotificationFacade notificationFacade;
  final List<Override> providerOverrides;
}

FakeAwikiMeAppHarness createFakeAwikiMeAppHarness({
  SessionIdentity? session,
  UserProfile? profile,
  AppLocaleMode localeMode = AppLocaleMode.zhHans,
}) {
  final gateway = FakeAwikiGateway()
    ..myProfile = profile ?? _defaultProfile(session)
    ..localCredentials = session == null
        ? const <SessionIdentity>[]
        : <SessionIdentity>[session];
  final realtimeGateway = FakeRealtimeGateway();
  final notificationFacade = FakeNotificationFacade();

  final bootstrap = AppBootstrap(
    accountGateway: gateway,
    gateway: gateway,
    realtimeGateway: realtimeGateway,
    notificationFacade: notificationFacade,
    e2eeFacade: FakeE2eeFacade(),
    localePreferenceService: FakeLocalePreferenceService(
      initialMode: localeMode,
    ),
    updateService: FakeUpdateService(),
    appSessionService: FakeAppSessionService(gateway),
    identityCorePort: FakeIdentityCorePort(),
    onboardingService: FakeOnboardingService(gateway),
    onboardingSupportService: FakeOnboardingSupportService(gateway),
    messagingService: FakeMessagingService(gateway),
    conversationService: FakeConversationService(gateway),
    agentInventoryPort: FakeAgentInventoryPort(),
    agentControlService: FakeAgentControlService(),
    groupApplicationService: FakeGroupApplicationService(gateway),
    profileApplicationService: FakeProfileApplicationService(gateway),
    peerIdentityService: FakePeerIdentityService(),
    directoryApplicationService: const FakeDirectoryApplicationService(),
    relationshipApplicationService: FakeRelationshipApplicationService(gateway),
    realtimeApplicationService: FakeRealtimeApplicationService(
      gateway: gateway,
      realtimeGateway: realtimeGateway,
    ),
    productLocalStore: FakeProductLocalStore(),
  );

  return FakeAwikiMeAppHarness(
    bootstrap: bootstrap,
    gateway: gateway,
    realtimeGateway: realtimeGateway,
    notificationFacade: notificationFacade,
    providerOverrides: <Override>[
      appLocaleModeProvider.overrideWith((ref) => localeMode),
      profileHomepageResolverProvider.overrideWithValue(
        ProfileHomepageResolver(
          environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
        ),
      ),
      homepageMarkdownLoaderProvider.overrideWithValue((_) async => null),
      attachmentPickerServiceProvider.overrideWithValue(
        FakeAttachmentPickerService(),
      ),
      if (session != null)
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller
            ..setSession(session)
            ..setLocalCredentials(<SessionIdentity>[session]);
          return controller;
        }),
      profileProvider.overrideWith((ref) {
        return TestProfileController(
          ref,
          initialProfile: gateway.myProfile,
        );
      }),
    ],
  );
}

class FakeDirectoryApplicationService implements DirectoryApplicationService {
  const FakeDirectoryApplicationService();

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) async {
    final normalized = handle.trim().toLowerCase();
    return DirectoryPeerResolution(
      input: handle,
      did: 'did:test:$normalized',
      handle: normalized,
    );
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) async {
    final normalized = peer.trim();
    return DirectoryPeerResolution(
      input: peer,
      did: normalized.startsWith('did:') ? normalized : 'did:test:$normalized',
      handle: normalized.startsWith('did:') ? null : normalized,
    );
  }
}

UserProfile _defaultProfile(SessionIdentity? session) {
  return UserProfile(
    did: session?.did ?? 'did:test:me',
    nickName: session?.displayName ?? 'Me',
    handle: session?.handle ?? 'me',
    bio: 'AWiki Me smoke test profile',
    tags: const <String>['smoke'],
    profileMarkdown: '# AWiki Me\n\nSmoke test profile.',
  );
}
