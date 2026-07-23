// [INPUT]: Audited awiki.info endpoints, a dedicated account/SSH OTP resolver,
//          production AppBootstrap/native Core, and independent CLI/App roots.
// [OUTPUT]: Two real, notification-driven, member-only Device Join scenarios.
// [POS]: Step 2 Join product E2E; no Registry discovery, implicit verification,
//        copied state, fake Core, static OTP, or secret-bearing evidence.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/data/services/local_auth_user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';

import '../../case_attestation.dart';
import '../../remote_multi_device_join_contract.dart';

const String _newDeviceCaseId = 'DEVICE-JOIN-E2E-001';
const String _adminApprovalCaseId = 'DEVICE-JOIN-E2E-002';
const String _runConfigPath =
    '.e2e/multi-device-remote-join/current/run_config.json';
const String _activationGate = 'AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED';
const String _phoneEnv = 'AWIKI_MULTI_DEVICE_E2E_PHONE';
const String _otpCommandEnv = 'AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON';
const String _genesisPurpose = 'awiki.device.genesis.v1';
const String _joinPurpose = 'awiki.device.join.v1';
const Duration _remoteTimeout = Duration(seconds: 30);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'App new device joins after CLI consumes its local notification inbox',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final cli = _JoinCli.admin(config);
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireIndependentEmptyPaths(<String>[
        config.appJoiningStateRoot,
        config.cliAdminWorkspace,
        config.cliAdminHome,
      ]);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await cli.deleteLocalState();
        await _deleteDirectory(config.appJoiningStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      if (!Platform.isMacOS || !File('/usr/bin/script').existsSync()) {
        fail(
          'The remote App-new-device Join gate requires a foreground macOS '
          'pseudo-terminal.',
        );
      }
      await cli.initialize();
      final handle = _uniqueHandle(config.handlePrefix);
      final genesisOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _genesisPurpose,
        handle: handle,
      );
      final did = await cli.registerReadyAdmin(
        handle: handle,
        phone: account.phone,
        otp: genesisOtp,
      );
      final initialCliRegistry = await cli.loadRegistry();
      final bootstrapAdminDeviceId = _requireCliReadyBootstrapAdmin(
        initialCliRegistry,
      );

      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.appJoiningStateRoot,
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
        failure: 'The new-device Join action was unavailable.',
      );
      var container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceJoinPage)),
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The App rejected the new-device Join');
          final progress = state.activeJoin;
          return progress?.side == DeviceJoinSide.newDevice &&
              progress?.phase == DeviceJoinPhase.pending &&
              progress?.remoteState == DeviceJoinRemoteState.pending &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 45),
        failure: 'OTP did not leave the App Join pending without a SAS.',
      );
      final initialPending = container.read(devicesProvider).activeJoin!;
      if (find.byKey(const Key('device-join-sas')).evaluate().isNotEmpty) {
        fail('The App displayed a SAS before verification started.');
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.appJoiningStateRoot,
      );
      final restoredSessions = await bootstrap.deviceManagementCorePort!
          .localDeviceJoinSessions();
      final restored = restoredSessions
          .where(
            (session) =>
                session.joinSessionId == initialPending.joinSessionId &&
                session.protocolDeviceId == initialPending.protocolDeviceId,
          )
          .toList(growable: false);
      if (restored.length != 1 ||
          restored.single.side != DeviceJoinSide.newDevice ||
          restored.single.isTerminal ||
          restored.single.sas != null) {
        fail('Restart did not restore the same secret-free pending Join.');
      }

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await _openNewDeviceJoin(tester);
      container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceJoinPage)),
      );
      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          return progress?.joinSessionId == initialPending.joinSessionId &&
              progress?.protocolDeviceId == initialPending.protocolDeviceId &&
              progress?.side == DeviceJoinSide.newDevice &&
              progress?.phase == DeviceJoinPhase.pending &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The restarted App did not resume the same pending Join.',
      );

      final notice = await cli.waitForJoinRequest(
        expectedSessionId: initialPending.joinSessionId,
        expectedDeviceId: initialPending.protocolDeviceId,
        expectedState: 'pending',
        expectedClaimedByCurrentDevice: false,
      );
      final started = await cli.startVerification(notice);
      if (started.remoteState != 'challenge_sent' || started.sas != null) {
        fail(
          'Explicit CLI verification did not publish a secret-free challenge.',
        );
      }

      await _pumpUntil(
        tester,
        () => find.byKey(const Key('device-join-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The App new device did not derive its Join SAS.',
      );
      final appSas =
          tester.widget<Text>(find.byKey(const Key('device-join-sas'))).data ??
          '';
      if (!_validSas(appSas)) {
        fail('The App projected a malformed Join SAS.');
      }

      await cli.waitForJoinRequest(
        expectedSessionId: initialPending.joinSessionId,
        expectedDeviceId: initialPending.protocolDeviceId,
        expectedState: 'response_verified',
        expectedClaimedByCurrentDevice: true,
      );
      await cli.approveAsMemberInForeground(
        joinSessionId: initialPending.joinSessionId,
        expectedSas: appSas,
      );

      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          final authorized = progress?.authorizedDevice;
          return progress?.phase == DeviceJoinPhase.authorized &&
              progress?.remoteState == DeviceJoinRemoteState.consumed &&
              progress?.sas == null &&
              authorized?.protocolDeviceId == initialPending.protocolDeviceId &&
              authorized?.role == DeviceRole.member &&
              authorized?.managementReady == false &&
              authorized?.isCurrent == true;
        },
        timeout: const Duration(seconds: 45),
        failure:
            'The App did not re-resolve and activate the joined member device.',
      );
      await _pumpUntil(
        tester,
        () =>
            container.read(sessionProvider).session?.did == did &&
            container.read(appRuntimeProvider).activatedDid == did,
        timeout: const Duration(seconds: 45),
        failure: 'The joined App did not activate the exact account DID.',
      );
      _requireCliAdminAndMember(
        await cli.waitForRegistryDeviceCount(2),
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: initialPending.protocolDeviceId,
      );
      _requireAppCurrentMember(
        await bootstrap.deviceManagementCorePort!.identityDeviceRegistry(did),
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: initialPending.protocolDeviceId,
      );

      await E2eCaseAttestationWriter.markPassed(
        _newDeviceCaseId,
        phases: const <String>[
          'independent_native_devices_bootstrapped',
          'app_otp_left_join_pending',
          'app_restart_restored_pending_without_sas',
          'sas_matched_without_secret_evidence',
          'cli_foreground_member_approval_completed',
          'app_joined_after_authority_reresolution',
        ],
      );
    },
    skip:
        !Platform.isMacOS ||
        !_RemoteJoinRunConfig.exists() ||
        !_invocationExpects(_newDeviceCaseId),
    timeout: const Timeout(Duration(minutes: 14)),
  );

  testWidgets(
    'App admin explicitly starts and approves a CLI Join from local inbox',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      final cli = _JoinCli.joining(config);
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireIndependentEmptyPaths(<String>[
        config.appStateRoot,
        config.cliWorkspace,
        config.cliHome,
      ]);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await cli.deleteLocalState();
        await _deleteDirectory(config.appStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      if (!await LocalAuthentication().isDeviceSupported()) {
        fail(
          'The remote App-admin Join gate requires real operating-system '
          'user presence.',
        );
      }
      await cli.initialize();
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.appStateRoot,
      );
      final handle = _uniqueHandle(config.handlePrefix);
      final genesisOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _genesisPurpose,
        handle: handle,
      );
      final IdentityRegistrationResult registration;
      try {
        registration = await bootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: genesisOtp,
              handle: handle,
              nickName: 'AWiki multi-device E2E',
            );
      } on Object {
        fail('App bootstrap registration failed without exposing remote data.');
      }
      final adminSession = registration.identity;
      if (registration.status != IdentityRegistrationStatus.registered ||
          adminSession == null ||
          !adminSession.authenticated) {
        fail('The App bootstrap identity was not a registered admin session.');
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
      await _openDevicesPage(tester);

      final joinOperationId = 'app-join-${_nonce(10)}';
      final joinOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _joinPurpose,
        handle: handle,
      );
      final grant = await _exchangeJoinGrant(
        client: httpClient,
        config: config,
        account: account,
        handle: handle,
        otp: joinOtp,
        operationId: joinOperationId,
      );
      final started = await cli.startJoin(
        did: adminSession.did,
        operationId: joinOperationId,
        accountVerificationToken: grant,
      );
      if (started.remoteState != 'pending' || started.sas != null) {
        fail('OTP did not leave the joining CLI pending without a SAS.');
      }

      await _syncAppJoinInboxUntil(
        container,
        reason: 'e2e_join_requested',
        condition: () {
          final matches = container
              .read(devicesProvider)
              .joinRequests
              .where(
                (request) =>
                    request.joinSessionId == started.joinSessionId &&
                    request.protocolDeviceId == started.protocolDeviceId,
              )
              .toList(growable: false);
          return matches.length == 1 &&
              matches.single.state == DeviceJoinRemoteState.pending &&
              matches.single.canStartVerification &&
              !matches.single.claimedByCurrentDevice;
        },
        failure:
            'The App did not project the Join request from its local inbox.',
      );
      await _pumpUntil(
        tester,
        () => find.text(started.protocolDeviceId).evaluate().length == 1,
        failure: 'The local Join request was not rendered on Devices.',
      );
      await _tapOne(
        tester,
        find.text(started.protocolDeviceId),
        failure: 'The local Join request could not be opened.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinApprovalSheet).evaluate().length == 1,
        failure: 'The App Join approval surface did not open.',
      );
      await tester.pump();
      if (container.read(devicesProvider).activeJoin != null) {
        fail('Opening the request implicitly wrote Join verification state.');
      }
      final startVerification = find.bySemanticsIdentifier(
        'multi-device-start-verification',
      );
      await _tapOne(
        tester,
        startVerification,
        failure: 'The explicit verification action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The App failed to start verification');
          final progress = state.activeJoin;
          return progress?.joinSessionId == started.joinSessionId &&
              progress?.protocolDeviceId == started.protocolDeviceId &&
              progress?.side == DeviceJoinSide.admin &&
              progress?.phase == DeviceJoinPhase.challengePrepared &&
              progress?.remoteState == DeviceJoinRemoteState.challengeSent &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The App did not start verification exactly from the request.',
      );
      if (startVerification.evaluate().isNotEmpty) {
        fail('The App exposed a repeated verification-start action.');
      }

      final cliProgress = await cli.pollUntilSas(
        started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      await _syncAppJoinInboxUntil(
        container,
        reason: 'e2e_join_response_verified',
        condition: () {
          final state = container.read(devicesProvider);
          _failOnDeviceError(state, 'The App failed to consume Join response');
          final progress = state.activeJoin;
          return progress?.joinSessionId == started.joinSessionId &&
              progress?.protocolDeviceId == started.protocolDeviceId &&
              progress?.side == DeviceJoinSide.admin &&
              progress?.phase == DeviceJoinPhase.responseVerified &&
              progress?.remoteState == DeviceJoinRemoteState.responseVerified &&
              _validSas(progress?.sas ?? '');
        },
        failure: 'The App did not restore verified progress from local state.',
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('device-approval-sas')).evaluate().length == 1,
        failure: 'The App did not render its locally derived SAS.',
      );
      final appSas =
          tester
              .widget<Text>(find.byKey(const Key('device-approval-sas')))
              .data ??
          '';
      if (!_validSas(appSas) ||
          !_constantTimeAsciiEquals(appSas, cliProgress.sas ?? '')) {
        fail('The independently derived App and CLI SAS values did not match.');
      }

      final approveAction = find.bySemanticsIdentifier('multi-device-approve');
      if (approveAction.evaluate().isNotEmpty) {
        fail('Approval was enabled before explicit SAS confirmation.');
      }
      final sasSwitch = find.descendant(
        of: find.byKey(const Key('device-sas-confirmation')),
        matching: find.byType(CupertinoSwitch),
      );
      await _tapOne(
        tester,
        sasSwitch,
        failure: 'The SAS confirmation control was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => approveAction.evaluate().length == 1,
        failure: 'SAS confirmation did not enable member approval.',
      );
      await _tapOne(
        tester,
        approveAction,
        failure: 'The member approval action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          if (presence.calls > 1) {
            fail('The App requested operating-system user presence twice.');
          }
          if (presence.completions == 1 && !presence.lastResult) {
            fail('The operating-system user-presence request was denied.');
          }
          return presence.completions == 1 && presence.lastResult;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The App approval did not complete after real user presence.',
      );
      if (presence.calls != 1 ||
          presence.completions != 1 ||
          !presence.lastResult) {
        fail('The App did not complete exactly one user-presence check.');
      }

      final authorized = await cli.pollUntilAuthorized(
        started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      if (authorized.protocolDeviceId != started.protocolDeviceId ||
          authorized.role != 'member' ||
          authorized.managementReady ||
          !authorized.isCurrent) {
        fail('The joining CLI did not become the current rootless member.');
      }
      _requireCliJoinedMember(
        await cli.waitForRegistryDeviceCount(2),
        joinedDeviceId: started.protocolDeviceId,
      );
      _requireAppAdminAndMember(
        await bootstrap.deviceManagementCorePort!.identityDeviceRegistry(
          adminSession.did,
        ),
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
        joinedDeviceId: started.protocolDeviceId,
      );

      await E2eCaseAttestationWriter.markPassed(
        _adminApprovalCaseId,
        phases: const <String>[
          'independent_native_devices_bootstrapped',
          'otp_left_join_pending',
          'sas_matched_without_secret_evidence',
          'single_real_user_presence_confirmed',
          'joined_device_active_member_not_admin',
        ],
      );
    },
    skip:
        !Platform.isMacOS ||
        !_RemoteJoinRunConfig.exists() ||
        !_invocationExpects(_adminApprovalCaseId),
    timeout: const Timeout(Duration(minutes: 14)),
  );
}

