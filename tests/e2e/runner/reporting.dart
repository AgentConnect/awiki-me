// [INPUT]: Scenario timings, case attestation, failure observation, resources, and platform facts.
// [OUTPUT]: Fail-closed schema-v2 report, resource ledger, and redacted console summary.
// [POS]: Runner evidence boundary; never performs product actions.

part of '../runner.dart';

extension DesktopE2eReporting on DesktopE2eRunner {
  Future<T> _timed<T>(String name, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      final result = await action();
      succeeded = true;
      return result;
    } finally {
      stopwatch.stop();
      _timings.add(
        DesktopTimingEntry(
          name: name,
          elapsed: stopwatch.elapsed,
          succeeded: succeeded,
        ),
      );
    }
  }

  String get _timingsPath => '${reportDir.path}/timings.json';

  Map<String, Object?> _readScenarioProgressSummary() {
    if (!scenarioProgressFile.existsSync()) {
      return const <String, Object?>{
        'status': 'missing',
        'lastPhase': null,
        'phaseCount': 0,
      };
    }
    try {
      final decoded = jsonDecode(scenarioProgressFile.readAsStringSync());
      final phases = decoded is Map && decoded['phases'] is List
          ? decoded['phases'] as List
          : const <Object?>[];
      final last = phases.isEmpty ? null : phases.last;
      final lastPhase = last is Map ? last['phase'] : null;
      return <String, Object?>{
        'status': 'available',
        'lastPhase': lastPhase is String ? lastPhase : null,
        'phaseCount': phases.length,
        'path': '<redacted-scenario-progress-path>',
      };
    } on Object {
      return const <String, Object?>{
        'status': 'invalid',
        'lastPhase': null,
        'phaseCount': 0,
      };
    }
  }

  Map<String, Object?> _readFailureObservationSummary() {
    if (!failureObservationFile.existsSync()) {
      return const <String, Object?>{'status': 'not_observed'};
    }
    try {
      final observation = E2eFailureObservation.read(failureObservationFile);
      if (observation.scenario != options.e2eCase.scenario ||
          observation.runId != runId) {
        return const <String, Object?>{'status': 'invalid'};
      }
      return <String, Object?>{
        'status': 'observed',
        'layer': observation.layer,
        'failureStatus': observation.status,
        'code': observation.code,
        'observedAt': observation.observedAt,
        if (observation.caseId != null) 'caseId': observation.caseId,
        'path': '<redacted-failure-observation-path>',
      };
    } on Object {
      return const <String, Object?>{'status': 'invalid'};
    }
  }

  DesktopProductTimingReport _readProductTimingReport() {
    if (!productTimingsFile.existsSync()) {
      throw E2eFailure(
        'Performance product timing report was not written: '
        '${productTimingsFile.path}',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(productTimingsFile.readAsStringSync());
    } on Object catch (error) {
      throw E2eFailure(
        'Performance product timing report is not valid JSON: $error',
      );
    }
    if (decoded is! Map) {
      throw E2eFailure(
        'Performance product timing report must be a JSON object.',
      );
    }
    return DesktopProductTimingReport.fromJson(<String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    });
  }

  void _loadCaseAttestation({required bool requireComplete}) {
    try {
      final attestation = E2eCaseAttestation.read(caseAttestationFile);
      final validation = E2eCaseAttestationValidation.validate(
        attestation: attestation,
        expectedScenario: options.e2eCase.scenario,
        expectedRunId: runId,
        expectedCaseIds: suiteDefinition.caseIds,
      );
      _attestedCases
        ..clear()
        ..addEntries(
          validation.caseById.entries.where(
            (entry) => suiteDefinition.caseIds.contains(entry.key),
          ),
        );
      _caseAttestationError = validation.passed
          ? null
          : validation.errors.join('; ');
      if (!requireComplete) {
        return;
      }
      if (!validation.passed) {
        throw FormatException(validation.errors.join('; '));
      }
    } on Object catch (error) {
      final message = redactor.redact(error.toString());
      _caseAttestationError = message;
      if (requireComplete) {
        throw E2eFailure('E2E case attestation failed closed: $message');
      }
    }
  }

  String _caseStatus(String caseId) {
    if (options.dryRun) {
      return 'dry_run';
    }
    if (options.prepareOnly) {
      return 'prepared';
    }
    final attested = _attestedCases[caseId]?.status;
    if (attested != null) {
      return attested;
    }
    if (failureObservationFile.existsSync()) {
      try {
        if (E2eFailureObservation.read(failureObservationFile).caseId ==
            caseId) {
          return 'failed';
        }
      } on Object {
        // The report exposes invalid failure evidence separately.
      }
    }
    return 'not_run';
  }

  String _suiteStatus({required bool orchestrationSucceeded}) {
    if (!orchestrationSucceeded) {
      return 'failed';
    }
    if (options.dryRun) {
      return 'dry_run';
    }
    if (options.prepareOnly) {
      return 'prepared';
    }
    final allPassed = suiteDefinition.caseIds.every(
      (caseId) => _caseStatus(caseId) == 'passed',
    );
    return orchestrationSucceeded && allPassed ? 'passed' : 'failed';
  }

  void _writeTimingReport({
    required bool orchestrationSucceeded,
    required Duration totalElapsed,
  }) {
    final productTimingReport = _productTimingReport;
    final performanceBudgetResult = _performanceBudgetResult;
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(_timingsPath);
    if (!options.dryRun) {
      reportDir.createSync(recursive: true);
    }
    file.writeAsStringSync(
      encoder.convert(<String, Object?>{
        'schemaVersion': 2,
        'status': _suiteStatus(orchestrationSucceeded: orchestrationSucceeded),
        'mode': options.dryRun
            ? 'dry_run'
            : options.prepareOnly
            ? 'prepared'
            : 'real',
        'scenario': (config?.e2eCase ?? options.e2eCase).scenario,
        'caseIds': suiteDefinition.caseIds,
        'passedCaseIds': <String>[
          for (final caseId in suiteDefinition.caseIds)
            if (_caseStatus(caseId) == 'passed') caseId,
        ],
        'caseResults': <Map<String, Object?>>[
          for (final caseId in suiteDefinition.caseIds)
            <String, Object?>{
              'caseId': caseId,
              'status': _caseStatus(caseId),
              'mode': options.dryRun
                  ? 'dry_run'
                  : options.prepareOnly
                  ? 'prepared'
                  : 'real',
              if (_attestedCases[caseId] != null)
                'startedAt': _attestedCases[caseId]!.startedAt,
              if (_attestedCases[caseId] != null)
                'finishedAt': _attestedCases[caseId]!.finishedAt,
              'phases': _attestedCases[caseId]?.phases ?? const <String>[],
              'assertions': <Map<String, Object?>>[
                for (final assertion
                    in _attestedCases[caseId]?.assertions ??
                        const <E2eAssertionEvidence>[])
                  assertion.toJson(),
              ],
            },
        ],
        'attestation': <String, Object?>{
          'schemaVersion': e2eCaseAttestationSchemaVersion,
          'path': '<redacted-attestation-path>',
          'status': options.dryRun
              ? 'not_expected_dry_run'
              : options.prepareOnly
              ? 'not_expected_prepared'
              : _caseAttestationError == null &&
                    suiteDefinition.caseIds.every(
                      (caseId) => _caseStatus(caseId) == 'passed',
                    )
              ? 'verified'
              : 'invalid',
          if (_caseAttestationError != null) 'error': _caseAttestationError,
        },
        'failureObservation': _readFailureObservationSummary(),
        'runId': runId,
        'awikiMeSourceRef': _repositorySourceRef(),
        'platform': platform.name,
        'hostPlatform': hostPlatform.toJson(),
        'case': (config?.e2eCase ?? options.e2eCase).caseName,
        'suiteManifest': <String, Object?>{
          'schemaVersion': suiteManifest.schemaVersion,
          'sourceRevision': suiteManifest.sourceRevision,
          'path': desktopE2eSuiteManifestPath,
        },
        'suitePolicy': suiteDefinition.toReportJson(),
        'dryRun': options.dryRun,
        'prepareOnly': options.prepareOnly,
        'configPath': fileConfig.path == null ? null : '<redacted-config-path>',
        if (config != null) 'serviceBaseUrl': config!.serviceBaseUrl,
        if (config != null)
          'userServiceUrl': config!.userServiceUrl ?? config!.serviceBaseUrl,
        if (config != null)
          'messageServiceUrl':
              config!.messageServiceUrl ?? config!.serviceBaseUrl,
        if (config != null) 'messageServiceWsUrl': config!.messageServiceWsUrl,
        if (config != null) 'mailServiceUrl': config!.mailServiceUrl,
        if (config != null) 'anpServiceUrl': config!.anpServiceUrl,
        if (config != null)
          'anpServiceDid': config!.anpServiceDid == null
              ? null
              : '<redacted-service-did>',
        if (config != null) 'didDomain': config!.didDomain,
        if (config != null) 'appHandle': config!.appHandle,
        if (config != null) 'cliHandle': config!.cliHandle,
        if (config != null) 'cliSourceRef': config!.cliSourceRef,
        if (remoteMultiDeviceJoinConfig != null)
          'serviceBaseUrl': remoteMultiDeviceJoinConfig!.serviceBaseUrl,
        if (remoteMultiDeviceJoinConfig != null)
          'userServiceUrl': remoteMultiDeviceJoinConfig!.userServiceUrl,
        if (remoteMultiDeviceJoinConfig != null)
          'messageServiceUrl': remoteMultiDeviceJoinConfig!.messageServiceUrl,
        if (remoteMultiDeviceJoinConfig != null)
          'mailServiceUrl': remoteMultiDeviceJoinConfig!.mailServiceUrl,
        if (remoteMultiDeviceJoinConfig != null)
          'anpServiceUrl': remoteMultiDeviceJoinConfig!.anpServiceUrl,
        if (remoteMultiDeviceJoinConfig != null)
          'anpServiceDid': '<redacted-service-did>',
        if (remoteMultiDeviceJoinConfig != null)
          'didDomain': remoteMultiDeviceJoinConfig!.didDomain,
        if (remoteMultiDeviceJoinConfig != null)
          'cliSourceRef': remoteMultiDeviceJoinConfig!.cliSourceRef,
        if (remoteHandleRecoveryConfig != null)
          'serviceBaseUrl': remoteHandleRecoveryConfig!.serviceBaseUrl,
        if (remoteHandleRecoveryConfig != null)
          'userServiceUrl': remoteHandleRecoveryConfig!.userServiceUrl,
        if (remoteHandleRecoveryConfig != null)
          'messageServiceUrl': remoteHandleRecoveryConfig!.messageServiceUrl,
        if (remoteHandleRecoveryConfig != null)
          'mailServiceUrl': remoteHandleRecoveryConfig!.mailServiceUrl,
        if (remoteHandleRecoveryConfig != null)
          'anpServiceUrl': remoteHandleRecoveryConfig!.anpServiceUrl,
        if (remoteHandleRecoveryConfig != null)
          'anpServiceDid': '<redacted-service-did>',
        if (remoteHandleRecoveryConfig != null)
          'didDomain': remoteHandleRecoveryConfig!.didDomain,
        if (remoteMultiDeviceAppPairConfig != null)
          'serviceBaseUrl': remoteMultiDeviceAppPairConfig!.serviceBaseUrl,
        if (remoteMultiDeviceAppPairConfig != null)
          'userServiceUrl': remoteMultiDeviceAppPairConfig!.userServiceUrl,
        if (remoteMultiDeviceAppPairConfig != null)
          'messageServiceUrl':
              remoteMultiDeviceAppPairConfig!.messageServiceUrl,
        if (remoteMultiDeviceAppPairConfig != null)
          'mailServiceUrl': remoteMultiDeviceAppPairConfig!.mailServiceUrl,
        if (remoteMultiDeviceAppPairConfig != null)
          'anpServiceUrl': remoteMultiDeviceAppPairConfig!.anpServiceUrl,
        if (remoteMultiDeviceAppPairConfig != null)
          'anpServiceDid': '<redacted-service-did>',
        if (remoteMultiDeviceAppPairConfig != null)
          'didDomain': remoteMultiDeviceAppPairConfig!.didDomain,
        if (remoteMultiDeviceAppPairConfig != null)
          'appPair': const <String, Object?>{
            'processCount': 2,
            'bundleIsolation': true,
            'buildIsolation': true,
            'stateIsolation': true,
            'coordinator': 'loopback_in_memory',
          },
        'identityPreflight': _identityPreflight,
        'resourceLifecycle': <String, Object?>{
          'cleanupPolicy': suiteDefinition.cleanupPolicy,
          'cleanupStatus': _resourceCleanupStatus,
          'reasonCode': _resourceCleanupReasonCode,
          'ledgerPath': '<redacted-resource-ledger-path>',
        },
        if (_failureCode != null)
          'failure': <String, Object?>{
            'code': _failureCode,
            'summary': _failureSummary ?? 'E2E failed.',
            'scenarioProgress': _readScenarioProgressSummary(),
          },
        if (config != null)
          'daemonRustRepo': config!.daemonRustRepo == null
              ? null
              : '<redacted-daemon-repo>',
        if (config != null)
          'daemonEnvFile': config!.daemonEnvFile == null
              ? null
              : '<redacted-daemon-env-file>',
        if (config != null)
          'personalAgent': <String, Object?>{
            'enabled': config!.personalAgentEnabled,
            'runtimeProvider': config!.personalAgentRuntimeProvider,
            'processingScope': config!.personalAgentProcessingScope,
            'realBackend': config!.personalAgentRealBackend,
            if (config!.e2eCase == DesktopE2eCase.personalAgent) ...{
              'uiEnabled': _caseStatus('PERSONALAGENT-E2E-001') == 'passed',
              'runtimeFinalReceived':
                  _caseStatus('PERSONALAGENT-E2E-002') == 'passed',
              'authorizationRevoked':
                  _caseStatus('PERSONALAGENT-E2E-004') == 'passed',
            },
          },
        if (config != null)
          'codexAgent': <String, Object?>{
            'enabled': config!.codexAgentEnabled,
            'realBackend': config!.codexAgentRealBackend,
            'prompt': '<redacted-deterministic-prompt>',
            'expectedReply':
                config!.codexAgentExpectedReply ??
                _defaultCodexExpectedReply(runId),
          },
        if (config != null)
          'claudeCodeAgent': <String, Object?>{
            'enabled': config!.claudeCodeAgentEnabled,
            'realBackend': config!.claudeCodeAgentRealBackend,
            'prompt': '<redacted-deterministic-prompt>',
            'expectedReply':
                config!.claudeCodeAgentExpectedReply ??
                _defaultClaudeCodeExpectedReply(runId),
          },
        'cliWorkspace': '<redacted-workspace>',
        'cliHome': '<redacted-home>',
        'appStateRoot': '<redacted-app-state>',
        'totalMs': totalElapsed.inMilliseconds,
        if (config?.e2eCase == DesktopE2eCase.performance)
          'dataset':
              productTimingReport?.dataset ??
              config?.performance.dataset.toJson(),
        if (config?.e2eCase == DesktopE2eCase.performance)
          'budgets': config!.performance.budgetsJson(),
        if (productTimingReport != null) 'metrics': productTimingReport.metrics,
        if (productTimingReport != null)
          'counters': productTimingReport.counters,
        if (productTimingReport != null)
          'appProductTimings': productTimingReport.appProductTimings,
        if (config?.e2eCase == DesktopE2eCase.performance)
          'toolingTimings': [
            for (final entry in _timings)
              <String, Object?>{
                'name': entry.name,
                'status': entry.succeeded ? 'success' : 'failed',
                'elapsedMs': entry.elapsed.inMilliseconds,
              },
          ],
        if (performanceBudgetResult != null)
          'hardFailures': performanceBudgetResult.hardFailures,
        if (performanceBudgetResult != null)
          'softWarnings': performanceBudgetResult.softWarnings,
        'steps': [
          for (final entry in _timings)
            <String, Object?>{
              'name': entry.name,
              'status': entry.succeeded ? 'success' : 'failed',
              'elapsedMs': entry.elapsed.inMilliseconds,
            },
        ],
      }),
    );
  }

  String get _resourceCleanupStatus {
    if (options.dryRun) {
      return 'not_applicable_dry_run';
    }
    if (options.prepareOnly || !_resourceSideEffectsPossible) {
      return 'not_needed';
    }
    return suiteDefinition.cleanupPolicy == 'none' ? 'not_needed' : 'residual';
  }

  String get _resourceCleanupReasonCode {
    if (_resourceCleanupStatus != 'residual') {
      return 'none';
    }
    return 'remote_public_delete_api_unavailable';
  }

  void _writeResourceLedger() {
    reportDir.createSync(recursive: true);
    final targetUrl =
        config?.serviceBaseUrl ??
        remoteMultiDeviceJoinConfig?.serviceBaseUrl ??
        remoteHandleRecoveryConfig?.serviceBaseUrl ??
        remoteMultiDeviceAppPairConfig?.serviceBaseUrl;
    final targetHost = targetUrl == null ? null : Uri.tryParse(targetUrl)?.host;
    final sourceRef =
        config?.cliSourceRef ?? remoteMultiDeviceJoinConfig?.cliSourceRef;
    resourceLedgerFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'runId': runId,
        'scenario': options.e2eCase.scenario,
        'suite': options.e2eCase.caseName,
        'namespace': runId,
        'targetHost': targetHost,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
        'cleanupStatus': _resourceCleanupStatus,
        'reasonCode': _resourceCleanupReasonCode,
        'resourceCategories': suiteDefinition.resourceCategories,
        'resourceCounts': <String, Object?>{
          'fixedIdentityPool': config != null
              ? 2
              : remoteMultiDeviceJoinConfig != null
              ? 1
              : remoteHandleRecoveryConfig != null
              ? 2
              : 0,
          'createdIdentities': _resourceSideEffectsPossible ? 'unknown' : 0,
          'messages': _resourceSideEffectsPossible ? 'unknown' : 0,
          'groups': _resourceSideEffectsPossible ? 'unknown' : 0,
          'attachments': _resourceSideEffectsPossible ? 'unknown' : 0,
        },
        'identityPreflightStatus': _identityPreflight['status'],
        'containsRawDids': false,
        'containsSecrets': false,
        'awikiMeSourceRef': _repositorySourceRef(),
        if (sourceRef != null) 'cliSourceRef': sourceRef,
      }),
    );
  }

  ({String code, String summary}) _classifyFailure(E2eFailure error) {
    return classifyDesktopE2eFailureMessage(redactor.redact(error.message));
  }

  void _printTimingSummary({
    required bool orchestrationSucceeded,
    required Duration totalElapsed,
  }) {
    _section('Timing summary');
    _line(
      'status: ${_suiteStatus(orchestrationSucceeded: orchestrationSucceeded)}',
    );
    _line('total: ${_formatDuration(totalElapsed)}');
    for (final entry in _timings) {
      _line(
        '${entry.name}: ${_formatDuration(entry.elapsed)}'
        '${entry.succeeded ? '' : ' (failed)'}',
      );
    }
    _line('timings: ${redactor.redact(_timingsPath)}');
  }

  void _section(String title) {
    _line('');
    _line('== ${redactor.redact(title)} ==');
  }

  void _line(String line) {
    commands.logLine(redactor.redact(line));
  }

  String _repositorySourceRef() {
    final result = Process.runSync(
      'git',
      const <String>['rev-parse', 'HEAD'],
      workingDirectory: root.path,
      runInShell: false,
    );
    final sourceRef = result.stdout.toString().trim().toLowerCase();
    return result.exitCode == 0 && isAuditableGitSha(sourceRef)
        ? sourceRef
        : 'unrecorded';
  }

  void _addRuntimeSecret(String value) {
    redactor.addSecret(value);
    commands.redactor.addSecret(value);
  }
}

class DesktopTimingEntry {
  DesktopTimingEntry({
    required this.name,
    required this.elapsed,
    required this.succeeded,
  });

  final String name;
  final Duration elapsed;
  final bool succeeded;
}
