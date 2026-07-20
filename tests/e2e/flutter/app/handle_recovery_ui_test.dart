// [INPUT]: Audited awiki.info endpoints, two dedicated SMS accounts, an exact
//          CLI peer, independent native Core roots, and real LocalAuthentication.
// [OUTPUT]: Secret-free attestations for durable old-admin cancellation and
//           requester cooling/reconfirmation/replacement-DID activation.
// [POS]: Activation-gated Step 09 product E2E; no fake Core/port, copied state,
//        staged SMS-error continuation, or secret-bearing evidence is allowed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/data/services/local_auth_user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';

import '../../case_attestation.dart';
import '../../remote_multi_device_join_contract.dart';

const String _coolingCaseId = 'HANDLE-RECOVERY-E2E-001';
const String _cancelCaseId = 'HANDLE-RECOVERY-E2E-002';
const String _runConfigPath =
    '.e2e/multi-device-remote-recovery/current/run_config.json';
const String _activationGate = 'AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED';
const String _primaryPhoneEnv = 'AWIKI_MULTI_DEVICE_E2E_PHONE';
const String _peerPhoneEnv = 'AWIKI_MULTI_DEVICE_E2E_PEER_PHONE';
const String _otpCommandEnv = 'AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON';
const String _genesisPurpose = 'awiki.device.genesis.v1';
const String _beginPurpose = 'awiki.device.recovery.begin.v1';
const String _finalizePurpose = 'awiki.device.recovery.finalize.v1';
const Duration _remoteTimeout = Duration(seconds: 30);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'old ready admin durably receives and cancels Handle Recovery',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final config = _RemoteRecoveryRunConfig.load();
      final accounts = _DedicatedAccounts.fromEnvironment();
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      final cli = _RecoveryCli(config);
      final appRoot = '${config.appStateRoot}/cancel-old-admin';
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireFreshPaths(<String>[
        appRoot,
        config.cliWorkspace,
        config.cliHome,
      ]);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await cli.deleteLocalState();
        await _deleteDirectory(appRoot);
        await tester.binding.setSurfaceSize(null);
      });
      await _requireRealUserPresence();

      bootstrap = await AppBootstrap.create(
        environment: _environment(config),
        appStateRoot: appRoot,
      );
      final handle = _uniqueHandle('${config.handlePrefix}cancel');
      final adminSession = await _registerReadyAdmin(
        client: httpClient,
        config: config,
        account: accounts.primary,
        bootstrap: bootstrap,
        handle: handle,
      );
      final oldDid = adminSession.did;
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );
      var container = await _mountAuthenticatedApp(
        tester: tester,
        bootstrap: bootstrap,
        session: adminSession,
        presence: presence,
      );

      await cli.initialize();
      final beginOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: accounts.primary,
        purpose: _beginPurpose,
        handle: handle,
      );
      final beginGrant = await _exchangeRecoveryGrant(
        client: httpClient,
        config: config,
        account: accounts.primary,
        purpose: _beginPurpose,
        handle: handle,
        otp: beginOtp,
      );
      final begun = await cli.begin(
        canonicalHandle: '$handle.${config.didDomain}',
        verificationGrant: beginGrant,
      );
      _requireCooling(begun, expectedOldDid: oldDid);
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );

      final notice = await _waitForDurableNotice(
        tester: tester,
        bootstrap: bootstrap,
        oldDid: oldDid,
        recoverySessionId: begun.recoverySessionId,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      bootstrap = null;

      bootstrap = await AppBootstrap.create(
        environment: _environment(config),
        appStateRoot: appRoot,
      );
      final restored = await bootstrap.appSessionService!.restoreSession();
      if (restored == null || restored.did != oldDid) {
        fail('The old admin identity did not survive the App restart.');
      }
      final persisted = await bootstrap.handleRecoveryPort!
          .listOldAdminRecoveryNotices(oldDid);
      if (persisted.length != 1 ||
          !_sameNotice(persisted.single, notice) ||
          persisted.single.recoverySessionId != begun.recoverySessionId) {
        fail('The Recovery warning was not durably restored after restart.');
      }
      container = await _mountAuthenticatedApp(
        tester: tester,
        bootstrap: bootstrap,
        session: restored,
        presence: presence,
      );
      await _openDevices(tester);
      await _pumpUntil(
        tester,
        () =>
            container
                .read(handleRecoveryProvider)
                .oldAdminNotices
                .where((value) => value.eventId == notice.eventId)
                .length ==
            1,
        timeout: const Duration(seconds: 30),
        failure: 'The durable Recovery warning was not visible after restart.',
      );

      await _tapOne(
        tester,
        find.byKey(Key('handle-recovery-cancel-${notice.eventId}')),
        failure: 'The old-admin Recovery cancel action was unavailable.',
      );
      await _tapOne(
        tester,
        find.byKey(const Key('handle-recovery-cancel-confirm')),
        failure: 'The explicit Recovery cancel confirmation was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          if (presence.calls > 1) {
            fail(
              'Recovery cancellation requested user presence more than once.',
            );
          }
          return presence.completions == 1 &&
              presence.lastResult &&
              find
                  .byKey(const Key('handle-recovery-admin-section'))
                  .evaluate()
                  .isEmpty;
        },
        timeout: const Duration(minutes: 2),
        failure:
            'The old admin did not complete Recovery cancellation after real user presence.',
      );
      if (presence.calls != 1 ||
          presence.completions != 1 ||
          !presence.lastResult) {
        fail(
          'Recovery cancellation did not use exactly one real user presence.',
        );
      }

      final cancelled = await cli.status(begun.recoverySessionId);
      _requireCancelled(cancelled, expectedOldDid: oldDid);
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );
      await _requireCancelledFinalizeRejected(
        client: httpClient,
        config: config,
        account: accounts.primary,
        cli: cli,
        handle: handle,
        recoverySessionId: begun.recoverySessionId,
      );
      final finalStatus = await cli.status(begun.recoverySessionId);
      _requireCancelled(finalStatus, expectedOldDid: oldDid);
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );

      await E2eCaseAttestationWriter.markPassed(
        _cancelCaseId,
        startedAt: startedAt,
        phases: const <String>[
          'independent_native_roots_created',
          'recovery_started_without_cutover',
          'durable_notice_survived_app_restart',
          'single_real_user_presence_cancelled',
          'cancelled_finalize_rejected',
          'old_handle_binding_preserved',
        ],
      );
    },
    skip: !Platform.isMacOS || !_RemoteRecoveryRunConfig.exists(),
    timeout: const Timeout(Duration(minutes: 16)),
  );

  testWidgets(
    'new App device completes real cooling and activates a replacement DID',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final config = _RemoteRecoveryRunConfig.load();
      final accounts = _DedicatedAccounts.fromEnvironment();
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      final oldRoot = '${config.appStateRoot}/success-old-admin';
      final requesterRoot = '${config.appStateRoot}/success-requester';
      AppBootstrap? oldBootstrap;
      AppBootstrap? requesterBootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireFreshPaths(<String>[oldRoot, requesterRoot]);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await requesterBootstrap?.dispose();
        await oldBootstrap?.dispose();
        await _deleteDirectory(requesterRoot);
        await _deleteDirectory(oldRoot);
        await tester.binding.setSurfaceSize(null);
      });
      await _requireRealUserPresence();

      oldBootstrap = await AppBootstrap.create(
        environment: _environment(config),
        appStateRoot: oldRoot,
      );
      final handle = _uniqueHandle('${config.handlePrefix}finish');
      final oldSession = await _registerReadyAdmin(
        client: httpClient,
        config: config,
        account: accounts.peer,
        bootstrap: oldBootstrap,
        handle: handle,
      );
      final oldDid = oldSession.did;
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );
      await oldBootstrap.dispose();
      oldBootstrap = null;

      requesterBootstrap = await AppBootstrap.create(
        environment: _environment(config),
        appStateRoot: requesterRoot,
      );
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: requesterBootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        failure: 'The Recovery requester onboarding surface did not open.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );

      await tester.enterText(
        find.bySemanticsIdentifier('e2e-handle-input'),
        handle,
      );
      await tester.enterText(
        find.bySemanticsIdentifier('e2e-phone-input'),
        accounts.peer.phone,
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-send-otp-button'),
        failure: 'The Recovery begin OTP action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.bySemanticsIdentifier('e2e-otp-sent').evaluate().length == 1,
        timeout: const Duration(seconds: 90),
        failure: 'The Recovery begin SMS was not accepted by the product path.',
      );
      final beginOtp = await _resolveOtp(
        account: accounts.peer,
        purpose: _beginPurpose,
        handle: handle,
        didDomain: config.didDomain,
      );
      await tester.enterText(
        find.bySemanticsIdentifier('e2e-otp-input'),
        beginOtp,
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-login-next-button'),
        failure: 'The Recovery begin next action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () =>
            find
                .bySemanticsIdentifier('e2e-complete-login-button')
                .evaluate()
                .length ==
            1,
        failure: 'The Recovery begin confirmation step did not open.',
      );
      final beginSubmittedAt = DateTime.now().toUtc();
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-complete-login-button'),
        failure: 'The Recovery begin confirmation was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          final active = container.read(handleRecoveryProvider).activeRequester;
          return active?.phase == HandleRecoveryPhase.cooling;
        },
        timeout: const Duration(seconds: 45),
        failure: 'Recovery did not enter its cooling phase.',
      );
      final begun = container.read(handleRecoveryProvider).activeRequester!;
      _requireAppCooling(
        begun,
        expectedOldDid: oldDid,
        beginSubmittedAt: beginSubmittedAt,
      );
      if (container.read(sessionProvider).session != null ||
          container.read(appRuntimeProvider).activatedDid != null) {
        fail('Recovery begin activated an identity before finalize.');
      }
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );

      final ready = await _waitForReady(
        tester: tester,
        container: container,
        initial: begun,
        maxCoolingSeconds: config.maxCoolingSeconds,
      );
      if (ready.oldDid != oldDid ||
          ready.newDid != null ||
          ready.localActivationPending ||
          container.read(sessionProvider).session != null) {
        fail('Recovery ready state changed identity before finalize.');
      }
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: oldDid,
      );

      await _tapOne(
        tester,
        find.bySemanticsIdentifier('handle-recovery-send-final-otp'),
        failure: 'The independent Recovery OTP action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => container.read(handleRecoveryProvider).reconfirmationOtpSent,
        timeout: const Duration(seconds: 45),
        failure: 'The independent Recovery OTP was not accepted.',
      );
      final finalOtp = await _resolveOtp(
        account: accounts.peer,
        purpose: _finalizePurpose,
        handle: handle,
        didDomain: config.didDomain,
        recoverySessionId: ready.recoverySessionId,
      );
      await tester.enterText(
        find.bySemanticsIdentifier('handle-recovery-reconfirmation-otp'),
        finalOtp,
      );
      await _tapOne(
        tester,
        find.byKey(const Key('handle-recovery-risk-confirmation')),
        failure: 'The explicit Recovery risk confirmation was unavailable.',
      );
      final finalize = find.descendant(
        of: find.byKey(const Key('handle-recovery-panel')),
        matching: find.byType(AppDangerButton),
      );
      await _tapOne(
        tester,
        finalize,
        failure: 'The Recovery finalize action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          if (presence.calls > 1) {
            fail('Recovery finalize requested user presence more than once.');
          }
          final session = container.read(sessionProvider).session;
          return presence.completions == 1 &&
              presence.lastResult &&
              session != null &&
              container.read(appRuntimeProvider).activatedDid == session.did &&
              find
                      .bySemanticsIdentifier('e2e-authenticated')
                      .evaluate()
                      .length ==
                  1;
        },
        timeout: const Duration(minutes: 3),
        failure:
            'Recovery did not activate the replacement identity after real user presence.',
      );
      if (presence.calls != 1 ||
          presence.completions != 1 ||
          !presence.lastResult) {
        fail('Recovery finalize did not use exactly one real user presence.');
      }
      final newDid = container.read(sessionProvider).session!.did;
      if (newDid == oldDid) {
        fail('Recovery reused the old DID instead of creating a replacement.');
      }
      await _requireHandleDid(
        client: httpClient,
        config: config,
        handle: handle,
        expectedDid: newDid,
      );
      final registry = await requesterBootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(newDid);
      _requireSoleReadyAdmin(registry);
      final recoveryState = container.read(handleRecoveryProvider);
      if (recoveryState.activeRequester != null ||
          recoveryState.activationPending != null ||
          recoveryState.isBusy) {
        fail('Replacement identity activation left Recovery locally pending.');
      }

      await E2eCaseAttestationWriter.markPassed(
        _coolingCaseId,
        startedAt: startedAt,
        phases: const <String>[
          'independent_native_roots_created',
          'begin_otp_entered_real_cooling',
          'old_handle_binding_preserved_until_ready',
          'independent_session_bound_otp_confirmed',
          'single_real_user_presence_finalized',
          'distinct_replacement_did_activated',
          'replacement_device_ready_admin',
        ],
      );
    },
    skip: !Platform.isMacOS || !_RemoteRecoveryRunConfig.exists(),
    timeout: const Timeout(Duration(minutes: 76)),
  );
}

