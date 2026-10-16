// App owns the management device; Gateway must remain a messages-only member.
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../case_attestation.dart';
import '../../e2e_user_presence_port.dart';
import '../support/hosted_gateway_fixture.dart';
import '../support/hosted_widget_support.dart';
import '../support/read_rendered_sas.dart';

const _caseId = 'HOSTED-GATEWAY-APPROVAL-E2E-001';

void registerHostedGatewayApprovalCase() {
  testWidgets(
    'App approves Gateway signed message-only Join',
    (tester) async {
      final path = e2eInvocationValue(
        'AWIKI_HOSTED_PHONE_FIXTURE_PATH',
        compiledValue: const String.fromEnvironment(
          'AWIKI_HOSTED_PHONE_FIXTURE_PATH',
        ),
      );
      final root = e2eInvocationValue(
        'AWIKI_HOSTED_APP_STATE_ROOT',
        compiledValue: const String.fromEnvironment(
          'AWIKI_HOSTED_APP_STATE_ROOT',
        ),
      );
      if (!Platform.isMacOS ||
          !path.startsWith('/') ||
          !root.startsWith('/') ||
          await Directory('$root-approval').exists()) {
        fail('hosted_approval_requires_fresh_mac_scope');
      }
      AppBootstrap? bootstrap;
      HostedGatewayFixture? gateway;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() async {
        gateway?.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap?.dispose();
        await tester.binding.setSurfaceSize(null);
        // Keep the exact identity/device keys, including after a partial failure.
      });
      var phase = 'fixture';
      try {
        final fixture = await HostedGatewayFixture.loadPhoneRegistration(path);
        gateway = fixture.gateway;
        final presence = E2eUserPresencePort();
        bootstrap = await AppBootstrap.create(
          appStateRoot: '$root-approval',
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
        await tester.pumpWidget(
          AwikiMeApp(
            bootstrap: bootstrap,
            providerOverrides: [
              userPresencePortProvider.overrideWithValue(presence),
            ],
          ),
        );
        await until(
          tester,
          () => find.byType(OnboardingPage).evaluate().length == 1,
        );
        final onboarding = ProviderScope.containerOf(
          tester.element(find.byType(OnboardingPage)),
        );
        await until(
          tester,
          () => onboarding.read(onboardingProvider).serverInfo != null,
        );
        phase = 'phone_registration_ui';
        await input(tester, 'e2e-handle-input', gateway.handle);
        await input(tester, 'e2e-phone-input', gateway.contact);
        await tester.tap(find.bySemanticsIdentifier('e2e-send-otp-button'));
        await until(
          tester,
          () =>
              onboarding.read(onboardingProvider).otpTargetFullHandle ==
              '${gateway!.handle}.$hostedDomain',
        );
        await input(tester, 'e2e-otp-input', fixture.code);
        await tester.tap(
          find.byKey(const Key('onboarding-mac-phone-submit-action')),
        );
        await until(tester, () => find.byType(AppShell).evaluate().length == 1);
        final active = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        final did = active.read(sessionProvider).session?.did;
        if (did == null || !did.startsWith('did:wba:$hostedDomain:')) {
          throw StateError('hosted_approval_identity');
        }
        final registryBefore = await bootstrap.deviceManagementCorePort!
            .identityDeviceRegistry(did);
        if (registryBefore.devices.length != 1 ||
            registryBefore.currentDevice?.canManageDevices != true) {
          throw StateError('hosted_approval_not_initial_admin');
        }
        phase = 'gateway_existing_identity';
        await gateway.login();
        final selected = await gateway.post('select', {
          'handle': '${gateway.handle}.$hostedDomain',
          'operation_id': gateway.operationId(),
        });
        if (selected['ready'] == true || selected['task_id'] is! String) {
          throw StateError('hosted_approval_not_new_join');
        }
        Future<Map<String, dynamic>> task() async {
          final tasks =
              (await gateway!.request('/connect/state'))['tasks'] as List;
          final matches = tasks
              .where((value) => value['id'] == selected['task_id'])
              .toList();
          if (matches.length != 1 ||
              ['failed', 'cancelled'].contains(matches.single['state'])) {
            throw StateError('hosted_approval_task_failed');
          }
          return Map<String, dynamic>.from(matches.single as Map);
        }

        String? session;
        for (var attempt = 0; attempt < 60; attempt++) {
          session =
              ((await task())['result'] as Map?)?['join_session_id'] as String?;
          if (session != null) break;
          await tester.pump(const Duration(seconds: 2));
        }
        if (session == null) throw StateError('hosted_approval_join_deadline');
        phase = 'signed_request_ui';
        final review = find.bySemanticsIdentifier('device-join-request-entry');
        await until(tester, () => review.hitTestable().evaluate().length == 1);
        await tester.tap(review);
        final sheet = find.byType(DeviceJoinApprovalSheet);
        await until(tester, () => sheet.evaluate().length == 1);
        final request = tester.widget<DeviceJoinApprovalSheet>(sheet).request;
        if (request.joinSessionId != session ||
            request.joinPurpose != 'messages_only') {
          throw StateError('hosted_approval_signed_purpose');
        }
        final purpose = tester
            .widget<Text>(find.byKey(const Key('device-approval-purpose')))
            .data;
        if (purpose !=
            tester.element(sheet).l10n.deviceJoinMessageOnlyPresenceReason) {
          throw StateError('hosted_approval_purpose_display');
        }
        await tester.tap(
          find.bySemanticsIdentifier('multi-device-start-verification'),
        );
        final sasView = find.byKey(const Key('device-approval-sas'));
        await until(tester, () => sasView.evaluate().length == 1);
        final sas = readRenderedSas(tester, sasView);
        phase = 'pairing_both_sides';
        String? other;
        for (var attempt = 0; attempt < 60; attempt++) {
          other = ((await task())['result'] as Map?)?['sas'] as String?;
          if (other != null) break;
          await tester.pump(const Duration(seconds: 2));
        }
        if (other != sas) throw StateError('hosted_approval_pairing_mismatch');
        final beforePresence = presence.calls;
        await tester.tap(find.byKey(const Key('device-sas-confirmation')));
        await tester.pump();
        await tester.tap(find.bySemanticsIdentifier('multi-device-approve'));
        await until(
          tester,
          () =>
              active.read(devicesProvider).activeJoin?.phase ==
              DeviceJoinPhase.authorized,
        );
        if (presence.calls != beforePresence + 1 || !presence.lastResult) {
          throw StateError('hosted_approval_presence');
        }
        phase = 'ordinary_member_boundary';
        var complete = false;
        for (var attempt = 0; attempt < 60; attempt++) {
          if ((await task())['state'] == 'complete') {
            complete = true;
            break;
          }
          await tester.pump(const Duration(seconds: 2));
        }
        if (!complete) throw StateError('hosted_approval_completion_deadline');
        final registry = await bootstrap.deviceManagementCorePort!
            .identityDeviceRegistry(did);
        final members = registry.devices
            .where((device) => !device.isCurrent)
            .toList();
        if (members.length != 1 ||
            members.single.protocolDeviceId != request.protocolDeviceId ||
            members.single.role != DeviceRole.member ||
            members.single.managementReady) {
          throw StateError('hosted_approval_management_escalation');
        }
        final denied = await gateway.post('device-requests', {
          'handle': '${gateway.handle}.$hostedDomain',
        }, expectedStatus: 403);
        if (denied['error'] != 'root_key_not_hosted') {
          throw StateError('hosted_approval_root_not_absent');
        }
        await E2eCaseAttestationWriter.markPassed(
          'HOSTED-GATEWAY-APPROVAL-E2E-001',
          phases: const [
            'phone_registration_ui',
            'verified_message_only_purpose_ui',
            'pairing_both_sides',
            'single_user_presence',
            'gateway_ordinary_member',
            'gateway_root_absent',
            'recovery_material_retained',
          ],
        );
      } on Object {
        await E2eCaseAttestationWriter.markFailed(_caseId, phase: phase);
        fail(
          'Hosted App approval failed; exact private fixture and device state retained.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
