// [INPUT]: Recovery suite selector and compile-time fault-injection semantics.
// [OUTPUT]: Exact prepared executable set for the selected Recovery lifecycle.
// [POS]: Recovery scenario preparation; business assertions remain in Flutter tests.

part of '../../runner.dart';

extension DesktopE2eRecoveryScenario on DesktopE2eRunner {
  Future<Map<String, _IsolatedAppArtifact>>
  _prepareHandleRecoveryIntegrationExecutables({
    required bool registrationRejoin,
    required bool freshOnly,
    required bool localDataOnly,
  }) async {
    final artifacts = <String, _IsolatedAppArtifact>{};
    if (registrationRejoin || freshOnly || !localDataOnly) {
      artifacts['recovery-main'] = await _prepareIntegrationExecutable(
        name: 'recovery-main',
        target: 'integration_test/handle_recovery_ui_test.dart',
        bundleId: 'ai.awiki.awikime.dev.e2e.recovery.main',
        stateRoot: appStateRootDir,
      );
    }
    if (!registrationRejoin && !freshOnly) {
      artifacts['recovery-crash-a'] = await _prepareIntegrationExecutable(
        name: 'recovery-crash-a',
        target: 'integration_test/handle_recovery_ui_test.dart',
        bundleId: 'ai.awiki.awikime.dev.e2e.recovery.crash.a',
        stateRoot: appStateRootDir,
        dartDefines: const <String>[
          'AWIKI_HANDLE_RECOVERY_E2E_PHASE=crash_a',
          'AWIKI_E2E_HANDLE_RECOVERY_CRASH_BEFORE_PRODUCT_RESET=true',
        ],
      );
      artifacts['recovery-crash-b'] = await _prepareIntegrationExecutable(
        name: 'recovery-crash-b',
        target: 'integration_test/handle_recovery_ui_test.dart',
        bundleId: 'ai.awiki.awikime.dev.e2e.recovery.crash.b',
        stateRoot: appStateRootDir,
        dartDefines: const <String>['AWIKI_HANDLE_RECOVERY_E2E_PHASE=crash_b'],
      );
    }
    if (freshOnly) {
      artifacts['recovery-fresh-restart'] = await _prepareIntegrationExecutable(
        name: 'recovery-fresh-restart',
        target: 'integration_test/handle_recovery_ui_test.dart',
        bundleId: 'ai.awiki.awikime.dev.e2e.recovery.fresh.restart',
        stateRoot: appStateRootDir,
        dartDefines: const <String>[
          'AWIKI_HANDLE_RECOVERY_E2E_PHASE=fresh_restart',
        ],
      );
    }
    return artifacts;
  }

  Future<void> _runFreshRemoteHandleRecovery(
    Map<String, _IsolatedAppArtifact> preparedArtifacts,
  ) async {
    Object? freshFailure;
    try {
      await _timed('Flutter Fresh Root business continuity lifecycle', () {
        if (preparedArtifacts.isNotEmpty) {
          return _executePreparedIntegration(
            artifact: preparedArtifacts['recovery-main']!,
            caseIds: _handleRecoveryFreshCaseIds,
            stateRoot: appStateRootDir,
          );
        }
        return _runFlutterTest(
          'integration_test/handle_recovery_ui_test.dart',
          caseIds: _handleRecoveryFreshCaseIds,
        );
      });
    } catch (error) {
      freshFailure = error;
    }
    try {
      await _timed('Flutter Fresh Root cold restart verification', () {
        if (preparedArtifacts.isNotEmpty) {
          return _executePreparedIntegration(
            artifact: preparedArtifacts['recovery-fresh-restart']!,
            caseIds: const <String>['HANDLE-RECOVERY-FRESH-RESTART-E2E-001'],
            stateRoot: appStateRootDir,
          );
        }
        return _runFlutterArgs(
          <String>[
            'test',
            '--dart-define=AWIKI_E2E=true',
            '--dart-define=AWIKI_HANDLE_RECOVERY_E2E_PHASE=fresh_restart',
            'integration_test/handle_recovery_ui_test.dart',
            '-d',
            platform.name,
          ],
          platform: platform,
          timeout: suiteDefinition.timeout,
          runtimeCaseIds: const <String>[
            'HANDLE-RECOVERY-FRESH-RESTART-E2E-001',
          ],
        );
      });
    } catch (error) {
      freshFailure ??= error;
    }
    if (freshFailure != null) throw freshFailure;
  }