bool _invocationExpects(String caseId) {
  const encoded = String.fromEnvironment(e2eCaseIdsDefine);
  if (encoded.trim().isEmpty) return true;
  return encoded.split(',').map((value) => value.trim()).contains(caseId);
}

class _RemoteJoinRunConfig {
  const _RemoteJoinRunConfig({
    required this.runId,
    required this.baseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.mailServiceUrl,
    required this.didDomain,
    required this.anpServiceUrl,
    required this.anpServiceDid,
    required this.handlePrefix,
    required this.allowStagedOtpOnSmsError,
    required this.cliBin,
    required this.cliSourceRef,
    required this.cliWorkspace,
    required this.cliHome,
    required this.cliAdminWorkspace,
    required this.cliAdminHome,
    required this.appStateRoot,
    required this.appJoiningStateRoot,
  });

  final String runId;
  final String baseUrl;
  final String userServiceUrl;
  final String messageServiceUrl;
  final String mailServiceUrl;
  final String didDomain;
  final String anpServiceUrl;
  final String anpServiceDid;
  final String handlePrefix;
  final bool allowStagedOtpOnSmsError;
  final String cliBin;
  final String cliSourceRef;
  final String cliWorkspace;
  final String cliHome;
  final String cliAdminWorkspace;
  final String cliAdminHome;
  final String appStateRoot;
  final String appJoiningStateRoot;

