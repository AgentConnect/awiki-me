// [INPUT]: Ignored YAML, protected environment overrides, and selected E2E case.
// [OUTPUT]: Typed local/remote runner configuration with fail-closed prerequisites.
// [POS]: Test-only configuration boundary; does not execute scenarios or alter product config.

part of '../runner.dart';

class _RemoteMultiDeviceBaseConfig {
  const _RemoteMultiDeviceBaseConfig({
    required this.platform,
    required this.serviceBaseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.mailServiceUrl,
    required this.didDomain,
    required this.anpServiceUrl,
    required this.anpServiceDid,
    required this.phone,
    required this.fixedOtp,
    required this.handlePrefix,
  });

  final DesktopE2ePlatform platform;
  final String serviceBaseUrl;
  final String userServiceUrl;
  final String messageServiceUrl;
  final String mailServiceUrl;
  final String didDomain;
  final String anpServiceUrl;
  final String anpServiceDid;
  final String phone;
  final String fixedOtp;
  final String handlePrefix;

  static _RemoteMultiDeviceBaseConfig from({
    required DesktopE2eFileConfig fileConfig,
    required Map<String, String> environment,
    String activationGate = _multiDeviceRemoteJoinGateEnv,
    String flowLabel = 'Join',
    Set<DesktopE2ePlatform> supportedPlatforms = const <DesktopE2ePlatform>{
      DesktopE2ePlatform.macos,
    },
  }) {
    final sourcePath = fileConfig.path ?? '<missing-config>';
    if (fileConfig.path == null) {
      throw E2eFailure(
        'Remote multi-device $flowLabel config file was not found: $sourcePath',
      );
    }
    if (environment[activationGate]?.trim() != '1') {
      throw E2eFailure(
        'Remote multi-device App $flowLabel is disabled. Set '
        '$activationGate=1 only after the dedicated account '
        'allowlist and hidden server rollout are ready.',
      );
    }
    final platform = fileConfig.platform ?? DesktopE2ePlatform.fromHost();
    if (!supportedPlatforms.contains(platform)) {
      throw E2eFailure(
        'Remote multi-device App $flowLabel does not support '
        '${platform.name} on this runner.',
      );
    }
    final serviceBaseUrl = _requiredConfig(
      fileConfig.serviceBaseUrl,
      'service.baseUrl',
      sourcePath,
    );
    final didDomain = _requiredConfig(
      fileConfig.didDomain,
      'service.didDomain',
      sourcePath,
    );
    final localPhone = fileConfig.otpPhone?.trim() ?? '';
    final localOtp = fileConfig.otpCode?.trim() ?? '';
    if (localPhone.isEmpty || !isSixDigitAsciiOtp(localOtp)) {
      throw E2eFailure(
        'Remote multi-device App $flowLabel requires otp.phone and one '
        'six-digit otp.code in the protected ignored local YAML.',
      );
    }
    final handlePrefix =
        (environment[_multiDeviceRemoteHandlePrefixEnv] ?? 'appmd')
            .trim()
            .toLowerCase();
    if (handlePrefix.length > 20 ||
        !RegExp(
          r'^[a-z0-9](?:[a-z0-9-]{0,18}[a-z0-9])?$',
        ).hasMatch(handlePrefix)) {
      throw E2eFailure(
        'Remote multi-device App $flowLabel handle prefix is invalid.',
      );
    }
    return _RemoteMultiDeviceBaseConfig(
      platform: platform,
      serviceBaseUrl: serviceBaseUrl,
      userServiceUrl: fileConfig.userServiceUrl ?? serviceBaseUrl,
      messageServiceUrl: fileConfig.messageServiceUrl ?? serviceBaseUrl,
      mailServiceUrl: fileConfig.mailServiceUrl ?? serviceBaseUrl,
      didDomain: didDomain,
      anpServiceUrl: fileConfig.anpServiceUrl ?? '$serviceBaseUrl/anp-im/rpc',
      anpServiceDid: fileConfig.anpServiceDid ?? 'did:wba:$didDomain',
      phone: localPhone,
      fixedOtp: localOtp,
      handlePrefix: handlePrefix,
    );
  }
}

