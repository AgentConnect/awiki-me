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
    expect(script, isNot(contains('AWIKI_APP_RELEASE_ACTORS')));

    final jobs = workflow['jobs'] as YamlMap;
    final authorize = jobs['authorize'] as YamlMap;
    final validate = jobs['validate'] as YamlMap;
    expect(authorize.containsKey('environment'), isFalse);
    expect(authorize['permissions'], isA<YamlMap>());
    expect((authorize['permissions'] as YamlMap), isEmpty);
    expect(validate['needs'], 'authorize');
    expect(validate['environment'], 'app-packaging');

    final authorizeSteps = authorize['steps'] as YamlList;
    final authorization = _stepNamed(
      authorizeSteps,
      'Require an authorized release actor and stable controller',
    );
    final authorizationEnvironment = authorization['env'] as YamlMap;
    expect(
      authorizationEnvironment['RELEASE_ACTORS'],
      r'${{ vars.AWIKI_APP_RELEASE_ACTORS }}',
    );
    expect(authorizationEnvironment['ACTOR'], r'${{ github.actor }}');
    expect(
      authorizationEnvironment['TRIGGERING_ACTOR'],
      r'${{ github.triggering_actor }}',
    );
    expect(
      authorizationEnvironment['DEFAULT_BRANCH'],
      r'${{ github.event.repository.default_branch }}',
    );
    expect(
      authorizationEnvironment['WORKFLOW_REF'],
      r'${{ github.workflow_ref }}',
    );
    final authorizationScript = authorization['run'].toString();
    expect(authorizationScript, contains('json.loads'));
    expect(authorizationScript, contains('ACTOR'));
    expect(authorizationScript, contains('TRIGGERING_ACTOR'));
    expect(
      authorizationScript,
      contains('package workflow controller must run from the default branch'),
    );
    expect(
      authorizationScript,
      contains('package workflow file does not come from the default branch'),
    );

    const expectedPrivilegedJobCondition = r'''
${{
  github.event_name == 'workflow_dispatch' &&
  github.ref == format('refs/heads/{0}', github.event.repository.default_branch) &&
  endsWith(github.workflow_ref, format('@refs/heads/{0}', github.event.repository.default_branch)) &&
  contains(fromJSON(vars.AWIKI_APP_RELEASE_ACTORS), github.actor) &&
  contains(fromJSON(vars.AWIKI_APP_RELEASE_ACTORS), github.triggering_actor)
}}
''';
    for (final jobName in <String>['validate', 'build', 'aggregate']) {
      final condition = (jobs[jobName] as YamlMap)['if'].toString();
      expect(
        _normalizeWhitespace(condition),
        _normalizeWhitespace(expectedPrivilegedJobCondition),
        reason: '$jobName must independently authorize every run attempt',
      );
    }

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

    for (final job in jobs.values.cast<YamlMap>()) {
      final jobSteps = job['steps'];
      if (jobSteps is! YamlList) continue;
      for (final step in jobSteps.cast<YamlMap>()) {
        final action = step['uses']?.toString() ?? '';
        if (!action.startsWith('actions/checkout@')) continue;
        expect(
          (step['with'] as YamlMap)['persist-credentials'],
          isFalse,
          reason: step['name'].toString(),
        );
      }
    }
  });

  test('release authorization fails closed for actors and controller refs', () {
    expect(_runAuthorization().exitCode, 0);

    final unauthorizedActor = _runAuthorization(actor: 'untrusted-user');
    expect(unauthorizedActor.exitCode, isNot(0));
    expect(unauthorizedActor.stderr, contains('ACTOR is not authorized'));

    final unauthorizedRerun = _runAuthorization(
      triggeringActor: 'untrusted-user',
    );
    expect(unauthorizedRerun.exitCode, isNot(0));
    expect(
      unauthorizedRerun.stderr,
      contains('TRIGGERING_ACTOR is not authorized'),
    );

    final malformedAllowlist = _runAuthorization(releaseActors: '{bad-json');
    expect(malformedAllowlist.exitCode, isNot(0));
    expect(malformedAllowlist.stderr, contains('must be a JSON array'));

    final wrongControlBranch = _runAuthorization(controlBranch: 'feature/x');
    expect(wrongControlBranch.exitCode, isNot(0));
    expect(
      wrongControlBranch.stderr,
      contains('controller must run from the default branch'),
    );

    final wrongWorkflowRef = _runAuthorization(
      workflowRef:
          'AgentConnect/awiki-me/.github/workflows/package-app.yml@refs/heads/feature/x',
    );
    expect(wrongWorkflowRef.exitCode, isNot(0));
    expect(
      wrongWorkflowRef.stderr,
      contains('workflow file does not come from the default branch'),
    );
  });
}

YamlMap _stepNamed(YamlList steps, String name) {
  return steps.cast<YamlMap>().singleWhere((step) => step['name'] == name);
}

ProcessResult _runAuthorization({
  String releaseActors = '["smartGrey"]',
  String actor = 'smartGrey',
  String triggeringActor = 'SMARTGREY',
  String controlBranch = 'main',
  String workflowRef =
      'AgentConnect/awiki-me/.github/workflows/package-app.yml@refs/heads/main',
}) {
  final workflow =
      loadYaml(File('.github/workflows/package-app.yml').readAsStringSync())
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;
  final authorize = jobs['authorize'] as YamlMap;
  final authorization = _stepNamed(
    authorize['steps'] as YamlList,
    'Require an authorized release actor and stable controller',
  );
  final script = authorization['run'].toString();
  return Process.runSync(
    'bash',
    <String>['-c', script],
    environment: <String, String>{
      'RELEASE_ACTORS': releaseActors,
      'ACTOR': actor,
      'TRIGGERING_ACTOR': triggeringActor,
      'EVENT_NAME': 'workflow_dispatch',
      'CONTROL_REF_TYPE': 'branch',
      'CONTROL_BRANCH': controlBranch,
      'CONTROL_REF': 'refs/heads/$controlBranch',
      'WORKFLOW_REF': workflowRef,
      'DEFAULT_BRANCH': 'main',
    },
  );
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
