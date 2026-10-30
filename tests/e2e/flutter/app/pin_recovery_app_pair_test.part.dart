part of 'multi_device_join_ui_test.dart';

const String _pinAppCaseId = 'PIN-RECOVERY-APP-E2E-001';

/// PIN and OTP stay in the protected, ignored fixture. The coordinator carries
/// only public identity checkpoints and payload-free lifecycle assertions.
({String pin, List<core.PinRecoveryTenantConfig> tenants}) _pinFixture() {
  final path = Platform.environment['AWIKI_PIN_RECOVERY_E2E_FIXTURE'];
  if (!awikiE2eEnabled || path == null) {
    throw StateError('PIN fixture is required.');
  }
  final file = File(path);
  if ((file.statSync().mode & 0x3f) != 0) {
    throw StateError('PIN fixture permissions are unsafe.');
  }
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final pin = data['pin'] as String;
  if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
    throw StateError('PIN fixture is invalid.');
  }
  return (
    pin: pin,
    tenants: decodePinRecoveryTenants(
      base64Encode(utf8.encode(jsonEncode(data['tenants']))),
    ),
  );
}

Future<void> _pinTap(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await _pumpUntil(
    tester,
    () =>
        finder.evaluate().length == 1 &&
        (tester.widget(finder) is! AppSecondaryButton ||
            tester.widget<AppSecondaryButton>(finder).onPressed != null) &&
        (tester.widget(finder) is! AppPrimaryButton ||
            tester.widget<AppPrimaryButton>(finder).onPressed != null),
    timeout: const Duration(seconds: 60),
    failure: 'PIN product control unavailable: $key',
  );
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pinFill(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await _pumpUntil(
    tester,
    () => finder.evaluate().length == 1,
    failure: 'PIN product input is unavailable: $key',
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _pinWrappedFill(
  WidgetTester tester,
  String key,
  String value,
) async {
  final wrapper = find.byKey(Key(key));
  await _pumpUntil(
    tester,
    () => wrapper.evaluate().length == 1,
    failure: 'Recovery field did not load.',
  );
  final input = find.descendant(
    of: wrapper,
    matching: find.byType(CupertinoTextField),
  );
  await _pumpUntil(
    tester,
    () =>
        input.evaluate().length == 1 &&
        tester.widget<CupertinoTextField>(input).enabled,
    failure: 'Recovery input did not become enabled.',
  );
  await tester.ensureVisible(input);
  await tester.enterText(input, value);
  await tester.pump();
}

Future<void> _pinOpenSettings(WidgetTester tester) async {
  unawaited(
    Navigator.of(
      tester.element(find.byType(AppShell)),
    ).push(CupertinoPageRoute<void>(builder: (_) => const SettingsPage())),
  );
  await tester.pump();
}

Future<void> _pinEnableFromSettings(
  WidgetTester tester,
  _DedicatedAccount account,
  String handle,
  String pin,
) async {
  await _pinOpenSettings(tester);
  await _pinTap(tester, 'settings-pin-backup-row');
  await _pinVerifySelect(tester, account, handle);
  await _pinFill(tester, 'pin-recovery-pin', pin);
  await _pinFill(tester, 'pin-recovery-pin-confirm', pin);
  await _pinTap(tester, 'pin-recovery-submit-pin');
  await _pumpUntil(
    tester,
    () => find.byKey(const Key('pin-recovery-done')).evaluate().length == 1,
    timeout: const Duration(minutes: 2),
    failure: 'New-root backup did not activate.',
  );
}

Object? _pinSorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _pinSorted(value[key])};
  }
  if (value is List) return value.map(_pinSorted).toList(growable: false);
  return value;
}

Future<Map<String, String>> _pinPublicMethods(String did) async {
  final parts = did.split(':');
  if (parts.length < 4 || parts[0] != 'did' || parts[1] != 'wba') {
    fail('Unexpected DID method.');
  }
  final client = http.Client();
  try {
    final response = await client.get(
      Uri.https(parts[2], '/${parts.skip(3).join('/')}/did.json'),
    );
    if (response.statusCode != 200) fail('Public DID document is unavailable.');
    final document = jsonDecode(response.body) as Map<String, dynamic>;
    if (document['id'] != did) fail('Public DID document target mismatch.');
    return {
      for (final method in document['verificationMethod'] as List)
        method['id'] as String: jsonEncode(_pinSorted(method)),
    };
  } finally {
    client.close();
  }
}