class RemoteHandleRecoveryConfig {
  const RemoteHandleRecoveryConfig._(
    this._base, {
    this.daemonBinary,
    this.daemonHandle,
  });

  final _RemoteMultiDeviceBaseConfig _base;

  DesktopE2ePlatform get platform => _base.platform;
  String get serviceBaseUrl => _base.serviceBaseUrl;
  String get userServiceUrl => _base.userServiceUrl;
  String get messageServiceUrl => _base.messageServiceUrl;
  String get mailServiceUrl => _base.mailServiceUrl;
  String get didDomain => _base.didDomain;
  String get anpServiceUrl => _base.anpServiceUrl;
  String get anpServiceDid => _base.anpServiceDid;
  String get phone => _base.phone;
  String get fixedOtp => _base.fixedOtp;
  String get handlePrefix => _base.handlePrefix;
  final String? daemonBinary;
  final String? daemonHandle;

  static RemoteHandleRecoveryConfig from({
    required DesktopE2eFileConfig fileConfig,
    required Map<String, String> environment,
  }) {
    final base = _RemoteMultiDeviceBaseConfig.from(
      fileConfig: fileConfig,
      environment: environment,
      activationGate: _multiDeviceRemoteRecoveryGateEnv,
      flowLabel: 'Handle Recovery',
      supportedPlatforms: const <DesktopE2ePlatform>{
        DesktopE2ePlatform.macos,
        DesktopE2ePlatform.linux,
      },
    );
    return RemoteHandleRecoveryConfig._(
      base,
      daemonBinary: fileConfig.daemonBinary,
      daemonHandle: fileConfig.daemonHandle,
    );
  }
}

class RemoteMultiDeviceAppPairConfig {
  const RemoteMultiDeviceAppPairConfig._(
    this._base, {
    required this.functional,
    required this.contentSync,
    this.cliBin,
    this.cliSourceRef,
    this.daemonBinary,
    this.daemonHandle,
    this.daemonEnvFile,
  });

  final _RemoteMultiDeviceBaseConfig _base;
  final bool functional;
  final bool contentSync;
  final String? cliBin;
  final String? cliSourceRef;
  final String? daemonBinary;
  final String? daemonHandle;
  final String? daemonEnvFile;

  DesktopE2ePlatform get platform => _base.platform;
  String get serviceBaseUrl => _base.serviceBaseUrl;
  String get userServiceUrl => _base.userServiceUrl;
  String get messageServiceUrl => _base.messageServiceUrl;
  String get mailServiceUrl => _base.mailServiceUrl;
  String get didDomain => _base.didDomain;
  String get anpServiceUrl => _base.anpServiceUrl;
  String get anpServiceDid => _base.anpServiceDid;
  String get phone => _base.phone;
  String get fixedOtp => _base.fixedOtp;
  String get handlePrefix => _base.handlePrefix;

  static RemoteMultiDeviceAppPairConfig from({
    required DesktopE2eFileConfig fileConfig,
    required Map<String, String> environment,
    bool functional = false,
    bool contentSync = false,
  }) {
    final base = _RemoteMultiDeviceBaseConfig.from(
      fileConfig: fileConfig,
      environment: environment,
      supportedPlatforms: const <DesktopE2ePlatform>{
        DesktopE2ePlatform.macos,
        DesktopE2ePlatform.linux,
      },
    );
    if (functional && contentSync) {
      throw E2eFailure('App-pair functional and content-sync modes conflict.');
    }
    if (!functional && !contentSync) {
      return RemoteMultiDeviceAppPairConfig._(
        base,
        functional: false,
        contentSync: false,
      );
    }
    final sourcePath = fileConfig.path ?? '<missing-config>';
    final cliBin = _requiredConfig(
      fileConfig.cliBin,
      'cliPeer.binary',
      sourcePath,
    );
    final cliSourceRef = _requiredConfig(
      fileConfig.cliSourceRef,
      'cliPeer.sourceRef',
      sourcePath,
    ).toLowerCase();
    if (!isAuditableGitSha(cliSourceRef)) {
      throw E2eFailure(
        'cliPeer.sourceRef must be the exact non-zero 40-character commit SHA embedded in the CLI binary.',
      );
    }
    return RemoteMultiDeviceAppPairConfig._(
      base,
      functional: functional,
      contentSync: contentSync,
      cliBin: cliBin,
      cliSourceRef: cliSourceRef,
      daemonBinary: functional
          ? _requiredConfig(
              fileConfig.daemonBinary,
              'daemon.binary',
              sourcePath,
            )
          : null,
      daemonHandle: functional
          ? _requiredConfig(
              fileConfig.daemonHandle,
              'daemon.handle',
              sourcePath,
            )
          : null,
      daemonEnvFile: functional ? fileConfig.daemonEnvFile : null,
    );
  }
}

