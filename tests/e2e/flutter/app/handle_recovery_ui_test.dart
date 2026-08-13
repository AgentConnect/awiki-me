// [INPUT]: Audited awiki.info endpoints, one protected fixed test SMS account,
//          server-issued SMS retry boundaries, fresh production
//          AppBootstrap/native Core roots with primed replica sync tails, and
//          an E2E-only user-presence decision.
// [OUTPUT]: Secret-free proof that Recovery replaces the DID once, exactly
//           resumes post-commit local transition, preserves Direct/transport
//           Group/Agent continuity, attributes fixture failure to the active
//           identity/Direct/Group/Daemon/Runtime/Agent/checkpoint stage,
//           converges Root-promotion authorization without logging out the
//           promoted device, and fences an old App principal.
// [POS]: Remote product UI acceptance; setup creates only the remote fixture,
//        while the tested onboarding or Settings Recovery is UI-driven.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/e2e_semantics.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/agent/agent_control_service.dart';
import 'package:awiki_me/src/application/app_bootstrap_epoch_barrier.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/message_sync_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/account_state_sync_coordinator_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yaml/yaml.dart';

import '../../case_attestation.dart';
import '../../e2e_user_presence_port.dart';
import '../../handle_recovery_fixture_contract.dart';
import '../../remote_multi_device_join_contract.dart';

const String _caseId = 'HANDLE-RECOVERY-V1-E2E-001';
const String _crashCutCaseId = 'HANDLE-RECOVERY-V1-E2E-002';
const String _settingsContinuityCaseId =
    'HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001';
const String _rejoinCaseId = 'HANDLE-RECOVERY-V1-E2E-003';
const String _registrationRejoinCaseId =
    'HANDLE-RECOVERY-REGISTRATION-REJOIN-E2E-001';
const String _freshAgentInventoryCaseId =
    'HANDLE-RECOVERY-FRESH-AGENT-INVENTORY-E2E-001';
const String _freshAgentMessageCaseId =
    'HANDLE-RECOVERY-FRESH-AGENT-MESSAGE-E2E-001';
const String _freshDirectInboundCaseId =
    'HANDLE-RECOVERY-FRESH-DIRECT-INBOUND-E2E-001';
const String _freshGroupRebindCaseId =
    'HANDLE-RECOVERY-FRESH-GROUP-REBIND-E2E-001';
const String _freshGroupInboundCaseId =
    'HANDLE-RECOVERY-FRESH-GROUP-INBOUND-E2E-001';
const String _freshRestartCaseId = 'HANDLE-RECOVERY-FRESH-RESTART-E2E-001';
const List<String> _freshFocusedCaseIds = <String>[
  _freshAgentInventoryCaseId,
  _freshAgentMessageCaseId,
  _freshDirectInboundCaseId,
  _freshGroupRebindCaseId,
  _freshGroupInboundCaseId,
  _freshRestartCaseId,
];
const String _e2ePhase = String.fromEnvironment(
  'AWIKI_HANDLE_RECOVERY_E2E_PHASE',
);
const String _runConfigPath =
    '.e2e/multi-device-remote-recovery/current/run_config.json';
const String _activationGate = 'AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED';
const String _registrationPurpose = 'awiki.identity.register.v1';
const String _joinPurpose = 'awiki.device.join.v1';
const String _recoveryPurpose = 'awiki.identity.handle-recovery.v1';
const Key _recoveryAdminAppKey = Key('recovery-admin-app');
const Key _recoveryPeerAppKey = Key('recovery-peer-app');
const Duration _remoteTimeout = Duration(seconds: 30);
const String _agentReplyPrefix = 'RECOVERY_AGENT_REPLY:';

