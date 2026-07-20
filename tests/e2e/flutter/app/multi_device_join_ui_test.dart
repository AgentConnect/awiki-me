// [INPUT]: Audited awiki.info endpoints, a dedicated account/SSH OTP resolver,
//          production AppBootstrap/native Core, and independent CLI/App roots.
// [OUTPUT]: Real bidirectional Join plus registered root-import, permanent-
//           revoke, and same-DID MLS lifecycle evidence from sibling parts.
// [POS]: Activation-gated remote product E2E; no fake port, copied state,
//        static OTP, production bypass, or secret-bearing report is permitted.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/data/services/local_auth_user_presence_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/group_encryption_status.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/group/group_encryption_status_card.dart';
import 'package:awiki_me/src/presentation/group/group_encryption_provider.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
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

part 'root_key_transfer_ui_test.dart';
part 'mls_multi_device_ui_test.dart';

const String _newDeviceCaseId = 'DEVICE-JOIN-E2E-001';
const String _adminApprovalCaseId = 'DEVICE-JOIN-E2E-002';
const String _runConfigPath =
    '.e2e/multi-device-remote-join/current/run_config.json';
const String _mlsRunConfigPath =
    '.e2e/multi-device-remote-mls/current/run_config.json';
const String _activationGate = 'AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED';
const String _phoneEnv = 'AWIKI_MULTI_DEVICE_E2E_PHONE';
const String _otpCommandEnv = 'AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON';
const String _genesisPurpose = 'awiki.device.genesis.v1';
const String _joinPurpose = 'awiki.device.join.v1';
const Duration _remoteTimeout = Duration(seconds: 30);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real AWiki Me joins an existing CLI admin as an authorized member',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final cli = _JoiningCli.admin(config);
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireIndependentEmptyPaths(_allLocalRoots(config));
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await cli.deleteLocalState();
        final appRoot = Directory(config.appJoiningStateRoot);
        if (await appRoot.exists()) {
          await appRoot.delete(recursive: true);
        }
        await tester.binding.setSurfaceSize(null);
      });

      if (!Platform.isMacOS || !File('/usr/bin/script').existsSync()) {
        fail(
          'The remote App-new-device Join gate requires a foreground macOS pseudo-terminal.',
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
      final initialCliRegistry = await cli.loadRegistrySnapshot();
      final bootstrapAdminDeviceId = _requireCliReadyBootstrapAdmin(
        initialCliRegistry,
      );

      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.appJoiningStateRoot,
      );
      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        failure:
            'The unauthenticated onboarding surface did not become visible.',
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('multi-device-join-entry'),
        failure: 'The public new-device Join entry was not visible.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinPage).evaluate().length == 1,
        failure: 'The public new-device Join page did not open.',
      );

      final joinOtp = await _requestAndResolveOtp(
        client: httpClient,
        config: config,
        account: account,
        purpose: _joinPurpose,
        handle: handle,
      );
      await _enterText(
        tester,
        'multi-device-join-handle',
        handle,
        failure: 'The new-device Handle field was unavailable.',
      );
      await _enterText(
        tester,
        'multi-device-join-phone',
        account.phone,
        failure: 'The new-device phone field was unavailable.',
      );
      await _enterText(
        tester,
        'multi-device-join-otp',
        joinOtp,
        failure: 'The new-device OTP field was unavailable.',
      );
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
          final progress = container.read(devicesProvider).activeJoin;
          return progress?.side == DeviceJoinSide.newDevice &&
              progress?.phase == DeviceJoinPhase.pending &&
              progress?.remoteState == DeviceJoinRemoteState.pending &&
              progress?.sas == null;
        },
        timeout: const Duration(seconds: 45),
        failure:
            'The App OTP did not leave the new device pending without SAS.',
      );
      if (find.byKey(const Key('device-join-sas')).evaluate().isNotEmpty) {
        fail('The App displayed a SAS before the CLI admin claimed the Join.');
      }
      final appPending = container.read(devicesProvider).activeJoin!;

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      bootstrap = null;
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(config),
        appStateRoot: config.appJoiningStateRoot,
      );
      final restoredSessions = await bootstrap.deviceManagementCorePort!
          .localDeviceJoinSessions();
      final restored = restoredSessions
          .where((session) => session.joinSessionId == appPending.joinSessionId)
          .toList(growable: false);
      if (restored.length != 1 ||
          restored.single.protocolDeviceId != appPending.protocolDeviceId ||
          restored.single.side != DeviceJoinSide.newDevice ||
          restored.single.isTerminal ||
          restored.single.sas != null) {
        fail('The restarted App did not restore one secret-free pending Join.');
      }
      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        failure: 'The restarted App onboarding surface did not become visible.',
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('multi-device-join-entry'),
        failure: 'The restarted App Join entry was not visible.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinPage).evaluate().length == 1,
        failure: 'The restarted App Join page did not open.',
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceJoinPage)),
      );
      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          return progress?.joinSessionId == appPending.joinSessionId &&
              progress?.protocolDeviceId == appPending.protocolDeviceId &&
              progress?.side == DeviceJoinSide.newDevice &&
              !progress!.isTerminal &&
              progress.sas == null;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The restarted App did not resume the same pending Join.',
      );
      final pending = await cli.pollUntilOnlyPendingJoin(
        expectedDeviceId: appPending.protocolDeviceId,
      );
      if (pending.joinSessionId != appPending.joinSessionId) {
        fail('The App and CLI did not bind the same pending Join session.');
      }

      await cli.claimJoin(pending);
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('multi-device-refresh-join'),
        failure: 'The App new-device refresh action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.byKey(const Key('device-join-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The App new device did not derive its Join SAS.',
      );
      final appSas =
          tester.widget<Text>(find.byKey(const Key('device-join-sas'))).data ??
          '';
      final cliProgress = await cli.pollAdminUntilSas(
        pending.joinSessionId,
        expectedDeviceId: pending.protocolDeviceId,
      );
      if (!_validSas(appSas) ||
          !_constantTimeAsciiEquals(appSas, cliProgress.sas!)) {
        fail('The independently derived App and CLI SAS values did not match.');
      }

      await cli.approveJoinAsMember(
        joinSessionId: pending.joinSessionId,
        expectedDeviceId: pending.protocolDeviceId,
        expectedSas: appSas,
      );
      await _pumpUntil(
        tester,
        () {
          final progress = container.read(devicesProvider).activeJoin;
          return progress?.phase == DeviceJoinPhase.authorized &&
              progress?.remoteState == DeviceJoinRemoteState.consumed;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The App new device did not converge to authorized.',
      );
      final authorized = container.read(devicesProvider).activeJoin!;
      if (authorized.sas != null ||
          authorized.authorizedDevice?.protocolDeviceId !=
              pending.protocolDeviceId ||
          authorized.authorizedDevice?.role != DeviceRole.member ||
          authorized.authorizedDevice?.managementReady != false ||
          authorized.authorizedDevice?.isCurrent != true) {
        fail(
          'The App did not project the joined device as the current member.',
        );
      }
      if (find.byKey(const Key('device-join-sas')).evaluate().isNotEmpty) {
        fail('The authorized App state retained a displayable SAS.');
      }
      final appRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(did);
      _requireAppCurrentMemberRegistry(
        appRegistry,
        protocolDeviceId: pending.protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
      );
      _requireCliCurrentAdminRegistry(
        await cli.loadRegistrySnapshot(),
        protocolDeviceId: pending.protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
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
    'real AWiki Me ready admin approves an independent CLI device as member',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      final cli = _JoiningCli.joining(config);
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireIndependentEmptyRoots(config);
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await cli.deleteLocalState();
        final appRoot = Directory(config.appStateRoot);
        if (await appRoot.exists()) {
          await appRoot.delete(recursive: true);
        }
        await tester.binding.setSurfaceSize(null);
      });

      if (!await LocalAuthentication().isDeviceSupported()) {
        fail(
          'The remote App-admin Join gate requires real operating-system user presence.',
        );
      }
      await cli.initialize();

      final environment = _joinOnlyEnvironment(config);
      bootstrap = await AppBootstrap.create(
        environment: environment,
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
      final AppSession adminSession;
      try {
        adminSession = await bootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: genesisOtp,
              handle: handle,
              nickName: 'AWiki multi-device E2E',
            );
      } on Object {
        fail('App bootstrap registration failed without exposing remote data.');
      }
      if (!adminSession.authenticated) {
        fail('The App bootstrap identity was not authenticated.');
      }
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(adminSession.did);
      final bootstrapAdminDeviceId = _requireReadyBootstrapAdmin(
        initialRegistry,
      );

      final joinOperation = 'app-join-${_nonce(10)}';
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
        operationId: joinOperation,
      );
      final started = await cli.startJoin(
        did: adminSession.did,
        operationId: joinOperation,
        accountVerificationToken: grant,
      );
      if (started.remoteState != 'pending' || started.sas != null) {
        fail('OTP did not leave the joining device pending without SAS.');
      }

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
          .activateSession(adminSession.toLegacySessionIdentity());
      await _pumpUntil(
        tester,
        () =>
            find.bySemanticsIdentifier('e2e-authenticated').evaluate().length ==
            1,
        failure: 'The authenticated App shell did not become visible.',
      );

      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-settings-tab'),
        failure: 'The App settings entry was not visible.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(SettingsPage).evaluate().length == 1,
        failure: 'The App settings surface did not open.',
      );
      await _tapOne(
        tester,
        find.text(
          tester.element(find.byType(SettingsPage)).l10n.settingsDevices,
        ),
        failure: 'The App Devices entry was not visible.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DevicesPage).evaluate().length == 1,
        failure: 'The App Devices surface did not open.',
      );
      await _pumpUntil(
        tester,
        () => find.text(started.protocolDeviceId).evaluate().length == 1,
        timeout: const Duration(seconds: 30),
        failure: 'The pending joining device did not appear in the App.',
      );
      await _tapOne(
        tester,
        find.text(started.protocolDeviceId),
        failure: 'The pending joining device could not be opened.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(DeviceJoinApprovalSheet).evaluate().length == 1,
        failure: 'The App Join approval surface did not open.',
      );

      final joiningProgress = await cli.pollUntilSas(
        started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      await _pumpUntil(
        tester,
        () =>
            find.byKey(const Key('device-approval-sas')).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The App did not derive a Join SAS.',
      );
      final appSasWidget = tester.widget<Text>(
        find.byKey(const Key('device-approval-sas')),
      );
      final appSas = appSasWidget.data ?? '';
      if (!_validSas(appSas) ||
          !_constantTimeAsciiEquals(appSas, joiningProgress.sas!)) {
        fail('The independently derived Join SAS values did not match.');
      }

      final sasSwitch = find.descendant(
        of: find.byKey(const Key('device-sas-confirmation')),
        matching: find.byType(CupertinoSwitch),
      );
      final adminSwitch = find.descendant(
        of: find.byKey(const Key('device-admin-toggle')),
        matching: find.byType(CupertinoSwitch),
      );
      if (tester.widget<CupertinoSwitch>(adminSwitch).value) {
        fail('The App selected the admin role without explicit user intent.');
      }
      final approveAction = find.bySemanticsIdentifier('multi-device-approve');
      if (approveAction.evaluate().isNotEmpty) {
        fail('The App enabled approval before explicit SAS confirmation.');
      }
      await _tapOne(
        tester,
        sasSwitch,
        failure: 'The SAS confirmation control was not available.',
      );
      await _pumpUntil(
        tester,
        () => approveAction.evaluate().length == 1,
        failure: 'The App did not enable approval after SAS confirmation.',
      );
      await _tapOne(
        tester,
        approveAction,
        failure: 'The default-member approval action was not available.',
      );
      await _pumpUntil(
        tester,
        () {
          if (presence.calls > 1) {
            fail('The App requested user presence more than once.');
          }
          if (presence.completions == 1 && !presence.lastResult) {
            fail('The real operating-system user-presence check was denied.');
          }
          return presence.completions == 1 &&
              presence.lastResult &&
              approveAction.evaluate().isEmpty;
        },
        timeout: const Duration(minutes: 2),
        failure:
            'The App approval did not complete after real user presence; approve the operating-system prompt.',
      );
      if (presence.calls != 1 ||
          presence.completions != 1 ||
          !presence.lastResult) {
        fail('The App did not complete exactly one real user-presence check.');
      }

      final activated = await cli.pollUntilAuthorized(
        started.joinSessionId,
        expectedDeviceId: started.protocolDeviceId,
      );
      if (activated.protocolDeviceId != started.protocolDeviceId ||
          activated.role != 'member' ||
          activated.managementReady ||
          !activated.isCurrent) {
        fail(
          'The joining CLI device was not activated as a member with management_ready=false.',
        );
      }
      final cliRegistry = await cli.loadRegistry();
      _requireJoinedMemberRegistry(
        cliRegistry,
        protocolDeviceId: started.protocolDeviceId,
      );
      final appRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(adminSession.did);
      _requireAppRegistryMember(
        appRegistry,
        protocolDeviceId: started.protocolDeviceId,
        bootstrapAdminDeviceId: bootstrapAdminDeviceId,
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

  _registerRootKeyTransferAndRevokeTests();
  _registerMlsMultiDeviceTests();
}

bool _invocationExpects(String caseId) {
  const encoded = String.fromEnvironment(e2eCaseIdsDefine);
  if (encoded.trim().isEmpty) {
    return true;
  }
  return encoded.split(',').map((value) => value.trim()).contains(caseId);
}

String get _activeRunConfigPath {
  const encoded = String.fromEnvironment(e2eCaseIdsDefine);
  return encoded.trim().isNotEmpty && _invocationExpects(_mlsReadinessCaseId)
      ? _mlsRunConfigPath
      : _runConfigPath;
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

  static bool exists() => File(_activeRunConfigPath).existsSync();

  static _RemoteJoinRunConfig load() {
    if (Platform.environment[_activationGate]?.trim() != '1') {
      throw StateError(
        'Remote multi-device App Join is not explicitly enabled.',
      );
    }
    final file = File(_activeRunConfigPath);
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 2 ||
        decoded['enabled'] != true) {
      throw StateError('Remote multi-device Join run config is invalid.');
    }
    final root = _stringMap(decoded);
    final service = _map(root, 'service');
    final account = _map(root, 'account');
    final cli = _map(root, 'cliJoiningDevice');
    final cliAdmin = _map(root, 'cliAdminDevice');
    final app = _map(root, 'app');
    final appJoining = _map(root, 'appJoiningDevice');
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
      cliBin: _required(cli, 'binary'),
      cliSourceRef: _required(cli, 'sourceRef'),
      cliWorkspace: _required(cli, 'workspace'),
      cliHome: _required(cli, 'home'),
      cliAdminWorkspace: _required(cliAdmin, 'workspace'),
      cliAdminHome: _required(cliAdmin, 'home'),
      appStateRoot: _required(app, 'stateRoot'),
      appJoiningStateRoot: _required(appJoining, 'stateRoot'),
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
        throw StateError(
          'Remote multi-device Join service target is not audited.',
        );
      }
    }
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(config.cliSourceRef) ||
        RegExp(r'^0{40}$').hasMatch(config.cliSourceRef)) {
      throw StateError('Remote multi-device Join CLI source is not auditable.');
    }
    if (_required(cliAdmin, 'binary') != config.cliBin ||
        _required(cliAdmin, 'sourceRef') != config.cliSourceRef) {
      throw StateError(
        'Remote multi-device Join CLI devices do not share one audited build.',
      );
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
    final rawCommand = Platform.environment[_otpCommandEnv]?.trim() ?? '';
    if (phone.isEmpty || rawCommand.isEmpty) {
      throw StateError(
        'Dedicated multi-device account configuration is missing.',
      );
    }
    final bool environmentAllowsStagedOtp;
    try {
      environmentAllowsStagedOtp = parseRemoteMultiDeviceStagedOtpFlag(
        Platform.environment,
      );
    } on FormatException {
      throw StateError('Dedicated multi-device staged OTP mode is invalid.');
    }
    if (environmentAllowsStagedOtp != allowStagedOtpOnSmsError) {
      throw StateError(
        'Dedicated multi-device staged OTP mode does not match the runner.',
      );
    }
    final List<String> command;
    try {
      command = parseRemoteMultiDeviceOtpCommand(
        rawCommand,
        requireReviewedStagedResolver: allowStagedOtpOnSmsError,
      );
    } on FormatException {
      throw StateError('Dedicated multi-device OTP resolver is invalid.');
    }
    return _DedicatedAccount(
      phone: phone,
      otpCommand: List<String>.unmodifiable(command),
    );
  }
}

