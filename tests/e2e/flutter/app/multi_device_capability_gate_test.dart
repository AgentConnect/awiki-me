// [INPUT]: Production AppBootstrap/native Core and two isolated temporary App roots.
// [OUTPUT]: Real product evidence for default-off and Join-only capability gating.
// [POS]: Local capability-gate E2E; it does not claim remote Join/SAS/Root/Recovery acceptance.

import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';

const String _caseId = 'MULTI-DEVICE-CAPABILITY-GATE-E2E-001';
const String _unreachableLoopback = 'http://127.0.0.1:1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production bootstrap keeps multi-device closed until Join is enabled',
    (tester) async {
      final disabledRoot = await Directory.systemTemp.createTemp(
        'awiki_me_multi_device_disabled_',
      );
      final joinOnlyRoot = await Directory.systemTemp.createTemp(
        'awiki_me_multi_device_join_only_',
      );
      addTearDown(() async {
        for (final root in <Directory>[disabledRoot, joinOnlyRoot]) {
          if (await root.exists()) await root.delete(recursive: true);
        }
      });

      AppBootstrap? disabledBootstrap;
      AppBootstrap? joinOnlyBootstrap;
      String? disabledScopeId;
      String? joinOnlyScopeId;
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      try {
        final disabledEnvironment = AwikiEnvironmentConfig(
          baseUrl: _unreachableLoopback,
          userServiceUrl: _unreachableLoopback,
          messageServiceUrl: _unreachableLoopback,
          mailServiceUrl: _unreachableLoopback,
          didDomain: 'multi-device-e2e.invalid',
          agentImEnabled: false,
        );
        _expectEveryMultiDeviceCapabilityDisabled(disabledEnvironment);
        disabledBootstrap = await AppBootstrap.create(
          environment: disabledEnvironment,
          appStateRoot: disabledRoot.path,
        );
        disabledScopeId = disabledBootstrap.storageScopeLayout!.scopeId.value;
        expect(disabledBootstrap.deviceManagementCorePort, isNull);
        expect(disabledBootstrap.rootKeyTransferPort, isNull);
        expect(disabledBootstrap.groupEncryptionCorePort, isNull);
        expect(disabledBootstrap.handleRecoveryPort, isNull);

        await tester.pumpWidget(AwikiMeApp(bootstrap: disabledBootstrap));
        await _pumpUntilVisible(tester, find.byType(OnboardingPage));
        expect(
          find.bySemanticsIdentifier('multi-device-join-entry'),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await disabledBootstrap.dispose();
        disabledBootstrap = null;

        final joinOnlyEnvironment = AwikiEnvironmentConfig(
          baseUrl: _unreachableLoopback,
          userServiceUrl: _unreachableLoopback,
          messageServiceUrl: _unreachableLoopback,
          mailServiceUrl: _unreachableLoopback,
          didDomain: 'multi-device-e2e.invalid',
          agentImEnabled: false,
          multiDeviceJoinEnabled: true,
          multiDeviceRootTransferEnabled: false,
          multiDeviceDeviceRevokeEnabled: false,
          multiDeviceDirectE2eeEnabled: false,
          multiDeviceGroupE2eeEnabled: false,
          handleRecoveryEnabled: false,
        );
        joinOnlyBootstrap = await AppBootstrap.create(
          environment: joinOnlyEnvironment,
          appStateRoot: joinOnlyRoot.path,
        );
        joinOnlyScopeId = joinOnlyBootstrap.storageScopeLayout!.scopeId.value;
        expect(joinOnlyScopeId, isNot(disabledScopeId));
        expect(joinOnlyBootstrap.deviceManagementCorePort, isNotNull);
        expect(joinOnlyBootstrap.rootKeyTransferPort, isNull);
        expect(joinOnlyBootstrap.groupEncryptionCorePort, isNull);
        expect(joinOnlyBootstrap.handleRecoveryPort, isNull);
        expect(joinOnlyEnvironment.multiDeviceDeviceRevokeEnabled, isFalse);
        expect(joinOnlyEnvironment.multiDeviceDirectE2eeEnabled, isFalse);
        expect(joinOnlyEnvironment.multiDeviceGroupE2eeEnabled, isFalse);

        await tester.pumpWidget(AwikiMeApp(bootstrap: joinOnlyBootstrap));
        final joinEntry = find.bySemanticsIdentifier('multi-device-join-entry');
        await _pumpUntilVisible(tester, joinEntry);
        await tester.ensureVisible(joinEntry);
        await tester.tap(joinEntry);
        await _pumpUntilVisible(tester, find.byType(DeviceJoinPage));

        expect(find.byKey(const Key('device-join-page')), findsOneWidget);
        expect(
          find.bySemanticsIdentifier('multi-device-join-handle'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('multi-device-join-phone'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('multi-device-join-otp'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsIdentifier('multi-device-start-join'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('device-join-sas')), findsNothing);
        expect(find.byKey(const Key('device-admin-toggle')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await joinOnlyBootstrap.dispose();
        joinOnlyBootstrap = null;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await joinOnlyBootstrap?.dispose();
        await disabledBootstrap?.dispose();
        await tester.binding.setSurfaceSize(null);
        for (final root in <Directory>[disabledRoot, joinOnlyRoot]) {
          if (await root.exists()) await root.delete(recursive: true);
        }
      }

      expect(disabledScopeId, isNotNull);
      expect(joinOnlyScopeId, isNotNull);
      expect(await disabledRoot.exists(), isFalse);
      expect(await joinOnlyRoot.exists(), isFalse);
      await E2eCaseAttestationWriter.markPassed(
        _caseId,
        phases: const <String>[
          'isolated_scopes_opened',
          'default_capabilities_failed_closed',
          'join_only_public_entry_opened',
          'high_risk_capabilities_stayed_closed',
          'temporary_scopes_deleted',
        ],
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}

void _expectEveryMultiDeviceCapabilityDisabled(
  AwikiEnvironmentConfig environment,
) {
  expect(environment.multiDeviceJoinEnabled, isFalse);
  expect(environment.multiDeviceRootTransferEnabled, isFalse);
  expect(environment.multiDeviceDeviceRevokeEnabled, isFalse);
  expect(environment.multiDeviceDirectE2eeEnabled, isFalse);
  expect(environment.multiDeviceGroupE2eeEnabled, isFalse);
  expect(environment.handleRecoveryEnabled, isFalse);
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}