  Future<void> _writeRemoteHandleRecoveryRunConfig(
    RemoteHandleRecoveryConfig recoveryConfig,
  ) async {
    final payload = <String, Object?>{
      'schemaVersion': 2,
      'enabled': true,
      'runId': runId,
      'platform': recoveryConfig.platform.name,
      'service': <String, Object?>{
        'baseUrl': recoveryConfig.serviceBaseUrl,
        'userServiceUrl': recoveryConfig.userServiceUrl,
        'messageServiceUrl': recoveryConfig.messageServiceUrl,
        'mailServiceUrl': recoveryConfig.mailServiceUrl,
        'didDomain': recoveryConfig.didDomain,
        'anpServiceUrl': recoveryConfig.anpServiceUrl,
        'anpServiceDid': recoveryConfig.anpServiceDid,
      },
      'account': <String, Object?>{
        'handlePrefix': recoveryConfig.handlePrefix,
        'otpMode': 'ignored_local_fixture',
        'localConfigPath': fileConfig.path,
      },
      'testControl': <String, Object?>{
        'automatedUserPresence': true,
        'productSmsRequestRequired': true,
      },
      'app': <String, Object?>{'stateRoot': appStateRootDir.path},
      'peerApp': <String, Object?>{
        'stateRoot': multiDeviceAppJoiningStateRootDir.path,
      },
      'crashCut': <String, Object?>{
        'handoffPath': processRestartHandoffFile.path,
      },
      if (recoveryConfig.daemonBinary != null)
        'daemon': <String, Object?>{
          'binary': recoveryConfig.daemonBinary,
          'stateRoot': appPairDaemonStateRootDir.path,
          'readyFile': appPairDaemonReadyFile.path,
          'handle': recoveryConfig.daemonHandle,
        },
      'suite': <String, Object?>{
        'manifestRevision': suiteManifest.sourceRevision,
        'tier': suiteDefinition.tier,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
      },
    };
    if (options.dryRun) {
      _line('would write remote Handle Recovery run config');
      return;
    }
    await runConfigFile.parent.create(recursive: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['700', runConfigFile.parent.path]);
    }
    await runConfigFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', runConfigFile.path]);
    }
  }

  Future<void> _runRemoteHandleRecovery() async {
    final registrationRejoin =
        options.e2eCase ==
        DesktopE2eCase.multiDeviceAppPairRecoveryRegistration;
    final freshOnly =
        options.e2eCase == DesktopE2eCase.multiDeviceRemoteRecoveryFresh;
    final localDataOnly =
        options.e2eCase == DesktopE2eCase.handleRecoveryLocalData;
    final recoveryConfig = RemoteHandleRecoveryConfig.from(
      fileConfig: fileConfig,
      environment: Platform.environment,
    );
    remoteHandleRecoveryConfig = recoveryConfig;
    if (registrationRejoin) {
      if (fileConfig.path == null || fileConfig.path!.trim().isEmpty) {
        throw E2eFailure(
          'The recovery registration App-pair case requires an explicit '
          'awiki.info config file.',
        );
      }
    }
    _addRuntimeSecret(recoveryConfig.phone);
    _addRuntimeSecret(recoveryConfig.fixedOtp);
    _addRuntimeSecret(recoveryConfig.daemonBinary ?? '');
    if (!options.dryRun && !commands.dryRun) {
      suiteDefinition.validateRemoteTargetValues(
        didDomain: recoveryConfig.didDomain,
        serviceUrls: <String>[
          recoveryConfig.serviceBaseUrl,
          recoveryConfig.userServiceUrl,
          recoveryConfig.messageServiceUrl,
        ],
      );
      if (freshOnly || localDataOnly) {
        await commands.requireFile(
          _requiredConfig(
            recoveryConfig.daemonBinary,
            'daemon.binary',
            fileConfig.path ?? '<missing-config>',
          ),
        );
        _requiredConfig(
          recoveryConfig.daemonHandle,
          'daemon.handle',
          fileConfig.path ?? '<missing-config>',
        );
      }
    }

    _section('AWiki Desktop remote Handle Recovery V1 E2E $runId');
    _line('platform: ${recoveryConfig.platform.name}');
    _line('config: ${fileConfig.path ?? '<not found>'}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('app state: ${redactor.redact(appStateRootDir.path)}');
    _line('case: ${options.e2eCase.caseName}');
    _line('flutter build dir: ${flutterBuildIsolation.buildDirectory}');
    _line('service base: ${recoveryConfig.serviceBaseUrl}');

    await _timed('Checking remote Handle Recovery tooling', () async {
      await commands.requireExecutable('flutter');
      await commands.requireExecutable('script');
      if (recoveryConfig.platform == DesktopE2ePlatform.linux) {
        await commands.requireExecutable('xvfb-run');
      }
      _identityPreflight = <String, Object?>{
        'status': options.dryRun ? 'dry_run' : 'passed',
        'auditedRemoteTarget': true,
        'automatedUserPresence': true,
        'realUserPresenceAttested': false,
        'productSmsRequestRequired': true,
        'otpMode': 'ignored_local_fixture',
        'twoIsolatedAppRoots': true,
        'containsRawDids': false,
      };
    });
    await _writeRemoteHandleRecoveryRunConfig(recoveryConfig);
    Map<String, _IsolatedAppArtifact> preparedRecoveryArtifacts =
        <String, _IsolatedAppArtifact>{};
    if (!options.dryRun &&
        !commands.dryRun &&
        (options.prepareOnly ||
            Platform.environment['AWIKI_E2E_USE_FLUTTER_TEST']?.trim() !=
                '1')) {
      preparedRecoveryArtifacts = await _timed(
        'Preparing Handle Recovery integration executables',
        () => _prepareHandleRecoveryIntegrationExecutables(
          registrationRejoin: registrationRejoin,
          freshOnly: freshOnly,
          localDataOnly: localDataOnly,
        ),
      );
    }
    if (options.prepareOnly) {
      _section('Prepare-only completed');
      _line('No remote identity or Handle Recovery operation was created.');
      return;
    }
    _resourceSideEffectsPossible = true;
    if (registrationRejoin) {
      await _timed(
        'Flutter registration re-Join and management transfer lifecycle',
        () => preparedRecoveryArtifacts.isNotEmpty
            ? _executePreparedIntegration(
                artifact: preparedRecoveryArtifacts['recovery-main']!,
                caseIds: _multiDeviceAppPairRecoveryRegistrationCaseIds,
                stateRoot: appStateRootDir,
              )
            : _runFlutterTest(
                'integration_test/handle_recovery_ui_test.dart',
                caseIds: _multiDeviceAppPairRecoveryRegistrationCaseIds,
              ),
      );
      return;
    }
    if (!options.dryRun && !commands.dryRun) {
      appStateRootDir.createSync(recursive: true);
      multiDeviceAppJoiningStateRootDir.createSync(recursive: true);
      if (freshOnly || localDataOnly) {
        if (appPairDaemonStateRootDir.existsSync()) {
          appPairDaemonStateRootDir.deleteSync(recursive: true);
        }
        appPairDaemonStateRootDir.createSync(recursive: true);
      }
    }
    if (freshOnly) {
      await _runFreshRemoteHandleRecovery(preparedRecoveryArtifacts);
      return;
    }
    final crashCaseIds = <String>[
      if (!localDataOnly) 'HANDLE-RECOVERY-V1-E2E-002',
      if (localDataOnly) 'HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001',
    ];
    await _timed('Flutter Recovery committed/reset crash-cut phase A', () {
      if (preparedRecoveryArtifacts.isNotEmpty) {
        return _executePreparedIntegration(
          artifact: preparedRecoveryArtifacts['recovery-crash-a']!,
          caseIds: crashCaseIds,
          stateRoot: appStateRootDir,
        );
      }
      return _runFlutterArgs(
        <String>[
          'test',
          '--dart-define=AWIKI_E2E=true',
          '--dart-define=AWIKI_HANDLE_RECOVERY_E2E_PHASE=crash_a',
          '--dart-define=AWIKI_E2E_HANDLE_RECOVERY_CRASH_BEFORE_PRODUCT_RESET=true',
          'integration_test/handle_recovery_ui_test.dart',
          '-d',
          platform.name,
        ],
        platform: platform,
        timeout: suiteDefinition.timeout,
        runtimeCaseIds: crashCaseIds,
      );
    });
    if (!options.dryRun && !processRestartHandoffFile.existsSync()) {
      throw E2eFailure(
        'Handle Recovery crash-cut phase A did not write its handoff evidence.',
      );
    }
    await _timed('Flutter Recovery committed/reset crash-cut phase B', () {
      if (preparedRecoveryArtifacts.isNotEmpty) {
        return _executePreparedIntegration(
          artifact: preparedRecoveryArtifacts['recovery-crash-b']!,
          caseIds: crashCaseIds,
          stateRoot: appStateRootDir,
        );
      }
      return _runFlutterArgs(
        <String>[
          'test',
          '--dart-define=AWIKI_E2E=true',
          '--dart-define=AWIKI_HANDLE_RECOVERY_E2E_PHASE=crash_b',
          'integration_test/handle_recovery_ui_test.dart',
          '-d',
          platform.name,
        ],
        platform: platform,
        timeout: suiteDefinition.timeout,
        runtimeCaseIds: crashCaseIds,
      );
    });
    if (localDataOnly) return;
    if (!options.dryRun && !commands.dryRun) {
      appStateRootDir.createSync(recursive: true);
      multiDeviceAppJoiningStateRootDir.createSync(recursive: true);
    }
    await _timed('Flutter visible Handle Recovery V1 lifecycle', () {
      if (preparedRecoveryArtifacts.isNotEmpty) {
        return _executePreparedIntegration(
          artifact: preparedRecoveryArtifacts['recovery-main']!,
          caseIds: const <String>[
            'HANDLE-RECOVERY-V1-E2E-001',
            'HANDLE-RECOVERY-V1-E2E-003',
          ],
          stateRoot: appStateRootDir,
        );
      }
      return _runFlutterTest(
        'integration_test/handle_recovery_ui_test.dart',
        caseIds: const <String>[
          'HANDLE-RECOVERY-V1-E2E-001',
          'HANDLE-RECOVERY-V1-E2E-003',
        ],
      );
    });
  }
}
