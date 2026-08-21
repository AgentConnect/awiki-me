// [INPUT]: Checked-in App suite manifest plus case, platform, and remote-target contracts.
// [OUTPUT]: Validated suite definitions and report-ready tier/lane policy.
// [POS]: Manifest authority boundary; contains no scenario execution or runtime secrets.

import 'dart:convert';
import 'dart:io';

import '../host_platform.dart';
import 'failure.dart';

const String desktopE2eSuiteManifestPath = 'tests/e2e/suite_manifest.json';

abstract interface class DesktopE2eCaseContract {
  String get caseName;
  List<String> get caseIds;
}

abstract interface class DesktopRemoteTargetContract {
  String get didDomain;
  String get serviceBaseUrl;
  String? get userServiceUrl;
  String? get messageServiceUrl;
  String? get messageServiceWsUrl;
}

class DesktopE2eSuiteManifest {
  DesktopE2eSuiteManifest({
    required this.schemaVersion,
    required this.sourceRevision,
    required this.definitions,
  });

  final int schemaVersion;
  final String sourceRevision;
  final Map<String, DesktopE2eSuiteDefinition> definitions;

  static DesktopE2eSuiteManifest load(Directory root) {
    final scopedFile = File('${root.path}/$desktopE2eSuiteManifestPath');
    final repositoryFile = File(desktopE2eSuiteManifestPath);
    final file = scopedFile.existsSync() ? scopedFile : repositoryFile;
    if (!file.existsSync()) {
      throw E2eFailure('E2E suite manifest was not found.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Object {
      throw E2eFailure('E2E suite manifest is not valid JSON.');
    }
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw E2eFailure('E2E suite manifest must use schemaVersion 1.');
    }
    final sourceRevision = decoded['sourceRevision'];
    final suites = decoded['suites'];
    if (sourceRevision is! String || sourceRevision.trim().isEmpty) {
      throw E2eFailure('E2E suite manifest has no sourceRevision.');
    }
    if (suites is! Map) {
      throw E2eFailure('E2E suite manifest has no suites object.');
    }
    final definitions = <String, DesktopE2eSuiteDefinition>{};
    for (final entry in suites.entries) {
      final name = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) {
        throw E2eFailure('E2E suite "$name" must be an object.');
      }
      definitions[name] = DesktopE2eSuiteDefinition.fromJson(name, raw);
    }
    return DesktopE2eSuiteManifest(
      schemaVersion: 1,
      sourceRevision: sourceRevision.trim(),
      definitions: definitions,
    );
  }

  DesktopE2eSuiteDefinition definitionFor(DesktopE2eCaseContract e2eCase) {
    final definition = definitions[e2eCase.caseName];
    if (definition == null) {
      throw E2eFailure(
        'E2E suite manifest does not define ${e2eCase.caseName}.',
      );
    }
    return definition;
  }
}

class DesktopE2eSuiteDefinition {
  DesktopE2eSuiteDefinition({
    required this.name,
    required this.tier,
    required this.requiredFor,
    required this.owner,
    required this.estimatedMinutes,
    required this.timeout,
    required this.cleanupPolicy,
    required this.allowedHosts,
    required this.allowedDidDomains,
    required this.resourceCategories,
    required this.supportedPlatforms,
    required this.requiredTools,
    required this.caseIds,
  });

  final String name;
  final String tier;
  final List<String> requiredFor;
  final String owner;
  final int estimatedMinutes;
  final Duration timeout;
  final String cleanupPolicy;
  final List<String> allowedHosts;
  final List<String> allowedDidDomains;
  final List<String> resourceCategories;
  final List<String> supportedPlatforms;
  final List<String> requiredTools;
  final List<String> caseIds;

