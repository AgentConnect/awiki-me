// [INPUT]: Production AppBootstrap/native Core and two isolated temporary App roots.
// [OUTPUT]: Real product evidence for the default device entry, adapters, and independent gates.
// [POS]: Local entry E2E; it does not claim remote Join/SAS/Root/Recovery acceptance.

import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';

const String _caseId = 'MULTI-DEVICE-CAPABILITY-GATE-E2E-001';
const String _unreachableLoopback = 'http://127.0.0.1:1';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production bootstrap exposes Join while high-risk gates stay closed',
    (tester) async {
      final appRoot = await Directory.systemTemp.createTemp(
        'awiki_me_multi_device_default_',
      );
      addTearDown(() async {
        if (await appRoot.exists()) await appRoot.delete(recursive: true);
      });

      AppBootstrap? bootstrap;
      String? scopeId;
      await tester.binding.setSurfaceSize(const Size(1280, 820));
      try {
        final environment = AwikiEnvironmentConfig(
          baseUrl: _unreachableLoopback,
          userServiceUrl: _unreachableLoopback,
          messageServiceUrl: _unreachableLoopback,
          mailServiceUrl: _unreachableLoopback,
          didDomain: 'multi-device-e2e.invalid',
          agentImEnabled: false,
        );
        _expectRolloutGatesDisabled(environment);
        bootstrap = await AppBootstrap.create(
          environment: environment,
          appStateRoot: appRoot.path,
        );
        scopeId = bootstrap.storageScopeLayout!.scopeId.value;
        expect(bootstrap.deviceManagementCorePort, isNotNull);
        expect(bootstrap.rootKeyTransferPort, isNotNull);
        expect(bootstrap.groupEncryptionCorePort, isNull);

        await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
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
        expect(
          find.byKey(const Key('root-transfer-grant-management')),
          findsNothing,
        );
        expect(find.byKey(const Key('device-join-sas')), findsNothing);
        expect(find.byKey(const Key('device-admin-toggle')), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap.dispose();
        bootstrap = null;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await tester.binding.setSurfaceSize(null);
        if (await appRoot.exists()) await appRoot.delete(recursive: true);
      }

      expect(scopeId, isNotNull);
      expect(await appRoot.exists(), isFalse);
      await E2eCaseAttestationWriter.markPassed(
        _caseId,
        phases: const <String>[
          'isolated_scope_opened',
          'default_join_entry_opened',
          'high_risk_capabilities_stayed_closed',
          'temporary_scope_deleted',
        ],
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}

void _expectRolloutGatesDisabled(AwikiEnvironmentConfig environment) {
  expect(environment.multiDeviceDeviceRevokeEnabled, isFalse);
  expect(environment.multiDeviceDirectE2eeEnabled, isFalse);
  expect(environment.multiDeviceGroupE2eeEnabled, isFalse);
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