class RemoteMultiDeviceJoinConfig {
  const RemoteMultiDeviceJoinConfig({
    required this.platform,
    required this.serviceBaseUrl,
    required this.userServiceUrl,
    required this.messageServiceUrl,
    required this.mailServiceUrl,
    required this.didDomain,
    required this.anpServiceUrl,
    required this.anpServiceDid,
    required this.phone,
    required this.fixedOtp,
    required this.handlePrefix,
    required this.cliBin,
    required this.cliSourceRef,
  });

  final DesktopE2ePlatform platform;
  final String serviceBaseUrl;
  final String userServiceUrl;
  final String messageServiceUrl;
  final String mailServiceUrl;
  final String didDomain;
  final String anpServiceUrl;
  final String anpServiceDid;
  final String phone;
  final String fixedOtp;
  final String handlePrefix;
  final String cliBin;
  final String cliSourceRef;

  static RemoteMultiDeviceJoinConfig from({
    required DesktopE2eFileConfig fileConfig,
    required Map<String, String> environment,
    Set<DesktopE2ePlatform> supportedPlatforms = const <DesktopE2ePlatform>{
      DesktopE2ePlatform.macos,
    },
  }) {
    final base = _RemoteMultiDeviceBaseConfig.from(
      fileConfig: fileConfig,
      environment: environment,
      supportedPlatforms: supportedPlatforms,
    );
    final sourcePath = fileConfig.path ?? '<missing-config>';
    final cliBin = _requiredConfig(
      fileConfig.cliBin,
      'cliPeer.binary',
      sourcePath,
    );
    final cliSourceRef = _requiredConfig(
      fileConfig.cliSourceRef,
      'cliPeer.sourceRef',
      sourcePath,
    );
    if (!isAuditableGitSha(cliSourceRef)) {
      throw E2eFailure(
        'cliPeer.sourceRef must be the exact non-zero 40-character commit SHA embedded in the CLI binary.',
      );
    }
    return RemoteMultiDeviceJoinConfig(
      platform: base.platform,
      serviceBaseUrl: base.serviceBaseUrl,
      userServiceUrl: base.userServiceUrl,
      messageServiceUrl: base.messageServiceUrl,
      mailServiceUrl: base.mailServiceUrl,
      didDomain: base.didDomain,
      anpServiceUrl: base.anpServiceUrl,
      anpServiceDid: base.anpServiceDid,
      phone: base.phone,
      fixedOtp: base.fixedOtp,
      handlePrefix: base.handlePrefix,
      cliBin: cliBin,
      cliSourceRef: cliSourceRef.toLowerCase(),
    );
  }
}

class DesktopCliPeerConfig implements DesktopRemoteTargetContract {
  DesktopCliPeerConfig({
    required this.platform,
    required this.serviceBaseUrl,
    required this.didDomain,
    required this.otpPhone,
    required this.otpCode,
    required this.appHandle,
    this.secondaryAppHandle,
    required this.cliHandle,
    required this.cliBin,
    required this.cliSourceRef,
    required this.e2eCase,
    required this.performance,
    this.userServiceUrl,
    this.messageServiceUrl,
    this.messageServiceWsUrl,
    this.mailServiceUrl,
    this.anpServiceUrl,
    this.anpServiceDid,
    this.daemonRustRepo,
    this.daemonBinary,
    this.daemonStateRoot,
    this.daemonReadyFile,
    this.daemonHandle,
    this.daemonEnvFile,
    this.daemonFakeHermesGatewayCommand,
    this.personalAgentEnabled = false,
    this.personalAgentRuntimeProvider = 'hermes',
    this.personalAgentProcessingScope = 'all_conversations',
    this.personalAgentRealBackend = false,
    this.codexAgentEnabled = false,
    this.codexAgentRealBackend = false,
    this.codexAgentPrompt,
    this.codexAgentExpectedReply,
    this.claudeCodeAgentEnabled = false,
    this.claudeCodeAgentRealBackend = false,
    this.claudeCodeAgentPrompt,
    this.claudeCodeAgentExpectedReply,
  });

