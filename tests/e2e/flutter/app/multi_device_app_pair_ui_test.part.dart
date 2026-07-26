part of 'multi_device_join_ui_test.dart';

void appPairAdminMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated admin App approves an isolated joining App',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final coordinator = config.coordinator;
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1320, 820));
      _requireIndependentEmptyPaths(<String>[config.adminStateRoot]);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await _deleteDirectory(config.adminStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      if (!await LocalAuthentication().isDeviceSupported()) {
        fail(
          'The App-pair admin requires real operating-system user presence.',
        );
      }
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.adminStateRoot,
      );
      final handle = _uniqueHandle(config.handlePrefix);
      final genesisOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _registrationPurpose,
        handle: handle,
      );
      final IdentityRegistrationResult registration;
      try {
        registration = await bootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: genesisOtp,
              handle: handle,
              nickName: 'AWiki App Pair Admin',
            );
      } on Object {
        fail('The App-pair admin registration failed safely.');
      }
      final adminSession = registration.identity;
      if (registration.status != IdentityRegistrationStatus.registered ||
          adminSession == null ||
          !adminSession.authenticated) {
        fail('The App-pair admin did not obtain an authenticated identity.');
      }
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(adminSession.did);
      final bootstrapAdminDeviceId = _requireAppReadyBootstrapAdmin(
        initialRegistry,
      );

      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
          ],
        ),
      );
      final container = await _waitForAuthenticatedApp(
        tester,
        expectedDid: adminSession.did,
      );
      await _pumpUntil(
        tester,
        () => container
            .read(realtimeConnectionStatusProvider)
            .maybeWhen(
              data: (status) => status == RealtimeConnectionStatus.connected,
              orElse: () => false,
            ),
        timeout: const Duration(seconds: 45),
        failure:
            'The admin App realtime listener was not ready before Join began.',
      );
      await coordinator.publish(
        'admin',
        'ready',
        data: <String, Object?>{
          'did': adminSession.did,
          'handle': handle,
          'adminDeviceId': bootstrapAdminDeviceId,
        },
      );

      final pending = await coordinator.waitFor(
        'joiner',
        'pending',
        timeout: const Duration(minutes: 3),
      );
      final joinSessionId = _required(pending, 'joinSessionId');
      final joinedDeviceId = _required(pending, 'joinedDeviceId');
      await _pumpUntil(
        tester,
        () {
          final matches = container
              .read(devicesProvider)
              .visibleJoinRequests
              .where(
                (request) =>
                    request.joinSessionId == joinSessionId &&
                    request.protocolDeviceId == joinedDeviceId,
              )
              .toList(growable: false);
          return matches.length == 1 &&
              matches.single.state == DeviceJoinRemoteState.pending &&
              matches.single.canStartVerification &&
              !matches.single.claimedByCurrentDevice;
        },
        timeout: const Duration(seconds: 60),
        failure:
            'The admin App did not expose the listener-delivered global Join entry.',
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('device-join-request-entry'),
        failure: 'The admin App global Join review entry was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinApprovalSheet).evaluate().length == 1,
        failure: 'The admin App Join approval sheet did not open.',
      );
      if (container.read(devicesProvider).activeJoin != null) {
        fail('Opening the App-pair request performed an implicit mutation.');
      }
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('multi-device-start-verification'),
        failure: 'The App-pair verification action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          return progress?.joinSessionId == joinSessionId &&
              progress?.protocolDeviceId == joinedDeviceId &&
              progress?.phase == DeviceJoinPhase.challengePrepared &&
              progress?.remoteState == DeviceJoinRemoteState.challengeSent &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 60),
        failure: 'The admin App did not start Join verification exactly once.',
      );
      await coordinator.publish('admin', 'verification_started');

      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(
            state,
            'The admin App failed to consume the Join response',
          );
          final progress = state.activeJoin;
          return progress?.joinSessionId == joinSessionId &&
              progress?.protocolDeviceId == joinedDeviceId &&
              progress?.phase == DeviceJoinPhase.responseVerified &&
              progress?.remoteState == DeviceJoinRemoteState.responseVerified &&
              _validSas(progress?.sas ?? '');
        },
        timeout: const Duration(seconds: 60),
        failure: 'The admin App did not restore the verified Join response.',
      );
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('device-approval-sas')).evaluate().length == 1,
        failure: 'The admin App did not render its local SAS.',
      );
      final adminSas =
          tester
              .widget<Text>(find.byKey(const Key('device-approval-sas')))
              .data ??
          '';
      if (!_validSas(adminSas) ||
          !await coordinator.submitAndCompareSas(
            'admin',
            adminSas,
            timeout: const Duration(minutes: 2),
          )) {
        fail('The two App processes did not derive the same SAS.');
      }

      final approveAction = find.bySemanticsIdentifier('multi-device-approve');
      if (approveAction.evaluate().isNotEmpty) {
        fail('App-pair approval was enabled before SAS confirmation.');
      }
      final sasSwitch = find.descendant(
        of: find.byKey(const Key('device-sas-confirmation')),
        matching: find.byType(CupertinoSwitch),
      );
      await _tapOne(
        tester,
        sasSwitch,
        failure: 'The App-pair SAS confirmation control was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => approveAction.evaluate().length == 1,
        failure: 'SAS confirmation did not enable App-pair approval.',
      );
      await _tapOne(
        tester,
        approveAction,
        failure: 'The App-pair member approval action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          if (presence.calls > 1) {
            fail('The admin App requested user presence more than once.');
          }
          if (presence.completions == 1 && !presence.lastResult) {
            fail('The App-pair operating-system user presence was denied.');
          }
          return presence.completions == 1 && presence.lastResult;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The admin App did not complete real user presence.',
      );

      final joined = await coordinator.waitFor(
        'joiner',
        'authorized',
        timeout: const Duration(minutes: 2),
      );
      if (_required(joined, 'joinedDeviceId') != joinedDeviceId ||
          _required(joined, 'adminDeviceId') != bootstrapAdminDeviceId) {
        fail('The joining App reported a different Registry identity.');
      }
      final adminRegistry = await _waitForAppRegistry(
        bootstrap.deviceManagementCorePort!,
        did: adminSession.did,
        expectedDeviceCount: 2,
      );
      _requireAppAdminAndMember(
        adminRegistry,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: joinedDeviceId,
      );
      await coordinator.publish('admin', 'complete');
      await E2eCaseAttestationWriter.markPassed(
        _appPairCaseId,
        phases: const <String>[
          'two_isolated_app_processes_bootstrapped',
          'joiner_pending_without_sas',
          'admin_global_join_review_entry_received',
          'sas_matched_in_memory_without_evidence',
          'single_real_user_presence_confirmed',
          'both_app_registries_converged',
        ],
      );
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

void appPairJoinerMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'isolated joining App completes member Join through visible UI',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final coordinator = config.coordinator;
      final httpClient = http.Client();
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1320, 820));
      _requireIndependentEmptyPaths(<String>[config.joinerStateRoot]);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await _deleteDirectory(config.joinerStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      final admin = await coordinator.waitFor(
        'admin',
        'ready',
        timeout: const Duration(minutes: 3),
      );
      final did = _required(admin, 'did');
      final handle = _required(admin, 'handle');
      final bootstrapAdminDeviceId = _required(admin, 'adminDeviceId');

      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.joinerStateRoot,
      );
      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await _openNewDeviceJoin(tester);
      final joinOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _joinPurpose,
        handle: handle,
      );
      await _enterText(tester, 'multi-device-join-handle', handle);
      await _enterText(tester, 'multi-device-join-phone', account.phone);
      await _enterText(tester, 'multi-device-join-otp', joinOtp);
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('multi-device-start-join'),
        failure: 'The joining App start action was unavailable.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceJoinPage)),
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The joining App rejected Join');
          final progress = state.activeJoin;
          return progress?.did == did &&
              progress?.side == DeviceJoinSide.newDevice &&
              progress?.phase == DeviceJoinPhase.pending &&
              progress?.remoteState == DeviceJoinRemoteState.pending &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 60),
        failure: 'OTP did not leave the joining App pending without a SAS.',
      );
      final pending = container.read(devicesProvider).activeJoin!;
      await coordinator.publish(
        'joiner',
        'pending',
        data: <String, Object?>{
          'joinSessionId': pending.joinSessionId,
          'joinedDeviceId': pending.protocolDeviceId,
        },
      );
      await coordinator.waitFor(
        'admin',
        'verification_started',
        timeout: const Duration(minutes: 2),
      );
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('device-join-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 60),
        failure: 'The joining App did not derive its local SAS.',
      );
      final joinerSas =
          tester.widget<Text>(find.byKey(const Key('device-join-sas'))).data ??
          '';
      if (!_validSas(joinerSas) ||
          !await coordinator.submitAndCompareSas(
            'joiner',
            joinerSas,
            timeout: const Duration(minutes: 2),
          )) {
        fail('The two App processes did not derive the same SAS.');
      }

      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The joining App failed to activate');
          final progress = state.activeJoin;
          final device = progress?.authorizedDevice;
          return progress?.phase == DeviceJoinPhase.authorized &&
              progress?.remoteState == DeviceJoinRemoteState.consumed &&
              progress?.sas == null &&
              device?.protocolDeviceId == pending.protocolDeviceId &&
              device?.role == DeviceRole.member &&
              device?.managementReady == false &&
              device?.isCurrent == true;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The joining App did not activate as the rootless member.',
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(sessionProvider).session?.did == did &&
            container.read(appRuntimeProvider).activatedDid == did,
        timeout: const Duration(seconds: 60),
        failure: 'The joining App did not activate the exact account DID.',
      );
      final joiningRegistry = await _waitForAppRegistry(
        bootstrap.deviceManagementCorePort!,
        did: did,
        expectedDeviceCount: 2,
      );
      _requireAppCurrentMember(
        joiningRegistry,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: pending.protocolDeviceId,
      );
      await coordinator.publish(
        'joiner',
        'authorized',
        data: <String, Object?>{
          'adminDeviceId': bootstrapAdminDeviceId,
          'joinedDeviceId': pending.protocolDeviceId,
        },
      );
      await coordinator.waitFor(
        'admin',
        'complete',
        timeout: const Duration(minutes: 2),
      );
    },
    timeout: const Timeout(Duration(minutes: 14)),
  );
}