class _RemoteRecoveryRunConfig {
  const _RemoteRecoveryRunConfig({
    required this.baseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.mailServiceUrl,
    required this.didDomain,
    required this.anpServiceUrl,
    required this.anpServiceDid,
    required this.handlePrefix,
    required this.maxCoolingSeconds,
    required this.cliBin,
    required this.cliSourceRef,
    required this.cliWorkspace,
    required this.cliHome,
    required this.appStateRoot,
  });

  final String baseUrl;
  final String userServiceUrl;
  final String messageServiceUrl;
  final String mailServiceUrl;
  final String didDomain;
  final String anpServiceUrl;
  final String anpServiceDid;
  final String handlePrefix;
  final int maxCoolingSeconds;
  final String cliBin;
  final String cliSourceRef;
  final String cliWorkspace;
  final String cliHome;
  final String appStateRoot;

  static bool exists() => File(_runConfigPath).existsSync();

  static _RemoteRecoveryRunConfig load() {
    if (Platform.environment[_activationGate]?.trim() != '1') {
      throw StateError('Remote Handle Recovery is not explicitly enabled.');
    }
    final decoded = jsonDecode(File(_runConfigPath).readAsStringSync());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['enabled'] != true) {
      throw StateError('Remote Handle Recovery run config is invalid.');
    }
    final root = _stringMap(decoded);
    final service = _map(root, 'service');
    final account = _map(root, 'account');
    final cooling = _map(root, 'cooling');
    final cli = _map(root, 'cliRequester');
    final app = _map(root, 'app');
    final minimumCooling = _requiredInt(cooling, 'minimumSeconds');
    final maximumCooling = _requiredInt(cooling, 'maximumWaitSeconds');
    if (minimumCooling != 3600 ||
        maximumCooling < minimumCooling ||
        maximumCooling > 604800 ||
        _requiredInt(account, 'accountCount') != 2) {
      throw StateError('Remote Handle Recovery run config is incomplete.');
    }
    final config = _RemoteRecoveryRunConfig(
      baseUrl: _required(root: service, key: 'baseUrl'),
      userServiceUrl: _required(root: service, key: 'userServiceUrl'),
      messageServiceUrl: _required(root: service, key: 'messageServiceUrl'),
      mailServiceUrl: _required(root: service, key: 'mailServiceUrl'),
      didDomain: _required(root: service, key: 'didDomain'),
      anpServiceUrl: _required(root: service, key: 'anpServiceUrl'),
      anpServiceDid: _required(root: service, key: 'anpServiceDid'),
      handlePrefix: _required(root: account, key: 'handlePrefix'),
      maxCoolingSeconds: maximumCooling,
      cliBin: _required(root: cli, key: 'binary'),
      cliSourceRef: _required(root: cli, key: 'sourceRef'),
      cliWorkspace: _required(root: cli, key: 'workspace'),
      cliHome: _required(root: cli, key: 'home'),
      appStateRoot: _required(root: app, key: 'stateRoot'),
    );
    if (config.didDomain != 'awiki.info') {
      throw StateError('Remote Handle Recovery DID domain is not audited.');
    }
    for (final value in <String>[
      config.baseUrl,
      config.userServiceUrl,
      config.messageServiceUrl,
      config.mailServiceUrl,
      config.anpServiceUrl,
    ]) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || uri.host != 'awiki.info') {
        throw StateError('Remote Handle Recovery target is not audited.');
      }
    }
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(config.cliSourceRef) ||
        RegExp(r'^0{40}$').hasMatch(config.cliSourceRef)) {
      throw StateError('Remote Handle Recovery CLI source is not auditable.');
    }
    return config;
  }
}