  final DesktopE2ePlatform platform;
  @override
  final String serviceBaseUrl;
  @override
  final String didDomain;
  final String otpPhone;
  final String otpCode;
  final String appHandle;
  final String? secondaryAppHandle;
  final String cliHandle;
  final String cliBin;
  final String cliSourceRef;
  final DesktopE2eCase e2eCase;
  final DesktopPerformanceConfig performance;
  @override
  final String? userServiceUrl;
  @override
  final String? messageServiceUrl;
  @override
  final String? messageServiceWsUrl;
  final String? mailServiceUrl;
  final String? anpServiceUrl;
  final String? anpServiceDid;
  final String? daemonRustRepo;
  final String? daemonBinary;
  final String? daemonStateRoot;
  final String? daemonReadyFile;
  final String? daemonHandle;
  final String? daemonEnvFile;
  final String? daemonFakeHermesGatewayCommand;
  final bool personalAgentEnabled;
  final String personalAgentRuntimeProvider;
  final String personalAgentProcessingScope;
  final bool personalAgentRealBackend;
  final bool codexAgentEnabled;
  final bool codexAgentRealBackend;
  final String? codexAgentPrompt;
  final String? codexAgentExpectedReply;
  final bool claudeCodeAgentEnabled;
  final bool claudeCodeAgentRealBackend;
  final String? claudeCodeAgentPrompt;
  final String? claudeCodeAgentExpectedReply;

  Duration get flutterTimeout {
    if (e2eCase == DesktopE2eCase.performance) {
      return performance.flutterTimeout;
    }
    return e2eCase.flutterTimeout;
  }

