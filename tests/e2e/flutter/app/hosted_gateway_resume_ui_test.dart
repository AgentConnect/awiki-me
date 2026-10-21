// Resume only the exact retained device. This does not attest a new Join.
import 'dart:io';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/domain/entities/identity_method.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../../case_attestation.dart';
import '../support/hosted_gateway_fixture.dart';
import '../support/hosted_widget_support.dart';

const String caseId = 'HOSTED-GATEWAY-RESUME-E2E-001';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );
  testWidgets(
    'Retained hosted App restores management after restart',
    (tester) async {
      final root = e2eInvocationValue(
        'AWIKI_HOSTED_RESUME_STATE_ROOT',
        compiledValue: '',
      );
      final path = e2eInvocationValue(
        'AWIKI_HOSTED_FIXTURE_PATH',
        compiledValue: '',
      );
      if (!Platform.isMacOS ||
          !root.startsWith('/') ||
          !Directory(root).existsSync()) {
        fail('hosted_requires_retained_mac_device');
      }
      AppBootstrap? bootstrap;
      HostedGatewayFixture? fixture;
      var phase = 'bootstrap';
      addTearDown(() async {
        fixture?.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await bootstrap?.dispose();
      });
      try {
        fixture = await HostedGatewayFixture.load(path);
        bootstrap = await AppBootstrap.create(
          appStateRoot: root,
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
        await until(tester, () => find.byType(AppShell).evaluate().length == 1);
        final active = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        phase = 'restore_identity';
        await until(
          tester,
          () =>
              active.read(sessionProvider).session?.did == fixture!.did &&
              active.read(appRuntimeProvider).activatedDid == fixture.did,
        );
        phase = 'local_management';
        final devices = active.read(deviceManagementCorePortProvider);
        final registry = await devices.identityDeviceRegistry(fixture.did);
        final device = registry.currentDevice;
        if (device == null ||
            !device.canManageDevices ||
            !await devices.localManagementReady(
              selector: fixture.did,
              protocolDeviceId: device.protocolDeviceId,
            )) {
          throw StateError('hosted_local_management_deadline');
        }
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
            'exact_identity_restored',
            'local_root_management_ready',
            'root_authorized_service_update',
            'recovery_material_retained',
          ],
        );
      } on Object catch (error, stack) {
        await E2eCaseAttestationWriter.markFailed(caseId, phase: phase);
        fail(
          'Hosted App resume failed at $phase (${hostedFailureCode(error)} '
          '${hostedFailureLocation(stack)}); private device state retained.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
