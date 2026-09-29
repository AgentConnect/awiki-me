import 'package:awiki_me/src/presentation/onboarding/registration_entry_provider.dart';
// Real native Core and reviewed test tenant; exact invitation provisioning
// and database cleanup belong to the invoking private acceptance fixture.
import 'dart:convert';
import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/data/services/method_channel_desktop_startup_presentation_service.dart';
import 'package:awiki_me/src/application/device_management_service.dart';
import 'package:awiki_me/src/application/message_sync_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/tenant/builtin_tenant_config.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';
import '../../remote_target.dart';
import '../../delete_isolated_directory.dart';
import '../../e2e_user_presence_port.dart';

const String _registrationCaseId = 'REGISTRATION-ACCOUNT-FIRST-E2E-001';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeBuiltinTenantCatalog);
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );
  testWidgets(
    'real invited short Handle registration and existing-account reentry',
    (tester) async {
      final path =
          Platform.environment['AWIKI_REGISTRATION_FIXTURE'] ??
          const String.fromEnvironment('AWIKI_REGISTRATION_FIXTURE');
      expect(
        path.isNotEmpty,
        isTrue,
        reason: 'Explicit disposable fixture required',
      );
      final fixture =
          jsonDecode(await e2eRuntimeFile(path).readAsString())
              as Map<String, dynamic>;
      final threeDid = await _runInvitedHandleJoin(
        tester,
        fixture,
        handle: fixture['handle'] as String,
        invite: fixture['inviteCode'] as String,
        expectedLength: 3,
      );
      final fourDid = await _runInvitedHandleJoin(
        tester,
        fixture,
        handle: fixture['fourCharHandle'] as String,
        invite: fixture['fourCharInviteCode'] as String,
        expectedLength: 4,
      );
      await _runExistingHandleRecovery(
        tester,
        fixture,
        handle: fixture['handle'] as String,
        previousDid: threeDid,
      );
      await _runExistingHandleRecovery(
        tester,
        fixture,
        handle: fixture['fourCharHandle'] as String,
        previousDid: fourDid,
      );
      await E2eCaseAttestationWriter.markPassed(
        _registrationCaseId,
        phases: const <String>[
          'isolated_native_scopes',
          'short_handle_invite_required',
          'real_scoped_otp',
          'real_native_registration',
          'existing_account_join_choice',
          'existing_account_member_join_completed',
          'four_character_registration_and_join_completed',
          'three_character_recovery_completed',
          'four_character_recovery_completed',
        ],
      );
    },
  );
}

AwikiEnvironmentConfig _remoteRegistrationEnvironment(
  Map<String, dynamic> fixture,
) {
  final origin = fixture['userServiceUrl'] as String;
  final domain = fixture['domain'] as String;
  validateRegistrationFixtureTarget(didDomain: domain, userServiceUrl: origin);
  return AwikiEnvironmentConfig(
    baseUrl: origin,
    userServiceUrl: origin,
    didDomain: domain,
    messageServiceUrl: origin,
    mailServiceUrl: origin,
    anpServiceUrl: '$origin/anp-im/rpc',
    anpServiceDid: 'did:wba:$domain',
    caBundle: fixture['caBundle'] as String?,
    agentImEnabled: false,
  );
}

