import 'dart:convert';
import 'dart:io';

const String appSuiteManifestPath = 'tests/e2e/suite_manifest.json';
const String appCaseCatalogPath = 'tests/e2e/case_catalog.json';
const String appCaseCatalogDocumentPath = 'docs/test-case-catalog.md';

class AppTestCatalog {
  AppTestCatalog._({
    required this.sourceRevision,
    required this.cases,
    required this.suitesByCaseId,
    required this.suiteCaseIds,
    required this.caseById,
  });

  final String sourceRevision;
  final List<AppTestCatalogCase> cases;
  final Map<String, List<String>> suitesByCaseId;
  final Map<String, List<String>> suiteCaseIds;
  final Map<String, AppTestCatalogCase> caseById;

  static AppTestCatalog load(Directory root) {
    final manifest = _readJsonObject(
      File('${root.path}/$appSuiteManifestPath'),
      label: 'suite manifest',
    );
    final catalog = _readJsonObject(
      File('${root.path}/$appCaseCatalogPath'),
      label: 'case catalog',
    );
    if (manifest['schemaVersion'] != 1 || catalog['schemaVersion'] != 1) {
      throw const FormatException(
        'suite manifest and case catalog must use schemaVersion 1',
      );
    }
    final suites = _requiredObject(manifest, 'suites', label: 'suite manifest');
    final expectedByCaseId = <String, _ExpectedCase>{};
    final suiteCaseIds = <String, List<String>>{};
    for (final entry in suites.entries) {
      final suiteName = entry.key;
      final suite = _object(entry.value, label: 'suite $suiteName');
      final caseIds = _stringList(suite, 'caseIds', label: 'suite $suiteName');
      if (caseIds.isEmpty || caseIds.toSet().length != caseIds.length) {
        throw FormatException(
          'suite $suiteName has missing or duplicate caseIds',
        );
      }
      suiteCaseIds[suiteName] = caseIds;
      for (final caseId in caseIds) {
        expectedByCaseId
            .putIfAbsent(caseId, _ExpectedCase.new)
            .addSuite(
              suiteName: suiteName,
              tier: _requiredString(suite, 'tier', label: 'suite $suiteName'),
              owner: _requiredString(suite, 'owner', label: 'suite $suiteName'),
              cleanupPolicy: _requiredString(
                suite,
                'cleanupPolicy',
                label: 'suite $suiteName',
              ),
              requiredFor: _stringList(
                suite,
                'requiredFor',
                label: 'suite $suiteName',
              ),
              allowedHosts: _stringList(
                suite,
                'allowedHosts',
                label: 'suite $suiteName',
              ),
            );
      }
    }

    final rawCases = catalog['cases'];
    if (rawCases is! List) {
      throw const FormatException('case catalog cases must be a list');
    }
    final parsed = <AppTestCatalogCase>[];
    final seen = <String>{};
    for (var index = 0; index < rawCases.length; index += 1) {
      final raw = _object(rawCases[index], label: 'catalog cases[$index]');
      final value = AppTestCatalogCase.fromJson(raw, index: index);
      if (!seen.add(value.caseId)) {
        throw FormatException(
          'case catalog contains duplicate ${value.caseId}',
        );
      }
      final expected = expectedByCaseId[value.caseId];
      if (value.catalogStatus == 'active' && expected == null) {
        throw FormatException(
          'case catalog contains unknown caseId ${value.caseId}',
        );
      }
      if (value.catalogStatus == 'planned' && expected != null) {
        throw FormatException(
          'planned case ${value.caseId} must not be declared by an executable suite',
        );
      }
      if (expected != null) {
        value._validateAgainst(expected);
      }
      final implementation = File('${root.path}/${value.implementationPath}');
      if (!implementation.existsSync()) {
        throw FormatException(
          'case ${value.caseId} implementation path does not exist: '
          '${value.implementationPath}',
        );
      }
      final implementationSource = _readDartImplementationBundle(
        implementation,
      );
      if (value.catalogStatus == 'active' &&
          value.evidenceType.contains('case_attestation') &&
          !hasActiveCaseAttestationRegistration(
            implementationSource,
            value.caseId,
          )) {
        throw FormatException(
          'active case ${value.caseId} has no executable markPassed '
          'attestation registration in ${value.implementationPath}',
        );
      }
      parsed.add(value);
    }
    final active = parsed
        .where((value) => value.catalogStatus == 'active')
        .map((value) => value.caseId)
        .toSet();
    final missing = expectedByCaseId.keys.toSet().difference(active).toList()
      ..sort();
    if (missing.isNotEmpty) {
      throw FormatException(
        'case catalog is missing manifest caseIds: ${missing.join(', ')}',
      );
    }
    parsed.sort((first, second) => first.caseId.compareTo(second.caseId));
    return AppTestCatalog._(
      sourceRevision: _requiredString(
        catalog,
        'sourceRevision',
        label: 'case catalog',
      ),
      cases: List<AppTestCatalogCase>.unmodifiable(parsed),
      suitesByCaseId: <String, List<String>>{
        for (final entry in expectedByCaseId.entries)
          entry.key: List<String>.unmodifiable(entry.value.suites..sort()),
      },
      suiteCaseIds: <String, List<String>>{
        for (final entry in suiteCaseIds.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      },
      caseById: Map<String, AppTestCatalogCase>.unmodifiable(
        <String, AppTestCatalogCase>{
          for (final value in parsed) value.caseId: value,
        },
      ),
    );
  }

  void validateReport(Map<String, Object?> report) {
    final suite = report['case'];
    if (suite is! String || !suiteCaseIds.containsKey(suite)) {
      throw FormatException(
        'report case must name an audited suite, got $suite',
      );
    }
    final expected = suiteCaseIds[suite]!;
    final declared = _stringList(report, 'caseIds', label: 'report');
    if (!_sameStrings(declared, expected)) {
      throw FormatException(
        'report caseIds mismatch for $suite: expected $expected, got $declared',
      );
    }
    final rawResults = report['caseResults'];
    if (rawResults is! List) {
      throw const FormatException('report caseResults must be a list');
    }
    final actual = <String>[];
    final seen = <String>{};
    for (var index = 0; index < rawResults.length; index += 1) {
      final row = _object(
        rawResults[index],
        label: 'report caseResults[$index]',
      );
      final caseId = _requiredString(
        row,
        'caseId',
        label: 'report caseResults[$index]',
      );
      if (!seen.add(caseId)) {
        throw FormatException('report contains duplicate caseId $caseId');
      }
      if (!suitesByCaseId.containsKey(caseId)) {
        throw FormatException('report contains unknown caseId $caseId');
      }
      _validateCaseAssertionEvidence(row, caseId: caseId, index: index);
      actual.add(caseId);
    }
    if (!_sameStrings(actual, expected)) {
      throw FormatException(
        'report caseResults mismatch for $suite: expected $expected, got $actual',
      );
    }
  }

  void _validateCaseAssertionEvidence(
    Map<String, Object?> row, {
    required String caseId,
    required int index,
  }) {
    if (row['status'] != 'passed') {
      return;
    }
    final label = 'report caseResults[$index]';
    final phases = _stringList(row, 'phases', label: label);
    if (phases.isEmpty) {
      throw FormatException('$label passed case must contain phases');
    }
    final rawAssertions = row['assertions'];
    if (rawAssertions is! List || rawAssertions.isEmpty) {
      throw FormatException(
        '$label passed case must contain structured assertions',
      );
    }
    final assertionIds = <String>[];
    final seenAssertionIds = <String>{};
    for (
      var assertionIndex = 0;
      assertionIndex < rawAssertions.length;
      assertionIndex += 1
    ) {
      final assertion = _object(
        rawAssertions[assertionIndex],
        label: '$label assertions[$assertionIndex]',
      );
      final assertionId = _requiredString(
        assertion,
        'assertionId',
        label: '$label assertions[$assertionIndex]',
      );
      if (!RegExp(
        '^${RegExp.escape(caseId)}:[a-z0-9_]+\$',
      ).hasMatch(assertionId)) {
        throw FormatException('$label assertionId must use $caseId:snake_case');
      }
      if (!seenAssertionIds.add(assertionId)) {
        throw FormatException(
          '$label contains duplicate assertionId $assertionId',
        );
      }
      if (assertion['status'] != 'passed') {
        throw FormatException('$label assertion $assertionId must be passed');
      }
      _requiredString(
        assertion,
        'observedAt',
        label: '$label assertions[$assertionIndex]',
      );
      assertionIds.add(assertionId);
    }
    final expectedAssertionIds = phases
        .map((phase) => '$caseId:$phase')
        .toList(growable: false);
    if (!_sameStrings(assertionIds, expectedAssertionIds)) {
      throw FormatException(
        '$label assertion IDs must exactly follow phase order',
      );
    }
    final contract = caseById[caseId]?.assertionContract;
    if (contract != null &&
        !_sameStrings(assertionIds, contract.assertionIds)) {
      throw FormatException(
        '$label assertion IDs do not match the catalog assertion contract',
      );
    }
  }

  String renderMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# AWiki Me test case catalog')
      ..writeln()
      ..writeln('> Generated from `$appCaseCatalogPath`; do not edit by hand.')
      ..writeln('> Catalog revision: `$sourceRevision`.')
      ..writeln()
      ..writeln(
        'Every row is reconciled with `$appSuiteManifestPath`. The checker '
        'requires a unique ID, complete ownership/environment/cleanup metadata, '
        'an existing implementation path containing the ID, and exact report IDs.',
      )
      ..writeln()
      ..writeln('## Audited cases')
      ..writeln()
      ..writeln(
        '| Case | Feature and action | Exact oracle | Negative guard | Gate / environment | Implementation |',
      )
      ..writeln('|---|---|---|---|---|---|');
    for (final value in cases) {
      final suites = suitesByCaseId[value.caseId]?.join(', ') ?? 'planned';
      buffer.writeln(
        '| `${value.caseId}` (${value.catalogStatus}) | **${_md(value.feature)}**<br>${_md(value.action)} '
        '| ${_mdList(value.exactOracles)} | ${_mdList(value.negativeChecks)} '
        '| suites: `${_md(suites)}`<br>required: `${_md(value.requiredFor.join(', '))}`'
        '<br>env: `${value.environment}`<br>cleanup: `${value.cleanupPolicy}`'
        '<br>owner: `${value.owner}` '
        '| `${value.implementationPath}`<br>evidence: `${value.evidenceType}` |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Known coverage boundaries')
      ..writeln()
      ..writeln(
        '- `full` means the audited Direct, Group, P9 Mention, Contacts and '
        'Attachment product slices plus one real App-admin/CLI-member Join and '
        '`ROOT-TRANSFER-E2E-001` readiness-completion lifecycle. It does '
        '**not** claim onboarding beyond that isolated lifecycle, '
        'profile editing/search, identity switching, group role/remove/leave, '
        'secure-trust UI, mobile-device, or optional runtime-provider coverage.',
      )
      ..writeln(
        '- `identity-switch` separately covers bidirectional messaging, unread '
        'and canonical timeline hydration across two local App identities. It '
        'does not claim visual acceptance of every account-picker surface.',
      )
      ..writeln(
        '- `performance` is an integration diagnostic because it prepares data '
        'through application services; it is not required UI acceptance.',
      )
      ..writeln(
        '- `multi-device` is currently a no-service device-entry E2E only. '
        'It opens an isolated production AppBootstrap/native Core scope, '
        'checks the default device-management composition, and mounts the Join surface '
        'inside the production provider tree without a backend fixture. '
        'It does not claim OTP, SAS, approval, root import, revoke, MLS, or '
        'Handle Recovery acceptance.',
      )
      ..writeln(
        '- `multi-device-remote-join` is a separate, explicitly activated '
        '`awiki.info` suite for `DEVICE-JOIN-E2E-001/002` only. It runs both '
        'App-new-device/CLI-admin and App-admin/CLI-new-device directions '
        'with independent native roots, protected fixed test OTPs, '
        'SAS comparison, pending-session App restart coverage, the production '
        'CLI foreground contract, fixed member authorization, CLI listener '
        'host wake, App global review entry, and exactly one E2E-only '
        'user-presence decision where the App approves. Production continues '
        'to use macOS LocalAuthentication and is not attested by this suite. '
        'The tests do not directly call Message Inbox '
        'hydration, requestSync(), or refreshJoinInbox() to discover Join. '
        'The same platform-neutral suite requires one minimal App+CLI Direct, '
        'peer realtime receipt, offline/same-root online convergence, visible read, '
        'and idle Core-directed sync case. '
        'It does not execute root transfer, revoke, or MLS; the root lifecycle '
        'is registered by `full`. A checked-in '
        'implementation is not evidence of a remote pass while the protected '
        'test-phone fixture or operator prerequisites are unavailable. The '
        'focused Join suite supports Linux and macOS desktop hosts.',
      )
      ..writeln(
        '- `multi-device-remote-recovery` is the separately activated '
        '`awiki.info` Manifest Handle Recovery V1 UI gate. It uses one fresh '
        'production Core root and a real purpose/operation-bound SMS OTP, '
        'then drives the visible risk confirmation, activation, and bounded '
        'resume controls. Its E2E-only UserPresencePort makes the run '
        'unattended and does not attest production LocalAuthentication. The '
        'suite also exercises a committed-before-Product-reset process crash '
        'and same-root bootstrap barrier. One independently rooted old App '
        'peer is fenced and then ordinarily re-Joins the replacement DID; '
        'the two Apps must converge Registry/session state and bidirectional '
        'Direct exact-one. It proves Handle preservation, DID '
        'replacement, ready-admin Registry projection, stable-account data '
        'preservation, and old epoch/session/Registry cleanup; it does not revive '
        'legacy recovery.begin/finalize protocols.',
      )
      ..writeln(
        '- `multi-device-remote-recovery-fresh` independently runs the six '
        'Fresh Root business-continuity cases after recovery: current Agent '
        'Inventory, visible Runtime messaging, Handle-resolved Direct '
        'inbound, Group membership rebind, Group inbound, and a second '
        'Flutter process over the same recovered root. It uses the same '
        'audited remote target, protected OTP fixture, E2E-only user presence, '
        'and residual ledger as the base Recovery suite, but its result is '
        'not gated by the base suite\'s crash-cut or old-peer re-Join phases.',
      )
      ..writeln(
        '- `multi-device-app-pair` is the one-host/two-process App↔App mode. '
        'It builds two Debug bundles with stable distinct bundle identifiers, '
        'isolated Flutter build directories, and independent native Core '
        'state roots, then concurrently drives their visible Join UI. The '
        'loopback coordinator carries only lifecycle checkpoints and compares '
        'transient SAS values in memory; it cannot call product APIs or write '
        'SAS evidence. This mode covers `DEVICE-JOIN-E2E-004` and then '
        '`DEVICE-JOIN-E2E-005`, which deletes the joined App local data, '
        'proves the completed local Join journal is retired, and reopens a '
        'fresh Join form. Its E2E-only UserPresencePort keeps the '
        'two-process run unattended without attesting production '
        'LocalAuthentication.',
      )
      ..writeln(
        '- `multi-device-app-pair-functional` reuses the same two isolated '
        'App processes but injects an E2E-only `UserPresencePort` so Agent '
        'inventory and Direct-message convergence can run unattended. It '
        'covers one shared Daemon plus Codex/Claude runtime projection, '
        'bidirectional App outbound own-sync, and one required-secure CLI '
        'peer reply on both Apps. It does not attest LocalAuthentication and never '
        'changes the production user-presence implementation.',
      )
      ..writeln(
        '- `DEVICE-JOIN-E2E-003`, `ROOT-TRANSFER-E2E-002`, and '
        '`MLS-MULTI-DEVICE-E2E-001` are planned, non-executable boundaries. '
        '`ROOT-TRANSFER-E2E-001` is active in its dedicated suite; '
        '`DEVICE-REVOKE-E2E-001` and `MLS-MULTI-DEVICE-E2E-002` are active in '
        '`step4-revoke-mls`. '
        'A later version must supply accepted contracts, independent '
        'device roots, real one-time OTPs, user presence where required, '
        'scenario-owned oracles, cleanup, and explicit suite registration. '
        '`ROOT-TRANSFER-E2E-002` is receiver-local completion recovery only; '
        'it cannot restore sender retry, imported ACK/Reply, a second '
        'user-presence prompt, or public original-message-ID semantics. '
        '`001` covers one pending App restart; standalone cancellation and the '
        'real expiration path remain fail-closed rather than adding a test-only '
        'TTL or time bypass.',
      )
      ..writeln(
        '- Personal Agent, Codex and Claude Code remain `optional_nightly`. A '
        'missing provider/configuration is reported as skipped/not-run, never passed.',
      )
      ..writeln(
        '- `PERSONALAGENT-E2E-003` is cataloged as planned, not executable: the '
        'supporting confirmation/draft step does not yet have its own accepted '
        'case attestation. The runnable Personal Agent suite attests enable, '
        'receive/process and exact revoke convergence.',
      )
      ..writeln(
        '- The latest recorded `awiki.info` conversation-correctness evidence '
        'includes a focused inbound-first run and a full Direct/Contacts/Group/'
        'Unread/Ordering/Display-name run, a focused full-Handle fallback run, '
        'plus a release-only two-process cold restart run. The full-Handle run '
        'currently exposes a real App-visible generated-name fallback failure. '
        'The v7 Full hidden/resume burst also exposes a real App-visible '
        'canonical message-order failure in `MSG-SEQUENCE-E2E-001`. '
        'The separate DID-only actor and Runtime Agent entry remain explicit '
        'planned boundaries.',
      )
      ..writeln()
      ..writeln('## Validation')
      ..writeln()
      ..writeln('```bash')
      ..writeln('dart run tool/validate_test_catalog.dart')
      ..writeln(
        'dart run tool/validate_test_catalog.dart --report <suite-report.json>',
      )
      ..writeln('```');
    return buffer.toString();
  }
}

String _readDartImplementationBundle(File implementation) {
  return _readDartImplementationBundleFiles(implementation, <String>{});
}

String _readDartImplementationBundleFiles(
  File implementation,
  Set<String> visited,
) {
  final resolvedImplementation = File(
    implementation.resolveSymbolicLinksSync(),
  );
  final path = resolvedImplementation.path;
  if (!visited.add(path)) {
    return '';
  }
  final source = resolvedImplementation.readAsStringSync();
  if (!resolvedImplementation.path.endsWith('.dart')) {
    return source;
  }
  final buffer = StringBuffer(source);
  final directory = resolvedImplementation.parent;
  final ownerMatch = RegExp(
    r'''^\s*part\s+of\s+['"]([^'"]+)['"]\s*;''',
    multiLine: true,
  ).firstMatch(source);
  if (ownerMatch != null) {
    final owner = File('${directory.path}/${ownerMatch.group(1)!}');
    if (!owner.existsSync()) {
      throw FormatException(
        'Dart implementation owner does not exist: ${owner.path}',
      );
    }
    buffer
      ..writeln()
      ..write(_readDartImplementationBundleFiles(owner, visited));
  }
  final parts = RegExp(
    r'''^\s*part\s+['"]([^'"]+)['"]\s*;''',
    multiLine: true,
  ).allMatches(source);
  for (final match in parts) {
    final part = File('${directory.path}/${match.group(1)!}');
    if (!part.existsSync()) {
      throw FormatException(
        'Dart implementation part does not exist: ${part.path}',
      );
    }
    buffer
      ..writeln()
      ..write(_readDartImplementationBundleFiles(part, visited));
  }
  return buffer.toString();
}

bool hasActiveCaseAttestationRegistration(String source, String caseId) {
  final escapedCaseId = RegExp.escape(caseId);
  final direct = RegExp(
    '''E2eCaseAttestationWriter\\.markPassed\\(\\s*['"]$escapedCaseId['"]\\s*,''',
    multiLine: true,
  );
  if (direct.hasMatch(source)) {
    return true;
  }

  final declaration = RegExp(
    '''(?:const|static\\s+const)\\s+String\\s+([A-Za-z_]\\w*)\\s*=\\s*['"]$escapedCaseId['"]\\s*;''',
    multiLine: true,
  );
  for (final match in declaration.allMatches(source)) {
    final symbol = RegExp.escape(match.group(1)!);
    if (RegExp(
      'E2eCaseAttestationWriter\\.markPassed\\(\\s*$symbol\\s*,',
      multiLine: true,
    ).hasMatch(source)) {
      return true;
    }
    if (RegExp(
          '$symbol\\s*:\\s*(?:const\\s*)?<String>\\s*\\[',
          multiLine: true,
        ).hasMatch(source) &&
        RegExp(
          r'E2eCaseAttestationWriter\.markPassed\(\s*entry\.key\s*,',
          multiLine: true,
        ).hasMatch(source)) {
      return true;
    }
  }

  final registeredPhaseMap = RegExp(
    '''['"]$escapedCaseId['"]\\s*:\\s*(?:const\\s*)?<String>\\s*\\[''',
    multiLine: true,
  );
  final registeredMapAttestation = RegExp(
    r'E2eCaseAttestationWriter\.markPassed\(\s*entry\.key\s*,',
    multiLine: true,
  );
  return registeredPhaseMap.hasMatch(source) &&
      registeredMapAttestation.hasMatch(source);
}

class AppTestCatalogCase {
  AppTestCatalogCase({
    required this.caseId,
    required this.catalogStatus,
    required this.feature,
    required this.layer,
    required this.preconditions,
    required this.action,
    required this.exactOracles,
    required this.negativeChecks,
    required this.environment,
    required this.cleanupPolicy,
    required this.requiredFor,
    required this.owner,
    required this.implementationPath,
    required this.evidenceType,
    required this.assertionContract,
  });

