import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/runner.dart';
import '../../e2e/test_catalog.dart';

void main() {
  final source = Directory.current;
  late Directory root;
  late File config;

  setUp(() {
    root = Directory.systemTemp.createTempSync('awiki-full-contract-');
    for (final name in <String>['tests', 'scripts']) {
      Link('${root.path}/$name').createSync('${source.path}/$name');
    }
    config = File(
      '${root.path}/config.yaml',
    )..writeAsStringSync('platform: ${Platform.isMacOS ? 'macos' : 'linux'}\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  DesktopE2eOptions options(
    String id, {
    bool dryRun = false,
    bool prepareOnly = false,
  }) => DesktopE2eOptions(
    dryRun: dryRun,
    prepareOnly: prepareOnly,
    help: false,
    configPath: config.path,
    runId: id,
    e2eCase: DesktopE2eCase.full,
  );

  Map<String, dynamic> report(String id) =>
      jsonDecode(
            File(
              '${root.path}/.e2e/full/$id/reports/timings.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('full covers every active case once, including native and recovery', () {
    final manifest = DesktopE2eSuiteManifest.load(source);
    final selected = manifest.fullSuites();
    final ids = selected.expand((s) => s.caseIds).toList();
    final active = AppTestCatalog.load(source).cases
        .where((c) => c.catalogStatus == 'active')
        .map((c) => c.caseId)
        .toSet();
    expect(ids.toSet(), active);
    expect(ids.length, active.length);
    expect(
      selected.map((s) => s.name),
      containsAll(<String>[
        'multi-device-app-pair',
        'multi-device-app-pair-functional',
        'handle-recovery-local-data',
        'handle-recovery-state-machine',
        'multi-device-remote-recovery',
        'root-transfer',
        'production-keychain',
        'codex-agent',
        'claude-code-agent',
        'performance',
        'restart',
      ]),
    );
    expect(DesktopE2eCase.messaging.caseIds, hasLength(24));
    expect(
      DesktopE2eOptions.parse(['--case', 'full']).e2eCase,
      DesktopE2eCase.full,
    );
    expect(() => DesktopE2eCase.full.testFile, throwsStateError);
  });

  test(
    'manifest rejects missing coverage, duplicates and nested aggregates',
    () {
      final manifest = DesktopE2eSuiteManifest.load(source);
      final full = manifest.definitions['full']!;
      final first = full.includes.removeAt(0);
      expect(manifest.fullSuites, throwsA(isA<E2eFailure>()));
      full.includes.insert(0, first);
      full.includes.add(first);
      expect(manifest.fullSuites, throwsA(isA<E2eFailure>()));
      full.includes[full.includes.length - 1] = 'full';
      expect(manifest.fullSuites, throwsA(isA<E2eFailure>()));
    },
  );

  test(
    'dry-run plans all active cases without running or claiming passes',
    () async {
      final commands = _LeafCommands(root);
      await runDesktopFull(
        root: root,
        options: options('plan', dryRun: true),
        commands: commands,
        environment: {},
      );
      final result = report('plan');
      expect(commands.suites, isEmpty);
      expect(result['status'], 'dry_run');
      expect(result['passedCaseIds'], isEmpty);
      expect(result['caseResults'], hasLength(114));
      expect(result['catalogNotExecutable'], hasLength(17));
      AppTestCatalog.load(source).validateReport(result);
      await expectLater(
        runDesktopFull(
          root: root,
          options: options('plan', dryRun: true),
          commands: commands,
          environment: {},
        ),
        throwsA(isA<E2eFailure>()),
      );
    },
  );

  test(
    'valid child evidence is required and independent suites continue',
    () async {
      final commands = _LeafCommands(
        root,
        invalidSuite: 'multi-device-app-pair',
      );
      final native = File('${root.path}/native.json')..writeAsStringSync('{}');
      await expectLater(
        runDesktopFull(
          root: root,
          options: options('invalid'),
          commands: commands,
          environment: {productionKeychainManifestEnv: native.path},
        ),
        throwsA(isA<E2eFailure>()),
      );
      final result = report('invalid');
      expect(result['status'], 'failed');
      expect(
        commands.suites,
        containsAll([
          'multi-device-app-pair',
          'root-transfer',
          'claude-code-agent',
        ]),
      );
      final children = result['children'] as List;
      expect(
        children.singleWhere(
          (r) => r['suite'] == 'multi-device-app-pair',
        )['status'],
        'invalid_evidence',
      );
      expect(
        children.singleWhere((r) => r['suite'] == 'root-transfer')['status'],
        'passed',
        reason: children
            .singleWhere((r) => r['suite'] == 'root-transfer')
            .toString(),
      );
      AppTestCatalog.load(source).validateReport(result);
      expect(
        commands.environments.map((e) => e['AWIKI_E2E_APP_HANDLE']).toSet(),
        hasLength(commands.suites.length),
      );
    },
  );

  test(
    'complete child evidence passes; native remains platform scoped',
    () async {
      final commands = _LeafCommands(root);
      final native = File('${root.path}/native.json')..writeAsStringSync('{}');
      await runDesktopFull(
        root: root,
        options: options('success'),
        commands: commands,
        environment: {productionKeychainManifestEnv: native.path},
      );
      final result = report('success');
      expect(result['status'], 'passed');
      expect(result['passedCaseIds'], hasLength(Platform.isMacOS ? 114 : 113));
      AppTestCatalog.load(source).validateReport(result);
      expect(
        (result['children'] as List).singleWhere(
          (r) => r['suite'] == 'production-keychain',
        )['status'],
        Platform.isMacOS ? 'passed' : 'not_applicable',
      );
    },
  );

  test('prepare-only never promotes prepared children to passes', () async {
    final native = File('${root.path}/native.json')..writeAsStringSync('{}');
    await runDesktopFull(
      root: root,
      options: options('prepare', prepareOnly: true),
      commands: _LeafCommands(root),
      environment: {productionKeychainManifestEnv: native.path},
    );
    expect(report('prepare')['status'], 'prepared');
    expect(report('prepare')['passedCaseIds'], isEmpty);
  });

  Future<_LeafCommands> runFixtureEnvironment(String id) async {
    final commands = _LeafCommands(root);
    final native = File('${root.path}/native.json')..writeAsStringSync('{}');
    await runDesktopFull(
      root: root,
      options: options(id),
      commands: commands,
      environment: {productionKeychainManifestEnv: native.path},
    );
    return commands;
  }

  test('full fixture prefix stays within the Recovery handle limit', () async {
    final commands = await runFixtureEnvironment('recovery-prefix');
    for (final suite in <String>[
      'multi-device-remote-recovery',
      'multi-device-app-pair-recovery-registration-rejoin-management-transfer',
      'multi-device-app-pair-recovery-retirement-ordinary-rejoin',
    ]) {
      final environment = commands.environments[commands.suites.indexOf(suite)];
      final prefix = environment['AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX']!;
      final externalHandle = '${prefix}external0123456789';
      expect(
        RegExp(r'^[a-z0-9-]{2,32}$').hasMatch(externalHandle),
        isTrue,
        reason:
            '$suite must leave room for the external fixture suffix and nonce',
      );
    }
  });

  test(
    'full fixture namespace remains authorized for App-pair cleanup',
    () async {
      final commands = await runFixtureEnvironment('cleanup-prefix');
      for (final suite in <String>[
        'multi-device-app-pair-functional',
        'multi-device-app-pair-paging-recovery',
      ]) {
        final environment =
            commands.environments[commands.suites.indexOf(suite)];
        final prefix = environment['AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX']!;
        expect(
          RegExp(r'^appmd[a-z0-9]{10}$').hasMatch('${prefix}0123456789'),
          isTrue,
          reason: '$suite must satisfy the existing User Service cleanup fence',
        );
      }
    },
  );

  test(
    'missing native prerequisite is blocked, not a fabricated pass',
    () async {
      final commands = _LeafCommands(root);
      final run = runDesktopFull(
        root: root,
        options: options('native-missing'),
        commands: commands,
        environment: {},
      );
      if (Platform.isMacOS) {
        await expectLater(run, throwsA(isA<E2eFailure>()));
        expect(report('native-missing')['status'], 'failed');
        expect(commands.suites, isNot(contains('production-keychain')));
      } else {
        await run;
        expect(report('native-missing')['status'], 'passed');
      }
      final row = (report('native-missing')['caseResults'] as List).singleWhere(
        (r) => r['caseId'] == 'NATIVE-E2E-002',
      );
      expect(row['status'], Platform.isMacOS ? 'blocked' : 'not_applicable');
      expect(row['attempt'], 0);
    },
  );

  test(
    'missing child evidence fails even when the command exits zero',
    () async {
      final commands = _LeafCommands(root, missingSuite: 'root-transfer');
      final native = File('${root.path}/native.json')..writeAsStringSync('{}');
      await expectLater(
        runDesktopFull(
          root: root,
          options: options('missing'),
          commands: commands,
          environment: {productionKeychainManifestEnv: native.path},
        ),
        throwsA(isA<E2eFailure>()),
      );
      expect(report('missing')['status'], 'failed');
      expect(commands.suites, contains('claude-code-agent'));
    },
  );
}

// Harness-only command fixture: no App, credentials, or backend is used.
class _LeafCommands extends DesktopCommandRunner {
  _LeafCommands(Directory root, {this.invalidSuite, this.missingSuite})
    : super(
        root: root,
        dryRun: false,
        redactor: DesktopSecretRedactor([]),
        logLine: (_) {},
      );
  final String? invalidSuite;
  final String? missingSuite;
  late final catalog = AppTestCatalog.load(root);
  final suites = <String>[];
  final environments = <Map<String, String>>[];

  @override
  Future<DesktopCommandResult> captureResult(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
    String? stdinText,
  }) async {
    final native = executable == 'bash';
    final suite = native
        ? 'production-keychain'
        : args[args.indexOf('--case') + 1];
    final id = native
        ? args.singleWhere((v) => v.startsWith('--run-id=')).split('=').last
        : args[args.indexOf('--run-id') + 1];
    suites.add(suite);
    environments.add(environment!);
    if (args.contains('--prepare-only') || suite == missingSuite) {
      return const DesktopCommandResult(exitCode: 0, output: '');
    }
    final scope = native
        ? 'production-keychain'
        : DesktopE2eCase.parse(suite).reportScope;
    final dir = Directory('${root.path}/.e2e/$scope/$id/reports')
      ..createSync(recursive: true);
    final definition = DesktopE2eSuiteManifest.load(root).definitions[suite]!;
    final now = DateTime.now().toUtc().toIso8601String();
    final cases = <Map<String, Object?>>[
      for (final caseId in definition.caseIds)
        <String, Object?>{
          'caseId': caseId,
          'status': 'passed',
          'startedAt': now,
          'finishedAt': now,
          'phases': catalog.caseById[caseId]!.assertionContract!.assertionIds
              .map((id) => id.substring(caseId.length + 1))
              .toList(),
          'assertions': [
            for (final id
                in catalog.caseById[caseId]!.assertionContract!.assertionIds)
              {'assertionId': id, 'status': 'passed', 'observedAt': now},
          ],
        },
    ];
    File('${dir.path}/timings.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 2,
        'case': suite,
        'runId': id,
        'status': 'passed',
        'mode': 'real',
        'platform': Platform.isMacOS ? 'macos' : 'linux',
        'dryRun': false,
        'prepareOnly': false,
        'caseIds': definition.caseIds,
        'caseResults': cases,
      }),
    );
    File('${dir.path}/case_attestation.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 2,
        'scenario': native
            ? 'production-keychain'
            : DesktopE2eCase.parse(suite).scenario,
        'runId': suite == invalidSuite ? 'stale-run' : id,
        'mode': 'real',
        'cases': cases,
      }),
    );
    File(
      '${dir.path}/resource_ledger.json',
    ).writeAsStringSync(jsonEncode({'cleanupStatus': 'residual'}));
    return const DesktopCommandResult(exitCode: 0, output: '');
  }
}
