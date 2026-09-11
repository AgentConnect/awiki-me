// [INPUT]: Checked-in App artifact specs and audited E2E suite manifest.
// [OUTPUT]: Complete, product-owned suite-to-artifact closure.
// [POS]: Deterministic contract preventing runner/orchestrator artifact drift.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/app_artifact_spec.dart';

void main() {
  final root = Directory.current;
  final specs = E2eAppArtifactSpecManifest.load(
    File('${root.path}/tests/e2e/app_artifact_specs.json'),
  );
  final suitePayload =
      jsonDecode(
            File(
              '${root.path}/tests/e2e/suite_manifest.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final suites = (suitePayload['suites'] as Map).cast<String, dynamic>();

  test('all non-native executable suites have an artifact closure', () {
    final consumers = <String>{
      for (final spec in specs.specs.values) ...spec.consumerSuites,
    };
    final executableSuites = suites.entries
        .where(
          (entry) =>
              entry.value['tier'] != 'native_release_security' &&
              entry.value['includes'] == null &&
              entry.value['catalogStatus'] != 'unsupported',
        )
        .map((entry) => entry.key)
        .toSet();

    expect(consumers.difference(suites.keys.toSet()), isEmpty);
    expect(executableSuites.difference(consumers), isEmpty);
    for (final spec in specs.specs.values) {
      expect(File('${root.path}/${spec.target}').existsSync(), isTrue);
    }
  });

  test('shared suite families use the intended minimal artifact set', () {
    Set<String> names(String suite) => specs
        .specsForSuite(suite, platform: 'linux')
        .map((spec) => spec.name)
        .toSet();

    const pair = <String>{'admin', 'joiner'};
    for (final suite in const <String>[
      'multi-device-app-pair',
      'multi-device-app-pair-functional',
      'multi-device-app-pair-content-sync',
      'multi-device-app-pair-paging-recovery',
    ]) {
      expect(names(suite), pair);
    }
    for (final suite in const <String>[
      'multi-device-remote-join',
      'root-transfer',
      'step4-revoke-mls',
    ]) {
      expect(names(suite), const <String>{'remote-join'});
    }
    expect(
      specs.requireSpec('personal-agent').target,
      'integration_test/personal_agent_real_backend_test.dart',
    );
  });

  test('compile-time defines are canonical and runtime fixtures stay out', () {
    for (final spec in specs.specs.values) {
      expect(
        spec.dartDefines,
        canonicalCompileTimeDartDefines(spec.dartDefines),
      );
      expect(spec.dartDefines.join(','), isNot(contains('messages_501')));
      expect(spec.dartDefines.join(','), isNot(contains('OTP')));
      expect(spec.dartDefines.join(','), isNot(contains('RUN_ID')));
    }
  });

  test('prepared Flutter targets report the binding failure count', () {
    final implementations = Directory('${root.path}/tests/e2e/flutter')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    var producers = 0;
    for (final file in implementations) {
      final source = file.readAsStringSync();
      if (!source.contains('E2eInvocationCompletionWriter.markFinished')) {
        continue;
      }
      producers++;
      expect(
        source,
        isNot(
          contains('tearDownAll(E2eInvocationCompletionWriter.markFinished)'),
        ),
        reason: file.path,
      );
      expect(
        source,
        contains('failedTestCount: binding.failureMethodsDetails.length'),
        reason: file.path,
      );
    }
    expect(producers, greaterThan(0));
  });

  test('Personal real-backend target always publishes process completion', () {
    final source = File(
      '${root.path}/tests/e2e/flutter/app/personal_agent_full_ui_test.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('failedTestCount: binding.failureMethodsDetails.length'),
    );
  });
}
