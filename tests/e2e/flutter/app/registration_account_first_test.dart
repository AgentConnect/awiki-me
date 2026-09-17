// Real native Core and loopback User Service; fixture provisioning/DB cleanup
// belong to the invoking local acceptance environment, never to production UI.
import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );
  testWidgets(
    'real invited short Handle registration and existing-account reentry',
    (tester) async {
      final path =
          Platform.environment['AWIKI_REGISTRATION_FIXTURE'] ??
          const String.fromEnvironment('AWIKI_REGISTRATION_FIXTURE');
      expect(
        path.isNotEmpty,
        isTrue,
        reason: 'Explicit disposable fixture required',
      );
      final fixture =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
      final url = fixture['userServiceUrl'] as String;
      expect(
        {'localhost', '127.0.0.1', '::1'}.contains(Uri.parse(url).host),
        isTrue,
      );
      final handle = fixture['handle'] as String;
      final domain = fixture['domain'] as String;
      final phone = fixture['phone'] as String;
      final invite = fixture['inviteCode'] as String;
      final otp = fixture['otp'] as String;
      expect(handle.length, 3);
      final roots = <Directory>[];
      AppBootstrap? bootstrap;
      try {
        for (final existing in [false, true]) {
          final root = await Directory.systemTemp.createTemp(
            'awiki_registration_native_',
          );
          roots.add(root);
          bootstrap = await AppBootstrap.create(
            environment: AwikiEnvironmentConfig(
              baseUrl: url,
              userServiceUrl: url,
              didDomain: domain,
              messageServiceUrl: 'http://127.0.0.1:19992',
              mailServiceUrl: 'http://127.0.0.1:19993',
              anpServiceUrl: 'http://127.0.0.1:19992/im/rpc',
              anpServiceDid: 'did:wba:$domain',
              agentImEnabled: false,
            ),
            appStateRoot: root.path,
          );
          await tester.binding.setSurfaceSize(const Size(1280, 900));
          await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
          await _until(
            tester,
            () => find.byType(OnboardingPage).evaluate().isNotEmpty,
            'Onboarding visible in isolated native scope',
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(OnboardingPage)),
          );
          await _until(
            tester,
            () => container.read(onboardingProvider).serverInfo != null,
            'Real User Service capabilities loaded',
          );
          await _enter(tester, 'e2e-handle-input', handle);
          expect(
            find.bySemanticsIdentifier('e2e-send-otp-button'),
            findsNothing,
          );
          await _tap(tester, find.bySemanticsIdentifier('e2e-account-next'));
          if (!existing) {
            await _until(
              tester,
              () => find
                  .bySemanticsIdentifier('e2e-invite-input')
                  .evaluate()
                  .isNotEmpty,
              'Three-character invitation required',
            );
            await _tap(tester, find.bySemanticsIdentifier('e2e-invite-next'));
            expect(
              find.bySemanticsIdentifier('e2e-send-otp-button'),
              findsNothing,
            );
            await _enter(tester, 'e2e-invite-input', invite);
            await _tap(tester, find.bySemanticsIdentifier('e2e-invite-next'));
          }
          await _until(
            tester,
            () => find
                .bySemanticsIdentifier('e2e-phone-input')
                .evaluate()
                .isNotEmpty,
            'Contact verification follows account admission',
          );
          expect(find.bySemanticsIdentifier('e2e-invite-input'), findsNothing);
          await _enter(tester, 'e2e-phone-input', phone);
          await _tap(tester, find.bySemanticsIdentifier('e2e-send-otp-button'));
          await _until(
            tester,
            () =>
                container.read(onboardingProvider).otpTargetFullHandle ==
                '$handle.$domain',
            'Real scoped OTP receipt accepted',
          );
          await _enter(tester, 'e2e-otp-input', otp);
          expect(container.read(onboardingProvider).canSubmitPhoneOtp, isTrue);
          expect(container.read(onboardingProvider).isBusy, isFalse);
          await _tap(
            tester,
            find.byKey(const Key('onboarding-mac-phone-submit-action')),
          );
          if (existing) {
            await _until(
              tester,
              () => find
                  .byKey(const Key('existing-handle-join-action'))
                  .evaluate()
                  .isNotEmpty,
              'Existing short account reaches authenticated Join choice without invitation',
            );
            expect(
              find.byKey(const Key('existing-handle-recovery-action')),
              findsOneWidget,
            );
          } else {
            await _until(
              tester,
              () => container.read(sessionProvider).session != null,
              'Native Core completes real invited registration',
              diagnostic: () {
                final feedback = container.read(uiFeedbackProvider);
                final visibleText = find
                    .byType(Text)
                    .evaluate()
                    .map((element) => (element.widget as Text).data ?? '')
                    .join(' | ');
                return '${container.read(onboardingProvider).phoneRegistrationFailureCode}; ${feedback?.message.id}: ${feedback?.message.detail ?? feedback?.detail ?? ""}; $visibleText'
                    .replaceAll(invite, '<invite>')
                    .replaceAll(phone, '<phone>')
                    .replaceAll(handle, '<handle>')
                    .replaceAll(otp, '<otp>');
              },
            );
            expect(
              container
                  .read(sessionProvider)
                  .session!
                  .did
                  .startsWith('did:wba:$domain:'),
              isTrue,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await bootstrap.dispose();
          bootstrap = null;
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        for (final root in roots) {
          if (await root.exists()) await root.delete(recursive: true);
        }
      }
      await E2eCaseAttestationWriter.markPassed(
        'REGISTRATION-ACCOUNT-FIRST-E2E-001',
        phases: const [
          'isolated_native_scopes',
          'short_handle_invite_required',
          'real_scoped_otp',
          'real_native_registration',
          'existing_account_join_choice',
        ],
      );
    },
  );
}

Future<void> _enter(WidgetTester tester, String id, String text) async {
  final field = find.descendant(
    of: find.bySemanticsIdentifier(id),
    matching: find.byType(CupertinoTextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason, {
  String Function()? diagnostic,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: '$reason ${ready() ? "" : diagnostic?.call() ?? ""}',
  );
}