class _DedicatedAccount {
  const _DedicatedAccount({required this.phone, required this.otpCommand});

  final String phone;
  final List<String> otpCommand;
}

class _DedicatedAccounts {
  const _DedicatedAccounts({required this.primary, required this.peer});

  final _DedicatedAccount primary;
  final _DedicatedAccount peer;

  static _DedicatedAccounts fromEnvironment() {
    final primaryPhone = Platform.environment[_primaryPhoneEnv]?.trim() ?? '';
    final peerPhone = Platform.environment[_peerPhoneEnv]?.trim() ?? '';
    final encodedCommand = Platform.environment[_otpCommandEnv]?.trim() ?? '';
    if (primaryPhone.isEmpty ||
        peerPhone.isEmpty ||
        primaryPhone == peerPhone ||
        encodedCommand.isEmpty) {
      throw StateError('Dedicated Recovery account configuration is missing.');
    }
    final bool staged;
    try {
      staged = parseRemoteMultiDeviceStagedOtpFlag(Platform.environment);
    } on FormatException {
      throw StateError('Dedicated Recovery SMS mode is invalid.');
    }
    if (staged) {
      throw StateError('Staged SMS errors cannot attest product Recovery.');
    }
    final List<String> command;
    try {
      command = parseRemoteMultiDeviceOtpCommand(
        encodedCommand,
        requireReviewedStagedResolver: false,
      );
    } on FormatException {
      throw StateError('Dedicated Recovery OTP resolver is invalid.');
    }
    final immutable = List<String>.unmodifiable(command);
    return _DedicatedAccounts(
      primary: _DedicatedAccount(phone: primaryPhone, otpCommand: immutable),
      peer: _DedicatedAccount(phone: peerPhone, otpCommand: immutable),
    );
  }
}

