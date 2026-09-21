import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/devices/identity_services_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'devices/device_test_support.dart';
import 'test_support.dart';

const _webDid = 'did:web:identity.example:awiki:web:alice';
const _webSession = SessionIdentity(
  did: _webDid,
  credentialName: 'alice',
  displayName: 'Alice',
  handle: 'alice.awiki.ai',
);
const _pending = PendingIdentityRegistration(
  did: _webDid,
  fullHandle: 'alice.awiki.ai',
  method: IdentityDidMethod.web,
  displayName: 'Alice',
  verificationKind: 'phone',
  phase: 'prepared',
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('Web method uses the existing onboarding form on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        tester.view.physicalSize = platform == TargetPlatform.macOS
            ? const Size(1200, 900)
            : const Size(440, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const OnboardingPage(),
            providerOverrides: [
              identityCorePortProvider.overrideWithValue(
                FakeIdentityCorePort(
                  creationMethods: const [
                    IdentityDidMethod.wba,
                    IdentityDidMethod.web,
                  ],
                ),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(OnboardingPage)),
        );
        expect(
          container.read(onboardingProvider).didMethod,
          IdentityDidMethod.wba,
        );
        expect(find.byKey(const Key('identity-method-picker')), findsOneWidget);
        await tester.tap(find.byKey(const Key('identity-method-web')));
        await tester.pumpAndSettle();
        expect(
          container.read(onboardingProvider).didMethod,
          IdentityDidMethod.web,
        );
        expect(
          find.byKey(const Key('identity-web-admin-limitation')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('onboarding-continue-recovery')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets(
    'pending registration survives page replacement with creation closed',
    (tester) async {
      final identities = FakeIdentityCorePort(
        creationMethods: const [IdentityDidMethod.wba],
        pendingRegistrations: const [_pending],
      );
      Future<void> open() async {
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const OnboardingPage(),
            providerOverrides: [
              identityCorePortProvider.overrideWithValue(identities),
            ],
          ),
        );
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.byKey(const Key('identity-method-web')), findsNothing);
      final button = find.byKey(
        const Key('identity-registration-pending-alice.awiki.ai'),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      var container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      expect(
        container.read(onboardingProvider).selectedPendingRegistration?.did,
        _webDid,
      );
      expect(
        container.read(onboardingProvider).canRegisterSelectedDidMethod,
        isTrue,
      );
      expect(
        find.byKey(const Key('identity-registration-resume-hint')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await open();
      container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      expect(
        container.read(onboardingProvider).pendingRegistrations.single.did,
        _webDid,
      );
      expect(
        container.read(onboardingProvider).selectedPendingRegistration,
        isNull,
      );
      expect(button, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Web service update preserves protected entries and resumes after reopening',
    (tester) async {
      final documents = _Documents();
      await tester.pumpWidget(_deviceApp(documents));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('devices-web-admin-limitation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('root-transfer-grant-management')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('identity-services-open')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('identity-service-edit-$_webDid#website')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('identity-service-endpoint')),
        'https://public.example/new',
      );
      await tester.tap(find.byKey(const Key('identity-service-save')));
      await tester.pumpAndSettle();
      expect(documents.writes, 1);
      expect(
        documents.proposal!.where((item) => item.isProtected).single,
        same(documents.protected),
      );
      expect(
        find.byKey(const Key('identity-services-pending')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppPrimaryButton>(
              find.byKey(const Key('identity-service-add')),
            )
            .onPressed,
        isNull,
      );
      Navigator.of(tester.element(find.byType(IdentityServicesPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('identity-services-open')));
      await tester.pumpAndSettle();
      expect(documents.writes, 1);
      expect(
        find.byKey(const Key('identity-services-pending')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('identity-services-resume')));
      await tester.pumpAndSettle();
      expect(documents.resumes, 1);
      expect(find.byKey(const Key('identity-services-pending')), findsNothing);
      expect(find.text('https://public.example/new'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Web member has no service or root management action', (
    tester,
  ) async {
    await tester.pumpWidget(_deviceApp(_Documents(), admin: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('identity-services-open')), findsNothing);
    expect(
      find.byKey(const Key('root-transfer-grant-management')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('devices-web-admin-limitation')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final capabilities in [wbaMethodCapabilities, webMethodCapabilities]) {
    testWidgets(
      'settings recovery follows Core capability ${capabilities.method}',
      (tester) async {
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const SettingsPage(),
            session: _webSession,
            providerOverrides: [
              identityCorePortProvider.overrideWithValue(
                FakeIdentityCorePort(methodCapabilities: capabilities),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings-recover-handle-did-row')),
          capabilities.handleRecovery ? findsOneWidget : findsNothing,
        );
      },
    );
  }
}

Widget _deviceApp(_Documents documents, {bool admin = true}) {
  final devices = FakeDeviceManagementCore()
    ..registry = DeviceRegistrySnapshot(
      did: _webDid,
      methodCapabilities: webMethodCapabilities,
      devices: [
        DeviceSummary(
          protocolDeviceId: 'current',
          signingKeyId: '$_webDid#sign',
          e2eeKeyId: '$_webDid#e2ee',
          status: DeviceStatus.active,
          role: admin ? DeviceRole.admin : DeviceRole.member,
          managementReady: admin,
          isCurrent: true,
        ),
        const DeviceSummary(
          protocolDeviceId: 'other',
          signingKeyId: '$_webDid#other-sign',
          e2eeKeyId: '$_webDid#other-e2ee',
          status: DeviceStatus.active,
          role: DeviceRole.member,
          managementReady: false,
          isCurrent: false,
        ),
      ],
    );
  return buildLocalizedTestApp(
    home: const DevicesPage(),
    session: _webSession,
    providerOverrides: [
      deviceManagementCorePortProvider.overrideWithValue(devices),
      identityDocumentCorePortProvider.overrideWithValue(documents),
      identityCorePortProvider.overrideWithValue(
        FakeIdentityCorePort(methodCapabilities: webMethodCapabilities),
      ),
    ],
  );
}

class _Documents implements IdentityDocumentCorePort {
  final protected = const IdentityDocumentService(
    id: '$_webDid#handle',
    type: 'ANPHandleService',
    endpoint: 'https://provider.example/handle',
  );
  late List<IdentityDocumentService> services = [
    protected,
    const IdentityDocumentService(
      id: '$_webDid#website',
      type: 'Website',
      endpoint: 'https://public.example/old',
    ),
  ];
  List<IdentityDocumentService>? proposal;
  bool pending = false;
  int writes = 0;
  int resumes = 0;

  @override
  Future<IdentityServicesSnapshot> identityServices(String selector) async {
    expect(selector, _webDid);
    return IdentityServicesSnapshot(services: services, pending: pending);
  }

  @override
  Future<void> updateIdentityServices(
    String selector,
    List<IdentityDocumentService> services,
  ) async {
    writes++;
    proposal = services;
    pending = true;
    throw StateError('test response lost');
  }

  @override
  Future<void> resumeIdentityServicesUpdate(String selector) async {
    resumes++;
    services = proposal!;
    pending = false;
  }
}