Future<String> _runInvitedHandleJoin(
  WidgetTester tester,
  Map<String, dynamic> fixture, {
  required String handle,
  required String invite,
  required int expectedLength,
}) async {
  final url = fixture['userServiceUrl'] as String;
  final domain = fixture['domain'] as String;
  validateRegistrationFixtureTarget(didDomain: domain, userServiceUrl: url);
  final phone = fixture['phone'] as String;
  final otp = fixture['otp'] as String;
  expect(handle.length, expectedLength);
  final roots = <Directory>[];
  AppBootstrap? bootstrap;
  AppBootstrap? admin;
  String? adminDid;
  final presence = E2eUserPresencePort();
  try {
    for (final existing in [false, true]) {
      final root = await Directory.systemTemp.createTemp(
        'awiki_registration_native_',
      );
      roots.add(root);
      bootstrap = await AppBootstrap.create(
        environment: _remoteRegistrationEnvironment(fixture),
        appStateRoot: root.path,
      );
      if (!Platform.isIOS && !Platform.isAndroid) {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
      }
      await tester.pumpWidget(
        AwikiMeApp(
          bootstrap: bootstrap,
          providerOverrides: [
            desktopStartupPresentationServiceProvider.overrideWithValue(
              buildDesktopStartupPresentationService(),
            ),
            userPresencePortProvider.overrideWithValue(presence),
          ],
        ),
      );
      await _until(
        tester,
        () => find.byType(OnboardingPage).evaluate().isNotEmpty,
        'Onboarding visible in isolated native scope',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      final labels = tester.element(find.byType(OnboardingPage)).l10n;
      await _until(
        tester,
        () => container.read(onboardingProvider).serverInfo != null,
        'Real User Service capabilities loaded',
      );
      await _enter(tester, 'e2e-handle-input', handle);
      expect(find.bySemanticsIdentifier('e2e-send-otp-button'), findsOneWidget);
      expect(find.bySemanticsIdentifier('e2e-phone-input'), findsOneWidget);
      await _enter(tester, 'e2e-phone-input', phone);
      if (!existing) {
        await _tap(tester, find.bySemanticsIdentifier('e2e-send-otp-button'));
        await _until(
          tester,
          () => find
              .bySemanticsIdentifier('e2e-invite-input')
              .evaluate()
              .isNotEmpty,
          '$expectedLength-character invitation required',
        );
        expect(find.bySemanticsIdentifier('e2e-handle-input'), findsOneWidget);
        expect(
          find.text(labels.onboardingShortHandleInviteHint),
          findsOneWidget,
        );
        expect(find.bySemanticsIdentifier('e2e-phone-input'), findsOneWidget);
        await _enter(tester, 'e2e-invite-input', invite);
      }
      await _until(
        tester,
        () =>
            find.bySemanticsIdentifier('e2e-phone-input').evaluate().isNotEmpty,
        'Contact verification follows account admission',
        diagnostic: () {
          final entry = container.read(registrationEntryProvider);
          final field = find.descendant(
            of: find.bySemanticsIdentifier('e2e-invite-input'),
            matching: find.byType(CupertinoTextField),
          );
          final fieldMatches =
              field.evaluate().isNotEmpty &&
              (field.evaluate().single.widget as CupertinoTextField)
                      .controller
                      ?.text ==
                  invite;
          return 'step=${entry.step.name} error=${entry.error ?? "none"} '
              'decision=${entry.check?.decision ?? "none"} '
              'inviteStatus=${entry.check?.inviteStatus ?? "none"} '
              'busy=${entry.busy} '
              'fieldCount=${field.evaluate().length} '
              'fieldMatches=$fieldMatches '
              'stateMatches=${entry.inviteCode == invite} '
              'clientVersion=${bootstrap!.userServiceHttpClient?.clientVersionHeader ?? "none"}';
        },
      );
      expect(
        find.bySemanticsIdentifier('e2e-invite-input'),
        existing ? findsNothing : findsOneWidget,
      );
      if (existing) {
        expect(find.bySemanticsIdentifier('e2e-invite-input'), findsNothing);
        await _tap(tester, find.bySemanticsIdentifier('e2e-send-otp-button'));
      }
      await _until(
        tester,
        () =>
            container.read(onboardingProvider).otpTargetFullHandle ==
            '$handle.$domain',
        'Real scoped OTP receipt accepted',
      );
      await _enter(tester, 'e2e-otp-input', otp);
      expect(container.read(onboardingProvider).canSubmitPhoneOtp, isTrue);
      expect(container.read(onboardingProvider).isBusy, isFalse);
      await _tap(tester, _visiblePhoneSubmitAction());
      if (existing) {
        await _until(
          tester,
          () => find
              .byKey(const Key('existing-handle-join-action'))
              .evaluate()
              .isNotEmpty,
          'Existing short account reaches authenticated Join choice without invitation',
        );
        expect(
          find.byKey(const Key('existing-handle-recovery-action')),
          findsOneWidget,
        );
        await _tap(
          tester,
          find.byKey(const Key('existing-handle-join-action')),
        );
        await _until(
          tester,
          () => find.byKey(const Key('device-join-page')).evaluate().isNotEmpty,
          'Existing-account continuation opens real Join',
        );
        await _completeMemberJoin(
          tester,
          container,
          admin!,
          adminDid!,
          presence,
        );
      } else {
        await _until(
          tester,
          () => container.read(sessionProvider).session != null,
          'Native Core completes real invited registration',
          diagnostic: () {
            final feedback = container.read(uiFeedbackProvider);
            final visibleText = find
                .byType(Text)
                .evaluate()
                .map((element) => (element.widget as Text).data ?? '')
                .join(' | ');
            return '${container.read(onboardingProvider).phoneRegistrationFailureCode}; ${feedback?.message.id}: ${feedback?.message.detail ?? feedback?.detail ?? ""}; $visibleText'
                .replaceAll(invite, '<invite>')
                .replaceAll(phone, '<phone>')
                .replaceAll(handle, '<handle>')
                .replaceAll(otp, '<otp>');
          },
        );
        expect(
          container
              .read(sessionProvider)
              .session!
              .did
              .startsWith('did:wba:$domain:'),
          isTrue,
        );
        adminDid = container.read(sessionProvider).session!.did;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (existing) {
        await bootstrap.dispose();
      } else {
        admin = bootstrap;
      }
      bootstrap = null;
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap?.dispose();
    await admin?.dispose();
    for (final root in roots) {
      await deleteIsolatedDirectory(root);
    }
  }
  return adminDid!;
}

Future<void> _runExistingHandleRecovery(
  WidgetTester tester,
  Map<String, dynamic> fixture, {
  required String handle,
  required String previousDid,
}) async {
  final domain = fixture['domain'] as String;
  final phone = fixture['phone'] as String;
  final otp = fixture['otp'] as String;
  final root = await Directory.systemTemp.createTemp('awiki_recovery_native_');
  final presence = E2eUserPresencePort();
  final bootstrap = await AppBootstrap.create(
    environment: _remoteRegistrationEnvironment(fixture),
    appStateRoot: root.path,
  );
  try {
    await tester.pumpWidget(
      AwikiMeApp(
        bootstrap: bootstrap,
        providerOverrides: [
          desktopStartupPresentationServiceProvider.overrideWithValue(
            buildDesktopStartupPresentationService(),
          ),
          userPresencePortProvider.overrideWithValue(presence),
        ],
      ),
    );
    await _until(
      tester,
      () => find.byType(OnboardingPage).evaluate().isNotEmpty,
      'Recovery starts in a new scope',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    await _until(
      tester,
      () => container.read(onboardingProvider).serverInfo != null,
      'Recovery tenant capabilities loaded',
    );
    await _enter(tester, 'e2e-handle-input', handle);
    await _enter(tester, 'e2e-phone-input', phone);
    await _tap(tester, find.bySemanticsIdentifier('e2e-send-otp-button'));
    await _until(
      tester,
      () => find.bySemanticsIdentifier('e2e-phone-input').evaluate().isNotEmpty,
      'Existing short account goes directly to contact verification',
    );
    expect(find.bySemanticsIdentifier('e2e-invite-input'), findsNothing);
    await _until(
      tester,
      () =>
          container.read(onboardingProvider).otpTargetFullHandle ==
          '$handle.$domain',
      'Existing account OTP is scoped',
    );
    await _enter(tester, 'e2e-otp-input', otp);
    await _tap(tester, _visiblePhoneSubmitAction());
    await _until(
      tester,
      () => find
          .byKey(const Key('existing-handle-recovery-action'))
          .evaluate()
          .isNotEmpty,
      'Authenticated existing-account Recovery choice',
    );
    await _until(
      tester,
      () => container.read(smsOtpCooldownProvider).canSend,
      'Respect the accepted OTP cooldown before Recovery',
    );
    await _tap(
      tester,
      find.byKey(const Key('existing-handle-recovery-action')),
    );
    await _until(
      tester,
      () => find.byKey(const Key('handle-recovery-page')).evaluate().isNotEmpty,
      'Recovery page opens from the account-first flow',
    );
    final recovery = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('handle-recovery-page'))),
    );
    String diagnostic() =>
        'recovery_error=${recovery.read(handleRecoveryProvider).error}; '
        'phase=${recovery.read(handleRecoveryProvider).progress?.phase}';
    await _until(
      tester,
      () {
        final state = recovery.read(handleRecoveryProvider);
        return !state.isBusy &&
            state.otpRequested &&
            state.otpOperationId != null;
      },
      'Recovery accepts a separate operation-bound OTP',
      diagnostic: diagnostic,
    );
    final otpField = find.descendant(
      of: find.byKey(const Key('handle-recovery-otp')),
      matching: find.byType(CupertinoTextField),
    );
    await tester.ensureVisible(otpField);
    await tester.enterText(otpField, otp);
    await _tap(tester, find.bySemanticsIdentifier('handle-recovery-verify'));
    await _until(
      tester,
      () {
        final state = recovery.read(handleRecoveryProvider);
        return !state.isBusy &&
            state.progress?.phase == HandleRecoveryProgressPhase.prepared;
      },
      'Recovery reaches the prepared phase',
      diagnostic: diagnostic,
    );
    final operationId = recovery
        .read(handleRecoveryProvider)
        .progress!
        .operationId;
    await _tap(
      tester,
      find.byKey(const Key('handle-recovery-risk-confirmation')),
    );
    expect(recovery.read(handleRecoveryProvider).riskConfirmed, isTrue);
    HandleRecoveryProgress? observed;
    final subscription = recovery.listen(handleRecoveryProvider, (_, state) {
      if (state.progress != null) observed = state.progress;
    }, fireImmediately: true);
    try {
      await _tap(
        tester,
        find.bySemanticsIdentifier('handle-recovery-activate'),
      );
      await _until(
        tester,
        () => observed?.isCompleted == true,
        'Recovery finishes the same durable operation',
        diagnostic: diagnostic,
      );
      expect(observed!.operationId, operationId);
      final reset = observed!.registryEpochReset!;
      expect(reset.previousDid, previousDid);
      expect(reset.currentDid == previousDid, isFalse);
      expect(reset.handle, '$handle.$domain');
      expect(reset.sourceKind, HandleRecoveryTransitionSourceKind.initiator);
      await _until(
        tester,
        () => container.read(sessionProvider).session?.did == reset.currentDid,
        'Recovered identity becomes the active App session',
      );
      final identities = await bootstrap.appSessionService!
          .listLocalIdentities();
      expect(identities.length, 1);
      expect(identities.single.did, reset.currentDid);
      expect(identities.single.handle, '$handle.$domain');
      final registry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(reset.currentDid);
      expect(registry.currentDevice!.status, DeviceStatus.active);
      expect(registry.currentDevice!.role, DeviceRole.admin);
      expect(registry.currentDevice!.managementReady, isTrue);
      expect(presence.completions, 1);
    } finally {
      subscription.close();
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await bootstrap.dispose();
    await deleteIsolatedDirectory(root);
  }
}

Future<void> _completeMemberJoin(
  WidgetTester tester,
  ProviderContainer joining,
  AppBootstrap admin,
  String adminDid,
  E2eUserPresencePort presence,
) async {
  await _until(
    tester,
    () => joining.read(devicesProvider).activeJoin != null,
    'New-device Join session persisted',
  );
  final sessionId = joining.read(devicesProvider).activeJoin!.joinSessionId;
  final joiningDeviceId = joining
      .read(devicesProvider)
      .activeJoin!
      .protocolDeviceId;
  final port = admin.deviceManagementCorePort!;
  final service = DeviceManagementService(core: port, userPresence: presence);
  var started = false;
  DeviceJoinProgress? verified;
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    // The peer drives the same public Core receive/process API as an admin
    // client; no Registry polling substitutes for the delivered Join notice.
    final receiver = admin.messageSyncService! as MessageReceiveService;
    final processing = await receiver.openProcessingSession();
    try {
      final received = await receiver.receiveNow(reason: 'manual_refresh');
      expect(
        received.errorCode,
        isNull,
        reason: 'Admin receives real service events',
      );
      final processed = await processing.waitUntilSettled();
      expect(
        processed.errorCode,
        isNull,
        reason: 'Admin processes received Join events',
      );
    } finally {
      await processing.close();
    }
    // Consume committed notices to advance the admin state before reading SAS.
    final notices = await port.localDeviceJoinRequests(adminDid);
    if (!started) {
      if (notices.any(
        (notice) =>
            notice.joinSessionId == sessionId && notice.canStartVerification,
      )) {
        await service.startVerification(
          selector: adminDid,
          joinSessionId: sessionId,
          operationId:
              'registration-join-${DateTime.now().microsecondsSinceEpoch}',
          challengeTtlSeconds: 120,
        );
        started = true;
      }
    } else {
      await joining.read(devicesProvider.notifier).pollNewDeviceActive();
      expect(joining.read(devicesProvider).error, isNull);
      final DeviceJoinProgress progress;
      try {
        progress = await port.localDeviceJoinVerificationProgress(
          selector: adminDid,
          joinSessionId: sessionId,
        );
      } on core.AwikiImCoreException catch (error) {
        if (error.code != 'local_state_unavailable' ||
            !error.message.contains(
              'admin Join verification progress is not available',
            )) {
          rethrow;
        }
        await tester.pump(const Duration(milliseconds: 200));
        continue;
      }
      if (progress.phase == DeviceJoinPhase.responseVerified) {
        verified = progress;
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(started, isTrue, reason: 'Admin received the real Join notification');
  expect(verified != null, isTrue, reason: 'Real challenge/response completed');
  await _until(
    tester,
    () => joining.read(devicesProvider).activeJoin?.sas != null,
    'New device displays the SAS',
  );
  expect(
    verified!.sas == joining.read(devicesProvider).activeJoin!.sas,
    isTrue,
    reason: 'Both independently generated SAS values must match',
  );
  final approved = await service.approveAsMember(
    selector: adminDid,
    progress: verified,
    displayedSas: verified.sas!,
    sasConfirmed: true,
    presenceReason: 'Approve disposable registration acceptance device',
  );
  expect(approved.phase, DeviceJoinPhase.authorized);
  await _until(
    tester,
    () => joining.read(sessionProvider).session?.did == adminDid,
    'Joining App activates the same account',
    diagnostic: () {
      final state = joining.read(devicesProvider);
      return 'phase=${state.activeJoin?.phase}; error=${state.error}; '
          'feedback=${joining.read(uiFeedbackProvider)?.message.id}';
    },
  );
  final registry = await port.identityDeviceRegistry(adminDid);
  final members = registry.devices
      .where(
        (device) =>
            device.role == DeviceRole.member &&
            device.status == DeviceStatus.active,
      )
      .toList();
  expect(members.length, 1);
  expect(members.single.protocolDeviceId, joiningDeviceId);
  expect(presence.completions, greaterThan(0));
}

Future<void> _enter(WidgetTester tester, String id, String text) async {
  final field = find.descendant(
    of: find.bySemanticsIdentifier(id),
    matching: find.byType(CupertinoTextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Finder _visiblePhoneSubmitAction() {
  final desktop = find.byKey(const Key('onboarding-mac-phone-submit-action'));
  return desktop.evaluate().isNotEmpty
      ? desktop
      : find.byKey(const Key('onboarding-phone-submit-action'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _until(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'Registration control becomes hit-testable',
  );
  await tester.tap(finder.hitTestable());
  await tester.pump();
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason, {
  String Function()? diagnostic,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: '$reason ${ready() ? "" : diagnostic?.call() ?? ""}',
  );
}