Future<void> _recordAppProjectionFixtureFailure({
  required String caseId,
  required String stage,
  required String code,
}) => E2eFailureObservationWriter.recordFirst(
  layer: 'app_projection',
  status: 'fatal',
  code: code,
  caseId: caseId,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Handle Recovery V4 replaces the DID through the visible App flow',
    (tester) async {
      final startedAt = DateTime.now().toUtc();
      final config = _RemoteRecoveryRunConfig.load();
      final account = _DedicatedAccount.fromConfig(config);
      final presence = E2eUserPresencePort();
      final peerPresence = E2eUserPresencePort();
      final registrationRejoinRequired = _invocationExpects(
        _registrationRejoinCaseId,
      );
      final freshFocusedRequired = _freshFocusedCaseIds.any(_invocationExpects);
      final rejoinRequired =
          _invocationExpects(_rejoinCaseId) || registrationRejoinRequired;
      final httpClient = http.Client();
      AppBootstrap? bootstrap;
      AppBootstrap? peerBootstrap;
      _RunningContinuityDaemon? freshDaemon;
      var retainFreshRoots = false;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await runHandleRecoveryFixtureBoundary<void>(
        record: freshFocusedRequired,
        caseId: _freshAgentInventoryCaseId,
        stage: 'fresh_root_precondition',
        action: () async {
          _requireFreshRoot(config.appStateRoot);
          if (rejoinRequired) {
            _requireIndependentFreshRoots(<String>[
              config.appStateRoot,
              config.peerAppStateRoot,
            ]);
          }
        },
        recordFailure: _recordAppProjectionFixtureFailure,
      );
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await freshDaemon?.stop();
        await bootstrap?.dispose();
        await peerBootstrap?.dispose();
        if (!retainFreshRoots) {
          await _deleteDirectory(config.appStateRoot);
          await _deleteDirectory(config.peerAppStateRoot);
          final daemonRoot = config.daemonStateRoot;
          if (daemonRoot != null) await _deleteDirectory(daemonRoot);
        }
        await tester.binding.setSurfaceSize(null);
      });

      bootstrap = await runHandleRecoveryFixtureBoundary<AppBootstrap>(
        record: freshFocusedRequired,
        caseId: _freshAgentInventoryCaseId,
        stage: 'app_bootstrap',
        action: () => AppBootstrap.create(
          environment: _environment(
            config,
            directE2eeEnabled: registrationRejoinRequired,
            groupE2eeEnabled: false,
            agentImEnabled: freshFocusedRequired,
          ),
          appStateRoot: config.appStateRoot,
        ),
        recordFailure: _recordAppProjectionFixtureFailure,
      );
      final bareHandle = _uniqueHandle(config.handlePrefix);
      final onboardingSupport = await runHandleRecoveryFixtureBoundary(
        record: freshFocusedRequired,
        caseId: _freshAgentInventoryCaseId,
        stage: 'onboarding_support',
        action: () async {
          final service = bootstrap!.onboardingSupportService;
          if (service == null) {
            fail('The production onboarding support service was unavailable.');
          }
          return service;
        },
        recordFailure: _recordAppProjectionFixtureFailure,
      );
      final registrationFactor = await runHandleRecoveryFixtureBoundary(
        record: freshFocusedRequired,
        caseId: _freshAgentInventoryCaseId,
        stage: 'registration_otp',
        action: () => _requestAndResolveRegistrationOtp(
          onboardingSupport: onboardingSupport,
          config: config,
          account: account,
          handle: bareHandle,
        ),
        recordFailure: _recordAppProjectionFixtureFailure,
      );
      final registration = await runHandleRecoveryFixtureBoundary(
        record: freshFocusedRequired,
        caseId: _freshAgentInventoryCaseId,
        stage: 'identity_registration',
        action: () async {
          final result = await bootstrap!.onboardingService!
              .registerHandleWithPhone(
                phone: account.phone,
                otp: registrationFactor.otp,
                handle: bareHandle,
                nickName: 'AWiki Handle Recovery E2E',
              );
          final identity = result.identity;
          if (result.status != IdentityRegistrationStatus.registered ||
              identity == null ||
              !identity.authenticated ||
              identity.handle == null) {
            fail(
              'The Recovery fixture did not create one authenticated identity.',
            );
          }
          return result;
        },
        recordFailure: _recordAppProjectionFixtureFailure,
      );
      final oldSession = registration.identity!;
      final oldDid = oldSession.did;
      final fullHandle = oldSession.handle!.trim().toLowerCase();
      await runHandleRecoveryFixtureBoundary<void>(
        record: freshFocusedRequired,
        caseId: _freshAgentInventoryCaseId,
        stage: 'registry_precondition',
        action: () async {
          final initialRegistry = await bootstrap!.deviceManagementCorePort!
              .identityDeviceRegistry(oldDid);
          _requireReadyCurrentAdmin(initialRegistry, expectedDid: oldDid);
        },
        recordFailure: _recordAppProjectionFixtureFailure,
      );
      _FreshRecoveryFixtureSnapshot? freshSnapshot;
      if (freshFocusedRequired) {
        await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
        await _pumpUntil(
          tester,
          () => find.byType(AppShell).evaluate().length == 1,
          timeout: const Duration(seconds: 45),
          failure: 'Fresh Recovery setup did not open the authenticated App.',
        );
        final setupContainer = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        final progress = HandleRecoveryFixtureProgress();
        final daemonConfig = _requireContinuityDaemonConfig(config);
        final fixture = await runHandleRecoveryFixtureStage(
          caseId: _freshAgentInventoryCaseId,
          progress: progress,
          action: () => _seedHandleRecoveryBusinessFixture(
            tester: tester,
            config: config,
            account: account,
            bootstrap: bootstrap!,
            container: setupContainer,
            inventory: setupContainer.read(agentInventoryPortProvider),
            agentControl: setupContainer.read(agentControlServiceProvider),
            conversations: setupContainer.read(conversationServiceProvider),
            ownerSession: oldSession,
            registrationRetryAt: registrationFactor.retryAt,
            daemonConfig: daemonConfig,
            progress: progress,
            kind: HandleRecoveryFixtureKind.freshRoot,
          ),
          recordFailure: _recordAppProjectionFixtureFailure,
        );
        final agents = await setupContainer
            .read(agentInventoryPortProvider)
            .listAgents(includeInactive: true);
        final daemon = requireHandleRecoveryExactOne<AgentSummary>(
          rawItems: agents,
          canonicalMatch: (agent) => agent.agentDid == fixture.daemonDid,
          semanticMatch: (agent) => agent.isDaemon,
        );
        final runtime = requireHandleRecoveryExactOne<AgentSummary>(
          rawItems: agents,
          canonicalMatch: (agent) => agent.agentDid == fixture.runtimeDid,
          semanticMatch: (agent) =>
              agent.isRuntime &&
              agent.daemonAgentDid == fixture.daemonDid &&
              agent.handle == fixture.runtimeHandle,
        );
        final group = await _waitForFixtureGroup(
          tester: tester,
          container: setupContainer,
          expectedReference: handleRecoveryFixtureReference(fixture.groupDid),
        );
        final members = await bootstrap.groupApplicationService!.listMembers(
          fixture.groupDid,
          limit: 100,
        );
        final accountState = await _requestFreshAccountState(
          tester: tester,
          container: setupContainer,
          reason: 'fresh-recovery-fixture-ready',
        );
        final checkpoint = fixture.checkpoint(
          caseId: _freshAgentInventoryCaseId,
          runId: config.runId,
          stableOwnerIdentityId: oldSession.identityId,
        );
        freshSnapshot = _FreshRecoveryFixtureSnapshot(
          fixture: fixture,
          checkpoint: checkpoint,
          daemon: daemon,
          runtime: runtime,
          group: group,
          members: members.items,
          accountStateVersions: accountState.domainVersions,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      var latestOtpRetryAt = registrationFactor.retryAt;
      String? oldPeerDeviceId;
      if (rejoinRequired) {
        peerBootstrap = await AppBootstrap.create(
          environment: _environment(
            config,
            directE2eeEnabled: registrationRejoinRequired,
            groupE2eeEnabled: false,
          ),
          appStateRoot: config.peerAppStateRoot,
        );
        final oldJoin = await _startAppPeerJoin(
          tester: tester,
          client: httpClient,
          config: config,
          account: account,
          adminBootstrap: bootstrap,
          peerBootstrap: peerBootstrap,
          adminPresence: presence,
          peerPresence: peerPresence,
          handle: bareHandle,
          expectedDid: oldDid,
        );
        latestOtpRetryAt = oldJoin.otpRetryAt;
        final authorized = await _completeAppPeerJoin(
          tester: tester,
          adminBootstrap: bootstrap,
          deviceCore: bootstrap.deviceManagementCorePort!,
          selector: oldDid,
          peerContainer: oldJoin.container,
          pending: oldJoin.progress,
        );
        oldPeerDeviceId = authorized.authorizedDevice?.protocolDeviceId;
        if (oldPeerDeviceId == null) {
          fail('The old App peer did not obtain an authorized device.');
        }
        await _activateAppPeerJoin(
          tester: tester,
          peerBootstrap: peerBootstrap,
          peerContainer: oldJoin.container,
          expectedDid: oldDid,
          expectedDeviceId: oldPeerDeviceId,
        );
        _requireAppAdminAndPeer(
          await _waitForAppRegistry(
            bootstrap.deviceManagementCorePort!,
            did: oldDid,
            expectedDeviceCount: 2,
          ),
          expectedDid: oldDid,
          peerDeviceId: oldPeerDeviceId,
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      bootstrap = null;
      await _deleteDirectory(config.appStateRoot);
      bootstrap = await AppBootstrap.create(
        environment: _environment(
          config,
          directE2eeEnabled: registrationRejoinRequired,
          groupE2eeEnabled: false,
          agentImEnabled: freshFocusedRequired,
        ),
        appStateRoot: config.appStateRoot,
      );
      if ((await bootstrap.appSessionService!.listLocalIdentities())
          .isNotEmpty) {
        fail('The Recovery machine unexpectedly retained a local identity.');
      }
      final recoveryCore = bootstrap.handleRecoveryCorePort;
      if (recoveryCore == null) {
        fail('The production Handle Recovery Core port was unavailable.');
      }
      final recordingRecoveryCore = _RecordingHandleRecoveryCorePort(
        recoveryCore,
      );

      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: <Override>[
            userPresencePortProvider.overrideWithValue(presence),
            handleRecoveryCorePortProvider.overrideWithValue(
              recordingRecoveryCore,
            ),
          ],
        ),
      );
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'The fresh machine did not open the real onboarding surface.',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      final onboardingFields = find.byType(CupertinoTextField);
      await _pumpUntil(
        tester,
        () => onboardingFields.evaluate().length >= 3,
        timeout: const Duration(seconds: 45),
        failure: 'The unified phone onboarding form did not become available.',
      );
      await tester.enterText(onboardingFields.at(0), account.phone);
      await tester.enterText(onboardingFields.at(1), bareHandle);
      await _waitForRegistrationRetryBoundary(latestOtpRetryAt);
      await _pumpUntil(
        tester,
        () {
          final onboarding = container.read(onboardingProvider);
          final cooldown = container.read(smsOtpCooldownProvider);
          return !onboarding.isBusy && cooldown.canSend;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The registration OTP action did not become enabled.',
      );
      final registrationFeedbackBefore = container.read(uiFeedbackProvider)?.id;
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-send-otp-button'),
        failure: 'The registration OTP action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(onboardingProvider);
          final feedback = container.read(uiFeedbackProvider);
          if (!state.isBusy &&
              feedback?.id != registrationFeedbackBefore &&
              feedback?.message.id == 'otpRateLimited') {
            return true;
          }
          _failOnDangerousUiFeedback(
            container,
            'Registration OTP request',
            existingEventId: registrationFeedbackBefore,
          );
          return !state.isBusy &&
              state.otpTargetFullHandle == fullHandle &&
              state.otpTargetPhone != null;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The UI did not bind the registration OTP to the Handle.',
        safeDiagnostic: () {
          final onboarding = container.read(onboardingProvider);
          final cooldown = container.read(smsOtpCooldownProvider);
          final feedback = container.read(uiFeedbackProvider);
          return <String>[
            'busy=${onboarding.isBusy}',
            'handle_target_present=${onboarding.otpTargetFullHandle != null}',
            'handle_target_matches=${onboarding.otpTargetFullHandle == fullHandle}',
            'phone_target_present=${onboarding.otpTargetPhone != null}',
            'cooldown_ready=${cooldown.isReady}',
            'cooldown_sending=${cooldown.isSending}',
            'cooldown_remaining=${cooldown.remainingSeconds}',
            'feedback=${_safeDiagnosticToken(feedback?.message.id)}',
          ].join(',');
        },
      );
      final registrationRateLimitFeedback = container.read(uiFeedbackProvider);
      if (registrationRateLimitFeedback?.message.id == 'otpRateLimited') {
        await _retryRegistrationOtpAfterRateLimit(tester, container);
        await _pumpUntil(
          tester,
          () {
            _failOnDangerousUiFeedback(
              container,
              'Registration OTP retry',
              existingEventId: registrationRateLimitFeedback!.id,
            );
            final state = container.read(onboardingProvider);
            return !state.isBusy &&
                state.otpTargetFullHandle == fullHandle &&
                state.otpTargetPhone != null;
          },
          timeout: const Duration(seconds: 45),
          failure: 'The UI did not bind the retried registration OTP.',
        );
      }
      final onboardingOtp = await _resolveOtp(
        account: account,
        purpose: _registrationPurpose,
        handle: bareHandle,
        didDomain: config.didDomain,
      );
      await tester.enterText(onboardingFields.at(2), onboardingOtp);
      await _tapOne(
        tester,
        find.byKey(const Key('onboarding-mac-phone-submit-action')),
        failure: 'The unified login/register action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          _failOnDangerousUiFeedback(container, 'Existing Handle verification');
          final state = container.read(onboardingProvider);
          return find
                      .byKey(const Key('existing-handle-recovery-action'))
                      .evaluate()
                      .length ==
                  1 &&
              state.isPhoneOtpConsumed &&
              !state.canSubmitPhoneOtp;
        },
        timeout: const Duration(seconds: 45),
        failure: 'Existing Handle did not expose the Join/Recovery choice.',
      );
      await _waitForPhoneGlobalRecoveryCooldown(tester, container);
      await _tapOne(
        tester,
        find.byKey(const Key('existing-handle-recovery-action')),
        failure: 'The existing-Handle Recovery choice was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(HandleRecoveryPage).evaluate().length == 1,
        failure: 'The unified onboarding flow did not open Recovery.',
      );
      final recoveryPage = find.byType(HandleRecoveryPage);
      if (find
                  .descendant(
                    of: find.byKey(const Key('handle-recovery-handle')),
                    matching: find.text(fullHandle),
                  )
                  .evaluate()
                  .length !=
              1 ||
          find
                  .descendant(
                    of: find.byKey(const Key('handle-recovery-phone')),
                    matching: find.text(account.phone),
                  )
                  .evaluate()
                  .length !=
              1 ||
          find
                  .descendant(
                    of: recoveryPage,
                    matching: find.byType(CupertinoTextField),
                  )
                  .evaluate()
                  .length !=
              1) {
        fail(
          'Recovery did not reuse the verified Handle and phone as read-only context.',
        );
      }
      var recoveryOtpRateLimitRetries = 0;
      await _pumpUntil(
        tester,
        () {
          final state = container.read(handleRecoveryProvider);
          return !state.isBusy &&
              ((state.otpRequested && state.otpOperationId != null) ||
                  state.error == HandleRecoveryUiError.rateLimited);
        },
        timeout: const Duration(seconds: 45),
        failure: 'The UI did not accept an operation-bound Recovery OTP.',
      );
      if (container.read(handleRecoveryProvider).error ==
          HandleRecoveryUiError.rateLimited) {
        recoveryOtpRateLimitRetries = 1;
        await _retryRecoveryOtpAfterRateLimit(tester, container);
      }
      await _pumpUntil(
        tester,
        () {
          final state = container.read(handleRecoveryProvider);
          _failOnRecoveryError(
            state,
            'OTP request',
            coreDiagnostic: recordingRecoveryCore.lastSafeFailure,
          );
          return state.otpRequested &&
              state.otpOperationId != null &&
              !state.isBusy;
        },
        timeout: const Duration(seconds: 45),
        failure: 'The UI did not accept an operation-bound Recovery OTP.',
      );
      final operationId = container
          .read(handleRecoveryProvider)
          .otpOperationId!;
      if (recordingRecoveryCore.requestOtpCalls !=
              1 + recoveryOtpRateLimitRetries ||
          recordingRecoveryCore.requestedHandle != fullHandle ||
          recordingRecoveryCore.requestedPhone != account.phone ||
          recordingRecoveryCore.requestedLocalIdentityId != null) {
        fail(
          'Recovery did not submit the exact verified context without a local selector.',
        );
      }
      final recoveryOtpRetryAt = recordingRecoveryCore.requestedRetryAt;
      if (recoveryOtpRetryAt == null) {
        fail('Recovery OTP omitted its structured retry boundary.');
      }
      latestOtpRetryAt = recoveryOtpRetryAt;
      final recoveryOtp = await _resolveOtp(
        account: account,
        purpose: _recoveryPurpose,
        handle: bareHandle,
        didDomain: config.didDomain,
        operationId: operationId,
      );
      await _enterTextByKey(
        tester,
        const Key('handle-recovery-otp'),
        recoveryOtp,
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('handle-recovery-verify'),
        failure: 'The Handle Recovery verification action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(handleRecoveryProvider);
          _failOnRecoveryError(
            state,
            'OTP verification',
            coreDiagnostic: recordingRecoveryCore.lastSafeFailure,
          );
          return state.progress?.phase ==
                  HandleRecoveryProgressPhase.prepared &&
              !state.isBusy;
        },
        timeout: const Duration(minutes: 2),
        failure: 'The UI did not reach the prepared Recovery phase.',
      );
      if (recordingRecoveryCore.requestedLocalIdentityId != null) {
        fail('Fresh-machine Recovery unexpectedly supplied a local identity.');
      }
      if (find.byKey(const Key('handle-recovery-progress')).evaluate().length !=
              1 ||
          find
                  .byKey(const Key('handle-recovery-risk-confirmation'))
                  .evaluate()
                  .length !=
              1) {
        fail('The prepared Recovery risks were not visibly presented.');
      }

      await _tapOne(
        tester,
        find.byKey(const Key('handle-recovery-risk-confirmation')),
        failure: 'The irreversible-risk confirmation was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => container.read(handleRecoveryProvider).riskConfirmed,
        failure: 'The UI did not retain explicit risk confirmation.',
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('handle-recovery-activate'),
        failure: 'The risk-gated Recovery activation was unavailable.',
      );
      await _waitForCompletedRecovery(tester, container);
      if (presence.calls != 1 ||
          presence.completions != 1 ||
          !presence.lastResult) {
        fail('Recovery did not use exactly one E2E user-presence decision.');
      }

      final completed = container.read(handleRecoveryProvider).progress!;
      final reset = completed.registryEpochReset;
      if (completed.handle != fullHandle ||
          reset == null ||
          reset.previousDid != oldDid ||
          reset.currentDid == oldDid ||
          reset.handle != fullHandle ||
          reset.sourceKind != HandleRecoveryTransitionSourceKind.initiator) {
        fail(
          'Recovery did not expose the expected DID replacement projection.',
        );
      }
      final localIdentities = await bootstrap.appSessionService!
          .listLocalIdentities();
      if (localIdentities.length != 1 ||
          localIdentities.single.identityId != completed.ownerIdentityId ||
          localIdentities.single.did != reset.currentDid ||
          localIdentities.single.did == oldDid ||
          localIdentities.single.handle?.trim().toLowerCase() != fullHandle ||
          localIdentities.any((identity) => identity.did == oldDid)) {
        fail(
          'The fresh local identity inventory did not install the recovery.',
        );
      }
      final activeBinding = await bootstrap.identityCorePort!
          .activeSyncAccountBinding();
      final authorizedReceipt = await recordingRecoveryCore
          .authorizedEpochReceipt(
            HandleRecoveryOwner(
              localIdentityId: completed.ownerIdentityId,
              handle: fullHandle,
            ),
          );
      if (authorizedReceipt == null) {
        fail('Core did not expose the authorized Recovery epoch receipt.');
      }
      final receiptMismatches = _receiptMismatchFields(
        authorizedReceipt,
        identity: localIdentities.single,
        binding: activeBinding,
      );
      if (receiptMismatches.isNotEmpty) {
        fail(
          'The authorized Recovery epoch receipt mismatched safe fields: '
          '${receiptMismatches.join(',')}.',
        );
      }
      final finalRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(reset.currentDid);
      _requireReadyCurrentAdmin(finalRegistry, expectedDid: reset.currentDid);

      await _pumpUntil(
        tester,
        () =>
            container.read(sessionProvider).session?.did == reset.currentDid &&
            container.read(appRuntimeProvider).activatedDid ==
                reset.currentDid &&
            container.read(shellDestinationProvider) ==
                ShellDestination.messages &&
            find.byType(HandleRecoveryPage).evaluate().isEmpty &&
            find.byType(ConversationWorkspacePage).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure:
            'The recovered identity did not open the message workspace automatically.',
        safeDiagnostic: () {
          final session = container.read(sessionProvider).session;
          final runtime = container.read(appRuntimeProvider);
          return 'session_present=${session != null}, '
              'session_is_recovered=${session?.did == reset.currentDid}, '
              'runtime_is_recovered=${runtime.activatedDid == reset.currentDid}, '
              'runtime_busy=${runtime.isBusy}, '
              'recovery_page_visible=${find.byType(HandleRecoveryPage).evaluate().isNotEmpty}, '
              'message_workspace_visible=${find.byType(ConversationWorkspacePage).evaluate().isNotEmpty}';
        },
      );
      if (freshFocusedRequired) {
        Object? focusedFailure;
        try {
          await _runFreshFocusedGates(
            tester: tester,
            config: config,
            bootstrap: bootstrap,
            container: container,
            snapshot: freshSnapshot!,
            oldDid: oldDid,
            newDid: reset.currentDid,
            startedAt: startedAt,
            startDaemon: () async {
              freshDaemon ??= await _RunningContinuityDaemon.start(
                config: config,
                daemonConfig: _requireContinuityDaemonConfig(config),
                gatewayScript: await _writeContinuityHermesGateway(
                  _requireContinuityDaemonConfig(config),
                ),
              );
            },
          );
        } catch (error) {
          focusedFailure = error;
        }
        retainFreshRoots = _invocationExpects(_freshRestartCaseId);
        if (focusedFailure != null) throw focusedFailure;
      }

      if (rejoinRequired) {
        if (peerBootstrap == null || oldPeerDeviceId == null) {
          fail('The isolated old App peer fixture was unavailable.');
        }
        await _requireOldAppPrincipalFenced(
          peerBootstrap,
          targetDid: reset.currentDid,
        );
        final rejoin = registrationRejoinRequired
            ? await _startAppPeerRegistrationJoin(
                tester: tester,
                config: config,
                account: account,
                adminBootstrap: bootstrap,
                peerBootstrap: peerBootstrap,
                adminPresence: presence,
                peerPresence: peerPresence,
                handle: bareHandle,
                fullHandle: fullHandle,
                expectedDid: reset.currentDid,
                registrationRetryAt: latestOtpRetryAt,
              )
            : await _startAppPeerJoin(
                tester: tester,
                client: httpClient,
                config: config,
                account: account,
                adminBootstrap: bootstrap,
                peerBootstrap: peerBootstrap,
                adminPresence: presence,
                peerPresence: peerPresence,
                handle: bareHandle,
                joinHandle: fullHandle,
                expectedDid: reset.currentDid,
              );
        final reauthorized = await _completeAppPeerJoin(
          tester: tester,
          adminBootstrap: bootstrap,
          deviceCore: bootstrap.deviceManagementCorePort!,
          selector: reset.currentDid,
          peerContainer: rejoin.container,
          pending: rejoin.progress,
        );
        final reauthorizedDevice = reauthorized.authorizedDevice;
        if (reauthorizedDevice == null ||
            reauthorizedDevice.role != DeviceRole.member ||
            reauthorizedDevice.managementReady ||
            !reauthorizedDevice.isCurrent) {
          fail('The old App peer did not complete a member re-Join.');
        }
        await _activateAppPeerJoin(
          tester: tester,
          peerBootstrap: peerBootstrap,
          peerContainer: rejoin.container,
          expectedDid: reset.currentDid,
          expectedDeviceId: reauthorizedDevice.protocolDeviceId,
        );
        final recoveredContainer = await _waitForRecoveredAppSession(
          tester,
          expectedDid: reset.currentDid,
        );
        final convergedRegistry = await _waitForAppRegistry(
          bootstrap.deviceManagementCorePort!,
          did: reset.currentDid,
          expectedDeviceCount: 2,
        );
        _requireAppAdminAndPeer(
          convergedRegistry,
          expectedDid: reset.currentDid,
          peerDeviceId: reauthorizedDevice.protocolDeviceId,
        );
        await _requirePeerCurrentIdentityAndRegistry(
          peerBootstrap,
          expectedDid: reset.currentDid,
          expectedDeviceId: reauthorizedDevice.protocolDeviceId,
          expectedDeviceCount: 2,
        );
        if (registrationRejoinRequired) {
          await _transferManagementToRejoinedPeer(
            bootstrap: bootstrap,
            peerBootstrap: peerBootstrap,
            peerContainer: rejoin.container,
            recoveredContainer: recoveredContainer,
            presence: presence,
            expectedDid: reset.currentDid,
            peerDeviceId: reauthorizedDevice.protocolDeviceId,
          );
        }
        if (recoveredContainer.read(sessionProvider).session?.did !=
                reset.currentDid ||
            recoveredContainer.read(appRuntimeProvider).activatedDid !=
                reset.currentDid) {
          fail('The recovered App session changed during peer re-Join.');
        }
        final peerIdentities = await peerBootstrap.appSessionService!
            .listLocalIdentities();
        if (peerIdentities.length != 1 ||
            peerIdentities.single.did != reset.currentDid) {
          fail('The rejoined App peer identity scope was not exact.');
        }
        final rejoinedIdentityId = peerIdentities.single.identityId;
        final externalHandle = _uniqueHandle('${config.handlePrefix}external');
        final externalFactor = await _requestAndResolveRegistrationOtp(
          onboardingSupport: peerBootstrap.onboardingSupportService!,
          config: config,
          account: account,
          handle: externalHandle,
        );
        final externalRegistration = await peerBootstrap.onboardingService!
            .registerHandleWithPhone(
              phone: account.phone,
              otp: externalFactor.otp,
              handle: externalHandle,
              nickName: 'AWiki Recovery External App Identity',
            );
        final externalIdentity = externalRegistration.identity;
        if (externalRegistration.status !=
                IdentityRegistrationStatus.registered ||
            externalIdentity == null ||
            !externalIdentity.authenticated ||
            externalIdentity.did == reset.currentDid) {
          fail('The second App did not create an external Direct identity.');
        }
        await _verifyBidirectionalDirectExactOne(
          tester: tester,
          bootstrap: bootstrap,
          peerBootstrap: peerBootstrap,
          did: reset.currentDid,
          rejoinedIdentityId: rejoinedIdentityId,
          externalIdentityId: externalIdentity.identityId,
          externalDid: externalIdentity.did,
          runId: config.runId,
        );
      }

      if (_invocationExpects(_caseId)) {
        await E2eCaseAttestationWriter.markPassed(
          _caseId,
          startedAt: startedAt,
          phases: const <String>[
            'existing_ready_admin_created',
            'fresh_machine_has_no_local_identity',
            'existing_handle_choice_opened_recovery',
            'verified_context_reused_without_duplicate_inputs',
            'operation_bound_otp_prepared_through_ui',
            'irreversible_risks_confirmed_through_ui',
            'recovery_completed_through_ui_resume',
            'recovery_opened_message_workspace',
            'recovery_navigation_followed_confirmed_session_activation',
            'new_local_owner_handle_and_replacement_did_verified',
            'old_did_absent_from_fresh_local_projection',
            'old_transport_group_rebound_to_recovered_did',
            'old_group_message_recognized_as_account_owned',
            'recovered_identity_sent_in_old_group',
          ],
        );
      }
      if (_invocationExpects(_rejoinCaseId)) {
        await E2eCaseAttestationWriter.markPassed(
          _rejoinCaseId,
          startedAt: startedAt,
          phases: const <String>[
            'old_app_peer_joined_before_recovery',
            'old_principal_remote_action_fenced',
            'old_app_returned_to_login_after_auth_fence',
            'fresh_ordinary_rejoin_authorized_to_recovery_did',
            'two_app_registry_session_converged',
            'app_to_external_direct_exact_one',
            'external_to_app_and_sibling_direct_exact_one',
          ],
        );
      }
      if (registrationRejoinRequired) {
        await E2eCaseAttestationWriter.markPassed(
          _registrationRejoinCaseId,
          startedAt: startedAt,
          phases: const <String>[
            'old_app_peer_joined_before_recovery',
            'old_principal_remote_action_fenced',
            'old_app_returned_to_login_after_auth_fence',
            'registration_returned_opaque_recovery_join_continuation',
            'registration_continuation_rejoined_recovery_did',
            'two_app_registry_session_converged',
            'standard_root_transfer_made_rejoined_peer_management_ready',
            'root_promotion_authorization_converged_without_logout',
            'app_to_external_direct_exact_one',
            'external_to_app_and_sibling_direct_exact_one',
          ],
        );
      }
    },
    skip:
        _e2ePhase.isNotEmpty ||
        !_RemoteRecoveryRunConfig.exists() ||
        (!_invocationExpects(_caseId) &&
            !_invocationExpects(_rejoinCaseId) &&
            !_invocationExpects(_registrationRejoinCaseId) &&
            !_freshFocusedCaseIds.any(_invocationExpects)),
    timeout: Timeout(
      Duration(
        minutes: _invocationExpects(_registrationRejoinCaseId)
            ? 25
            : _freshFocusedCaseIds.any(_invocationExpects)
            ? 35
            : 20,
      ),
    ),
  );

  testWidgets(
    'Handle Recovery crash-cut phase A stops before Product reset',
    _runRecoveryCrashCutPhaseA,
    skip:
        _e2ePhase != 'crash_a' ||
        !_RemoteRecoveryRunConfig.exists() ||
        (!_invocationExpects(_crashCutCaseId) &&
            !_invocationExpects(_settingsContinuityCaseId)),
    timeout: Timeout(
      Duration(
        minutes: _invocationExpects(_settingsContinuityCaseId) ? 25 : 15,
      ),
    ),
  );

  testWidgets(
    'Handle Recovery crash-cut phase B applies barrier before session restore',
    _runRecoveryCrashCutPhaseB,
    skip:
        _e2ePhase != 'crash_b' ||
        !_RemoteRecoveryRunConfig.exists() ||
        (!_invocationExpects(_crashCutCaseId) &&
            !_invocationExpects(_settingsContinuityCaseId)),
    timeout: Timeout(
      Duration(minutes: _invocationExpects(_settingsContinuityCaseId) ? 15 : 8),
    ),
  );

  testWidgets(
    'Fresh Handle Recovery survives a cold App process restart',
    _runFreshRecoveryRestart,
    skip:
        _e2ePhase != 'fresh_restart' ||
        !_RemoteRecoveryRunConfig.exists() ||
        !_invocationExpects(_freshRestartCaseId),
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

class _ContinuityDaemonConfig {
  const _ContinuityDaemonConfig({
    required this.binary,
    required this.stateRoot,
    required this.readyFile,
    required this.handle,
  });

  final String binary;
  final String stateRoot;
  final String readyFile;
  final String handle;
}

class _HandleRecoveryBusinessFixture {
  const _HandleRecoveryBusinessFixture({
    required this.kind,
    required this.registrationRetryAt,
    required this.peerDid,
    required this.directConversationId,
    required this.peerDirectConversationId,
    required this.directOutgoing,
    required this.directIncoming,
    required this.groupDid,
    required this.groupConversationId,
    required this.group,
    required this.groupOwner,
    required this.groupPeer,
    required this.groupOutgoing,
    required this.groupIncoming,
    required this.daemonDid,
    required this.runtimeDid,
    required this.runtimeHandle,
    required this.agentConversationId,
    required this.agentPrompt,
    required this.agentReply,
    required this.conversationIds,
    required this.agentDids,
    required this.directMessageCount,
    required this.groupMessageCount,
    required this.groupMemberCount,
    required this.agentMessageCount,
  });

  final HandleRecoveryFixtureKind kind;
  final DateTime registrationRetryAt;
  final String peerDid;
  final String directConversationId;
  final String peerDirectConversationId;
  final ChatMessage directOutgoing;
  final ChatMessage directIncoming;
  final String groupDid;
  final String groupConversationId;
  final GroupSummary group;
  final GroupMemberSummary groupOwner;
  final GroupMemberSummary groupPeer;
  final ChatMessage groupOutgoing;
  final ChatMessage groupIncoming;
  final String daemonDid;
  final String runtimeDid;
  final String runtimeHandle;
  final String agentConversationId;
  final ChatMessage agentPrompt;
  final ChatMessage agentReply;
  final List<String> conversationIds;
  final List<String> agentDids;
  final int directMessageCount;
  final int groupMessageCount;
  final int groupMemberCount;
  final int agentMessageCount;

  HandleRecoveryFixtureCheckpoint checkpoint({
    required String caseId,
    required String runId,
    required String stableOwnerIdentityId,
  }) {
    final commonReferences = <String, String>{
      'admin_identity': stableOwnerIdentityId,
      'daemon_agent': daemonDid,
      'direct_peer': peerDid,
      'external_group_member': peerDid,
      'transport_group': groupDid,
      'runtime_agent': runtimeDid,
      'runtime_handle': runtimeHandle,
    };
    final commonCounts = <String, int>{
      'admin_identities': 1,
      'daemon_agents': 1,
      'direct_peers': 1,
      'external_group_members': 1,
      'transport_groups': 1,
      'runtime_agents': 1,
    };
    return HandleRecoveryFixtureCheckpoint.fromRaw(
      caseId: caseId,
      kind: kind,
      stage: HandleRecoveryFixtureStage.checkpointReady,
      runId: runId,
      rawReferences: kind == HandleRecoveryFixtureKind.freshRoot
          ? commonReferences
          : <String, String>{
              ...commonReferences,
              'direct_conversation': directConversationId,
              'peer_direct_conversation': peerDirectConversationId,
              'direct_outgoing_message': _requiredMessageId(directOutgoing),
              'direct_outgoing_semantic': directOutgoing.content,
              'direct_incoming_message': _requiredMessageId(directIncoming),
              'direct_incoming_semantic': directIncoming.content,
              'direct_read_message': _requiredMessageId(directIncoming),
              'group_conversation': groupConversationId,
              'group_display_name': group.displayName,
              'group_description': group.description,
              'group_role': _checkpointOptional(group.myRole),
              'group_membership_status': _checkpointOptional(
                group.membershipStatus,
              ),
              'group_owner_role': groupOwner.role,
              'group_owner_membership_status': groupOwner.membershipStatus.name,
              'group_peer_role': groupPeer.role,
              'group_peer_membership_status': groupPeer.membershipStatus.name,
              'group_outgoing_message': _requiredMessageId(groupOutgoing),
              'group_outgoing_semantic': groupOutgoing.content,
              'group_incoming_message': _requiredMessageId(groupIncoming),
              'group_incoming_semantic': groupIncoming.content,
              'group_read_message': _requiredMessageId(groupIncoming),
              'agent_conversation': agentConversationId,
              'agent_prompt_message': _requiredMessageId(agentPrompt),
              'agent_prompt_semantic': agentPrompt.content,
              'agent_reply_message': _requiredMessageId(agentReply),
              'agent_reply_semantic': agentReply.content,
              'conversation_inventory': jsonEncode(conversationIds),
              'agent_inventory': jsonEncode(agentDids),
            },
      expectedCounts: kind == HandleRecoveryFixtureKind.freshRoot
          ? commonCounts
          : <String, int>{
              ...commonCounts,
              'direct_messages': directMessageCount,
              'group_messages': groupMessageCount,
              'group_members': groupMemberCount,
              'agent_messages': agentMessageCount,
              'agent_inventory_items': agentDids.length,
              'conversations': conversationIds.length,
            },
    );
  }
}

class _FreshRecoveryFixtureSnapshot {
  const _FreshRecoveryFixtureSnapshot({
    required this.fixture,
    required this.checkpoint,
    required this.daemon,
    required this.runtime,
    required this.group,
    required this.members,
    required this.accountStateVersions,
  });

  final _HandleRecoveryBusinessFixture fixture;
  final HandleRecoveryFixtureCheckpoint checkpoint;
  final AgentSummary daemon;
  final AgentSummary runtime;
  final GroupSummary group;
  final List<GroupMemberSummary> members;
  final Map<ProductAccountDomain, String> accountStateVersions;
}

_ContinuityDaemonConfig _requireContinuityDaemonConfig(
  _RemoteRecoveryRunConfig config,
) {
  final binary = config.daemonBinary?.trim() ?? '';
  final stateRoot = config.daemonStateRoot?.trim() ?? '';
  final readyFile = config.daemonReadyFile?.trim() ?? '';
  final handle = config.daemonHandle?.trim() ?? '';
  if (binary.isEmpty ||
      stateRoot.isEmpty ||
      readyFile.isEmpty ||
      handle.isEmpty ||
      !File(binary).existsSync()) {
    fail('Settings Recovery continuity requires one audited daemon fixture.');
  }
  return _ContinuityDaemonConfig(
    binary: binary,
    stateRoot: stateRoot,
    readyFile: readyFile,
    handle: handle,
  );
}

Future<_HandleRecoveryBusinessFixture> _seedHandleRecoveryBusinessFixture({
  required WidgetTester tester,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required AgentInventoryPort inventory,
  required AgentControlService agentControl,
  required ConversationService conversations,
  required AppSession ownerSession,
  required DateTime registrationRetryAt,
  required _ContinuityDaemonConfig daemonConfig,
  required HandleRecoveryFixtureProgress progress,
  required HandleRecoveryFixtureKind kind,
}) async {
  final ownerDid = ownerSession.did;
  final ownerHandle = ownerSession.handle?.trim().toLowerCase() ?? '';
  final messaging = bootstrap.messagingService;
  final sync = bootstrap.messageSyncService;
  final groups = bootstrap.groupApplicationService;
  if (ownerHandle.isEmpty ||
      messaging == null ||
      sync == null ||
      groups == null) {
    fail('Settings Recovery continuity dependencies were unavailable.');
  }

  progress.enter(HandleRecoveryFixtureStage.identity);
  final peerBootstrap = await AppBootstrap.create(
    environment: _environment(
      config,
      groupE2eeEnabled: false,
      agentImEnabled: true,
    ),
    appStateRoot: config.peerAppStateRoot,
  );
  try {
    await _waitForRegistrationRetryBoundary(registrationRetryAt);
    final peerHandle = _uniqueHandle('${config.handlePrefix}peer');
    final peerFactor = await _requestAndResolveRegistrationOtp(
      onboardingSupport: peerBootstrap.onboardingSupportService!,
      config: config,
      account: account,
      handle: peerHandle,
    );
    final peerRegistration = await peerBootstrap.onboardingService!
        .registerHandleWithPhone(
          phone: account.phone,
          otp: peerFactor.otp,
          handle: peerHandle,
          nickName: 'AWiki Recovery continuity peer',
        );
    final registeredPeer = peerRegistration.identity;
    if (peerRegistration.status != IdentityRegistrationStatus.registered ||
        registeredPeer == null ||
        !registeredPeer.authenticated ||
        registeredPeer.did == ownerDid) {
      fail('Settings Recovery did not create an independent Direct peer.');
    }
    await _activatePeerIdentity(
      peerBootstrap,
      identityId: registeredPeer.identityId,
      expectedDid: registeredPeer.did,
    );
    final peerSession = await peerBootstrap.appSessionService!.currentSession();
    if (peerSession == null ||
        !peerSession.authenticated ||
        peerSession.did != registeredPeer.did) {
      fail('The continuity peer did not activate its exact identity.');
    }
    await _syncHandleRecoveryFixtureWithRetry(
      tester: tester,
      bootstrap: peerBootstrap,
      reason: 'handle-recovery-fixture-peer-bootstrap',
    );
    progress.enter(HandleRecoveryFixtureStage.direct);
    final directOutgoing = await messaging.sendText(
      thread: AppThreadRef.direct(peerSession.did),
      content: 'direct-before-out ${config.runId} ${_nonce(8)}',
    );
    _requireCommittedDirect(
      directOutgoing,
      senderDid: ownerDid,
      receiverDid: peerSession.did,
      isMine: true,
    );
    await _syncAndWaitForAppThreadExactOne(
      tester: tester,
      appBootstrap: peerBootstrap,
      thread: AppThreadRef.direct(ownerDid),
      messageId: _requiredMessageId(directOutgoing),
      content: directOutgoing.content,
      senderDid: ownerDid,
      receiverDid: peerSession.did,
      isMine: false,
    );
    final directIncoming = await peerBootstrap.messagingService!.sendText(
      thread: AppThreadRef.direct(ownerDid),
      content: 'direct-before-in ${config.runId} ${_nonce(8)}',
    );
    _requireCommittedDirect(
      directIncoming,
      senderDid: peerSession.did,
      receiverDid: ownerDid,
      isMine: true,
    );
    final ownerIncomingProjection = await _syncAndWaitForAppThreadExactOne(
      tester: tester,
      appBootstrap: bootstrap,
      thread: AppThreadRef.direct(peerSession.did),
      messageId: _requiredMessageId(directIncoming),
      content: directIncoming.content,
      senderDid: peerSession.did,
      receiverDid: ownerDid,
      isMine: false,
    );
    final directConversation = await _waitForDirectConversation(
      tester: tester,
      bootstrap: bootstrap,
      ownerDid: ownerDid,
      peerDid: peerSession.did,
      content: directIncoming.content,
      unreadCount: 1,
    );
    final peerDirectConversation = await _waitForDirectConversation(
      tester: tester,
      bootstrap: peerBootstrap,
      ownerDid: peerSession.did,
      peerDid: ownerDid,
      content: directIncoming.content,
    );
    final directConversationId = directConversation.conversationId;
    final peerDirectConversationId = peerDirectConversation.conversationId;
    final peerDirectHistory = await _loadConversationHistory(
      peerBootstrap,
      peerDirectConversationId,
    );
    _requireExactMessage(
      peerDirectHistory,
      expected: directOutgoing,
      isMine: false,
      conversationId: peerDirectConversationId,
    );
    _requireExactMessage(
      peerDirectHistory,
      expected: directIncoming,
      isMine: true,
      conversationId: peerDirectConversationId,
    );
    await _markRecoveryFixtureRead(
      conversations: conversations,
      conversationId: directConversationId,
      message: ownerIncomingProjection,
    );
    progress.enter(HandleRecoveryFixtureStage.group);
    final group = await groups.createGroup(
      name: 'Settings Recovery continuity ${_nonce(8)}',
      slug: 'settings-recovery-${_nonce(10)}',
      description: 'Settings Handle Recovery continuity',
      goal: 'Verify stable transport Group continuity',
      rules: 'E2E only',
      identity: GroupIdentitySelection.handle(ownerHandle),
    );
    await groups.addMember(groupDid: group.groupId, memberRef: peerSession.did);
    await _waitForPeerGroup(
      tester: tester,
      peerBootstrap: peerBootstrap,
      groupDid: group.groupId,
    );
    final groupOutgoing = await messaging.sendText(
      thread: AppThreadRef.group(group.groupId),
      content: 'group-before-out ${config.runId} ${_nonce(8)}',
    );
    _requireCommittedGroup(
      groupOutgoing,
      groupDid: group.groupId,
      senderDid: ownerDid,
      isMine: true,
      conversationId: group.conversationId,
    );
    await _waitForGroupMessageExactOne(
      tester: tester,
      bootstrap: peerBootstrap,
      groupDid: group.groupId,
      messageId: _requiredMessageId(groupOutgoing),
      content: groupOutgoing.content,
      senderDid: ownerDid,
      isMine: false,
      conversationId: group.conversationId,
    );
    final groupIncoming = await peerBootstrap.messagingService!.sendText(
      thread: AppThreadRef.group(group.groupId),
      content: 'group-before-in ${config.runId} ${_nonce(8)}',
    );
    _requireCommittedGroup(
      groupIncoming,
      groupDid: group.groupId,
      senderDid: peerSession.did,
      isMine: true,
      conversationId: group.conversationId,
    );
    final ownerGroupIncomingProjection = await _waitForGroupMessageExactOne(
      tester: tester,
      bootstrap: bootstrap,
      groupDid: group.groupId,
      messageId: _requiredMessageId(groupIncoming),
      content: groupIncoming.content,
      senderDid: peerSession.did,
      isMine: false,
      conversationId: group.conversationId,
    );
    await _markRecoveryFixtureRead(
      conversations: conversations,
      conversationId: group.conversationId,
      message: ownerGroupIncomingProjection,
    );
    final groupBeforeRecovery = await groups.getGroup(group.groupId);
    final groupMembers = await groups.listMembers(group.groupId, limit: 100);
    final groupOwner = requireHandleRecoveryExactOne<GroupMemberSummary>(
      rawItems: groupMembers.items,
      canonicalMatch: (member) => member.did == ownerDid,
      semanticMatch: (member) =>
          member.did == ownerDid &&
          member.membershipStatus == GroupMemberMembershipStatus.active,
    );
    final groupPeer = requireHandleRecoveryExactOne<GroupMemberSummary>(
      rawItems: groupMembers.items,
      canonicalMatch: (member) => member.did == peerSession.did,
      semanticMatch: (member) =>
          member.did == peerSession.did &&
          member.membershipStatus == GroupMemberMembershipStatus.active,
    );
    if (groupMembers.items.length != 2 ||
        groupBeforeRecovery.memberCount != groupMembers.items.length ||
        groupBeforeRecovery.membershipStatus?.trim().toLowerCase() !=
            'active' ||
        groupBeforeRecovery.myRole?.trim().isEmpty != false) {
      fail('The Local Data fixture did not retain exact Group metadata.');
    }
    progress.enter(HandleRecoveryFixtureStage.daemon);
    final daemonInstall = await _installContinuityDaemon(
      config: config,
      daemonConfig: daemonConfig,
      inventory: inventory,
      controllerDid: ownerDid,
      controllerHandle: ownerHandle,
    );
    final gatewayScript = await _writeContinuityHermesGateway(daemonConfig);
    final daemon = await _RunningContinuityDaemon.start(
      config: config,
      daemonConfig: daemonConfig,
      gatewayScript: gatewayScript,
    );
    late final AgentSummary runtimeAgent;
    try {
      await _waitForContinuityDaemonReady(
        tester: tester,
        container: container,
        daemonDid: daemonInstall.daemonDid,
      );
      progress.enter(HandleRecoveryFixtureStage.runtime);
      final runtimeHandle = _uniqueHandle('${config.handlePrefix}runtime');
      final runtimeRequestId = 'recovery-runtime-${_nonce(12)}';
      try {
        await agentControl.createHermesRuntime(
          daemonAgentDid: daemonInstall.daemonDid,
          controllerDid: ownerDid,
          handle: runtimeHandle,
          displayName: 'Recovery continuity runtime',
          clientRequestId: runtimeRequestId,
        );
      } on TimeoutException {
        // Final acceptance can time out after the committed control message;
        // authoritative Inventory and daemon sync below decide the outcome.
      }
      runtimeAgent = await _waitForAgent(
        inventory: inventory,
        description: 'continuity Runtime Agent',
        matches: (agent) =>
            agent.isRuntime &&
            agent.daemonAgentDid == daemonInstall.daemonDid &&
            agent.handle == runtimeHandle,
      );
      await _waitForRuntimeMessageSyncReady(
        daemonStateRoot: daemonConfig.stateRoot,
        runtimeDid: runtimeAgent.agentDid,
      );
      final agentConversation = await _waitForRuntimeConversationRoute(
        tester: tester,
        bootstrap: bootstrap,
        runtimeDid: runtimeAgent.agentDid,
      );
      progress.enter(HandleRecoveryFixtureStage.agentMessage);
      final submittedPrompt = await _plainDirectMessaging(messaging)
          .sendPlainConversationText(
            conversation: agentConversation,
            content: 'agent-before ${config.runId} ${_nonce(8)}',
          );
      final prompt = await _syncAndWaitForConversationExactOne(
        tester: tester,
        bootstrap: bootstrap,
        conversation: agentConversation,
        messageId: _requiredMessageId(submittedPrompt),
        content: submittedPrompt.content,
        senderDid: ownerDid,
        receiverDid: runtimeAgent.agentDid,
        isMine: true,
      );
      _requireCommittedDirect(
        prompt,
        senderDid: ownerDid,
        receiverDid: runtimeAgent.agentDid,
        isMine: true,
      );
      final reply = await _waitForAgentReply(
        tester: tester,
        bootstrap: bootstrap,
        runtimeDid: runtimeAgent.agentDid,
        conversations: conversations,
        expectedContent: '$_agentReplyPrefix${prompt.content}',
        existingMessageIds: <String>{_requiredMessageId(prompt)},
      );
      final agentConversationId = _requiredConversationId(reply);

      progress.enter(HandleRecoveryFixtureStage.checkpoint);
      final directHistory = await _loadConversationHistory(
        bootstrap,
        directConversationId,
      );
      final groupHistory = await _retryHandleRecoveryCoreTransport(
        tester: tester,
        action: () => groups.listMessages(group.groupId, limit: 100),
        failure: 'Handle Recovery fixture Group history remained unavailable.',
      );
      final agentHistory = await _loadConversationHistory(
        bootstrap,
        agentConversationId,
      );
      _requireExactMessage(
        directHistory,
        expected: directOutgoing,
        isMine: true,
        conversationId: directConversationId,
      );
      _requireExactMessage(
        directHistory,
        expected: directIncoming,
        isMine: false,
        conversationId: directConversationId,
      );
      _requireExactMessage(
        groupHistory,
        expected: groupOutgoing,
        isMine: true,
        conversationId: group.conversationId,
      );
      _requireExactMessage(
        groupHistory,
        expected: groupIncoming,
        isMine: false,
        conversationId: group.conversationId,
      );
      _requireExactMessage(
        agentHistory,
        expected: prompt,
        isMine: true,
        conversationId: agentConversationId,
      );
      _requireExactMessage(
        agentHistory,
        expected: reply,
        isMine: false,
        conversationId: agentConversationId,
      );

      final agentInventory = await inventory.listAgents(includeInactive: true);
      final agentDids =
          agentInventory.map((agent) => agent.agentDid).toList(growable: false)
            ..sort();
      if (agentDids.toSet().length != agentDids.length ||
          agentDids.where((did) => did == runtimeAgent.agentDid).length != 1) {
        fail('Pre-Recovery Agent inventory contained a duplicate.');
      }
      final conversationIds = await _waitForContinuityConversationIds(
        tester: tester,
        bootstrap: bootstrap,
        conversations: conversations,
        ownerDid: ownerDid,
        requiredIds: <String>{
          directConversationId,
          group.conversationId,
          agentConversationId,
        },
      );
      return _HandleRecoveryBusinessFixture(
        kind: kind,
        registrationRetryAt: peerFactor.retryAt,
        peerDid: peerSession.did,
        directConversationId: directConversationId,
        peerDirectConversationId: peerDirectConversationId,
        directOutgoing: directOutgoing,
        directIncoming: directIncoming,
        groupDid: group.groupId,
        groupConversationId: group.conversationId,
        group: groupBeforeRecovery,
        groupOwner: groupOwner,
        groupPeer: groupPeer,
        groupOutgoing: groupOutgoing,
        groupIncoming: groupIncoming,
        daemonDid: daemonInstall.daemonDid,
        runtimeDid: runtimeAgent.agentDid,
        runtimeHandle: runtimeAgent.handle!,
        agentConversationId: agentConversationId,
        agentPrompt: prompt,
        agentReply: reply,
        conversationIds: conversationIds,
        agentDids: agentDids,
        directMessageCount: directHistory.length,
        groupMessageCount: groupHistory.length,
        groupMemberCount: groupMembers.items.length,
        agentMessageCount: agentHistory.length,
      );
    } finally {
      await daemon.stop();
    }
  } finally {
    await peerBootstrap.dispose();
  }
}

String _checkpointOptional(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? '<absent>' : normalized;
}

String _requiredMessageId(ChatMessage message) {
  final value = message.remoteId?.trim() ?? '';
  if (value.isEmpty) fail('A continuity message had no remote ID.');
  return value;
}

String _requiredConversationId(ChatMessage message) {
  final value = message.conversationId?.trim() ?? '';
  if (value.isEmpty) fail('A continuity message had no conversation ID.');
  return value;
}

Future<void> _markRecoveryFixtureRead({
  required ConversationService conversations,
  required String conversationId,
  required ChatMessage message,
}) async {
  final messageId = _requiredMessageId(message);
  final threadSequence = message.serverSequence?.toString();
  if (threadSequence == null) {
    fail('A Local Data read fixture had no public thread sequence.');
  }
  final result = await conversations.markConversationRead(
    AppConversationReadRef.fromConversationId(conversationId),
    watermark: AppThreadReadWatermark(
      lastReadMessageId: messageId,
      lastReadThreadSeq: threadSequence,
      readAt: DateTime.now().toUtc(),
    ),
  );
  final effective = result.effectiveWatermark;
  if (!result.remoteAcknowledged ||
      result.partial ||
      result.fallbackUsed ||
      result.pendingRemoteAck ||
      effective?.lastReadMessageId != messageId ||
      effective?.lastReadThreadSeq != threadSequence) {
    fail('A Local Data read fixture was not acknowledged exactly.');
  }
  requireHandleRecoveryReadWatermark(
    previousThreadSequence: threadSequence,
    currentThreadSequence: effective!.lastReadThreadSeq!,
    expectedThreadSequence: threadSequence,
  );
}

void _requireCommittedDirect(
  ChatMessage message, {
  required String senderDid,
  required String receiverDid,
  required bool isMine,
}) {
  if (_requiredMessageId(message).isEmpty ||
      _requiredConversationId(message).isEmpty ||
      message.senderDid != senderDid ||
      message.receiverDid != receiverDid ||
      message.isMine != isMine ||
      message.sendState != MessageSendState.sent) {
    fail('A continuity Direct message was not committed exactly.');
  }
}

void _requireCommittedGroup(
  ChatMessage message, {
  required String groupDid,
  required String senderDid,
  required bool isMine,
  required String conversationId,
}) {
  if (_requiredMessageId(message).isEmpty ||
      _requiredConversationId(message) != conversationId ||
      message.senderDid != senderDid ||
      message.groupId != groupDid ||
      message.isMine != isMine ||
      message.sendState != MessageSendState.sent) {
    fail('A continuity Group message was not committed exactly.');
  }
}

void _requireExactMessage(
  List<ChatMessage> history, {
  required ChatMessage expected,
  required bool isMine,
  required String conversationId,
}) {
  requireHandleRecoveryExactOne<ChatMessage>(
    rawItems: history,
    canonicalMatch: (message) => message.remoteId == expected.remoteId,
    semanticMatch: (message) =>
        message.content == expected.content &&
        message.senderDid == expected.senderDid &&
        message.isMine == isMine &&
        message.conversationId == conversationId,
  );
}

ChatMessage _requireExactStoredMessageByReference(
  List<ChatMessage> history, {
  required HandleRecoveryFixtureCheckpoint checkpoint,
  required String messageReferenceName,
  required String semanticReferenceName,
  required String senderDid,
  required bool isMine,
  required String conversationId,
}) {
  return requireHandleRecoveryReferenceExactOne<ChatMessage>(
    rawItems: history,
    expectedReference: checkpoint.reference(messageReferenceName),
    rawReference: _requiredMessageId,
    semanticMatch: (message) =>
        message.content.isNotEmpty &&
        handleRecoveryFixtureReference(message.content) ==
            checkpoint.reference(semanticReferenceName) &&
        message.senderDid == senderDid &&
        message.isMine == isMine &&
        message.conversationId == conversationId,
  );
}

bool _sameStrings(Iterable<String> left, Iterable<String> right) {
  final normalizedLeft = left.toList(growable: false)..sort();
  final normalizedRight = right.toList(growable: false)..sort();
  if (normalizedLeft.length != normalizedRight.length) return false;
  for (var index = 0; index < normalizedLeft.length; index += 1) {
    if (normalizedLeft[index] != normalizedRight[index]) return false;
  }
  return true;
}

bool _isSingleGenerationAdvance(String previous, String current) {
  final before = BigInt.tryParse(previous);
  final after = BigInt.tryParse(current);
  return before != null && after != null && after == before + BigInt.one;
}

Future<void> _waitForPeerGroup({
  required WidgetTester tester,
  required AppBootstrap peerBootstrap,
  required String groupDid,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await peerBootstrap.messageSyncService!.syncNow(
      reason: 'settings-recovery-group-member',
      limit: 100,
    );
    final groups = await peerBootstrap.groupApplicationService!.listGroups(
      limit: 100,
    );
    if (groups.items.where((group) => group.groupId == groupDid).length == 1) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('The continuity peer did not project the original Group once.');
}

Future<void> _waitForRecoveredContinuityGroup({
  required WidgetTester tester,
  required ProviderContainer container,
  required AppBootstrap bootstrap,
  required String groupDid,
  required String conversationId,
  required String previousDid,
  required String currentDid,
  required String peerDid,
  required HandleRecoveryFixtureCheckpoint checkpoint,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      await container.read(groupProvider.notifier).refresh();
      final projected = container
          .read(groupProvider)
          .groups
          .where((group) => group.groupId == groupDid)
          .toList(growable: false);
      if (projected.length > 1) {
        fail('Recovery duplicated the original Group projection.');
      }
      if (projected.length == 1 &&
          projected.single.conversationId == conversationId) {
        final group = await bootstrap.groupApplicationService!.getGroup(
          groupDid,
        );
        if (group.conversationId != conversationId) {
          fail('Recovery changed the original Group conversation ID.');
        }
        final members = await bootstrap.groupApplicationService!.listMembers(
          groupDid,
          limit: 100,
        );
        final ownerMatches = members.items
            .where((member) => member.did == currentDid)
            .toList(growable: false);
        final peerMatches = members.items
            .where((member) => member.did == peerDid)
            .toList(growable: false);
        if (ownerMatches.length == 1 &&
            members.items
                .where((member) => member.did == previousDid)
                .isEmpty &&
            peerMatches.length == 1 &&
            members.items.length == checkpoint.expectedCount('group_members') &&
            group.memberCount == checkpoint.expectedCount('group_members')) {
          checkpoint
            ..requireReference('group_display_name', group.displayName)
            ..requireReference('group_description', group.description)
            ..requireReference('group_role', _checkpointOptional(group.myRole))
            ..requireReference(
              'group_membership_status',
              _checkpointOptional(group.membershipStatus),
            )
            ..requireReference('group_owner_role', ownerMatches.single.role)
            ..requireReference(
              'group_owner_membership_status',
              ownerMatches.single.membershipStatus.name,
            )
            ..requireReference('group_peer_role', peerMatches.single.role)
            ..requireReference(
              'group_peer_membership_status',
              peerMatches.single.membershipStatus.name,
            );
          return;
        }
      }
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  fail(
    'The recovered Handle-backed transport Group did not converge '
    '(last_error=${_safeDiagnosticToken(lastError?.runtimeType.toString())}).',
  );
}

Future<ChatMessage> _waitForGroupMessageExactOne({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String groupDid,
  required String messageId,
  required String content,
  required String senderDid,
  required bool isMine,
  required String conversationId,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'settings-recovery-group-message',
      limit: 100,
    );
    final history = await bootstrap.groupApplicationService!.listMessages(
      groupDid,
      limit: 100,
    );
    final matches = history
        .where((message) => message.remoteId == messageId)
        .toList(growable: false);
    if (matches.length > 1) {
      fail('A Group message was projected more than once.');
    }
    if (matches.length == 1) {
      final message = matches.single;
      if (message.content != content ||
          message.senderDid != senderDid ||
          message.isMine != isMine ||
          message.conversationId != conversationId) {
        fail('A Group message projection changed identity or ownership.');
      }
      return message;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('A Group message did not converge exact-one.');
}

Future<ChatMessage> _syncAndWaitForConversationExactOne({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required AppConversationReadRef conversation,
  required String messageId,
  required String content,
  required String senderDid,
  required String receiverDid,
  required bool isMine,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'settings-recovery-conversation-message',
      limit: 100,
    );
    final history = await _loadConversationHistory(
      bootstrap,
      conversation.conversationId,
    );
    final matches = history
        .where(
          (message) =>
              message.remoteId == messageId && message.content == content,
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('A Direct conversation message was projected more than once.');
    }
    if (matches.length == 1) {
      final message = matches.single;
      if (message.senderDid != senderDid ||
          message.receiverDid != receiverDid ||
          message.isMine != isMine ||
          message.sendState != MessageSendState.sent ||
          message.conversationId != conversation.conversationId) {
        fail('A Direct conversation message changed identity or ownership.');
      }
      return message;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('A Direct conversation message did not converge exact-one.');
}

Future<ChatMessage> _waitForAgentReply({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String runtimeDid,
  String? conversationId,
  ConversationService? conversations,
  required String expectedContent,
  required Set<String> existingMessageIds,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'settings-recovery-agent-reply',
      limit: 100,
    );
    final history = conversationId == null
        ? await _loadAllConversationHistory(
            bootstrap,
            conversations: conversations,
          )
        : await _loadConversationHistory(bootstrap, conversationId);
    final matches = history
        .where(
          (message) =>
              message.senderDid == runtimeDid &&
              message.content == expectedContent &&
              !existingMessageIds.contains(message.remoteId),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('An Agent reply was projected more than once.');
    }
    if (matches.length == 1) {
      final reply = matches.single;
      if (reply.isMine ||
          reply.sendState != MessageSendState.sent ||
          _requiredMessageId(reply).isEmpty) {
        fail('The Agent reply had invalid ownership or state.');
      }
      return reply;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  fail('The original Agent did not return one deterministic reply.');
}

Future<List<ChatMessage>> _loadAllConversationHistory(
  AppBootstrap bootstrap, {
  ConversationService? conversations,
}) async {
  final session = await bootstrap.appSessionService!.currentSession();
  final effectiveConversations = conversations ?? bootstrap.conversationService;
  if (session == null || effectiveConversations == null) {
    fail('Canonical conversation discovery was unavailable.');
  }
  final summaries = await effectiveConversations.listConversations(
    ownerDid: session.did,
    limit: 100,
  );
  final messages = <ChatMessage>[];
  for (final summary in summaries) {
    messages.addAll(
      await _loadConversationHistory(bootstrap, summary.conversationId),
    );
  }
  return messages;
}

Future<List<ChatMessage>> _loadConversationHistory(
  AppBootstrap bootstrap,
  String conversationId,
) {
  final messaging = bootstrap.messagingService;
  if (messaging == null || messaging is! ConversationTimelineMessagingService) {
    fail('Canonical conversation timeline messaging was unavailable.');
  }
  final timeline = messaging as ConversationTimelineMessagingService;
  return timeline.loadConversationTimeline(
    AppConversationReadRef.fromConversationId(conversationId),
    limit: 100,
  );
}

Future<List<String>> _waitForContinuityConversationIds({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required ConversationService conversations,
  required String ownerDid,
  required Set<String> requiredIds,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'settings-recovery-conversation-count',
      limit: 100,
    );
    final items = await conversations.listConversations(
      ownerDid: ownerDid,
      limit: 100,
    );
    final ids = items.map((item) => item.conversationId).toList(growable: false)
      ..sort();
    if (ids.toSet().length != ids.length) {
      fail('Conversation projection contained duplicate IDs.');
    }
    if (requiredIds.every(ids.contains)) return ids;
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('The three continuity conversations did not converge.');
}

class _ContinuityDaemonInstall {
  const _ContinuityDaemonInstall({required this.daemonDid});

  final String daemonDid;
}

Future<_ContinuityDaemonInstall> _installContinuityDaemon({
  required _RemoteRecoveryRunConfig config,
  required _ContinuityDaemonConfig daemonConfig,
  required AgentInventoryPort inventory,
  required String controllerDid,
  required String controllerHandle,
}) async {
  final token = await inventory.issueDaemonToken(
    controllerDid: controllerDid,
    controllerHandle: controllerHandle,
    clientPlatform: Platform.operatingSystem,
  );
  final result = await Process.run(
    daemonConfig.binary,
    <String>[
      'install',
      '--token',
      token.token,
      '--base-url',
      config.baseUrl,
      '--no-service',
      '--print-json',
      '--state-root',
      daemonConfig.stateRoot,
    ],
    environment: _continuityDaemonEnvironment(config),
  ).timeout(const Duration(minutes: 2));
  if (result.exitCode != 0) {
    fail('The continuity daemon install command failed safely.');
  }
  final decoded = jsonDecode(result.stdout.toString());
  final daemonDid = decoded is Map
      ? decoded['daemon_agent_did']?.toString().trim() ?? ''
      : '';
  if (daemonDid.isEmpty) {
    fail('The continuity daemon install returned no daemon identity.');
  }
  return _ContinuityDaemonInstall(daemonDid: daemonDid);
}

Future<AgentSummary> _waitForAgent({
  required AgentInventoryPort inventory,
  required String description,
  required bool Function(AgentSummary agent) matches,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final agents = await inventory.listAgents(includeInactive: true);
    final selected = agents.whereType<AgentSummary>().where(matches).toList();
    if (selected.length > 1) fail('$description was duplicated.');
    if (selected.length == 1) return selected.single;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail('Timed out waiting for $description.');
}

Future<AgentSummary> _waitForFixtureAgent({
  required WidgetTester tester,
  required AgentInventoryPort inventory,
  required String expectedReference,
  required String description,
  required bool Function(AgentSummary agent) semanticMatch,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    final agents = (await inventory.listAgents(
      includeInactive: true,
    )).whereType<AgentSummary>().toList(growable: false);
    try {
      return requireHandleRecoveryReferenceExactOne<AgentSummary>(
        rawItems: agents,
        expectedReference: expectedReference,
        rawReference: (agent) => agent.agentDid,
        semanticMatch: semanticMatch,
      );
    } on HandleRecoveryOracleFailure catch (error) {
      if (error.code != 'fixture_reference_not_found') rethrow;
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
  }
  fail('Timed out waiting for $description by fixture reference.');
}

Future<GroupSummary> _waitForFixtureGroup({
  required WidgetTester tester,
  required ProviderContainer container,
  required String expectedReference,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await container.read(groupProvider.notifier).refresh();
    final groups = container.read(groupProvider).groups;
    try {
      return requireHandleRecoveryReferenceExactOne<GroupSummary>(
        rawItems: groups,
        expectedReference: expectedReference,
        rawReference: (group) => group.groupId,
      );
    } on HandleRecoveryOracleFailure catch (error) {
      if (error.code != 'fixture_reference_not_found') rethrow;
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
  }
  fail('Timed out waiting for the fixture Group reference.');
}

Future<ConversationSummary> _waitForFixtureConversation({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required ConversationService conversations,
  required String ownerDid,
  required String expectedReference,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'settings-recovery-fixture-reference',
      limit: 100,
    );
    final items = await conversations.listConversations(
      ownerDid: ownerDid,
      limit: 100,
    );
    try {
      return requireHandleRecoveryReferenceExactOne<ConversationSummary>(
        rawItems: items,
        expectedReference: expectedReference,
        rawReference: (conversation) => conversation.conversationId,
      );
    } on HandleRecoveryOracleFailure catch (error) {
      if (error.code != 'fixture_reference_not_found') rethrow;
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 550));
    }
  }
  fail('Timed out waiting for a fixture conversation reference.');
}

Future<AgentSummary> _waitForContinuityDaemonReady({
  required WidgetTester tester,
  required ProviderContainer container,
  required String daemonDid,
}) async {
  final controller = container.read(agentsProvider.notifier);
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    await controller.load();
    controller.select(daemonDid);
    await controller.refreshDaemonStatus(daemonDid);
    await tester.pump(const Duration(milliseconds: 250));
    final state = container.read(agentsProvider);
    final matches = state.agents
        .where((agent) => agent.isDaemon && agent.agentDid == daemonDid)
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The continuity daemon was duplicated.');
    }
    if (matches.length == 1 && state.canCreateRuntimeAgent(matches.single)) {
      return matches.single;
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
  }
  final state = container.read(agentsProvider);
  fail(
    'The continuity daemon did not become actionable '
    '(error=${_safeDiagnosticToken(state.error)}, '
    'debug=${_safeDiagnosticToken(state.debugLastError)}).',
  );
}

Future<void> _waitForRuntimeMessageSyncReady({
  required String daemonStateRoot,
  required String runtimeDid,
}) async {
  final daemonDbPath = '$daemonStateRoot/daemon.db';
  final coreDbPath = '$daemonStateRoot/im-core/local-state.sqlite';
  final deadline = DateTime.now().add(const Duration(seconds: 120));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final daemonDb = await databaseFactoryFfi.openDatabase(
        daemonDbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      String? ownerIdentityId;
      var completedSyncCount = 0;
      try {
        final identities = await daemonDb.query(
          'agent_device_identity',
          columns: const <String>['identity_id'],
          where: 'agent_did = ?',
          whereArgs: <Object?>[runtimeDid],
          limit: 2,
        );
        if (identities.length == 1) {
          ownerIdentityId = identities.single['identity_id']?.toString();
        }
        final completed = await daemonDb.rawQuery(
          '''
        SELECT COUNT(*) AS count
        FROM audit_log
        WHERE event_type = 'daemon.realtime.sync.completed'
          AND agent_did = ?
        ''',
          <Object?>[runtimeDid],
        );
        completedSyncCount = completed.single['count'] as int? ?? 0;
      } finally {
        await daemonDb.close();
      }
      if (ownerIdentityId != null && completedSyncCount > 0) {
        final coreDb = await databaseFactoryFfi.openDatabase(
          coreDbPath,
          options: OpenDatabaseOptions(readOnly: true),
        );
        try {
          final states = await coreDb.query(
            'message_sync_state',
            columns: const <String>['bootstrap_state', 'last_error_code'],
            where: 'owner_identity_id = ?',
            whereArgs: <Object?>[ownerIdentityId],
            limit: 2,
          );
          if (states.length == 1 &&
              states.single['bootstrap_state'] == 'active' &&
              states.single['last_error_code'] == null) {
            await Future<void>.delayed(const Duration(seconds: 2));
            return;
          }
        } finally {
          await coreDb.close();
        }
      }
    } on DatabaseException catch (error) {
      final code = error.getResultCode();
      if (code == null || (code & 0xff) != 5) rethrow;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The Runtime Agent did not establish reliable message sync.');
}

Future<AppConversationReadRef> _waitForRuntimeConversationRoute({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String runtimeDid,
}) async {
  final directory = bootstrap.directoryApplicationService;
  if (directory == null) {
    fail('Runtime Agent directory resolution was unavailable.');
  }
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final resolved = await directory.resolvePeer(runtimeDid);
      if (resolved.did == runtimeDid &&
          resolved.conversationId?.startsWith('dm:peer-scope:v1:') == true) {
        await Future<void>.delayed(const Duration(seconds: 2));
        return AppConversationReadRef.fromConversationId(
          resolved.conversationId!,
        );
      }
    } on Object {
      // Runtime identity publication is eventually consistent.
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  fail('The Runtime Agent did not publish one canonical Direct route.');
}

PlainDirectMessagingService _plainDirectMessaging(MessagingService messaging) {
  if (messaging is! PlainDirectMessagingService) {
    fail('AWikiMe does not expose the Runtime Agent default-plain send path.');
  }
  return messaging as PlainDirectMessagingService;
}

Future<File> _writeContinuityHermesGateway(
  _ContinuityDaemonConfig config,
) async {
  final script = File('${config.stateRoot}/recovery_fake_hermes_gateway.py');
  await script.parent.create(recursive: true);
  await script.writeAsString('''import json
import sys

print(json.dumps({"jsonrpc": "2.0", "method": "event", "params": {"type": "gateway.ready", "payload": {"version": "recovery-e2e"}}}), flush=True)
for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    if method == "session.create":
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"session_id": "recovery_e2e", "stored_session_id": "recovery_e2e"}}), flush=True)
    elif method == "session.resume":
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"session_id": "recovery_e2e", "stored_session_id": "recovery_e2e"}}), flush=True)
    elif method == "prompt.submit":
        params = request.get("params", {})
        prompt = str(params.get("text", ""))
        marker = "\\nuser_message:\\n"
        user_message = prompt.rsplit(marker, 1)[-1] if marker in prompt else prompt
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {"final_text": "$_agentReplyPrefix" + user_message}}), flush=True)
    else:
        print(json.dumps({"jsonrpc": "2.0", "id": request.get("id"), "error": {"message": "unknown method"}}), flush=True)
''', flush: true);
  return script;
}

Map<String, String> _continuityDaemonEnvironment(
  _RemoteRecoveryRunConfig config, {
  File? gatewayScript,
}) => <String, String>{
  'AWIKI_DAEMON_SERVICE_BASE_URL': config.baseUrl,
  'AWIKI_DAEMON_USER_SERVICE_BASE_URL': config.userServiceUrl,
  'AWIKI_DAEMON_MESSAGE_SERVICE_BASE_URL': config.messageServiceUrl,
  'AWIKI_DAEMON_DID_DOMAIN': config.didDomain,
  'AWIKI_DAEMON_ALLOW_PLAIN_CONTROL': '1',
  if (gatewayScript != null)
    'AWIKI_HERMES_GATEWAY_CMD': '/usr/bin/env python3 ${gatewayScript.path}',
};

class _RunningContinuityDaemon {
  _RunningContinuityDaemon._(
    this._process,
    this._stdoutSubscription,
    this._stderrSubscription,
  );

  final Process _process;
  final StreamSubscription<String> _stdoutSubscription;
  final StreamSubscription<String> _stderrSubscription;

  static Future<_RunningContinuityDaemon> start({
    required _RemoteRecoveryRunConfig config,
    required _ContinuityDaemonConfig daemonConfig,
    required File gatewayScript,
  }) async {
    final ready = File(daemonConfig.readyFile);
    if (ready.existsSync()) await ready.delete();
    final process = await Process.start(
      daemonConfig.binary,
      <String>[
        'foreground',
        '--state-root',
        daemonConfig.stateRoot,
        '--ready-file',
        daemonConfig.readyFile,
        '--max-runtime-ms',
        '1200000',
        '--poll-interval-ms',
        '100',
      ],
      environment: _continuityDaemonEnvironment(
        config,
        gatewayScript: gatewayScript,
      ),
      includeParentEnvironment: true,
      runInShell: false,
    );
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen((_) {}, onError: (_) {});
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen((_) {}, onError: (_) {});
    int? exitCode;
    unawaited(process.exitCode.then((value) => exitCode = value));
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!ready.existsSync() && DateTime.now().isBefore(deadline)) {
      if (exitCode != null) {
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
        fail('The continuity daemon exited before becoming ready.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!ready.existsSync()) {
      process.kill(ProcessSignal.sigkill);
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      fail('The continuity daemon did not become ready.');
    }
    return _RunningContinuityDaemon._(
      process,
      stdoutSubscription,
      stderrSubscription,
    );
  }

  Future<void> stop() async {
    if (!_process.kill(ProcessSignal.sigterm)) {
      _process.kill(ProcessSignal.sigkill);
    }
    try {
      await _process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _process.exitCode.timeout(const Duration(seconds: 5));
    } finally {
      await _stdoutSubscription.cancel();
      await _stderrSubscription.cancel();
    }
  }
}

Future<void> _runRecoveryCrashCutPhaseA(WidgetTester tester) async {
  final config = _RemoteRecoveryRunConfig.load();
  final account = _DedicatedAccount.fromConfig(config);
  final presence = E2eUserPresencePort();
  final continuityRequired = _invocationExpects(_settingsContinuityCaseId);
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  final daemonConfig = continuityRequired
      ? _requireContinuityDaemonConfig(config)
      : null;
  _requireIndependentFreshRoots(<String>[
    config.appStateRoot,
    if (continuityRequired) config.peerAppStateRoot,
    if (daemonConfig != null) daemonConfig.stateRoot,
  ]);

  final bootstrap = await AppBootstrap.create(
    environment: _environment(
      config,
      groupE2eeEnabled: false,
      agentImEnabled: true,
    ),
    appStateRoot: config.appStateRoot,
  );
  final onboardingSupport = bootstrap.onboardingSupportService;
  if (onboardingSupport == null || bootstrap.productLocalStore == null) {
    fail('The production Recovery crash-cut dependencies were unavailable.');
  }
  final bareHandle = _uniqueHandle('${config.handlePrefix}cut');
  final factor = await _requestAndResolveRegistrationOtp(
    onboardingSupport: onboardingSupport,
    config: config,
    account: account,
    handle: bareHandle,
  );
  final registration = await bootstrap.onboardingService!
      .registerHandleWithPhone(
        phone: account.phone,
        otp: factor.otp,
        handle: bareHandle,
        nickName: 'AWiki Recovery crash cut',
      );
  final oldSession = registration.identity;
  final oldBinding = oldSession?.accountBinding;
  if (registration.status != IdentityRegistrationStatus.registered ||
      oldSession == null ||
      oldBinding == null ||
      oldSession.handle == null) {
    fail('Crash-cut setup did not create one bound local identity.');
  }
  final activatedOldSession = await bootstrap.appSessionService!
      .loginWithIdentity(oldSession.identityId);
  if (!activatedOldSession.authenticated ||
      activatedOldSession.did != oldSession.did) {
    fail('Crash-cut setup did not activate its registered identity.');
  }
  final ownerRealtime = bootstrap.realtimeApplicationService;
  if (continuityRequired) {
    if (ownerRealtime == null) {
      fail('Crash-cut continuity owner realtime was unavailable.');
    }
    await ownerRealtime.start();
    if (!ownerRealtime.isRunning) {
      fail('Crash-cut continuity owner realtime did not start.');
    }
  }
  final productBinding = ProductAccountBinding.fromSession(oldBinding);
  final oldEpoch = ProductDeviceRegistryEpoch(
    currentDid: oldBinding.currentDid,
    bindingGeneration: oldBinding.identityGeneration,
  );
  final seededAt = DateTime.now().toUtc();
  await bootstrap.productLocalStore!.replaceProfileSnapshot(
    ProductProfileSnapshot(
      binding: productBinding,
      domainVersion: '1',
      refreshedAt: seededAt,
      payloadJson: '{"display_name":"stable-account-profile"}',
    ),
  );
  await bootstrap.productLocalStore!.replaceDeviceRegistrySnapshot(
    ProductDeviceRegistrySnapshot(
      binding: productBinding,
      epoch: oldEpoch,
      domainVersion: '1',
      refreshedAt: seededAt,
      devices: <ProductDeviceRegistryItem>[
        ProductDeviceRegistryItem(
          protocolDeviceId: oldBinding.protocolDeviceId,
          authGeneration: oldBinding.deviceAuthGeneration,
          payloadJson: '{"status":"active"}',
        ),
      ],
    ),
  );
  final recordingCore = _RecordingHandleRecoveryCorePort(
    bootstrap.handleRecoveryCorePort!,
  );
  await tester.pumpWidget(
    AwikiMeApp(
      bootstrap: bootstrap,
      providerOverrides: <Override>[
        userPresencePortProvider.overrideWithValue(presence),
        handleRecoveryCorePortProvider.overrideWithValue(recordingCore),
      ],
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byType(AppShell).evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'Crash-cut setup did not restore the old authenticated App.',
  );
  final appContainer = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  await _pumpUntil(
    tester,
    () =>
        appContainer.read(sessionProvider).session?.did == oldSession.did &&
        appContainer.read(appRuntimeProvider).activatedDid == oldSession.did,
    timeout: const Duration(seconds: 45),
    failure: 'Crash-cut setup did not activate the registered identity.',
    safeDiagnostic: () {
      final session = appContainer.read(sessionProvider).session;
      final runtime = appContainer.read(appRuntimeProvider);
      return 'session_present=${session != null}, '
          'session_is_registered=${session?.did == oldSession.did}, '
          'runtime_is_registered=${runtime.activatedDid == oldSession.did}, '
          'runtime_busy=${runtime.isBusy}';
    },
  );
  final fixtureProgress = HandleRecoveryFixtureProgress();
  final continuity = continuityRequired
      ? await runHandleRecoveryFixtureStage<_HandleRecoveryBusinessFixture>(
          caseId: _settingsContinuityCaseId,
          progress: fixtureProgress,
          action: () => _seedHandleRecoveryBusinessFixture(
            tester: tester,
            config: config,
            account: account,
            bootstrap: bootstrap,
            container: appContainer,
            inventory: appContainer.read(agentInventoryPortProvider),
            agentControl: appContainer.read(agentControlServiceProvider),
            conversations: appContainer.read(conversationServiceProvider),
            ownerSession: activatedOldSession,
            registrationRetryAt: factor.retryAt,
            daemonConfig: daemonConfig!,
            progress: fixtureProgress,
            kind: HandleRecoveryFixtureKind.localData,
          ),
          recordFailure: ({required caseId, required stage, required code}) =>
              E2eFailureObservationWriter.recordFirst(
                layer: 'app_projection',
                status: 'fatal',
                code: code,
                caseId: caseId,
              ),
        )
      : null;
  await _waitForRegistrationRetryBoundary(
    continuity?.registrationRetryAt ?? factor.retryAt,
  );
  appContainer
      .read(shellDestinationProvider.notifier)
      .select(ShellDestination.settings);
  await _pumpUntil(
    tester,
    () => find.byType(SettingsPage).evaluate().length == 1,
    failure: 'Crash-cut setup did not open Settings.',
  );
  final recoveryRow = find.byKey(const Key('settings-recover-handle-did-row'));
  await tester.ensureVisible(recoveryRow);
  await _tapOne(
    tester,
    recoveryRow,
    failure: 'Settings did not expose Handle DID Recovery.',
  );
  await _pumpUntil(
    tester,
    () => find.byType(HandleRecoveryPage).evaluate().length == 1,
    failure: 'Crash-cut setup did not open the visible Recovery surface.',
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HandleRecoveryPage)),
  );
  await _enterTextByKey(
    tester,
    const Key('handle-recovery-phone-input'),
    account.phone,
  );
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('handle-recovery-send-otp'),
    failure: 'Settings Recovery OTP action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () {
      final state = container.read(handleRecoveryProvider);
      _failOnRecoveryError(state, 'Crash-cut OTP request');
      return state.otpRequested &&
          state.otpOperationId != null &&
          !state.isBusy;
    },
    timeout: const Duration(seconds: 45),
    failure: 'Crash-cut Recovery did not request an operation-bound OTP.',
  );
  if (recordingCore.requestedLocalIdentityId != oldSession.identityId ||
      recordingCore.requestedHandle !=
          oldSession.handle!.trim().toLowerCase() ||
      recordingCore.requestedPhone != account.phone) {
    fail('Settings Recovery did not target the exact active local identity.');
  }
  final operationId = container.read(handleRecoveryProvider).otpOperationId!;
  final otp = await _resolveOtp(
    account: account,
    purpose: _recoveryPurpose,
    handle: bareHandle,
    didDomain: config.didDomain,
    operationId: operationId,
  );
  await _enterTextByKey(tester, const Key('handle-recovery-otp'), otp);
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('handle-recovery-verify'),
    failure: 'Crash-cut Recovery verification was unavailable.',
  );
  await _pumpUntil(
    tester,
    () {
      final state = container.read(handleRecoveryProvider);
      _failOnRecoveryError(state, 'Crash-cut prepare');
      return state.progress?.phase == HandleRecoveryProgressPhase.prepared &&
          !state.isBusy;
    },
    timeout: const Duration(minutes: 2),
    failure: 'Crash-cut Recovery did not reach prepared.',
  );
  await _tapOne(
    tester,
    find.byKey(const Key('handle-recovery-risk-confirmation')),
    failure: 'Crash-cut risk confirmation was unavailable.',
  );
  await _pumpUntil(
    tester,
    () => container.read(handleRecoveryProvider).riskConfirmed,
    failure: 'Crash-cut Recovery did not retain risk confirmation.',
  );
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('handle-recovery-activate'),
    failure: 'Crash-cut activation was unavailable.',
  );
  await _waitForCompletedRecovery(tester, container);
  final completed = container.read(handleRecoveryProvider).progress!;
  final reset = completed.registryEpochReset;
  if (reset == null ||
      reset.previousDid != oldSession.did ||
      reset.currentDid == oldSession.did ||
      reset.ownerIdentityId != oldBinding.ownerIdentityId ||
      reset.accountUserId != oldBinding.accountId ||
      reset.handle != oldSession.handle!.trim().toLowerCase() ||
      !_isSingleGenerationAdvance(
        oldBinding.identityGeneration,
        reset.bindingGeneration,
      ) ||
      presence.completions != 1) {
    fail('Crash-cut phase A did not stop after one committed Recovery.');
  }
  final preResetEpoch = await bootstrap.productLocalStore!
      .loadDeviceRegistryEpoch(binding: productBinding);
  final preResetSnapshot = await bootstrap.productLocalStore!
      .loadDeviceRegistrySnapshot(binding: productBinding);
  if (!(preResetEpoch?.matches(oldEpoch) ?? false) ||
      preResetSnapshot?.devices.length != 1 ||
      appContainer.read(sessionProvider).session != null ||
      appContainer.read(appRuntimeProvider).activatedDid != null) {
    fail(
      'Product state advanced or the old App session remained active before '
      'the deliberate crash cut.',
    );
  }
  final fixtureCheckpoint = continuity?.checkpoint(
    caseId: _settingsContinuityCaseId,
    runId: config.runId,
    stableOwnerIdentityId: oldBinding.ownerIdentityId,
  );
  final handoff = HandleRecoveryCrashCutHandoff.fromRaw(
    runId: config.runId,
    rawTransitionReferences: <String, String>{
      'owner_identity': oldBinding.ownerIdentityId,
      'account': oldBinding.accountId,
      'handle': oldSession.handle!.trim().toLowerCase(),
      'previous_identity': oldSession.did,
      'current_identity': reset.currentDid,
      'operation': operationId,
      'previous_generation': oldBinding.identityGeneration,
      'current_generation': reset.bindingGeneration,
    },
    expectedCounts: <String, int>{
      'local_identities': 1,
      'pre_reset_registry_devices': preResetSnapshot!.devices.length,
    },
    fixtureCheckpoint: fixtureCheckpoint,
  );
  await _writeCrashCutHandoff(config.crashCutHandoffPath, handoff);

  // Deliberately do not dispose [bootstrap]. Returning lets the Flutter test
  // process terminate with the Core commit durable and Product reset pending.
}

Future<void> _runRecoveryCrashCutPhaseB(WidgetTester tester) async {
  final config = _RemoteRecoveryRunConfig.load();
  final continuityRequired = _invocationExpects(_settingsContinuityCaseId);
  final daemonConfig = continuityRequired
      ? _requireContinuityDaemonConfig(config)
      : null;
  final handoffFile = File(config.crashCutHandoffPath);
  if (!handoffFile.existsSync()) {
    fail('Crash-cut phase B found no phase-A handoff.');
  }
  final decoded = jsonDecode(handoffFile.readAsStringSync());
  if (decoded is! Map) {
    fail('Crash-cut handoff was invalid.');
  }
  final handoff = HandleRecoveryCrashCutHandoff.fromJson(<String, Object?>{
    for (final entry in decoded.entries) entry.key.toString(): entry.value,
  });
  handoff.requireRunId(config.runId);
  final fixtureCheckpoint = handoff.fixtureCheckpoint;
  if (continuityRequired != (fixtureCheckpoint != null)) {
    fail('Crash-cut fixture checkpoint did not match the invoked case.');
  }

  final bootstrap = await AppBootstrap.create(
    environment: _environment(
      config,
      groupE2eeEnabled: continuityRequired ? false : null,
      agentImEnabled: continuityRequired ? true : null,
    ),
    appStateRoot: config.appStateRoot,
  );
  AppBootstrap? peerBootstrap;
  _RunningContinuityDaemon? daemon;
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() async {
    await daemon?.stop();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await peerBootstrap?.dispose();
    await bootstrap.dispose();
    await _deleteDirectory(config.appStateRoot);
    if (continuityRequired) {
      await _deleteDirectory(config.peerAppStateRoot);
      await _deleteDirectory(daemonConfig!.stateRoot);
    }
    if (handoffFile.existsSync()) await handoffFile.delete();
    await tester.binding.setSurfaceSize(null);
  });
  final preBootstrapIdentities = await bootstrap.appSessionService!
      .listLocalIdentities();
  final ownerIdentity = requireHandleRecoveryReferenceExactOne<AppSession>(
    rawItems: preBootstrapIdentities,
    expectedReference: handoff.transitionReferences['owner_identity']!,
    rawReference: (identity) => identity.identityId,
  );
  handoff.requireTransitionReference('current_identity', ownerIdentity.did);
  final handle = ownerIdentity.handle?.trim().toLowerCase() ?? '';
  handoff.requireTransitionReference('handle', handle);
  final operations = await bootstrap.handleRecoveryCorePort!.listOperations(
    HandleRecoveryOwner(
      localIdentityId: ownerIdentity.identityId,
      handle: handle,
    ),
  );
  final committedRecovery =
      requireHandleRecoveryReferenceExactOne<HandleRecoveryProgress>(
        rawItems: operations,
        expectedReference: handoff.transitionReferences['operation']!,
        rawReference: (operation) => operation.operationId,
      );
  final reset = committedRecovery.registryEpochReset;
  if (!committedRecovery.isCompleted || reset == null) {
    fail('Crash-cut phase B could not resolve the committed Recovery receipt.');
  }
  final binding = ProductAccountBinding(
    ownerIdentityId: reset.ownerIdentityId,
    accountId: reset.accountUserId,
  );
  final oldDid = reset.previousDid;
  final newDid = reset.currentDid;
  final newGeneration = reset.bindingGeneration;
  handoff.requireTransitionReference('owner_identity', reset.ownerIdentityId);
  handoff.requireTransitionReference('account', reset.accountUserId);
  handoff.requireTransitionReference('handle', reset.handle);
  handoff.requireTransitionReference('previous_identity', oldDid);
  handoff.requireTransitionReference('current_identity', newDid);
  handoff.requireTransitionReference('current_generation', newGeneration);
  final before = await bootstrap.productLocalStore!.loadDeviceRegistrySnapshot(
    binding: binding,
  );
  final oldGeneration = before?.epoch.bindingGeneration;
  if (before?.epoch.currentDid != oldDid || oldGeneration == null) {
    fail('Crash-cut phase B did not begin with the old Product epoch.');
  }
  handoff.requireTransitionReference('previous_generation', oldGeneration);
  requireHandleRecoveryGenerationAdvance(
    previous: oldGeneration,
    current: newGeneration,
  );
  if (preBootstrapIdentities.length !=
          handoff.expectedCounts['local_identities'] ||
      before!.devices.length !=
          handoff.expectedCounts['pre_reset_registry_devices']) {
    fail('Crash-cut phase B changed a pre-bootstrap expected count.');
  }

  await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
  late ProviderContainer appContainer;
  await _pumpUntil(
    tester,
    () {
      final shell = find.byType(AppShell);
      if (shell.evaluate().length != 1) return false;
      appContainer = ProviderScope.containerOf(tester.element(shell));
      return appContainer.read(sessionProvider).session?.did == newDid &&
          appContainer.read(appRuntimeProvider).activatedDid == newDid;
    },
    timeout: const Duration(seconds: 45),
    failure: 'Crash-cut phase B did not restore the replacement identity.',
  );
  final local = bootstrap.productLocalStore!;
  final session = await bootstrap.appSessionService!.currentSession();
  final accountBinding = session?.accountBinding;
  final epoch = await local.loadDeviceRegistryEpoch(binding: binding);
  final staleRegistry = await local.loadDeviceRegistrySnapshot(
    binding: binding,
  );
  final stableProfile = await local.loadProfileSnapshot(binding: binding);
  final localIdentities = await bootstrap.appSessionService!
      .listLocalIdentities();
  if (accountBinding == null ||
      epoch?.currentDid != newDid ||
      epoch?.bindingGeneration != accountBinding.identityGeneration ||
      staleRegistry != null ||
      stableProfile?.domainVersion != '1' ||
      localIdentities.any((identity) => identity.did == oldDid) ||
      appBootstrapEpochBarrierMetrics.snapshot()['ready'] != 1) {
    fail('Crash-cut bootstrap barrier did not converge exactly once.');
  }
  if (_invocationExpects(_crashCutCaseId)) {
    await E2eCaseAttestationWriter.markPassed(
      _crashCutCaseId,
      phases: const <String>[
        'phase_a_committed_with_old_product_epoch',
        'phase_a_old_runtime_quiesced_before_recovery_commit',
        'phase_a_process_terminated_before_product_reset',
        'phase_b_reopened_same_state_root',
        'bootstrap_barrier_reset_before_session_activation',
        'epoch_bound_registry_cleared_exactly_once',
        'stable_account_profile_preserved',
        'replacement_identity_visible_without_old_did',
      ],
    );
  }
  if (!continuityRequired) return;

  final checkpoint = fixtureCheckpoint!;

  if (session == null ||
      session.identityId != binding.ownerIdentityId ||
      session.handle?.trim().toLowerCase() != handle ||
      accountBinding.ownerIdentityId != binding.ownerIdentityId ||
      accountBinding.accountId != binding.accountId ||
      accountBinding.currentDid != newDid ||
      accountBinding.identityGeneration != newGeneration ||
      localIdentities.length != 1 ||
      localIdentities.single.identityId != binding.ownerIdentityId ||
      localIdentities.single.did != newDid) {
    fail('Settings Recovery did not preserve one exact Handle/account owner.');
  }

  peerBootstrap = await AppBootstrap.create(
    environment: _environment(
      config,
      groupE2eeEnabled: false,
      agentImEnabled: true,
    ),
    appStateRoot: config.peerAppStateRoot,
  );
  final peerIdentities = await peerBootstrap.appSessionService!
      .listLocalIdentities();
  final peerIdentity = requireHandleRecoveryReferenceExactOne<AppSession>(
    rawItems: peerIdentities,
    expectedReference: checkpoint.reference('direct_peer'),
    rawReference: (identity) => identity.did,
  );
  await _activatePeerIdentity(
    peerBootstrap,
    identityId: peerIdentity.identityId,
    expectedDid: peerIdentity.did,
  );
  final peerSession = await peerBootstrap.appSessionService!.currentSession();
  if (peerSession?.identityId != peerIdentity.identityId ||
      peerSession?.did != peerIdentity.did) {
    fail('The continuity peer did not reopen its exact identity.');
  }
  final peerDid = peerIdentity.did;

  final gatewayScript = await _writeContinuityHermesGateway(daemonConfig!);
  daemon = await _RunningContinuityDaemon.start(
    config: config,
    daemonConfig: daemonConfig,
    gatewayScript: gatewayScript,
  );
  final inventory = appContainer.read(agentInventoryPortProvider);
  final conversations = appContainer.read(conversationServiceProvider);
  final daemonAgent = await _waitForFixtureAgent(
    tester: tester,
    inventory: inventory,
    expectedReference: checkpoint.reference('daemon_agent'),
    description: 'reopened continuity daemon',
    semanticMatch: (agent) => agent.isDaemon,
  );
  final runtimeAgent = await _waitForFixtureAgent(
    tester: tester,
    inventory: inventory,
    expectedReference: checkpoint.reference('runtime_agent'),
    description: 'reopened continuity Runtime Agent',
    semanticMatch: (agent) =>
        agent.isRuntime && agent.daemonAgentDid == daemonAgent.agentDid,
  );
  final runtimeHandle = runtimeAgent.handle?.trim() ?? '';
  checkpoint.requireReference('runtime_handle', runtimeHandle);
  final recoveredGroup = await _waitForFixtureGroup(
    tester: tester,
    container: appContainer,
    expectedReference: checkpoint.reference('transport_group'),
  );
  checkpoint.requireReference(
    'group_conversation',
    recoveredGroup.conversationId,
  );
  final directConversation = await _waitForFixtureConversation(
    tester: tester,
    bootstrap: bootstrap,
    conversations: conversations,
    ownerDid: newDid,
    expectedReference: checkpoint.reference('direct_conversation'),
  );
  final agentConversation = await _waitForFixtureConversation(
    tester: tester,
    bootstrap: bootstrap,
    conversations: conversations,
    ownerDid: newDid,
    expectedReference: checkpoint.reference('agent_conversation'),
  );
  final peerDirectConversation = await _waitForFixtureConversation(
    tester: tester,
    bootstrap: peerBootstrap,
    conversations: peerBootstrap.conversationService!,
    ownerDid: peerDid,
    expectedReference: checkpoint.reference('peer_direct_conversation'),
  );
  final daemonDid = daemonAgent.agentDid;
  final runtimeDid = runtimeAgent.agentDid;
  final groupDid = recoveredGroup.groupId;
  final groupConversationId = recoveredGroup.conversationId;
  final directConversationId = directConversation.conversationId;
  final peerDirectConversationId = peerDirectConversation.conversationId;
  final agentConversationId = agentConversation.conversationId;
  await _waitForRecoveredContinuityGroup(
    tester: tester,
    container: appContainer,
    bootstrap: bootstrap,
    groupDid: groupDid,
    conversationId: groupConversationId,
    previousDid: oldDid,
    currentDid: newDid,
    peerDid: peerDid,
    checkpoint: checkpoint,
  );
  final recoveredGroupSnapshot = await bootstrap.groupApplicationService!
      .getGroup(groupDid);

  final groupConversation = await _waitForFixtureConversation(
    tester: tester,
    bootstrap: bootstrap,
    conversations: conversations,
    ownerDid: newDid,
    expectedReference: checkpoint.reference('group_conversation'),
  );
  if (directConversation.unreadCount != 0 ||
      groupConversation.unreadCount != 0) {
    fail('Local Data read state regressed after same-root restart.');
  }

  final recoveredConversationIds = await _waitForContinuityConversationIds(
    tester: tester,
    bootstrap: bootstrap,
    conversations: conversations,
    ownerDid: newDid,
    requiredIds: <String>{
      directConversationId,
      groupConversationId,
      agentConversationId,
    },
  );
  final recoveredAgents = await inventory.listAgents(includeInactive: true);
  final recoveredAgentDids =
      recoveredAgents.map((agent) => agent.agentDid).toList(growable: false)
        ..sort();
  checkpoint.requireReference(
    'conversation_inventory',
    jsonEncode(recoveredConversationIds),
  );
  checkpoint.requireReference(
    'agent_inventory',
    jsonEncode(recoveredAgentDids),
  );
  if (recoveredConversationIds.length !=
          checkpoint.expectedCount('conversations') ||
      recoveredAgentDids.length !=
          checkpoint.expectedCount('agent_inventory_items') ||
      recoveredAgentDids.where((did) => did == runtimeDid).length != 1) {
    fail('Recovery abnormally changed conversation or Agent inventory counts.');
  }

  final messaging = bootstrap.messagingService!;
  final groups = bootstrap.groupApplicationService!;
  final directHistory = await _loadConversationHistory(
    bootstrap,
    directConversationId,
  );
  final groupHistory = await groups.listMessages(groupDid, limit: 100);
  final agentHistory = await _loadConversationHistory(
    bootstrap,
    agentConversationId,
  );
  final recoveredGroupMembers = await groups.listMembers(groupDid, limit: 100);
  final recoveredGroupOwner = requireHandleRecoveryExactOne<GroupMemberSummary>(
    rawItems: recoveredGroupMembers.items,
    canonicalMatch: (member) => member.did == newDid,
    semanticMatch: (member) =>
        member.did == newDid &&
        member.membershipStatus == GroupMemberMembershipStatus.active,
  );
  final recoveredGroupPeer = requireHandleRecoveryExactOne<GroupMemberSummary>(
    rawItems: recoveredGroupMembers.items,
    canonicalMatch: (member) => member.did == peerDid,
    semanticMatch: (member) =>
        member.did == peerDid &&
        member.membershipStatus == GroupMemberMembershipStatus.active,
  );
  final directOutgoingBefore = _requireExactStoredMessageByReference(
    directHistory,
    checkpoint: checkpoint,
    messageReferenceName: 'direct_outgoing_message',
    semanticReferenceName: 'direct_outgoing_semantic',
    senderDid: oldDid,
    isMine: true,
    conversationId: directConversationId,
  );
  final directIncomingBefore = _requireExactStoredMessageByReference(
    directHistory,
    checkpoint: checkpoint,
    messageReferenceName: 'direct_incoming_message',
    semanticReferenceName: 'direct_incoming_semantic',
    senderDid: peerDid,
    isMine: false,
    conversationId: directConversationId,
  );
  final groupOutgoingBefore = _requireExactStoredMessageByReference(
    groupHistory,
    checkpoint: checkpoint,
    messageReferenceName: 'group_outgoing_message',
    semanticReferenceName: 'group_outgoing_semantic',
    senderDid: oldDid,
    isMine: true,
    conversationId: groupConversationId,
  );
  final groupIncomingBefore = _requireExactStoredMessageByReference(
    groupHistory,
    checkpoint: checkpoint,
    messageReferenceName: 'group_incoming_message',
    semanticReferenceName: 'group_incoming_semantic',
    senderDid: peerDid,
    isMine: false,
    conversationId: groupConversationId,
  );
  final agentPromptBefore = _requireExactStoredMessageByReference(
    agentHistory,
    checkpoint: checkpoint,
    messageReferenceName: 'agent_prompt_message',
    semanticReferenceName: 'agent_prompt_semantic',
    senderDid: oldDid,
    isMine: true,
    conversationId: agentConversationId,
  );
  final agentReplyBefore = _requireExactStoredMessageByReference(
    agentHistory,
    checkpoint: checkpoint,
    messageReferenceName: 'agent_reply_message',
    semanticReferenceName: 'agent_reply_semantic',
    senderDid: runtimeDid,
    isMine: false,
    conversationId: agentConversationId,
  );
  final observedCheckpoint = HandleRecoveryFixtureCheckpoint.fromRaw(
    caseId: _settingsContinuityCaseId,
    kind: HandleRecoveryFixtureKind.localData,
    stage: HandleRecoveryFixtureStage.checkpointReady,
    runId: config.runId,
    rawReferences: <String, String>{
      'admin_identity': binding.ownerIdentityId,
      'daemon_agent': daemonDid,
      'direct_peer': peerDid,
      'external_group_member': peerDid,
      'transport_group': groupDid,
      'runtime_agent': runtimeDid,
      'runtime_handle': runtimeHandle,
      'direct_conversation': directConversationId,
      'peer_direct_conversation': peerDirectConversationId,
      'direct_outgoing_message': _requiredMessageId(directOutgoingBefore),
      'direct_outgoing_semantic': directOutgoingBefore.content,
      'direct_incoming_message': _requiredMessageId(directIncomingBefore),
      'direct_incoming_semantic': directIncomingBefore.content,
      'direct_read_message': _requiredMessageId(directIncomingBefore),
      'group_conversation': groupConversationId,
      'group_display_name': recoveredGroupSnapshot.displayName,
      'group_description': recoveredGroupSnapshot.description,
      'group_role': _checkpointOptional(recoveredGroupSnapshot.myRole),
      'group_membership_status': _checkpointOptional(
        recoveredGroupSnapshot.membershipStatus,
      ),
      'group_owner_role': recoveredGroupOwner.role,
      'group_owner_membership_status':
          recoveredGroupOwner.membershipStatus.name,
      'group_peer_role': recoveredGroupPeer.role,
      'group_peer_membership_status': recoveredGroupPeer.membershipStatus.name,
      'group_outgoing_message': _requiredMessageId(groupOutgoingBefore),
      'group_outgoing_semantic': groupOutgoingBefore.content,
      'group_incoming_message': _requiredMessageId(groupIncomingBefore),
      'group_incoming_semantic': groupIncomingBefore.content,
      'group_read_message': _requiredMessageId(groupIncomingBefore),
      'agent_conversation': agentConversationId,
      'agent_prompt_message': _requiredMessageId(agentPromptBefore),
      'agent_prompt_semantic': agentPromptBefore.content,
      'agent_reply_message': _requiredMessageId(agentReplyBefore),
      'agent_reply_semantic': agentReplyBefore.content,
      'conversation_inventory': jsonEncode(recoveredConversationIds),
      'agent_inventory': jsonEncode(recoveredAgentDids),
    },
    expectedCounts: <String, int>{
      'admin_identities': localIdentities.length,
      'daemon_agents': recoveredAgents.where((agent) => agent.isDaemon).length,
      'direct_peers': peerSession == null ? 0 : 1,
      'external_group_members': recoveredGroupMembers.items
          .where((member) => member.did == peerDid)
          .length,
      'transport_groups': 1,
      'runtime_agents': recoveredAgents
          .where((agent) => agent.isRuntime)
          .length,
      'direct_messages': directHistory.length,
      'group_messages': groupHistory.length,
      'group_members': recoveredGroupMembers.items.length,
      'agent_messages': agentHistory.length,
      'agent_inventory_items': recoveredAgentDids.length,
      'conversations': recoveredConversationIds.length,
    },
  );
  observedCheckpoint.requireReplayOf(checkpoint);
  final directMessageCount = checkpoint.expectedCount('direct_messages');
  final groupMessageCount = checkpoint.expectedCount('group_messages');
  final agentMessageCount = checkpoint.expectedCount('agent_messages');
  if (directHistory.length != directMessageCount ||
      groupHistory.length != groupMessageCount ||
      agentHistory.length != agentMessageCount) {
    fail('Recovery changed a continuity thread message count.');
  }

  final directOutgoingAfter = await messaging.sendText(
    thread: AppThreadRef.direct(peerDid),
    content: 'direct-after-out ${config.runId} ${_nonce(8)}',
  );
  _requireCommittedDirect(
    directOutgoingAfter,
    senderDid: newDid,
    receiverDid: peerDid,
    isMine: true,
  );
  final peerOutgoingAfterProjection = await _syncAndWaitForAppThreadExactOne(
    tester: tester,
    appBootstrap: peerBootstrap,
    thread: AppThreadRef.direct(newDid),
    messageId: _requiredMessageId(directOutgoingAfter),
    content: directOutgoingAfter.content,
    senderDid: newDid,
    receiverDid: peerDid,
    isMine: false,
  );
  final directIncomingAfter = await peerBootstrap.messagingService!.sendText(
    thread: AppThreadRef.direct(newDid),
    content: 'direct-after-in ${config.runId} ${_nonce(8)}',
  );
  _requireCommittedDirect(
    directIncomingAfter,
    senderDid: peerDid,
    receiverDid: newDid,
    isMine: true,
  );
  if (_requiredConversationId(peerOutgoingAfterProjection) !=
      peerDirectConversationId) {
    fail('Recovery changed the peer-side Direct conversation ID.');
  }
  final ownerIncomingAfterProjection = await _syncAndWaitForAppThreadExactOne(
    tester: tester,
    appBootstrap: bootstrap,
    thread: AppThreadRef.direct(peerDid),
    messageId: _requiredMessageId(directIncomingAfter),
    content: directIncomingAfter.content,
    senderDid: peerDid,
    receiverDid: newDid,
    isMine: false,
  );
  if (_requiredConversationId(ownerIncomingAfterProjection) !=
      directConversationId) {
    fail('The peer did not continue the original Direct conversation.');
  }
  final peerDirectHistoryAfter = await _loadConversationHistory(
    peerBootstrap,
    peerDirectConversationId,
  );
  _requireExactMessage(
    peerDirectHistoryAfter,
    expected: directIncomingAfter,
    isMine: true,
    conversationId: peerDirectConversationId,
  );

  final groupOutgoingAfter = await messaging.sendText(
    thread: AppThreadRef.group(groupDid),
    content: 'group-after-out ${config.runId} ${_nonce(8)}',
  );
  _requireCommittedGroup(
    groupOutgoingAfter,
    groupDid: groupDid,
    senderDid: newDid,
    isMine: true,
    conversationId: groupConversationId,
  );
  await _waitForGroupMessageExactOne(
    tester: tester,
    bootstrap: peerBootstrap,
    groupDid: groupDid,
    messageId: _requiredMessageId(groupOutgoingAfter),
    content: groupOutgoingAfter.content,
    senderDid: newDid,
    isMine: false,
    conversationId: groupConversationId,
  );
  final groupIncomingAfter = await peerBootstrap.messagingService!.sendText(
    thread: AppThreadRef.group(groupDid),
    content: 'group-after-in ${config.runId} ${_nonce(8)}',
  );
  await _waitForGroupMessageExactOne(
    tester: tester,
    bootstrap: bootstrap,
    groupDid: groupDid,
    messageId: _requiredMessageId(groupIncomingAfter),
    content: groupIncomingAfter.content,
    senderDid: peerDid,
    isMine: false,
    conversationId: groupConversationId,
  );

  final submittedAgentPromptAfter = await _plainDirectMessaging(messaging)
      .sendPlainConversationText(
        conversation: AppConversationReadRef.fromConversationId(
          agentConversationId,
        ),
        content: 'agent-after ${config.runId} ${_nonce(8)}',
      );
  final agentPromptAfter = await _syncAndWaitForConversationExactOne(
    tester: tester,
    bootstrap: bootstrap,
    conversation: AppConversationReadRef.fromConversationId(
      agentConversationId,
    ),
    messageId: _requiredMessageId(submittedAgentPromptAfter),
    content: submittedAgentPromptAfter.content,
    senderDid: newDid,
    receiverDid: runtimeDid,
    isMine: true,
  );
  _requireCommittedDirect(
    agentPromptAfter,
    senderDid: newDid,
    receiverDid: runtimeDid,
    isMine: true,
  );
  final agentReplyAfter = await _waitForAgentReply(
    tester: tester,
    bootstrap: bootstrap,
    runtimeDid: runtimeDid,
    conversationId: agentConversationId,
    expectedContent: '$_agentReplyPrefix${agentPromptAfter.content}',
    existingMessageIds: agentHistory
        .map((message) => message.remoteId)
        .whereType<String>()
        .toSet(),
  );

  final finalDirectHistory = await _loadConversationHistory(
    bootstrap,
    directConversationId,
  );
  final finalGroupHistory = await groups.listMessages(groupDid, limit: 100);
  final finalAgentHistory = await _loadConversationHistory(
    bootstrap,
    agentConversationId,
  );
  _requireExactMessage(
    finalDirectHistory,
    expected: directOutgoingAfter,
    isMine: true,
    conversationId: directConversationId,
  );
  _requireExactMessage(
    finalDirectHistory,
    expected: directIncomingAfter,
    isMine: false,
    conversationId: directConversationId,
  );
  _requireExactMessage(
    finalGroupHistory,
    expected: groupOutgoingAfter,
    isMine: true,
    conversationId: groupConversationId,
  );
  _requireExactMessage(
    finalGroupHistory,
    expected: groupIncomingAfter,
    isMine: false,
    conversationId: groupConversationId,
  );
  _requireExactMessage(
    finalAgentHistory,
    expected: agentPromptAfter,
    isMine: true,
    conversationId: agentConversationId,
  );
  _requireExactMessage(
    finalAgentHistory,
    expected: agentReplyAfter,
    isMine: false,
    conversationId: agentConversationId,
  );
  final finalConversationIds = await _waitForContinuityConversationIds(
    tester: tester,
    bootstrap: bootstrap,
    conversations: conversations,
    ownerDid: newDid,
    requiredIds: recoveredConversationIds.toSet(),
  );
  final finalAgentDids = (await inventory.listAgents(
    includeInactive: true,
  )).map((agent) => agent.agentDid).toList(growable: false);
  final keyIds = <String>[
    _requiredMessageId(directOutgoingBefore),
    _requiredMessageId(directIncomingBefore),
    _requiredMessageId(groupOutgoingBefore),
    _requiredMessageId(groupIncomingBefore),
    _requiredMessageId(agentPromptBefore),
    _requiredMessageId(agentReplyBefore),
    _requiredMessageId(directOutgoingAfter),
    _requiredMessageId(directIncomingAfter),
    _requiredMessageId(groupOutgoingAfter),
    _requiredMessageId(groupIncomingAfter),
    _requiredMessageId(agentPromptAfter),
    _requiredMessageId(agentReplyAfter),
  ];
  if (finalDirectHistory.length != directMessageCount + 2 ||
      finalGroupHistory.length != groupMessageCount + 2 ||
      finalAgentHistory.length != agentMessageCount + 2 ||
      !_sameStrings(finalConversationIds, recoveredConversationIds) ||
      !_sameStrings(finalAgentDids, recoveredAgentDids) ||
      keyIds.toSet().length != keyIds.length) {
    fail('Post-Recovery continuity produced duplicate or abnormal growth.');
  }

  await E2eCaseAttestationWriter.markPassed(
    _settingsContinuityCaseId,
    phases: const <String>[
      'settings_recovery_preserved_handle_and_account',
      'did_generation_advanced_exactly_once',
      'same_root_restart_preserved_recovery_state',
      'direct_and_group_read_state_preserved_after_restart',
      'direct_id_history_ownership_and_bidirectional_send_preserved',
      'handle_backed_transport_group_id_history_and_send_preserved',
      'group_profile_role_status_count_and_members_preserved',
      'agent_inventory_conversation_history_and_reply_preserved',
      'conversation_message_and_agent_counts_remained_exact',
      'all_key_messages_converged_exactly_once',
    ],
  );
}

class _FreshFocusedEvidence {
  String? directConversationId;
  String? directInboundMessageId;
  String? directReplyMessageId;
  String? groupConversationId;
  String? groupInboundMessageId;
  String? groupReplyMessageId;
  String? agentConversationId;
  String? agentPromptMessageId;
  String? agentReplyMessageId;
}

Future<AccountStateSyncCoordinatorState> _requestFreshAccountState({
  required WidgetTester tester,
  required ProviderContainer container,
  required String reason,
}) async {
  final previous = container
      .read(accountStateSyncCoordinatorProvider)
      .lastCompletedAt;
  await container
      .read(accountStateSyncCoordinatorProvider.notifier)
      .request(reason, force: true);
  await _pumpUntil(
    tester,
    () {
      final state = container.read(accountStateSyncCoordinatorProvider);
      return !state.isSyncing &&
          state.pendingReason == null &&
          state.lastCompletedAt != null &&
          state.lastCompletedAt != previous;
    },
    timeout: const Duration(seconds: 45),
    failure: 'Fresh Recovery Account State did not quiesce.',
  );
  final state = container.read(accountStateSyncCoordinatorProvider);
  if (state.status != AccountStateSyncCoordinatorStatus.ready ||
      state.domainErrors.isNotEmpty ||
      state.domainVersions.length != ProductAccountDomain.values.length ||
      state.domainVersions.values.any(
        (version) => !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(version),
      )) {
    fail('Fresh Recovery Account State did not converge in all four domains.');
  }
  return state;
}

Future<void> _runFreshFocusedGates({
  required WidgetTester tester,
  required _RemoteRecoveryRunConfig config,
  required AppBootstrap bootstrap,
  required ProviderContainer container,
  required _FreshRecoveryFixtureSnapshot snapshot,
  required String oldDid,
  required String newDid,
  required DateTime startedAt,
  required Future<void> Function() startDaemon,
}) async {
  final evidence = _FreshFocusedEvidence();
  final failedCases = <String, String>{};
  final conversations = bootstrap.conversationService!;
  final preInbound = await conversations.listConversations(
    ownerDid: newDid,
    limit: 100,
  );
  if (preInbound.any(
    (conversation) => conversation.targetDid == snapshot.fixture.peerDid,
  )) {
    fail('Fresh Recovery restored an old ordinary Direct conversation.');
  }
  if (preInbound.any(
    (conversation) =>
        conversation.targetDid == snapshot.fixture.runtimeDid &&
        (conversation.lastMessageSnapshot != null ||
            conversation.lastMessagePreview.trim().isNotEmpty ||
            conversation.unreadCount != 0 ||
            conversation.unreadMentionCount != 0),
  )) {
    fail('Fresh Recovery restored old Agent message history.');
  }

  Future<void> runCase(
    String caseId,
    List<String> phases,
    Future<void> Function() action,
  ) async {
    if (!_invocationExpects(caseId)) return;
    try {
      await action();
      await _markFreshFocusedPassed(
        caseId,
        startedAt: startedAt,
        phases: phases,
      );
    } catch (error) {
      failedCases[caseId] = error.toString();
      await E2eCaseAttestationWriter.markFailed(
        caseId,
        startedAt: startedAt,
        phase: 'focused_gate_failed',
      );
    }
  }

  await startDaemon();
  await _waitForContinuityDaemonReady(
    tester: tester,
    container: container,
    daemonDid: snapshot.fixture.daemonDid,
  );
  await runCase(
    _freshAgentInventoryCaseId,
    const <String>[
      'fresh_root_had_no_old_local_identity_or_ordinary_conversation',
      'four_account_state_domains_converged_without_version_regression',
      'daemon_inventory_metadata_and_status_version_preserved_exactly_once',
      'runtime_inventory_metadata_and_parent_preserved_exactly_once',
      'registry_kept_only_the_replacement_identity',
    ],
    () async {
      final state = await _requestFreshAccountState(
        tester: tester,
        container: container,
        reason: 'fresh-agent-inventory',
      );
      requireHandleRecoveryAccountStateVersions(
        previous: <String, String>{
          for (final entry in snapshot.accountStateVersions.entries)
            entry.key.storageValue: entry.value,
        },
        current: <String, String>{
          for (final entry in state.domainVersions.entries)
            entry.key.storageValue: entry.value,
        },
        advancedDomains: const <String>{},
      );
      final inventory = container.read(agentInventoryPortProvider);
      final daemon = await _waitForFixtureAgent(
        tester: tester,
        inventory: inventory,
        expectedReference: snapshot.checkpoint.reference('daemon_agent'),
        description: 'Fresh Recovery Daemon Agent',
        semanticMatch: (agent) =>
            agent.isDaemon &&
            agent.handle == snapshot.daemon.handle &&
            agent.displayName == snapshot.daemon.displayName &&
            agent.activeState == snapshot.daemon.activeState &&
            agent.latest.version == snapshot.daemon.latest.version,
      );
      await _waitForFixtureAgent(
        tester: tester,
        inventory: inventory,
        expectedReference: snapshot.checkpoint.reference('runtime_agent'),
        description: 'Fresh Recovery Runtime Agent',
        semanticMatch: (agent) =>
            agent.isRuntime &&
            agent.handle == snapshot.runtime.handle &&
            agent.displayName == snapshot.runtime.displayName &&
            agent.activeState == snapshot.runtime.activeState &&
            agent.daemonAgentDid == daemon.agentDid,
      );
      final registry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(newDid);
      _requireReadyCurrentAdmin(registry, expectedDid: newDid);
      if ((await bootstrap.appSessionService!.listLocalIdentities()).any(
        (identity) => identity.did == oldDid,
      )) {
        fail('Fresh Recovery retained the previous DID locally.');
      }
    },
  );

  await runCase(
    _freshGroupRebindCaseId,
    const <String>[
      'group_identity_profile_role_status_and_count_preserved',
      'old_member_replaced_by_recovery_did_without_duplicate',
      'public_product_projection_rebind_converged_exactly_once',
    ],
    () async {
      final group = await _waitForFixtureGroup(
        tester: tester,
        container: container,
        expectedReference: snapshot.checkpoint.reference('transport_group'),
      );
      final members = await bootstrap.groupApplicationService!.listMembers(
        group.groupId,
        limit: 100,
      );
      final previousOwner = requireHandleRecoveryExactOne<GroupMemberSummary>(
        rawItems: snapshot.members,
        canonicalMatch: (member) => member.did == oldDid,
        semanticMatch: (member) => member.did == oldDid,
      );
      final recoveredOwner = requireHandleRecoveryExactOne<GroupMemberSummary>(
        rawItems: members.items,
        canonicalMatch: (member) => member.did == newDid,
        semanticMatch: (member) => member.did == newDid,
      );
      final previousPeer = requireHandleRecoveryExactOne<GroupMemberSummary>(
        rawItems: snapshot.members,
        canonicalMatch: (member) => member.did == snapshot.fixture.peerDid,
        semanticMatch: (member) => member.did == snapshot.fixture.peerDid,
      );
      final recoveredPeer = requireHandleRecoveryExactOne<GroupMemberSummary>(
        rawItems: members.items,
        canonicalMatch: (member) => member.did == snapshot.fixture.peerDid,
        semanticMatch: (member) => member.did == snapshot.fixture.peerDid,
      );
      if (group.conversationId != snapshot.group.conversationId ||
          group.displayName != snapshot.group.displayName ||
          group.description != snapshot.group.description ||
          group.avatarUri != snapshot.group.avatarUri ||
          group.myRole != snapshot.group.myRole ||
          group.membershipStatus != snapshot.group.membershipStatus ||
          group.memberCount != snapshot.group.memberCount ||
          members.items.length != snapshot.members.length ||
          members.items.where((member) => member.did == newDid).length != 1 ||
          members.items.any((member) => member.did == oldDid) ||
          members.items.map((member) => member.did).toSet().length !=
              members.items.length) {
        fail('Fresh Recovery Group rebind changed canonical metadata.');
      }
      _requireFreshGroupMemberMetadataPreserved(
        previous: previousOwner,
        current: recoveredOwner,
        allowDidReplacement: true,
      );
      _requireFreshGroupMemberMetadataPreserved(
        previous: previousPeer,
        current: recoveredPeer,
        allowDidReplacement: false,
      );
    },
  );

  final peerBootstrap = await AppBootstrap.create(
    environment: _environment(
      config,
      groupE2eeEnabled: false,
      agentImEnabled: true,
    ),
    appStateRoot: config.peerAppStateRoot,
  );
  try {
    final peerSession = await peerBootstrap.appSessionService!.restoreSession();
    if (peerSession == null || peerSession.did != snapshot.fixture.peerDid) {
      fail('Fresh Recovery external peer fixture was not preserved.');
    }
    final recoveredSession = await bootstrap.appSessionService!
        .currentSession();
    final recoveredHandle = recoveredSession?.handle?.trim().toLowerCase();
    if (recoveredHandle == null) {
      fail('Fresh Recovery current Handle was unavailable.');
    }
    final resolved = await peerBootstrap.directoryApplicationService!
        .lookupHandle(recoveredHandle);
    if (resolved.did != newDid || resolved.did == oldDid) {
      fail('The external peer did not re-resolve the Handle to the new DID.');
    }

    await runCase(
      _freshDirectInboundCaseId,
      const <String>[
        'external_peer_resolved_handle_to_replacement_did',
        'old_did_direct_send_was_fenced',
        'inbound_created_one_canonical_direct_without_manual_prerequisite',
        'preview_and_unread_rendered_before_open',
        'inbound_and_visible_ui_reply_converged_exactly_once',
      ],
      () async {
        final inbound = await peerBootstrap.messagingService!.sendText(
          thread: AppThreadRef.direct(resolved.did),
          content: 'fresh-direct-in ${config.runId} ${_nonce(8)}',
        );
        final projection = await _syncAndWaitForAppThreadExactOne(
          tester: tester,
          appBootstrap: bootstrap,
          thread: AppThreadRef.direct(peerSession.did),
          messageId: _requiredMessageId(inbound),
          content: inbound.content,
          senderDid: peerSession.did,
          receiverDid: newDid,
          isMine: false,
        );
        final conversation = await _waitForDirectConversation(
          tester: tester,
          bootstrap: bootstrap,
          ownerDid: newDid,
          peerDid: peerSession.did,
          content: inbound.content,
          unreadCount: 1,
        );
        final conversationId = conversation.conversationId;
        evidence
          ..directConversationId = conversationId
          ..directInboundMessageId = _requiredMessageId(projection);
        await _requireFreshInboundRowAndOpen(
          tester: tester,
          container: container,
          conversationId: conversationId,
          content: inbound.content,
        );
        final reply = await _sendFreshConversationReplyThroughUi(
          tester: tester,
          bootstrap: bootstrap,
          conversationId: conversationId,
          senderDid: newDid,
          receiverDid: peerSession.did,
          content: 'fresh-direct-out ${config.runId} ${_nonce(8)}',
        );
        evidence.directReplyMessageId = _requiredMessageId(reply);
        await _syncAndWaitForAppThreadExactOne(
          tester: tester,
          appBootstrap: peerBootstrap,
          thread: AppThreadRef.direct(newDid),
          messageId: _requiredMessageId(reply),
          content: reply.content,
          senderDid: newDid,
          receiverDid: peerSession.did,
          isMine: false,
        );
        var oldDidRejected = false;
        try {
          await peerBootstrap.messagingService!.sendText(
            thread: AppThreadRef.direct(oldDid),
            content: 'fresh-old-did-negative ${config.runId}',
          );
        } catch (_) {
          oldDidRejected = true;
        }
        if (!oldDidRejected) {
          fail('The external peer could still send to the old DID.');
        }
      },
    );

    await runCase(
      _freshGroupInboundCaseId,
      const <String>[
        'external_member_sent_after_rebind_without_local_group_history_copy',
        'group_conversation_group_did_and_wire_thread_remained_canonical',
        'preview_and_unread_rendered_before_open',
        'inbound_and_visible_ui_reply_converged_exactly_once',
      ],
      () async {
        final inbound = await peerBootstrap.messagingService!.sendText(
          thread: AppThreadRef.group(snapshot.fixture.groupDid),
          content: 'fresh-group-in ${config.runId} ${_nonce(8)}',
        );
        final projection = await _waitForGroupMessageExactOne(
          tester: tester,
          bootstrap: bootstrap,
          groupDid: snapshot.fixture.groupDid,
          messageId: _requiredMessageId(inbound),
          content: inbound.content,
          senderDid: peerSession.did,
          isMine: false,
          conversationId: snapshot.fixture.groupConversationId,
        );
        evidence
          ..groupConversationId = _requiredConversationId(projection)
          ..groupInboundMessageId = _requiredMessageId(projection);
        await _requireFreshInboundRowAndOpen(
          tester: tester,
          container: container,
          conversationId: snapshot.fixture.groupConversationId,
          content: inbound.content,
        );
        final reply = await _sendFreshConversationReplyThroughUi(
          tester: tester,
          bootstrap: bootstrap,
          conversationId: snapshot.fixture.groupConversationId,
          senderDid: newDid,
          groupDid: snapshot.fixture.groupDid,
          content: 'fresh-group-out ${config.runId} ${_nonce(8)}',
        );
        evidence.groupReplyMessageId = _requiredMessageId(reply);
        await _waitForGroupMessageExactOne(
          tester: tester,
          bootstrap: peerBootstrap,
          groupDid: snapshot.fixture.groupDid,
          messageId: _requiredMessageId(reply),
          content: reply.content,
          senderDid: newDid,
          isMine: false,
          conversationId: snapshot.fixture.groupConversationId,
        );
      },
    );

    await runCase(
      _freshAgentMessageCaseId,
      const <String>[
        'original_runtime_selected_from_visible_agents_ui',
        'prompt_sent_through_visible_composer_without_manual_conversation',
        'runtime_received_replacement_controller_and_replied',
        'prompt_and_reply_converged_exactly_once',
      ],
      () async {
        await container.read(agentsProvider.notifier).ensureLoaded();
        await _tapOne(
          tester,
          find.bySemanticsIdentifier('e2e-agents-tab'),
          failure: 'Fresh Recovery Agents tab was unavailable.',
        );
        await _pumpUntil(
          tester,
          () => find.byType(AgentsWorkspacePage).evaluate().length == 1,
          failure: 'Fresh Recovery Agents workspace did not open.',
        );
        final runtime = await _waitForFixtureAgent(
          tester: tester,
          inventory: container.read(agentInventoryPortProvider),
          expectedReference: snapshot.checkpoint.reference('runtime_agent'),
          description: 'Fresh Recovery Runtime Agent message target',
          semanticMatch: (agent) =>
              agent.isRuntime &&
              agent.daemonAgentDid == snapshot.fixture.daemonDid,
        );
        container.read(agentsProvider.notifier).select(runtime.agentDid);
        await tester.pump(const Duration(milliseconds: 200));
        await _tapOne(
          tester,
          find.text(
            tester.element(find.byType(AgentsWorkspacePage)).l10n.agentOpenChat,
          ),
          failure: 'Fresh Recovery Runtime Agent chat action was unavailable.',
        );
        final promptText = 'fresh-agent ${config.runId} ${_nonce(8)}';
        final input = find.bySemanticsIdentifier('e2e-chat-input');
        await _pumpUntil(
          tester,
          () => input.evaluate().length == 1,
          failure: 'Fresh Recovery Runtime Agent composer was unavailable.',
        );
        await tester.enterText(input, promptText);
        final send = find.bySemanticsIdentifier('e2e-chat-send-button');
        await _pumpUntil(
          tester,
          () => send.hitTestable().evaluate().length == 1,
          failure: 'Fresh Recovery Runtime Agent send action was unavailable.',
        );
        await _tapOne(
          tester,
          send,
          failure: 'Fresh Recovery Runtime Agent send action was unavailable.',
        );
        final prompt = await _waitForFreshSemanticMessage(
          tester: tester,
          bootstrap: bootstrap,
          ownerDid: newDid,
          targetDid: runtime.agentDid,
          content: promptText,
          senderDid: newDid,
          isMine: true,
        );
        final reply = await _waitForAgentReply(
          tester: tester,
          bootstrap: bootstrap,
          runtimeDid: runtime.agentDid,
          conversationId: _requiredConversationId(prompt),
          expectedContent: '$_agentReplyPrefix${prompt.content}',
          existingMessageIds: <String>{_requiredMessageId(prompt)},
        );
        evidence
          ..agentConversationId = _requiredConversationId(prompt)
          ..agentPromptMessageId = _requiredMessageId(prompt)
          ..agentReplyMessageId = _requiredMessageId(reply);
      },
    );
  } finally {
    await peerBootstrap.dispose();
  }

  if (_invocationExpects(_freshRestartCaseId)) {
    try {
      await _waitForFreshFocusedConversationsRead(
        tester: tester,
        bootstrap: bootstrap,
        evidence: evidence,
      );
      await _writeFreshRestartHandoff(
        config: config,
        snapshot: snapshot,
        newDid: newDid,
        evidence: evidence,
      );
    } catch (error) {
      failedCases[_freshRestartCaseId] = error.toString();
      await E2eCaseAttestationWriter.markFailed(
        _freshRestartCaseId,
        startedAt: startedAt,
        phase: 'restart_handoff_incomplete',
      );
    }
  }
  if (failedCases.isNotEmpty) {
    fail(
      'Fresh Recovery focused gates failed: '
      '${failedCases.entries.map((entry) => '${entry.key}: ${entry.value}').join('; ')}',
    );
  }
}

void _requireFreshGroupMemberMetadataPreserved({
  required GroupMemberSummary previous,
  required GroupMemberSummary current,
  required bool allowDidReplacement,
}) {
  final changed = <String>[
    if (!allowDidReplacement && current.did != previous.did) 'did',
    if (!allowDidReplacement && current.userId != previous.userId) 'userId',
    if (current.handle != previous.handle) 'handle',
    if (current.role != previous.role) 'role',
    if (current.membershipId != previous.membershipId) 'membershipId',
    if (current.peerPersonaId != previous.peerPersonaId) 'peerPersonaId',
    if (!allowDidReplacement && current.credentialDid != previous.credentialDid)
      'credentialDid',
    if (!allowDidReplacement && current.profileUrl != previous.profileUrl)
      'profileUrl',
    if (current.displayName != previous.displayName) 'displayName',
    if (current.avatarUri != previous.avatarUri) 'avatarUri',
    if (current.subjectType != previous.subjectType) 'subjectType',
    if (current.membershipStatus != previous.membershipStatus)
      'membershipStatus',
  ];
  if (changed.isNotEmpty) {
    fail(
      'Fresh Recovery changed public Group member metadata fields: '
      '${changed.join(', ')}.',
    );
  }
}

Future<void> _waitForFreshFocusedConversationsRead({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required _FreshFocusedEvidence evidence,
}) async {
  final expected = <String>{
    if (evidence.directConversationId != null) evidence.directConversationId!,
    if (evidence.groupConversationId != null) evidence.groupConversationId!,
    if (evidence.agentConversationId != null) evidence.agentConversationId!,
  };
  if (expected.length != 3) {
    throw const HandleRecoveryOracleFailure('restart_handoff_incomplete');
  }
  final conversations = bootstrap.conversationService!;
  final session = await bootstrap.appSessionService!.currentSession();
  if (session == null) {
    throw const HandleRecoveryOracleFailure('restart_handoff_incomplete');
  }
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await conversations.listConversations(
      ownerDid: session.did,
      limit: 100,
    );
    final focused = rows
        .where((conversation) => expected.contains(conversation.conversationId))
        .toList(growable: false);
    if (focused.length == expected.length &&
        focused.every((conversation) => conversation.unreadCount == 0)) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('Fresh Recovery focused conversations did not converge to read.');
}

Future<void> _markFreshFocusedPassed(
  String caseId, {
  required DateTime startedAt,
  required List<String> phases,
}) => switch (caseId) {
  _freshAgentInventoryCaseId => E2eCaseAttestationWriter.markPassed(
    _freshAgentInventoryCaseId,
    startedAt: startedAt,
    phases: phases,
  ),
  _freshAgentMessageCaseId => E2eCaseAttestationWriter.markPassed(
    _freshAgentMessageCaseId,
    startedAt: startedAt,
    phases: phases,
  ),
  _freshDirectInboundCaseId => E2eCaseAttestationWriter.markPassed(
    _freshDirectInboundCaseId,
    startedAt: startedAt,
    phases: phases,
  ),
  _freshGroupRebindCaseId => E2eCaseAttestationWriter.markPassed(
    _freshGroupRebindCaseId,
    startedAt: startedAt,
    phases: phases,
  ),
  _freshGroupInboundCaseId => E2eCaseAttestationWriter.markPassed(
    _freshGroupInboundCaseId,
    startedAt: startedAt,
    phases: phases,
  ),
  _ => throw StateError('Unsupported Fresh Recovery focused case.'),
};

Future<void> _requireFreshInboundRowAndOpen({
  required WidgetTester tester,
  required ProviderContainer container,
  required String conversationId,
  required String content,
}) async {
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-messages-tab'),
    failure: 'Fresh Recovery Messages tab was unavailable.',
  );
  await _pumpUntil(
    tester,
    () {
      final matches = container
          .read(conversationListProvider)
          .conversations
          .where((item) => item.conversationId == conversationId)
          .toList(growable: false);
      if (matches.length > 1) {
        fail('Fresh Recovery projected a duplicate conversation row.');
      }
      return matches.length == 1 &&
          matches.single.lastMessagePreview == content &&
          matches.single.unreadCount > 0 &&
          find
                  .byKey(Key('conversation-row:$conversationId'))
                  .evaluate()
                  .length ==
              1;
    },
    timeout: const Duration(seconds: 60),
    failure: 'Fresh Recovery inbound preview/unread did not converge.',
  );
  final row = find.byKey(Key('conversation-row:$conversationId'));
  final unread = find.descendant(
    of: row,
    matching: find.byKey(const Key('conversation-row-unread-badge')),
  );
  if (unread.evaluate().length != 1) {
    fail('Fresh Recovery inbound row did not render one unread badge.');
  }
  await _tapOne(
    tester,
    row,
    failure: 'Fresh Recovery exact inbound conversation did not open.',
  );
  await _pumpUntil(
    tester,
    () => find
        .bySemanticsIdentifier(e2eMessageIdentifier(content))
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 60),
    failure: 'Fresh Recovery inbound message was not visibly rendered.',
  );
}

