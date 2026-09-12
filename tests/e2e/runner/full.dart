// [INPUT]: Audited aggregate membership, host/config, and existing leaf runners.
// [OUTPUT]: Incremental full report with exact case coverage and child evidence.
// [POS]: E2E orchestration; business assertions remain in owning leaf suites.

part of '../runner.dart';

const String productionKeychainManifestEnv =
    'AWIKI_E2E_PRODUCTION_KEYCHAIN_MANIFEST';

Future<void> runDesktopFull({
  required Directory root,
  required DesktopE2eOptions options,
  required DesktopCommandRunner commands,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final manifest = DesktopE2eSuiteManifest.load(root);
  final suites = manifest.fullSuites();
  manifest
      .definitionFor(DesktopE2eCase.full)
      .validateCodeCaseIds(DesktopE2eCase.full.caseIds);
  final catalog = AppTestCatalog.load(root);
  final config = DesktopE2eFileConfig.load(
    root: root,
    path: options.configPath,
    environment: env,
  );
  for (final secret in <String>[
    config.path ?? '',
    config.otpPhone ?? '',
    config.otpCode ?? '',
  ]) {
    commands.redactor.addSecret(secret);
  }
  final platform = config.platform ?? DesktopE2ePlatform.fromHost();
  if (!options.dryRun) {
    (await E2eHostPlatform.detect()).requireOperatingSystem(platform.name);
  }
  final runId = options.runId ?? _newRunId();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,95}$').hasMatch(runId)) {
    throw E2eFailure(
      'full run ID must be a safe name of at most 96 characters.',
    );
  }
  final reportDir = Directory('${root.path}/.e2e/full/$runId/reports');
  if (reportDir.existsSync()) {
    throw E2eFailure('full run ID already exists; choose a new run ID.');
  }
  reportDir.createSync(recursive: true);
  final timer = Stopwatch()..start();
  final startedAt = DateTime.now().toUtc().toIso8601String();
  final rows = <String, Map<String, Object?>>{
    for (final id in DesktopE2eCase.full.caseIds)
      id: <String, Object?>{
        'caseId': id,
        'suite': suites.singleWhere((suite) => suite.caseIds.contains(id)).name,
        'status': 'not_run',
        'attempt': 0,
        'platform': platform.name,
      },
  };
  final children = <Map<String, Object?>>[];
  var failed = false;
  void writeReport(String status) {
    final report = <String, Object?>{
      'schemaVersion': 2,
      'sourceRevision': manifest.sourceRevision,
      'case': 'full',
      'runId': runId,
      'status': status,
      'mode': options.dryRun ? 'dry-run' : 'real',
      'dryRun': options.dryRun,
      'prepareOnly': options.prepareOnly,
      'platform': platform.name,
      'startedAt': startedAt,
      'totalMs': timer.elapsedMilliseconds,
      'caseIds': rows.keys.toList(),
      'caseResults': rows.values.toList(),
      'passedCaseIds': rows.values
          .where((r) => r['status'] == 'passed')
          .map((r) => r['caseId'])
          .toList(),
      'children': children,
      'catalogNotExecutable': <Map<String, String>>[
        for (final item in catalog.cases)
          if (item.catalogStatus != 'active')
            <String, String>{
              'caseId': item.caseId,
              'status': item.catalogStatus,
            },
      ],
      'resourceLifecycle': <String, Object?>{
        'cleanupPolicy': 'child_suite_ledgers',
        'cleanupStatus': 'see_child_ledgers',
      },
    };
    final temporary = File('${reportDir.path}/timings.json.tmp');
    temporary.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    temporary.renameSync('${reportDir.path}/timings.json');
  }

  writeReport('running');
  for (var index = 0; index < suites.length; index++) {
    final suite = suites[index];
    final childId = '$runId-${(index + 1).toString().padLeft(2, '0')}';
    final native = suite.name == 'production-keychain';
    final childCase = native ? null : DesktopE2eCase.parse(suite.name);
    final scope = native ? 'production-keychain' : childCase!.reportScope;
    final childReports = Directory('${root.path}/.e2e/$scope/$childId/reports');
    final child = <String, Object?>{
      'suite': suite.name,
      'runId': childId,
      'status': 'not_run',
      'reportPath': '.e2e/$scope/$childId/reports/timings.json',
      'cleanupStatus': 'unknown',
    };
    children.add(child);
    commands.logLine('full [${index + 1}/${suites.length}] ${suite.name}');
    if (!suite.supportedPlatforms.contains(platform.name)) {
      child['status'] = 'not_applicable';
      for (final id in suite.caseIds) {
        rows[id]!['status'] = 'not_applicable';
        rows[id]!['reasonCode'] = 'unsupported_host_platform';
      }
      writeReport('running');
      continue;
    }
    final nativeManifest = env[productionKeychainManifestEnv];
    final args = native
        ? <String>[
            'scripts/run_macos_production_scope_restart_gate.sh',
            '--execute',
            '--artifact-manifest=${nativeManifest ?? '<prepared-native-manifest>'}',
            '--report-dir=${childReports.path}',
            '--run-id=$childId',
          ]
        : <String>[
            'run',
            'tests/e2e/runner.dart',
            '--case',
            suite.name,
            '--config',
            options.configPath,
            '--run-id',
            childId,
            if (options.prepareOnly) '--prepare-only',
          ];
    child['command'] = commands.redactor.redact(
      '${native ? 'bash' : 'dart'} ${args.join(' ')}',
    );
    if (options.dryRun) {
      child['status'] = 'dry_run';
      commands.logLine(child['command'] as String);
      for (final id in suite.caseIds) {
        rows[id]!['status'] = 'dry_run';
      }
      writeReport('running');
      continue;
    }
    final childTimer = Stopwatch()..start();
    Object? failure;
    var childStarted = false;
    try {
      if (childReports.existsSync()) {
        throw E2eFailure('Child report directory already exists.');
      }
      if (native &&
          (nativeManifest == null || !File(nativeManifest).existsSync())) {
        throw E2eFailure(
          'production-keychain requires $productionKeychainManifestEnv; '
          'full never implicitly builds a universal Release artifact.',
        );
      }
      if (native && options.prepareOnly) {
        child['status'] = 'prepared';
      } else {
        final digest = sha256
            .convert(utf8.encode(childId))
            .toString()
            .substring(0, 12);
        commands.diagnosticDirectory = Directory(
          '${reportDir.path}/diagnostics/${suite.name}',
        );
        childStarted = true;
        for (final id in suite.caseIds) {
          rows[id]!['attempt'] = 1;
        }
        final result = await commands.captureResult(
          native ? 'bash' : Platform.resolvedExecutable,
          args,
          environment: <String, String>{
            ...env,
            _e2eAppHandleEnv: 'e2ea$digest',
            _e2eSecondaryAppHandleEnv: 'e2eb$digest',
            _e2eCliHandleEnv: 'e2ec$digest',
            _multiDeviceRemoteHandlePrefixEnv: appPairCleanupHandlePrefix,
            _e2eDaemonStateRootEnv:
                '${Directory.systemTemp.path}/aw-full-$digest',
            _e2eDaemonReadyFileEnv:
                '${Directory.systemTemp.path}/aw-full-$digest/ready.json',
          },
          includeParentEnvironment: false,
          timeout: suite.timeout + const Duration(minutes: 10),
        );
        child['exitCode'] = result.exitCode;
        child['status'] = options.prepareOnly ? 'prepared' : 'finished';
      }
    } on Object catch (error) {
      failure = error;
      failed = true;
      child['status'] = error is DesktopCommandTimeout ? 'timeout' : 'error';
      child['failureSummary'] = error is DesktopCommandTimeout
          ? error.safeSummary
          : childStarted
          ? 'Child command failed; see redacted child diagnostics.'
          : commands.redactor.redact(error.toString());
    }
    child['elapsedMs'] = childTimer.elapsedMilliseconds;
    if (options.prepareOnly && failure == null) {
      for (final id in suite.caseIds) {
        rows[id]!['status'] = 'prepared';
      }
    } else {
      try {
        if (!childStarted) throw E2eFailure('Child was not started.');
        final decoded = jsonDecode(
          File('${childReports.path}/timings.json').readAsStringSync(),
        );
        final report = Map<String, Object?>.from(decoded as Map);
        if (report['runId'] != childId ||
            report['case'] != suite.name ||
            report['platform'] != platform.name ||
            report['mode'] != 'real' ||
            report['dryRun'] != false ||
            report['prepareOnly'] != false) {
          throw E2eFailure('Child report invocation does not match full.');
        }
        catalog.validateReport(report);
        if (report['status'] == 'passed') {
          final validation = E2eCaseAttestationValidation.validate(
            attestation: E2eCaseAttestation.read(
              File('${childReports.path}/case_attestation.json'),
            ),
            expectedScenario: native
                ? 'production-keychain'
                : childCase!.scenario,
            expectedRunId: childId,
            expectedCaseIds: suite.caseIds,
          );
          if (!validation.passed ||
              (report['caseResults'] as List).any(
                (r) => (r as Map)['status'] != 'passed',
              )) {
            throw E2eFailure('Child pass lacks complete valid attestation.');
          }
        }
        for (final value in report['caseResults'] as List) {
          final row = Map<String, Object?>.from(value as Map);
          rows[row['caseId'] as String] = <String, Object?>{
            ...row,
            'suite': suite.name,
            'attempt': 1,
            'platform': platform.name,
          };
        }
        child['status'] = failure == null ? report['status'] : child['status'];
        child['awikiMeSourceRef'] = report['awikiMeSourceRef'];
        child['cliSourceRef'] = report['cliSourceRef'];
        final ledger = File('${childReports.path}/resource_ledger.json');
        if (ledger.existsSync()) {
          final resource = jsonDecode(ledger.readAsStringSync()) as Map;
          child['cleanupStatus'] = resource['cleanupStatus'] ?? 'unknown';
          child['resourceLedgerPath'] =
              '.e2e/$scope/$childId/reports/resource_ledger.json';
        }
        if (child['status'] != 'passed') failed = true;
      } on Object catch (error) {
        child['evidenceError'] = commands.redactor.redact(error.toString());
        failed = true;
        child['status'] = failure == null
            ? 'invalid_evidence'
            : child['status'];
        child['reasonCode'] = 'missing_or_invalid_child_evidence';
        for (final id in suite.caseIds) {
          rows[id]!['status'] = 'blocked';
          rows[id]!['reasonCode'] = 'missing_or_invalid_child_evidence';
        }
      }
    }
    writeReport('running');
  }
  timer.stop();
  final status = failed
      ? 'failed'
      : options.dryRun
      ? 'dry_run'
      : options.prepareOnly
      ? 'prepared'
      : 'passed';
  writeReport(status);
  commands.logLine(
    'full: $status; ${rows.length} audited cases; '
    '${rows.values.where((r) => r['status'] == 'passed').length} passed.',
  );
  if (failed) {
    throw E2eFailure(
      'full has failed or blocked suites; see aggregate timings.json.',
    );
  }
}
