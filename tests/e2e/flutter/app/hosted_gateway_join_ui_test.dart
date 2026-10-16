// Real Mac App email Join and receiving-device root activation. Gateway account
// preparation is a separate owning fixture; no mock Core or copied App state.
import 'dart:async';
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/domain/entities/identity_method.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';
import '../support/hosted_gateway_fixture.dart';
import '../support/read_rendered_sas.dart';
import '../support/hosted_widget_support.dart';
import 'hosted_gateway_approval_ui_case.dart';

const String caseId = 'HOSTED-GATEWAY-JOIN-E2E-001';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );
  registerHostedGatewayApprovalCase();
  testWidgets(
    'hosted email Join activates receiving App management',
    (tester) async {
      final fixturePath = e2eInvocationValue(
        'AWIKI_HOSTED_FIXTURE_PATH',
        compiledValue: const String.fromEnvironment(
          'AWIKI_HOSTED_FIXTURE_PATH',
        ),
      );
      final stateRoot = e2eInvocationValue(
        'AWIKI_HOSTED_APP_STATE_ROOT',
        compiledValue: const String.fromEnvironment(
          'AWIKI_HOSTED_APP_STATE_ROOT',
        ),
      );
      if (!Platform.isMacOS ||
          fixturePath.isEmpty ||
          stateRoot.isEmpty ||
          !stateRoot.startsWith('/') ||
          await Directory(stateRoot).exists()) {
        fail('hosted_requires_mac_and_fresh_explicit_state');
      }
      AppBootstrap? bootstrap;
      HostedGatewayFixture? fixture;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() async {
        fixture?.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap?.dispose();
        await tester.binding.setSurfaceSize(null);
        // Keep this exact device's keys for isolated follow-up and recovery.
      });
      var phase = 'fixture';
      try {
        fixture = await HostedGatewayFixture.load(fixturePath);
        await fixture.login();
        phase = 'bootstrap';
        bootstrap = await AppBootstrap.create(
          appStateRoot: stateRoot,
          environment: AwikiEnvironmentConfig(
            baseUrl: hostedOrigin,
            userServiceUrl: hostedOrigin,
            messageServiceUrl: hostedOrigin,
            didDomain: hostedDomain,
            agentImEnabled: false,
            multiDeviceDirectE2eeEnabled: true,
            multiDeviceGroupE2eeEnabled: false,
          ),
        );
        await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
        await until(
          tester,
          () => find.byType(OnboardingPage).evaluate().length == 1,
        );
        unawaited(
          openDeviceJoinPage(tester.element(find.byType(OnboardingPage))),
        );
        await until(
          tester,
          () => find.byType(DeviceJoinPage).evaluate().length == 1,
        );
        final page = find.byType(DeviceJoinPage);
        await tester.tap(
          find.descendant(
            of: page,
            matching: find.text(tester.element(page).l10n.onboardingEmail),
          ),
        );
        await tester.pump();
        await input(tester, 'multi-device-join-email', fixture.contact);
        await input(
          tester,
          'multi-device-join-handle',
          '${fixture.handle}.$hostedDomain',
        );
        phase = 'email_join';
        final code = await fixture.otp('join', fixture.handle);
        await input(tester, 'multi-device-join-otp', code);
        final start = find.bySemanticsIdentifier('multi-device-start-join');
        await tester.ensureVisible(start);
        await tester.tap(start);
        final container = ProviderScope.containerOf(tester.element(page));
        await until(
          tester,
          () => container.read(devicesProvider).activeJoin != null,
        );
        final join = container.read(devicesProvider).activeJoin!;
        final arguments = {
          'handle': '${fixture.handle}.$hostedDomain',
          'join_session_id': join.joinSessionId,
        };
        phase = 'request_delivery';
        await fixture.waitForJoinRequest(join.joinSessionId);
        phase = 'pairing';
        await fixture.post('pair-device', arguments);
        await until(
          tester,
          () => find.byKey(const Key('device-join-sas')).evaluate().length == 1,
        );
        final sas = readRenderedSas(
          tester,
          find.byKey(const Key('device-join-sas')),
        );
        final paired = await fixture.post('pair-device', {
          ...arguments,
          'refresh': true,
        });
        if (paired['sas'] != sas) throw StateError('hosted_pairing_mismatch');
        phase = 'approve';
        await fixture.post('approve-device', {
          ...arguments,
          'displayed_sas': sas,
          'sas_confirmed': true,
          'grant_management': true,
          'operation_id': fixture.operationId(),
        });
        await until(tester, () => find.byType(AppShell).evaluate().length == 1);
        final active = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        if (active.read(sessionProvider).session?.did != fixture.did) {
          throw StateError('hosted_app_wrong_identity');
        }
        phase = 'local_activation';
        final devices = bootstrap.deviceManagementCorePort!;
        var ready = false;
        for (var attempt = 0; attempt < 120; attempt++) {
          final registry = await devices.identityDeviceRegistry(fixture.did);
          final device = registry.currentDevice;
          if (device != null &&
              device.canManageDevices &&
              await devices.localManagementReady(
                selector: fixture.did,
                protocolDeviceId: device.protocolDeviceId,
              )) {
            ready = true;
            break;
          }
          await tester.pump(const Duration(seconds: 1));
        }
        if (!ready) throw StateError('hosted_local_management_deadline');
        phase = 'root_operation';
        final documents = active.read(identityDocumentCorePortProvider);
        final before = await documents.identityServices(fixture.did);
        final marker = '${fixture.did}#hosted-app-e2e-management';
        await documents.updateIdentityServices(fixture.did, [
          ...before.services.where((item) => item.id != marker),
          IdentityDocumentService(
            id: marker,
            type: 'HostedAppE2eManagement',
            endpoint: '$hostedOrigin/connect',
          ),
        ]);
        final after = await documents.identityServices(fixture.did);
        if (after.pending ||
            after.services.where((item) => item.id == marker).length != 1) {
          throw StateError('hosted_root_authorized_update_failed');
        }
        await E2eCaseAttestationWriter.markPassed(
          caseId,
          phases: const [
            'email_join_ui',
            'pairing_both_sides',
            'exact_identity_activated',
            'local_root_management_ready',
            'root_authorized_service_update',
            'recovery_material_retained',
          ],
        );
      } on Object catch (error, stack) {
        await E2eCaseAttestationWriter.markFailed(caseId, phase: phase);
        fail(
          'Hosted App Join failed at $phase (${hostedFailureCode(error)} ${hostedFailureLocation(stack)}); private device state retained.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