Future<ChatMessage> _sendFreshConversationReplyThroughUi({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String conversationId,
  required String senderDid,
  String? receiverDid,
  String? groupDid,
  required String content,
}) async {
  final input = find.bySemanticsIdentifier('e2e-chat-input');
  await _pumpUntil(
    tester,
    () => input.evaluate().length == 1,
    failure: 'Fresh Recovery conversation composer was unavailable.',
  );
  await tester.enterText(input, content);
  final send = find.bySemanticsIdentifier('e2e-chat-send-button');
  await _pumpUntil(
    tester,
    () => send.hitTestable().evaluate().length == 1,
    failure: 'Fresh Recovery visible reply action was unavailable.',
  );
  await _tapOne(
    tester,
    send,
    failure: 'Fresh Recovery visible reply action was unavailable.',
  );
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'fresh-recovery-visible-reply',
      limit: 100,
    );
    final history = await _loadConversationHistory(bootstrap, conversationId);
    final matches = history
        .where(
          (message) =>
              message.content == content &&
              message.senderDid == senderDid &&
              message.isMine &&
              (receiverDid == null || message.receiverDid == receiverDid) &&
              (groupDid == null || message.groupId == groupDid),
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('Fresh Recovery visible reply was duplicated.');
    }
    if (matches.length == 1 &&
        matches.single.sendState == MessageSendState.sent) {
      return matches.single;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('Fresh Recovery visible reply did not commit exactly once.');
}

