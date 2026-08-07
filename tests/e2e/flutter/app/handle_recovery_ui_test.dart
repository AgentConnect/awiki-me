// [INPUT]: Audited awiki.info endpoints, one dedicated SMS account and OTP
//          resolver, a fresh production AppBootstrap/native Core root, and an
//          E2E-only user-presence decision.
// [OUTPUT]: Secret-free proof that the visible Handle Recovery V4 flow keeps
//           the Handle, replaces the DID, and fences the old local identity.
// [POS]: Remote product UI acceptance; setup may register through the
//        production application service, but Recovery itself is UI-driven.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_provider.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yaml/yaml.dart';

import '../../case_attestation.dart';
import '../../e2e_user_presence_port.dart';
import '../../remote_multi_device_join_contract.dart';

const String _caseId = 'HANDLE-RECOVERY-V1-E2E-001';
const String _runConfigPath =
    '.e2e/multi-device-remote-recovery/current/run_config.json';
const String _activationGate = 'AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED';
const String _phoneEnv = 'AWIKI_MULTI_DEVICE_E2E_PHONE';
const String _otpCommandEnv = 'AWIKI_MULTI_DEVICE_E2E_OTP_COMMAND_JSON';
const String _registrationPurpose = 'awiki.identity.register.v1';
const String _recoveryPurpose = 'awiki.identity.handle-recovery.v1';
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
      AppBootstrap? bootstrap;
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      _requireFreshRoot(config.appStateRoot);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await bootstrap?.dispose();
        await _deleteDirectory(config.appStateRoot);
        await tester.binding.setSurfaceSize(null);
      });

      bootstrap = await AppBootstrap.create(
        environment: _environment(config),
        appStateRoot: config.appStateRoot,
      );
      final recoveryCore = bootstrap.handleRecoveryCorePort;
      if (recoveryCore == null) {
        fail('The production Handle Recovery Core port was unavailable.');
      }
      final recordingRecoveryCore = _RecordingHandleRecoveryCorePort(
        recoveryCore,
      );
      final bareHandle = _uniqueHandle(config.handlePrefix);
      final onboardingSupport = bootstrap.onboardingSupportService;
      if (onboardingSupport == null) {
        fail('The production onboarding support service was unavailable.');
      }
      final registrationOtp = await _requestAndResolveRegistrationOtp(
        onboardingSupport: onboardingSupport,
        config: config,
        account: account,
        handle: bareHandle,
      );
      final registration = await bootstrap.onboardingService!
          .registerHandleWithPhone(
            phone: account.phone,
            otp: registrationOtp,
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
      final stableCredentialName =
          oldSession.localAlias ?? oldSession.identityId;
      final fullHandle = oldSession.handle!.trim().toLowerCase();
      final initialRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(oldDid);
      _requireReadyCurrentAdmin(initialRegistry, expectedDid: oldDid);

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
      final container = await _waitForAuthenticatedApp(
        tester,
        expectedDid: oldDid,
      );
      await container.read(appRuntimeProvider.notifier).logout();
      await _pumpUntil(
        tester,
        () => find.byType(OnboardingPage).evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure: 'Logout did not return to the real onboarding surface.',
      );
      final recoveryEntry = find.bySemanticsIdentifier(
        'handle-recovery-entry:$stableCredentialName',
      );
      await _pumpUntil(
        tester,
        () => recoveryEntry.evaluate().length == 1,
        timeout: const Duration(seconds: 45),
        failure:
            'The identity-scoped Handle Recovery entry did not become visible.',
      );
      await _tapOne(
        tester,
        recoveryEntry,
        failure:
            'The visible identity-scoped Handle Recovery entry was unavailable.',
      );
      await _pumpUntil(
        tester,
        () => find.byType(HandleRecoveryPage).evaluate().length == 1,
        failure: 'The visible Handle Recovery page did not open.',
      );

      await _enterTextByKey(
        tester,
        const Key('handle-recovery-handle'),
        fullHandle,
      );
      await _enterTextByKey(
        tester,
        const Key('handle-recovery-phone'),
        account.phone,
      );
      await _tapOne(
        tester,
        find.bySemanticsIdentifier('handle-recovery-send-otp'),
        failure: 'The Handle Recovery OTP action was unavailable.',
      );
      await _pumpUntil(
        tester,
        () {
          final state = container.read(handleRecoveryProvider);
          _failOnRecoveryError(state, 'OTP request');
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
      if (recordingRecoveryCore.requestedLocalIdentityId !=
          oldSession.identityId) {
        fail('Handle Recovery did not preserve the exact local identity ID.');
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
      final replacement = localIdentities
          .where(
            (identity) =>
                (identity.localAlias ?? identity.identityId) ==
                stableCredentialName,
          )
          .toList(growable: false);
      if (replacement.length != 1 ||
          replacement.single.did != reset.currentDid ||
          replacement.single.did == oldDid ||
          replacement.single.handle?.trim().toLowerCase() != fullHandle ||
          localIdentities.any((identity) => identity.did == oldDid)) {
        fail('The local identity inventory did not fence the replaced DID.');
      }
      final finalRegistry = await bootstrap.deviceManagementCorePort!
          .identityDeviceRegistry(reset.currentDid);
      _requireReadyCurrentAdmin(finalRegistry, expectedDid: reset.currentDid);

      await E2eCaseAttestationWriter.markPassed(
        _caseId,
        startedAt: startedAt,
        phases: const <String>[
          'existing_ready_admin_created',
          'recovery_entry_advertised_and_opened',
          'operation_bound_otp_prepared_through_ui',
          'irreversible_risks_confirmed_through_ui',
          'recovery_completed_through_ui_resume',
          'stable_owner_handle_and_replacement_did_verified',
          'old_identity_fenced_from_local_projection',
        ],
      );
    },
    skip:
        !Platform.isMacOS ||
        !_RemoteRecoveryRunConfig.exists() ||
        !_invocationExpects(_caseId),
    timeout: const Timeout(Duration(minutes: 15)),
  );
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

class _RecordingHandleRecoveryCorePort implements HandleRecoveryCorePort {
  _RecordingHandleRecoveryCorePort(this._delegate);

  final HandleRecoveryCorePort _delegate;
  String? lastSafeFailure;
  String? requestedLocalIdentityId;

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
        _ => 'type=${_safeDiagnosticToken(error.runtimeType.toString())}',
      };
      rethrow;
    }
  }

  @override
  Future<HandleRecoveryOtpResult> requestOtp({
    required HandleRecoveryOwner owner,
    required String phone,
  }) {
    requestedLocalIdentityId = owner.localIdentityId;
    return _record(() => _delegate.requestOtp(owner: owner, phone: phone));
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

Future<ProviderContainer> _waitForAuthenticatedApp(
  WidgetTester tester, {
  required String expectedDid,
}) async {
  await _pumpUntil(
    tester,
    () => find.byType(AppShell).evaluate().length == 1,
    timeout: const Duration(seconds: 45),
    failure: 'The authenticated App shell did not open.',
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(AppShell)),
  );
  await _pumpUntil(
    tester,
    () {
      final runtime = container.read(appRuntimeProvider);
      return runtime.isInitialized &&
          !runtime.isBusy &&
          runtime.activatedDid == expectedDid;
    },
    timeout: const Duration(seconds: 45),
    failure: 'The expected authenticated identity did not become active.',
  );
  return container;
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

Future<String> _requestAndResolveRegistrationOtp({
  required OnboardingSupportService onboardingSupport,
  required _RemoteRecoveryRunConfig config,
  required _DedicatedAccount account,
  required String handle,
}) async {
  for (var attempt = 0; attempt < 3; attempt += 1) {
    try {
      await onboardingSupport.sendRegistrationOtp(
        phone: account.phone,
        handle: handle,
        domain: config.didDomain,
        fullHandle: '$handle.${config.didDomain}',
      );
      return _resolveOtp(
        account: account,
        purpose: _registrationPurpose,
        handle: handle,
        didDomain: config.didDomain,
      );
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

Future<String> _resolveOtp({
  required _DedicatedAccount account,
  required String purpose,
  required String handle,
  required String didDomain,
  String? operationId,
}) async {
  final fixedOtp = account.fixedOtp;
  if (fixedOtp != null) return fixedOtp;
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
      'operation_id': operationId,
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
    required this.automatedUserPresence,
    required this.otpMode,
    this.localConfigPath,
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
  final bool automatedUserPresence;
  final String otpMode;
  final String? localConfigPath;
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
    final testControl = _map(root, 'testControl');
    final app = _map(root, 'app');
    final config = _RemoteRecoveryRunConfig(
      baseUrl: _required(service, 'baseUrl'),
      userServiceUrl: _required(service, 'userServiceUrl'),
      messageServiceUrl: _required(service, 'messageServiceUrl'),
      mailServiceUrl: _required(service, 'mailServiceUrl'),
      didDomain: _required(service, 'didDomain'),
      anpServiceUrl: _required(service, 'anpServiceUrl'),
      anpServiceDid: _required(service, 'anpServiceDid'),
      handlePrefix: _required(account, 'handlePrefix'),
      otpMode: _required(account, 'otpMode'),
      localConfigPath: _optional(account, 'localConfigPath'),
      automatedUserPresence: _requiredBool(
        testControl,
        'automatedUserPresence',
      ),
      appStateRoot: _required(app, 'stateRoot'),
    );
    if (!config.automatedUserPresence ||
        config.didDomain != 'awiki.info' ||
        !const <String>{
          'resolver',
          'ignored_local_fixture',
        }.contains(config.otpMode) ||
        (config.otpMode == 'ignored_local_fixture' &&
            config.localConfigPath == null)) {
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
  const _DedicatedAccount({
    required this.phone,
    required this.otpCommand,
    this.fixedOtp,
  });

  final String phone;
  final List<String> otpCommand;
  final String? fixedOtp;

  static _DedicatedAccount fromConfig(_RemoteRecoveryRunConfig config) {
    if (config.otpMode == 'ignored_local_fixture') {
      final path = config.localConfigPath!;
      final file = File(path);
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
      return _DedicatedAccount(
        phone: phone,
        otpCommand: const <String>[],
        fixedOtp: fixedOtp,
      );
    }
    final phone = Platform.environment[_phoneEnv]?.trim() ?? '';
    final encodedCommand = Platform.environment[_otpCommandEnv]?.trim() ?? '';
    if (phone.isEmpty || encodedCommand.isEmpty) {
      throw StateError('Dedicated Handle Recovery account is missing.');
    }
    final bool staged;
    try {
      staged = parseRemoteMultiDeviceStagedOtpFlag(Platform.environment);
    } on FormatException {
      throw StateError('Dedicated Handle Recovery SMS mode is invalid.');
    }
    if (staged) {
      throw StateError('Staged SMS errors cannot attest Handle Recovery.');
    }
    final List<String> command;
    try {
      command = parseRemoteMultiDeviceOtpCommand(
        encodedCommand,
        requireReviewedStagedResolver: false,
      );
    } on FormatException {
      throw StateError('Dedicated Handle Recovery OTP resolver is invalid.');
    }
    return _DedicatedAccount(
      phone: phone,
      otpCommand: List<String>.unmodifiable(command),
    );
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

String? _optional(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw StateError('Invalid optional run config value $key.');
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