  final String caseId;
  final String catalogStatus;
  final String feature;
  final String layer;
  final String preconditions;
  final String action;
  final List<String> exactOracles;
  final List<String> negativeChecks;
  final String environment;
  final String cleanupPolicy;
  final List<String> requiredFor;
  final String owner;
  final String implementationPath;
  final String evidenceType;
  final AppTestAssertionContract? assertionContract;

  factory AppTestCatalogCase.fromJson(
    Map<String, Object?> json, {
    required int index,
  }) {
    final label = 'catalog cases[$index]';
    final path = _requiredString(json, 'implementationPath', label: label);
    if (path.startsWith('/') ||
        path.startsWith(r'\') ||
        RegExp(r'^[A-Za-z]:[\/]').hasMatch(path) ||
        path.split('/').contains('..')) {
      throw FormatException('$label implementationPath must be repo-relative');
    }
    final requiredFor = _stringList(json, 'requiredFor', label: label)..sort();
    final exactOracles = _stringList(json, 'exactOracles', label: label);
    final negativeChecks = _stringList(json, 'negativeChecks', label: label);
    final catalogStatus = _requiredString(json, 'catalogStatus', label: label);
    if (!const <String>{'active', 'planned'}.contains(catalogStatus)) {
      throw FormatException('$label catalogStatus must be active or planned');
    }
    if (requiredFor.isEmpty || exactOracles.isEmpty || negativeChecks.isEmpty) {
      throw FormatException(
        '$label requiredFor/exactOracles/negativeChecks must be non-empty',
      );
    }
    final assertionContract = AppTestAssertionContract.tryParse(
      json['assertionContract'],
      caseId: _requiredString(json, 'caseId', label: label),
      exactOracleCount: exactOracles.length,
      negativeCheckCount: negativeChecks.length,
      label: label,
    );
    return AppTestCatalogCase(
      caseId: _requiredString(json, 'caseId', label: label),
      catalogStatus: catalogStatus,
      feature: _requiredString(json, 'feature', label: label),
      layer: _requiredString(json, 'layer', label: label),
      preconditions: _requiredString(json, 'preconditions', label: label),
      action: _requiredString(json, 'action', label: label),
      exactOracles: exactOracles,
      negativeChecks: negativeChecks,
      environment: _requiredString(json, 'environment', label: label),
      cleanupPolicy: _requiredString(json, 'cleanupPolicy', label: label),
      requiredFor: requiredFor,
      owner: _requiredString(json, 'owner', label: label),
      implementationPath: path,
      evidenceType: _requiredString(json, 'evidenceType', label: label),
      assertionContract: assertionContract,
    );
  }

  void _validateAgainst(_ExpectedCase expected) {
    final expectedLayer = expected.only(expected.tiers, label: 'tier');
    final expectedCleanup = expected.only(
      expected.cleanupPolicies,
      label: 'cleanup policy',
    );
    final expectedEnvironment = expected.allowedHosts.isEmpty
        ? 'no_service'
        : 'awiki_info_remote';
    if (layer != expectedLayer ||
        cleanupPolicy != expectedCleanup ||
        environment != expectedEnvironment ||
        !_sameStrings(requiredFor, expected.requiredFor.toList()..sort())) {
      throw FormatException(
        'case $caseId metadata drifts from suite manifest: '
        'layer=$layer/$expectedLayer owner=$owner '
        'cleanup=$cleanupPolicy/$expectedCleanup '
        'environment=$environment/$expectedEnvironment '
        'requiredFor=$requiredFor/${expected.requiredFor}',
      );
    }
  }
}

class AppTestAssertionContract {
  const AppTestAssertionContract({
    required this.assertionIds,
    required this.exactOracleAssertions,
    required this.negativeCheckAssertions,
  });