Future<ChatMessage> _waitForFreshSemanticMessage({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String ownerDid,
  required String targetDid,
  required String content,
  required String senderDid,
  required bool isMine,
}) async {
  final conversations = bootstrap.conversationService!;
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await bootstrap.messageSyncService!.syncNow(
      reason: 'fresh-recovery-agent-message',
      limit: 100,
    );
    final candidates = (await conversations.listConversations(
      ownerDid: ownerDid,
      limit: 100,
    )).where((item) => item.targetDid == targetDid).toList(growable: false);
    if (candidates.length > 1) {
      fail('Fresh Recovery created duplicate Agent conversations.');
    }
    if (candidates.length == 1) {
      final history = await _loadConversationHistory(
        bootstrap,
        candidates.single.conversationId,
      );
      final matches = history
          .where(
            (message) =>
                message.content == content &&
                message.senderDid == senderDid &&
                message.isMine == isMine,
          )
          .toList(growable: false);
      if (matches.length > 1) {
        fail('Fresh Recovery Agent semantic message was duplicated.');
      }
      if (matches.length == 1) return matches.single;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('Fresh Recovery Agent message did not converge.');
}

Future<void> _writeFreshRestartHandoff({
  required _RemoteRecoveryRunConfig config,
  required _FreshRecoveryFixtureSnapshot snapshot,
  required String newDid,
  required _FreshFocusedEvidence evidence,
}) async {
  final rawReferences = <String, String?>{
    'current_identity': newDid,
    'daemon_agent': snapshot.fixture.daemonDid,
    'runtime_agent': snapshot.fixture.runtimeDid,
    'transport_group': snapshot.fixture.groupDid,
    'direct_conversation': evidence.directConversationId,
    'direct_inbound_message': evidence.directInboundMessageId,
    'direct_reply_message': evidence.directReplyMessageId,
    'group_conversation': evidence.groupConversationId,
    'group_inbound_message': evidence.groupInboundMessageId,
    'group_reply_message': evidence.groupReplyMessageId,
    'agent_conversation': evidence.agentConversationId,
    'agent_prompt_message': evidence.agentPromptMessageId,
    'agent_reply_message': evidence.agentReplyMessageId,
  };
  if (rawReferences.values.any((value) => value?.trim().isEmpty != false)) {
    throw const HandleRecoveryOracleFailure('restart_handoff_incomplete');
  }
  final payload = <String, Object?>{
    'schemaVersion': 1,
    'stage': 'fresh_business_ready',
    'runRef': handleRecoveryFixtureReference(config.runId),
    'references': <String, String>{
      for (final entry in rawReferences.entries)
        entry.key: handleRecoveryFixtureReference(entry.value!),
    },
    'expectedCounts': <String, int>{
      'local_identities': 1,
      'focused_conversations': 3,
      'fixture_agents': snapshot.fixture.agentDids.length,
    },
  };
  final file = File(config.crashCutHandoffPath);
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(payload), flush: true);
  await temporary.rename(file.path);
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['600', file.path]);
  }
}