class _JoiningCli {
  _JoiningCli(
    this.config, {
    this.rootTransferEnabled = false,
    this.deviceRevokeEnabled = false,
    this.directE2eeEnabled = false,
    this.groupE2eeEnabled = false,
  }) : workspace = config.cliWorkspace,
       home = config.cliHome,
       _tenantName = 'e2e-${_safeId(config.runId, 36)}';

  _JoiningCli._(
    this.config, {
    required this.workspace,
    required this.home,
    required String role,
  }) : rootTransferEnabled = false,
       deviceRevokeEnabled = false,
       directE2eeEnabled = false,
       groupE2eeEnabled = false,
       _tenantName = 'e2e-${_safeId(config.runId, 28)}-${_safeId(role, 8)}';

  factory _JoiningCli.joining(_RemoteJoinRunConfig config) =>
      _JoiningCli(config);

  factory _JoiningCli.admin(_RemoteJoinRunConfig config) => _JoiningCli._(
    config,
    workspace: config.cliAdminWorkspace,
    home: config.cliAdminHome,
    role: 'admin',
  );

  final _RemoteJoinRunConfig config;
  final String workspace;
  final String home;
  final bool rootTransferEnabled;
  final bool deviceRevokeEnabled;
  final bool directE2eeEnabled;
  final bool groupE2eeEnabled;
  final String _tenantName;