  static DesktopCliPeerConfig from(
    DesktopE2eOptions options,
    DesktopE2eFileConfig fileConfig,
  ) {
    final sourcePath = fileConfig.path ?? options.configPath;
    if (fileConfig.path == null) {
      throw E2eFailure('E2E config file was not found: $sourcePath');
    }
    final platform = fileConfig.platform ?? DesktopE2ePlatform.fromHost();
    final serviceBaseUrl = _requiredConfig(
      fileConfig.serviceBaseUrl,
      'service.baseUrl',
      sourcePath,
    );
    final didDomain = _requiredConfig(
      fileConfig.didDomain,
      'service.didDomain',
      sourcePath,
    );
    final otpPhone = _requiredConfig(
      fileConfig.otpPhone,
      'otp.phone',
      sourcePath,
    );
    final otpCode = _requiredConfig(fileConfig.otpCode, 'otp.code', sourcePath);
    final appHandle = _requiredConfig(
      fileConfig.appHandle,
      'accounts.appUser.handle',
      sourcePath,
    );
    final secondaryAppHandle = options.e2eCase == DesktopE2eCase.identitySwitch
        ? _requiredConfig(
            fileConfig.secondaryAppHandle,
            'accounts.appSecondaryUser.handle',
            sourcePath,
          )
        : fileConfig.secondaryAppHandle;
    final cliHandle = _requiredConfig(
      fileConfig.cliHandle,
      'accounts.cliPeer.handle',
      sourcePath,
    );
    if (appHandle.toLowerCase() == cliHandle.toLowerCase()) {
      throw E2eFailure('App handle and CLI handle must differ.');
    }
    if (secondaryAppHandle != null &&
        <String>{
              appHandle.toLowerCase(),
              cliHandle.toLowerCase(),
              secondaryAppHandle.toLowerCase(),
            }.length !=
            3) {
      throw E2eFailure(
        'Primary App, secondary App, and CLI handles must all differ.',
      );
    }
    final cliBin = _requiredConfig(
      fileConfig.cliBin,
      'cliPeer.binary',
      sourcePath,
    );
    final peerConfig = DesktopCliPeerConfig(
      platform: platform,
      serviceBaseUrl: serviceBaseUrl,
      didDomain: didDomain,
      otpPhone: otpPhone,
      otpCode: otpCode,
      appHandle: appHandle,
      secondaryAppHandle: secondaryAppHandle,
      cliHandle: cliHandle,
      cliBin: cliBin,
      cliSourceRef: fileConfig.cliSourceRef ?? 'unrecorded',
      e2eCase: options.e2eCase,
      performance: fileConfig.performance ?? DesktopPerformanceConfig.defaults,
      userServiceUrl: fileConfig.userServiceUrl,
      messageServiceUrl: fileConfig.messageServiceUrl,
      messageServiceWsUrl: fileConfig.messageServiceWsUrl,
      mailServiceUrl: fileConfig.mailServiceUrl,
      anpServiceUrl: fileConfig.anpServiceUrl,
      anpServiceDid: fileConfig.anpServiceDid,
      daemonRustRepo: fileConfig.daemonRustRepo,
      daemonBinary: fileConfig.daemonBinary,
      daemonStateRoot: fileConfig.daemonStateRoot,
      daemonReadyFile: fileConfig.daemonReadyFile,
      daemonHandle: fileConfig.daemonHandle,
      daemonEnvFile: fileConfig.daemonEnvFile,
      daemonFakeHermesGatewayCommand: fileConfig.daemonFakeHermesGatewayCommand,
      personalAgentEnabled: _effectivePersonalAgentEnabled(
        options,
        fileConfig,
        sourcePath,
      ),
      personalAgentRuntimeProvider:
          fileConfig.personalAgentRuntimeProvider ?? 'hermes',
      personalAgentProcessingScope:
          fileConfig.personalAgentProcessingScope ?? 'all_conversations',
      personalAgentRealBackend: _effectivePersonalAgentRealBackend(
        options,
        fileConfig,
        sourcePath,
      ),
      codexAgentEnabled: _effectiveCodexAgentEnabled(
        options,
        fileConfig,
        sourcePath,
      ),
      codexAgentRealBackend: _effectiveCodexAgentRealBackend(
        options,
        fileConfig,
      ),
      codexAgentPrompt: fileConfig.codexAgentPrompt,
      codexAgentExpectedReply: fileConfig.codexAgentExpectedReply,
      claudeCodeAgentEnabled: _effectiveClaudeCodeAgentEnabled(
        options,
        fileConfig,
        sourcePath,
      ),
      claudeCodeAgentRealBackend: _effectiveClaudeCodeAgentRealBackend(
        options,
        fileConfig,
      ),
      claudeCodeAgentPrompt: fileConfig.claudeCodeAgentPrompt,
      claudeCodeAgentExpectedReply: fileConfig.claudeCodeAgentExpectedReply,
    );
    peerConfig.validateSelectedCaseConfig(sourcePath);
    return peerConfig;
  }

  void validateSelectedCaseConfig(String sourcePath) {
    if (e2eCase != DesktopE2eCase.personalAgent) {
      return;
    }
    _requiredConfig(messageServiceUrl, 'service.messageServiceUrl', sourcePath);
    _requiredConfig(
      messageServiceWsUrl,
      'service.messageServiceWsUrl',
      sourcePath,
    );
    _requiredConfig(daemonRustRepo, 'daemon.rustRepo', sourcePath);
    _requiredConfig(daemonBinary, 'daemon.binary', sourcePath);
    _requiredConfig(daemonStateRoot, 'daemon.stateRoot', sourcePath);
    _requiredConfig(daemonReadyFile, 'daemon.readyFile', sourcePath);
    _requiredConfig(
      daemonFakeHermesGatewayCommand,
      'daemon.fakeHermesGatewayCommand',
      sourcePath,
    );
    if (personalAgentRuntimeProvider.trim().toLowerCase() != 'hermes') {
      throw E2eFailure(
        'personalAgent.runtimeProvider must be hermes for --case personal-agent in $sourcePath.',
      );
    }
  }
}