Future<void> _runFreshRecoveryRestart(WidgetTester tester) async {
  final startedAt = DateTime.now().toUtc();
  final config = _RemoteRecoveryRunConfig.load();
  final handoffFile = File(config.crashCutHandoffPath);
  if (!handoffFile.existsSync()) {
    await E2eCaseAttestationWriter.markFailed(
      _freshRestartCaseId,
      startedAt: startedAt,
      phase: 'restart_handoff_missing',
    );
    fail('Fresh Recovery restart handoff was missing.');
  }
  final decoded = jsonDecode(handoffFile.readAsStringSync());
  if (decoded is! Map ||
      decoded['schemaVersion'] != 1 ||
      decoded['stage'] != 'fresh_business_ready' ||
      decoded['runRef'] != handleRecoveryFixtureReference(config.runId)) {
    fail('Fresh Recovery restart handoff was invalid.');
  }
  final references = _freshStringMap(decoded, 'references');
  final expectedCounts = _freshIntMap(decoded, 'expectedCounts');
  const expectedReferenceNames = <String>{
    'current_identity',
    'daemon_agent',
    'runtime_agent',
    'transport_group',
    'direct_conversation',
    'direct_inbound_message',
    'direct_reply_message',
    'group_conversation',
    'group_inbound_message',
    'group_reply_message',
    'agent_conversation',
    'agent_prompt_message',
    'agent_reply_message',
  };
  if (!_sameStrings(references.keys, expectedReferenceNames) ||
      !_sameStrings(expectedCounts.keys, const <String>{
        'local_identities',
        'focused_conversations',
        'fixture_agents',
      })) {
    fail('Fresh Recovery restart handoff shape was not exact.');
  }
  final bootstrap = await AppBootstrap.create(
    environment: _environment(
      config,
      groupE2eeEnabled: false,
      agentImEnabled: true,
    ),
    appStateRoot: config.appStateRoot,
  );
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap.dispose();
    await _deleteDirectory(config.appStateRoot);
    await _deleteDirectory(config.peerAppStateRoot);
    if (config.daemonStateRoot != null) {
      await _deleteDirectory(config.daemonStateRoot!);
    }
    if (handoffFile.existsSync()) await handoffFile.delete();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
  late ProviderContainer container;
  await _pumpUntil(
    tester,
    () {
      final shell = find.byType(AppShell);
      if (shell.evaluate().length != 1) return false;
      container = ProviderScope.containerOf(tester.element(shell));
      final session = container.read(sessionProvider).session;
      return session != null &&
          handleRecoveryFixtureReference(session.did) ==
              references['current_identity'];
    },
    timeout: const Duration(seconds: 60),
    failure: 'Fresh Recovery cold restart did not restore current identity.',
  );
  final state = await _requestFreshAccountState(
    tester: tester,
    container: container,
    reason: 'fresh-recovery-cold-restart',
  );
  if (state.domainVersions.length != ProductAccountDomain.values.length) {
    fail('Fresh Recovery restart lost an Account State domain.');
  }
  final session = await bootstrap.appSessionService!.currentSession();
  final identities = await bootstrap.appSessionService!.listLocalIdentities();
  if (session == null ||
      identities.length != expectedCounts['local_identities'] ||
      identities.where((item) => item.did == session.did).length != 1) {
    fail('Fresh Recovery restart local identity inventory was not exact.');
  }
  final conversations = await bootstrap.conversationService!.listConversations(
    ownerDid: session.did,
    limit: 100,
  );
  final focusedConversationRefs = <String>{
    references['direct_conversation']!,
    references['group_conversation']!,
    references['agent_conversation']!,
  };
  final focused = conversations
      .where(
        (item) => focusedConversationRefs.contains(
          handleRecoveryFixtureReference(item.conversationId),
        ),
      )
      .toList(growable: false);
  if (focused.length != expectedCounts['focused_conversations'] ||
      focused.map((item) => item.conversationId).toSet().length !=
          focused.length ||
      focused.any((item) => item.unreadCount != 0)) {
    fail('Fresh Recovery restart duplicated a conversation or regressed read.');
  }
  final expectedMessageRefs = <String>{
    references['direct_inbound_message']!,
    references['direct_reply_message']!,
    references['group_inbound_message']!,
    references['group_reply_message']!,
    references['agent_prompt_message']!,
    references['agent_reply_message']!,
  };
  final observedMessageRefs = <String>[];
  for (final conversation in focused) {
    final history = await _loadConversationHistory(
      bootstrap,
      conversation.conversationId,
    );
    observedMessageRefs.addAll(
      history.map(
        (message) =>
            handleRecoveryFixtureReference(_requiredMessageId(message)),
      ),
    );
  }
  for (final expected in expectedMessageRefs) {
    if (observedMessageRefs.where((value) => value == expected).length != 1) {
      fail('Fresh Recovery restart did not preserve a key message exact-one.');
    }
  }
  final agents = await container
      .read(agentInventoryPortProvider)
      .listAgents(includeInactive: true);
  if (agents.length != expectedCounts['fixture_agents'] ||
      agents.map((agent) => agent.agentDid).toSet().length != agents.length) {
    fail('Fresh Recovery restart changed Agent inventory cardinality.');
  }
  for (final key in const <String>['daemon_agent', 'runtime_agent']) {
    if (agents
            .where(
              (agent) =>
                  handleRecoveryFixtureReference(agent.agentDid) ==
                  references[key],
            )
            .length !=
        1) {
      fail('Fresh Recovery restart lost a fixture Agent exact-one.');
    }
  }
  final groups = bootstrap.groupApplicationService!;
  final groupCandidates = await groups.listGroups(limit: 100);
  if (groupCandidates.items
          .where(
            (group) =>
                handleRecoveryFixtureReference(group.groupId) ==
                references['transport_group'],
          )
          .length !=
      1) {
    fail('Fresh Recovery restart lost the canonical Group exact-one.');
  }
  final registry = await bootstrap.deviceManagementCorePort!
      .identityDeviceRegistry(session.did);
  _requireReadyCurrentAdmin(registry, expectedDid: session.did);
  await E2eCaseAttestationWriter.markPassed(
    _freshRestartCaseId,
    startedAt: startedAt,
    phases: const <String>[
      'same_fresh_recovery_root_reopened_in_new_flutter_process',
      'current_identity_and_four_account_state_domains_persisted',
      'direct_group_and_agent_conversations_remained_exactly_once',
      'six_post_recovery_messages_remained_exactly_once',
      'read_state_did_not_regress',
      'group_agent_inventory_and_registry_did_not_duplicate_or_revert',
    ],
  );
}