  Future<void> initialize() async {
    await Directory(workspace).create(recursive: true);
    await Directory(home).create(recursive: true);
    final version = await _run(const <String>['--format', 'json', 'version']);
    final versionData = _data(version, action: null);
    if (versionData['commit'] != config.cliSourceRef) {
      fail('The joining CLI binary does not match its audited source commit.');
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
    final data = _data(payload, action: 'register_handle');
    final identity = data['identity'];
    if (identity is! Map) {
      fail('The CLI bootstrap returned no safe identity projection.');
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
      if (progress.joinSessionId != sessionId ||
          progress.protocolDeviceId != expectedDeviceId) {
        fail('The joining CLI changed the active Join identity while polling.');
      }
      if (progress.remoteState == 'response_verified' &&
          _validSas(progress.sas ?? '')) {
        return progress;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The joining CLI device did not derive its SAS in time.');
  }

  Future<_CliPendingJoin> pollUntilOnlyPendingJoin({
    required String expectedDeviceId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final registry = await loadRegistrySnapshot();
      if (registry.pending.length == 1 &&
          registry.pending.single.protocolDeviceId == expectedDeviceId) {
        return registry.pending.single;
      }
      if (registry.pending.length > 1) {
        fail('The CLI admin observed more than one pending Join request.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The CLI admin did not observe the App pending Join in time.');
  }

  Future<void> claimJoin(_CliPendingJoin pending) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'device',
      'join',
      'claim',
      '--session',
      pending.joinSessionId,
      '--operation-id',
      'app-admin-claim-${_nonce(10)}',
    ]);
    final progress = _JoinProgress.fromData(
      _data(payload, action: 'device_join_claim'),
    );
    if (progress.joinSessionId != pending.joinSessionId ||
        progress.protocolDeviceId != pending.protocolDeviceId ||
        progress.remoteState != 'challenge_sent' ||
        progress.sas != null) {
      fail('The CLI admin did not submit exactly one Join challenge.');
    }
  }

  Future<_JoinProgress> pollAdminUntilSas(
    String sessionId, {
    required String expectedDeviceId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final data = await _pollAdminData(sessionId);
      final progress = _JoinProgress.fromData(data);
      if (progress.joinSessionId != sessionId ||
          progress.protocolDeviceId != expectedDeviceId) {
        fail('The CLI admin changed the active Join identity while polling.');
      }
      if (progress.remoteState == 'response_verified' &&
          _validSas(progress.sas ?? '')) {
        return progress;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The CLI admin did not derive its SAS in time.');
  }

  Future<void> approveJoinAsMember({
    required String joinSessionId,
    required String expectedDeviceId,
    required String expectedSas,
  }) async {
    await _runForegroundMemberApproval(
      joinSessionId: joinSessionId,
      expectedSas: expectedSas,
    );
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final data = await _pollAdminData(joinSessionId);
      final progress = _JoinProgress.fromData(data);
      if (progress.joinSessionId != joinSessionId ||
          progress.protocolDeviceId != expectedDeviceId) {
        fail('The CLI approval changed the active Join identity.');
      }
      if (progress.remoteState == 'consumed') {
        if (progress.sas != null) {
          fail('The terminal CLI approval state retained a SAS.');
        }
        final rawDevice = data['result'];
        final result = rawDevice is Map ? _stringMap(rawDevice) : null;
        final authorized = result?['authorized_device'];
        if (authorized is! Map) {
          fail('The CLI approval returned no authorization projection.');
        }
        final device = _AuthorizedDevice.fromJson(_stringMap(authorized));
        if (device.protocolDeviceId != expectedDeviceId ||
            device.role != 'member' ||
            device.managementReady) {
          fail('The CLI did not authorize the App as a rootless member.');
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The CLI member approval did not converge in time.');
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
      if (progress.joinSessionId != sessionId ||
          progress.protocolDeviceId != expectedDeviceId) {
        fail('The joining CLI changed the active Join identity while polling.');
      }
      if (data['remote_state'] == 'consumed') {
        if (data['sas'] != null) {
          fail('Terminal joining-device state retained a SAS.');
        }
        final device = data['authorized_device'];
        if (device is! Map) {
          fail('The joining CLI device returned no authorization projection.');
        }
        return _AuthorizedDevice.fromJson(_stringMap(device));
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The joining CLI device did not become authorized in time.');
  }

  Future<_CliRegistrySnapshot> loadRegistrySnapshot() async {
    final payload = await _run(const <String>[
      '--format',
      'json',
      'id',
      'device',
      'list',
    ]);
    final result = _data(payload, action: 'device_registry')['result'];
    if (result is! Map ||
        result['devices'] is! List ||
        result['pending_join_requests'] is! List) {
      fail('The CLI device returned no safe Registry projection.');
    }
    final devices = (result['devices'] as List)
        .map((value) {
          if (value is! Map) {
            fail('The CLI Registry contains an invalid device row.');
          }
          return _stringMap(value);
        })
        .toList(growable: false);
    final pending = (result['pending_join_requests'] as List)
        .map((value) {
          if (value is! Map) {
            fail('The CLI Registry contains an invalid pending Join row.');
          }
          return _CliPendingJoin.fromJson(_stringMap(value));
        })
        .toList(growable: false);
    return _CliRegistrySnapshot(devices: devices, pending: pending);
  }

  Future<List<Map<String, Object?>>> loadRegistry() async =>
      (await loadRegistrySnapshot()).devices;

  Future<Map<String, Object?>> _pollAdminData(String sessionId) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'id',
      'device',
      'join',
      'poll',
      '--session',
      sessionId,
      '--admin',
    ]);
    return _data(payload, action: 'device_join_admin_poll');
  }

  Future<void> _runForegroundMemberApproval({
    required String joinSessionId,
    required String expectedSas,
  }) async {
    if (!_validSas(expectedSas)) {
      fail('The foreground CLI approval received no valid SAS.');
    }
    Process? process;
    final transcript = <int>[];
    var localSasMatched = false;
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
          '--role',
          'member',
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
        if (!localSasMatched) {
          final localSas = remoteMultiDeviceCliApprovalSas(transcript);
          if (localSas != null) {
            localSasMatched = _constantTimeAsciiEquals(localSas, expectedSas);
            if (!localSasMatched) {
              invalidOutput = true;
              process?.kill(ProcessSignal.sigkill);
              return;
            }
          }
        }
        if (localSasMatched &&
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
        // The child may close its TTY immediately after rendering success.
      }
    } on Object {
      invalidOutput = true;
    } finally {
      if (process != null && exitCode < 0) {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on Object {
          // The transcript is still erased below and the gate fails closed.
        }
      }
      transcript.fillRange(0, transcript.length, 0);
      transcript.clear();
    }
    if (invalidOutput ||
        exitCode != 0 ||
        !localSasMatched ||
        !sasSubmitted ||
        !approvalSubmitted) {
      fail('The foreground CLI member approval failed safely.');
    }
  }

  Future<void> syncInbox() async {
    final payload = await _run(const <String>[
      '--format',
      'json',
      'msg',
      'inbox',
      '--limit',
      '20',
    ]);
    if (_containsRootControlProjection(payload)) {
      fail('The CLI inbox exposed root-control content to the product layer.');
    }
  }

  Future<List<Map<String, Object?>>> loadRootTransfers() async {
    final payload = await _run(const <String>[
      '--format',
      'json',
      'id',
      'device',
      'root-key',
      'list',
      '--include-completed',
    ]);
    final result = _data(payload, action: 'root_key_transfer_list')['result'];
    if (result is! List) {
      fail('The joining CLI returned no safe root-transfer projection.');
    }
    return result
        .map((value) {
          if (value is! Map) {
            fail('The joining CLI root-transfer projection is invalid.');
          }
          return _stringMap(value);
        })
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _run(
    List<String> args, {
    String? accountVerificationToken,
  }) async {
    final result = await _runProcess(
      args,
      accountVerificationToken: accountVerificationToken,
    );
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

  Future<String> _runForErrorCode(List<String> args) async {
    final result = await _runProcess(args);
    if (result.exitCode == 0) {
      fail('The independent CLI unexpectedly accepted the operation.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on Object {
      fail('The independent CLI returned invalid error JSON.');
    }
    if (decoded is! Map || decoded['ok'] != false || decoded['error'] is! Map) {
      fail('The independent CLI returned no safe error projection.');
    }
    final error = _stringMap(decoded['error'] as Map);
    final code = error['code']?.toString().trim() ?? '';
    if (code.isEmpty) {
      fail('The independent CLI returned no stable error code.');
    }
    return code;
  }

  Future<ProcessResult> _runProcess(
    List<String> args, {
    String? accountVerificationToken,
  }) async {
    final environment = _environment(
      accountVerificationToken: accountVerificationToken,
    );
    try {
      return await Process.run(
        config.cliBin,
        args,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: false,
      ).timeout(_remoteTimeout);
    } on Object {
      fail('The independent CLI process did not complete safely.');
    }
  }

  Map<String, String> _environment({String? accountVerificationToken}) {
    final environment = <String, String>{
      'HOME': home,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': workspace,
      'AWIKI_MULTI_DEVICE_JOIN_ENABLED': '1',
      if (rootTransferEnabled) 'AWIKI_MULTI_DEVICE_ROOT_TRANSFER_ENABLED': '1',
      if (deviceRevokeEnabled) 'AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED': '1',
      if (directE2eeEnabled) 'AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED': '1',
      if (groupE2eeEnabled) 'AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED': '1',
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
    for (final path in <String>[workspace, home]) {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
}

bool _containsRootControlProjection(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (_isRootControlMarker(entry.key.toString()) ||
          _containsRootControlProjection(entry.value)) {
        return true;
      }
    }
    return false;
  }
  if (value is Iterable) {
    return value.any(_containsRootControlProjection);
  }
  return value is String && _isRootControlMarker(value);
}

bool _isRootControlMarker(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('root_private_key') ||
      normalized.contains('rootkeyenvelope') ||
      normalized.contains('root-key-transfer') ||
      normalized.contains('root_key_imported_ack') ||
      normalized.contains('system_type') ||
      normalized == 'ciphertext';
}

class _CliRegistrySnapshot {
  const _CliRegistrySnapshot({required this.devices, required this.pending});

  final List<Map<String, Object?>> devices;
  final List<_CliPendingJoin> pending;
}

class _CliPendingJoin {
  const _CliPendingJoin({
    required this.joinSessionId,
    required this.protocolDeviceId,
  });

  final String joinSessionId;
  final String protocolDeviceId;

  static _CliPendingJoin fromJson(Map<String, Object?> json) => _CliPendingJoin(
    joinSessionId: _required(json, 'join_session_id'),
    protocolDeviceId: _required(json, 'protocol_device_id'),
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

  static _JoinProgress fromData(Map<String, Object?> data) {
    final result = data['result'];
    if (result is! Map) {
      fail('The joining CLI returned no Join progress.');
    }
    final progress = _stringMap(result);
    final session = progress['session'];
    if (session is! Map) {
      fail('The joining CLI returned no Join session.');
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

  static _AuthorizedDevice fromJson(Map<String, Object?> json) {
    return _AuthorizedDevice(
      protocolDeviceId: _required(json, 'protocol_device_id'),
      role: _required(json, 'role'),
      managementReady: json['management_ready'] == true,
      isCurrent: json['is_current'] == true,
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
      multiDeviceJoinEnabled: true,
      multiDeviceRootTransferEnabled: false,
      multiDeviceDeviceRevokeEnabled: false,
      multiDeviceDirectE2eeEnabled: false,
      multiDeviceGroupE2eeEnabled: false,
      handleRecoveryEnabled: false,
    );

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
      fail(
        'The purpose-bound OTP request failed without exposing account data.',
      );
    }
    if (response.statusCode != 429 || attempt == 1) {
      break;
    }
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
    fail('The purpose-bound OTP request was rejected.');
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
    fail('The dedicated OTP resolver returned an invalid response.');
  }
  if (decoded is! Map || decoded.length != 1) {
    fail('The dedicated OTP resolver returned an invalid response.');
  }
  final otp = decoded['otp'];
  if (otp is! String || !isSixDigitAsciiOtp(otp)) {
    fail('The dedicated OTP resolver returned an invalid response.');
  }
  return otp;
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

String _requireReadyBootstrapAdmin(DeviceRegistrySnapshot registry) {
  if (registry.devices.length != 1) {
    fail('The App bootstrap Registry did not contain one device.');
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

void _requireIndependentEmptyRoots(_RemoteJoinRunConfig config) {
  _requireIndependentEmptyPaths(<String>[
    config.appStateRoot,
    config.cliWorkspace,
    config.cliHome,
  ]);
}

List<String> _allLocalRoots(_RemoteJoinRunConfig config) => <String>[
  config.appStateRoot,
  config.appJoiningStateRoot,
  config.cliWorkspace,
  config.cliHome,
  config.cliAdminWorkspace,
  config.cliAdminHome,
];

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

String _requireCliReadyBootstrapAdmin(_CliRegistrySnapshot registry) {
  if (registry.devices.length != 1 || registry.pending.isNotEmpty) {
    fail('The CLI bootstrap Registry did not contain exactly one device.');
  }
  final device = registry.devices.single;
  if (device['is_current'] != true ||
      device['role'] != 'admin' ||
      device['management_ready'] != true ||
      device['status'] != 'active') {
    fail('The CLI bootstrap device was not the active ready admin.');
  }
  return _required(device, 'protocol_device_id');
}

void _requireCliCurrentAdminRegistry(
  _CliRegistrySnapshot registry, {
  required String protocolDeviceId,
  required String bootstrapAdminDeviceId,
}) {
  if (registry.devices.length != 2 || registry.pending.isNotEmpty) {
    fail('The CLI admin Registry did not converge to exactly two devices.');
  }
  final current = registry.devices
      .where((device) => device['is_current'] == true)
      .toList(growable: false);
  if (current.length != 1 ||
      current.single['protocol_device_id'] != bootstrapAdminDeviceId ||
      current.single['role'] != 'admin' ||
      current.single['management_ready'] != true ||
      current.single['status'] != 'active') {
    fail('The CLI did not remain the unique current active ready admin.');
  }
  final joined = registry.devices
      .where((device) => device['protocol_device_id'] == protocolDeviceId)
      .toList(growable: false);
  if (joined.length != 1 ||
      joined.single['is_current'] == true ||
      joined.single['role'] != 'member' ||
      joined.single['management_ready'] != false ||
      joined.single['status'] != 'active') {
    fail('The CLI did not resolve the App as one non-current active member.');
  }
}

void _requireJoinedMemberRegistry(
  List<Map<String, Object?>> devices, {
  required String protocolDeviceId,
}) {
  if (devices.length != 2) {
    fail('The joined CLI Registry did not contain exactly two devices.');
  }
  final current = devices
      .where((device) => device['is_current'] == true)
      .toList();
  if (current.length != 1 ||
      current.single['protocol_device_id'] != protocolDeviceId ||
      current.single['role'] != 'member' ||
      current.single['management_ready'] != false ||
      current.single['status'] != 'active') {
    fail('The joined CLI Registry did not project one current active member.');
  }
  final originalAdmin = devices
      .where((device) => device['is_current'] != true)
      .toList(growable: false);
  if (originalAdmin.length != 1 ||
      originalAdmin.single['protocol_device_id'] == protocolDeviceId ||
      originalAdmin.single['role'] != 'admin' ||
      originalAdmin.single['management_ready'] != true ||
      originalAdmin.single['status'] != 'active') {
    fail(
      'The joined CLI Registry did not retain one non-current active ready admin.',
    );
  }
}

void _requireAppRegistryMember(
  DeviceRegistrySnapshot registry, {
  required String protocolDeviceId,
  required String bootstrapAdminDeviceId,
}) {
  if (registry.devices.length != 2) {
    fail('The App Registry did not contain exactly two devices.');
  }
  final matches = registry.devices
      .where((device) => device.protocolDeviceId == protocolDeviceId)
      .toList();
  if (matches.length != 1 ||
      matches.single.role != DeviceRole.member ||
      matches.single.managementReady ||
      matches.single.status != DeviceStatus.active) {
    fail('The App did not resolve the authorized device as one active member.');
  }
  final current = registry.devices.where((device) => device.isCurrent).toList();
  if (current.length != 1 ||
      current.single.protocolDeviceId != bootstrapAdminDeviceId ||
      current.single.role != DeviceRole.admin ||
      !current.single.managementReady ||
      current.single.status != DeviceStatus.active) {
    fail(
      'The original App device did not remain the unique current active ready admin.',
    );
  }
}

void _requireAppCurrentMemberRegistry(
  DeviceRegistrySnapshot registry, {
  required String protocolDeviceId,
  required String bootstrapAdminDeviceId,
}) {
  if (registry.devices.length != 2 || registry.pendingJoins.isNotEmpty) {
    fail('The joined App Registry did not converge to exactly two devices.');
  }
  final current = registry.devices.where((device) => device.isCurrent).toList();
  if (current.length != 1 ||
      current.single.protocolDeviceId != protocolDeviceId ||
      current.single.role != DeviceRole.member ||
      current.single.managementReady ||
      current.single.status != DeviceStatus.active) {
    fail('The joined App did not resolve itself as the current active member.');
  }
  final admin = registry.devices
      .where((device) => device.protocolDeviceId == bootstrapAdminDeviceId)
      .toList(growable: false);
  if (admin.length != 1 ||
      admin.single.isCurrent ||
      admin.single.role != DeviceRole.admin ||
      !admin.single.managementReady ||
      admin.single.status != DeviceStatus.active) {
    fail('The joined App did not retain the CLI as an active ready admin.');
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

Future<void> _enterText(
  WidgetTester tester,
  String semanticsIdentifier,
  String value, {
  required String failure,
}) async {
  final editable = find.descendant(
    of: find.bySemanticsIdentifier(semanticsIdentifier),
    matching: find.byType(EditableText),
  );
  if (editable.evaluate().length != 1) {
    fail(failure);
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
  if (safe.isEmpty) {
    return 'run';
  }
  return safe.length <= maxLength ? safe : safe.substring(0, maxLength);
}

bool _validSas(String value) => RegExp(r'^\d{6}$').hasMatch(value);

bool _constantTimeAsciiEquals(String first, String second) {
  if (first.length != second.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < first.length; index += 1) {
    difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
  }
  return difference == 0;
}