class _RecoveryCli {
  _RecoveryCli(this.config);

  final _RemoteRecoveryRunConfig config;
  late final String _tenantName = 'e2e-recovery-${_nonce(8)}';

  Future<void> initialize() async {
    await Directory(config.cliWorkspace).create(recursive: true);
    await Directory(config.cliHome).create(recursive: true);
    final version = await _run(const <String>['--format', 'json', 'version']);
    if (_data(version, action: null)['commit'] != config.cliSourceRef) {
      fail('The Recovery CLI does not match its audited source commit.');
    }
    await _run(const <String>['--format', 'json', 'init']);
    await _run(<String>[
      '--format',
      'json',
      'tenant',
      'create',
      _tenantName,
      '--backend-base-url',
      config.baseUrl,
      '--did-host',
      config.didDomain,
      '--display-name',
      'AWiki Recovery E2E',
    ]);
    await _run(<String>['--format', 'json', 'tenant', 'use', _tenantName]);
  }

  Future<_CliRecoveryProgress> begin({
    required String canonicalHandle,
    required String verificationGrant,
  }) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'recovery',
      'begin',
      '--handle',
      canonicalHandle,
    ], beginGrant: verificationGrant);
    return _CliRecoveryProgress.fromPayload(
      payload,
      action: 'handle_recovery_begin',
    );
  }

  Future<_CliRecoveryProgress> status(String recoverySessionId) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'recovery',
      'status',
      '--session',
      recoverySessionId,
    ]);
    return _CliRecoveryProgress.fromPayload(
      payload,
      action: 'handle_recovery_status',
    );
  }

  Future<void> requireFinalizeRejected({
    required String recoverySessionId,
    required String verificationGrant,
  }) async {
    final process = await Process.start(
      '/usr/bin/script',
      <String>[
        '-q',
        '/dev/null',
        config.cliBin,
        '--format',
        'json',
        'id',
        'recovery',
        'finalize',
        '--session',
        recoverySessionId,
      ],
      environment: _environment(finalizeGrant: verificationGrant),
      includeParentEnvironment: false,
      runInShell: false,
    );
    final stdoutDone = process.stdout.drain<void>();
    final stderrDone = process.stderr.drain<void>();
    process.stdin.write('$recoverySessionId\nRESET\n');
    await process.stdin.close();
    int code;
    try {
      code = await process.exitCode.timeout(_remoteTimeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      fail('Cancelled Recovery finalize did not terminate safely.');
    }
    await stdoutDone;
    await stderrDone;
    if (code == 0) {
      fail('Cancelled Recovery finalize unexpectedly succeeded.');
    }
  }

  Future<Map<String, Object?>> _run(
    List<String> args, {
    String? beginGrant,
  }) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        config.cliBin,
        args,
        environment: _environment(beginGrant: beginGrant),
        includeParentEnvironment: false,
        runInShell: false,
      ).timeout(_remoteTimeout);
    } on Object {
      fail('The Recovery CLI process did not complete safely.');
    }
    if (result.exitCode != 0) {
      fail('The Recovery CLI command failed without exposing output.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on Object {
      fail('The Recovery CLI returned invalid JSON.');
    }
    if (decoded is! Map || decoded['ok'] != true) {
      fail('The Recovery CLI returned no successful result.');
    }
    return _stringMap(decoded);
  }

  Map<String, String> _environment({
    String? beginGrant,
    String? finalizeGrant,
  }) {
    final values = <String, String>{
      'HOME': config.cliHome,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
      'AWIKI_MULTI_DEVICE_HANDLE_RECOVERY_ENABLED': '1',
      if (beginGrant != null)
        'AWIKI_HANDLE_RECOVERY_BEGIN_VERIFICATION_TOKEN': beginGrant,
      if (finalizeGrant != null)
        'AWIKI_HANDLE_RECOVERY_FINALIZE_VERIFICATION_TOKEN': finalizeGrant,
    };
    for (final name in const <String>[
      'PATH',
      'LANG',
      'LC_ALL',
      'TMPDIR',
      'SSL_CERT_FILE',
      'SSL_CERT_DIR',
    ]) {
      final value = Platform.environment[name];
      if (value != null && value.trim().isNotEmpty) {
        values[name] = value;
      }
    }
    return values;
  }

  Future<void> deleteLocalState() async {
    await _deleteDirectory(config.cliWorkspace);
    await _deleteDirectory(config.cliHome);
  }
}