Map<String, String> _freshStringMap(Map<dynamic, dynamic> root, String key) {
  final value = root[key];
  if (value is! Map ||
      value.keys.any((item) => item is! String) ||
      value.values.any((item) => item is! String)) {
    throw FormatException('$key must be a string map');
  }
  return <String, String>{
    for (final entry in value.entries)
      entry.key.toString(): entry.value.toString(),
  };
}

Map<String, int> _freshIntMap(Map<dynamic, dynamic> root, String key) {
  final value = root[key];
  if (value is! Map ||
      value.keys.any((item) => item is! String) ||
      value.values.any((item) => item is! int)) {
    throw FormatException('$key must be an integer map');
  }
  return <String, int>{
    for (final entry in value.entries) entry.key.toString(): entry.value as int,
  };
}

Future<void> _writeCrashCutHandoff(
  String path,
  HandleRecoveryCrashCutHandoff handoff,
) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final temporary = File('$path.tmp');
  await temporary.writeAsString(jsonEncode(handoff.toJson()), flush: true);
  await temporary.rename(path);
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['600', path]);
  }
}

Future<void> _waitForCompletedRecovery(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final initial = container.read(handleRecoveryProvider);
  if (initial.progress?.canActivate ?? false) {
    await _pumpUntil(
      tester,
      () {
        final state = container.read(handleRecoveryProvider);
        return state.isBusy ||
            state.error != null ||
            !(state.progress?.canActivate ?? false);
      },
      timeout: const Duration(minutes: 1),
      failure: 'Recovery activation did not start after the visible action.',
    );
  }
  for (var attempt = 0; attempt < 8; attempt += 1) {
    await _pumpUntil(
      tester,
      () => !container.read(handleRecoveryProvider).isBusy,
      timeout: const Duration(minutes: 2),
      failure: 'A Recovery transition did not return control to the UI.',
    );
    final state = container.read(handleRecoveryProvider);
    final progress = state.progress;
    if (progress?.isCompleted ?? false) return;
    final error = state.error;
    if (error != null &&
        !(error.action == HandleRecoveryUiAction.exactResume &&
            (progress?.canResume ?? false))) {
      _failOnRecoveryError(state, 'Recovery activation/resume');
    }
    if (progress == null || !progress.canResume) {
      fail(
        'Recovery stopped in a non-resumable non-terminal phase '
        '(phase=${progress?.phase.name ?? 'absent'}, '
        'lifecycle=${progress?.lifecycleClass.name ?? 'absent'}, '
        'commitAttempted=${progress?.commitAttempted ?? false}, '
        'keyState=${progress?.keyState.name ?? 'absent'}, '
        'error=${error?.safeCode ?? 'absent'}).',
      );
    }
    await _tapOne(
      tester,
      find.bySemanticsIdentifier('handle-recovery-resume'),
      failure: 'The exact Recovery resume action was unavailable.',
    );
  }
  fail('Recovery exceeded the bounded UI resume budget.');
}

void _failOnRecoveryError(
  HandleRecoveryState state,
  String action, {
  String? coreDiagnostic,
}) {
  final error = state.error;
  if (error != null) {
    final diagnostic = coreDiagnostic == null
        ? ''
        : ' Core diagnostic: $coreDiagnostic.';
    fail('$action failed with safe error ${error.safeCode}.$diagnostic');
  }
}

void _failOnDangerousUiFeedback(
  ProviderContainer container,
  String action, {
  int? existingEventId,
}) {
  final feedback = container.read(uiFeedbackProvider);
  if (feedback?.id == existingEventId) return;
  if (feedback?.danger ?? false) {
    fail(
      '$action failed with safe UI message '
      '${_safeDiagnosticToken(feedback!.message.id)}.',
    );
  }
}

class _RecordingHandleRecoveryCorePort implements HandleRecoveryCorePort {
  _RecordingHandleRecoveryCorePort(this._delegate);

  final HandleRecoveryCorePort _delegate;
  String? lastSafeFailure;
  int requestOtpCalls = 0;
  String? requestedHandle;
  String? requestedPhone;
  String? requestedLocalIdentityId;
  DateTime? requestedRetryAt;

  Future<T> _record<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      lastSafeFailure = switch (error) {
        core.AwikiImCoreException() => [
          'code=${_safeDiagnosticToken(error.code)}',
          'status=${error.statusCode?.toString() ?? 'none'}',
          'service=${_safeDiagnosticToken(error.serviceCode)}',
        ].join(','),
        HandleRecoveryFailure() => 'failure=${error.code.name}',
        _ when error.runtimeType.toString() == 'PanicException' =>
          _safePanicDiagnostic(error),
        _ => 'type=${_safeDiagnosticToken(error.runtimeType.toString())}',
      };
      rethrow;
    }
  }

  String _safePanicDiagnostic(Object error) {
    var value = error.toString();
    for (final secret in <String?>[requestedPhone, requestedHandle]) {
      final normalized = secret?.trim() ?? '';
      if (normalized.isNotEmpty) {
        value = value.replaceAll(normalized, '<redacted>');
      }
    }
    value = value
        .replaceAll(RegExp(r'did:[^\s,)]+'), '<did>')
        .replaceAll(RegExp(r'join-[A-Za-z0-9_-]+'), '<join>')
        .replaceAll(RegExp(r'recover[_-][A-Za-z0-9_-]+'), '<operation>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.length > 300) value = value.substring(0, 300);
    return 'panic=$value';
  }

  @override
  Future<HandleRecoveryOtpResult> requestOtp({
    required String handle,
    required String phone,
    String? localIdentityId,
  }) async {
    requestOtpCalls += 1;
    requestedHandle = handle;
    requestedPhone = phone;
    requestedLocalIdentityId = localIdentityId;
    final result = await _record(
      () => _delegate.requestOtp(
        handle: handle,
        phone: phone,
        localIdentityId: localIdentityId,
      ),
    );
    requestedRetryAt = result.retryAt;
    return result;
  }

  @override
  Future<HandleRecoveryProgress> prepare({
    required String operationId,
    required String phone,
    required String otp,
  }) => _record(
    () => _delegate.prepare(operationId: operationId, phone: phone, otp: otp),
  );

  @override
  Future<List<HandleRecoveryProgress>> listOperations(
    HandleRecoveryOwner owner,
  ) => _record(() => _delegate.listOperations(owner));

  @override
  Future<HandleRecoveryProgress> getStatus(String operationId) =>
      _record(() => _delegate.getStatus(operationId));

  @override
  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required bool userPresenceConfirmed,
  }) => _record(
    () => _delegate.activate(
      operationId: operationId,
      userPresenceConfirmed: userPresenceConfirmed,
    ),
  );

  @override
  Future<HandleRecoveryProgress> reconcile(String operationId) =>
      _record(() => _delegate.reconcile(operationId));

  @override
  Future<void> discardPreAttempt(String operationId) =>
      _record(() => _delegate.discardPreAttempt(operationId));

  @override
  Future<HandleRecoveryProgress> quarantineKeyUnavailable({
    required String operationId,
    required bool confirmed,
  }) => _record(
    () => _delegate.quarantineKeyUnavailable(
      operationId: operationId,
      confirmed: confirmed,
    ),
  );

  @override
  Future<HandleRecoveryRegistryEpochReset?> authorizedEpochReceipt(
    HandleRecoveryOwner owner,
  ) => _record(() => _delegate.authorizedEpochReceipt(owner));

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> activateAuthorizedJoin({
    required HandleRecoveryIdentityScope scope,
    required String phone,
    required String otp,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required bool userPresenceConfirmed,
  }) => _record(
    () => _delegate.activateAuthorizedJoin(
      scope: scope,
      phone: phone,
      otp: otp,
      handle: handle,
      did: did,
      operationId: operationId,
      ttlSeconds: ttlSeconds,
      userPresenceConfirmed: userPresenceConfirmed,
    ),
  );

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> resumeAuthorizedJoinActivation({
    required String joinSessionId,
  }) => _record(
    () =>
        _delegate.resumeAuthorizedJoinActivation(joinSessionId: joinSessionId),
  );
}

String _safeDiagnosticToken(String? value) {
  final normalized = value?.trim() ?? '';
  return RegExp(r'^[A-Za-z0-9_.-]{1,96}$').hasMatch(normalized)
      ? normalized
      : 'none';
}