  static bool exists() => File(_runConfigPath).existsSync();

  static _RemoteJoinRunConfig load() {
    if (Platform.environment[_activationGate]?.trim() != '1') {
      throw StateError('Remote multi-device Join is not explicitly enabled.');
    }
    final decoded = jsonDecode(File(_runConfigPath).readAsStringSync());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 2 ||
        decoded['enabled'] != true) {
      throw StateError('Remote multi-device Join run config is invalid.');
    }
    final root = _stringMap(decoded);
    final service = _map(root, 'service');
    final account = _map(root, 'account');
    final joiningCli = _map(root, 'cliJoiningDevice');
    final adminCli = _map(root, 'cliAdminDevice');
    final app = _map(root, 'app');
    final joiningApp = _map(root, 'appJoiningDevice');
    final config = _RemoteJoinRunConfig(
      runId: _required(root, 'runId'),
      baseUrl: _required(service, 'baseUrl'),
      userServiceUrl: _required(service, 'userServiceUrl'),
      messageServiceUrl: _required(service, 'messageServiceUrl'),
      mailServiceUrl: _required(service, 'mailServiceUrl'),
      didDomain: _required(service, 'didDomain'),
      anpServiceUrl: _required(service, 'anpServiceUrl'),
      anpServiceDid: _required(service, 'anpServiceDid'),
      handlePrefix: _required(account, 'handlePrefix'),
      allowStagedOtpOnSmsError: _requiredBool(
        account,
        'allowStagedOtpOnSmsError',
      ),
      cliBin: _required(joiningCli, 'binary'),
      cliSourceRef: _required(joiningCli, 'sourceRef'),
      cliWorkspace: _required(joiningCli, 'workspace'),
      cliHome: _required(joiningCli, 'home'),
      cliAdminWorkspace: _required(adminCli, 'workspace'),
      cliAdminHome: _required(adminCli, 'home'),
      appStateRoot: _required(app, 'stateRoot'),
      appJoiningStateRoot: _required(joiningApp, 'stateRoot'),
    );
    if (config.didDomain != 'awiki.info') {
      throw StateError('Remote multi-device Join DID domain is not audited.');
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
        throw StateError('Remote multi-device service target is not audited.');
      }
    }
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(config.cliSourceRef) ||
        RegExp(r'^0{40}$').hasMatch(config.cliSourceRef) ||
        _required(adminCli, 'binary') != config.cliBin ||
        _required(adminCli, 'sourceRef') != config.cliSourceRef) {
      throw StateError('Remote multi-device CLI build is not auditable.');
    }
    return config;
  }
}

