import 'dart:convert';
import 'dart:io';

import 'runner/failure.dart';
import 'runner/manifest.dart';

const String desktopE2eUserExclusionsPath =
    'tests/e2e/user_test_exclusions.json';

/// User-directed suite exclusions applied before E2E setup or artifact use.
class DesktopE2eUserExclusions {
  DesktopE2eUserExclusions({
    required this.decisionDate,
    required this.reason,
    required this.appSuites,
  });

  final String decisionDate;
  final String reason;
  final Set<String> appSuites;

  static DesktopE2eUserExclusions load(Directory root) {
    final file = File('${root.path}/$desktopE2eUserExclusionsPath');
    if (!file.existsSync()) {
      throw E2eFailure('E2E user exclusion policy is missing.');
    }
    Object? raw;
    try {
      raw = jsonDecode(file.readAsStringSync());
    } on Object {
      throw E2eFailure('E2E user exclusion policy is invalid JSON.');
    }
    if (raw is! Map || raw['schemaVersion'] != 1) {
      throw E2eFailure('E2E user exclusion policy must use schemaVersion 1.');
    }
    final decisionDate = raw['decisionDate'];
    final reason = raw['reason'];
    final suites = raw['appSuites'];
    if (decisionDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(decisionDate) ||
        reason is! String ||
        !reason.startsWith('user_excluded:') ||
        suites is! List ||
        suites.any((suite) => suite is! String || suite.trim().isEmpty) ||
        suites.toSet().length != suites.length) {
      throw E2eFailure('E2E user exclusion policy has invalid fields.');
    }
    return DesktopE2eUserExclusions(
      decisionDate: decisionDate,
      reason: reason,
      appSuites: suites.cast<String>().toSet(),
    );
  }

  void validateAgainst(DesktopE2eSuiteManifest manifest) {
    for (final name in appSuites) {
      final suite = manifest.definitions[name];
      if (suite == null ||
          suite.includes.isNotEmpty ||
          suite.catalogStatus != 'active') {
        throw E2eFailure('E2E user exclusion names an unknown active leaf.');
      }
    }
  }

  bool excludes(String suite) => appSuites.contains(suite);

  void requireAllowed(String suite) {
    if (excludes(suite)) {
      throw E2eFailure(
        '$suite is user_excluded by $desktopE2eUserExclusionsPath; '
        'restore it only after explicit user direction.',
      );
    }
  }
}
