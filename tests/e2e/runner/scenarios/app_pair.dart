// [INPUT]: App-pair suite selector, two isolated roots, verified role artifacts, and loopback coordinator.
// [OUTPUT]: Prepared or executed two-App lifecycle with bounded driver evidence and cleanup.
// [POS]: App-pair orchestration; product Join/message assertions remain in Flutter scenarios.

part of '../../runner.dart';

extension DesktopE2eAppPairScenario on DesktopE2eRunner {
  Future<void> _runRemoteMultiDeviceAppPair() async {
    final flutterBin =
        Platform.environment['AWIKI_E2E_FLUTTER_BIN']?.trim().isNotEmpty == true
        ? Platform.environment['AWIKI_E2E_FLUTTER_BIN']!.trim()
        : 'flutter';
    final pairConfig = RemoteMultiDeviceAppPairConfig.from(
      fileConfig: fileConfig,
      environment: Platform.environment,
      functional:
          options.e2eCase == DesktopE2eCase.multiDeviceAppPairFunctional,
      contentSync:
          options.e2eCase == DesktopE2eCase.multiDeviceAppPairContentSync,
    );
    remoteMultiDeviceAppPairConfig = pairConfig;
    _addRuntimeSecret(pairConfig.phone);
    _addRuntimeSecret(pairConfig.fixedOtp);
    _addRuntimeSecret(pairConfig.cliBin ?? '');
    _addRuntimeSecret(pairConfig.daemonBinary ?? '');
    _addRuntimeSecret(pairConfig.daemonEnvFile ?? '');
    if (!options.dryRun && !commands.dryRun) {
      suiteDefinition.validateRemoteTargetValues(
        didDomain: pairConfig.didDomain,
        serviceUrls: <String>[
          pairConfig.serviceBaseUrl,
          pairConfig.userServiceUrl,
          pairConfig.messageServiceUrl,
        ],
      );
    }

    _section('AWiki Desktop isolated App + App multi-device E2E $runId');
    _line('platform: ${pairConfig.platform.name}');
    _line('config: ${fileConfig.path ?? '<not found>'}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('admin state: ${redactor.redact(appPairAdminStateRootDir.path)}');
    _line('joiner state: ${redactor.redact(appPairJoinerStateRootDir.path)}');
    _line('artifacts: ${redactor.redact(appPairArtifactRootDir.path)}');
    _line('case: ${options.e2eCase.caseName}');
    _line('service base: ${pairConfig.serviceBaseUrl}');

    await _timed('Checking App-pair tooling and source', () async {
      await commands.requireExecutable(flutterBin);
      await commands.requireExecutable('dart');
      if (pairConfig.platform == DesktopE2ePlatform.linux) {
        await commands.requireExecutable('xvfb-run');
        await commands.requireFile('tool/ensure_linux_im_core.dart');
        if (!options.dryRun && !commands.dryRun) {
          await LinuxImCoreArtifactGuard(projectRoot: root).ensure();
        }
      }
      await commands.requireFile('tool/build_isolated_e2e_app.dart');
      await commands.requireFile(_multiDeviceAppPairTarget);
      await commands.requireFile('test_driver/integration_test.dart');
      if (pairConfig.functional) {
        _requireAppPairRecoveryOperatorEnvironment(Platform.environment);
        _requireAppPairAccountStateOperatorEnvironment(
          root: root,
          environment: Platform.environment,
        );
        if (!daemonStateRootFitsUnixSocket(appPairDaemonStateRootDir.path)) {
          throw E2eFailure(
            'The App-pair Daemon state root exceeds the macOS Unix-domain socket path limit.',
          );
        }
        await commands.requireFile(pairConfig.daemonBinary!);
        if (pairConfig.daemonEnvFile != null) {
          await commands.requireFile(pairConfig.daemonEnvFile!);
        }
      }
      if (pairConfig.functional || pairConfig.contentSync) {
        await commands.requireFile(pairConfig.cliBin!);
        final version = await commands.captureResult(pairConfig.cliBin!, const [
          '--format',
          'json',
          'version',
        ]);
        if (!options.dryRun && !commands.dryRun) {
          cliBuildVersionFromVersionJson(version.output);
          final binaryCommit = cliBuildCommitFromVersionJson(version.output);
          if (binaryCommit != pairConfig.cliSourceRef) {
            throw E2eFailure(
              'cliPeer.sourceRef does not match the commit embedded in the CLI binary.',
            );
          }
        }
      }
      _identityPreflight = <String, Object?>{
        'status': options.dryRun ? 'dry_run' : 'passed',
        'auditedRemoteTarget': true,
        'twoIsolatedAppProcesses': true,
        'automatedUserPresence': true,
        'realUserPresenceAttested': false,
        'cliSourceVerified':
            (pairConfig.functional || pairConfig.contentSync) &&
            !options.dryRun &&
            !commands.dryRun,
        'containsRawDids': false,
      };
    });

    if (options.prepareOnly) {
      if (options.dryRun || commands.dryRun) {
        _line('would build and validate isolated admin and joiner Apps');
      } else {
        await _withFlutterExecutionLease(pairConfig.platform, runId, () async {
          final competingPids = await competingFlutterIntegrationTestPids();
          if (competingPids.isNotEmpty) {
            throw E2eFailure(
              'Another Flutter integration test is already running '
              '(pids=${competingPids.join(',')}); refusing to share the '
              'desktop build environment.',
            );
          }
          await _buildAndValidateAppPairRoles(
            flutterBin: flutterBin,
            platform: pairConfig.platform,
          );
        });
      }
      _section('Prepare-only completed');
      _line(
        'Both isolated App roles were prepared; no coordinator, App process, '
        'or remote account was created.',
      );
      return;
    }
    if (options.dryRun || commands.dryRun) {
      _line(
        'would build, launch, and concurrently drive isolated admin and '
        'joiner Debug Apps',
      );
      return;
    }

    _resourceSideEffectsPossible = true;
    await _timed('Two isolated Flutter App member-Join lifecycle', () {
      return _withFlutterExecutionLease(pairConfig.platform, runId, () async {
        final competingPids = await competingFlutterIntegrationTestPids();
        if (competingPids.isNotEmpty) {
          throw E2eFailure(
            'Another Flutter integration test is already running '
            '(pids=${competingPids.join(',')}); refusing to share the '
            'desktop device.',
          );
        }
        final token = _newAppPairToken();
        _addRuntimeSecret(token);
        final coordinator = await AppPairCoordinatorServer.start(token: token);
        _RunningIsolatedApp? adminApp;
        _RunningIsolatedApp? joinerApp;
        try {
          await _writeAppPairRunConfig(pairConfig, coordinator, token);
          final artifacts = await _buildAndValidateAppPairRoles(
            flutterBin: flutterBin,
            platform: pairConfig.platform,
          );
          final productEnvironment = <String, String>{
            _multiDeviceRemoteJoinGateEnv: '1',
            'AWIKI_MULTI_DEVICE_APP_PAIR_CONFIG': appPairRunConfigFile.path,
            e2eCaseAttestationPathDefine: caseAttestationFile.path,
            e2eCaseScenarioDefine: options.e2eCase.scenario,
            e2eCaseRunIdDefine: runId,
            e2eCaseIdsDefine: options.e2eCase.caseIds.join(','),
            if (pairConfig.functional) ...<String, String>{
              _syncRecoveryEnableEnv:
                  Platform.environment[_syncRecoveryEnableEnv]!,
              _syncRecoveryOperatorModeEnv:
                  Platform.environment[_syncRecoveryOperatorModeEnv]!,
              _syncRecoveryTargetEnv:
                  Platform.environment[_syncRecoveryTargetEnv]!,
              _accountStateEnableEnv:
                  Platform.environment[_accountStateEnableEnv]!,
              _accountStateOperatorCommandEnv:
                  Platform.environment[_accountStateOperatorCommandEnv]!,
              _accountStateFailpointEnableEnv:
                  Platform.environment[_accountStateFailpointEnableEnv]!,
            },
          };
          adminApp = await _RunningIsolatedApp.start(
            role: 'admin',
            artifact: artifacts.admin,
            environment: productEnvironment,
            platform: pairConfig.platform,
          );
          joinerApp = await _RunningIsolatedApp.start(
            role: 'joiner',
            artifact: artifacts.joiner,
            environment: productEnvironment,
            platform: pairConfig.platform,
          );
          await _driveAppPair(
            adminApp: adminApp,
            joinerApp: joinerApp,
            flutterBin: flutterBin,
            platform: pairConfig.platform,
            timeout: suiteDefinition.timeout,
          );
        } finally {
          await Future.wait(<Future<void>>[
            if (adminApp != null) adminApp.close(commands),
            if (joinerApp != null) joinerApp.close(commands),
          ]);
          await coordinator.close();
          if (appPairRunConfigFile.existsSync()) {
            appPairRunConfigFile.deleteSync();
          }
          await _deleteDirectoryBestEffort(appPairAdminStateRootDir);
          await _deleteDirectoryBestEffort(appPairJoinerStateRootDir);
          await _deleteDirectoryBestEffort(appPairDaemonStateRootDir);
          if (pairConfig.functional || pairConfig.contentSync) {
            await _deleteDirectoryBestEffort(cliWorkspaceDir);
            await _deleteDirectoryBestEffort(cliHomeDir);
          }
          if (appPairDaemonReadyFile.existsSync()) {
            appPairDaemonReadyFile.deleteSync();
          }
        }
      });
    });
  }

  Future<void> _writeAppPairRunConfig(
    RemoteMultiDeviceAppPairConfig pairConfig,
    AppPairCoordinatorServer coordinator,
    String token,
  ) async {
    final payload = <String, Object?>{
      'schemaVersion': 2,
      'enabled': true,
      'runId': runId,
      'service': <String, Object?>{
        'baseUrl': pairConfig.serviceBaseUrl,
        'userServiceUrl': pairConfig.userServiceUrl,
        'messageServiceUrl': pairConfig.messageServiceUrl,
        'mailServiceUrl': pairConfig.mailServiceUrl,
        'didDomain': pairConfig.didDomain,
        'anpServiceUrl': pairConfig.anpServiceUrl,
        'anpServiceDid': pairConfig.anpServiceDid,
      },
      'account': <String, Object?>{
        'handlePrefix': pairConfig.handlePrefix,
        'otpMode': 'ignored_local_fixture',
        'localConfigPath': fileConfig.path,
      },
      'testControl': <String, Object?>{'automatedUserPresence': true},
      'coordinator': <String, Object?>{
        'baseUrl': coordinator.endpoint.toString(),
        'token': token,
      },
      'apps': <String, Object?>{
        'admin': <String, Object?>{
          'stateRoot': appPairAdminStateRootDir.path,
          'bundleId': 'ai.awiki.awikime.dev.e2e.pair.admin',
        },
        'joiner': <String, Object?>{
          'stateRoot': appPairJoinerStateRootDir.path,
          'bundleId': 'ai.awiki.awikime.dev.e2e.pair.joiner',
        },
      },
      if (pairConfig.functional)
        'functional': <String, Object?>{
          'cliPeer': <String, Object?>{
            'binary': pairConfig.cliBin,
            'sourceRef': pairConfig.cliSourceRef,
            'workspace': cliWorkspaceDir.path,
            'home': cliHomeDir.path,
          },
          'daemon': <String, Object?>{
            'binary': pairConfig.daemonBinary,
            'stateRoot': appPairDaemonStateRootDir.path,
            'readyFile': appPairDaemonReadyFile.path,
            'handle': pairConfig.daemonHandle,
            'envFile': pairConfig.daemonEnvFile,
          },
          'accountState': <String, Object?>{
            'operatorCommand': _accountStateOperatorCommand(
              Platform.environment,
            ),
          },
        },
      if (pairConfig.contentSync)
        'contentSync': <String, Object?>{
          'cliPeer': <String, Object?>{
            'binary': pairConfig.cliBin,
            'sourceRef': pairConfig.cliSourceRef,
            'workspace': cliWorkspaceDir.path,
            'home': cliHomeDir.path,
          },
        },
      'suite': <String, Object?>{
        'manifestRevision': suiteManifest.sourceRevision,
        'tier': suiteDefinition.tier,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
      },
    };
    await appPairRunConfigFile.parent.create(recursive: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>[
        '700',
        appPairRunConfigFile.parent.path,
      ]);
    }
    await appPairRunConfigFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['600', appPairRunConfigFile.path]);
    }
  }

  Future<_IsolatedAppArtifact> _buildAppPairRole({
    required String role,
    required String bundleId,
    required String flutterBin,
    required DesktopE2ePlatform platform,
  }) async {
    final roleWorkRoot = Directory('${appPairBuildRootDir.path}/$role');
    final result = await commands.captureResult('dart', <String>[
      'tool/build_isolated_e2e_app.dart',
      '--name=$role',
      '--target=$_multiDeviceAppPairTarget',
      '--state-root=${role == 'admin' ? appPairAdminStateRootDir.path : appPairJoinerStateRootDir.path}',
      '--work-root=${roleWorkRoot.path}',
      '--artifact-root=${appPairArtifactRootDir.path}',
      '--bundle-id=$bundleId',
      '--platform=${platform.name}',
      '--flutter-bin=$flutterBin',
      '--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=$role',
    ], timeout: const Duration(minutes: 12));
    return _IsolatedAppArtifact.fromBuilderOutput(result.output);
  }

  Future<({_IsolatedAppArtifact admin, _IsolatedAppArtifact joiner})>
  _buildAndValidateAppPairRoles({
    required String flutterBin,
    required DesktopE2ePlatform platform,
  }) async {
    final admin = await _timed(
      'Building isolated App-pair admin artifact',
      () => _buildAppPairRole(
        role: 'admin',
        bundleId: 'ai.awiki.awikime.dev.e2e.pair.admin',
        flutterBin: flutterBin,
        platform: platform,
      ),
    );
    final joiner = await _timed(
      'Building isolated App-pair joiner artifact',
      () => _buildAppPairRole(
        role: 'joiner',
        bundleId: 'ai.awiki.awikime.dev.e2e.pair.joiner',
        flutterBin: flutterBin,
        platform: platform,
      ),
    );
    if (admin.bundleId == joiner.bundleId ||
        admin.executable.path == joiner.executable.path ||
        appPairAdminStateRootDir.path == appPairJoinerStateRootDir.path) {
      throw E2eFailure(
        'The two App roles did not receive independent bundle, artifact, '
        'and state identities.',
      );
    }
    return (admin: admin, joiner: joiner);
  }

  Future<void> _driveAppPair({
    required _RunningIsolatedApp adminApp,
    required _RunningIsolatedApp joinerApp,
    required String flutterBin,
    required DesktopE2ePlatform platform,
    required Duration timeout,
  }) async {
    final locale = desktopE2eUtf8Locale(
      platform: platform,
      lang: Platform.environment['LANG'],
      lcAll: Platform.environment['LC_ALL'],
    );
    final adminDriver = await _RunningAppPairDriver.start(
      role: 'admin',
      flutterBin: flutterBin,
      vmServiceUri: adminApp.vmServiceUri,
      root: root,
      flutterConfigDirectory: Directory(
        '${appPairBuildRootDir.path}/admin/flutter-config',
      ),
      locale: locale,
      platform: platform,
      redactor: redactor,
    );
    _RunningAppPairDriver? joinerDriver;
    try {
      joinerDriver = await _RunningAppPairDriver.start(
        role: 'joiner',
        flutterBin: flutterBin,
        vmServiceUri: joinerApp.vmServiceUri,
        root: root,
        flutterConfigDirectory: Directory(
          '${appPairBuildRootDir.path}/joiner/flutter-config',
        ),
        locale: locale,
        platform: platform,
        redactor: redactor,
      );
      final exits = <Future<MapEntry<String, int>>>[
        adminDriver.exitCode.then(
          (code) => MapEntry<String, int>('admin', code),
        ),
        joinerDriver.exitCode.then(
          (code) => MapEntry<String, int>('joiner', code),
        ),
      ];
      final deadline = DateTime.now().add(timeout);
      Duration remaining() {
        final value = deadline.difference(DateTime.now());
        return value.isNegative ? Duration.zero : value;
      }

      final first = await Future.any(exits).timeout(remaining());
      if (first.value != 0) {
        final failedDriver = first.key == 'admin' ? adminDriver : joinerDriver;
        throw E2eFailure(
          'The isolated ${first.key} App integration driver failed.\n'
          '${failedDriver.diagnosticTail}',
        );
      }
      final results = await Future.wait(exits).timeout(remaining());
      MapEntry<String, int>? failed;
      for (final result in results) {
        if (result.value != 0) {
          failed = result;
          break;
        }
      }
      if (failed != null) {
        final failedDriver = failed.key == 'admin' ? adminDriver : joinerDriver;
        throw E2eFailure(
          'The isolated ${failed.key} App integration driver failed.\n'
          '${failedDriver.diagnosticTail}',
        );
      }
    } on TimeoutException {
      throw DesktopCommandTimeout(
        executable: 'flutter drive (App pair)',
        timeout: timeout,
        terminated: true,
      );
    } finally {
      await Future.wait(<Future<void>>[
        adminDriver.close(commands),
        if (joinerDriver != null) joinerDriver.close(commands),
      ]);
    }
  }
}