class _CliRecoveryProgress {
  const _CliRecoveryProgress({
    required this.recoverySessionId,
    required this.oldDid,
    required this.phase,
    required this.side,
    required this.coolingUntil,
    required this.newDid,
    required this.localActivationPending,
  });

  final String recoverySessionId;
  final String oldDid;
  final String phase;
  final String side;
  final DateTime coolingUntil;
  final String? newDid;
  final bool localActivationPending;

  static _CliRecoveryProgress fromPayload(
    Map<String, Object?> payload, {
    required String action,
  }) {
    final data = _data(payload, action: action);
    final raw = data['result'];
    if (raw is! Map) {
      fail('The Recovery CLI returned no safe progress projection.');
    }
    final progress = _stringMap(raw);
    final coolingUntil = DateTime.tryParse(
      _required(root: progress, key: 'cooling_until'),
    );
    if (coolingUntil == null) {
      fail('The Recovery CLI returned an invalid cooling deadline.');
    }
    return _CliRecoveryProgress(
      recoverySessionId: _required(root: progress, key: 'recovery_session_id'),
      oldDid: _required(root: progress, key: 'old_did'),
      phase: _required(root: progress, key: 'phase'),
      side: _required(root: progress, key: 'side'),
      coolingUntil: coolingUntil.toUtc(),
      newDid: progress['new_did']?.toString(),
      localActivationPending: progress['local_activation_pending'] == true,
    );
  }
}

class _CountingRealUserPresencePort implements UserPresencePort {
  final LocalAuthUserPresencePort _delegate = LocalAuthUserPresencePort();
  int calls = 0;
  int completions = 0;
  bool lastResult = false;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    lastResult = await _delegate.confirm(reason: reason);
    completions += 1;
    return lastResult;
  }
}

AwikiEnvironmentConfig _environment(_RemoteRecoveryRunConfig config) {
  return AwikiEnvironmentConfig(
    baseUrl: config.baseUrl,
    userServiceUrl: config.userServiceUrl,
    messageServiceUrl: config.messageServiceUrl,
    mailServiceUrl: config.mailServiceUrl,
    didDomain: config.didDomain,
    anpServiceUrl: config.anpServiceUrl,
    anpServiceDid: config.anpServiceDid,
    agentImEnabled: false,
    multiDeviceJoinEnabled: true,
    multiDeviceRootTransferEnabled: false,
    multiDeviceDeviceRevokeEnabled: false,
    multiDeviceDirectE2eeEnabled: false,
    multiDeviceGroupE2eeEnabled: false,
    handleRecoveryEnabled: true,
  );
}