  final List<String> assertionIds;
  final List<List<String>> exactOracleAssertions;
  final List<List<String>> negativeCheckAssertions;

  static AppTestAssertionContract? tryParse(
    Object? raw, {
    required String caseId,
    required int exactOracleCount,
    required int negativeCheckCount,
    required String label,
  }) {
    if (raw == null) {
      return null;
    }
    final map = _object(raw, label: '$label assertionContract');
    final assertionIds = _stringList(
      map,
      'assertionIds',
      label: '$label assertionContract',
    );
    if (assertionIds.isEmpty ||
        assertionIds.toSet().length != assertionIds.length) {
      throw FormatException(
        '$label assertionContract must contain unique assertionIds',
      );
    }
    for (final assertionId in assertionIds) {
      if (!RegExp(
        '^${RegExp.escape(caseId)}:[a-z0-9_]+\$',
      ).hasMatch(assertionId)) {
        throw FormatException(
          '$label assertionContract ID must use $caseId:snake_case',
        );
      }
    }
    final exact = _assertionCoverageLists(
      map,
      'exactOracleAssertions',
      expectedLength: exactOracleCount,
      assertionIds: assertionIds,
      label: '$label assertionContract',
    );
    final negative = _assertionCoverageLists(
      map,
      'negativeCheckAssertions',
      expectedLength: negativeCheckCount,
      assertionIds: assertionIds,
      label: '$label assertionContract',
    );
    final covered = <String>{
      for (final values in exact) ...values,
      for (final values in negative) ...values,
    };
    final unclaimed = assertionIds.toSet().difference(covered);
    if (unclaimed.isNotEmpty) {
      throw FormatException(
        '$label assertionContract contains unclaimed IDs: '
        '${unclaimed.join(', ')}',
      );
    }
    return AppTestAssertionContract(
      assertionIds: List<String>.unmodifiable(assertionIds),
      exactOracleAssertions: List<List<String>>.unmodifiable(exact),
      negativeCheckAssertions: List<List<String>>.unmodifiable(negative),
    );
  }
}

class _ExpectedCase {
  final List<String> suites = <String>[];
  final Set<String> tiers = <String>{};
  final Set<String> owners = <String>{};
  final Set<String> cleanupPolicies = <String>{};
  final Set<String> requiredFor = <String>{};
  final Set<String> allowedHosts = <String>{};