  static DesktopE2eSuiteDefinition fromJson(String name, Map raw) {
    List<String> stringList(String key) {
      final value = raw[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw E2eFailure('E2E suite "$name" has invalid $key.');
      }
      return value.cast<String>();
    }

    final tier = raw['tier'];
    final owner = raw['owner'];
    final estimatedMinutes = raw['estimatedMinutes'];
    final timeoutMinutes = raw['timeoutMinutes'];
    final cleanupPolicy = raw['cleanupPolicy'];
    if (tier is! String || tier.trim().isEmpty) {
      throw E2eFailure('E2E suite "$name" has no tier.');
    }
    final canonicalTier = tier.trim();
    try {
      awikiExecutionLaneForAppTier(canonicalTier);
    } on FormatException catch (error) {
      throw E2eFailure(error.message);
    }
    if (owner is! String || owner.trim().isEmpty) {
      throw E2eFailure('E2E suite "$name" has no owner.');
    }
    if (estimatedMinutes is! int || estimatedMinutes <= 0) {
      throw E2eFailure('E2E suite "$name" has invalid estimatedMinutes.');
    }
    if (timeoutMinutes is! int || timeoutMinutes <= 0) {
      throw E2eFailure('E2E suite "$name" has invalid timeoutMinutes.');
    }
    if (timeoutMinutes < estimatedMinutes) {
      throw E2eFailure(
        'E2E suite "$name" timeoutMinutes must not be less than estimatedMinutes.',
      );
    }
    if (cleanupPolicy is! String || cleanupPolicy.trim().isEmpty) {
      throw E2eFailure('E2E suite "$name" has no cleanupPolicy.');
    }
    final caseIds = stringList('caseIds');
    if (caseIds.isEmpty || caseIds.toSet().length != caseIds.length) {
      throw E2eFailure('E2E suite "$name" has missing or duplicate caseIds.');
    }
    final supportedPlatforms = stringList('supportedPlatforms');
    if (supportedPlatforms.isEmpty ||
        supportedPlatforms.toSet().length != supportedPlatforms.length ||
        supportedPlatforms.any(
          (value) => !awikiSupportedTestPlatforms.contains(value),
        )) {
      throw E2eFailure('E2E suite "$name" has invalid supportedPlatforms.');
    }
    final requiredTools = stringList('requiredTools');
    if (requiredTools.isEmpty ||
        requiredTools.toSet().length != requiredTools.length ||
        requiredTools.any((value) => value.trim().isEmpty)) {
      throw E2eFailure('E2E suite "$name" has invalid requiredTools.');
    }
    return DesktopE2eSuiteDefinition(
      name: name,
      tier: canonicalTier,
      requiredFor: stringList('requiredFor'),
      owner: owner.trim(),
      estimatedMinutes: estimatedMinutes,
      timeout: Duration(minutes: timeoutMinutes),
      cleanupPolicy: cleanupPolicy.trim(),
      allowedHosts: stringList('allowedHosts'),
      allowedDidDomains: stringList('allowedDidDomains'),
      resourceCategories: stringList('resourceCategories'),
      supportedPlatforms: supportedPlatforms,
      requiredTools: requiredTools,
      caseIds: caseIds,
    );
  }

  void validateCodeCaseIds(List<String> codeCaseIds) {
    if (!_sameOrderedStrings(caseIds, codeCaseIds)) {
      throw E2eFailure(
        'E2E suite manifest drift for "$name"; caseIds do not match the Flutter scenario contract.',
      );
    }
  }

  String get executionLane => awikiExecutionLaneForAppTier(tier);

  void validatePlatform(String platform) {
    if (!awikiSupportedTestPlatforms.contains(platform)) {
      throw E2eFailure(
        'E2E suite "$name" received unknown platform $platform.',
      );
    }
    if (!supportedPlatforms.contains(platform)) {
      throw E2eFailure(
        'E2E suite "$name" does not support $platform; supported: '
        '${supportedPlatforms.join(', ')}.',
      );
    }
  }

  void validateRemoteTarget(DesktopRemoteTargetContract config) {
    validateRemoteTargetValues(
      didDomain: config.didDomain,
      serviceUrls: <String>[
        config.serviceBaseUrl,
        config.userServiceUrl ?? config.serviceBaseUrl,
        config.messageServiceUrl ?? config.serviceBaseUrl,
      ],
    );
    if (allowedHosts.isEmpty && allowedDidDomains.isEmpty) {
      return;
    }
    final ws = config.messageServiceWsUrl;
    final wsUri = ws == null ? null : Uri.tryParse(ws);
    if (wsUri == null ||
        wsUri.scheme != 'wss' ||
        !allowedHosts.contains(wsUri.host) ||
        wsUri.path != '/im/ws') {
      throw E2eFailure(
        'E2E suite "$name" requires the audited remote WebSocket endpoint.',
      );
    }
  }

  void validateRemoteTargetValues({
    required String didDomain,
    required List<String> serviceUrls,
  }) {
    if (allowedHosts.isEmpty && allowedDidDomains.isEmpty) {
      return;
    }
    if (!allowedDidDomains.contains(didDomain)) {
      throw E2eFailure(
        'E2E suite "$name" must target an audited remote DID domain.',
      );
    }
    for (final value in serviceUrls) {
      final uri = Uri.tryParse(value);
      if (uri == null || !allowedHosts.contains(uri.host)) {
        throw E2eFailure(
          'E2E suite "$name" must target an audited remote host.',
        );
      }
      if (uri.scheme != 'https') {
        throw E2eFailure(
          'E2E suite "$name" requires secure remote service URLs.',
        );
      }
    }
  }

  Map<String, Object?> toReportJson() => <String, Object?>{
    'tier': tier,
    'executionLane': executionLane,
    'supportedPlatforms': supportedPlatforms,
    'requiredTools': requiredTools,
    'requiredFor': requiredFor,
    'owner': owner,
    'estimatedMinutes': estimatedMinutes,
    'timeoutMinutes': timeout.inMinutes,
    'cleanupPolicy': cleanupPolicy,
    'unexpectedSkipBudget': 0,
  };
}

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