Future<AppSession> _registerReadyAdmin({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required AppBootstrap bootstrap,
  required String handle,
}) async {
  final otp = await _requestAndResolveOtp(
    client: client,
    config: config,
    account: account,
    purpose: _genesisPurpose,
    handle: handle,
  );
  final AppSession session;
  try {
    session = await bootstrap.onboardingService!.registerHandleWithPhone(
      phone: account.phone,
      otp: otp,
      handle: handle,
      nickName: 'AWiki Recovery E2E',
    );
  } on Object {
    fail('Recovery bootstrap registration failed safely.');
  }
  if (!session.authenticated) {
    fail('Recovery bootstrap identity was not authenticated.');
  }
  final registry = await bootstrap.deviceManagementCorePort!
      .identityDeviceRegistry(session.did);
  _requireSoleReadyAdmin(registry);
  return session;
}

void _requireSoleReadyAdmin(DeviceRegistrySnapshot registry) {
  if (registry.devices.length != 1) {
    fail('Recovery identity did not contain exactly one device.');
  }
  final device = registry.devices.single;
  if (!device.isCurrent ||
      device.status != DeviceStatus.active ||
      device.role != DeviceRole.admin ||
      !device.managementReady) {
    fail('Recovery identity device was not the sole ready admin.');
  }
}

Future<ProviderContainer> _mountAuthenticatedApp({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required AppSession session,
  required UserPresencePort presence,
}) async {
  await tester.pumpWidget(
    AwikiMeApp(
      bootstrap: bootstrap,
      providerOverrides: <Override>[
        userPresencePortProvider.overrideWithValue(presence),
      ],
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  await container
      .read(appRuntimeProvider.notifier)
      .activateSession(session.toLegacySessionIdentity());
  await _pumpUntil(
    tester,
    () =>
        find.bySemanticsIdentifier('e2e-authenticated').evaluate().length == 1,
    failure: 'The authenticated Recovery App shell did not become visible.',
  );
  return container;
}

Future<void> _openDevices(WidgetTester tester) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-settings-tab'),
    failure: 'The Recovery App settings entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().length == 1,
    failure: 'The Recovery App settings surface did not open.',
  );
  await _tapOne(
    tester,
    find.text(tester.element(find.byType(SettingsPage)).l10n.settingsDevices),
    failure: 'The Recovery App Devices entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DevicesPage).evaluate().length == 1,
    failure: 'The Recovery App Devices surface did not open.',
  );
}

Future<OldAdminRecoveryNotice> _waitForDurableNotice({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String oldDid,
  required String recoverySessionId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      await bootstrap.messageSyncService!.syncNow(
        reason: 'e2e_recovery_notice',
      );
    } on Object {
      // Realtime and the next bounded sync attempt remain authoritative.
    }
    final notices = await bootstrap.handleRecoveryPort!
        .listOldAdminRecoveryNotices(oldDid);
    final matches = notices
        .where((value) => value.recoverySessionId == recoverySessionId)
        .toList(growable: false);
    if (matches.length == 1) {
      return matches.single;
    }
    if (matches.length > 1) {
      fail('Recovery produced duplicate durable old-admin notices.');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
  }
  fail('The old admin did not receive a durable Recovery notice in time.');
}

Future<HandleRecoveryProgress> _waitForReady({
  required WidgetTester tester,
  required ProviderContainer container,
  required HandleRecoveryProgress initial,
  required int maxCoolingSeconds,
}) async {
  final remaining = initial.coolingUntil.difference(DateTime.now().toUtc());
  if (remaining < const Duration(minutes: 55)) {
    fail('Recovery did not expose the deployed full cooling period.');
  }
  final deadline = DateTime.now().add(Duration(seconds: maxCoolingSeconds));
  var observedCooling = false;
  while (DateTime.now().isBefore(deadline)) {
    final active = container.read(handleRecoveryProvider).activeRequester;
    if (active?.phase == HandleRecoveryPhase.ready) {
      if (!observedCooling) {
        fail('Recovery reached ready without an observed cooling phase.');
      }
      if (DateTime.now().toUtc().isBefore(initial.coolingUntil)) {
        fail(
          'Recovery became ready before its authoritative cooling deadline.',
        );
      }
      return active!;
    }
    if (active == null || active.phase != HandleRecoveryPhase.cooling) {
      fail('Recovery left cooling through an unexpected state.');
    }
    observedCooling = true;
    await Future<void>.delayed(const Duration(seconds: 5));
    await container.read(handleRecoveryProvider.notifier).pollActive();
    await tester.pump();
  }
  fail('Recovery did not become ready after its deployed cooling period.');
}

void _requireCooling(
  _CliRecoveryProgress progress, {
  required String expectedOldDid,
}) {
  if (progress.phase != 'cooling' ||
      progress.side != 'requester' ||
      progress.oldDid != expectedOldDid ||
      progress.newDid != null ||
      progress.localActivationPending ||
      !progress.coolingUntil.isAfter(DateTime.now().toUtc())) {
    fail('Recovery begin did not return a safe requester cooling projection.');
  }
}

