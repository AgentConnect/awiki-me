import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/tenant/builtin_tenant_config.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';
import '../../delete_isolated_directory.dart';

const String _caseId = 'REGISTRATION-DOMAIN-DISCOVERY-E2E-001';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeBuiltinTenantCatalog);
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );
  testWidgets(
    'real tenant registration discovery selects the visible contact method',
    (tester) async {
      final path =
          Platform.environment['AWIKI_REGISTRATION_DISCOVERY_FIXTURE'] ??
          const String.fromEnvironment('AWIKI_REGISTRATION_DISCOVERY_FIXTURE');
      expect(
        path,
        isNotEmpty,
        reason: 'Explicit read-only remote fixture required',
      );
      final fixture =
          jsonDecode(await e2eRuntimeFile(path).readAsString())
              as Map<String, dynamic>;
      final origin = Uri.parse(fixture['backend'] as String);
      expect(origin.scheme, 'https');
      expect(origin.origin, fixture['backend']);
      final domains = (fixture['domains'] as List).cast<Map<String, dynamic>>();
      expect(domains.length, 2);
      expect(domains[0]['domain'], isNot(domains[1]['domain']));
      for (final target in [domains[0], domains[1], domains[0]]) {
        final domain = target['domain'] as String;
        final method = target['method'] as String;
        expect(
          domain,
          isNot(origin.host),
          reason: 'Platform backend must differ from customer DID domain',
        );
        expect(['phone', 'email'], contains(method));
        final root = await Directory.systemTemp.createTemp(
          'awiki_domain_discovery_',
        );
        AppBootstrap? bootstrap;
        try {
          bootstrap = await AppBootstrap.create(
            environment: AwikiEnvironmentConfig(
              baseUrl: origin.origin,
              userServiceUrl: origin.origin,
              messageServiceUrl: origin.origin,
              mailServiceUrl: origin.origin,
              didDomain: domain,
              anpServiceUrl: '${origin.origin}/anp-im/rpc',
              anpServiceDid: 'did:wba:${origin.host}',
              agentImEnabled: false,
            ),
            appStateRoot: root.path,
          );
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
          await _until(
            tester,
            () => find.byType(OnboardingPage).evaluate().isNotEmpty,
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(OnboardingPage)),
          );
          await _until(
            tester,
            () => container.read(onboardingProvider).isServerInfoReady,
          );
          final state = container.read(onboardingProvider);
          final policy =
              state.serverInfo!.identity.handleRegistration.registrationPolicy;
          expect(policy?['domain'], domain);
          expect(policy?['source'], 'tenant');
          expect(policy?['mode'], 'allowlist');
          expect(state.authMode, method);
          await _until(
            tester,
            () => find
                .bySemanticsIdentifier('e2e-$method-input')
                .evaluate()
                .isNotEmpty,
          );
          expect(
            find.bySemanticsIdentifier('e2e-$method-input'),
            findsOneWidget,
          );
          final other = method == 'phone' ? 'email' : 'phone';
          expect(find.bySemanticsIdentifier('e2e-$other-input'), findsNothing);
          container.read(onboardingProvider.notifier).setAuthMode(other);
          await tester.pump();
          expect(container.read(onboardingProvider).authMode, method);
          if (target['existing_handle'] case final String existing) {
            final input = find.descendant(
              of: find.bySemanticsIdentifier('e2e-handle-input'),
              matching: find.byType(CupertinoTextField),
            );
            await tester.enterText(input, existing);
            await tester.pump();
            await tester.tap(
              find.bySemanticsIdentifier('e2e-existing-account-methods'),
            );
            await _until(
              tester,
              () =>
                  container.read(onboardingProvider).existingAccountMethods &&
                  container.read(onboardingProvider).isServerInfoReady,
            );
            expect(
              container.read(onboardingProvider).supportsPhoneOtpRegistration,
              isTrue,
            );
            container.read(onboardingProvider.notifier).setAuthMode('phone');
            await tester.pump();
            expect(container.read(onboardingProvider).authMode, 'phone');
            await _until(
              tester,
              () => find
                  .bySemanticsIdentifier('e2e-phone-input')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(
              find.bySemanticsIdentifier('e2e-phone-input'),
              findsOneWidget,
            );
            await tester.enterText(
              find.descendant(
                of: find.bySemanticsIdentifier('e2e-handle-input'),
                matching: find.byType(CupertinoTextField),
              ),
              'trnewaccountprobe',
            );
            await _until(
              tester,
              () =>
                  !container.read(onboardingProvider).existingAccountMethods &&
                  container.read(onboardingProvider).isServerInfoReady,
            );
            expect(container.read(onboardingProvider).authMode, method);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await bootstrap?.dispose();
          await deleteIsolatedDirectory(root);
        }
      }
      await E2eCaseAttestationWriter.markPassed(
        _caseId,
        phases: const [
          'real_backend_customer_scope',
          'visible_effective_methods',
          'domain_a_b_a_isolation',
        ],
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _until(WidgetTester tester, bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Real onboarding discovery did not become ready',
  );
}