List<String> _receiptMismatchFields(
  HandleRecoveryRegistryEpochReset receipt, {
  required AppSession identity,
  required SessionAccountBinding binding,
}) {
  final mismatches = <String>[];
  final handle = identity.handle?.trim().toLowerCase();
  void check(bool matches, String field) {
    if (!matches) mismatches.add(field);
  }

  check(receipt.receiptSchemaVersion == '1', 'receipt_schema_version');
  check(receipt.accountUserId == binding.accountId, 'account_user_id');
  check(receipt.ownerIdentityId == binding.ownerIdentityId, 'binding_owner');
  check(receipt.ownerIdentityId == identity.identityId, 'identity_owner');
  check(receipt.handle == handle, 'handle');
  check(receipt.currentDid == binding.currentDid, 'current_did');
  check(
    receipt.bindingGeneration == binding.identityGeneration,
    'binding_generation',
  );
  check(
    RegExp(r'^[1-9][0-9]*$').hasMatch(receipt.bindingGeneration),
    'binding_generation_format',
  );
  check(receipt.currentDeviceId == binding.protocolDeviceId, 'device_id');
  check(
    receipt.deviceAuthGeneration.toString() == binding.deviceAuthGeneration,
    'device_auth_generation',
  );
  check(receipt.previousDid != receipt.currentDid, 'previous_did');
  check(receipt.deviceAuthGeneration > 0, 'device_auth_generation_format');
  check(receipt.registryVersion > 0, 'registry_version');
  check(
    RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(receipt.stateRootFingerprint),
    'state_root_fingerprint',
  );
  check(receipt.appliedAt.isUtc, 'applied_at_timezone');
  check(
    receipt.appliedAt.millisecond == 0 && receipt.appliedAt.microsecond == 0,
    'applied_at_precision',
  );
  check(receipt.metadataJson == '{}', 'metadata_json');
  check(
    receipt.sourceId.isNotEmpty && receipt.sourceId.trim() == receipt.sourceId,
    'source_id',
  );
  return mismatches;
}

void _requireReadyCurrentAdmin(
  DeviceRegistrySnapshot registry, {
  required String expectedDid,
}) {
  final active = registry.devices
      .where((device) => device.status == DeviceStatus.active)
      .toList(growable: false);
  final current = active.where((device) => device.isCurrent).toList();
  if (registry.did != expectedDid ||
      active.length != 1 ||
      current.length != 1 ||
      current.single.role != DeviceRole.admin ||
      !current.single.managementReady) {
    fail('The identity did not have one ready current admin device.');
  }
}

AwikiEnvironmentConfig _environment(
  _RemoteRecoveryRunConfig config, {
  bool? directE2eeEnabled,
  bool? groupE2eeEnabled,
  bool? agentImEnabled,
}) {
  return AwikiEnvironmentConfig(
    baseUrl: config.baseUrl,
    userServiceUrl: config.userServiceUrl,
    messageServiceUrl: config.messageServiceUrl,
    mailServiceUrl: config.mailServiceUrl,
    didDomain: config.didDomain,
    anpServiceUrl: config.anpServiceUrl,
    anpServiceDid: config.anpServiceDid,
    multiDeviceDirectE2eeEnabled: directE2eeEnabled,
    multiDeviceGroupE2eeEnabled: groupE2eeEnabled,
    agentImEnabled: agentImEnabled,
  );
}

Future<({String otp, DateTime retryAt})> _requestAndResolveRegistrationOtp({
  required OnboardingSupportService onboardingSupport,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String handle,
}) async {
  try {
    final receipt = await onboardingSupport.sendRegistrationOtp(
      phone: account.phone,
      handle: handle,
      domain: config.didDomain,
      fullHandle: '$handle.${config.didDomain}',
    );
    final otp = await _resolveOtp(
      account: account,
      purpose: _registrationPurpose,
      handle: handle,
      didDomain: config.didDomain,
    );
    return (otp: otp, retryAt: receipt.retryAt);
  } on Object {
    fail('The fixed registration OTP request failed safely.');
  }
}

Future<
  ({
    DeviceJoinProgress progress,
    ProviderContainer container,
    DateTime otpRetryAt,
  })