void _requireAppCooling(
  HandleRecoveryProgress progress, {
  required String expectedOldDid,
  required DateTime beginSubmittedAt,
}) {
  if (progress.phase != HandleRecoveryPhase.cooling ||
      progress.side != HandleRecoverySide.requester ||
      progress.oldDid != expectedOldDid ||
      progress.newDid != null ||
      progress.localActivationPending ||
      !progress.coolingUntil.isAfter(DateTime.now().toUtc())) {
    fail('The App did not project a safe requester cooling state.');
  }
  if (progress.coolingUntil.difference(beginSubmittedAt) <
      const Duration(seconds: 3600)) {
    fail('Recovery did not expose the deployed full cooling deadline.');
  }
}

void _requireCancelled(
  _CliRecoveryProgress progress, {
  required String expectedOldDid,
}) {
  if (progress.phase != 'cancelled' ||
      progress.oldDid != expectedOldDid ||
      progress.newDid != null ||
      progress.localActivationPending) {
    fail('Cancelled Recovery returned an unsafe terminal projection.');
  }
}

Future<void> _requireCancelledFinalizeRejected({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required _RecoveryCli cli,
  required String handle,
  required String recoverySessionId,
}) async {
  final response = await _requestOtp(
    client: client,
    config: config,
    account: account,
    purpose: _finalizePurpose,
    handle: handle,
    recoverySessionId: recoverySessionId,
  );
  if (response.statusCode == 409 || response.statusCode == 410) {
    return;
  }
  if (response.statusCode != 200) {
    fail(
      'Cancelled Recovery OTP was not rejected at an authoritative boundary.',
    );
  }
  final otp = await _resolveOtp(
    account: account,
    purpose: _finalizePurpose,
    handle: handle,
    didDomain: config.didDomain,
    recoverySessionId: recoverySessionId,
  );
  final exchange = await _exchangeRecoveryGrantResponse(
    client: client,
    config: config,
    account: account,
    purpose: _finalizePurpose,
    handle: handle,
    otp: otp,
    recoverySessionId: recoverySessionId,
  );
  if (exchange.statusCode == 409 || exchange.statusCode == 410) {
    return;
  }
  final grant = _credentialFromExchange(
    exchange,
    purpose: _finalizePurpose,
    field: 'reconfirmation_token',
  );
  await cli.requireFinalizeRejected(
    recoverySessionId: recoverySessionId,
    verificationGrant: grant,
  );
}

Future<String> _requestAndResolveOtp({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  String? recoverySessionId,
}) async {
  final response = await _requestOtp(
    client: client,
    config: config,
    account: account,
    purpose: purpose,
    handle: handle,
    recoverySessionId: recoverySessionId,
  );
  if (response.statusCode != 200) {
    fail('The purpose-bound Recovery OTP request was rejected.');
  }
  return _resolveOtp(
    account: account,
    purpose: purpose,
    handle: handle,
    didDomain: config.didDomain,
    recoverySessionId: recoverySessionId,
  );
}

Future<http.Response> _requestOtp({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  String? recoverySessionId,
}) async {
  http.Response? response;
  for (var attempt = 0; attempt < 2; attempt += 1) {
    try {
      response = await client
          .post(
            Uri.parse(
              config.userServiceUrl,
            ).resolve('/user-service/auth/sms-codes'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'phone': account.phone,
              'purpose': purpose,
              'target_handle': handle,
              'target_handle_domain': config.didDomain,
              if (recoverySessionId != null)
                'recovery_session_id': recoverySessionId,
              'rate_limit_seconds': 30,
              'code_expire_minutes': 5,
            }),
          )
          .timeout(_remoteTimeout);
    } on Object {
      fail('The purpose-bound Recovery OTP request failed safely.');
    }
    if (response.statusCode != 429 || attempt == 1) {
      return response;
    }
    await Future<void>.delayed(const Duration(seconds: 31));
  }
  fail('The purpose-bound Recovery OTP request did not complete.');
}

