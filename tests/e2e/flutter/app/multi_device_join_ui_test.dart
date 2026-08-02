// [INPUT]: Audited awiki.info endpoints, a dedicated account/SSH OTP resolver,
//          production AppBootstrap/native Core, independent CLI/App or App/App
//          roots, explicit E2E-only user-presence control, foreground CLI TTY
//          where used, and loopback App-pair phases.
// [OUTPUT]: Real notification-driven member Join plus isolated App-pair Agent
//           inventory and Direct-message convergence scenarios.
// [POS]: Step 2 Join product E2E; no Registry discovery, implicit verification,
//        copied state, fake Core, static OTP, or secret-bearing evidence.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/e2e_semantics.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/message_sync_diagnostics.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/account_state_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/message_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/group/group_encryption_provider.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import '../../account_state_operator_contract.dart';
import '../../app_pair_protocol.dart';
import '../../case_attestation.dart';
import '../../e2e_user_presence_port.dart';
import '../../remote_multi_device_join_contract.dart';
import '../../sync_recovery_operator_contract.dart';

part 'multi_device_app_pair_ui_test.part.dart';

const String _newDeviceCaseId = 'DEVICE-JOIN-E2E-001';
const String _adminApprovalCaseId = 'DEVICE-JOIN-E2E-002';
const String _appPairCaseId = 'DEVICE-JOIN-E2E-004';
const String _appPairAgentSyncCaseId = 'DEVICE-AGENT-SYNC-E2E-001';
const String _appPairAgentMessageSyncCaseId =
    'DEVICE-AGENT-MESSAGE-SYNC-E2E-001';
const String _appPairOutboundSyncCaseId = 'DEVICE-MESSAGE-SYNC-E2E-001';
const String _appPairInboundSyncCaseId = 'DEVICE-MESSAGE-SYNC-E2E-002';
const String _appPairOnlineSyncV2CaseId = 'DEVICE-MESSAGE-ONLINE-SYNC-E2E-001';
const String _appPairTailOnlySyncV2CaseId = 'DEVICE-MESSAGE-TAIL-ONLY-E2E-001';
const String _appPairReadSyncV2CaseId = 'DEVICE-MESSAGE-READ-SYNC-E2E-001';
const String _appPairOfflineRecoveryV2CaseId =
    'DEVICE-MESSAGE-OFFLINE-RECOVERY-E2E-001';
const String _appPairAgentAddSyncCaseId = 'DEVICE-AGENT-ADD-SYNC-E2E-001';
const String _appPairAgentRenameSyncCaseId = 'DEVICE-AGENT-RENAME-SYNC-E2E-001';
const String _appPairAgentDeleteSyncCaseId = 'DEVICE-AGENT-DELETE-SYNC-E2E-001';
const String _appPairAgentUnbindSyncCaseId = 'DEVICE-AGENT-UNBIND-SYNC-E2E-001';
const String _appPairAgentArchiveSyncCaseId =
    'DEVICE-AGENT-ARCHIVE-SYNC-E2E-001';
const String _appPairProfileSyncCaseId = 'DEVICE-PROFILE-SYNC-E2E-001';
const String _appPairRegistrySyncCaseId = 'DEVICE-REGISTRY-SYNC-E2E-001';
const String _appPairDomainIsolationCaseId =
    'DEVICE-ACCOUNT-DOMAIN-ISOLATION-E2E-001';
const String _syncRecoveryEnableEnv = 'AWIKI_MESSAGE_SYNC_V2_RECOVERY_E2E';
const String _syncRecoveryOperatorModeEnv =
    'AWIKI_MULTI_DEVICE_E2E_OPERATOR_MODE';
const String _syncRecoveryTargetEnv = 'AWIKI_SYSTEM_TEST_TARGET';
const String _syncRecoveryTarget = 'awiki-info-testing';
const String _accountStateEnableEnv = 'AWIKI_ACCOUNT_STATE_V1_E2E';
const String _accountStateOperatorModeEnv =
    'AWIKI_MULTI_DEVICE_E2E_OPERATOR_MODE';
const String _accountStateOperatorCommandEnv =
    'AWIKI_ACCOUNT_STATE_E2E_OPERATOR_COMMAND_JSON';
const String _accountStateFailpointEnableEnv =
    'AWIKI_ACCOUNT_STATE_TEST_FAILPOINTS_ENABLED';
const String _rootTransferCaseId = 'ROOT-TRANSFER-E2E-001';
const String _step4PaginationCaseId = 'STEP4-GROUP-PAGINATION-E2E-001';
const String _deviceRevokeCaseId = 'DEVICE-REVOKE-E2E-001';
const String _mlsRevokeCaseId = 'MLS-MULTI-DEVICE-E2E-002';
const String _runConfigPath =
    '.e2e/multi-device-remote-join/current/run_config.json';
