part of 'multi_device_join_ui_test.dart';

void _registerDshDeviceJoinInteropTest() {
  testWidgets(
    'AWiki Me joins a Handle created and managed by DSH',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromConfig(config);
      final dshStateRoot = config.dshStateRoot;
      _requireIndependentEmptyPaths(<String>[
        config.dshAppStateRoot,
        dshStateRoot,
      ]);
      final dsh = await _DshE2eDriver.start(
        config: config,
        stateRoot: dshStateRoot,
      );
      AppBootstrap? bootstrap;
      var handle = '';
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await dsh.close();
        await _deleteDirectory(config.dshAppStateRoot);
        await _deleteDirectory(dshStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      handle = _uniqueHandle('${config.handlePrefix}dsh');
      final registration = await dsh.hostValue('register', <String, Object?>{
        'handle': handle,
        'phone': account.phone,
        'otp': account.fixedOtp,
      });
      final identity = _DshE2eDriver.map(registration, 'identity');
      final did = _DshE2eDriver.string(identity, 'did');
      if (registration['status'] != 'registered') {
        fail('DSH did not create the bootstrap Handle.');
      }
      final initial = await dsh.hostValue('device_refresh');
      if (initial['canManage'] != true ||
          initial['role'] != 'admin' ||
          initial['readiness'] != 'admin_ready') {
        fail('DSH bootstrap device was not ready-admin.');
      }

      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.dshAppStateRoot,
      );
      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The joining App did not open onboarding.',
      );
      await _pumpUntil(
        tester,
        () =>
            find.bySemanticsIdentifier('e2e-phone-input').evaluate().length ==
                1 &&
            find.bySemanticsIdentifier('e2e-handle-input').evaluate().length ==
                1 &&
            find.bySemanticsIdentifier('e2e-otp-input').evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The joining App onboarding phone form was unavailable.',
      );
      await _enterText(tester, 'e2e-phone-input', account.phone);
      await _enterText(tester, 'e2e-handle-input', handle);
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-send-otp-button'),
        failure: 'The App could not request its registration OTP.',
      );
      await _pumpUntil(
        tester,
        () => find.bySemanticsIdentifier('e2e-otp-sent').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
        failure: 'The App registration OTP was not accepted.',
      );
      await _enterText(tester, 'e2e-otp-input', account.fixedOtp);
      final macSubmit = find.byKey(
        const Key('onboarding-mac-phone-submit-action'),
      );
      await _tapOne(
        tester,
        macSubmit.evaluate().isNotEmpty
            ? macSubmit
            : find.byKey(const Key('onboarding-phone-submit-action')),
        failure: 'The App could not consume its registration OTP.',
      );
      await _pumpUntil(
        tester,
        () => find
            .byKey(const Key('existing-handle-join-action'))
            .evaluate()
            .isNotEmpty,
        timeout: const Duration(seconds: 45),
        failure: 'The DSH-created Handle did not expose ordinary Join.',
      );
      await _tapOne(
        tester,
        find.byKey(const Key('existing-handle-join-action')),
        failure: 'The App ordinary Join action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinPage).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The App did not open Device Join.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceJoinPage)),
      );
      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          return progress?.side == DeviceJoinSide.newDevice &&
              progress?.phase == DeviceJoinPhase.pending &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The App did not remain pending without SAS.',
      );
      final pending = container.read(devicesProvider).activeJoin!;

      final request = await dsh.waitForSingleRequest();
      final requestRef = _DshE2eDriver.string(request, 'requestRef');
      final started = await dsh.hostValue('device_start', <String, Object?>{
        'requestRef': requestRef,
      });
      if (started['phase'] != 'verifying' || started.containsKey('sas')) {
        fail('DSH exposed SAS before response verification.');
      }
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('device-join-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The App did not derive its Join SAS.',
      );
      final appSas =
          tester.widget<Text>(find.byKey(const Key('device-join-sas'))).data ??
          '';
      if (!_validSas(appSas)) {
        fail('The App produced a malformed SAS.');
      }
      final dshSas = await dsh.waitForSas(requestRef);
      if (!_constantTimeAsciiEquals(appSas, dshSas)) {
        fail('The independently derived App and DSH SAS values did not match.');
      }
      final approved = await dsh.hostValue('device_approve', <String, Object?>{
        'requestRef': requestRef,
        'enteredSas': appSas,
        'confirmation': 'APPROVE',
      });
      if (approved['phase'] != 'authorized') {
        fail('DSH did not authorize the App as member.');
      }
      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          final device = progress?.authorizedDevice;
          return progress?.joinSessionId == pending.joinSessionId &&
              progress?.phase == DeviceJoinPhase.authorized &&
              progress?.remoteState == DeviceJoinRemoteState.consumed &&
              progress?.sas == null &&
              device?.role == DeviceRole.member &&
              device?.managementReady == false &&
              device?.isCurrent == true;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The App did not activate as the current member.',
      );
      await _pumpUntil(
        tester,
        () => container.read(sessionProvider).session?.did == did,
        timeout: const Duration(seconds: 45),
        failure: 'The App did not activate the DSH-created DID.',
      );

      final finalSnapshot = await dsh.hostValue('device_refresh');
      final devices = _DshE2eDriver.maps(finalSnapshot, 'devices');
      final appDevices = devices
          .where(
            (device) =>
                device['isCurrent'] == false &&
                device['status'] == 'active' &&
                device['role'] == 'member' &&
                device['managementReady'] == false,
          )
          .toList(growable: false);
      if (devices.length != 2 || appDevices.length != 1) {
        fail('DSH Registry did not converge to one admin and one App member.');
      }
      final revoked = await dsh.hostValue('device_revoke', <String, Object?>{
        'deviceRef': _DshE2eDriver.string(appDevices.single, 'deviceRef'),
        'confirmation': 'REVOKE',
      });
      final admins = devices
          .where((device) => device['isCurrent'] == true)
          .toList();
      if (admins.length != 1)
        fail('DSH Registry did not contain one current admin.');
      void requireExactSurvivingAdmin(Map<String, Object?> snapshot) {
        final remaining = _DshE2eDriver.maps(snapshot, 'devices');
        if (remaining.length != 1 ||
            remaining.single['deviceRef'] != admins.single['deviceRef'] ||
            remaining.single['isCurrent'] != true ||
            remaining.single['status'] != 'active' ||
            remaining.single['role'] != 'admin' ||
            remaining.single['managementReady'] != true) {
          fail(
            'DSH active-device projection did not remove the member and preserve the exact ready admin.',
          );
        }
      }

      requireExactSurvivingAdmin(revoked);
      requireExactSurvivingAdmin(await dsh.hostValue('device_refresh'));

      await E2eCaseAttestationWriter.markPassed(
        _dshAdminJoinCaseId,
        phases: const <String>[
          'dsh_bootstrap_ready_admin',
          'app_ordinary_join_left_pending',
          'sas_matched_without_secret_evidence',
          'dsh_foreground_member_approval_completed',
          'app_joined_as_member',
          'dsh_revoked_member',
          'residual_identity_declared_by_suite_policy',
        ],
      );
    },
    skip:
        !_RemoteJoinRunConfig.exists() ||
        !_invocationExpects(_dshAdminJoinCaseId),
    timeout: const Timeout(Duration(minutes: 18)),
  );
}

