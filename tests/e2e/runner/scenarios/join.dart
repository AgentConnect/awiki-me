// [INPUT]: Remote Join selector, audited config, prepared executable, and isolated roots.
// [OUTPUT]: Two-direction Join lifecycle plan and private runtime config.
// [POS]: Remote Join orchestration; product actions and assertions remain in Flutter/Core.

part of '../../runner.dart';

extension DesktopE2eJoinScenario on DesktopE2eRunner {
  Future<void> _runRemoteMultiDeviceJoin({List<String>? caseIds}) async {
    final fullRootTransfer = options.e2eCase == DesktopE2eCase.rootTransfer;
    final joinConfig = RemoteMultiDeviceJoinConfig.from(
      fileConfig: fileConfig,
      environment: fullRootTransfer
          ? <String, String>{
              ...Platform.environment,
              _multiDeviceRemoteJoinGateEnv: '1',
            }
          : Platform.environment,
      supportedPlatforms:
          options.e2eCase == DesktopE2eCase.multiDeviceRemoteJoin ||
              fullRootTransfer
          ? const <DesktopE2ePlatform>{
              DesktopE2ePlatform.macos,
              DesktopE2ePlatform.linux,
            }
          : const <DesktopE2ePlatform>{
              DesktopE2ePlatform.macos,
              DesktopE2ePlatform.linux,
            },
    );
    remoteMultiDeviceJoinConfig = joinConfig;
    _addRuntimeSecret(joinConfig.phone);
    _addRuntimeSecret(joinConfig.fixedOtp);
    _addRuntimeSecret(joinConfig.cliBin);
    if (!options.dryRun && !commands.dryRun) {
      suiteDefinition.validateRemoteTargetValues(
        didDomain: joinConfig.didDomain,
        serviceUrls: <String>[
          joinConfig.serviceBaseUrl,
          joinConfig.userServiceUrl,
          joinConfig.messageServiceUrl,
        ],
      );
    }

    _section(
      'AWiki Desktop remote multi-device bidirectional management E2E $runId',
    );
    _line('platform: ${joinConfig.platform.name}');
    _line('config: ${fileConfig.path ?? '<not found>'}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('cli workspace: ${redactor.redact(cliWorkspaceDir.path)}');
    _line('cli home: ${redactor.redact(cliHomeDir.path)}');
    _line('app state: ${redactor.redact(appStateRootDir.path)}');
    _line('case: ${options.e2eCase.caseName}');
    _line('flutter build dir: ${flutterBuildIsolation.buildDirectory}');
    _line('service base: ${joinConfig.serviceBaseUrl}');

    await _timed('Checking remote Join tooling and source', () async {
      await commands.requireExecutable('flutter');
      await commands.requireExecutable('script');
      if (joinConfig.platform == DesktopE2ePlatform.linux) {
        await commands.requireExecutable('xvfb-run');
      }
      await commands.requireFile(joinConfig.cliBin);
      final version = await commands.captureResult(
        joinConfig.cliBin,
        const <String>['--format', 'json', 'version'],
      );
      if (!options.dryRun && !commands.dryRun) {
        cliBuildVersionFromVersionJson(version.output);
        final binaryCommit = cliBuildCommitFromVersionJson(version.output);
        if (binaryCommit != joinConfig.cliSourceRef.toLowerCase()) {
          throw E2eFailure(
            'cliPeer.sourceRef does not match the commit embedded in the CLI binary.',
          );
        }
      }
      _identityPreflight = <String, Object?>{
        'status': options.dryRun ? 'dry_run' : 'passed',
        'auditedRemoteTarget': true,
        'cliSourceVerified': !options.dryRun,
        'automatedUserPresence': true,
        'realUserPresenceAttested': false,
        'containsRawDids': false,
      };
    });

    await _writeRemoteMultiDeviceJoinRunConfig(joinConfig);
    _IsolatedAppArtifact? preparedJoinArtifact;
    if (!options.dryRun &&
        !commands.dryRun &&
        (options.prepareOnly ||
            Platform.environment['AWIKI_E2E_USE_FLUTTER_TEST']?.trim() !=
                '1')) {
      preparedJoinArtifact = await _timed(
        'Preparing remote Join integration executable',
        () => _prepareIntegrationExecutable(
          name: 'remote-join',
          target: 'integration_test/multi_device_join_ui_test.dart',
          bundleId: 'ai.awiki.awikime.dev.e2e.remote.join',
          stateRoot: appStateRootDir,
        ),
      );
    }
    if (options.prepareOnly) {
      _section('Prepare-only completed');
      _line('No remote identity or Join session was created.');
      return;
    }
    _resourceSideEffectsPossible = true;
    final requestedCaseIds = caseIds ?? options.e2eCase.caseIds;
    const joiningAppCaseIds = <String>{
      'DEVICE-JOIN-E2E-001',
      'DEVICE-JOIN-MESSAGE-CORE-E2E-001',
    };
    final joiningAppCases = requestedCaseIds
        .where(joiningAppCaseIds.contains)
        .toList(growable: false);
    final adminAppCases = requestedCaseIds
        .where((caseId) => !joiningAppCaseIds.contains(caseId))
        .toList(growable: false);
    final adminAppStateRoot = fullRootTransfer
        ? rootTransferAppAdminStateRootDir
        : appStateRootDir;
    if (joiningAppCases.isNotEmpty) {
      await _timed('Flutter joining App + CLI admin lifecycle', () {
        if (preparedJoinArtifact != null) {
          return _executePreparedIntegration(
            artifact: preparedJoinArtifact,
            caseIds: joiningAppCases,
            stateRoot: multiDeviceAppJoiningStateRootDir,
            environment: const <String, String>{
              _multiDeviceRemoteJoinGateEnv: '1',
            },
          );
        }
        return _runFlutterTest(
          'integration_test/multi_device_join_ui_test.dart',
          caseIds: joiningAppCases,
          appStateRoot: multiDeviceAppJoiningStateRootDir,
        );
      });
    }
    if (adminAppCases.isNotEmpty) {
      if (!options.dryRun && !commands.dryRun) {
        adminAppStateRoot.createSync(recursive: true);
        cliWorkspaceDir.createSync(recursive: true);
        cliHomeDir.createSync(recursive: true);
      }
      await _timed('Flutter admin App + CLI joining lifecycle', () {
        if (preparedJoinArtifact != null) {
          return _executePreparedIntegration(
            artifact: preparedJoinArtifact,
            caseIds: adminAppCases,
            stateRoot: adminAppStateRoot,
            environment: const <String, String>{
              _multiDeviceRemoteJoinGateEnv: '1',
            },
          );
        }
        return _runFlutterTest(
          'integration_test/multi_device_join_ui_test.dart',
          caseIds: adminAppCases,
          appStateRoot: adminAppStateRoot,
        );
      });
    }
  }

  Future<void> _writeRemoteMultiDeviceJoinRunConfig(
    RemoteMultiDeviceJoinConfig joinConfig,
  ) async {
    final fullRootTransferOnly = options.e2eCase == DesktopE2eCase.rootTransfer;
    final payload = <String, Object?>{
      'schemaVersion': 2,
      'enabled': true,
      'runId': runId,
      'platform': joinConfig.platform.name,
      'service': <String, Object?>{
        'baseUrl': joinConfig.serviceBaseUrl,
        'userServiceUrl': joinConfig.userServiceUrl,
        'messageServiceUrl': joinConfig.messageServiceUrl,
        'mailServiceUrl': joinConfig.mailServiceUrl,
        'didDomain': joinConfig.didDomain,
        'anpServiceUrl': joinConfig.anpServiceUrl,
        'anpServiceDid': joinConfig.anpServiceDid,
      },
      'account': <String, Object?>{
        'handlePrefix': joinConfig.handlePrefix,
        'otpMode': 'ignored_local_fixture',
        'localConfigPath': fileConfig.path,
      },
      'testControl': <String, Object?>{'automatedUserPresence': true},
      'cliJoiningDevice': <String, Object?>{
        'binary': joinConfig.cliBin,
        'sourceRef': joinConfig.cliSourceRef,
        'workspace': fullRootTransferOnly
            ? rootTransferCliMemberWorkspaceDir.path
            : cliWorkspaceDir.path,
        'home': fullRootTransferOnly
            ? rootTransferCliMemberHomeDir.path
            : cliHomeDir.path,
      },
      'cliAdminDevice': <String, Object?>{
        'binary': joinConfig.cliBin,
        'sourceRef': joinConfig.cliSourceRef,
        'workspace': fullRootTransferOnly
            ? cliWorkspaceDir.path
            : multiDeviceCliAdminWorkspaceDir.path,
        'home': fullRootTransferOnly
            ? cliHomeDir.path
            : multiDeviceCliAdminHomeDir.path,
      },
      'app': <String, Object?>{
        'stateRoot': fullRootTransferOnly
            ? rootTransferAppAdminStateRootDir.path
            : appStateRootDir.path,
      },
      'appJoiningDevice': <String, Object?>{
        'stateRoot': fullRootTransferOnly
            ? appStateRootDir.path
            : multiDeviceAppJoiningStateRootDir.path,
      },
      'suite': <String, Object?>{
        'manifestRevision': suiteManifest.sourceRevision,
        'tier': suiteDefinition.tier,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
      },
    };
    if (options.dryRun) {
      _line('would write remote multi-device Join run config');
      return;
    }
    await remoteMultiDeviceRunConfigFile.parent.create(recursive: true);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>[
        '700',
        remoteMultiDeviceRunConfigFile.parent.path,
      ]);
    }
    await remoteMultiDeviceRunConfigFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>[
        '600',
        remoteMultiDeviceRunConfigFile.path,
      ]);
    }
  }
}