const String _compiledAppPairConfigPath = String.fromEnvironment(
  'AWIKI_MULTI_DEVICE_APP_PAIR_CONFIG',
);
const String _activationGate = 'AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED';
const String _phoneEnv = 'AWIKI_MULTI_DEVICE_E2E_PHONE';
const String _otpCommandEnv = 'AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON';
const String _registrationPurpose = 'awiki.identity.register.v1';
const String _joinPurpose = 'awiki.device.join.v1';
const Duration _remoteTimeout = Duration(seconds: 30);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'App new device joins after CLI listener emits a host wake',
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
        purpose: _registrationPurpose,
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
      await cli.startRealtimeListener();

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

      final notice = await cli.waitForJoinRequestWake(
        expectedSessionId: initialPending.joinSessionId,
        expectedDeviceId: initialPending.protocolDeviceId,
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

      await cli.waitForJoinRequestProjection(
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
          final state = container.read(devicesProvider);
          _failOnDeviceError(
            state,
            'The App failed to finalize the joined member',
          );
          final progress = state.activeJoin;
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
          'cli_listener_join_wake_received',
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
    'App admin reviews a listener-delivered CLI Join from the global entry',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final presence = E2eUserPresencePort();
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

      await cli.initialize();
      bootstrap = await AppBootstrap.create(
        environment: _joinOnlyEnvironment(
          config,
          enableRootTransfer:
              _invocationExpects(_rootTransferCaseId) ||
              _invocationExpects(_deviceRevokeCaseId),
          enableStep4: _invocationExpects(_deviceRevokeCaseId),
        ),
        appStateRoot: config.appStateRoot,
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

      await _pumpUntil(
        tester,
        () {
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
        timeout: const Duration(seconds: 45),
        failure:
            'The App listener did not project the Join request from its trusted local inbox.',
      );
      final joinRequestEntry = find.bySemanticsIdentifier(
        'device-join-request-entry',
      );
      await _tapOne(
        tester,
        joinRequestEntry,
        failure:
            'The listener-delivered Join request did not expose a review entry.',
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
      await _pumpUntil(
        tester,
        () {
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
        timeout: const Duration(seconds: 45),
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
            fail('The App requested user presence twice.');
          }
          if (presence.completions == 1 && !presence.lastResult) {
            fail('The user-presence request was denied.');
          }
          return presence.completions == 1 && presence.lastResult;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The App approval did not complete after user presence.',
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

      if (_invocationExpects(_adminApprovalCaseId)) {
        await E2eCaseAttestationWriter.markPassed(
          _adminApprovalCaseId,
          phases: const <String>[
            'independent_native_devices_bootstrapped',
            'otp_left_join_pending',
            'app_global_join_review_entry_received',
            'sas_matched_without_secret_evidence',
            'single_e2e_user_presence_confirmed',
            'joined_device_active_member_not_admin',
          ],
        );
      }
      if (_invocationExpects(_rootTransferCaseId) ||
          _invocationExpects(_deviceRevokeCaseId)) {
        if (bootstrap.rootKeyTransferPort == null) {
          fail('The real App bootstrap did not compose root transfer.');
        }
        await _verifyRootTransferCompletion(
          tester: tester,
          container: container,
          cli: cli,
          presence: presence,
          did: adminSession.did,
          joinSessionId: started.joinSessionId,
          senderDeviceId: bootstrapAdminDeviceId,
          recipientDeviceId: started.protocolDeviceId,
        );
      }
      if (_invocationExpects(_deviceRevokeCaseId)) {
        await _verifyStep4RevokeAndMls(
          tester: tester,
          container: container,
          bootstrap: bootstrap,
          cli: cli,
          presence: presence,
          did: adminSession.did,
          currentDeviceId: bootstrapAdminDeviceId,
          targetDeviceId: started.protocolDeviceId,
        );
      }
    },
    skip:
        !Platform.isMacOS ||
        !_RemoteJoinRunConfig.exists() ||
        (!_invocationExpects(_adminApprovalCaseId) &&
            !_invocationExpects(_rootTransferCaseId) &&
            !_invocationExpects(_deviceRevokeCaseId)),
    timeout: Timeout(
      _invocationExpects(_deviceRevokeCaseId)
          ? const Duration(minutes: 30)
          : const Duration(minutes: 14),
    ),
  );
}

Future<void> _verifyStep4RevokeAndMls({
  required WidgetTester tester,
  required ProviderContainer container,
  required AppBootstrap bootstrap,
  required _JoinCli cli,
  required E2eUserPresencePort presence,
  required String did,
  required String currentDeviceId,
  required String targetDeviceId,
}) async {
  if (find.byType(DeviceJoinApprovalSheet).evaluate().isNotEmpty) {
    Navigator.of(tester.element(find.byType(DeviceJoinApprovalSheet))).pop();
    await tester.pumpAndSettle();
  }
  await cli.startRealtimeListener();
  final groups = container.read(groupApplicationServiceProvider);
  final nonce = _nonce(8);
  final group = await groups.createGroup(
    name: 'Step4 revoke $nonce',
    slug: 'step4-$nonce',
    description: 'Step4 exact-device convergence',
    goal: 'Verify revoke convergence',
    rules: 'E2E only',
  );
  final pageGroup = await groups.createGroup(
    name: 'Step4 page $nonce',
    slug: 'step4-page-$nonce',
    description: 'Step4 cursor projection',
    goal: 'Verify pagination',
    rules: 'E2E only',
  );
  final groupController = container.read(groupProvider.notifier);
  await groupController.refresh(limit: 1);
  final firstPageState = container.read(groupProvider);
  if (!firstPageState.groupsHasMore ||
      firstPageState.groupsNextCursor == null ||
      firstPageState.groups.length != 1) {
    fail('The real App group provider did not expose an explicit first page.');
  }
  final retainedFirstGroupId = firstPageState.groups.single.groupId;
  await groupController.loadMoreGroups(limit: 1);
  final secondPageState = container.read(groupProvider);
  final groupIds = secondPageState.groups
      .map((item) => item.groupId)
      .toList(growable: false);
  if (groupIds.length != 2 ||
      groupIds.toSet().length != groupIds.length ||
      groupIds.where((id) => id == retainedFirstGroupId).length != 1 ||
      !groupIds.contains(group.groupId) ||
      !groupIds.contains(pageGroup.groupId)) {
    fail(
      'Explicit App provider load-more lost, duplicated, or reused a group.',
    );
  }
  await groupController.loadGroupMembers(group.groupId, limit: 1);
  final memberPage = container.read(groupProvider).memberPages[group.groupId];
  if (memberPage?.pageGroupDid != group.groupId ||
      memberPage?.groupStateVersion?.trim().isEmpty != false) {
    fail('The App member page was not bound to its group and state version.');
  }
  await E2eCaseAttestationWriter.markPassed(
    _step4PaginationCaseId,
    phases: const <String>[
      'real_group_first_page_has_opaque_cursor',
      'explicit_next_cursor_loaded',
      'stable_group_projection_retained',
    ],
  );

  final registryBeforeRepair = await bootstrap.deviceManagementCorePort!
      .identityDeviceRegistry(did);
  final currentReadyAdmin = registryBeforeRepair.devices
      .where(
        (device) =>
            device.protocolDeviceId == currentDeviceId &&
            device.isCurrent &&
            device.role == DeviceRole.admin &&
            device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  final targetReadyAdmin = registryBeforeRepair.devices
      .where(
        (device) =>
            device.protocolDeviceId == targetDeviceId &&
            !device.isCurrent &&
            device.role == DeviceRole.admin &&
            device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  if (registryBeforeRepair.devices.length != 2 ||
      currentReadyAdmin.length != 1 ||
      targetReadyAdmin.length != 1) {
    fail('Fresh Registry did not bind the two exact ready device principals.');
  }

  final secure = container.read(groupEncryptionCorePortProvider);
  var appReady = await secure.retry(group.groupId);
  final appReadyDeadline = DateTime.now().add(const Duration(seconds: 45));
  while (!appReady.canSendSecure && DateTime.now().isBefore(appReadyDeadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    appReady = await secure.retry(group.groupId);
  }
  if (!appReady.canSendSecure) {
    fail('The App controller did not reconcile the CLI Manifest device.');
  }
  final twoLeafEvidence = await cli.repairGroupUntilReady(group.groupId);
  final cliReadinessFailure = twoLeafEvidence.repairGroup != group.groupId
      ? 'repair_group_mismatch'
      : twoLeafEvidence.repairState.toLowerCase() != 'ready'
      ? 'repair_not_ready'
      : twoLeafEvidence.remainingDevices != 0
      ? 'repair_devices_remaining'
      : twoLeafEvidence.statusGroup != group.groupId
      ? 'status_group_mismatch'
      : twoLeafEvidence.statusState.toLowerCase() != 'ready'
      ? 'status_not_ready'
      : !twoLeafEvidence.canSendSecure
      ? 'cannot_send_secure'
      : !twoLeafEvidence.hasLocalState
      ? 'missing_local_state'
      : !twoLeafEvidence.hasActiveMembership
      ? 'missing_active_membership'
      : null;
  if (twoLeafEvidence.repairGroup != group.groupId ||
      twoLeafEvidence.repairState.toLowerCase() != 'ready' ||
      twoLeafEvidence.remainingDevices != 0 ||
      twoLeafEvidence.statusGroup != group.groupId ||
      twoLeafEvidence.statusState.toLowerCase() != 'ready' ||
      !twoLeafEvidence.canSendSecure ||
      !twoLeafEvidence.hasLocalState ||
      !twoLeafEvidence.hasActiveMembership) {
    fail(
      'CLI public repair/status did not prove its exact ready device leaf '
      '($cliReadinessFailure).',
    );
  }
  final appStatusBeforeRevoke = await secure.status(group.groupId);
  if (appStatusBeforeRevoke.groupDid != group.groupId ||
      !appStatusBeforeRevoke.canSendSecure) {
    fail('App public status did not prove its exact ready device leaf.');
  }

  if (find.byType(DevicesPage).evaluate().isEmpty) {
    await _openDevicesPage(tester);
  }
  await _tapOne(
    tester,
    find.byKey(Key('device-revoke-$targetDeviceId')),
    failure: 'The exact non-current device did not expose revoke.',
  );
  await _pumpUntil(
    tester,
    () =>
        find
            .byKey(const Key('device-revoke-confirm-dialog'))
            .evaluate()
            .length ==
        1,
    failure: 'The destructive revoke confirmation was not rendered.',
  );
  final presenceBefore = presence.calls;
  await _tapOne(
    tester,
    find.byKey(const Key('device-revoke-confirm-action')),
    failure: 'The destructive revoke confirmation was unavailable.',
  );
  await _pumpUntil(
    tester,
    () {
      DeviceSummary? target;
      for (final device
          in container.read(devicesProvider).registry?.devices ??
              const <DeviceSummary>[]) {
        if (device.protocolDeviceId == targetDeviceId) {
          target = device;
          break;
        }
      }
      return target?.status == DeviceStatus.revoked;
    },
    timeout: const Duration(minutes: 2),
    failure: 'Fresh Registry did not project the exact target revoked.',
  );
  if (presence.calls != presenceBefore + 1) {
    fail('Device revoke did not consume exactly one fresh user presence.');
  }
  final registry = container.read(devicesProvider).registry!;
  final current = registry.devices
      .where((device) => device.protocolDeviceId == currentDeviceId)
      .single;
  if (!current.canManageDevices) {
    fail('The surviving current ready admin was not retained.');
  }
  await E2eCaseAttestationWriter.markPassed(
    _deviceRevokeCaseId,
    phases: const <String>[
      'destructive_confirmation_visible',
      'single_fresh_user_presence_confirmed',
      'registry_projected_target_revoked',
      'current_ready_admin_retained',
    ],
  );

  var status = await secure.status(group.groupId);
  final maintenanceDeadline = DateTime.now().add(const Duration(seconds: 45));
  while (status.canSendSecure && DateTime.now().isBefore(maintenanceDeadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 750));
    status = await secure.status(group.groupId);
  }
  if (status.canSendSecure) {
    fail('The group reported ready before revoke convergence repair.');
  }
  container.read(groupProvider.notifier).upsertGroup(group);
  unawaited(
    Navigator.of(tester.element(find.byType(DevicesPage))).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => GroupDetailPage(initialGroup: group),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => find
        .byKey(const Key('group-encryption-retry-button'))
        .hitTestable()
        .evaluate()
        .isNotEmpty,
    failure:
        'The current controller group did not expose an actionable repair.',
  );
  await _tapOne(
    tester,
    find.byKey(const Key('group-encryption-retry-button')),
    failure: 'The explicit group repair action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () =>
        container
            .read(groupEncryptionProvider(group.groupId))
            .status
            ?.canSendSecure ==
        true,
    timeout: const Duration(seconds: 45),
    failure:
        'The surviving App did not become ready after exact Remove repair.',
  );
  status =
      container.read(groupEncryptionProvider(group.groupId)).status ?? status;
  if (!status.canSendSecure) {
    fail('The surviving App did not become ready after exact Remove repair.');
  }
  final members = await groups.listMembers(group.groupId);
  if (members.items.where((member) => member.did == did).length != 1) {
    fail('Exact-device revoke changed DID-level business membership.');
  }
  final futureContent = 'step4 future secure ${_nonce(8)}';
  final futureMessage = await container
      .read(messagingServiceProvider)
      .sendText(
        thread: AppThreadRef.group(group.groupId),
        content: futureContent,
      );
  final futureMessageId = futureMessage.remoteId?.trim();
  if (futureMessageId == null || futureMessageId.isEmpty) {
    fail('The surviving App did not send a future secure group application.');
  }
  await cli.requireRevokedGroupReadRejected(
    groupDid: group.groupId,
    futureMessageId: futureMessageId,
    futureContent: futureContent,
  );
  await E2eCaseAttestationWriter.markPassed(
    _mlsRevokeCaseId,
    phases: const <String>[
      'exact_device_revoked_with_remove_commit',
      'app_ready_only_after_remove_convergence',
      'revoked_endpoint_rejected_future_group_data',
      'surviving_app_leaf_and_business_member_retained',
    ],
  );
}

Future<void> _verifyRootTransferCompletion({
  required WidgetTester tester,
  required ProviderContainer container,
  required _JoinCli cli,
  required E2eUserPresencePort presence,
  required String did,
  required String joinSessionId,
  required String senderDeviceId,
  required String recipientDeviceId,
}) async {
  final before = container.read(devicesProvider);
  final activeJoin = before.activeJoin;
  final recipient = activeJoin?.authorizedDevice;
  if (activeJoin?.joinSessionId != joinSessionId ||
      activeJoin?.did != did ||
      activeJoin?.protocolDeviceId != recipientDeviceId ||
      activeJoin?.side != DeviceJoinSide.admin ||
      activeJoin?.phase != DeviceJoinPhase.authorized ||
      recipient?.protocolDeviceId != recipientDeviceId ||
      recipient?.role != DeviceRole.member ||
      recipient?.managementReady != false ||
      recipient?.isCurrent != false) {
    fail('Root transfer did not retain the exact authorized Join context.');
  }
  await cli.requireRootlessCurrentMember(
    expectedDid: did,
    expectedDeviceId: recipientDeviceId,
  );

  final presenceCallsBeforePrepare = presence.calls;
  await _pumpUntil(
    tester,
    () {
      _failOnDeviceError(
        container.read(devicesProvider),
        'The App failed to project the authorized member',
      );
      return find
              .byKey(const Key('root-transfer-grant-management'))
              .evaluate()
              .length ==
          1;
    },
    timeout: const Duration(seconds: 45),
    failure:
        'The exact joined member did not expose root transfer after Registry convergence.',
  );
  await _tapOne(
    tester,
    find.byKey(const Key('root-transfer-grant-management')),
    failure: 'The exact joined member did not expose root transfer.',
  );
  await _pumpUntil(
    tester,
    () {
      final state = container.read(devicesProvider);
      _failOnDeviceError(state, 'The App failed root-transfer preparation');
      return state.rootTransfer.phase ==
              RootKeyTransferPhase.awaitingConfirmation &&
          state.rootTransfer.preparation != null;
    },
    timeout: const Duration(seconds: 45),
    failure: 'Core did not prepare the exact root-transfer recipient.',
  );
  final prepared = container.read(devicesProvider).rootTransfer;
  final preparation = prepared.preparation!;
  if (prepared.context?.joinSessionId != joinSessionId ||
      prepared.context?.did != did ||
      prepared.context?.recipientDeviceId != recipientDeviceId ||
      preparation.recipient.did != did ||
      preparation.recipient.deviceId != recipientDeviceId ||
      preparation.recipient.signingKeyId !=
          prepared.context?.recipientSigningKeyId ||
      preparation.recipient.e2eeKeyId != prepared.context?.recipientE2eeKeyId ||
      preparation.recipient.registryVersion < 1 ||
      presence.calls != presenceCallsBeforePrepare ||
      prepared.receipt != null) {
    fail('Root transfer preparation escaped the exact Join context.');
  }
  if (find
              .byKey(const Key('root-transfer-recipient-summary'))
              .evaluate()
              .length !=
          1 ||
      find.byKey(const Key('root-transfer-confirm-send')).evaluate().length !=
          1 ||
      find.byKey(const Key('root-transfer-sent')).evaluate().isNotEmpty) {
    fail('The App did not stop at the safe prepare-before-confirm boundary.');
  }
  final summaryText = tester
      .widget<Text>(find.byKey(const Key('root-transfer-recipient-summary')))
      .data;
  final expectedSummary = tester
      .element(find.byType(DeviceJoinApprovalSheet))
      .l10n
      .deviceRootTransferTarget(
        preparation.recipient.deviceId,
        preparation.recipient.signingKeyId,
        preparation.recipient.e2eeKeyId,
      );
  if (summaryText != expectedSummary) {
    fail('The App did not render only Core safe recipient summary fields.');
  }

  await _tapOne(
    tester,
    find.byKey(const Key('root-transfer-confirm-send')),
    failure: 'The prepared root-transfer confirmation was unavailable.',
  );
  await _pumpUntil(
    tester,
    () {
      if (presence.calls > presenceCallsBeforePrepare + 1) {
        fail('Root transfer requested user presence twice.');
      }
      final state = container.read(devicesProvider);
      _failOnDeviceError(state, 'The App failed root transfer');
      return state.rootTransfer.phase == RootKeyTransferPhase.sent &&
          state.rootTransfer.receipt != null;
    },
    timeout: const Duration(minutes: 2),
    failure: 'The sender did not stop at standard P5 accepted.',
  );
  if (presence.calls != presenceCallsBeforePrepare + 1 ||
      presence.completions != presenceCallsBeforePrepare + 1 ||
      !presence.lastResult) {
    fail('Root transfer did not complete exactly one fresh user presence.');
  }
  final sent = container.read(devicesProvider).rootTransfer;
  final receipt = sent.receipt!;
  if (sent.context != prepared.context ||
      receipt.did != did ||
      receipt.senderDeviceId != senderDeviceId ||
      receipt.recipientDeviceId != recipientDeviceId ||
      receipt.messageId.trim().isEmpty ||
      receipt.acceptedAt.isAfter(
        DateTime.now().toUtc().add(const Duration(seconds: 5)),
      )) {
    fail('The sender returned an invalid standard P5 accepted receipt.');
  }
  _requireAppAdminAndMember(
    container.read(devicesProvider).registry!,
    bootstrapAdminDeviceId: senderDeviceId,
    joinedDeviceId: recipientDeviceId,
  );

  await cli.waitForRootImportCompletion(
    expectedDid: did,
    expectedDeviceId: recipientDeviceId,
  );

  await container
      .read(messageSyncCoordinatorProvider.notifier)
      .requestSync('e2e_root_transfer_receiver_completed', immediate: true);
  await container.read(conversationListProvider.notifier).refresh();
  final projectedConversations = container
      .read(conversationListProvider)
      .conversations;
  final storedConversations = await container
      .read(conversationServiceProvider)
      .listConversations(ownerDid: did);
  if (projectedConversations.isNotEmpty || storedConversations.isNotEmpty) {
    fail('Root P5 entered the ordinary App conversation projection.');
  }
  final senderAfterReceiverCompletion = container
      .read(devicesProvider)
      .rootTransfer;
  if (senderAfterReceiverCompletion.phase != RootKeyTransferPhase.sent ||
      senderAfterReceiverCompletion.receipt?.messageId != receipt.messageId ||
      presence.calls != presenceCallsBeforePrepare + 1) {
    fail('Receiver completion changed the terminal sender boundary.');
  }

  final done = find.descendant(
    of: find.byType(DeviceJoinApprovalSheet),
    matching: find.text(
      tester.element(find.byType(DeviceJoinApprovalSheet)).l10n.commonDone,
    ),
  );
  await _tapOne(
    tester,
    done,
    failure: 'The sent root-transfer sheet could not be closed.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(DeviceJoinApprovalSheet).evaluate().isEmpty,
    failure: 'The root-transfer sheet remained open after completion.',
  );
  for (final key in const <Key>[
    Key('root-transfer-grant-management'),
    Key('root-transfer-preparing'),
    Key('root-transfer-recipient-summary'),
    Key('root-transfer-confirm-send'),
    Key('root-transfer-sending'),
    Key('root-transfer-sent'),
    Key('root-transfer-failed'),
  ]) {
    if (find.byKey(key).evaluate().isNotEmpty) {
      fail('Generic Devices projected a root-transfer control.');
    }
  }

  if (_invocationExpects(_rootTransferCaseId)) {
    await E2eCaseAttestationWriter.markPassed(
      _rootTransferCaseId,
      phases: const <String>[
        'member_not_ready_before_completion',
        'safe_summary_single_presence',
        'sender_accepted_terminal',
        'receiver_completion_ready',
        'root_p5_not_projected',
      ],
    );
  }
}

bool _invocationExpects(String caseId) {
  final encoded = e2eInvocationValue(
    e2eCaseIdsDefine,
    compiledValue: const String.fromEnvironment(e2eCaseIdsDefine),
  );
  if (encoded.trim().isEmpty) return true;
  return encoded.split(',').map((value) => value.trim()).contains(caseId);
}

bool _invocationExplicitlyExpects(String caseId) {
  final encoded = e2eInvocationValue(
    e2eCaseIdsDefine,
    compiledValue: const String.fromEnvironment(e2eCaseIdsDefine),
  );
  if (encoded.trim().isEmpty) return false;
  return encoded.split(',').map((value) => value.trim()).contains(caseId);
}

abstract interface class _RemoteJoinEndpointConfig {
  String get baseUrl;
  String get userServiceUrl;
  String get messageServiceUrl;
  String get mailServiceUrl;
  String get didDomain;
  String get anpServiceUrl;
  String get anpServiceDid;
  String get handlePrefix;
  bool get allowStagedOtpOnSmsError;
}

abstract interface class _CliEndpointConfig
    implements _RemoteJoinEndpointConfig {
  String get runId;
  String get cliBin;
  String get cliSourceRef;
  bool get multiDeviceDirectE2eeEnabled;
  bool get multiDeviceGroupE2eeEnabled;
}

class _AppPairRunConfig implements _CliEndpointConfig {
  const _AppPairRunConfig({
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
    required this.adminStateRoot,
    required this.joinerStateRoot,
    required this.coordinator,
    required this.functional,
    required this.automatedUserPresence,
    required this.cliBin,
    required this.cliSourceRef,
    required this.cliWorkspace,
    required this.cliHome,
    required this.daemonBinary,
    required this.daemonStateRoot,
    required this.daemonReadyFile,
    required this.daemonHandle,
    required this.daemonEnvFile,
    required this.accountStateOperatorCommand,
  });

  @override
  final String runId;
  @override
  final String baseUrl;
  @override
  final String userServiceUrl;
  @override
  final String messageServiceUrl;
  @override
  final String mailServiceUrl;
  @override
  final String didDomain;
  @override
  final String anpServiceUrl;
  @override
  final String anpServiceDid;
  @override
  final String handlePrefix;
  @override
  final bool allowStagedOtpOnSmsError;
  final String adminStateRoot;
  final String joinerStateRoot;
  final AppPairCoordinatorClient coordinator;
  final bool functional;
  final bool automatedUserPresence;
  @override
  bool get multiDeviceDirectE2eeEnabled => false;
  @override
  bool get multiDeviceGroupE2eeEnabled => false;
  @override
  final String cliBin;
  @override
  final String cliSourceRef;
  final String cliWorkspace;
  final String cliHome;
  final String daemonBinary;
  final String daemonStateRoot;
  final String daemonReadyFile;
  final String daemonHandle;
  final String? daemonEnvFile;
  final List<String> accountStateOperatorCommand;

  static _AppPairRunConfig load() {
    if (Platform.environment[_activationGate]?.trim() != '1') {
      throw StateError('Remote multi-device Join is not explicitly enabled.');
    }
    final appPairConfigPath = e2eInvocationValue(
      'AWIKI_MULTI_DEVICE_APP_PAIR_CONFIG',
      compiledValue: _compiledAppPairConfigPath,
    );
    if (appPairConfigPath.isEmpty) {
      throw StateError('The App-pair run config path is missing.');
    }
    final decoded = jsonDecode(File(appPairConfigPath).readAsStringSync());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['enabled'] != true) {
      throw StateError('The App-pair run config is invalid.');
    }
    final root = _stringMap(decoded);
    final service = _map(root, 'service');
    final account = _map(root, 'account');
    final testControl = _map(root, 'testControl');
    final apps = _map(root, 'apps');
    final admin = _map(apps, 'admin');
    final joiner = _map(apps, 'joiner');
    final coordinator = _map(root, 'coordinator');
    final functional = root['functional'] is Map
        ? _stringMap(root['functional'] as Map)
        : const <String, Object?>{};
    final cliPeer = functional.isEmpty
        ? const <String, Object?>{}
        : _map(functional, 'cliPeer');
    final daemon = functional.isEmpty
        ? const <String, Object?>{}
        : _map(functional, 'daemon');
    final accountState = functional.isEmpty
        ? const <String, Object?>{}
        : _map(functional, 'accountState');
    final endpoint = Uri.tryParse(_required(coordinator, 'baseUrl'));
    if (endpoint == null ||
        endpoint.scheme != 'http' ||
        endpoint.host != InternetAddress.loopbackIPv4.address ||
        endpoint.port == 0) {
      throw StateError('The App-pair coordinator is not loopback-only.');
    }
    final config = _AppPairRunConfig(
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
      adminStateRoot: _required(admin, 'stateRoot'),
      joinerStateRoot: _required(joiner, 'stateRoot'),
      coordinator: AppPairCoordinatorClient(
        endpoint: endpoint,
        token: _required(coordinator, 'token'),
      ),
      functional: functional.isNotEmpty,
      automatedUserPresence: _requiredBool(
        testControl,
        'automatedUserPresence',
      ),
      cliBin: functional.isEmpty ? '' : _required(cliPeer, 'binary'),
      cliSourceRef: functional.isEmpty ? '' : _required(cliPeer, 'sourceRef'),
      cliWorkspace: functional.isEmpty ? '' : _required(cliPeer, 'workspace'),
      cliHome: functional.isEmpty ? '' : _required(cliPeer, 'home'),
      daemonBinary: functional.isEmpty ? '' : _required(daemon, 'binary'),
      daemonStateRoot: functional.isEmpty ? '' : _required(daemon, 'stateRoot'),
      daemonReadyFile: functional.isEmpty ? '' : _required(daemon, 'readyFile'),
      daemonHandle: functional.isEmpty ? '' : _required(daemon, 'handle'),
      daemonEnvFile: functional.isEmpty ? null : daemon['envFile']?.toString(),
      accountStateOperatorCommand: functional.isEmpty
          ? const <String>[]
          : _requiredStringList(accountState, 'operatorCommand'),
    );
    if (config.didDomain != 'awiki.info' ||
        config.adminStateRoot == config.joinerStateRoot) {
      throw StateError('The App-pair target or state isolation is invalid.');
    }
    if (!config.automatedUserPresence) {
      throw StateError(
        'The App-pair suite must use the E2E-only unattended '
        'user-presence port.',
      );
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
    if (config.functional) {
      if (!config.automatedUserPresence ||
          config.cliBin.isEmpty ||
          config.cliSourceRef.isEmpty ||
          config.cliWorkspace.isEmpty ||
          config.cliHome.isEmpty ||
          config.daemonBinary.isEmpty ||
          config.daemonStateRoot.isEmpty ||
          config.daemonReadyFile.isEmpty ||
          config.daemonHandle.isEmpty ||
          config.accountStateOperatorCommand.isEmpty) {
        throw StateError('The App-pair functional config is incomplete.');
      }
      _requireAccountStateOperatorEnvironment(
        config.accountStateOperatorCommand,
      );
      final isolatedPaths = <String>[
        config.adminStateRoot,
        config.joinerStateRoot,
        config.cliWorkspace,
        config.cliHome,
        config.daemonStateRoot,
      ];
      if (isolatedPaths.toSet().length != isolatedPaths.length) {
        throw StateError('The App-pair functional roots are not isolated.');
      }
    }
    return config;
  }
}

class _RemoteJoinRunConfig implements _CliEndpointConfig {
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
    required this.automatedUserPresence,
    required this.cliBin,
    required this.cliSourceRef,
    required this.cliWorkspace,
    required this.cliHome,
    required this.cliAdminWorkspace,
    required this.cliAdminHome,
    required this.appStateRoot,
    required this.appJoiningStateRoot,
  });

  @override
  final String runId;
  @override
  final String baseUrl;
  @override
  final String userServiceUrl;
  @override
  final String messageServiceUrl;
  @override
  final String mailServiceUrl;
  @override
  final String didDomain;
  @override
  final String anpServiceUrl;
  @override
  final String anpServiceDid;
  @override
  final String handlePrefix;
  @override
  final bool allowStagedOtpOnSmsError;
  final bool automatedUserPresence;
  @override
  final String cliBin;
  @override
  final String cliSourceRef;
  @override
  bool get multiDeviceDirectE2eeEnabled =>
      _invocationExplicitlyExpects(_rootTransferCaseId) ||
      _invocationExplicitlyExpects(_deviceRevokeCaseId);
  @override
  bool get multiDeviceGroupE2eeEnabled =>
      _invocationExplicitlyExpects(_mlsRevokeCaseId);
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
    final testControl = _map(root, 'testControl');
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
      automatedUserPresence: _requiredBool(
        testControl,
        'automatedUserPresence',
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
    if (!config.automatedUserPresence) {
      throw StateError(
        'Remote multi-device Join must use the E2E-only unattended '
        'user-presence port.',
      );
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

  factory _JoinCli.peer(_AppPairRunConfig config) => _JoinCli._(
    config: config,
    workspace: config.cliWorkspace,
    home: config.cliHome,
    role: 'peer',
  );

  final _CliEndpointConfig config;
  final String workspace;
  final String home;
  final String _tenantName;
  Process? _joinRequestListener;
  String? _hostNotificationPath;

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

  Future<String> sendDirectText({
    required String to,
    required String text,
  }) async {
    final payload = await _run(<String>[
      '--format',
      'json',
      'msg',
      'send',
      '--to',
      to,
      '--text',
      text,
    ]);
    final message = _data(payload, action: null)['message'];
    if (message is! Map) {
      fail('The independent CLI send returned no canonical message.');
    }
    return _required(_stringMap(message), 'id');
  }

  Future<void> startRealtimeListener() async {
    if (_joinRequestListener != null) {
      fail('The CLI realtime listener was started more than once.');
    }
    await _run(const <String>[
      '--format',
      'json',
      'runtime',
      'listener',
      'config',
      'set',
      '--enabled=true',
      '--auto-install=false',
      '--auto-start=false',
    ]);
    await _run(const <String>[
      '--format',
      'json',
      'runtime',
      'mode',
      'set',
      'websocket',
    ]);
    await _run(const <String>[
      '--format',
      'json',
      'runtime',
      'host-notify',
      'config',
      'set',
      '--sink',
      'file',
    ]);
    final enabled = await _run(const <String>[
      '--format',
      'json',
      'runtime',
      'host-notify',
      'enable',
    ]);
    final hostNotify = _data(enabled, action: null)['host_notify'];
    if (hostNotify is! Map) {
      fail('The CLI returned no host-notification configuration.');
    }
    _hostNotificationPath = _required(_stringMap(hostNotify), 'file_path');

    final process = await Process.start(
      config.cliBin,
      const <String>['--format', 'json', 'runtime', 'listener', 'run'],
      environment: <String, String>{
        ..._environment(),
        'AWIKI_CLI_INTERNAL_ENTRY': '1',
      },
      includeParentEnvironment: false,
      runInShell: false,
    );
    _joinRequestListener = process;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await _processExited(process)) {
        fail('The CLI realtime listener exited before it was ready.');
      }
      final status = await _run(const <String>[
        '--format',
        'json',
        'runtime',
        'listener',
        'status',
      ]);
      final listener = _data(status, action: null)['listener'];
      if (listener is Map) {
        final listenerData = _stringMap(listener);
        final sessions = listenerData['sessions'];
        final host = listenerData['host_notify'];
        final connected =
            sessions is List &&
            sessions.whereType<Map>().any(
              (session) => session['connected'] == true,
            );
        final configured =
            host is Map &&
            host['sink'] == 'file' &&
            host['file_path'] == _hostNotificationPath;
        if (connected && configured) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail('The CLI realtime listener did not become ready.');
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

  Future<_JoinRequest> waitForJoinRequestWake({
    required String expectedSessionId,
    required String expectedDeviceId,
  }) async {
    final path = _hostNotificationPath;
    if (path == null || _joinRequestListener == null) {
      fail('The CLI Join request listener was not active.');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final file = File(path);
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (final line in lines) {
          Object? decoded;
          try {
            decoded = jsonDecode(line);
          } on Object {
            fail('The CLI host-notification file contained invalid JSON.');
          }
          if (decoded is! Map ||
              decoded['topic'] != 'im.device.join.requested') {
            continue;
          }
          final data = decoded['data'];
          if (data is! Map || data['join_session_id'] != expectedSessionId) {
            continue;
          }
          const allowedFields = <String>{
            'channel',
            'event_id',
            'join_session_id',
            'recipient_did',
            'issued_at',
            'expires_at',
          };
          if (data.keys.any((key) => !allowedFields.contains(key.toString()))) {
            fail('The CLI Join wake event contained an unapproved field.');
          }
          return waitForJoinRequestProjection(
            expectedSessionId: expectedSessionId,
            expectedDeviceId: expectedDeviceId,
            expectedState: 'pending',
            expectedClaimedByCurrentDevice: false,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    fail('The CLI listener did not emit the expected Join request wake event.');
  }

  Future<_JoinRequest> waitForJoinRequestProjection({
    required String expectedSessionId,
    required String expectedDeviceId,
    required String expectedState,
    required bool expectedClaimedByCurrentDevice,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
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
      if (progress.sas != null) {
        fail('The joining CLI exposed a SAS in structured output.');
      }
      if (progress.remoteState == 'response_verified') {
        final sas = await _readPollSasInForeground(sessionId);
        return _JoinProgress(
          joinSessionId: progress.joinSessionId,
          protocolDeviceId: progress.protocolDeviceId,
          remoteState: progress.remoteState,
          sas: sas,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The joining CLI did not reach response_verified in time.');
  }

  Future<String> _readPollSasInForeground(String sessionId) async {
    Process? process;
    final transcript = <int>[];
    String? sas;
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
          'poll',
          '--session',
          sessionId,
        ],
        environment: _environment(),
        includeParentEnvironment: false,
        runInShell: false,
      );

      void consume(List<int> bytes) {
        if (invalidOutput) return;
        if (transcript.length + bytes.length > 64 * 1024) {
          invalidOutput = true;
          process?.kill(ProcessSignal.sigkill);
          return;
        }
        transcript.addAll(bytes);
      }

      final outputDone = Future.wait<void>(<Future<void>>[
        process.stdout.listen(consume).asFuture<void>(),
        process.stderr.listen(consume).asFuture<void>(),
      ]);
      try {
        exitCode = await process.exitCode.timeout(_remoteTimeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
      await outputDone;
      if (!invalidOutput && exitCode == 0) {
        sas = remoteMultiDeviceCliPollSas(transcript);
      }
    } on Object {
      invalidOutput = true;
    } finally {
      if (process != null && exitCode < 0) {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
        } on Object {
          // The in-memory transcript is scrubbed below.
        }
      }
      transcript.fillRange(0, transcript.length, 0);
      transcript.clear();
    }
    if (invalidOutput || exitCode != 0 || !_validSas(sas ?? '')) {
      fail(
        'The joining CLI did not expose its SAS through the foreground TTY.',
      );
    }
    return sas!;
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

  Future<void> requireRevokedGroupReadRejected({
    required String groupDid,
    required String futureMessageId,
    required String futureContent,
  }) async {
    final ProcessResult result;
    try {
      result = await Process.run(
        config.cliBin,
        <String>[
          '--format',
          'json',
          'group',
          'messages',
          '--group',
          groupDid,
          '--limit',
          '20',
        ],
        environment: _environment(),
        includeParentEnvironment: false,
        runInShell: false,
      ).timeout(_remoteTimeout);
    } on Object {
      fail('The revoked CLI group read did not complete safely.');
    }
    final stdout = result.stdout.toString();
    final stderr = result.stderr.toString();
    if (result.exitCode == 0) {
      fail('The revoked CLI retained authorized access to the target group.');
    }
    if (stdout.contains(futureMessageId) ||
        stdout.contains(futureContent) ||
        stderr.contains(futureMessageId) ||
        stderr.contains(futureContent)) {
      fail('The revoked CLI received the future target-group message.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(stderr);
    } on Object {
      fail('The revoked CLI returned no structured authorization rejection.');
    }
    if (decoded is! Map || decoded['ok'] != false) {
      fail('The revoked CLI returned no failed public group-read result.');
    }
    final error = decoded['error'];
    if (error is! Map) {
      fail('The revoked CLI group read omitted its public error.');
    }
    final code = error['code']?.toString();
    if (code != 'auth_required' &&
        code != 'identity_required' &&
        code != 'permission_denied') {
      fail('The revoked CLI group read was not rejected by authorization.');
    }
  }

  Future<_CliGroupSecureEvidence> repairGroupUntilReady(String groupDid) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    var repairGroup = '';
    var repairState = '';
    var remainingDevices = 0;
    var statusGroup = '';
    var statusState = '';
    var canSendSecure = false;
    var hasLocalState = false;
    var hasActiveMembership = false;
    while (DateTime.now().isBefore(deadline)) {
      final inbox = _data(
        await _run(const <String>[
          '--format',
          'json',
          'msg',
          'inbox',
          '--scope',
          'direct',
          '--limit',
          '20',
        ]),
        action: null,
      );
      if (inbox['messages'] is! List) {
        fail('CLI did not expose its ordinary Inbox projection.');
      }
      final repaired = _data(
        await _run(<String>[
          '--format',
          'json',
          'group',
          'secure',
          'repair',
          '--group',
          groupDid,
        ]),
        action: null,
      )['repair'];
      if (repaired is! Map) {
        fail('CLI group repair returned no public repair projection.');
      }
      final repair = _stringMap(repaired);
      repairGroup = _required(repair, 'group');
      repairState = _required(repair, 'state');
      final remaining = int.tryParse(
        repair['remaining_devices']?.toString() ?? '',
      );
      if (remaining == null) {
        fail('CLI group repair omitted its convergence count.');
      }
      remainingDevices = remaining;
      final statusRaw = _data(
        await _run(<String>[
          '--format',
          'json',
          'group',
          'secure',
          'status',
          '--group',
          groupDid,
        ]),
        action: null,
      )['status'];
      if (statusRaw is! Map) {
        fail('CLI group status returned no public status projection.');
      }
      final status = _stringMap(statusRaw);
      statusGroup = _required(status, 'group');
      statusState = _required(status, 'state');
      final localRaw = status['local_readiness'];
      if (localRaw is! Map) {
        fail('CLI group status omitted local readiness.');
      }
      final local = _stringMap(localRaw);
      canSendSecure = status['can_send_secure'] == true;
      hasLocalState = local['has_local_state'] == true;
      hasActiveMembership = local['has_active_membership'] == true;
      final evidence = _CliGroupSecureEvidence(
        repairGroup: repairGroup,
        repairState: repairState,
        remainingDevices: remainingDevices,
        statusGroup: statusGroup,
        statusState: statusState,
        canSendSecure: canSendSecure,
        hasLocalState: hasLocalState,
        hasActiveMembership: hasActiveMembership,
      );
      if (evidence.repairGroup == groupDid &&
          evidence.repairState.toLowerCase() == 'ready' &&
          evidence.remainingDevices == 0 &&
          evidence.statusGroup == groupDid &&
          evidence.statusState.toLowerCase() == 'ready' &&
          evidence.canSendSecure &&
          evidence.hasLocalState &&
          evidence.hasActiveMembership) {
        return evidence;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    return _CliGroupSecureEvidence(
      repairGroup: repairGroup,
      repairState: repairState,
      remainingDevices: remainingDevices,
      statusGroup: statusGroup,
      statusState: statusState,
      canSendSecure: canSendSecure,
      hasLocalState: hasLocalState,
      hasActiveMembership: hasActiveMembership,
    );
  }

  Future<void> requireRootlessCurrentMember({
    required String expectedDid,
    required String expectedDeviceId,
  }) async {
    final identity = await _loadCurrentIdentityStatus();
    if (identity['did'] != expectedDid ||
        identity['has_jwt'] != true ||
        identity['has_did_document'] != true) {
      fail('The joining CLI was not a fresh-auth rootless identity.');
    }
    _requireCliJoinedMember(
      await waitForRegistryDeviceCount(2),
      joinedDeviceId: expectedDeviceId,
    );
  }

  Future<void> waitForRootImportCompletion({
    required String expectedDid,
    required String expectedDeviceId,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      final inbox = await _run(const <String>[
        '--format',
        'json',
        'msg',
        'inbox',
        '--scope',
        'direct',
        '--limit',
        '20',
      ]);
      final inboxData = _data(inbox, action: null);
      final rawMessages = inboxData['messages'];
      if (rawMessages is! List) {
        fail('The CLI inbox returned no safe message projection.');
      }
      if (rawMessages.isNotEmpty) {
        fail('Root P5 or an ACK entered the ordinary CLI inbox projection.');
      }

      final devices = await loadRegistry();
      final currentReadyAdmin = devices
          .where(
            (device) =>
                device['protocol_device_id'] == expectedDeviceId &&
                device['is_current'] == true &&
                device['role'] == 'admin' &&
                device['management_ready'] == true &&
                device['status'] == 'active',
          )
          .toList(growable: false);
      if (devices.length == 2 && currentReadyAdmin.length == 1) {
        final identity = await _loadCurrentIdentityStatus();
        if (identity['did'] != expectedDid ||
            identity['has_jwt'] != true ||
            identity['has_did_document'] != true) {
          fail(
            'Receiver Registry became ready without fresh authenticated identity state.',
          );
        }
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 750));
    }
    fail('The CLI receiver did not complete root import and readiness.');
  }

  Future<Map<String, Object?>> _loadCurrentIdentityStatus() async {
    final payload = await _run(const <String>[
      '--format',
      'json',
      'id',
      'status',
    ]);
    final identity = _data(payload, action: null)['active_identity'];
    if (identity is! Map) {
      fail('The CLI returned no active identity status.');
    }
    return _stringMap(identity);
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
      fail(
        'The independent CLI command failed '
        '(${safeCliFailureDiagnostic(exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr)}).',
      );
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
      if (config.multiDeviceDirectE2eeEnabled)
        'AWIKI_MULTI_DEVICE_DIRECT_E2EE_ENABLED': '1',
      if (config.multiDeviceGroupE2eeEnabled)
        'AWIKI_MULTI_DEVICE_GROUP_E2EE_ENABLED': '1',
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
    final listener = _joinRequestListener;
    _joinRequestListener = null;
    if (listener != null && !await _processExited(listener)) {
      listener.kill(ProcessSignal.sigterm);
      try {
        await listener.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        listener.kill(ProcessSignal.sigkill);
        await listener.exitCode;
      }
    }
    await _deleteDirectory(workspace);
    await _deleteDirectory(home);
  }
}

Future<bool> _processExited(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return true;
  } on TimeoutException {
    return false;
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

class _CliGroupSecureEvidence {
  const _CliGroupSecureEvidence({
    required this.repairGroup,
    required this.repairState,
    required this.remainingDevices,
    required this.statusGroup,
    required this.statusState,
    required this.canSendSecure,
    required this.hasLocalState,
    required this.hasActiveMembership,
  });

  final String repairGroup;
  final String repairState;
  final int remainingDevices;
  final String statusGroup;
  final String statusState;
  final bool canSendSecure;
  final bool hasLocalState;
  final bool hasActiveMembership;
}

AwikiEnvironmentConfig _joinOnlyEnvironment(
  _RemoteJoinEndpointConfig config, {
  bool enableRootTransfer = false,
  bool enableStep4 = false,
  bool enableAppPairFunctional = false,
}) => AwikiEnvironmentConfig(
  baseUrl: config.baseUrl,
  userServiceUrl: config.userServiceUrl,
  messageServiceUrl: config.messageServiceUrl,
  mailServiceUrl: config.mailServiceUrl,
  didDomain: config.didDomain,
  anpServiceUrl: config.anpServiceUrl,
  anpServiceDid: config.anpServiceDid,
  agentImEnabled: enableAppPairFunctional,
  messageSyncV2ReadEnabled: enableAppPairFunctional,
  multiDeviceDeviceRevokeEnabled: enableStep4 || enableAppPairFunctional,
  multiDeviceDirectE2eeEnabled: enableRootTransfer,
  multiDeviceGroupE2eeEnabled: enableStep4,
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

Future<String> _requestAndResolveOtp({
  required http.Client client,
  required _RemoteJoinEndpointConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
}) async {
  http.Response? response;
  for (var attempt = 0; attempt < 3; attempt += 1) {
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
      response = null;
      if (attempt == 2) {
        fail('The purpose-bound OTP request failed safely.');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      continue;
    }
    if (response.statusCode != 429 || attempt == 2) break;
    await Future<void>.delayed(
      remoteMultiDeviceOtpRetryDelay(response.headers['retry-after']),
    );
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
  required _RemoteJoinEndpointConfig config,
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

Future<DeviceRegistrySnapshot> _waitForAppRegistry(
  DeviceManagementCorePort core, {
  required String did,
  required int expectedDeviceCount,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final registry = await core.identityDeviceRegistry(did);
      if (registry.devices.length == expectedDeviceCount) {
        return registry;
      }
    } on Object {
      // Registry convergence remains a read-only remote oracle.
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  fail('The App Registry did not converge to the expected device count.');
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

List<String> _requiredStringList(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List ||
      value.isEmpty ||
      value.any((item) => item is! String || item.trim().isEmpty)) {
    throw StateError('Remote multi-device config is incomplete.');
  }
  return value.cast<String>().toList(growable: false);
}

void _requireAccountStateOperatorEnvironment(List<String> configuredCommand) {
  List<String>? environmentCommand;
  try {
    environmentCommand = parseAccountStateOperatorCommand(
      Platform.environment[_accountStateOperatorCommandEnv] ?? '',
    );
  } on FormatException {
    environmentCommand = null;
  }
  if (Platform.environment[_accountStateEnableEnv]?.trim() != '1' ||
      Platform.environment[_accountStateOperatorModeEnv]?.trim() != 'ali' ||
      Platform.environment[_syncRecoveryTargetEnv]?.trim() !=
          _syncRecoveryTarget ||
      Platform.environment[_accountStateFailpointEnableEnv]?.trim() != '1' ||
      environmentCommand == null ||
      !_sameOrderedText(
        environmentCommand,
        reviewedAccountStateOperatorCommand,
      ) ||
      !_sameOrderedText(
        configuredCommand,
        reviewedAccountStateOperatorCommand,
      )) {
    throw StateError('The App-pair Account State operator gate is incomplete.');
  }
}

bool _sameOrderedText(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
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