class _DedicatedAccount {
  const _DedicatedAccount({required this.phone, required this.otpCommand});

  final String phone;
  final List<String> otpCommand;

  static _DedicatedAccount fromEnvironment({
    required bool allowStagedOtpOnSmsError,
  }) {
    final phone = Platform.environment[_phoneEnv]?.trim() ?? '';
    final encodedCommand = Platform.environment[_otpCommandEnv]?.trim() ?? '';
    if (phone.isEmpty || encodedCommand.isEmpty) {
      throw StateError('Dedicated multi-device account is missing.');
    }
    final bool stagedOtpEnabled;
    try {
      stagedOtpEnabled = parseRemoteMultiDeviceStagedOtpFlag(
        Platform.environment,
      );
    } on FormatException {
      throw StateError('Dedicated staged OTP mode is invalid.');
    }
    if (stagedOtpEnabled != allowStagedOtpOnSmsError) {
      throw StateError('Dedicated staged OTP mode does not match the runner.');
    }
    final List<String> command;
    try {
      command = parseRemoteMultiDeviceOtpCommand(
        encodedCommand,
        requireReviewedStagedResolver: allowStagedOtpOnSmsError,
      );
    } on FormatException {
      throw StateError('Dedicated OTP resolver is invalid.');
    }
    return _DedicatedAccount(
      phone: phone,
      otpCommand: List<String>.unmodifiable(command),
    );
  }
}

class _JoinCli {
  _JoinCli._({
    required this.config,
    required this.workspace,
    required this.home,
    required String role,
  }) : _tenantName = 'e2e-${_safeId(config.runId, 28)}-${_safeId(role, 8)}';

  factory _JoinCli.joining(_RemoteJoinRunConfig config) => _JoinCli._(
    config: config,
    workspace: config.cliWorkspace,
    home: config.cliHome,
    role: 'joining',
  );

  factory _JoinCli.admin(_RemoteJoinRunConfig config) => _JoinCli._(
    config: config,
    workspace: config.cliAdminWorkspace,
    home: config.cliAdminHome,
    role: 'admin',
  );

  final _RemoteJoinRunConfig config;
  final String workspace;
  final String home;
  final String _tenantName;

