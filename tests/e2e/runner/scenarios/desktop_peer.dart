// [INPUT]: Typed App/CLI peer config, prepared CLI/App artifacts, and isolated workspaces.
// [OUTPUT]: Desktop peer tenant/identity lifecycle and selected Flutter scenario execution.
// [POS]: App+CLI scenario orchestration; product assertions remain in Flutter/Core tests.

part of '../../runner.dart';

extension DesktopE2ePeerScenario on DesktopE2eRunner {
  Future<void> _runAppCliPeer() async {
    final peerConfig = DesktopCliPeerConfig.from(options, fileConfig);
    config = peerConfig;
    if (!options.dryRun && !commands.dryRun) {
      suiteDefinition.validateRemoteTarget(peerConfig);
    }
    _addRuntimeSecret(peerConfig.otpPhone);
    _addRuntimeSecret(peerConfig.otpCode);
    _addRuntimeSecret(peerConfig.cliBin);
    _addRuntimeSecret(peerConfig.daemonStateRoot ?? '');
    _addRuntimeSecret(peerConfig.daemonReadyFile ?? '');
    _addRuntimeSecret(peerConfig.daemonEnvFile ?? '');
    _section('AWiki Desktop App + CLI peer E2E $runId');
    _line('platform: ${peerConfig.platform.name}');
    _line('config: ${fileConfig.path ?? '<not found>'}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('cli workspace: ${redactor.redact(cliWorkspaceDir.path)}');
    _line('cli home: ${redactor.redact(cliHomeDir.path)}');
    _line('app state: ${redactor.redact(appStateRootDir.path)}');
    if (peerConfig.daemonEnvFile != null) {
      _line('daemon env file: ${redactor.redact(peerConfig.daemonEnvFile!)}');
    }
    _line('app handle: ${peerConfig.appHandle}');
    if (peerConfig.secondaryAppHandle != null) {
      _line('secondary app handle: ${peerConfig.secondaryAppHandle}');
    }
    _line('cli handle: ${peerConfig.cliHandle}');
    _line('case: ${peerConfig.e2eCase.caseName}');
    _line('flutter build dir: ${flutterBuildIsolation.buildDirectory}');
    _line('service base: ${peerConfig.serviceBaseUrl}');
    _line(
      'user service: ${peerConfig.userServiceUrl ?? peerConfig.serviceBaseUrl}',
    );
    _line(
      'message service: '
      '${peerConfig.messageServiceUrl ?? peerConfig.serviceBaseUrl}',
    );

    await _timed('Checking tooling', _checkTooling);
    if (options.prepareOnly) {
      if (peerConfig.e2eCase == DesktopE2eCase.restart) {
        if (options.dryRun || commands.dryRun) {
          _line('would prepare three restart integration executables');
        } else {
          await _timed('Preparing restart integration executables', () {
            return _prepareRestartIntegrationExecutables();
          });
        }
      } else if (_supportsPreparedDesktopPeerExecutable(peerConfig.e2eCase)) {
        if (options.dryRun || commands.dryRun) {
          _line('would prepare the desktop integration executable');
        } else {
          await _timed('Preparing desktop integration executable', () {
            return _prepareDesktopPeerExecutable(peerConfig);
          });
        }
      }
      _section('Prepare-only completed');
      _line('No CLI identity, App process, or remote resource was created.');
      return;
    }
    await _timed('Preparing CLI workspace', _prepareCliWorkspace);
    await _timed('Preparing CLI identity', _prepareCliIdentity);
    await _timed('Checking CLI ready state', _checkCliReady);
    await _writeFlutterRunConfig(peerConfig);
    await _timed('Flutter App + CLI peer flow', _planFlutterDesktopSmoke);
    await _timed('Checking App identity ready state', _checkAppIdentityReady);
    if (!options.dryRun && peerConfig.e2eCase == DesktopE2eCase.performance) {
      _productTimingReport = _readProductTimingReport();
      _performanceBudgetResult = DesktopPerformanceBudgetResult.evaluate(
        config: peerConfig.performance,
        report: _productTimingReport,
      );
      final failures = _performanceBudgetResult!.hardFailures;
      if (failures.isNotEmpty) {
        throw E2eFailure(
          'Performance E2E budget failed: ${failures.join('; ')}',
        );
      }
    } else if (peerConfig.e2eCase == DesktopE2eCase.performance) {
      _performanceBudgetResult = DesktopPerformanceBudgetResult(
        hardFailures: const <String>[],
        softWarnings: const <String>[],
      );
    }
  }

  Future<void> _checkTooling() async {
    await commands.requireExecutable('flutter');
    final peerConfig = _requireConfig();
    if (peerConfig.platform == DesktopE2ePlatform.linux) {
      await commands.requireExecutable('xvfb-run');
    }
    await commands.requireFile(peerConfig.cliBin);
  }

  Future<void> _prepareCliWorkspace() async {
    await _cli(const <String>['--format', 'json', 'init']);
    await _prepareCliTenant(workspaceDir: cliWorkspaceDir, homeDir: cliHomeDir);
    await _writeCliConfig(cliWorkspaceDir);
    await _cli(const <String>['--format', 'json', 'config', 'show']);
  }

  Future<void> _prepareCliTenant({
    required Directory workspaceDir,
    required Directory homeDir,
  }) async {
    final peerConfig = _requireConfig();
    final tenantName = _tenantName;
    DesktopCliTenantConfig? existing;
    if (!options.dryRun && !commands.dryRun) {
      final list = await _cliForWorkspace(
        workspaceDir: workspaceDir,
        homeDir: homeDir,
        args: const <String>['--format', 'json', 'tenant', 'list'],
      );
      existing = cliTenantConfigFromListJson(list.output, tenantName);
    }
    if (existing == null) {
      await _cliForWorkspace(
        workspaceDir: workspaceDir,
        homeDir: homeDir,
        args: <String>[
          '--format',
          'json',
          'tenant',
          'create',
          tenantName,
          '--backend-base-url',
          peerConfig.serviceBaseUrl,
          '--did-host',
          peerConfig.didDomain,
          '--display-name',
          'AWiki E2E $runId',
        ],
      );
    } else if (!_sameHttpEndpoint(
          existing.backendBaseUrl,
          peerConfig.serviceBaseUrl,
        ) ||
        _normalizedDomain(existing.didHost) !=
            _normalizedDomain(peerConfig.didDomain)) {
      throw E2eFailure(
        'Existing E2E tenant does not match the selected service target.',
      );
    }
    await _cliForWorkspace(
      workspaceDir: workspaceDir,
      homeDir: homeDir,
      args: <String>['--format', 'json', 'tenant', 'use', tenantName],
    );
    await _cliForWorkspace(
      workspaceDir: workspaceDir,
      homeDir: homeDir,
      args: const <String>['--format', 'json', 'tenant', 'current'],
    );
  }

  String get _tenantName {
    final suffix = runId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final bounded = suffix.length <= 40 ? suffix : suffix.substring(0, 40);
    return 'e2e-${bounded.isEmpty ? 'run' : bounded}';
  }

  Future<void> _writeCliConfig(Directory workspaceDir) async {
    final peerConfig = _requireConfig();
    final file = File('${workspaceDir.path}/tenants/$_tenantName/config.yaml');
    final configMap = file.existsSync()
        ? _toStringKeyMap(loadYaml(file.readAsStringSync()), path: 'config')
        : <String, Object?>{};
    final services = _mapAt(configMap, 'services', optional: true);
    final runtime = _mapAt(configMap, 'runtime', optional: true);
    services['anp_service_endpoint'] =
        peerConfig.anpServiceUrl ?? '${peerConfig.serviceBaseUrl}/anp-im/rpc';
    services['anp_service_did'] =
        peerConfig.anpServiceDid ?? 'did:wba:${peerConfig.didDomain}';
    services['mail_service_url'] =
        peerConfig.mailServiceUrl ?? peerConfig.serviceBaseUrl;
    // This isolated E2E workspace is driven by foreground CLI processes owned
    // by the harness. Persist the transport mode without applying host service
    // policy, which would otherwise require a login-session service manager.
    runtime['mode'] = 'http';
    configMap['schema_version'] = 1;
    configMap['services'] = services;
    configMap['runtime'] = runtime;

    if (options.dryRun) {
      _line(
        'would write CLI config: ${redactor.redact(file.path)} '
        '(tenant_backend=${peerConfig.serviceBaseUrl}, '
        'tenant_did_host=${peerConfig.didDomain}, '
        'anp_service_endpoint=${services['anp_service_endpoint']}, '
        'anp_service_did=${services['anp_service_did']}, '
        'mail_service_url=${services['mail_service_url']})',
      );
    } else {
      workspaceDir.createSync(recursive: true);
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_renderYamlMap(configMap));
  }

  Future<void> _prepareCliIdentity() async {
    final peerConfig = _requireConfig();
    var reuseReadyIdentity = false;
    if (!options.dryRun && !commands.dryRun) {
      final current = await _cli(const <String>[
        '--format',
        'json',
        'id',
        'current',
      ], allowFailure: true);
      if (current.exitCode == 0) {
        reuseReadyIdentity = cliCurrentIdentityReadyForHandle(
          current.output,
          handle: peerConfig.cliHandle,
          didDomain: peerConfig.didDomain,
        );
      }
    }
    if (!reuseReadyIdentity) {
      final otpArgs = <String>[
        '--format',
        'json',
        'id',
        'register',
        '--handle',
        peerConfig.cliHandle,
        '--verification-stdin',
      ];
      final otpInput = jsonEncode(<String, String>{
        'phone': peerConfig.otpPhone,
      });
      final otpRequest = await _cli(
        otpArgs,
        allowFailure: true,
        stdinText: otpInput,
      );
      if (otpRequest.exitCode != 0 && !options.dryRun) {
        throw E2eFailure(
          'CLI peer registration OTP request failed: '
          '${redactor.redact(otpRequest.output)}',
        );
      }
      final register = await _cli(
        <String>[
          '--format',
          'json',
          'id',
          'register',
          '--handle',
          peerConfig.cliHandle,
          '--verification-stdin',
        ],
        allowFailure: true,
        stdinText: jsonEncode(<String, String>{
          'phone': peerConfig.otpPhone,
          'otp': peerConfig.otpCode,
        }),
      );
      if (register.exitCode != 0 && !options.dryRun) {
        throw E2eFailure(
          'CLI peer register failed: ${redactor.redact(register.output)}',
        );
      }
      if (!options.dryRun) {
        _resourceSideEffectsPossible = true;
      }
    }

    if (peerConfig.e2eCase.publishesNicknameFixture) {
      await _cli(<String>[
        '--format',
        'json',
        'id',
        'profile',
        'set',
        '--display-name',
        _desktopCliPeerDisplayName,
      ]);
      _resourceSideEffectsPossible = true;
    }
  }

  Future<void> _checkCliReady() async {
    final peerConfig = _requireConfig();
    final current = await _cli(const <String>[
      '--format',
      'json',
      'id',
      'current',
    ]);
    await _cli(const <String>['--format', 'json', 'id', 'status']);
    await _cli(const <String>[
      '--format',
      'json',
      'msg',
      'inbox',
      '--limit',
      '1',
    ]);
    if (options.dryRun || commands.dryRun) {
      _identityPreflight = <String, Object?>{
        'status': options.dryRun ? 'dry_run' : 'not_executed_command_stub',
        'cliHandleMatchesCurrent': false,
        'appHandleResolvable': false,
        'identitiesDistinct': false,
      };
      return;
    }
    if (!isAuditableGitSha(peerConfig.cliSourceRef)) {
      throw E2eFailure(
        'cliPeer.sourceRef must be the exact non-zero 40-character commit SHA embedded in the CLI binary.',
      );
    }
    final version = await _cli(const <String>['--format', 'json', 'version']);
    cliBuildVersionFromVersionJson(version.output);
    final binaryCommit = cliBuildCommitFromVersionJson(version.output);
    if (binaryCommit != peerConfig.cliSourceRef.toLowerCase()) {
      throw E2eFailure(
        'cliPeer.sourceRef does not match the commit embedded in the CLI binary.',
      );
    }
    final cliResolved = await _cli(<String>[
      '--format',
      'json',
      'id',
      'resolve',
      '--handle',
      peerConfig.cliHandle,
    ]);
    final currentDid = _cliDidFromJson(current.output, current: true);
    final cliDid = _cliDidFromJson(cliResolved.output);
    final cliMatches = currentDid == cliDid;
    _identityPreflight = <String, Object?>{
      'status': cliMatches ? 'cli_ready' : 'failed',
      'cliHandleMatchesCurrent': cliMatches,
      'appHandleResolvable': false,
      'identitiesDistinct': false,
      'containsRawDids': false,
    };
    if (!cliMatches) {
      throw E2eFailure('CLI peer identity mismatch.');
    }
  }

  Future<void> _checkAppIdentityReady() async {
    final peerConfig = _requireConfig();
    if (options.dryRun || commands.dryRun) {
      return;
    }
    final current = await _cli(const <String>[
      '--format',
      'json',
      'id',
      'current',
    ]);
    final appResolved = await _cli(<String>[
      '--format',
      'json',
      'id',
      'resolve',
      '--handle',
      peerConfig.appHandle,
    ]);
    final secondaryAppResolved = peerConfig.secondaryAppHandle == null
        ? null
        : await _cli(<String>[
            '--format',
            'json',
            'id',
            'resolve',
            '--handle',
            peerConfig.secondaryAppHandle!,
          ]);
    final currentDid = _cliDidFromJson(current.output, current: true);
    final appDid = _cliDidFromJson(appResolved.output);
    final secondaryAppDid = secondaryAppResolved == null
        ? null
        : _cliDidFromJson(secondaryAppResolved.output);
    final identitiesDistinct = secondaryAppDid == null
        ? currentDid != appDid
        : <String>{currentDid, appDid, secondaryAppDid}.length == 3;
    _identityPreflight = <String, Object?>{
      ..._identityPreflight,
      'status': identitiesDistinct ? 'passed' : 'failed',
      'appHandleResolvable': true,
      'secondaryAppHandleResolvable': secondaryAppDid != null,
      'identitiesDistinct': identitiesDistinct,
      'containsRawDids': false,
    };
    if (!identitiesDistinct) {
      throw E2eFailure('App and CLI peer identities must be distinct.');
    }
  }

  Future<void> _planFlutterDesktopSmoke() async {
    final peerConfig = _requireConfig();
    if (peerConfig.e2eCase == DesktopE2eCase.restart &&
        !options.dryRun &&
        !commands.dryRun &&
        Platform.environment['AWIKI_E2E_USE_FLUTTER_TEST']?.trim() != '1') {
      final artifacts = await _prepareRestartIntegrationExecutables();
      await _executePreparedIntegration(
        artifact: artifacts.phaseA,
        caseIds: suiteDefinition.caseIds,
        stateRoot: appStateRootDir,
      );
      if (!processRestartHandoffFile.existsSync()) {
        throw E2eFailure(
          'Process-restart phase A did not write its handoff evidence.',
        );
      }
      await _executePreparedIntegration(
        artifact: artifacts.phaseB,
        caseIds: suiteDefinition.caseIds,
        stateRoot: appStateRootDir,
      );
      if (!credentialDeleteMarkerFile.existsSync()) {
        throw E2eFailure(
          'Credential-delete phase B did not write its completion evidence.',
        );
      }
      await _executePreparedIntegration(
        artifact: artifacts.phaseC,
        caseIds: suiteDefinition.caseIds,
        stateRoot: appStateRootDir,
      );
      return;
    }
    if (peerConfig.e2eCase == DesktopE2eCase.restart) {
      await _runFlutterArgs(
        <String>[
          'test',
          '--dart-define=AWIKI_E2E=true',
          'integration_test/desktop_cli_peer_restart_phase_a_test.dart',
          '-d',
          peerConfig.platform.name,
        ],
        platform: peerConfig.platform,
        timeout: _effectiveFlutterTimeout(peerConfig),
      );
      if (!options.dryRun && !processRestartHandoffFile.existsSync()) {
        throw E2eFailure(
          'Process-restart phase A did not write its handoff evidence.',
        );
      }
      await _runFlutterArgs(
        <String>[
          'test',
          '--dart-define=AWIKI_E2E=true',
          'integration_test/desktop_cli_peer_restart_phase_b_test.dart',
          '-d',
          peerConfig.platform.name,
        ],
        platform: peerConfig.platform,
        timeout: _effectiveFlutterTimeout(peerConfig),
      );
      if (!options.dryRun && !credentialDeleteMarkerFile.existsSync()) {
        throw E2eFailure(
          'Credential-delete phase B did not write its completion evidence.',
        );
      }
      await _runFlutterArgs(
        <String>[
          'test',
          '--dart-define=AWIKI_E2E=true',
          'integration_test/desktop_cli_peer_credential_delete_phase_c_test.dart',
          '-d',
          peerConfig.platform.name,
        ],
        platform: peerConfig.platform,
        timeout: _effectiveFlutterTimeout(peerConfig),
      );
      return;
    }
    if (!options.dryRun &&
        !commands.dryRun &&
        _supportsPreparedDesktopPeerExecutable(peerConfig.e2eCase) &&
        Platform.environment['AWIKI_E2E_USE_FLUTTER_TEST']?.trim() != '1') {
      final artifact = await _prepareDesktopPeerExecutable(peerConfig);
      _resourceSideEffectsPossible = true;
      await _executePreparedIntegration(
        artifact: artifact,
        caseIds: suiteDefinition.caseIds,
        stateRoot: appStateRootDir,
      );
      return;
    }
    final flutterArgs = <String>[
      'test',
      '--dart-define=AWIKI_E2E=true',
      ..._multiDeviceProductDartDefines(peerConfig.e2eCase),
      if (peerConfig.e2eCase == DesktopE2eCase.personalAgent) ...<String>[
        '--plain-name',
        'Personal Agent full UI drives real backend daemon and recovery',
      ],
      peerConfig.e2eCase.testFile,
      '-d',
      peerConfig.platform.name,
    ];
    _resourceSideEffectsPossible = true;
    await _runFlutterArgs(
      flutterArgs,
      platform: peerConfig.platform,
      timeout: _effectiveFlutterTimeout(peerConfig),
    );
  }

  bool _supportsPreparedDesktopPeerExecutable(DesktopE2eCase e2eCase) =>
      e2eCase != DesktopE2eCase.restart &&
      e2eCase != DesktopE2eCase.personalAgent;

  Future<_IsolatedAppArtifact> _prepareDesktopPeerExecutable(
    DesktopCliPeerConfig peerConfig,
  ) {
    final caseName = peerConfig.e2eCase.caseName;
    final bundleSuffix = caseName.replaceAll('-', '.');
    return _prepareIntegrationExecutable(
      name: caseName,
      target: peerConfig.e2eCase.testFile,
      bundleId: 'ai.awiki.awikime.dev.e2e.$bundleSuffix',
      stateRoot: appStateRootDir,
      dartDefines: <String>[
        for (final argument in _multiDeviceProductDartDefines(
          peerConfig.e2eCase,
        ))
          argument.substring('--dart-define='.length),
      ],
    );
  }

  Future<
    ({
      _IsolatedAppArtifact phaseA,
      _IsolatedAppArtifact phaseB,
      _IsolatedAppArtifact phaseC,
    })
  >
  _prepareRestartIntegrationExecutables() async {
    final phaseA = await _prepareIntegrationExecutable(
      name: 'restart-a',
      target: 'integration_test/desktop_cli_peer_restart_phase_a_test.dart',
      bundleId: 'ai.awiki.awikime.dev.e2e.restart.a',
      stateRoot: appStateRootDir,
    );
    final phaseB = await _prepareIntegrationExecutable(
      name: 'restart-b',
      target: 'integration_test/desktop_cli_peer_restart_phase_b_test.dart',
      bundleId: 'ai.awiki.awikime.dev.e2e.restart.b',
      stateRoot: appStateRootDir,
    );
    final phaseC = await _prepareIntegrationExecutable(
      name: 'restart-c',
      target:
          'integration_test/desktop_cli_peer_credential_delete_phase_c_test.dart',
      bundleId: 'ai.awiki.awikime.dev.e2e.restart.c',
      stateRoot: appStateRootDir,
    );
    return (phaseA: phaseA, phaseB: phaseB, phaseC: phaseC);
  }

  Future<void> _writeFlutterRunConfig(DesktopCliPeerConfig peerConfig) async {
    final payload = <String, Object?>{
      'enabled': true,
      'runId': runId,
      'platform': peerConfig.platform.name,
      'case': peerConfig.e2eCase.caseName,
      'service': <String, Object?>{
        'baseUrl': peerConfig.serviceBaseUrl,
        'userServiceUrl': peerConfig.userServiceUrl,
        'messageServiceUrl': peerConfig.messageServiceUrl,
        'messageServiceWsUrl': peerConfig.messageServiceWsUrl,
        'mailServiceUrl': peerConfig.mailServiceUrl,
        'didDomain': peerConfig.didDomain,
        'anpServiceUrl': peerConfig.anpServiceUrl,
        'anpServiceDid': peerConfig.anpServiceDid,
      },
      'otp': <String, Object?>{
        'mode': 'ignored_local_fixture',
        'localConfigPath': fileConfig.path,
      },
      'accounts': <String, Object?>{
        'appUser': <String, Object?>{'handle': peerConfig.appHandle},
        if (peerConfig.secondaryAppHandle != null)
          'appSecondaryUser': <String, Object?>{
            'handle': peerConfig.secondaryAppHandle,
          },
        'cliPeer': <String, Object?>{'handle': peerConfig.cliHandle},
      },
      'cliPeer': <String, Object?>{
        'binary': peerConfig.cliBin,
        'sourceRef': peerConfig.cliSourceRef,
        'workspace': cliWorkspaceDir.path,
        'home': cliHomeDir.path,
      },
      'suite': <String, Object?>{
        'manifestRevision': suiteManifest.sourceRevision,
        'tier': suiteDefinition.tier,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
      },
      'app': <String, Object?>{'stateRoot': appStateRootDir.path},
      'processRestart': <String, Object?>{
        'handoffPath': processRestartHandoffFile.path,
      },
      'performance': <String, Object?>{
        'enabled': peerConfig.e2eCase == DesktopE2eCase.performance,
        'productTimingsPath': productTimingsFile.path,
        'datasetConversationCount':
            peerConfig.performance.datasetConversationCount,
        'longThreadMessageCount': peerConfig.performance.longThreadMessageCount,
        'requiredMetrics': peerConfig.performance.requiredMetrics.toList(),
        'hardBudgetMs': peerConfig.performance.hardBudgetMs,
        'softBudgetMs': peerConfig.performance.softBudgetMs,
        'maxFullRefreshDuringSendReceive':
            peerConfig.performance.maxFullRefreshDuringSendReceive,
      },
      'daemon': <String, Object?>{
        'rustRepo': peerConfig.daemonRustRepo,
        'binary': peerConfig.daemonBinary,
        'stateRoot': peerConfig.daemonStateRoot,
        'readyFile': peerConfig.daemonReadyFile,
        'handle': peerConfig.daemonHandle,
        'envFile': peerConfig.daemonEnvFile,
        'fakeHermesGatewayCommand': peerConfig.daemonFakeHermesGatewayCommand,
      },
      'personalAgent': <String, Object?>{
        'enabled': peerConfig.personalAgentEnabled,
        'runtimeProvider': peerConfig.personalAgentRuntimeProvider,
        'processingScope': peerConfig.personalAgentProcessingScope,
        'realBackend': peerConfig.personalAgentRealBackend,
      },
      'codexAgent': <String, Object?>{
        'enabled': peerConfig.codexAgentEnabled,
        'realBackend': peerConfig.codexAgentRealBackend,
        'prompt': peerConfig.codexAgentPrompt ?? _defaultCodexPrompt(runId),
        'expectedReply':
            peerConfig.codexAgentExpectedReply ??
            _defaultCodexExpectedReply(runId),
      },
      'claudeCodeAgent': <String, Object?>{
        'enabled': peerConfig.claudeCodeAgentEnabled,
        'realBackend': peerConfig.claudeCodeAgentRealBackend,
        'prompt':
            peerConfig.claudeCodeAgentPrompt ?? _defaultClaudeCodePrompt(runId),
        'expectedReply':
            peerConfig.claudeCodeAgentExpectedReply ??
            _defaultClaudeCodeExpectedReply(runId),
      },
    };
    if (options.dryRun && !options.prepareOnly) {
      _line('would write Flutter E2E run config: ${runConfigFile.path}');
    }
    await runConfigFile.parent.create(recursive: true);
    await runConfigFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  Future<DesktopCommandResult> _cli(
    List<String> args, {
    bool allowFailure = false,
    String? stdinText,
  }) {
    return _cliForWorkspace(
      workspaceDir: cliWorkspaceDir,
      homeDir: cliHomeDir,
      args: args,
      allowFailure: allowFailure,
      stdinText: stdinText,
    );
  }

  Future<DesktopCommandResult> _cliForWorkspace({
    required Directory workspaceDir,
    required Directory homeDir,
    required List<String> args,
    bool allowFailure = false,
    String? stdinText,
  }) {
    final environment = <String, String>{
      'HOME': homeDir.path,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': workspaceDir.path,
      if (_requireConfig().e2eCase ==
          DesktopE2eCase.full) ...const <String, String>{
        'AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED': '1',
      },
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
    return commands.captureResult(
      _requireConfig().cliBin,
      args,
      environment: environment,
      includeParentEnvironment: false,
      allowFailure: allowFailure,
      stdinText: stdinText,
    );
  }

  DesktopCliPeerConfig _requireConfig() {
    final peerConfig = config;
    if (peerConfig == null) {
      throw E2eFailure('App + CLI peer config is not initialized.');
    }
    return peerConfig;
  }

  List<String> _multiDeviceProductDartDefines(DesktopE2eCase e2eCase) {
    if (e2eCase != DesktopE2eCase.full) {
      return const <String>[];
    }
    return const <String>[
      '--dart-define=AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED=true',
    ];
  }

  Duration _effectiveFlutterTimeout(DesktopCliPeerConfig peerConfig) {
    if (peerConfig.e2eCase != DesktopE2eCase.performance) {
      return suiteDefinition.timeout;
    }
    final performanceTimeout = peerConfig.flutterTimeout;
    return performanceTimeout > suiteDefinition.timeout
        ? performanceTimeout
        : suiteDefinition.timeout;
  }

  String _cliDidFromJson(String output, {bool current = false}) {
    Object? decoded;
    try {
      decoded = jsonDecode(output);
    } on Object {
      throw E2eFailure('CLI identity preflight returned invalid JSON.');
    }
    if (decoded is! Map) {
      throw E2eFailure('CLI identity preflight returned an invalid object.');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw E2eFailure('CLI identity preflight omitted data.');
    }
    if (current) {
      final identity = data['identity'];
      final did = identity is Map ? identity['did'] : null;
      if (did is String && did.trim().isNotEmpty) {
        return did.trim();
      }
    } else {
      for (final key in const <String>['lookup', 'resolve']) {
        final value = data[key];
        final did = value is Map ? value['did'] : null;
        if (did is String && did.trim().isNotEmpty) {
          return did.trim();
        }
      }
    }
    throw E2eFailure('CLI identity preflight omitted a canonical DID.');
  }
}