bool _effectivePersonalAgentEnabled(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.personalAgentEnabled;
  if (options.e2eCase != DesktopE2eCase.personalAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'personalAgent.enabled must be true for --case personal-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectivePersonalAgentRealBackend(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.personalAgentRealBackend;
  if (options.e2eCase != DesktopE2eCase.personalAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'personalAgent.realBackend must be true for --case personal-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectiveCodexAgentEnabled(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.codexAgentEnabled;
  if (options.e2eCase != DesktopE2eCase.codexAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'codexAgent.enabled must be true for --case codex-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectiveCodexAgentRealBackend(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
) {
  if (options.e2eCase == DesktopE2eCase.codexAgent) {
    return fileConfig.codexAgentRealBackend ?? true;
  }
  return fileConfig.codexAgentRealBackend ?? false;
}

bool _effectiveClaudeCodeAgentEnabled(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.claudeCodeAgentEnabled;
  if (options.e2eCase != DesktopE2eCase.claudeCodeAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'claudeCodeAgent.enabled must be true for --case claude-code-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectiveClaudeCodeAgentRealBackend(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
) {
  if (options.e2eCase == DesktopE2eCase.claudeCodeAgent) {
    return fileConfig.claudeCodeAgentRealBackend ?? true;
  }
  return fileConfig.claudeCodeAgentRealBackend ?? false;
}

String _defaultCodexExpectedReply(String runId) {
  final suffix = runId
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'OK-CODEX-${suffix.isEmpty ? 'E2E' : suffix}';
}

String _defaultCodexPrompt(String runId) {
  return 'Reply exactly ${_defaultCodexExpectedReply(runId)} and nothing else';
}

String _defaultClaudeCodeExpectedReply(String runId) {
  final suffix = runId
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'OK-CLAUDE-CODE-${suffix.isEmpty ? 'E2E' : suffix}';
}

String _defaultClaudeCodePrompt(String runId) {
  return 'Reply exactly ${_defaultClaudeCodeExpectedReply(runId)} and nothing else';
}

class DesktopE2eFileConfig {
  const DesktopE2eFileConfig({
    this.path,
    this.platform,
    this.serviceBaseUrl,
    this.userServiceUrl,
    this.messageServiceUrl,
    this.messageServiceWsUrl,
    this.mailServiceUrl,
    this.didDomain,
    this.anpServiceUrl,
    this.anpServiceDid,
    this.daemonRustRepo,
    this.daemonBinary,
    this.daemonStateRoot,
    this.daemonReadyFile,
    this.daemonHandle,
    this.daemonEnvFile,
    this.daemonFakeHermesGatewayCommand,
    this.personalAgentEnabled,
    this.personalAgentRuntimeProvider,
    this.personalAgentProcessingScope,
    this.personalAgentRealBackend,
    this.codexAgentEnabled,
    this.codexAgentRealBackend,
    this.codexAgentPrompt,
    this.codexAgentExpectedReply,
    this.claudeCodeAgentEnabled,
    this.claudeCodeAgentRealBackend,
    this.claudeCodeAgentPrompt,
    this.claudeCodeAgentExpectedReply,
    this.otpPhone,
    this.otpCode,
    this.appHandle,
    this.secondaryAppHandle,
    this.cliHandle,
    this.cliBin,
    this.cliSourceRef,
    this.performance,
  });

  const DesktopE2eFileConfig.empty()
    : path = null,
      platform = null,
      serviceBaseUrl = null,
      userServiceUrl = null,
      messageServiceUrl = null,
      messageServiceWsUrl = null,
      mailServiceUrl = null,
      didDomain = null,
      anpServiceUrl = null,
      anpServiceDid = null,
      daemonRustRepo = null,
      daemonBinary = null,
      daemonStateRoot = null,
      daemonReadyFile = null,
      daemonHandle = null,
      daemonEnvFile = null,
      daemonFakeHermesGatewayCommand = null,
      personalAgentEnabled = null,
      personalAgentRuntimeProvider = null,
      personalAgentProcessingScope = null,
      personalAgentRealBackend = null,
      codexAgentEnabled = null,
      codexAgentRealBackend = null,
      codexAgentPrompt = null,
      codexAgentExpectedReply = null,
      claudeCodeAgentEnabled = null,
      claudeCodeAgentRealBackend = null,
      claudeCodeAgentPrompt = null,
      claudeCodeAgentExpectedReply = null,
      otpPhone = null,
      otpCode = null,
      appHandle = null,
      secondaryAppHandle = null,
      cliHandle = null,
      cliBin = null,
      cliSourceRef = null,
      performance = null;

  final String? path;
  final DesktopE2ePlatform? platform;
  final String? serviceBaseUrl;
  final String? userServiceUrl;
  final String? messageServiceUrl;
  final String? messageServiceWsUrl;
  final String? mailServiceUrl;
  final String? didDomain;
  final String? anpServiceUrl;
  final String? anpServiceDid;
  final String? daemonRustRepo;
  final String? daemonBinary;
  final String? daemonStateRoot;
  final String? daemonReadyFile;
  final String? daemonHandle;
  final String? daemonEnvFile;
  final String? daemonFakeHermesGatewayCommand;
  final bool? personalAgentEnabled;
  final String? personalAgentRuntimeProvider;
  final String? personalAgentProcessingScope;
  final bool? personalAgentRealBackend;
  final bool? codexAgentEnabled;
  final bool? codexAgentRealBackend;
  final String? codexAgentPrompt;
  final String? codexAgentExpectedReply;
  final bool? claudeCodeAgentEnabled;
  final bool? claudeCodeAgentRealBackend;
  final String? claudeCodeAgentPrompt;
  final String? claudeCodeAgentExpectedReply;
  final String? otpPhone;
  final String? otpCode;
  final String? appHandle;
  final String? secondaryAppHandle;
  final String? cliHandle;
  final String? cliBin;
  final String? cliSourceRef;
  final DesktopPerformanceConfig? performance;

  static DesktopE2eFileConfig load({
    required Directory root,
    required String path,
    Map<String, String> environment = const <String, String>{},
  }) {
    final file = File(_resolvePath(root, path));
    if (!file.existsSync()) {
      return const DesktopE2eFileConfig.empty();
    }
    final raw = _toStringKeyMap(loadYaml(file.readAsStringSync()), path: path);
    final service = _mapAt(raw, 'service', optional: true);
    final accounts = _mapAt(raw, 'accounts', optional: true);
    final appUser = _mapAt(accounts, 'appUser', optional: true);
    final secondaryAppUser = _mapAt(
      accounts,
      'appSecondaryUser',
      optional: true,
    );
    final cliUser = _mapAt(accounts, 'cliPeer', optional: true);
    final cliPeer = _mapAt(raw, 'cliPeer', optional: true);
    final daemon = _mapAt(raw, 'daemon', optional: true);
    final personalAgent = raw.containsKey('personalAgent')
        ? _mapAt(raw, 'personalAgent', optional: true)
        : _mapAt(raw, 'messageAgent', optional: true);
    final codexAgent = _mapAt(raw, 'codexAgent', optional: true);
    final claudeCodeAgent = _mapAt(raw, 'claudeCodeAgent', optional: true);
    final performance = _mapAt(raw, 'performance', optional: true);
    final otp = _mapAt(raw, 'otp', optional: true);

    final baseUrl = _stringAt(service, 'baseUrl');
    final didDomain = _stringAt(service, 'didDomain');
    final environmentOtpPhone = environment[_e2eOtpPhoneEnv]?.trim();
    final environmentOtpCode = environment[_e2eOtpCodeEnv]?.trim();
    final otpPhone = environmentOtpPhone?.isNotEmpty == true
        ? environmentOtpPhone
        : _stringAt(otp, 'phone');
    final otpCode = environmentOtpCode?.isNotEmpty == true
        ? environmentOtpCode
        : _stringAt(otp, 'code');
    final appHandle = _stringAt(appUser, 'handle');
    final secondaryAppHandle = _stringAt(secondaryAppUser, 'handle');
    final cliHandle = _stringAt(cliUser, 'handle');
    final configuredRustRepo = _stringAt(daemon, 'rustRepo');
    final environmentRustRepo = environment[_awikiCliRustRepoEnv]?.trim();
    final environmentCliBinary = environment[_e2eCliBinaryEnv]?.trim();
    final environmentCliSourceRef = environment[_e2eCliSourceRefEnv]?.trim();
    final environmentDaemonBinary = environment[_e2eDaemonBinaryEnv]?.trim();
    final rustRepo = environmentRustRepo?.isNotEmpty == true
        ? environmentRustRepo!
        : configuredRustRepo ?? '../awiki-cli-rs2';
    final cliBin = environmentCliBinary?.isNotEmpty == true
        ? environmentCliBinary!
        : environmentRustRepo?.isNotEmpty == true
        ? '$rustRepo/target/debug/awiki-cli'
        : _stringAt(cliPeer, 'binary') ?? '$rustRepo/target/debug/awiki-cli';
    final daemonBinary = environmentDaemonBinary?.isNotEmpty == true
        ? environmentDaemonBinary!
        : environmentRustRepo?.isNotEmpty == true
        ? '$rustRepo/target/debug/awiki-deamon'
        : _stringAt(daemon, 'binary') ?? '$rustRepo/target/debug/awiki-deamon';
    final platformValue = _stringAt(raw, 'platform');

    return DesktopE2eFileConfig(
      path: file.path,
      platform: platformValue == null
          ? null
          : DesktopE2ePlatform.parse(platformValue),
      serviceBaseUrl: baseUrl,
      userServiceUrl: _stringAt(service, 'userServiceUrl'),
      messageServiceUrl: _stringAt(service, 'messageServiceUrl'),
      messageServiceWsUrl: _stringAt(service, 'messageServiceWsUrl'),
      mailServiceUrl: _stringAt(service, 'mailServiceUrl'),
      didDomain: didDomain,
      anpServiceUrl: _stringAt(service, 'anpServiceUrl'),
      anpServiceDid: _stringAt(service, 'anpServiceDid'),
      daemonRustRepo: rustRepo,
      daemonBinary: _resolvePath(root, daemonBinary),
      daemonStateRoot: _resolveOptionalPath(
        root,
        _stringAt(daemon, 'stateRoot'),
      ),
      daemonReadyFile: _resolveOptionalPath(
        root,
        _stringAt(daemon, 'readyFile'),
      ),
      daemonHandle: _stringAt(daemon, 'handle'),
      daemonEnvFile: _resolveOptionalPath(root, _stringAt(daemon, 'envFile')),
      daemonFakeHermesGatewayCommand: _stringAt(
        daemon,
        'fakeHermesGatewayCommand',
      ),
      personalAgentEnabled: _boolAt(personalAgent, 'enabled'),
      personalAgentRuntimeProvider: _stringAt(personalAgent, 'runtimeProvider'),
      personalAgentProcessingScope: _stringAt(personalAgent, 'processingScope'),
      personalAgentRealBackend: _boolAt(personalAgent, 'realBackend'),
      codexAgentEnabled: _boolAt(codexAgent, 'enabled'),
      codexAgentRealBackend: _boolAt(codexAgent, 'realBackend'),
      codexAgentPrompt: _stringAt(codexAgent, 'prompt'),
      codexAgentExpectedReply: _stringAt(codexAgent, 'expectedReply'),
      claudeCodeAgentEnabled: _boolAt(claudeCodeAgent, 'enabled'),
      claudeCodeAgentRealBackend: _boolAt(claudeCodeAgent, 'realBackend'),
      claudeCodeAgentPrompt: _stringAt(claudeCodeAgent, 'prompt'),
      claudeCodeAgentExpectedReply: _stringAt(claudeCodeAgent, 'expectedReply'),
      otpPhone: otpPhone,
      otpCode: otpCode,
      appHandle: appHandle,
      secondaryAppHandle: secondaryAppHandle,
      cliHandle: cliHandle,
      cliBin: _resolvePath(root, cliBin),
      cliSourceRef: environmentCliSourceRef?.isNotEmpty == true
          ? environmentCliSourceRef
          : _stringAt(cliPeer, 'sourceRef'),
      performance: DesktopPerformanceConfig.fromYaml(performance),
    );
  }
}