  Future<void> initialize() async {
    await Directory(workspace).create(recursive: true);
    await Directory(home).create(recursive: true);
    final version = await _run(const <String>['--format', 'json', 'version']);
    if (_data(version, action: null)['commit'] != config.cliSourceRef) {
      fail('The CLI binary does not match its audited source commit.');
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
      'AWiki App Join E2E',
    ]);
    await _run(<String>['--format', 'json', 'tenant', 'use', _tenantName]);
  }

  Future<String> registerReadyAdmin({
    required String handle,
    required String phone,
    required String otp,
  }) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'register',
      '--handle',
      handle,
      '--phone',
      phone,
      '--otp',
      otp,
    ]);
    final identity = _data(payload, action: 'register_handle')['identity'];
    if (identity is! Map) {
      fail('The CLI registration returned no safe identity projection.');
    }
    return _required(_stringMap(identity), 'did');
  }

  Future<_JoinProgress> startJoin({
    required String did,
    required String operationId,
    required String accountVerificationToken,
  }) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'device',
      'join',
      'start',
      '--did',
      did,
      '--operation-id',
      operationId,
    ], accountVerificationToken: accountVerificationToken);
    return _JoinProgress.fromData(_data(payload, action: 'device_join_start'));
  }

  Future<_JoinRequest> waitForJoinRequest({
    required String expectedSessionId,
    required String expectedDeviceId,
    required String expectedState,
    required bool expectedClaimedByCurrentDevice,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      await _run(const <String>[
        '--format',
        'json',
        'msg',
        'inbox',
        '--scope',
        'direct',
        '--limit',
        '20',
      ]);
      final payload = await _run(const <String>[
        '--format',
        'json',
        'id',
        'device',
        'join',
        'requests',
      ]);
      final result = _data(payload, action: 'device_join_requests')['result'];
      if (result is! List) {
        fail('The CLI returned no local Join request list.');
      }
      final matches = result
          .whereType<Map>()
          .map((value) => _JoinRequest.fromJson(_stringMap(value)))
          .where(
            (request) =>
                request.joinSessionId == expectedSessionId &&
                request.protocolDeviceId == expectedDeviceId,
          )
          .toList(growable: false);
      if (matches.length > 1) {
        fail('The CLI local inbox projected duplicate Join requests.');
      }
      if (matches.length == 1) {
        final request = matches.single;
        if (request.state == expectedState &&
            request.claimedByCurrentDevice == expectedClaimedByCurrentDevice) {
          return request;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The CLI did not consume the expected local Join notification.');
  }

  Future<_JoinProgress> startVerification(_JoinRequest request) async {
    if (request.state != 'pending' ||
        request.claimedByCurrentDevice ||
        !request.canStartVerification) {
      fail('The CLI local request was not eligible for verification.');
    }
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'device',
      'join',
      'verify',
      '--session',
      request.joinSessionId,
      '--operation-id',
      'e2e-verify-${_nonce(10)}',
    ]);
    final progress = _JoinProgress.fromData(
      _data(payload, action: 'device_join_verify'),
    );
    if (progress.joinSessionId != request.joinSessionId ||
        progress.protocolDeviceId != request.protocolDeviceId) {
      fail('CLI verification changed the selected Join identity.');
    }
    return progress;
  }

  Future<_JoinProgress> pollUntilSas(
    String sessionId, {
    required String expectedDeviceId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final payload = await _run(<String>[
        '--format',
        'json',
        'id',
        'device',
        'join',
        'poll',
        '--session',
        sessionId,
      ]);
      final progress = _JoinProgress.fromData(
        _data(payload, action: 'device_join_poll'),
      );
      _requireJoinIdentity(progress, sessionId, expectedDeviceId);
      if (progress.remoteState == 'response_verified' &&
          _validSas(progress.sas ?? '')) {
        return progress;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The joining CLI did not derive a SAS in time.');
  }

  Future<void> approveAsMemberInForeground({
    required String joinSessionId,
    required String expectedSas,
  }) async {
    if (!_validSas(expectedSas)) {
      fail('Foreground approval received no valid SAS.');
    }
    Process? process;
    final transcript = <int>[];
    var sasMatched = false;
    var sasSubmitted = false;
    var approvalSubmitted = false;
    var invalidOutput = false;
    var exitCode = -1;
    try {
      process = await Process.start(
        '/usr/bin/script',
        <String>[
          '-q',
          '/dev/null',
          config.cliBin,
          '--format',
          'json',
          'id',
          'device',
          'join',
          'approve',
          '--session',
          joinSessionId,
        ],
        environment: _environment(),
        includeParentEnvironment: false,
        runInShell: false,
      );

      void consume(List<int> bytes) {
        if (invalidOutput) return;
        if (transcript.length + bytes.length > 1024 * 1024) {
          invalidOutput = true;
          process?.kill(ProcessSignal.sigkill);
          return;
        }
        transcript.addAll(bytes);
        if (!sasMatched) {
          final localSas = remoteMultiDeviceCliApprovalSas(transcript);
          if (localSas != null) {
            sasMatched = _constantTimeAsciiEquals(localSas, expectedSas);
            if (!sasMatched) {
              invalidOutput = true;
              process?.kill(ProcessSignal.sigkill);
              return;
            }
          }
        }
        if (sasMatched &&
            !sasSubmitted &&
            remoteMultiDeviceCliRequestsSasInput(transcript)) {
          process?.stdin.writeln(expectedSas);
          unawaited(process?.stdin.flush());
          sasSubmitted = true;
        }
        if (sasSubmitted &&
            !approvalSubmitted &&
            remoteMultiDeviceCliRequestsApproval(transcript)) {
          process?.stdin.writeln('APPROVE');
          unawaited(process?.stdin.flush());
          approvalSubmitted = true;
        }
      }

      final outputDone = Future.wait<void>(<Future<void>>[
        process.stdout.listen(consume).asFuture<void>(),
        process.stderr.listen(consume).asFuture<void>(),
      ]);
      try {
        exitCode = await process.exitCode.timeout(const Duration(minutes: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
      await outputDone;
      try {
        await process.stdin.close();
      } on Object {
        // The child can close its TTY immediately after success.
      }
    } on Object {
      invalidOutput = true;
    } finally {
      if (process != null && exitCode < 0) {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on Object {
          // The scrubbed transcript below is the only retained process state.
        }
      }
      transcript.fillRange(0, transcript.length, 0);
      transcript.clear();
    }
    if (invalidOutput ||
        exitCode != 0 ||
        !sasMatched ||
        !sasSubmitted ||
        !approvalSubmitted) {
      fail('The foreground CLI member approval failed safely.');
    }
  }

  Future<_AuthorizedDevice> pollUntilAuthorized(
    String sessionId, {
    required String expectedDeviceId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final payload = await _run(<String>[
        '--format',
        'json',
        'id',
        'device',
        'join',
        'poll',
        '--session',
        sessionId,
      ]);
      final data = _data(payload, action: 'device_join_poll');
      final progress = _JoinProgress.fromData(data);
      _requireJoinIdentity(progress, sessionId, expectedDeviceId);
      if (progress.remoteState == 'consumed') {
        if (progress.sas != null) {
          fail('Terminal joining-device state retained a SAS.');
        }
        final result = data['result'];
        final authorized = result is Map
            ? _stringMap(result)['authorized_device']
            : null;
        if (authorized is! Map) {
          fail('The joining CLI returned no authorization projection.');
        }
        return _AuthorizedDevice.fromJson(_stringMap(authorized));
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The joining CLI did not become authorized in time.');
  }

  Future<List<Map<String, Object?>>> loadRegistry() async {
    final payload = await _run(const <String>[
      '--format',
      'json',
      'id',
      'device',
      'list',
    ]);
    final result = _data(payload, action: 'device_registry')['result'];
    if (result is! Map || result['devices'] is! List) {
      fail('The CLI returned no safe device Registry projection.');
    }
    return (result['devices'] as List)
        .map((value) {
          if (value is! Map) {
            fail('The CLI Registry contains an invalid device row.');
          }
          return _stringMap(value);
        })
        .toList(growable: false);
  }

  Future<List<Map<String, Object?>>> waitForRegistryDeviceCount(
    int expected,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final devices = await loadRegistry();
      if (devices.length == expected) return devices;
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The CLI Registry did not converge to $expected devices.');
  }

  Future<Map<String, Object?>> _run(
    List<String> args, {
    String? accountVerificationToken,
  }) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        config.cliBin,
        args,
        environment: _environment(
          accountVerificationToken: accountVerificationToken,
        ),
        includeParentEnvironment: false,
        runInShell: false,
      ).timeout(_remoteTimeout);
    } on Object {
      fail('The independent CLI process did not complete safely.');
    }
    if (result.exitCode != 0) {
      fail('The independent CLI command failed without exposing output.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on Object {
      fail('The independent CLI returned invalid JSON.');
    }
    if (decoded is! Map || decoded['ok'] != true) {
      fail('The independent CLI returned no successful result.');
    }
    return _stringMap(decoded);
  }

  Map<String, String> _environment({String? accountVerificationToken}) {
    final environment = <String, String>{
      'HOME': home,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': workspace,
      if (accountVerificationToken != null)
        'AWIKI_ACCOUNT_VERIFICATION_TOKEN': accountVerificationToken,
    };
    for (final name in const <String>[
      'PATH',
      'LANG',
      'LC_ALL',
      'TMPDIR',
      'SSL_CERT_FILE',
      'SSL_CERT_DIR',
      'TERM',
    ]) {
      final value = Platform.environment[name];
      if (value != null && value.trim().isNotEmpty) {
        environment[name] = value;
      }
    }
    return environment;
  }

  Future<void> deleteLocalState() async {
    await _deleteDirectory(workspace);
    await _deleteDirectory(home);
  }
}

class _JoinRequest {
  const _JoinRequest({
    required this.joinSessionId,
    required this.protocolDeviceId,
    required this.state,
    required this.claimedByCurrentDevice,
    required this.canStartVerification,
  });

  final String joinSessionId;
  final String protocolDeviceId;
  final String state;
  final bool claimedByCurrentDevice;
  final bool canStartVerification;

  factory _JoinRequest.fromJson(Map<String, Object?> json) => _JoinRequest(
    joinSessionId: _required(json, 'join_session_id'),
    protocolDeviceId: _required(json, 'protocol_device_id'),
    state: _required(json, 'state'),
    claimedByCurrentDevice: json['claimed_by_current_device'] == true,
    canStartVerification: json['can_start_verification'] == true,
  );
}

class _JoinProgress {
  const _JoinProgress({
    required this.joinSessionId,
    required this.protocolDeviceId,
    required this.remoteState,
    required this.sas,
  });

  final String joinSessionId;
  final String protocolDeviceId;
  final String remoteState;
  final String? sas;

  factory _JoinProgress.fromData(Map<String, Object?> data) {
    final result = data['result'];
    if (result is! Map) {
      fail('The CLI returned no Join progress.');
    }
    final progress = _stringMap(result);
    final session = progress['session'];
    if (session is! Map) {
      fail('The CLI returned no Join session.');
    }
    final sessionMap = _stringMap(session);
    return _JoinProgress(
      joinSessionId: _required(sessionMap, 'join_session_id'),
      protocolDeviceId: _required(sessionMap, 'protocol_device_id'),
      remoteState: _required(progress, 'remote_state'),
      sas: progress['sas']?.toString(),
    );
  }
}

class _AuthorizedDevice {
  const _AuthorizedDevice({
    required this.protocolDeviceId,
    required this.role,
    required this.managementReady,
    required this.isCurrent,
  });

  final String protocolDeviceId;
  final String role;
  final bool managementReady;
  final bool isCurrent;

  factory _AuthorizedDevice.fromJson(Map<String, Object?> json) =>
      _AuthorizedDevice(
        protocolDeviceId: _required(json, 'protocol_device_id'),
        role: _required(json, 'role'),
        managementReady: json['management_ready'] == true,
        isCurrent: json['is_current'] == true,
      );
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

AwikiEnvironmentConfig _joinOnlyEnvironment(_RemoteJoinRunConfig config) =>
    AwikiEnvironmentConfig(
      baseUrl: config.baseUrl,
      userServiceUrl: config.userServiceUrl,
      messageServiceUrl: config.messageServiceUrl,
      mailServiceUrl: config.mailServiceUrl,
      didDomain: config.didDomain,
      anpServiceUrl: config.anpServiceUrl,
      anpServiceDid: config.anpServiceDid,
      agentImEnabled: false,
      multiDeviceDeviceRevokeEnabled: false,
      multiDeviceDirectE2eeEnabled: false,
      multiDeviceGroupE2eeEnabled: false,
    );

Future<void> _openNewDeviceJoin(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(OnboardingPage).evaluate().length == 1,
    failure: 'The onboarding surface did not become visible.',
  );
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('multi-device-join-entry'),
    failure: 'The public new-device Join entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DeviceJoinPage).evaluate().length == 1,
    failure: 'The public new-device Join page did not open.',
  );
}

Future<ProviderContainer> _waitForAuthenticatedApp(
  WidgetTester tester, {
  required String expectedDid,
}) async {
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  await _pumpUntil(
    tester,
    () {
      final runtime = container.read(appRuntimeProvider);
      if (!runtime.isInitialized || runtime.isBusy) return false;
      if (runtime.activatedDid != expectedDid ||
          container.read(sessionProvider).session?.did != expectedDid) {
        fail('The App did not restore the expected authenticated identity.');
      }
      return find
              .bySemanticsIdentifier('e2e-authenticated')
              .evaluate()
              .length ==
          1;
    },
    timeout: const Duration(seconds: 45),
    failure: 'The authenticated App shell did not become stable.',
  );
  return container;
}

Future<void> _openDevicesPage(WidgetTester tester) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-settings-tab'),
    failure: 'The App settings entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().length == 1,
    failure: 'The App settings surface did not open.',
  );
  await _tapOne(
    tester,
    find.text(tester.element(find.byType(SettingsPage)).l10n.settingsDevices),
    failure: 'The App Devices entry was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DevicesPage).evaluate().length == 1,
    failure: 'The App Devices surface did not open.',
  );
}

Future<void> _syncAppJoinInboxUntil(
  ProviderContainer container, {
  required String reason,
  required bool Function() condition,
  required String failure,
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await container
        .read(messageSyncCoordinatorProvider.notifier)
        .requestSync(reason, immediate: true);
    await container.read(devicesProvider.notifier).refreshJoinInbox();
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 750));
  }
  fail(failure);
}

