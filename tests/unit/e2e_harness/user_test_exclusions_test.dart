import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/runner.dart';
import '../../e2e/user_test_exclusions.dart';

void main() {
  test('checked-in DID Web exclusion rejects direct execution', () {
    final root = Directory.current;
    final policy = DesktopE2eUserExclusions.load(root);
    policy.validateAgainst(DesktopE2eSuiteManifest.load(root));

    expect(policy.appSuites, {'did-method-web'});
    expect(policy.reason, startsWith('user_excluded:'));
    expect(
      () => policy.requireAllowed('did-method-web'),
      throwsA(isA<E2eFailure>()),
    );
    policy.requireAllowed('multi-device-app-pair');
  });

  test('unknown exclusions fail closed against the audited manifest', () {
    final policy = DesktopE2eUserExclusions(
      decisionDate: '2026-09-24',
      reason: 'user_excluded: synthetic test policy',
      appSuites: {'missing-app-suite'},
    );
    expect(
      () => policy.validateAgainst(
        DesktopE2eSuiteManifest.load(Directory.current),
      ),
      throwsA(isA<E2eFailure>()),
    );
  });
}
