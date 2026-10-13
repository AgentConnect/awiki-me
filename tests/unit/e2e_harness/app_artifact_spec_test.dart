// [INPUT]: Checked-in App artifact specs and audited E2E suite manifest.
// [OUTPUT]: Complete, product-owned suite-to-artifact closure.
// [POS]: Deterministic contract preventing runner/orchestrator artifact drift.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:awiki_me/src/application/tenant/builtin_tenant_config.dart';

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

  test(
    'isolated artifacts embed the product tenant catalog and exact digest',
    () {
      final selected = E2eAppArtifactSpecManifest.load(
        File('${root.path}/tests/e2e/app_artifact_specs.json'),
        target: 'singapore-test-fix',
      );
      final normal = E2eAppArtifactSpecManifest.load(
        File('${root.path}/tests/e2e/app_artifact_specs.json'),
        target: 'awiki-info-testing',
      );
      for (final spec in selected.specs.values) {
        final values = <String, String>{
          for (final value in spec.dartDefines)
            value.substring(0, value.indexOf('=')): value.substring(
              value.indexOf('=') + 1,
            ),
        };
        final bytes = base64Decode(values[builtinTenantsBase64EnvironmentKey]!);
        expect(
          values[builtinTenantsSha256EnvironmentKey],
          sha256.convert(bytes).toString(),
        );
        expect(
          bytes,
          File(
            '${root.path}/tests/e2e/configs/singapore-test-fix-tenants.json',
          ).readAsBytesSync(),
        );
        final catalog = decodeBuiltinTenantCatalog(utf8.decode(bytes));
        expect(catalog.primary.didHost, 'test-fix.anpclaw.com');
        expect(catalog.secondary.didHost, 'test-fix-b.anpclaw.com');
        expect(
          spec.dartDefines,
          isNot(normal.requireSpec(spec.name).dartDefines),
        );
        expect(
          normal
              .requireSpec(spec.name)
              .dartDefines
              .any((value) => value.startsWith('AWIKI_BUILTIN_TENANTS_')),
          isFalse,
        );
      }
    },
  );

  test(
    'catalog content changes compile definitions and cannot use an external path',
    () {
      final temporary = Directory.systemTemp.createTempSync('app-tenant-spec-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final source = File('${root.path}/tests/e2e/app_artifact_specs.json');
      final payload =
          jsonDecode(source.readAsStringSync()) as Map<String, dynamic>;
      final file = File('${temporary.path}/specs.json');
      final config = File(
        '${temporary.path}/configs/singapore-test-fix-tenants.json',
      );
      config.parent.createSync();
      config.writeAsStringSync('{}');
      file.writeAsStringSync(jsonEncode(payload));
      final first = E2eAppArtifactSpecManifest.load(
        file,
        target: 'singapore-test-fix',
      ).specs.values.first.dartDefines;
      config.writeAsStringSync('{}\n');
      final second = E2eAppArtifactSpecManifest.load(
        file,
        target: 'singapore-test-fix',
      ).specs.values.first.dartDefines;
      expect(second, isNot(first));
      payload['targetTenantCatalogs'] = {'singapore-test-fix': '../other.json'};
      file.writeAsStringSync(jsonEncode(payload));
      expect(
        () =>
            E2eAppArtifactSpecManifest.load(file, target: 'singapore-test-fix'),
        throwsFormatException,
      );
    },
  );

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