class _DshE2eDriver {
  _DshE2eDriver(this._process, this._lines, this._stderrDrain);

  final Process _process;
  final StreamIterator<String> _lines;
  final Future<void> _stderrDrain;

  static Future<_DshE2eDriver> start({
    required _RemoteJoinRunConfig config,
    required String stateRoot,
  }) async {
    final repo = Directory(config.dshRepoRoot);
    final driver = File('${repo.path}/scripts/device-join-e2e.mjs');
    final built = File('${repo.path}/lib/index.js');
    if (!driver.existsSync() || !built.existsSync()) {
      fail('The DSH Device Join source and build are required.');
    }
    for (final value in <String>[
      config.userServiceUrl,
      config.messageServiceUrl,
      config.baseUrl,
    ]) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || uri.host != 'awiki.info') {
        fail('DSH E2E writes require exact awiki.info endpoints.');
      }
    }
    final process = await Process.start(
      'node',
      <String>[driver.path],
      workingDirectory: repo.path,
      environment: <String, String>{...Platform.environment},
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrDrain = process.stderr.drain<void>();
    final instance = _DshE2eDriver(process, lines, stderrDrain);
    instance._write(<String, Object?>{
      'stateRoot': stateRoot,
      'didDomain': 'awiki.info',
      'userServiceUrl': config.userServiceUrl,
      'messageServiceUrl': config.messageServiceUrl,
      'messageServicePublicUrl': config.messageServiceUrl,
      'messageServiceDid': 'did:wba:awiki.info',
      'realtimeEnabled': true,
      'listenerEnabled': false,
      'listenerAllowedPeers': <String>[],
    });
    final ready = await instance._read();
    if (ready['ok'] != true || ready['ready'] != true) {
      await instance.close();
      fail('The DSH Device Join driver did not become ready.');
    }
    return instance;
  }

  void _write(Map<String, Object?> value) {
    _process.stdin.writeln(jsonEncode(value));
  }

  Future<Map<String, Object?>> _read() async {
    final moved = await _lines.moveNext().timeout(const Duration(seconds: 45));
    if (!moved) {
      fail('The DSH Device Join driver closed unexpectedly.');
    }
    final line = _lines.current;
    if (utf8.encode(line).length > 64 * 1024) {
      fail('The DSH Device Join driver returned oversized output.');
    }
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      fail('The DSH Device Join driver returned invalid JSON.');
    }
    return decoded.cast<String, Object?>();
  }

  Future<Map<String, Object?>> command(
    String action, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) async {
    _write(<String, Object?>{'action': action, ...fields});
    final response = await _read();
    if (response['ok'] != true || response['result'] is! Map) {
      final rawCode = response['code'];
      final safeCode =
          rawCode is String && RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(rawCode)
          ? rawCode
          : 'operation_failed';
      fail('The DSH Device Join command $action failed ($safeCode).');
    }
    return (response['result']! as Map).cast<String, Object?>();
  }

  Future<Map<String, Object?>> hostValue(
    String action, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) async {
    final result = await command(action, fields);
    if (result['ok'] != true || result['value'] is! Map) {
      fail('The DSH Host operation failed.');
    }
    return (result['value']! as Map).cast<String, Object?>();
  }

  Future<Map<String, Object?>> waitForSingleRequest() async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    var lastRequests = const <Map<String, Object?>>[];
    while (DateTime.now().isBefore(deadline)) {
      final snapshot = await hostValue('device_refresh');
      final requests = maps(snapshot, 'requests');
      lastRequests = requests;
      if (requests.length == 1 &&
          (requests.single['canStartVerification'] == true ||
              requests.single['claimedByCurrentDevice'] == true)) {
        return requests.single;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail(
      'DSH did not discover exactly one local Join request '
      '(count=${lastRequests.length}, states=${lastRequests.map((request) => <String, Object?>{'canStart': request['canStartVerification'] == true, 'claimed': request['claimedByCurrentDevice'] == true}).toList()}).',
    );
  }

  Future<String> waitForSas(String requestRef) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await hostValue('device_refresh');
      final progress = await hostValue('device_start', <String, Object?>{
        'requestRef': requestRef,
      });
      final sas = progress['sas'];
      if (progress['phase'] == 'sas-ready' && sas is String && _validSas(sas)) {
        return sas;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail('DSH did not derive its SAS from local verification progress.');
  }

  Future<void> close() async {
    if (_process.pid <= 0) return;
    try {
      _write(const <String, Object?>{'action': 'close'});
      await _read();
    } on Object {
      _process.kill();
    }
    await _process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _process.kill();
        return _process.exitCode;
      },
    );
    await _stderrDrain;
    await _lines.cancel();
  }

  static Map<String, Object?> map(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! Map) fail('The DSH result omitted $key.');
    return value.cast<String, Object?>();
  }

  static List<Map<String, Object?>> maps(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value is! List || value.any((item) => item is! Map)) {
      fail('The DSH result omitted $key.');
    }
    return value
        .map((item) => (item as Map).cast<String, Object?>())
        .toList(growable: false);
  }

  static String string(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is! String || value.isEmpty) {
      fail('The DSH result omitted $key.');
    }
    return value;
  }
}
