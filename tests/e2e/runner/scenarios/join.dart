// [INPUT]: Remote Join selector, audited config, prepared executable, and isolated roots.
// [OUTPUT]: Two-direction Join lifecycle plan and private runtime config.
// [POS]: Remote Join orchestration; product actions and assertions remain in Flutter/Core.

part of '../../runner.dart';

String dshRevokeOtpForJoin({required String explicit, required String fixed}) {
  final selected = explicit.trim();
  return selected.isNotEmpty ? selected : fixed.trim();
}

extension DesktopE2eJoinScenario on DesktopE2eRunner {
  Future<void> _runRemoteMultiDeviceJoin({List<String>? caseIds}) async {
    final fullRootTransfer = options.e2eCase == DesktopE2eCase.rootTransfer;
    final requestedCaseIds = caseIds ?? options.e2eCase.caseIds;
    final includesDshInterop = requestedCaseIds.contains('DEVICE-JOIN-E2E-006');
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
    final configuredDshRevokeOtp =
        Platform.environment['AWIKI_DSH_HANDLE_REVOKE_OTP']?.trim() ?? '';
    final dshRevokeOtp = dshRevokeOtpForJoin(
      explicit: configuredDshRevokeOtp,
      fixed: joinConfig.fixedOtp,
    );
    if (dshRevokeOtp.isNotEmpty) _addRuntimeSecret(dshRevokeOtp);
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
      if (includesDshInterop) {
        await commands.requireExecutable('node');
        final dshRoot = Directory(
          Directory('../dsh-awiki').absolute.resolveSymbolicLinksSync(),
        );
        await commands.requireFile(
          '${dshRoot.path}/scripts/device-join-e2e.mjs',
        );
        await commands.requireFile('${dshRoot.path}/lib/index.js');
        final manifest = jsonDecode(
          File('${dshRoot.path}/package.json').readAsStringSync(),
        );
        if (manifest is! Map ||
            (manifest['dependencies'] as Map?)?['@awiki/im-core-node'] !=
                '0.2.3') {
          throw E2eFailure('DSH E2E requires @awiki/im-core-node 0.2.3.');
        }
        if (!options.dryRun &&
            !commands.dryRun &&
            !isSixDigitAsciiOtp(dshRevokeOtp)) {
          throw E2eFailure(
            'The reviewed DSH Handle-revoke factor fixture is unavailable.',
          );
        }
      }
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
    const joiningAppCaseIds = <String>{
      'DEVICE-JOIN-E2E-001',
      'DEVICE-JOIN-E2E-006',
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
            environment: <String, String>{
              _multiDeviceRemoteJoinGateEnv: '1',
              if (includesDshInterop)
                'AWIKI_DSH_HANDLE_REVOKE_OTP': dshRevokeOtp,
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
      'dshDevice': <String, Object?>{
        'repoRoot': Directory(
          '../dsh-awiki',
        ).absolute.resolveSymbolicLinksSync(),
        'stateRoot': dshStateRootDir.path,
        'appStateRoot': dshAppStateRootDir.path,
        'nodePackageVersion': '0.2.3',
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
