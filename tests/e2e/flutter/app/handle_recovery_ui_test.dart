// [INPUT]: Audited awiki.info endpoints, one protected fixed test SMS account,
//          server-issued SMS retry boundaries, a fresh production
//          AppBootstrap/native Core root, and an E2E-only user-presence decision.
// [OUTPUT]: Secret-free proof that unified onboarding can recover a Handle on
//           a machine with no local identity, replace its DID, and install it.
// [POS]: Remote product UI acceptance; setup creates only the remote fixture,
//        while the tested registration choice and Recovery are UI-driven.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/app_bootstrap_epoch_barrier.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/ports/device_management_core_port.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:yaml/yaml.dart';

import '../../case_attestation.dart';
import '../../e2e_user_presence_port.dart';
import '../../remote_multi_device_join_contract.dart';

const String _caseId = 'HANDLE-RECOVERY-V1-E2E-001';
const String _crashCutCaseId = 'HANDLE-RECOVERY-V1-E2E-002';
const String _rejoinCaseId = 'HANDLE-RECOVERY-V1-E2E-003';
const String _registrationRejoinCaseId =
    'HANDLE-RECOVERY-REGISTRATION-REJOIN-E2E-001';
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
      final rejoinRequired =
          _invocationExpects(_rejoinCaseId) || registrationRejoinRequired;
      final httpClient = http.Client();
      AppBootstrap? bootstrap;
      AppBootstrap? peerBootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireFreshRoot(config.appStateRoot);
      if (rejoinRequired) {
        _requireIndependentFreshRoots(<String>[
          config.appStateRoot,
          config.peerAppStateRoot,
        ]);
      }
      addTearDown(() async {
        httpClient.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await peerBootstrap?.dispose();
        await _deleteDirectory(config.appStateRoot);
        await _deleteDirectory(config.peerAppStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      bootstrap = await AppBootstrap.create(
        environment: _environment(config),
        appStateRoot: config.appStateRoot,
      );
      final bareHandle = _uniqueHandle(config.handlePrefix);
      final onboardingSupport = bootstrap.onboardingSupportService;
      if (onboardingSupport == null) {
        fail('The production onboarding support service was unavailable.');
      }
      final registrationFactor = await _requestAndResolveRegistrationOtp(
        onboardingSupport: onboardingSupport,
        config: config,
        account: account,
        handle: bareHandle,
      );
      final registration = await bootstrap.onboardingService!
          .registerHandleWithPhone(
            phone: account.phone,
            otp: registrationFactor.otp,
            handle: bareHandle,
            nickName: 'AWiki Handle Recovery E2E',
          );
      final oldSession = registration.identity;
      if (registration.status != IdentityRegistrationStatus.registered ||
          oldSession == null ||
          !oldSession.authenticated ||
          oldSession.handle == null) {
        fail('The Recovery fixture did not create one authenticated identity.');
      }
      final oldDid = oldSession.did;
      final fullHandle = oldSession.handle!.trim().toLowerCase();
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(oldDid);
      _requireReadyCurrentAdmin(initialRegistry, expectedDid: oldDid);
      var latestOtpRetryAt = registrationFactor.retryAt;
      String? oldPeerDeviceId;
      if (rejoinRequired) {
        peerBootstrap = await AppBootstrap.create(
          environment: _environment(config),
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
        environment: _environment(config),
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
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('e2e-send-otp-button'),
        failure: 'The registration OTP action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          _failOnDangerousUiFeedback(container, 'Registration OTP request');
          final state = container.read(onboardingProvider);
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
          return find
                  .byKey(const Key('existing-handle-recovery-action'))
                  .evaluate()
                  .length ==
              1;
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
      if (recordingRecoveryCore.requestOtpCalls != 1 ||
          recordingRecoveryCore.requestedHandle != fullHandle ||
          recordingRecoveryCore.requestedPhone != account.phone ||
          recordingRecoveryCore.requestedLocalIdentityId != null) {
        fail(
          'Recovery did not submit the exact verified context once without a local selector.',
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

      if (rejoinRequired) {
        await _pumpUntil(
          tester,
          () =>
              container.read(sessionProvider).session?.did ==
                  reset.currentDid &&
              container.read(appRuntimeProvider).activatedDid ==
                  reset.currentDid,
          timeout: const Duration(seconds: 45),
          failure:
              'The App did not activate the recovered identity before re-Join.',
          safeDiagnostic: () {
            final feedback = container.read(uiFeedbackProvider);
            final session = container.read(sessionProvider).session;
            final runtime = container.read(appRuntimeProvider);
            return 'feedback=${feedback?.message.id ?? 'none'}, '
                'failure=${_safeRecoveryActivationFailure(feedback?.message.detail)}, '
                'barrier=${appBootstrapEpochBarrierMetrics.snapshot()}, '
                'session=${session == null ? 'none' : 'present'}, '
                'session_is_recovered=${session?.did == reset.currentDid}, '
                'runtime_is_recovered=${runtime.activatedDid == reset.currentDid}, '
                'runtime_busy=${runtime.isBusy}';
          },
        );
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
            'new_local_owner_handle_and_replacement_did_verified',
            'old_did_absent_from_fresh_local_projection',
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
            'registration_returned_opaque_recovery_join_continuation',
            'registration_continuation_rejoined_recovery_did',
            'two_app_registry_session_converged',
            'standard_root_transfer_made_rejoined_peer_management_ready',
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
            !_invocationExpects(_registrationRejoinCaseId)),
    timeout: Timeout(
      Duration(
        minutes: _invocationExpects(_registrationRejoinCaseId) ? 25 : 20,
      ),
    ),
  );

  testWidgets(
    'Handle Recovery crash-cut phase A stops before Product reset',
    _runRecoveryCrashCutPhaseA,
    skip:
        _e2ePhase != 'crash_a' ||
        !_RemoteRecoveryRunConfig.exists() ||
        !_invocationExpects(_crashCutCaseId),
    timeout: const Timeout(Duration(minutes: 15)),
  );

  testWidgets(
    'Handle Recovery crash-cut phase B applies barrier before session restore',
    _runRecoveryCrashCutPhaseB,
    skip:
        _e2ePhase != 'crash_b' ||
        !_RemoteRecoveryRunConfig.exists() ||
        !_invocationExpects(_crashCutCaseId),
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

Future<void> _runRecoveryCrashCutPhaseA(WidgetTester tester) async {
  final config = _RemoteRecoveryRunConfig.load();
  final account = _DedicatedAccount.fromConfig(config);
  final presence = E2eUserPresencePort();
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  _requireFreshRoot(config.appStateRoot);

  final bootstrap = await AppBootstrap.create(
    environment: _environment(config),
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
  await _waitForRegistrationRetryBoundary(factor.retryAt);
  unawaited(
    Navigator.of(tester.element(find.byType(AppShell))).push<void>(
      CupertinoPageRoute<void>(
        builder: (_) => HandleRecoveryPage(
          initialHandle: oldSession.handle!.trim().toLowerCase(),
          initialPhone: account.phone,
        ),
      ),
    ),
  );
  await _pumpUntil(
    tester,
    () => find.byType(HandleRecoveryPage).evaluate().length == 1,
    failure: 'Crash-cut setup did not open the visible Recovery surface.',
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(HandleRecoveryPage)),
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
      presence.completions != 1) {
    fail('Crash-cut phase A did not stop after one committed Recovery.');
  }
  final preResetEpoch = await bootstrap.productLocalStore!
      .loadDeviceRegistryEpoch(binding: productBinding);
  final preResetSnapshot = await bootstrap.productLocalStore!
      .loadDeviceRegistrySnapshot(binding: productBinding);
  if (!(preResetEpoch?.matches(oldEpoch) ?? false) ||
      preResetSnapshot?.devices.length != 1 ||
      appContainer.read(sessionProvider).session?.did != oldSession.did) {
    fail('Product state advanced before the deliberate crash cut.');
  }
  await _writeCrashCutHandoff(config.crashCutHandoffPath, <String, Object?>{
    'schemaVersion': 1,
    'oldDid': oldSession.did,
    'newDid': reset.currentDid,
    'ownerIdentityId': oldBinding.ownerIdentityId,
    'accountId': oldBinding.accountId,
    'operationId': operationId,
  });

  // Deliberately do not dispose [bootstrap]. Returning lets the Flutter test
  // process terminate with the Core commit durable and Product reset pending.
}

Future<void> _runRecoveryCrashCutPhaseB(WidgetTester tester) async {
  final config = _RemoteRecoveryRunConfig.load();
  final handoffFile = File(config.crashCutHandoffPath);
  if (!handoffFile.existsSync()) {
    fail('Crash-cut phase B found no phase-A handoff.');
  }
  final decoded = jsonDecode(handoffFile.readAsStringSync());
  if (decoded is! Map || decoded['schemaVersion'] != 1) {
    fail('Crash-cut handoff was invalid.');
  }
  final handoff = _stringMap(decoded);
  final oldDid = _required(handoff, 'oldDid');
  final newDid = _required(handoff, 'newDid');
  final binding = ProductAccountBinding(
    ownerIdentityId: _required(handoff, 'ownerIdentityId'),
    accountId: _required(handoff, 'accountId'),
  );

  final bootstrap = await AppBootstrap.create(
    environment: _environment(config),
    appStateRoot: config.appStateRoot,
  );
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap.dispose();
    await _deleteDirectory(config.appStateRoot);
    if (handoffFile.existsSync()) await handoffFile.delete();
    await tester.binding.setSurfaceSize(null);
  });
  final before = await bootstrap.productLocalStore!.loadDeviceRegistrySnapshot(
    binding: binding,
  );
  if (before?.epoch.currentDid != oldDid) {
    fail('Crash-cut phase B did not begin with the old Product epoch.');
  }

  await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
  await _pumpUntil(
    tester,
    () {
      final shell = find.byType(AppShell);
      if (shell.evaluate().length != 1) return false;
      final container = ProviderScope.containerOf(tester.element(shell));
      return container.read(sessionProvider).session?.did == newDid &&
          container.read(appRuntimeProvider).activatedDid == newDid;
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
  await E2eCaseAttestationWriter.markPassed(
    _crashCutCaseId,
    phases: const <String>[
      'phase_a_committed_with_old_product_epoch',
      'phase_a_process_terminated_before_product_reset',
      'phase_b_reopened_same_state_root',
      'bootstrap_barrier_reset_before_session_activation',
      'epoch_bound_registry_cleared_exactly_once',
      'stable_account_profile_preserved',
      'replacement_identity_visible_without_old_did',
    ],
  );
}

Future<void> _writeCrashCutHandoff(
  String path,
  Map<String, Object?> payload,
) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final temporary = File('$path.tmp');
  await temporary.writeAsString(jsonEncode(payload), flush: true);
  await temporary.rename(path);
  if (!Platform.isWindows) {
    await Process.run('chmod', <String>['600', path]);
  }
}

Future<void> _waitForCompletedRecovery(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 8; attempt += 1) {
    await _pumpUntil(
      tester,
      () => !container.read(handleRecoveryProvider).isBusy,
      timeout: const Duration(minutes: 2),
      failure: 'A Recovery transition did not return control to the UI.',
    );
    final state = container.read(handleRecoveryProvider);
    _failOnRecoveryError(state, 'Recovery activation/resume');
    final progress = state.progress;
    if (progress?.isCompleted ?? false) return;
    if (progress == null || !progress.canResume) {
      fail('Recovery stopped in a non-resumable non-terminal phase.');
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

String _safeRecoveryActivationFailure(String? detail) {
  final value = detail ?? '';
  for (final code in AppBootstrapEpochBarrierFailureCode.values) {
    if (value.contains('AppBootstrapEpochBarrierFailure(${code.name})')) {
      return 'epoch_barrier_${code.name}';
    }
  }
  const knownCodes = <String>{
    'active_sync_account_binding_identity_mismatch',
    'local_identity_not_found',
    'session_transition_superseded',
  };
  for (final code in knownCodes) {
    if (value.contains(code)) return code;
  }
  return value.isEmpty ? 'none' : 'unclassified';
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

AwikiEnvironmentConfig _environment(_RemoteRecoveryRunConfig config) {
  return AwikiEnvironmentConfig(
    baseUrl: config.baseUrl,
    userServiceUrl: config.userServiceUrl,
    messageServiceUrl: config.messageServiceUrl,
    mailServiceUrl: config.mailServiceUrl,
    didDomain: config.didDomain,
    anpServiceUrl: config.anpServiceUrl,
    anpServiceDid: config.anpServiceDid,
    multiDeviceHandleRecoveryEnabled: true,
  );
}

Future<({String otp, DateTime retryAt})> _requestAndResolveRegistrationOtp({
  required OnboardingSupportService onboardingSupport,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String handle,
}) async {
  for (var attempt = 0; attempt < 3; attempt += 1) {
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
    } on RegistrationOtpRateLimited catch (error) {
      if (attempt == 2 || error.retryAfterSeconds > 120) {
        fail('The registration OTP request remained rate limited.');
      }
      await Future<void>.delayed(
        Duration(seconds: error.retryAfterSeconds + 1),
      );
    } on Object {
      fail('The registration OTP request failed safely.');
    }
  }
  fail('The registration OTP request exhausted its retry budget.');
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
  final peerShell = find.descendant(
    of: peerRoot,
    matching: find.byType(AppShell),
  );
  await _pumpUntil(
    tester,
    () => peerShell.evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'The fenced peer App did not restore before registration re-Join.',
  );
  unawaited(
    Navigator.of(tester.element(peerShell)).push<void>(
      CupertinoPageRoute<void>(builder: (_) => const OnboardingPage()),
    ),
  );
  final onboardingPage = find.descendant(
    of: peerRoot,
    matching: find.byType(OnboardingPage),
  );
  await _pumpUntil(
    tester,
    () => onboardingPage.evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'The fenced peer App did not open registration onboarding.',
  );
  final container = ProviderScope.containerOf(tester.element(onboardingPage));
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
  http.Response? response;
  for (var attempt = 0; attempt < 3; attempt += 1) {
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
  if (response == null || response.statusCode != 200) {
    fail('The purpose-bound OTP request was rejected.');
  }
  return DateTime.now().toUtc().add(const Duration(seconds: 60));
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
    await _pumpUntil(
      tester,
      () =>
          find
              .descendant(of: peerRoot, matching: find.byType(AppShell))
              .evaluate()
              .length ==
          1,
      timeout: const Duration(seconds: 45),
      failure: 'The old peer App did not restore its local session.',
    );
    unawaited(
      openDeviceJoinPage(
        tester.element(
          find.descendant(of: peerRoot, matching: find.byType(AppShell)),
        ),
      ),
    );
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
  unawaited(openDeviceJoinPage(tester.element(onboarding)));
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
  if (messaging == null) {
    fail('The old peer App did not expose remote messaging.');
  }
  try {
    await messaging.sendText(
      thread: AppThreadRef.direct(targetDid),
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
    await peerBootstrap.messageSyncService!.syncNow(
      reason: 'handle-recovery-registration-root-transfer',
      limit: 100,
    );
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

  await _activatePeerIdentity(
    peerBootstrap,
    identityId: externalIdentityId,
    expectedDid: externalDid,
  );
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

Future<void> _syncAndWaitForAppThreadExactOne({
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
    await sync.syncNow(reason: 'handle-recovery-rejoin-e2e', limit: 100);
    final messages = await messaging.loadHistory(thread, limit: 30);
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
      final stable = await messaging.loadHistory(thread, limit: 30);
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
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 550));
  }
  fail('An App did not converge the exact thread message.');
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

String _required(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! String || value.trim().isEmpty) {
    throw StateError('Missing run config value $key.');
  }
  return value.trim();
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