>
_startAppPeerRegistrationJoin({
  required WidgetTester tester,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required AppBootstrap adminBootstrap,
  required AppBootstrap peerBootstrap,
  required E2eUserPresencePort adminPresence,
  required E2eUserPresencePort peerPresence,
  required String handle,
  required String fullHandle,
  required String expectedDid,
  required DateTime registrationRetryAt,
}) async {
  final localIdentities = await peerBootstrap.appSessionService!
      .listLocalIdentities();
  if (localIdentities.length != 1 ||
      localIdentities.single.did == expectedDid) {
    fail(
      'The registration re-Join did not begin from one fenced old identity.',
    );
  }
  final callsBefore = peerPresence.calls;
  await tester.pumpWidget(
    Row(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        Expanded(
          child: KeyedSubtree(
            key: _recoveryAdminAppKey,
            child: AwikiMeApp(
              bootstrap: adminBootstrap,
              providerOverrides: <Override>[
                userPresencePortProvider.overrideWithValue(adminPresence),
              ],
            ),
          ),
        ),
        Expanded(
          child: KeyedSubtree(
            key: _recoveryPeerAppKey,
            child: AwikiMeApp(
              bootstrap: peerBootstrap,
              providerOverrides: <Override>[
                userPresencePortProvider.overrideWithValue(peerPresence),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  final peerRoot = find.byKey(_recoveryPeerAppKey);
  final container = await _confirmFencedPeerReturnedToOnboarding(
    tester,
    peerRoot: peerRoot,
  );
  await _pumpUntil(
    tester,
    () => container.read(onboardingProvider).supportsPhoneOtpRegistration,
    timeout: const Duration(seconds: 45),
    failure: 'Registration onboarding did not expose phone verification.',
  );
  final phoneField = find.descendant(
    of: peerRoot,
    matching: find.bySemanticsIdentifier('e2e-phone-input'),
  );
  final handleField = find.descendant(
    of: peerRoot,
    matching: find.bySemanticsIdentifier('e2e-handle-input'),
  );
  final otpField = find.descendant(
    of: peerRoot,
    matching: find.bySemanticsIdentifier('e2e-otp-input'),
  );
  if (phoneField.evaluate().length != 1 ||
      handleField.evaluate().length != 1 ||
      otpField.evaluate().length != 1) {
    fail('Registration re-Join did not expose one exact onboarding form.');
  }
  await tester.enterText(phoneField, account.phone);
  await tester.enterText(handleField, handle);
  await _waitForRegistrationRetryBoundary(registrationRetryAt);
  await _pumpUntil(
    tester,
    () =>
        !container.read(onboardingProvider).isBusy &&
        container.read(smsOtpCooldownProvider).canSend,
    timeout: const Duration(seconds: 90),
    failure: 'Registration re-Join OTP action did not become available.',
  );
  final existingFeedbackId = container.read(uiFeedbackProvider)?.id;
  await _tapOne(
    tester,
    find.descendant(
      of: peerRoot,
      matching: find.bySemanticsIdentifier('e2e-send-otp-button'),
    ),
    failure: 'Registration re-Join OTP action was unavailable.',
  );
  await _pumpUntil(
    tester,
    () {
      _failOnDangerousUiFeedback(
        container,
        'Registration re-Join OTP request',
        existingEventId: existingFeedbackId,
      );
      final state = container.read(onboardingProvider);
      return !state.isBusy &&
          state.otpTargetFullHandle == fullHandle &&
          state.otpTargetPhone != null;
    },
    timeout: const Duration(seconds: 90),
    failure: 'Registration re-Join did not bind OTP to the recovered Handle.',
  );
  final otp = await _resolveOtp(
    account: account,
    purpose: _registrationPurpose,
    handle: handle,
    didDomain: config.didDomain,
  );
  await tester.enterText(otpField, otp);
  await _tapOne(
    tester,
    find.descendant(
      of: peerRoot,
      matching: find.byKey(const Key('onboarding-mac-phone-submit-action')),
    ),
    failure: 'Registration re-Join submit action was unavailable.',
  );
  final joinAction = find.byKey(const Key('existing-handle-join-action'));
  await _pumpUntil(
    tester,
    () {
      _failOnDangerousUiFeedback(
        container,
        'Registration re-Join verification',
      );
      final state = container.read(onboardingProvider);
      return joinAction.evaluate().length == 1 &&
          state.isPhoneOtpConsumed &&
          !state.canSubmitPhoneOtp &&
          state.existingHandleContinuationId != null &&
          state.existingHandleJoinMode ==
              ExistingHandleJoinMode.handleRecoveryRebind &&
          state.existingHandleJoinRequiresUserPresence;
    },
    timeout: const Duration(minutes: 2),
    failure:
        'Registration did not return one opaque Recovery rebind continuation.',
  );
  await _tapOne(
    tester,
    joinAction,
    failure: 'The registration continuation Join choice was unavailable.',
  );
  final peerJoinPage = find.descendant(
    of: peerRoot,
    matching: find.byType(DeviceJoinPage),
  );
  await _pumpUntil(
    tester,
    () {
      if (peerJoinPage.evaluate().length != 1) return false;
      final state = container.read(devicesProvider);
      if (state.error != null) {
        fail('The peer App rejected its registration continuation.');
      }
      final progress = state.activeJoin;
      return !state.isActionPending &&
          progress?.did == expectedDid &&
          progress?.side == DeviceJoinSide.newDevice &&
          progress?.phase == DeviceJoinPhase.pending &&
          progress?.remoteState == DeviceJoinRemoteState.pending &&
          progress?.sas == null &&
          progress?.cause == DeviceJoinCause.handleRecovery;
    },
    timeout: const Duration(minutes: 2),
    failure: 'The registration continuation did not create Recovery re-Join.',
  );
  if (peerPresence.calls != callsBefore + 1 ||
      peerPresence.completions != callsBefore + 1 ||
      !peerPresence.lastResult ||
      container.read(onboardingProvider).existingHandleContinuationId != null) {
    fail('Registration re-Join crossed an invalid user-presence boundary.');
  }
  return (
    progress: container.read(devicesProvider).activeJoin!,
    container: container,
    otpRetryAt:
        container.read(smsOtpCooldownProvider).retryAt ??
        DateTime.now().toUtc(),
  );
}

Future<void> _waitForRegistrationRetryBoundary(DateTime retryAt) async {
  final remaining = retryAt.toUtc().difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) return;
  if (remaining > const Duration(minutes: 2)) {
    fail('The registration OTP retry boundary exceeded the E2E safety limit.');
  }
  await Future<void>.delayed(remaining + const Duration(seconds: 1));
}

Future<void> _waitForPhoneGlobalRecoveryCooldown(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final cooldown = container.read(smsOtpCooldownProvider);
  if (!cooldown.canSend) {
    final retryAt = cooldown.retryAt;
    if (retryAt == null) {
      fail('The registration OTP cooldown omitted its retry receipt.');
    }
    final delay = remoteHandleRecoveryPhoneCooldownDelay(
      retryAt: retryAt,
      now: DateTime.now().toUtc(),
    );
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }
  await _pumpUntil(
    tester,
    () => container.read(smsOtpCooldownProvider).canSend,
    timeout: const Duration(seconds: 5),
    failure:
        'The registration OTP cooldown did not release before Recovery OTP.',
  );
}

Future<void> _retryRecoveryOtpAfterRateLimit(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final retryAt = container.read(handleRecoverySmsOtpCooldownProvider).retryAt;
  if (retryAt == null) {
    fail('The Recovery OTP rate limit omitted its retry receipt.');
  }
  final delay = remoteHandleRecoveryPhoneCooldownDelay(
    retryAt: retryAt,
    now: DateTime.now().toUtc(),
  );
  if (delay > Duration.zero) {
    await Future<void>.delayed(delay);
  }
  await _pumpUntil(
    tester,
    () => container.read(handleRecoverySmsOtpCooldownProvider).canSend,
    timeout: const Duration(seconds: 5),
    failure: 'The Recovery OTP rate limit did not release at retryAt.',
  );
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('handle-recovery-send-otp'),
    failure: 'The Recovery OTP retry action was unavailable.',
  );
}

Future<void> _retryRegistrationOtpAfterRateLimit(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final retryAt = container.read(smsOtpCooldownProvider).retryAt;
  if (retryAt == null) {
    fail('The registration OTP rate limit omitted its retry receipt.');
  }
  final delay = remoteHandleRecoveryPhoneCooldownDelay(
    retryAt: retryAt,
    now: DateTime.now().toUtc(),
  );
  if (delay > Duration.zero) {
    await Future<void>.delayed(delay);
  }
  await _pumpUntil(
    tester,
    () => container.read(smsOtpCooldownProvider).canSend,
    timeout: const Duration(seconds: 5),
    failure: 'The registration OTP rate limit did not release at retryAt.',
  );
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('e2e-send-otp-button'),
    failure: 'The registration OTP retry action was unavailable.',
  );
}

Future<String> _resolveOtp({
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  required String didDomain,
  String? operationId,
}) async {
  return account.fixedOtp;
}

Future<DateTime> _requestScopedOtp({
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
}) async {
  http.Response response;
  try {
    response = await client
        .post(
          Uri.parse(
            config.userServiceUrl,
          ).resolve('/user-service/v1/auth/sms-codes'),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'phone': account.phone,
            'purpose': purpose,
            'target_handle': handle,
            'target_handle_domain': config.didDomain,
            'rate_limit_seconds': 60,
            'code_expire_minutes': 5,
          }),
        )
        .timeout(_remoteTimeout);
  } on Object {
    fail('The fixed purpose-bound OTP request failed safely.');
  }
  if (response.statusCode != 200) {
    fail('The fixed purpose-bound OTP request was rejected.');
  }
  return DateTime.now().toUtc().add(const Duration(seconds: 1));
}

Future<
  ({
    DeviceJoinProgress progress,
    ProviderContainer container,
    DateTime otpRetryAt,
  })
>
_startAppPeerJoin({
  required WidgetTester tester,
  required http.Client client,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required AppBootstrap adminBootstrap,
  required AppBootstrap peerBootstrap,
  required E2eUserPresencePort adminPresence,
  required E2eUserPresencePort peerPresence,
  required String handle,
  String? joinHandle,
  required String expectedDid,
}) async {
  final localIdentities = await peerBootstrap.appSessionService!
      .listLocalIdentities();
  if (localIdentities.length > 1) {
    fail('The isolated peer App had an ambiguous local identity scope.');
  }
  final recoveryAware = localIdentities.length == 1;
  final otpRetryAt = await _requestScopedOtp(
    client: client,
    config: config,
    account: account,
    purpose: _joinPurpose,
    handle: handle,
  );
  final callsBefore = peerPresence.calls;
  await tester.pumpWidget(
    Row(
      textDirection: TextDirection.ltr,
      children: <Widget>[
        Expanded(
          child: KeyedSubtree(
            key: _recoveryAdminAppKey,
            child: AwikiMeApp(
              bootstrap: adminBootstrap,
              providerOverrides: <Override>[
                userPresencePortProvider.overrideWithValue(adminPresence),
              ],
            ),
          ),
        ),
        Expanded(
          child: KeyedSubtree(
            key: _recoveryPeerAppKey,
            child: AwikiMeApp(
              bootstrap: peerBootstrap,
              providerOverrides: <Override>[
                userPresencePortProvider.overrideWithValue(peerPresence),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  final peerRoot = find.byKey(_recoveryPeerAppKey);
  if (recoveryAware) {
    await _confirmFencedPeerReturnedToOnboarding(tester, peerRoot: peerRoot);
    await _openAppPeerJoinFromOnboarding(tester, peerRoot: peerRoot);
  } else {
    await _openAppPeerJoinFromOnboarding(tester, peerRoot: peerRoot);
  }
  final peerJoinPage = find.descendant(
    of: peerRoot,
    matching: find.byType(DeviceJoinPage),
  );
  await _pumpUntil(
    tester,
    () => peerJoinPage.evaluate().length == 1,
    failure: 'The isolated peer App did not open ordinary Join.',
  );
  await _enterJoinText(
    tester,
    'multi-device-join-handle',
    joinHandle ?? handle,
  );
  await _enterJoinText(tester, 'multi-device-join-phone', account.phone);
  await _enterJoinText(tester, 'multi-device-join-otp', account.fixedOtp);
  await _tapOne(
    tester,
    find.bySemanticsIdentifier('multi-device-start-join'),
    failure: 'The isolated peer App ordinary Join action was unavailable.',
  );
  final container = ProviderScope.containerOf(tester.element(peerJoinPage));
  await _pumpUntil(
    tester,
    () {
      final state = container.read(devicesProvider);
      if (state.error != null) {
        fail('The isolated peer App rejected ordinary Join.');
      }
      final progress = state.activeJoin;
      return !state.isActionPending &&
          progress?.did == expectedDid &&
          progress?.side == DeviceJoinSide.newDevice &&
          progress?.phase == DeviceJoinPhase.pending &&
          progress?.remoteState == DeviceJoinRemoteState.pending &&
          progress?.sas == null &&
          progress?.cause ==
              (recoveryAware
                  ? DeviceJoinCause.handleRecovery
                  : DeviceJoinCause.ordinary);
    },
    timeout: const Duration(minutes: 2),
    failure: 'The isolated peer App did not remain pending without SAS.',
    safeDiagnostic: () {
      final state = container.read(devicesProvider);
      final progress = state.activeJoin;
      return 'pending=${state.isActionPending}, '
          'error=${state.error?.name ?? 'none'}, '
          'progress=${progress == null ? 'none' : 'present'}, '
          'did_matches=${progress?.did == expectedDid}, '
          'side=${progress?.side.name ?? 'none'}, '
          'phase=${progress?.phase.name ?? 'none'}, '
          'remote=${progress?.remoteState.name ?? 'none'}, '
          'cause=${progress?.cause.name ?? 'none'}, '
          'sas_present=${progress?.sas != null}, '
          'presence_calls=${peerPresence.calls}, '
          'presence_completions=${peerPresence.completions}';
    },
  );
  final progress = container.read(devicesProvider).activeJoin!;
  final expectedPresenceCalls = recoveryAware ? callsBefore + 1 : callsBefore;
  if (peerPresence.calls != expectedPresenceCalls ||
      peerPresence.completions != expectedPresenceCalls ||
      (recoveryAware && !peerPresence.lastResult)) {
    fail('The peer App Join used an invalid user-presence boundary.');
  }
  return (progress: progress, container: container, otpRetryAt: otpRetryAt);
}

Future<DeviceJoinProgress> _completeAppPeerJoin({
  required WidgetTester tester,
  required AppBootstrap adminBootstrap,
  required DeviceManagementCorePort deviceCore,
  required String selector,
  required ProviderContainer peerContainer,
  required DeviceJoinProgress pending,
}) async {
  final realtime = adminBootstrap.realtimeApplicationService;
  if (realtime == null) {
    fail('The admin App did not expose the realtime Join listener.');
  }
  try {
    await realtime.start();
  } on Object {
    fail('The admin App realtime Join listener failed to start.');
  }
  if (!realtime.isRunning) {
    fail('The admin App realtime Join listener was not running.');
  }
  final requestDeadline = DateTime.now().add(const Duration(seconds: 45));
  DeviceJoinRequestNotice? request;
  while (DateTime.now().isBefore(requestDeadline)) {
    final matches = (await deviceCore.localDeviceJoinRequests(selector))
        .where(
          (candidate) =>
              candidate.joinSessionId == pending.joinSessionId &&
              candidate.protocolDeviceId == pending.protocolDeviceId,
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('The App projected a duplicate ordinary Join request.');
    }
    if (matches.length == 1 &&
        matches.single.did == selector &&
        matches.single.state == DeviceJoinRemoteState.pending &&
        !matches.single.claimedByCurrentDevice &&
        matches.single.canStartVerification) {
      request = matches.single;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (request == null) {
    fail('The App did not ingest the exact ordinary Join notification.');
  }
  final started = await deviceCore.startDeviceJoinVerification(
    selector: selector,
    joinSessionId: pending.joinSessionId,
    operationId: 'recovery-admin-${_nonce(12)}',
    challengeTtlSeconds: 300,
  );
  if (started.joinSessionId != pending.joinSessionId ||
      started.protocolDeviceId != pending.protocolDeviceId ||
      started.side != DeviceJoinSide.admin ||
      started.remoteState != DeviceJoinRemoteState.challengeSent ||
      started.sas != null) {
    fail('The App admin did not start the exact ordinary Join verification.');
  }
  DeviceJoinProgress? peerProgress;
  final peerDeadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(peerDeadline)) {
    await peerContainer.read(devicesProvider.notifier).pollNewDeviceActive();
    final state = peerContainer.read(devicesProvider);
    if (state.error != null) {
      fail('The isolated peer App failed to consume the Join challenge.');
    }
    final progress = state.activeJoin;
    if (progress?.joinSessionId == pending.joinSessionId &&
        progress?.protocolDeviceId == pending.protocolDeviceId &&
        progress?.phase == DeviceJoinPhase.responsePrepared &&
        progress?.remoteState == DeviceJoinRemoteState.responseVerified &&
        _validSas(progress?.sas ?? '')) {
      peerProgress = progress;
      break;
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (peerProgress == null) {
    fail('The isolated peer App did not derive the ordinary Join SAS.');
  }
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  DeviceJoinProgress? verified;
  while (DateTime.now().isBefore(deadline)) {
    await deviceCore.localDeviceJoinRequests(selector);
    final DeviceJoinProgress progress;
    try {
      progress = await deviceCore.localDeviceJoinVerificationProgress(
        selector: selector,
        joinSessionId: pending.joinSessionId,
      );
    } on core.AwikiImCoreException catch (error) {
      if (error.code != 'local_state_unavailable' ||
          !error.message.contains(
            'admin Join verification progress is not available',
          )) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      continue;
    }
    if (progress.remoteState == DeviceJoinRemoteState.responseVerified &&
        progress.phase == DeviceJoinPhase.responseVerified &&
        progress.sas != null) {
      verified = progress;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (verified == null ||
      !_validSas(verified.sas ?? '') ||
      !_constantTimeAsciiEquals(verified.sas!, peerProgress.sas!)) {
    fail('The two isolated Apps did not derive the same ordinary Join SAS.');
  }
  final prompt = await deviceCore.prepareDeviceJoinApproval(
    selector: selector,
    joinSessionId: pending.joinSessionId,
    sasConfirmed: true,
  );
  if (prompt.joinSessionId != pending.joinSessionId ||
      !_constantTimeAsciiEquals(prompt.sas, verified.sas!)) {
    fail('The App approval prompt changed the verified ordinary Join.');
  }
  final approved = await deviceCore.confirmDeviceJoinApproval(
    approvalHandle: prompt.approvalHandle,
    userPresenceConfirmed: true,
  );
  if (approved.joinSessionId != pending.joinSessionId ||
      approved.remoteState != DeviceJoinRemoteState.consumed) {
    fail('The App admin did not commit the ordinary Join approval.');
  }
  DeviceJoinProgress? authorized;
  final authorizedDeadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(authorizedDeadline)) {
    await peerContainer.read(devicesProvider.notifier).pollNewDeviceActive();
    final state = peerContainer.read(devicesProvider);
    if (state.error != null) {
      fail('The isolated peer App failed to consume Join authorization.');
    }
    final progress = state.activeJoin;
    final device = progress?.authorizedDevice;
    if (progress?.joinSessionId == pending.joinSessionId &&
        progress?.protocolDeviceId == pending.protocolDeviceId &&
        progress?.phase == DeviceJoinPhase.authorized &&
        progress?.remoteState == DeviceJoinRemoteState.consumed &&
        progress?.sas == null &&
        device?.protocolDeviceId == pending.protocolDeviceId &&
        device?.role == DeviceRole.member &&
        device?.managementReady == false &&
        device?.isCurrent == true) {
      authorized = progress;
      break;
    }
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (authorized == null) {
    fail('The isolated peer App did not activate as an ordinary member.');
  }
  return authorized;
}

Future<void> _openAppPeerJoinFromOnboarding(
  WidgetTester tester, {
  required Finder peerRoot,
}) async {
  final onboarding = find.descendant(
    of: peerRoot,
    matching: find.byType(OnboardingPage),
  );
  await _pumpUntil(
    tester,
    () => onboarding.evaluate().length == 1,
    failure: 'The isolated peer App onboarding surface was unavailable.',
  );
  // A fenced peer reaches onboarding while the auth-revoked dialog route is
  // still finishing its reverse transition. Wait for that route to settle so
  // the ordinary Join route is not pushed while the Navigator is locked.
  await tester.pumpAndSettle();
  unawaited(openDeviceJoinPage(tester.element(onboarding)));
  await tester.pump();
}

Future<ProviderContainer> _confirmFencedPeerReturnedToOnboarding(
  WidgetTester tester, {
  required Finder peerRoot,
}) async {
  final onboarding = find.descendant(
    of: peerRoot,
    matching: find.byType(OnboardingPage),
  );
  final confirm = find.descendant(
    of: peerRoot,
    matching: find.byKey(const Key('auth-revoked-dialog-confirm')),
  );
  await _pumpUntil(
    tester,
    () {
      if (onboarding.evaluate().length != 1 || confirm.evaluate().length != 1) {
        return false;
      }
      final container = ProviderScope.containerOf(tester.element(onboarding));
      return container.read(sessionProvider).session == null &&
          container.read(appRuntimeProvider).authRevoked;
    },
    timeout: const Duration(seconds: 45),
    failure:
        'The fenced peer App did not return to onboarding with an auth notice.',
  );
  final container = ProviderScope.containerOf(tester.element(onboarding));
  await _tapOne(
    tester,
    confirm,
    failure: 'The fenced peer App auth notice could not be confirmed.',
  );
  await _pumpUntil(
    tester,
    () => confirm.evaluate().isEmpty,
    failure: 'The fenced peer App auth notice did not close.',
  );
  return container;
}

Future<void> _enterJoinText(
  WidgetTester tester,
  String semanticsIdentifier,
  String value,
) async {
  final field = find.bySemanticsIdentifier(semanticsIdentifier);
  if (field.evaluate().length != 1) {
    fail('The isolated peer App Join field was unavailable.');
  }
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> _activateAppPeerJoin({
  required WidgetTester tester,
  required AppBootstrap peerBootstrap,
  required ProviderContainer peerContainer,
  required String expectedDid,
  required String expectedDeviceId,
}) async {
  await _pumpUntil(
    tester,
    () {
      final state = peerContainer.read(devicesProvider);
      if (state.error != null) {
        fail('The isolated peer App failed during member activation.');
      }
      return state.activeJoin?.authorizedDevice?.protocolDeviceId ==
              expectedDeviceId &&
          peerContainer.read(sessionProvider).session?.did == expectedDid &&
          peerContainer.read(appRuntimeProvider).activatedDid == expectedDid;
    },
    timeout: const Duration(minutes: 2),
    failure: 'The isolated peer App did not activate the expected identity.',
  );
  final identities = await peerBootstrap.appSessionService!
      .listLocalIdentities();
  if (identities.length != 1 || identities.single.did != expectedDid) {
    fail('The isolated peer App retained an invalid identity projection.');
  }
  final registry = await _waitForAppRegistry(
    peerBootstrap.deviceManagementCorePort!,
    did: expectedDid,
    expectedDeviceCount: 2,
  );
  final current = registry.devices.where(
    (device) =>
        device.protocolDeviceId == expectedDeviceId &&
        device.isCurrent &&
        device.role == DeviceRole.member &&
        device.status == DeviceStatus.active,
  );
  if (current.length != 1) {
    fail('The isolated peer App Registry did not select its member device.');
  }
}

Future<DeviceRegistrySnapshot> _waitForAppRegistry(
  DeviceManagementCorePort core, {
  required String did,
  required int expectedDeviceCount,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final registry = await core.identityDeviceRegistry(did);
      if (registry.did == did &&
          registry.devices.length == expectedDeviceCount) {
        return registry;
      }
    } on Object {
      // This bounded read is only waiting for the remote Registry projection.
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The App Registry did not converge after ordinary Join.');
}

void _requireAppAdminAndPeer(
  DeviceRegistrySnapshot registry, {
  required String expectedDid,
  required String peerDeviceId,
}) {
  final currentAdmin = registry.devices.where(
    (device) =>
        device.isCurrent &&
        device.role == DeviceRole.admin &&
        device.managementReady &&
        device.status == DeviceStatus.active,
  );
  final peer = registry.devices.where(
    (device) =>
        device.protocolDeviceId == peerDeviceId &&
        !device.isCurrent &&
        device.role == DeviceRole.member &&
        !device.managementReady &&
        device.status == DeviceStatus.active,
  );
  if (registry.did != expectedDid ||
      registry.devices.length != 2 ||
      currentAdmin.length != 1 ||
      peer.length != 1) {
    fail('The App Registry did not converge to one admin and one App peer.');
  }
}

Future<ProviderContainer> _waitForRecoveredAppSession(
  WidgetTester tester, {
  required String expectedDid,
}) async {
  final adminShell = find.descendant(
    of: find.byKey(_recoveryAdminAppKey),
    matching: find.byType(AppShell),
  );
  await _pumpUntil(
    tester,
    () => adminShell.evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'The recovered App shell did not remount after peer re-Join.',
  );
  final container = ProviderScope.containerOf(tester.element(adminShell));
  await _pumpUntil(
    tester,
    () =>
        container.read(sessionProvider).session?.did == expectedDid &&
        container.read(appRuntimeProvider).activatedDid == expectedDid,
    timeout: const Duration(seconds: 45),
    failure: 'The recovered App did not restore its exact session.',
  );
  return container;
}

Future<void> _requireOldAppPrincipalFenced(
  AppBootstrap peerBootstrap, {
  required String targetDid,
}) async {
  final messaging = peerBootstrap.messagingService;
  final directory = peerBootstrap.directoryApplicationService;
  if (messaging == null || directory == null) {
    fail('The old peer App did not expose remote messaging.');
  }
  try {
    final resolved = await directory.resolvePeer(targetDid);
    final conversationId = resolved.conversationId?.trim() ?? '';
    if (resolved.did != targetDid || conversationId.isEmpty) {
      fail('The old peer App did not resolve the Recovery target exactly.');
    }
    await _plainDirectMessaging(messaging).sendPlainConversationText(
      conversation: AppConversationReadRef.fromConversationId(conversationId),
      content: 'fence-${_nonce(10)}',
    );
  } on core.AwikiImCoreException catch (error) {
    final fenced =
        const <String>{
          'auth_required',
          'identity_required',
          'permission_denied',
        }.contains(error.code) ||
        const <String>{
          'client.session_unauthorized',
          'anp.device_not_eligible',
          'anp.device_state_changed',
        }.contains(error.serviceCode);
    if (fenced) return;
    fail('The old peer App was rejected for a non-fencing reason.');
  }
  fail('The old peer App retained a remote messaging capability.');
}

Future<void> _requirePeerCurrentIdentityAndRegistry(
  AppBootstrap peerBootstrap, {
  required String expectedDid,
  required String expectedDeviceId,
  required int expectedDeviceCount,
}) async {
  final identities = await peerBootstrap.appSessionService!
      .listLocalIdentities();
  if (identities.length != 1 || identities.single.did != expectedDid) {
    fail('The rejoined peer App did not activate the Recovery DID.');
  }
  final registry = await peerBootstrap.deviceManagementCorePort!
      .identityDeviceRegistry(expectedDid);
  final current = registry.devices.where(
    (device) =>
        device.protocolDeviceId == expectedDeviceId &&
        device.isCurrent &&
        device.role == DeviceRole.member &&
        device.status == DeviceStatus.active,
  );
  if (registry.did != expectedDid ||
      registry.devices.length != expectedDeviceCount ||
      current.length != 1) {
    fail('The rejoined peer App Registry did not converge to the new DID.');
  }
}

Future<void> _transferManagementToRejoinedPeer({
  required AppBootstrap bootstrap,
  required AppBootstrap peerBootstrap,
  required ProviderContainer peerContainer,
  required ProviderContainer recoveredContainer,
  required E2eUserPresencePort presence,
  required String expectedDid,
  required String peerDeviceId,
}) async {
  if (bootstrap.rootKeyTransferPort == null ||
      peerBootstrap.messageSyncService == null) {
    fail('The App pair did not compose standard root transfer and sync.');
  }
  final registry = await bootstrap.deviceManagementCorePort!
      .identityDeviceRegistry(expectedDid);
  final senders = registry.devices
      .where(
        (device) =>
            device.isCurrent &&
            device.role == DeviceRole.admin &&
            device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  final recipients = registry.devices
      .where(
        (device) =>
            device.protocolDeviceId == peerDeviceId &&
            !device.isCurrent &&
            device.role == DeviceRole.member &&
            !device.managementReady &&
            device.status == DeviceStatus.active,
      )
      .toList(growable: false);
  if (senders.length != 1 || recipients.length != 1) {
    fail('Root transfer did not begin from the exact admin/member Registry.');
  }
  final service = recoveredContainer.read(rootKeyTransferServiceProvider);
  final callsBefore = presence.calls;
  final preparation = await service.prepare(
    expectedDid: expectedDid,
    recipient: recipients.single,
  );
  if (presence.calls != callsBefore ||
      preparation.recipient.did != expectedDid ||
      preparation.recipient.deviceId != peerDeviceId) {
    fail('Root transfer preparation escaped its exact recipient boundary.');
  }
  final receipt = await service.confirmAndSend(
    expectedDid: expectedDid,
    sender: senders.single,
    preparation: preparation,
    presenceReason: 'Confirm management transfer to recovered App peer',
    contextStillValid: () => true,
  );
  if (presence.calls != callsBefore + 1 ||
      presence.completions != callsBefore + 1 ||
      !presence.lastResult ||
      receipt.did != expectedDid ||
      receipt.senderDeviceId != senders.single.protocolDeviceId ||
      receipt.recipientDeviceId != peerDeviceId ||
      receipt.messageId.trim().isEmpty) {
    fail('The App did not accept one exact standard root transfer.');
  }

  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      final outcome = await peerBootstrap.messageSyncService!.syncNow(
        reason: 'handle-recovery-registration-root-transfer',
        limit: 100,
      );
      if (outcome.status == MessageSyncStatus.authRevoked) {
        fail(
          'Root promotion was misclassified as a revoked peer authorization.',
        );
      }
    } on MessageSyncCoreFailure catch (error) {
      // The App realtime listener may ACK the same committed P5 control while
      // this explicit E2E reconciliation is in flight. The next bounded read
      // must still prove the authoritative Registry transition.
      if (error.code != 'secure_inbox_ack_incomplete') rethrow;
    }
    final peerRegistry = await peerBootstrap.deviceManagementCorePort!
        .identityDeviceRegistry(expectedDid);
    final adminRegistry = await bootstrap.deviceManagementCorePort!
        .identityDeviceRegistry(expectedDid);
    final peerReady = peerRegistry.devices.where(
      (device) =>
          device.protocolDeviceId == peerDeviceId &&
          device.isCurrent &&
          device.role == DeviceRole.admin &&
          device.managementReady &&
          device.status == DeviceStatus.active,
    );
    final senderReady = adminRegistry.devices.where(
      (device) =>
          device.protocolDeviceId == senders.single.protocolDeviceId &&
          device.isCurrent &&
          device.role == DeviceRole.admin &&
          device.managementReady &&
          device.status == DeviceStatus.active,
    );
    final projectedPeer = adminRegistry.devices.where(
      (device) =>
          device.protocolDeviceId == peerDeviceId &&
          !device.isCurrent &&
          device.role == DeviceRole.admin &&
          device.managementReady &&
          device.status == DeviceStatus.active,
    );
    if (peerRegistry.did == expectedDid &&
        adminRegistry.did == expectedDid &&
        peerRegistry.devices.length == 2 &&
        adminRegistry.devices.length == 2 &&
        peerReady.length == 1 &&
        senderReady.length == 1 &&
        projectedPeer.length == 1) {
      final peerSession = await peerBootstrap.appSessionService!
          .currentSession();
      if (peerSession?.did != expectedDid ||
          peerContainer.read(sessionProvider).session?.did != expectedDid ||
          peerContainer.read(appRuntimeProvider).authRevoked) {
        fail('Root promotion did not retain the rejoined App session.');
      }
      final peerHistory = await peerBootstrap.messagingService!.loadHistory(
        AppThreadRef.direct(expectedDid),
        limit: 20,
      );
      if (peerHistory.any((message) => message.remoteId == receipt.messageId)) {
        fail('Root transfer entered the ordinary App message projection.');
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('The rejoined App peer did not become management-ready after P5.');
}

Future<void> _verifyBidirectionalDirectExactOne({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required AppBootstrap peerBootstrap,
  required String did,
  required String rejoinedIdentityId,
  required String externalIdentityId,
  required String externalDid,
  required String runId,
}) async {
  final recoveredMessaging = bootstrap.messagingService;
  final peerMessaging = peerBootstrap.messagingService;
  if (recoveredMessaging == null || peerMessaging == null) {
    fail('The two Apps did not expose canonical messaging.');
  }
  await _activatePeerIdentity(
    peerBootstrap,
    identityId: externalIdentityId,
    expectedDid: externalDid,
  );
  final appText = 'rejoin-${_safeId(runId, 18)}-app';
  final appMessage = await recoveredMessaging.sendText(
    thread: AppThreadRef.direct(externalDid),
    content: appText,
  );
  final appMessageId = appMessage.remoteId?.trim() ?? '';
  if (appMessageId.isEmpty ||
      appMessage.conversationId?.trim().isEmpty != false ||
      appMessage.senderDid != did ||
      appMessage.receiverDid != externalDid ||
      !appMessage.isMine ||
      appMessage.sendState != MessageSendState.sent) {
    fail('The recovered App did not commit the exact Direct message.');
  }

  await _syncAndWaitForAppThreadExactOne(
    tester: tester,
    appBootstrap: peerBootstrap,
    thread: AppThreadRef.direct(did),
    messageId: appMessageId,
    content: appText,
    senderDid: did,
    receiverDid: externalDid,
    isMine: false,
  );

  await _activatePeerIdentity(
    peerBootstrap,
    identityId: rejoinedIdentityId,
    expectedDid: did,
  );
  await _syncAndWaitForAppThreadExactOne(
    tester: tester,
    appBootstrap: peerBootstrap,
    thread: AppThreadRef.direct(externalDid),
    messageId: appMessageId,
    content: appText,
    senderDid: did,
    receiverDid: externalDid,
    isMine: true,
  );

  await _activatePeerIdentity(
    peerBootstrap,
    identityId: externalIdentityId,
    expectedDid: externalDid,
  );
  final peerText = 'rejoin-${_safeId(runId, 18)}-external';
  final peerMessage = await peerMessaging.sendText(
    thread: AppThreadRef.direct(did),
    content: peerText,
  );
  final peerMessageId = peerMessage.remoteId?.trim() ?? '';
  if (peerMessageId.isEmpty ||
      peerMessage.conversationId?.trim().isEmpty != false ||
      peerMessage.senderDid != externalDid ||
      peerMessage.receiverDid != did ||
      !peerMessage.isMine ||
      peerMessage.sendState != MessageSendState.sent) {
    fail('The external App identity did not commit the exact Direct reply.');
  }
  await _syncAndWaitForAppThreadExactOne(
    tester: tester,
    appBootstrap: bootstrap,
    thread: AppThreadRef.direct(externalDid),
    messageId: peerMessageId,
    content: peerText,
    senderDid: externalDid,
    receiverDid: did,
    isMine: false,
  );

  await _activatePeerIdentity(
    peerBootstrap,
    identityId: rejoinedIdentityId,
    expectedDid: did,
  );
  await _syncAndWaitForAppThreadExactOne(
    tester: tester,
    appBootstrap: peerBootstrap,
    thread: AppThreadRef.direct(externalDid),
    messageId: peerMessageId,
    content: peerText,
    senderDid: externalDid,
    receiverDid: did,
    isMine: false,
  );
  if ((await bootstrap.appSessionService!.currentSession())?.did != did ||
      (await peerBootstrap.appSessionService!.currentSession())?.did != did) {
    fail('A recovered App session changed while Direct sync converged.');
  }
}

Future<ChatMessage> _syncAndWaitForAppThreadExactOne({
  required WidgetTester tester,
  required AppBootstrap appBootstrap,
  required AppThreadRef thread,
  required String messageId,
  required String content,
  required String senderDid,
  required String receiverDid,
  required bool isMine,
}) async {
  final messaging = appBootstrap.messagingService;
  final sync = appBootstrap.messageSyncService;
  if (messaging == null || sync == null) {
    fail('An App lacked canonical thread message sync.');
  }
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      await sync.syncNow(reason: 'handle-recovery-rejoin-e2e', limit: 100);
    } on MessageSyncCoreFailure catch (error) {
      if (error.code != 'transport_unavailable') rethrow;
      await tester.pump(const Duration(milliseconds: 200));
      await Future<void>.delayed(const Duration(milliseconds: 550));
      continue;
    }
    final messages = await _loadExactThreadCandidates(
      appBootstrap: appBootstrap,
      thread: thread,
      messageId: messageId,
    );
    final matches = messages
        .where(
          (message) =>
              message.remoteId == messageId && message.content == content,
        )
        .toList(growable: false);
    if (matches.length > 1) {
      fail('An App projected a duplicate exact thread message.');
    }
    if (matches.length == 1) {
      final message = matches.single;
      if (message.senderDid != senderDid ||
          message.receiverDid != receiverDid ||
          message.isMine != isMine ||
          message.sendState != MessageSendState.sent) {
        fail(
          'An App projected invalid thread message ownership '
          '(sender=${message.senderDid == senderDid}, '
          'receiver=${message.receiverDid == receiverDid}, '
          'mine=${message.isMine}, expectedMine=$isMine, '
          'state=${message.sendState.name}).',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final stable = await _loadExactThreadCandidates(
        appBootstrap: appBootstrap,
        thread: thread,
        messageId: messageId,
      );
      if (stable
              .where(
                (candidate) =>
                    candidate.remoteId == messageId &&
                    candidate.content == content,
              )
              .length !=
          1) {
        fail('An App thread projection was not exact-one stable.');
      }
      return message;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('An App did not converge the exact thread message.');
}

Future<void> _syncHandleRecoveryFixtureWithRetry({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      await bootstrap.messageSyncService!.syncNow(reason: reason, limit: 100);
      return;
    } on MessageSyncCoreFailure catch (error) {
      if (error.code != 'transport_unavailable') rethrow;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('Handle Recovery fixture sync transport remained unavailable.');
}

Future<T> _retryHandleRecoveryCoreTransport<T>({
  required WidgetTester tester,
  required Future<T> Function() action,
  required String failure,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    try {
      return await action();
    } on core.AwikiImCoreException catch (error) {
      if (error.code != 'transport_unavailable') rethrow;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail(failure);
}

Future<ConversationSummary> _waitForDirectConversation({
  required WidgetTester tester,
  required AppBootstrap bootstrap,
  required String ownerDid,
  required String peerDid,
  required String content,
  int? unreadCount,
}) async {
  final conversations = bootstrap.conversationService;
  final sync = bootstrap.messageSyncService;
  if (conversations == null || sync == null) {
    fail('Handle Recovery fixture lacked canonical conversation sync.');
  }
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    await sync.syncNow(reason: 'fresh-recovery-direct-inbound', limit: 100);
    final items = await conversations.listConversations(
      ownerDid: ownerDid,
      limit: 100,
    );
    try {
      final selected = requireHandleRecoveryExactOne<ConversationSummary>(
        rawItems: items,
        canonicalMatch: (conversation) =>
            !conversation.isGroup && conversation.targetDid == peerDid,
        semanticMatch: (conversation) =>
            !conversation.isGroup &&
            conversation.lastMessagePreview == content &&
            (unreadCount == null || conversation.unreadCount == unreadCount),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final stable = await conversations.listConversations(
        ownerDid: ownerDid,
        limit: 100,
      );
      requireHandleRecoveryExactOne<ConversationSummary>(
        rawItems: stable,
        canonicalMatch: (conversation) =>
            conversation.conversationId == selected.conversationId,
        semanticMatch: (conversation) =>
            !conversation.isGroup &&
            conversation.targetDid == peerDid &&
            conversation.lastMessagePreview == content &&
            (unreadCount == null || conversation.unreadCount == unreadCount),
      );
      return selected;
    } on HandleRecoveryOracleFailure catch (error) {
      if (error.code != 'canonical_exact_one_failed') rethrow;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('Handle Recovery fixture did not project one exact Direct row.');
}

Future<List<ChatMessage>> _loadExactThreadCandidates({
  required AppBootstrap appBootstrap,
  required AppThreadRef thread,
  required String messageId,
}) async {
  final messaging = appBootstrap.messagingService!;
  final legacy = await messaging.loadHistory(thread, limit: 100);
  final canonicalLegacyMatch = legacy.any(
    (message) =>
        message.remoteId == messageId &&
        (message.conversationId?.trim().isNotEmpty ?? false),
  );
  if (canonicalLegacyMatch ||
      messaging is! ConversationTimelineMessagingService) {
    return legacy;
  }
  final timelineMessaging = messaging as ConversationTimelineMessagingService;
  final session = await appBootstrap.appSessionService!.currentSession();
  final conversations = appBootstrap.conversationService;
  if (session == null || conversations == null) return legacy;
  final summaries = await conversations.listConversations(
    ownerDid: session.did,
    limit: 100,
  );
  for (final summary in summaries) {
    final timeline = await timelineMessaging.loadConversationTimeline(
      AppConversationReadRef.fromConversationId(summary.conversationId),
      limit: 100,
    );
    if (timeline.any((message) => message.remoteId == messageId)) {
      return timeline;
    }
  }
  return legacy;
}

Future<void> _activatePeerIdentity(
  AppBootstrap peerBootstrap, {
  required String identityId,
  required String expectedDid,
}) async {
  final sessions = peerBootstrap.appSessionService!;
  await sessions.logout();
  final session = await sessions.loginWithIdentity(identityId);
  if (!session.authenticated || session.did != expectedDid) {
    fail('The second App did not activate the expected local identity.');
  }
  final realtime = peerBootstrap.realtimeApplicationService;
  if (realtime == null) {
    fail('The second App did not expose realtime after identity switch.');
  }
  await realtime.start();
  if (!realtime.isRunning) {
    fail('The second App realtime did not restart after identity switch.');
  }
}

bool _validSas(String value) => RegExp(r'^\d{6}$').hasMatch(value);

bool _constantTimeAsciiEquals(String first, String second) {
  final firstBytes = ascii.encode(first);
  final secondBytes = ascii.encode(second);
  var difference = firstBytes.length ^ secondBytes.length;
  final count = max(firstBytes.length, secondBytes.length);
  for (var index = 0; index < count; index += 1) {
    final left = index < firstBytes.length ? firstBytes[index] : 0;
    final right = index < secondBytes.length ? secondBytes[index] : 0;
    difference |= left ^ right;
  }
  return difference == 0;
}

String _safeId(String value, int maxLength) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
  return safe.substring(0, min(safe.length, maxLength));
}

void _requireIndependentFreshRoots(List<String> paths) {
  final roots = paths.map((path) => Directory(path).absolute.path).toSet();
  if (roots.length != paths.length) {
    fail('The Recovery App and CLI peer roots were not independent.');
  }
  for (final candidate in roots) {
    for (final other in roots) {
      if (candidate != other &&
          candidate.startsWith('$other${Platform.pathSeparator}')) {
        fail('The Recovery App and CLI peer roots were nested.');
      }
    }
  }
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync() ||
        directory.listSync(followLinks: false).isNotEmpty) {
      fail('A Recovery App or CLI peer root was not fresh.');
    }
  }
}

class _RemoteRecoveryRunConfig {
  const _RemoteRecoveryRunConfig({
    required this.runId,
    required this.baseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.mailServiceUrl,
    required this.didDomain,
    required this.anpServiceUrl,
    required this.anpServiceDid,
    required this.handlePrefix,
    required this.automatedUserPresence,
    required this.otpMode,
    required this.localConfigPath,
    required this.appStateRoot,
    required this.peerAppStateRoot,
    required this.crashCutHandoffPath,
    required this.daemonBinary,
    required this.daemonStateRoot,
    required this.daemonReadyFile,
    required this.daemonHandle,
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
  final bool automatedUserPresence;
  final String otpMode;
  final String localConfigPath;
  final String appStateRoot;
  final String peerAppStateRoot;
  final String crashCutHandoffPath;
  final String? daemonBinary;
  final String? daemonStateRoot;
  final String? daemonReadyFile;
  final String? daemonHandle;

  static bool exists() => File(_runConfigPath).existsSync();

  static _RemoteRecoveryRunConfig load() {
    if (Platform.environment[_activationGate]?.trim() != '1') {
      throw StateError('Remote Handle Recovery is not explicitly enabled.');
    }
    final decoded = jsonDecode(File(_runConfigPath).readAsStringSync());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 2 ||
        decoded['enabled'] != true) {
      throw StateError('Remote Handle Recovery run config is invalid.');
    }
    final root = _stringMap(decoded);
    final service = _map(root, 'service');
    final account = _map(root, 'account');
    final testControl = _map(root, 'testControl');
    final app = _map(root, 'app');
    final peerApp = _map(root, 'peerApp');
    final crashCut = _map(root, 'crashCut');
    final daemon = _optionalMap(root, 'daemon');
    final config = _RemoteRecoveryRunConfig(
      runId: _required(root, 'runId'),
      baseUrl: _required(service, 'baseUrl'),
      userServiceUrl: _required(service, 'userServiceUrl'),
      messageServiceUrl: _required(service, 'messageServiceUrl'),
      mailServiceUrl: _required(service, 'mailServiceUrl'),
      didDomain: _required(service, 'didDomain'),
      anpServiceUrl: _required(service, 'anpServiceUrl'),
      anpServiceDid: _required(service, 'anpServiceDid'),
      handlePrefix: _required(account, 'handlePrefix'),
      otpMode: _required(account, 'otpMode'),
      localConfigPath: _required(account, 'localConfigPath'),
      automatedUserPresence: _requiredBool(
        testControl,
        'automatedUserPresence',
      ),
      appStateRoot: _required(app, 'stateRoot'),
      peerAppStateRoot: _required(peerApp, 'stateRoot'),
      crashCutHandoffPath: _required(crashCut, 'handoffPath'),
      daemonBinary: _optionalString(daemon, 'binary'),
      daemonStateRoot: _optionalString(daemon, 'stateRoot'),
      daemonReadyFile: _optionalString(daemon, 'readyFile'),
      daemonHandle: _optionalString(daemon, 'handle'),
    );
    if (!config.automatedUserPresence ||
        config.didDomain != 'awiki.info' ||
        config.otpMode != 'ignored_local_fixture') {
      throw StateError('Remote Handle Recovery controls are not audited.');
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
    return config;
  }
}

class _DedicatedAccount {
  const _DedicatedAccount({required this.phone, required this.fixedOtp});

  final String phone;
  final String fixedOtp;

  static _DedicatedAccount fromConfig(_RemoteRecoveryRunConfig config) {
    final file = File(config.localConfigPath);
    if (!file.existsSync()) {
      throw StateError('The ignored local OTP fixture is missing.');
    }
    final Object? decoded;
    try {
      decoded = loadYaml(file.readAsStringSync());
    } on Object {
      throw StateError('The ignored local OTP fixture is invalid.');
    }
    if (decoded is! Map) {
      throw StateError('The ignored local OTP fixture is invalid.');
    }
    final otp = _map(_stringMap(decoded), 'otp');
    final phone = _required(otp, 'phone');
    final fixedOtp = _required(otp, 'code');
    if (!isSixDigitAsciiOtp(fixedOtp)) {
      throw StateError('The ignored local test OTP is invalid.');
    }
    return _DedicatedAccount(phone: phone, fixedOtp: fixedOtp);
  }
}

Map<String, Object?> _stringMap(Map<dynamic, dynamic> value) =>
    <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };

Map<String, Object?> _map(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! Map) throw StateError('Missing run config object $key.');
  return _stringMap(value);
}

Map<String, Object?> _optionalMap(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value == null) return const <String, Object?>{};
  if (value is! Map) throw StateError('Invalid run config object $key.');
  return _stringMap(value);
}

String _required(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! String || value.trim().isEmpty) {
    throw StateError('Missing run config value $key.');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> root, String key) {
  final value = root[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

bool _requiredBool(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! bool) throw StateError('Missing run config flag $key.');
  return value;
}

bool _invocationExpects(String caseId) {
  final value = e2eInvocationValue(
    e2eCaseIdsDefine,
    compiledValue: const String.fromEnvironment(e2eCaseIdsDefine),
  );
  return value.split(',').map((item) => item.trim()).contains(caseId);
}

void _requireFreshRoot(String path) {
  final directory = Directory(path);
  if (!directory.existsSync() ||
      directory.listSync(followLinks: false).isNotEmpty) {
    fail('The Handle Recovery App root was missing or not fresh.');
  }
}

Future<void> _deleteDirectory(String path) async {
  final directory = Directory(path);
  if (await directory.exists()) await directory.delete(recursive: true);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String failure,
  Duration timeout = const Duration(seconds: 15),
  String Function()? safeDiagnostic,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (!condition()) {
    final diagnostic = safeDiagnostic?.call();
    fail(
      diagnostic == null ? failure : '$failure Safe diagnostic: $diagnostic.',
    );
  }
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

Future<void> _enterTextByKey(WidgetTester tester, Key key, String value) async {
  final editable = find.descendant(
    of: find.byKey(key),
    matching: find.byType(EditableText),
  );
  if (editable.evaluate().length != 1) {
    fail('The keyed Handle Recovery field was unavailable.');
  }
  await tester.ensureVisible(editable);
  await tester.enterText(editable, value);
  await tester.pump();
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