Future<String> _resolveOtp({
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  required String didDomain,
  String? recoverySessionId,
}) async {
  final Process process;
  try {
    process = await Process.start(
      account.otpCommand.first,
      account.otpCommand.skip(1).toList(growable: false),
      runInShell: false,
    );
  } on Object {
    fail('The dedicated Recovery OTP resolver transport failed safely.');
  }
  process.stdin.write(
    jsonEncode(<String, Object?>{
      'phone': account.phone,
      'purpose': purpose,
      'target_handle': handle,
      'target_handle_domain': didDomain,
      'recovery_session_id': recoverySessionId,
    }),
  );
  await process.stdin.close();
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.drain<void>();
  int exitCode;
  try {
    exitCode = await process.exitCode.timeout(_remoteTimeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    fail('The dedicated Recovery OTP resolver timed out.');
  }
  final stdout = await stdoutFuture;
  await stderrFuture;
  if (exitCode != 0 || stdout.length > 1024) {
    fail('The dedicated Recovery OTP resolver failed without exposing output.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(stdout);
  } on Object {
    fail('The dedicated Recovery OTP resolver returned invalid JSON.');
  }
  if (decoded is! Map || decoded.length != 1) {
    fail('The dedicated Recovery OTP resolver returned an invalid response.');
  }
  final otp = decoded['otp'];
  if (otp is! String || !isSixDigitAsciiOtp(otp)) {
    fail('The dedicated Recovery OTP resolver returned an invalid response.');
  }
  return otp;
}

Future<String> _exchangeRecoveryGrant({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  required String otp,
  String? recoverySessionId,
}) async {
  final response = await _exchangeRecoveryGrantResponse(
    client: client,
    config: config,
    account: account,
    purpose: purpose,
    handle: handle,
    otp: otp,
    recoverySessionId: recoverySessionId,
  );
  return _credentialFromExchange(
    response,
    purpose: purpose,
    field: purpose == _beginPurpose
        ? 'account_verification_token'
        : 'reconfirmation_token',
  );
}

Future<http.Response> _exchangeRecoveryGrantResponse({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  required String otp,
  String? recoverySessionId,
}) async {
  try {
    return await client
        .post(
          Uri.parse(
            config.userServiceUrl,
          ).resolve('/user-service/auth/account-verification/exchange'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': 'sms',
            'purpose': purpose,
            'phone': account.phone,
            'code': otp,
            'target_handle': handle,
            'target_handle_domain': config.didDomain,
            'idempotency_scope': 'app-recovery-${_nonce(12)}',
            if (recoverySessionId != null)
              'recovery_session_id': recoverySessionId,
          }),
        )
        .timeout(_remoteTimeout);
  } on Object {
    fail('The Recovery account-verification exchange failed safely.');
  }
}

String _credentialFromExchange(
  http.Response response, {
  required String purpose,
  required String field,
}) {
  if (response.statusCode != 200) {
    fail('The Recovery account-verification exchange was rejected.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on Object {
    fail('The Recovery account-verification exchange returned invalid JSON.');
  }
  if (decoded is! Map || decoded['purpose'] != purpose) {
    fail(
      'The Recovery account-verification exchange returned an invalid scope.',
    );
  }
  final token = decoded[field];
  if (token is! String || token.trim().isEmpty) {
    fail('The Recovery account-verification exchange returned no grant.');
  }
  return token;
}

Future<void> _requireHandleDid({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required String handle,
  required String expectedDid,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final response = await client
          .get(
            Uri.parse('https://${config.didDomain}/.well-known/handle/$handle'),
            headers: const <String, String>{'Accept': 'application/json'},
          )
          .timeout(_remoteTimeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map &&
            decoded['status'] == 'active' &&
            decoded['did'] == expectedDid) {
          return;
        }
      }
    } on Object {
      // Retry the bounded public Handle observation without logging payloads.
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail('The public Handle binding did not converge to the expected identity.');
}

Future<void> _requireRealUserPresence() async {
  if (!await LocalAuthentication().isDeviceSupported()) {
    fail(
      'Remote Handle Recovery requires real operating-system user presence.',
    );
  }
}

void _requireFreshPaths(List<String> paths) {
  if (paths.map((value) => Directory(value).absolute.path).toSet().length !=
      paths.length) {
    fail('Recovery E2E local roots were not independent.');
  }
  for (final path in paths) {
    final directory = Directory(path);
    if (directory.existsSync() &&
        directory.listSync(followLinks: false).isNotEmpty) {
      fail('A Recovery E2E local root was not fresh.');
    }
  }
}

bool _sameNotice(OldAdminRecoveryNotice first, OldAdminRecoveryNotice second) {
  return first.eventId == second.eventId &&
      first.recoverySessionId == second.recoverySessionId &&
      first.canonicalHandle == second.canonicalHandle &&
      first.oldDid == second.oldDid &&
      first.requestedAt == second.requestedAt &&
      first.cancellableUntil == second.cancellableUntil;
}

Future<void> _deleteDirectory(String path) async {
  final directory = Directory(path);
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String failure,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (!condition()) {
    fail(failure);
  }
}

Future<void> _tapOne(
  WidgetTester tester,
  Finder finder, {
  required String failure,
}) async {
  final target = finder.hitTestable();
  if (target.evaluate().length != 1) {
    fail(failure);
  }
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Map<String, Object?> _data(
  Map<String, Object?> payload, {
  required String? action,
}) {
  final raw = payload['data'];
  if (raw is! Map) {
    fail('The CLI response omitted its safe data object.');
  }
  final data = _stringMap(raw);
  if (action != null && data['action'] != action) {
    fail('The CLI response action did not match the requested operation.');
  }
  return data;
}

Map<String, Object?> _stringMap(Map raw) => <String, Object?>{
  for (final entry in raw.entries) entry.key.toString(): entry.value,
};

Map<String, Object?> _map(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! Map) {
    throw StateError('Remote Handle Recovery config is invalid.');
  }
  return _stringMap(value);
}

String _required({required Map<String, Object?> root, required String key}) {
  final value = root[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw StateError('Remote Handle Recovery config is incomplete.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! int) {
    throw StateError('Remote Handle Recovery config is incomplete.');
  }
  return value;
}

String _uniqueHandle(String prefix) => '$prefix${_nonce(8)}';

String _nonce(int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List<String>.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
