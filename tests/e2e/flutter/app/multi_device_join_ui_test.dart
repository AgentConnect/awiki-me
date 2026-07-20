// [INPUT]: Audited awiki.info endpoints, a dedicated account/SSH OTP resolver,
//          production AppBootstrap/native Core, and an independent public CLI root.
// [OUTPUT]: Real App-admin UI evidence for SAS comparison, one native
//           user-presence prompt, and default-member Join authorization.
// [POS]: Activation-gated remote product E2E; no fake port, copied state,
//        static OTP, or secret-bearing report is permitted.

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
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_approval_sheet.dart';
import 'package:awiki_me/src/presentation/devices/devices_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';

import '../../case_attestation.dart';
import '../../remote_multi_device_join_contract.dart';

const String _caseId = 'DEVICE-JOIN-E2E-002';
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
    'real AWiki Me ready admin approves an independent CLI device as member',
    (tester) async {
      final config = _RemoteJoinRunConfig.load();
      final account = _DedicatedAccount.fromEnvironment(
        allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
      );
      final httpClient = http.Client();
      final presence = _CountingRealUserPresencePort();
      final cli = _JoiningCli(config);
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

      final environment = AwikiEnvironmentConfig(
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
        _caseId,
        phases: const <String>[
          'independent_native_devices_bootstrapped',
          'otp_left_join_pending',
          'sas_matched_without_secret_evidence',
          'single_real_user_presence_confirmed',
          'joined_device_active_member_not_admin',
        ],
      );
    },
    skip: !Platform.isMacOS || !_RemoteJoinRunConfig.exists(),
    timeout: const Timeout(Duration(minutes: 14)),
  );
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
    required this.appStateRoot,
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
  final String appStateRoot;

  static bool exists() => File(_runConfigPath).existsSync();

  static _RemoteJoinRunConfig load() {
    if (Platform.environment[_activationGate]?.trim() != '1') {
      throw StateError(
        'Remote multi-device App Join is not explicitly enabled.',
      );
    }
    final file = File(_runConfigPath);
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map ||
        decoded['schemaVersion'] != 1 ||
        decoded['enabled'] != true) {
      throw StateError('Remote multi-device Join run config is invalid.');
    }
    final root = _stringMap(decoded);
    final service = _map(root, 'service');
    final account = _map(root, 'account');
    final cli = _map(root, 'cliJoiningDevice');
    final app = _map(root, 'app');
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
      appStateRoot: _required(app, 'stateRoot'),
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
  _JoiningCli(this.config);

  final _RemoteJoinRunConfig config;
  late final String _tenantName = 'e2e-${_safeId(config.runId, 36)}';

  Future<void> initialize() async {
    await Directory(config.cliWorkspace).create(recursive: true);
    await Directory(config.cliHome).create(recursive: true);
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
      fail('The joining CLI device returned no safe Registry projection.');
    }
    return (result['devices'] as List)
        .map((value) {
          if (value is! Map) {
            fail('The joining CLI Registry contains an invalid device row.');
          }
          return _stringMap(value);
        })
        .toList(growable: false);
  }

  Future<Map<String, Object?>> _run(
    List<String> args, {
    String? accountVerificationToken,
  }) async {
    final environment = <String, String>{
      'HOME': config.cliHome,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
      'AWIKI_MULTI_DEVICE_JOIN_ENABLED': '1',
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
    ]) {
      final value = Platform.environment[name];
      if (value != null && value.trim().isNotEmpty) {
        environment[name] = value;
      }
    }
    ProcessResult result;
    try {
      result = await Process.run(
        config.cliBin,
        args,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: false,
      ).timeout(_remoteTimeout);
    } on Object {
      fail('The independent joining CLI process did not complete safely.');
    }
    if (result.exitCode != 0) {
      fail(
        'The independent joining CLI command failed without exposing output.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(result.stdout.toString());
    } on Object {
      fail('The independent joining CLI returned invalid JSON.');
    }
    if (decoded is! Map || decoded['ok'] != true) {
      fail('The independent joining CLI returned no successful result.');
    }
    return _stringMap(decoded);
  }

  Future<void> deleteLocalState() async {
    for (final path in <String>[config.cliWorkspace, config.cliHome]) {
      final directory = Directory(path);
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  }
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
    evaluateRemoteMultiDeviceSmsResponse(
      statusCode: response.statusCode,
      contentType: response.headers['content-type'],
      body: response.body,
      allowStagedOtpOnSmsError: config.allowStagedOtpOnSmsError,
    );
  } on FormatException {
    fail('The purpose-bound OTP request was rejected.');
  }
  return _resolveOtp(
    account: account,
    purpose: purpose,
    handle: handle,
    didDomain: config.didDomain,
  );
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
  final roots = <String>{
    Directory(config.appStateRoot).absolute.path,
    Directory(config.cliWorkspace).absolute.path,
    Directory(config.cliHome).absolute.path,
  };
  if (roots.length != 3) {
    fail('The App and CLI did not receive independent local roots.');
  }
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync() ||
        directory.listSync(followLinks: false).isNotEmpty) {
      fail('A multi-device E2E local root was missing or not fresh.');
    }
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