  void addSuite({
    required String suiteName,
    required String tier,
    required String owner,
    required String cleanupPolicy,
    required List<String> requiredFor,
    required List<String> allowedHosts,
  }) {
    suites.add(suiteName);
    tiers.add(tier);
    owners.add(owner);
    cleanupPolicies.add(cleanupPolicy);
    this.requiredFor.addAll(requiredFor);
    this.allowedHosts.addAll(allowedHosts);
  }

  String only(Set<String> values, {required String label}) {
    if (values.length != 1) {
      throw FormatException(
        'one case has conflicting suite $label values: $values',
      );
    }
    return values.single;
  }
}

Map<String, Object?> _readJsonObject(File file, {required String label}) {
  if (!file.existsSync()) {
    throw FormatException('$label is missing: ${file.path}');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on Object catch (error) {
    throw FormatException('$label is invalid JSON: $error');
  }
  return _object(decoded, label: label);
}

Map<String, Object?> _object(Object? value, {required String label}) {
  if (value is! Map) {
    throw FormatException('$label must be an object');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> value,
  String key, {
  required String label,
}) => _object(value[key], label: '$label $key');

String _requiredString(
  Map<String, Object?> value,
  String key, {
  required String label,
}) {
  final raw = value[key];
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('$label $key must be a non-empty string');
  }
  return raw.trim();
}

List<String> _stringList(
  Map<String, Object?> value,
  String key, {
  required String label,
}) {
  final raw = value[key];
  if (raw is! List ||
      raw.any((entry) => entry is! String || entry.trim().isEmpty)) {
    throw FormatException('$label $key must be a string list');
  }
  final values = raw.cast<String>().map((entry) => entry.trim()).toList();
  if (values.toSet().length != values.length) {
    throw FormatException('$label $key contains duplicates');
  }
  return values;
}

List<List<String>> _assertionCoverageLists(
  Map<String, Object?> value,
  String key, {
  required int expectedLength,
  required List<String> assertionIds,
  required String label,
}) {
  final raw = value[key];
  if (raw is! List || raw.length != expectedLength) {
    throw FormatException(
      '$label $key must contain one entry per catalog claim',
    );
  }
  final allowed = assertionIds.toSet();
  final result = <List<String>>[];
  for (var index = 0; index < raw.length; index += 1) {
    final entry = raw[index];
    if (entry is! List ||
        entry.isEmpty ||
        entry.any((value) => value is! String)) {
      throw FormatException('$label $key[$index] must be a string list');
    }
    final values = entry.cast<String>().map((value) => value.trim()).toList();
    if (values.any((value) => value.isEmpty || !allowed.contains(value)) ||
        values.toSet().length != values.length) {
      throw FormatException(
        '$label $key[$index] contains unknown, empty, or duplicate IDs',
      );
    }
    result.add(List<String>.unmodifiable(values));
  }
  return result;
}

bool _sameStrings(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

String _md(String value) => value.replaceAll('|', r'\|').replaceAll('\n', ' ');

String _mdList(List<String> values) =>
    values.map((value) => '• ${_md(value)}').join('<br>');