Future<String> _requestAndResolveOtp({
  required http.Client client,
  required _RemoteJoinRunConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
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
              'rate_limit_seconds': 30,
              'code_expire_minutes': 5,
            }),
          )
          .timeout(_remoteTimeout);
    } on Object {
      fail('The purpose-bound OTP request failed safely.');
    }
    if (response.statusCode != 429 || attempt == 1) break;
    await Future<void>.delayed(const Duration(seconds: 31));
  }
  if (response == null) {
    fail('The purpose-bound OTP request was rejected.');
  }
  try {
    return continueRemoteMultiDeviceOtpAfterSmsResponse(
      statusCode: response.statusCode,
      contentType: response.headers['content-type'],
      body: response.body,
      allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      resolveOtp: () => _resolveOtp(
        account: account,
        purpose: purpose,
        handle: handle,
        didDomain: config.didDomain,
      ),
    );
  } on FormatException {
    fail('The purpose-bound OTP response was invalid.');
  }
}

Future<String> _resolveOtp({
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  required String didDomain,
}) async {
  final Process process;
  try {
    process = await Process.start(
      account.otpCommand.first,
      account.otpCommand.skip(1).toList(growable: false),
      runInShell: false,
    );
  } on Object {
    fail('The dedicated OTP resolver transport failed safely.');
  }
  process.stdin.write(
    jsonEncode(<String, Object?>{
      'phone': account.phone,
      'purpose': purpose,
      'target_handle': handle,
      'target_handle_domain': didDomain,
      'recovery_session_id': null,
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
    fail('The dedicated OTP resolver timed out.');
  }
  final stdout = await stdoutFuture;
  await stderrFuture;
  if (exitCode != 0 || stdout.length > 1024) {
    fail('The dedicated OTP resolver failed without exposing output.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(stdout);
  } on Object {
    fail('The dedicated OTP resolver returned invalid JSON.');
  }
  if (decoded is! Map ||
      decoded.length != 1 ||
      decoded['otp'] is! String ||
      !isSixDigitAsciiOtp(decoded['otp'] as String)) {
    fail('The dedicated OTP resolver returned an invalid response.');
  }
  return decoded['otp'] as String;
}

Future<String> _exchangeJoinGrant({
  required http.Client client,
  required _RemoteJoinRunConfig config,
  required _DedicatedAccount account,
  required String handle,
  required String otp,
  required String operationId,
}) async {
  final http.Response response;
  try {
    response = await client
        .post(
          Uri.parse(
            config.userServiceUrl,
          ).resolve('/user-service/auth/account-verification/exchange'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'provider': 'sms',
            'purpose': _joinPurpose,
            'phone': account.phone,
            'code': otp,
            'target_handle': handle,
            'target_handle_domain': config.didDomain,
            'idempotency_scope': operationId,
          }),
        )
        .timeout(_remoteTimeout);
  } on Object {
    fail('The Join account-verification exchange failed safely.');
  }
  if (response.statusCode != 200) {
    fail('The Join account-verification exchange was rejected.');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on Object {
    fail('The Join account-verification exchange returned invalid JSON.');
  }
  if (decoded is! Map || decoded['purpose'] != _joinPurpose) {
    fail('The Join account-verification exchange returned an invalid scope.');
  }
  final token = decoded['account_verification_token'];
  if (token is! String || token.trim().isEmpty) {
    fail('The Join account-verification exchange returned no grant.');
  }
  return token;
}

String _requireCliReadyBootstrapAdmin(List<Map<String, Object?>> devices) {
  if (devices.length != 1) {
    fail('The CLI bootstrap Registry did not contain exactly one device.');
  }
  final device = devices.single;
  if (device['is_current'] != true ||
      device['role'] != 'admin' ||
      device['management_ready'] != true ||
      device['status'] != 'active') {
    fail('The CLI bootstrap device was not the active ready admin.');
  }
  return _required(device, 'protocol_device_id');
}

String _requireAppReadyBootstrapAdmin(DeviceRegistrySnapshot registry) {
  if (registry.devices.length != 1) {
    fail('The App bootstrap Registry did not contain exactly one device.');
  }
  final device = registry.devices.single;
  if (!device.isCurrent ||
      device.role != DeviceRole.admin ||
      !device.managementReady ||
      device.status != DeviceStatus.active) {
    fail('The App bootstrap device was not the active ready admin.');
  }
  return device.protocolDeviceId;
}

void _requireCliAdminAndMember(
  List<Map<String, Object?>> devices, {
  required String bootstrapAdminDeviceId,
  required String joinedDeviceId,
}) {
  final admin = devices
      .where(
        (device) =>
            device['protocol_device_id'] == bootstrapAdminDeviceId &&
            device['is_current'] == true &&
            device['role'] == 'admin' &&
            device['management_ready'] == true &&
            device['status'] == 'active',
      )
      .toList(growable: false);
  final member = devices
      .where(
        (device) =>
            device['protocol_device_id'] == joinedDeviceId &&
            device['is_current'] != true &&
            device['role'] == 'member' &&
            device['management_ready'] == false &&
            device['status'] == 'active',
      )
      .toList(growable: false);
  if (devices.length != 2 || admin.length != 1 || member.length != 1) {
    fail('The CLI did not resolve one current admin and one joined member.');
  }
}

void _requireCliJoinedMember(
  List<Map<String, Object?>> devices, {
  required String joinedDeviceId,
}) {
  final currentMember = devices
      .where(
        (device) =>
            device['protocol_device_id'] == joinedDeviceId &&
            device['is_current'] == true &&
            device['role'] == 'member' &&
            device['management_ready'] == false &&
            device['status'] == 'active',
      )
      .toList(growable: false);
  final readyAdmin = devices
      .where(
        (device) =>
            device['protocol_device_id'] != joinedDeviceId &&
            device['is_current'] != true &&
            device['role'] == 'admin' &&
            device['management_ready'] == true &&
            device['status'] == 'active',
      )
      .toList(growable: false);
  if (devices.length != 2 ||
      currentMember.length != 1 ||
      readyAdmin.length != 1) {
    fail('The joined CLI Registry did not contain the expected member/admin.');
  }
}

void _requireAppCurrentMember(
  DeviceRegistrySnapshot registry, {
  required String bootstrapAdminDeviceId,
  required String joinedDeviceId,
}) {
  final currentMember = registry.devices
      .where(
        (device) =>
            device.protocolDeviceId == joinedDeviceId &&
            device.isCurrent &&
            device.role == DeviceRole.member &&
            !device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  final readyAdmin = registry.devices
      .where(
        (device) =>
            device.protocolDeviceId == bootstrapAdminDeviceId &&
            !device.isCurrent &&
            device.role == DeviceRole.admin &&
            device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  if (registry.devices.length != 2 ||
      currentMember.length != 1 ||
      readyAdmin.length != 1) {
    fail('The joined App Registry did not contain the expected member/admin.');
  }
}

void _requireAppAdminAndMember(
  DeviceRegistrySnapshot registry, {
  required String bootstrapAdminDeviceId,
  required String joinedDeviceId,
}) {
  final currentAdmin = registry.devices
      .where(
        (device) =>
            device.protocolDeviceId == bootstrapAdminDeviceId &&
            device.isCurrent &&
            device.role == DeviceRole.admin &&
            device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  final member = registry.devices
      .where(
        (device) =>
            device.protocolDeviceId == joinedDeviceId &&
            !device.isCurrent &&
            device.role == DeviceRole.member &&
            !device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  if (registry.devices.length != 2 ||
      currentAdmin.length != 1 ||
      member.length != 1) {
    fail('The App Registry did not contain the expected admin/member.');
  }
}

void _requireJoinIdentity(
  _JoinProgress progress,
  String sessionId,
  String deviceId,
) {
  if (progress.joinSessionId != sessionId ||
      progress.protocolDeviceId != deviceId) {
    fail('The CLI changed the selected Join identity.');
  }
}

void _failOnDeviceError(DevicesState state, String context) {
  final error = state.error;
  if (error != null) {
    fail('$context with safe error ${error.name}.');
  }
}

void _requireIndependentEmptyPaths(List<String> paths) {
  final roots = paths.map((path) => Directory(path).absolute.path).toSet();
  if (roots.length != paths.length) {
    fail('The App and CLI did not receive independent local roots.');
  }
  for (final candidate in roots) {
    for (final other in roots) {
      if (candidate != other &&
          candidate.startsWith('$other${Platform.pathSeparator}')) {
        fail('The App and CLI local roots must not be nested.');
      }
    }
  }
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync() ||
        directory.listSync(followLinks: false).isNotEmpty) {
      fail('A multi-device E2E local root was missing or not fresh.');
    }
  }
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
  if (!condition()) fail(failure);
}

Future<void> _tapOne(
  WidgetTester tester,
  Finder finder, {
  required String failure,
}) async {
  final target = finder.hitTestable();
  if (target.evaluate().length != 1) fail(failure);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> _enterText(
  WidgetTester tester,
  String semanticsIdentifier,
  String value,
) async {
  final editable = find.descendant(
    of: find.bySemanticsIdentifier(semanticsIdentifier),
    matching: find.byType(EditableText),
  );
  if (editable.evaluate().length != 1) {
    fail('The $semanticsIdentifier field was unavailable.');
  }
  await tester.ensureVisible(editable);
  await tester.enterText(editable, value);
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

Map<String, Object?> _map(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! Map) {
    throw StateError('Remote multi-device config is invalid.');
  }
  return _stringMap(value);
}

String _required(Map<String, Object?> map, String key) {
  final value = map[key]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw StateError('Remote multi-device config is incomplete.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw StateError('Remote multi-device config is incomplete.');
  }
  return value;
}

String _uniqueHandle(String prefix) => '$prefix${_nonce(10)}';

String _nonce(int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List<String>.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}

String _safeId(String value, int maxLength) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (safe.isEmpty) return 'run';
  return safe.length <= maxLength ? safe : safe.substring(0, maxLength);
}

bool _validSas(String value) => RegExp(r'^\d{6}$').hasMatch(value);

bool _constantTimeAsciiEquals(String first, String second) {
  if (first.length != second.length) return false;
  var difference = 0;
  for (var index = 0; index < first.length; index += 1) {
    difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
  }
  return difference == 0;
}
