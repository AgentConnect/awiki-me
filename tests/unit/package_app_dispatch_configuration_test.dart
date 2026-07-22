import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('package dispatch separates the controller from source revisions', () {
    final script = File('scripts/package_app.sh').readAsStringSync();
    final workflowSource = File(
      '.github/workflows/package-app.yml',
    ).readAsStringSync();
    final workflow = loadYaml(workflowSource) as YamlMap;

    expect(script, contains(r'gh repo view "$repository"'));
    expect(script, contains('--json defaultBranchRef'));
    expect(script, contains("--jq '.defaultBranchRef.name'"));
    expect(script, contains(r'--ref "$WORKFLOW_REF"'));
    expect(script, contains(r'--branch "$WORKFLOW_REF"'));
    expect(script, contains('--raw-field "app_ref=\$APP_SOURCE_REF"'));
    expect(script, contains('--raw-field "core_ref=\$IM_CORE_SOURCE_REF"'));
    expect(script, isNot(contains(r'--ref "$APP_SOURCE_BRANCH"')));
    expect(script, isNot(contains(r'--branch "$APP_SOURCE_BRANCH"')));
    expect(script, isNot(contains('WORKFLOW_REF="main"')));

    final jobs = workflow['jobs'] as YamlMap;
    final validate = jobs['validate'] as YamlMap;
    final steps = validate['steps'] as YamlList;
    final appCheckout = _stepNamed(steps, 'Checkout exact AWiki Me source');
    final coreCheckout = _stepNamed(
      steps,
      'Checkout exact CLI / IM Core source',
    );
    final anpCheckout = _stepNamed(steps, 'Checkout exact ANP source');
    final verification = _stepNamed(
      steps,
      'Verify source refs and committed version',
    );

    expect((appCheckout['with'] as YamlMap)['ref'], r'${{ inputs.app_ref }}');
    expect((coreCheckout['with'] as YamlMap)['ref'], r'${{ inputs.core_ref }}');
    expect((anpCheckout['with'] as YamlMap)['ref'], r'${{ inputs.anp_ref }}');

    final verificationScript = verification['run'].toString();
    expect(verificationScript, isNot(contains(r'$GITHUB_SHA')));
    expect(verificationScript, contains(r'git -C awiki-me rev-parse HEAD'));
    expect(
      verificationScript,
      contains(r'git -C awiki-cli-rs2 rev-parse HEAD'),
    );
    expect(verificationScript, contains(r'git -C anp/anp rev-parse HEAD'));
  });
}

YamlMap _stepNamed(YamlList steps, String name) {
  return steps.cast<YamlMap>().singleWhere((step) => step['name'] == name);
}