Future<void> _pinVerifySelect(
  WidgetTester tester,
  _DedicatedAccount account,
  String fullHandle, {
  String? deviceLabel,
}) async {
  await _pinFill(tester, 'pin-recovery-phone', account.phone);
  await _pinTap(tester, 'pin-recovery-send-code');
  await _pinFill(tester, 'pin-recovery-otp', account.fixedOtp);
  await _pinTap(tester, 'pin-recovery-verify');
  final targetButton = find.widgetWithText(AppSecondaryButton, fullHandle);
  await _pumpUntil(
    tester,
    () => targetButton.evaluate().length == 1,
    failure: 'Dedicated verified phone did not discover the exact Handle.',
  );
  if (deviceLabel != null) {
    await _pinFill(tester, 'pin-recovery-device-label', deviceLabel);
  }
  await tester.ensureVisible(targetButton);
  await tester.tap(targetButton);
  await tester.pump();
}

void _pinAppAdminMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'PIN backup from optional offer and identity settings on App A',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final fixture = _pinFixture();
      final account = _DedicatedAccount.fromProtectedConfig(
        config.localConfigPath,
      );
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1320, 820));
      _requireIndependentEmptyPaths([config.adminStateRoot]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(
          config,
          enableRootTransfer: true,
          enableMessageSyncCore: true,
        ),
        appStateRoot: config.adminStateRoot,
        pinRecoveryTenants: fixture.tenants,
      );
      final handle = _uniqueHandle(config.handlePrefix);
      await config.coordinator.publish(
        'admin',
        'pin_registration_intent',
        data: {'handle': handle},
      );
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: [
            userPresencePortProvider.overrideWithValue(E2eUserPresencePort()),
          ],
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        failure: 'Fresh App A onboarding did not load.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(onboardingProvider).supportsPhoneOtpRegistration &&
            container.read(onboardingProvider).canRegisterSelectedDidMethod,
        failure: 'App A phone registration did not become available.',
      );
      final onboarding = container.read(onboardingProvider.notifier);
      await onboarding.requestOtp(
        phone: account.phone,
        handle: handle,
        handleDomain: config.didDomain,
      );
      final verification = container.read(onboardingProvider);
      if (verification.otpTargetFullHandle != '$handle.${config.didDomain}' ||
          verification.otpTargetPhone == null ||
          verification.isPhoneOtpConsumed) {
        fail('App A registration OTP did not bind the requested Handle.');
      }
      // Exercise the owning production registration orchestration; all new PIN
      // steps below use the visible production surfaces and native adapter.
      var registrationDone = false;
      IdentityRegistrationStatus? registrationStatus;
      final registration = onboarding
          .registerWithPhone(
            phone: account.phone,
            otp: account.fixedOtp,
            handle: handle,
            handleDomain: config.didDomain,
            nickName: 'PIN App A',
            profileMarkdown: '# PIN App A\n',
          )
          .then((status) {
            registrationStatus = status;
            registrationDone = true;
          });
      await _pumpUntil(
        tester,
        () => registrationDone,
        timeout: const Duration(seconds: 90),
        failure: 'App A registration did not return within its deadline.',
      );
      await registration;
      if (registrationStatus != IdentityRegistrationStatus.registered) {
        final state = container.read(onboardingProvider);
        final code = safeAppPairFailureCode(state.phoneRegistrationFailureCode);
        final category = safeAppPairFailureCode(
          container.read(uiFeedbackProvider)?.message.id.toLowerCase(),
        );
        fail(
          'App A registration did not complete '
          '(outcome=${state.phoneRegistrationOutcome.name},'
          'code=$code,category=$category).',
        );
      }
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('pin-backup-skip')).evaluate().length == 1,
        timeout: const Duration(seconds: 90),
        failure: 'New identity did not offer optional PIN backup.',
      );
      final identity = container.read(sessionProvider).session!;
      final did = identity.did;
      await config.coordinator.publish(
        'admin',
        'cleanup_scope',
        data: {'accountId': _requireAppPairAccountId(container)},
      );
      final registry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(did);
      final oldDevice = _requireAppReadyBootstrapAdmin(registry);
      final methods = await _pinPublicMethods(did);
      await _pinTap(tester, 'pin-backup-skip');
      await tester.pump(const Duration(milliseconds: 300));
      if ((await bootstrap.pinRecoveryCorePort!.listPending()).isNotEmpty) {
        fail('Skipping backup created an operation.');
      }
      if (identity.localIdentityId == null ||
          (await bootstrap.pinRecoveryCorePort!.backupStatus(
                identity.localIdentityId!,
              )).state !=
              PinBackupState.notEnabled) {
        fail('Skipped initial backup was not authoritatively disabled.');
      }
      if (container.read(sessionProvider).session?.did != did) {
        fail('Skipping backup lost the new identity.');
      }
      final context = tester.element(find.byType(AppShell));
      unawaited(
        Navigator.of(
          context,
        ).push(CupertinoPageRoute<void>(builder: (_) => const SettingsPage())),
      );
      await tester.pump();
      await _pinTap(tester, 'settings-pin-backup-row');
      await _pinVerifySelect(tester, account, '$handle.${config.didDomain}');
      await _pinFill(tester, 'pin-recovery-pin', fixture.pin);
      await _pinFill(tester, 'pin-recovery-pin-confirm', fixture.pin);
      await _pinTap(tester, 'pin-recovery-submit-pin');
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('pin-recovery-done')).evaluate().length == 1,
        timeout: const Duration(minutes: 2),
        failure: 'Three-Realm backup did not activate.',
      );
      await config.coordinator.publish(
        'admin',
        'pin_backup_ready',
        data: {
          'did': did,
          'fullHandle': '$handle.${config.didDomain}',
          'oldDevice': oldDevice,
          'publicMethods': methods,
        },
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      bootstrap = null;
      await config.coordinator.publish('admin', 'pin_old_runtime_offline');
      await config.coordinator.waitFor(
        'joiner',
        'pin_new_device_authenticated',
        timeout: const Duration(minutes: 5),
      );
      final v4 = await config.coordinator.waitFor(
        'joiner',
        'pin_v4_new_backup_ready',
        timeout: const Duration(minutes: 5),
      );
      final currentDid = _required(v4, 'did');
      if (currentDid == did) fail('V4 did not replace the original DID.');
      final newRoot = '${config.adminStateRoot}-v4';
      await Directory(newRoot).create(recursive: true);
      _requireIndependentEmptyPaths([newRoot]);
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(
          config,
          enableRootTransfer: true,
          enableMessageSyncCore: true,
        ),
        appStateRoot: newRoot,
        pinRecoveryTenants: fixture.tenants,
      );
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: [
            userPresencePortProvider.overrideWithValue(E2eUserPresencePort()),
          ],
        ),
      );
      await _pinTap(tester, 'pin-recovery-entry');
      await _pinVerifySelect(tester, account, '$handle.${config.didDomain}');
      await _pinFill(tester, 'pin-recovery-pin', fixture.pin);
      await _pinTap(tester, 'pin-recovery-submit-pin');
      await _pinTap(tester, 'pin-recovery-confirm-device');
      await _pinTap(tester, 'pin-recovery-enter');
      final v4Container = await _waitForAuthenticatedApp(
        tester,
        expectedDid: currentDid,
      );
      final v4Registry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(currentDid);
      if (v4Registry.devices.length != 2 || v4Registry.currentDevice == null) {
        fail('Fresh App A did not rejoin the new V4 root.');
      }
      final v4Methods = await _pinPublicMethods(currentDid);
      final beforeV4Join = Map<String, String>.from(v4['publicMethods'] as Map);
      if (beforeV4Join.entries.any((e) => v4Methods[e.key] != e.value)) {
        fail('New-root PIN recovery changed existing root/device methods.');
      }
      if (v4Container.read(sessionProvider).session?.did != currentDid) {
        fail('Fresh App A activated a stale root.');
      }
      await config.coordinator.publish(
        'admin',
        'pin_v4_rejoined',
        data: {'deviceId': v4Registry.currentDevice!.protocolDeviceId},
      );
      // Every PIN/V4 request has finished before the phone gains its second
      // disposable owner for Direct messaging. Both accounts enter the ledger.
      final messageDid = currentDid;
      await v4Container
          .read(appRuntimeProvider.notifier)
          .prepareIdentityActivation(isCurrent: () => true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final peerHandle = _uniqueHandle(config.handlePrefix);
      await config.coordinator.publish(
        'admin',
        'pin_peer_registration_intent',
        data: {'handle': peerHandle},
      );
      final peerOtp = await _requestAppRegistrationOtp(
        bootstrap: bootstrap,
        config: config,
        account: account,
        handle: peerHandle,
      );
      final peerRegistration = await bootstrap.onboardingService!
          .registerHandleWithPhone(
            phone: account.phone,
            otp: peerOtp,
            handle: peerHandle,
            nickName: 'PIN Direct peer',
          );
      final peer = peerRegistration.identity;
      if (peer == null ||
          peerRegistration.status != IdentityRegistrationStatus.registered) {
        fail('Direct peer registration did not complete.');
      }
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: [
            userPresencePortProvider.overrideWithValue(E2eUserPresencePort()),
          ],
        ),
      );
      final peerContainer = await _waitForAuthenticatedApp(
        tester,
        expectedDid: peer.did,
      );
      await config.coordinator.publish(
        'admin',
        'cleanup_peer',
        data: {'accountId': _requireAppPairAccountId(peerContainer)},
      );
      final route = await bootstrap.directoryApplicationService!.resolvePeer(
        messageDid,
      );
      final conversationId = route.conversationId;
      if (conversationId == null) fail('Direct peer has no canonical route.');
      await config.coordinator.publish(
        'admin',
        'pin_peer_ready',
        data: {'peerDid': peer.did},
      );
      final outbound = await config.coordinator.waitFor(
        'joiner',
        'pin_outbound',
        timeout: const Duration(minutes: 2),
      );
      final outboundText = _appPairMessage(config.runId, 'pin-joined-outbound');
      await _waitForAppPairMessage(
        container: peerContainer,
        messaging: bootstrap.messagingService!,
        conversationId: conversationId,
        content: outboundText,
        messageId: _required(outbound, 'messageId'),
        senderDid: messageDid,
        receiverDid: peer.did,
        isMine: false,
      );
      await _openAppPairConversation(
        tester: tester,
        conversationId: conversationId,
        content: outboundText,
      );
      final reply = await bootstrap.messagingService!.sendConversationText(
        conversation: AppConversationReadRef.fromConversationId(conversationId),
        content: _appPairMessage(config.runId, 'pin-peer-reply'),
      );
      if (reply.sendState != MessageSendState.sent || reply.remoteId == null) {
        fail('Direct peer reply was not committed.');
      }
      await config.coordinator.publish(
        'admin',
        'pin_reply',
        data: {'messageId': reply.remoteId!},
      );
      await config.coordinator.waitFor(
        'joiner',
        'pin_roundtrip_visible',
        timeout: const Duration(minutes: 2),
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

void _pinAppJoinerMain() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'PIN restores original identity and confirms a new device in App B',
    (tester) async {
      final config = _AppPairRunConfig.load();
      final fixture = _pinFixture();
      final account = _DedicatedAccount.fromProtectedConfig(
        config.localConfigPath,
      );
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1320, 820));
      _requireIndependentEmptyPaths([config.joinerStateRoot]);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await tester.binding.setSurfaceSize(null);
      });
      final ready = await config.coordinator.waitFor(
        'admin',
        'pin_backup_ready',
        timeout: const Duration(minutes: 4),
      );
      await config.coordinator.waitFor(
        'admin',
        'pin_old_runtime_offline',
        timeout: const Duration(minutes: 1),
      );
      final did = _required(ready, 'did'),
          fullHandle = _required(ready, 'fullHandle');
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(
          config,
          enableRootTransfer: true,
          enableMessageSyncCore: true,
        ),
        appStateRoot: config.joinerStateRoot,
        pinRecoveryTenants: fixture.tenants,
      );
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: [
            userPresencePortProvider.overrideWithValue(E2eUserPresencePort()),
          ],
        ),
      );
      await _pinTap(tester, 'pin-recovery-entry');
      await _pinVerifySelect(
        tester,
        account,
        fullHandle,
        deviceLabel: 'PIN Joiner B',
      );
      final wrongPin = fixture.pin == '0000' ? '0001' : '0000';
      await _pinFill(tester, 'pin-recovery-pin', wrongPin);
      await _pinTap(tester, 'pin-recovery-submit-pin');
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('pin-recovery-error')).evaluate().isNotEmpty,
        timeout: const Duration(minutes: 1),
        failure: 'Wrong PIN did not show a safe failure.',
      );
      final pending = await bootstrap.pinRecoveryCorePort!.listPending();
      if (pending.length != 1 ||
          pending.single.attemptsUsed != 1 ||
          (await bootstrap.identityCorePort!.listLocalIdentities())
              .isNotEmpty) {
        fail(
          'Wrong PIN created an identity or did not consume exactly one attempt.',
        );
      }
      await _pinFill(tester, 'pin-recovery-pin', fixture.pin);
      await _pinTap(tester, 'pin-recovery-submit-pin');
      await _pumpUntil(
        tester,
        () =>
            find
                .byKey(const Key('pin-recovery-confirm-device'))
                .evaluate()
                .length ==
            1,
        timeout: const Duration(minutes: 2),
        failure: 'Correct PIN did not reach explicit device confirmation.',
      );
      if ((await bootstrap.identityCorePort!.listLocalIdentities())
          .isNotEmpty) {
        fail('Root recovery activated a device before confirmation.');
      }
      final deviceConfirmation =
          tester
              .widget<Text>(
                find.byKey(const Key('pin-recovery-device-label-confirmed')),
              )
              .data ??
          '';
      if (!deviceConfirmation.contains('PIN Joiner B')) {
        fail('Device confirmation did not show the Core-fixed device name.');
      }
      await _pinTap(tester, 'pin-recovery-confirm-device');
      await _pinTap(tester, 'pin-recovery-enter');
      final container = await _waitForAuthenticatedApp(
        tester,
        expectedDid: did,
      );
      final registry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(did);
      final current = registry.currentDevice;
      if (current == null ||
          current.protocolDeviceId == _required(ready, 'oldDevice') ||
          !current.managementReady ||
          registry.devices.length != 2 ||
          !registry.devices.any(
            (d) =>
                d.protocolDeviceId == _required(ready, 'oldDevice') &&
                d.status == DeviceStatus.active,
          )) {
        fail('Original DID device enrollment did not preserve both devices.');
      }
      final before = Map<String, String>.from(ready['publicMethods'] as Map);
      final after = await _pinPublicMethods(did);
      if (before.entries.any((e) => after[e.key] != e.value)) {
        fail('PIN Join changed an existing public/root verification key.');
      }
      if (container.read(sessionProvider).session?.jwtToken?.isNotEmpty !=
          true) {
        fail('New device was not authenticated by production Core.');
      }
      await config.coordinator.publish(
        'joiner',
        'pin_new_device_authenticated',
        data: {
          'operationId': pending.single.operationId,
          'deviceId': current.protocolDeviceId,
        },
      );
      await _pinOpenSettings(tester);
      await _pinTap(tester, 'settings-pin-backup-row');
      await _pinTap(tester, 'pin-recovery-forgot');
      await _pinTap(tester, 'pin-recovery-v4-action');
      await _pinWrappedFill(
        tester,
        'handle-recovery-phone-input',
        account.phone,
      );
      await _pinTap(tester, 'handle-recovery-send-otp');
      await _pinWrappedFill(tester, 'handle-recovery-otp', account.fixedOtp);
      await _pinTap(tester, 'handle-recovery-verify');
      await _pinTap(tester, 'handle-recovery-risk-confirmation');
      await _pinTap(tester, 'handle-recovery-activate');
      await _pinTap(tester, 'handle-recovery-enter-messages');
      await _pinTap(tester, 'pin-backup-skip');
      final v4Container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final replacement = v4Container.read(sessionProvider).session;
      if (replacement == null ||
          replacement.did == did ||
          replacement.localIdentityId == null) {
        fail('V4 did not activate a new identity.');
      }
      final newDid = replacement.did;
      final afterSkip = await bootstrap.pinRecoveryCorePort!.backupStatus(
        replacement.localIdentityId!,
      );
      if (afterSkip.state != PinBackupState.notEnabled ||
          (await bootstrap.pinRecoveryCorePort!.listPending()).any(
            (p) => p.target.did == newDid,
          )) {
        fail('Skipping the V4 backup created a backup or pending operation.');
      }
      await _pinEnableFromSettings(tester, account, fullHandle, fixture.pin);
      final newMethods = await _pinPublicMethods(newDid);
      await _pinTap(tester, 'pin-recovery-done');
      Navigator.of(tester.element(find.byType(SettingsPage))).pop();
      await tester.pump();
      await config.coordinator.publish(
        'joiner',
        'pin_v4_new_backup_ready',
        data: {'did': newDid, 'publicMethods': newMethods},
      );
      await config.coordinator.waitFor(
        'admin',
        'pin_v4_rejoined',
        timeout: const Duration(minutes: 3),
      );
      final peerReady = await config.coordinator.waitFor(
        'admin',
        'pin_peer_ready',
        timeout: const Duration(minutes: 3),
      );
      final peerDid = _required(peerReady, 'peerDid');
      final route = await bootstrap.directoryApplicationService!.resolvePeer(
        peerDid,
      );
      final conversationId = route.conversationId;
      if (conversationId == null) {
        fail('Recovered App has no canonical Direct peer route.');
      }
      final outbound = await bootstrap.messagingService!.sendConversationText(
        conversation: AppConversationReadRef.fromConversationId(conversationId),
        content: _appPairMessage(config.runId, 'pin-joined-outbound'),
      );
      if (outbound.sendState != MessageSendState.sent ||
          outbound.remoteId == null ||
          outbound.senderDid != newDid) {
        fail('Recovered App did not commit its new Direct message.');
      }
      await config.coordinator.publish(
        'joiner',
        'pin_outbound',
        data: {'messageId': outbound.remoteId!},
      );
      final reply = await config.coordinator.waitFor(
        'admin',
        'pin_reply',
        timeout: const Duration(minutes: 2),
      );
      final replyText = _appPairMessage(config.runId, 'pin-peer-reply');
      await _waitForAppPairMessage(
        container: v4Container,
        messaging: bootstrap.messagingService!,
        conversationId: conversationId,
        content: replyText,
        messageId: _required(reply, 'messageId'),
        senderDid: peerDid,
        receiverDid: newDid,
        isMine: false,
      );
      await _openAppPairConversation(
        tester: tester,
        conversationId: conversationId,
        content: replyText,
      );
      await config.coordinator.publish('joiner', 'pin_roundtrip_visible');
      await E2eCaseAttestationWriter.markPassed(
        _pinAppCaseId,
        phases: const [
          'two_independent_native_vaults',
          'backup_offer_skip_created_no_operation',
          'three_realm_backup_completed',
          'old_app_runtime_offline_during_recovery',
          'wrong_pin_counted_once_no_identity',
          'same_did_new_device_confirmed',
          'root_and_existing_device_preserved',
          'new_device_authenticated',
          'v4_new_root_offer_skipped_without_backup',
          'v4_new_root_backup_and_fresh_app_recovery',
          'new_direct_roundtrip_visible',
        ],
      );
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
